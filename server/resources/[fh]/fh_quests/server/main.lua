-- fh_quests server core (Q2): per-character state cache + lock, fh_quest_state persistence, reward payout I/O,
-- fh:quests:* emission and fh:quests:sync. Thin: every decision is in shared/ (engine, intake, rewards, store,
-- journal, board, jobs); this file only does I/O. server/api.lua holds the exports and the intake handlers.
local E, I, R, S, J, B, Jobs = FhQuestsEngine, FhQuestsIntake, FhQuestsRewards, FhQuestsStore, FhQuestsJournal,
    FhQuestsBoard, FhQuestsJobs

local Q = {
    ready = false,      -- fh_quest_state exists (migration applied)
    defs = {},          -- quest_id -> def (registerQuest)
    jobTypes = {},      -- name -> { hooks, owner, events = { [name] = true } }
    jobEvents = {},     -- event name -> true while some registered job type lists it
    cache = {},         -- citizenid -> { [quest_id] = state }
    srcOf = {},         -- citizenid -> player server id (online characters)
    boards = {},        -- region_id -> { epoch, offers }
    viewing = {},       -- src -> region_id of the board last asked for (included in sync)
    ROTATE_MIN = B.DEFAULTS.rotate_min,
}
FhQuestsServer = Q

function Q.log(fmt, ...) print(('[fh_quests] ' .. fmt):format(...)) end

local function core() return exports['rsg-core']:GetCoreObject() end

---src -> citizenid of the loaded character, or nil.
function Q.citizenidOf(src)
    if type(src) ~= 'number' or src < 1 then return nil end
    local ok, p = pcall(function() return core().Functions.GetPlayer(src) end)
    return ok and p and p.PlayerData and p.PlayerData.citizenid or nil
end

-- ---------------------------------------------------------------- per-character lock
-- Quest state for one character is read, changed and persisted under this lock, so two events can never both see
-- the same 'active' state (which is what keeps "reward exactly once" true across concurrent handlers). Re-entrant
-- for the holding coroutine. A waiter gives up after `timeoutMs` (fh_busy) instead of hanging forever.
local busy = {}

function Q.locked(cid, timeoutMs, fn, ...)
    local co = coroutine.running()
    if busy[cid] == co then return fn(...) end
    local deadline = GetGameTimer() + (timeoutMs or 5000)
    while busy[cid] do
        if GetGameTimer() > deadline then return false, 'fh_busy' end
        Wait(0)
    end
    busy[cid] = co
    local res = table.pack(pcall(fn, ...))
    busy[cid] = nil
    if not res[1] then
        Q.log('^1error for %s: %s^7', cid, tostring(res[2]))
        return false, 'fh_internal'
    end
    return table.unpack(res, 2, res.n)
end

-- ---------------------------------------------------------------- defs
local jobDefMemo = setmetatable({}, { __mode = 'k' }) -- progress.job snapshot table -> def

function Q.eventSet()
    local set = {}
    for _, name in ipairs(E.INTAKE) do set[name] = true end
    for name in pairs(Q.jobEvents) do set[name] = true end
    return set
end

---The def a state belongs to: a registered quest, or a job rebuilt from its stored offer snapshot.
function Q.defOf(qid, state)
    if Q.defs[qid] then return Q.defs[qid] end
    local snap = state and state.progress and state.progress.job
    if type(snap) ~= 'table' then return nil end
    local memo = jobDefMemo[snap]
    if memo ~= nil then return memo or nil end
    local def, err = Jobs.def(snap, { regions = FhRegions.regions, events = Q.eventSet() })
    if not def then Q.log('job row %s unusable: %s', qid, tostring(err)) end
    jobDefMemo[snap] = def or false
    return def
end

---Forget rebuilt job defs (the job event set changed: a def refused earlier may now validate).
function Q.resetJobDefs() jobDefMemo = setmetatable({}, { __mode = 'k' }) end

function Q.defsFor(states)
    local defs = {}
    for qid, st in pairs(states) do defs[qid] = Q.defOf(qid, st) end
    return defs
end

---Route for intake.feed: nil = engine matches, hook = job type decides, false = job type not registered (paused).
function Q.hookFor(def)
    if not def.job_type then return nil end
    local jt = Q.jobTypes[def.job_type]
    if not jt then return false end
    return jt.hooks.onEvent or nil
end

-- ---------------------------------------------------------------- persistence
---Load (or return cached) states for a character. Call under Q.locked.
---@return table|nil states, string|nil err
function Q.load(cid)
    if Q.cache[cid] then return Q.cache[cid] end
    local ok, rows = pcall(MySQL.query.await, S.SELECT, { cid })
    if not ok or type(rows) ~= 'table' then
        Q.log('^1load failed for %s: %s^7', cid, tostring(rows))
        return nil, 'fh_db'
    end
    local states = {}
    for _, row in ipairs(rows) do
        local st, err = S.fromRow(row, json.decode)
        if st then states[st.quest_id] = st else Q.log('skipping row %s/%s: %s', cid, tostring(row.quest_id), err) end
    end
    Q.cache[cid] = states
    return states
end

---Persist one state (UPSERT). Only a successful write updates the cache.
function Q.save(state)
    local ok, res = pcall(MySQL.update.await, S.UPSERT, S.params(state, json.encode))
    if not ok or type(res) ~= 'number' then
        Q.log('^1save failed for %s/%s: %s^7', state.citizenid, state.quest_id, tostring(res))
        return false
    end
    local states = Q.cache[state.citizenid]
    if states then states[state.quest_id] = state end
    return true
end

-- ---------------------------------------------------------------- rewards
local function online(cid)
    local src = Q.srcOf[cid]
    if src and Q.citizenidOf(src) == cid then return src end
    return nil
end

local function callExport(res, fn, ...)
    if GetResourceState(res) ~= 'started' then return true, false, res .. '_down' end -- not called: plain refusal
    local args = table.pack(...)
    local called, ok, err = pcall(function() return exports[res][fn](exports[res], table.unpack(args, 1, args.n)) end)
    if not called then return false, nil, tostring(ok) end -- threw: outcome unknown, rewards.run decides
    return true, ok == true, err
end

---Pay what a done state still owes (rewards.run protocol). Call under Q.locked. Offline = refused, retried on load.
function Q.payout(cid, def)
    local state = (Q.cache[cid] or {})[def.id]
    if not R.pending(state) then return end
    local reason = R.reason(def)
    local io = {
        now = os.time(),
        save = Q.save,
        pay = function(part)
            local src = online(cid)
            if not src then return true, false, 'fh_no_player' end
            if part.kind == 'pay' then
                return callExport('fh_economy', 'pay', src, part.amount, reason, part.region_id)
            elseif part.kind == 'rep' then
                return callExport('fh_economy', 'rep', src, part.region_id, part.delta, reason)
            end
            -- items: the player's inventory ref through fh_core (README "Rewards")
            return callExport('fh_core', 'addItem', { type = 'backpack', id = src }, part.name, part.amount, part.info)
        end,
        ledger = function(part, inflight)
            local sql, params = R.ledgerQuery(def, part, cid, inflight)
            if not sql then return nil end
            local ok, id = pcall(MySQL.scalar.await, sql, params)
            if not ok then return nil end
            return id ~= nil
        end,
    }
    local _, log = R.run(def, state, io)
    for _, l in ipairs(log) do
        Q.log('reward %s %s %s: %s%s', cid, def.id, l.key, l.outcome, l.err and (' (' .. tostring(l.err) .. ')') or '')
    end
end

---Pay every pending reward of a character (on load / resource start). Call under Q.locked.
function Q.payoutAll(cid)
    for qid, st in pairs(Q.cache[cid] or {}) do
        if R.pending(st) then
            local def = Q.defOf(qid, st)
            if def then Q.payout(cid, def) else Q.log('reward %s %s owed but no def registered', cid, qid) end
        end
    end
end

-- ---------------------------------------------------------------- commit + emit + sync
---Persist an engine result, then emit its events, then pay its reward. Nothing is emitted or paid unless the new
---state was written. Call under Q.locked.
---@return boolean ok
function Q.commit(def, after, effects)
    if not Q.save(after) then return false end
    local events, reward = I.emits(effects)
    for _, ev in ipairs(events) do TriggerEvent(ev.name, ev.payload) end
    if reward then Q.payout(after.citizenid, def) end
    return true
end

function Q.boardFor(region_id, now)
    local epoch = B.epoch(now, Q.ROTATE_MIN)
    local cached = Q.boards[region_id]
    if cached and cached.epoch == epoch then return cached end
    -- Disabled regions (FhRegions.isEnabled) get an empty board: no job type is asked for offers there.
    local lists, failed = B.collect(region_id, Q.jobTypes, FhRegions.isEnabled)
    for _, f in ipairs(failed) do
        Q.log('job type %s offers(%s) failed: %s', f.name, region_id, tostring(f.err))
    end
    local board = { epoch = epoch, expires_at = (epoch + 1) * Q.ROTATE_MIN * 60,
        offers = B.rotate(region_id, epoch, lists, { rotate_min = Q.ROTATE_MIN }) }
    Q.boards[region_id] = board
    return board
end

function Q.boardView(region_id, states, now)
    local board = Q.boardFor(region_id, now)
    local accepted = {}
    for qid, st in pairs(states or {}) do
        if st.status == 'active' then accepted[qid] = true end
    end
    return J.boardView(region_id, board.epoch, board.expires_at, board.offers, accepted, Jobs.questId)
end

---Send the full fh:quests:sync snapshot to a character's client (if online).
function Q.sync(cid)
    local src = online(cid)
    local states = Q.cache[cid]
    if not src or not states then return end
    local region = Q.viewing[src]
    local boardObj = region and Q.boardView(region, states, os.time()) or nil
    TriggerClientEvent('fh:quests:sync', src, J.snapshot(Q.defsFor(states), states, boardObj))
end

function Q.boardChanged(region_id) TriggerEvent('fh:quests:board_changed', { region_id = region_id }) end

-- ---------------------------------------------------------------- lifecycle
local function playerLoaded(src, cid)
    Q.srcOf[cid] = src
    Q.locked(cid, 30000, function()
        Q.cache[cid] = nil -- fresh read on every character load
        if Q.load(cid) then Q.payoutAll(cid) end
    end)
    Q.sync(cid)
end

local function forget(src)
    Q.viewing[src] = nil
    for cid, s in pairs(Q.srcOf) do
        if s == src then
            Q.srcOf[cid] = nil
            if not busy[cid] then Q.cache[cid] = nil end
        end
    end
end

AddEventHandler('RSGCore:Server:PlayerLoaded', function(Player)
    if not Q.ready then return end
    local d = Player and Player.PlayerData
    if d and type(d.source) == 'number' and type(d.citizenid) == 'string' then playerLoaded(d.source, d.citizenid) end
end)
AddEventHandler('RSGCore:Server:OnPlayerUnload', function(src) forget(src) end)
AddEventHandler('playerDropped', function() forget(tonumber(source)) end)

-- Migration check: the table comes from server/migrations (tools/setup-server.ps1); fh_quests never creates it.
local TABLE_SQL = "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = DATABASE() "
    .. "AND table_name = 'fh_quest_state'"

CreateThread(function()
    local ok, n = pcall(MySQL.scalar.await, TABLE_SQL)
    if not ok or tonumber(n) ~= 1 then
        Q.log('^1fh_quest_state missing (run tools/setup-server.ps1 to apply the fh_quests migration); '
            .. 'quests are disabled^7')
        return
    end
    Q.ready = true
    for _, id in ipairs(GetPlayers()) do -- resource restart with players online
        local src = tonumber(id)
        local cid = Q.citizenidOf(src)
        if cid then playerLoaded(src, cid) end
    end
    -- Board rotation: announce each region whose epoch rolled over (offers regenerate on the next getBoard).
    while true do
        Wait(60000)
        local now = os.time()
        for region_id, board in pairs(Q.boards) do
            if board.epoch ~= B.epoch(now, Q.ROTATE_MIN) then
                Q.boards[region_id] = nil
                Q.boardChanged(region_id)
            end
        end
    end
end)

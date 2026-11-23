-- fh_hands: hire/fire hands, wage ticks, task registry. State is persisted per citizenid in fh_hands (migration 0009_hands);
-- timers run server-side from the stored last_tick, so offline time is caught up (capped) the next time the owner is online.
-- Every load / tick / hire / fire for a citizenid runs under that citizenid's lock (FhHandsLogic.withLock), and each
-- wage tick is claimed in the DB before it is charged (FhHandsLogic.runOwner), so ticks never double-charge.
local cfg = FhHandsConfig
local logic = FhHandsLogic
local charger = FhHandsCharge

assert(logic.validateConfig(cfg))

local tasks = {} -- kind -> fn(ctx) -> ok, info
local hands = {} -- [citizenid] = { citizenid, src, list = { [hand_kind] = { last_tick, unpaid, status } } }
local locks = {} -- [citizenid] = true while a load / tick / hire / fire for it is in flight
local ready = false -- set once the table exists; exports refuse ('not_ready') and loads wait until then

local LOCK_WAIT = { wait = function() Wait(0) end, clock = GetGameTimer, timeoutMs = 30000 }
local LOCK_TRY = { wait = function() Wait(0) end, clock = GetGameTimer } -- poll: skip an owner that is busy

local function log(msg) print(('^3[fh_hands] %s^7'):format(msg)) end

local function registerFeed()
    local called, ok, err = pcall(function()
        return exports.fh_core:registerItems({
            [cfg.feed.item] = { label = 'Feed', weight = 500, size_class = 'bulky', stackable = true, value_base = 2 },
        })
    end)
    if not called or not ok then log(('feed item register failed: %s'):format(tostring(called and err or ok))) end
end

local function citizenOf(src)
    local P = exports['rsg-core']:GetPlayer(src)
    return P and P.PlayerData and P.PlayerData.citizenid or nil
end

-- Number of affected rows from a pcall'd MySQL.update.await, or nil when the call failed.
local function affected(okCall, n)
    if not okCall or n == nil then return nil end
    return tonumber(n) or 0
end

local function dbUpdate(sql, params) return affected(pcall(MySQL.update.await, sql, params)) end

---Caller holds the citizenid's lock. Reads the rows, then re-checks that src still has this character loaded (the
---read yields; a drop / switch during it must not leave a ghost entry bound to a src that gets reused).
---@return table|nil entry, string? err
local function loadOwner(src, cid)
    local okQ, rows = pcall(MySQL.query.await,
        'SELECT hand_kind, last_tick, unpaid, status FROM fh_hands WHERE citizenid = ?', { cid })
    if not okQ or type(rows) ~= 'table' then return nil, 'db_failed' end
    if citizenOf(src) ~= cid then return nil, 'no_player' end
    local e, quitKinds = logic.entryFromRows(cid, src, rows, cfg)
    for other, oe in pairs(hands) do -- a src carries one character: drop anything still bound to it
        if oe.src == src and other ~= cid then hands[other] = nil end
    end
    hands[cid] = e
    for _, kind in ipairs(quitKinds) do
        dbUpdate("DELETE FROM fh_hands WHERE citizenid = ? AND hand_kind = ? AND status = 'quit'", { cid, kind })
    end
    return e
end

---Register a task other lanes can attach to a hand kind (cfg.hands[kind].task). fn(ctx) -> ok, info
---ctx = { src, citizenid, hand_kind }. Re-registering a kind replaces it.
---@return boolean ok, string|nil err
local function registerTask(kind, fn)
    if type(kind) ~= 'string' or kind == '' then return false, 'bad_kind' end
    if type(fn) ~= 'function' and not (type(fn) == 'table' and fn.__cfx_functionReference) then return false, 'bad_fn' end
    tasks[kind] = fn
    return true
end

local function runTask(kind, ctx)
    local fn = tasks[kind]
    if not fn then return false, 'no_task' end
    local called, ok, info = pcall(fn, ctx)
    if not called then return false, 'task_error: ' .. tostring(ok) end
    return ok, info
end

-- ---------------------------------------------------------------- first task: feed_topup
-- Workaround: chest feed until a lane owns troughs; follow-up trough task.
-- The chest ref is rebuilt from fh_homestead's getPlot export; the stash id format must match
-- fh_homestead chestStashId ('fh:chest:<plot>:1').
local function homesteadChest(citizenid)
    local ok, plotId = pcall(function() return exports.fh_homestead:getPlot(citizenid) end)
    if not ok or type(plotId) ~= 'string' then return nil end
    return { type = 'chest', id = ('fh:chest:%s:1'):format(plotId) }
end

registerTask('feed_topup', function(ctx)
    local ref = homesteadChest(ctx.citizenid)
    if not ref then return false, 'no_homestead' end
    local items, why = exports.fh_core:snapshot(ref)
    if not items then return false, why or 'no_chest' end
    local amount = logic.topupAmount(logic.countItem(items, cfg.feed.item), cfg.feed.cap, cfg.feed.perTick)
    if amount == 0 then return true, 0 end
    local added, err = exports.fh_core:addItem(ref, cfg.feed.item, amount)
    if not added then return false, err end
    return true, amount
end)

-- ---------------------------------------------------------------- ticking
local function ioFor(e)
    local cid = e.citizenid
    return {
        online = function() return hands[cid] == e and citizenOf(e.src) == cid end,
        setLast = function(kind, expect, set)
            return (dbUpdate('UPDATE fh_hands SET last_tick = ? WHERE citizenid = ? AND hand_kind = ? AND last_tick = ?',
                { set, cid, kind, expect }) or 0) == 1
        end,
        -- Only the call's success counts: an unchanged unpaid/status may report 0 changed rows.
        saveState = function(kind, last_tick, unpaid, status)
            return dbUpdate('UPDATE fh_hands SET unpaid = ?, status = ? WHERE citizenid = ? AND hand_kind = ? AND last_tick = ?',
                { unpaid, status, cid, kind, last_tick }) ~= nil
        end,
        remove = function(kind)
            return (dbUpdate('DELETE FROM fh_hands WHERE citizenid = ? AND hand_kind = ?', { cid, kind }) or 0) >= 1
        end,
        -- B7 charge via server/charge.lua; FhHandsLogic.chargeOutcome maps its errors (fh_insufficient_funds = unpaid
        -- strike: the hand idles and eventually quits). Never a negative balance.
        charge = function(amount, reason) return charger.charge(e.src, amount, reason, cfg.regionId) end,
        runTask = function(task, kind) return runTask(task, { src = e.src, citizenid = cid, hand_kind = kind }) end,
        emit = function(name, p)
            p.src, p.citizenid = e.src, cid
            TriggerEvent(name, p)
        end,
        log = log,
    }
end

-- Caller holds the lock.
local function tickOwner(cid, now)
    local e = hands[cid]
    if e then logic.runOwner(e, cfg, now, ioFor(e)) end
end

CreateThread(function()
    while not ready do Wait(500) end
    while true do
        Wait(cfg.pollSeconds * 1000)
        local now = os.time()
        local cids = {}
        for cid in pairs(hands) do cids[#cids + 1] = cid end -- snapshot: hands changes while ticks yield
        for _, cid in ipairs(cids) do
            local ok, why, msg = logic.withLock(locks, cid, LOCK_TRY, tickOwner, cid, now)
            if not ok and why == 'error' then log(('tick %s errored: %s'):format(cid, tostring(msg))) end
        end
    end
end)

-- ---------------------------------------------------------------- lifecycle
-- Login / resource start: load under the lock, then run the capped offline catch-up.
local function onLoaded(src, cid)
    while not ready do Wait(250) end
    local ok, why, msg = logic.withLock(locks, cid, LOCK_WAIT, function()
        if citizenOf(src) ~= cid then return end
        local e, err = loadOwner(src, cid)
        if not e then log(('load %s failed: %s'):format(cid, tostring(err))) return end
        tickOwner(cid, os.time())
    end)
    if not ok then log(('login %s: %s %s'):format(cid, tostring(why), tostring(msg or ''))) end
end

-- Server-only event (rsg-core/server/player.lua Login); passes the Player object.
AddEventHandler('RSGCore:Server:PlayerLoaded', function(Player)
    local pd = Player and Player.PlayerData
    if pd and type(pd.source) == 'number' and type(pd.citizenid) == 'string' then onLoaded(pd.source, pd.citizenid) end
end)

local function forget(src)
    if type(src) ~= 'number' then return end
    for cid, e in pairs(hands) do if e.src == src then hands[cid] = nil end end
end

-- Logout / character switch (rsg-core/server/player.lua Logout) and disconnect: the src no longer bills that character.
AddEventHandler('RSGCore:Server:OnPlayerUnload', function(src) forget(tonumber(src)) end)
AddEventHandler('playerDropped', function() forget(tonumber(source)) end)

-- fh_core keeps runtime-registered items in memory: re-register feed when it restarts.
AddEventHandler('onResourceStart', function(res)
    if res == 'fh_core' and ready then registerFeed() end
end)

CreateThread(function()
    -- Idempotent, same DDL as server/migrations/0009_hands.sql (belt and braces for a DB that skipped the migration).
    local okDDL, err = pcall(MySQL.query.await, [[CREATE TABLE IF NOT EXISTS `fh_hands` (
      `citizenid` varchar(50) NOT NULL,
      `hand_kind` varchar(50) NOT NULL,
      `hired_at` bigint(20) NOT NULL,
      `last_tick` bigint(20) NOT NULL,
      `unpaid` int(11) NOT NULL DEFAULT 0,
      `status` varchar(16) NOT NULL DEFAULT 'working',
      PRIMARY KEY (`citizenid`, `hand_kind`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci]])
    if not okDDL then log(('CREATE TABLE failed (relying on migration 0009): %s'):format(tostring(err))) end
    ready = true
    registerFeed() -- fh_core item registry: we own 'feed'
    -- Resource (re)start: load everyone already online.
    for _, id in ipairs(GetPlayers()) do
        local src = tonumber(id)
        local cid = src and citizenOf(src)
        if cid then CreateThread(function() onLoaded(src, cid) end) end
    end
end)

-- ---------------------------------------------------------------- exports
---Run fn(e, cid) under the owner's lock with the owner's entry loaded (loaded on demand).
---@return any ... fn's results, or false, err
local function withOwner(src, fn)
    if not ready then return false, 'not_ready' end
    if type(src) ~= 'number' then return false, 'no_player' end
    local cid = citizenOf(src)
    if not cid then return false, 'no_player' end
    local res = table.pack(logic.withLock(locks, cid, LOCK_WAIT, function()
        if citizenOf(src) ~= cid then return false, 'no_player' end
        local e = hands[cid]
        if not e or e.src ~= src then
            local err
            e, err = loadOwner(src, cid)
            if not e then return false, err end
        end
        return fn(e, cid)
    end))
    if not res[1] then
        if res[2] == 'error' then log(('export for %s errored: %s'):format(cid, tostring(res[3]))) end
        return false, res[2]
    end
    return table.unpack(res, 2, res.n)
end

---Hire a hand of `kind`. Gated by fh_progression canUnlock('hire_hand'). Starts the wage clock now.
---@return boolean ok, string|nil err  unknown_hand | no_player | locked | already_hired | db_failed | busy | not_ready
local function hire(src, kind)
    local def = type(kind) == 'string' and cfg.hands[kind]
    if not def then return false, 'unknown_hand' end
    return withOwner(src, function(e, cid)
        if e.list[kind] then return false, 'already_hired' end
        local okU, allowed = pcall(function() return exports.fh_progression:canUnlock(src, cfg.unlockId) end)
        if not okU or allowed ~= true then return false, 'locked' end
        if citizenOf(src) ~= cid then return false, 'no_player' end -- canUnlock can yield (rep read)
        local now = os.time()
        -- a 'quit' row whose delete failed would block the insert on the primary key
        dbUpdate("DELETE FROM fh_hands WHERE citizenid = ? AND hand_kind = ? AND status = 'quit'", { cid, kind })
        local n = dbUpdate('INSERT INTO fh_hands (citizenid, hand_kind, hired_at, last_tick, unpaid, status) VALUES (?, ?, ?, ?, 0, ?)',
            { cid, kind, now, now, 'working' })
        if n ~= 1 then return false, 'db_failed' end
        e.list[kind] = { last_tick = now, unpaid = 0, status = 'working' }
        TriggerEvent('fh:hands:hired', { src = src, citizenid = cid, hand_kind = kind })
        return true
    end)
end

---@return boolean ok, string|nil err  no_player | not_hired | db_failed | busy | not_ready
local function fire(src, kind)
    if type(kind) ~= 'string' then return false, 'not_hired' end
    return withOwner(src, function(e, cid)
        if not e.list[kind] then return false, 'not_hired' end
        local n = dbUpdate('DELETE FROM fh_hands WHERE citizenid = ? AND hand_kind = ?', { cid, kind })
        if n == nil then return false, 'db_failed' end
        e.list[kind] = nil
        if n == 0 then return false, 'not_hired' end -- row already gone (quit elsewhere): nothing was fired now
        TriggerEvent('fh:hands:fired', { src = src, citizenid = cid, hand_kind = kind })
        return true
    end)
end

---@return table hands kind -> { unpaid, status, last_tick } (copy; empty when unavailable)
local function getHands(src)
    local ok, out = withOwner(src, function(e)
        local copy = {}
        for k, h in pairs(e.list) do copy[k] = { unpaid = h.unpaid, status = h.status, last_tick = h.last_tick } end
        return true, copy
    end)
    return ok == true and out or {}
end

exports('hire', hire)
exports('fire', fire)
exports('getHands', getHands)
exports('registerTask', registerTask)

-- ---------------------------------------------------------------- admin test command
-- `fh_hand_tick <serverId>`: run one wage + task tick for that player's hands now. It goes through withOwner (the same
-- per-citizenid lock as login / poll / hire / fire) and tickOwner -> runOwner (claim-before-charge), only with a clock
-- moved just far enough that the oldest hand's next tick is due. Never a bypass: charge, strikes and quit rules apply.
-- Restricted: console, or ACE `command.fh_hand_tick` (server.cfg: add_ace group.admin command allow).
RegisterCommand('fh_hand_tick', function(source, args)
    if source ~= 0 and not IsPlayerAceAllowed(source, 'command.fh_hand_tick') then return end
    local function say(msg)
        if source == 0 then print('[fh_hands] ' .. msg)
        else TriggerClientEvent('chat:addMessage', source, { args = { 'fh', msg } }) end
    end
    local p, err = logic.parseTickArgs(args)
    if not p then return say('fh_hand_tick: ' .. err) end
    local ok, why = withOwner(p.target, function(e, cid)
        local now = logic.forcedNow(e.list, cfg, os.time())
        if not now then return false, 'no_hands' end
        tickOwner(cid, now)
        return true
    end)
    say(ok and ('fh_hand_tick: ticked %d'):format(p.target) or ('fh_hand_tick: %s'):format(tostring(why)))
end, true)

-- `fh_hand_hire <serverId> <kind>` / `fh_hand_fire <serverId> <kind>`: test-only wrappers over the exports above
-- (hire keeps its canUnlock gate; both run under the owner's lock). Same restriction as fh_hand_tick.
for cmd, fn in pairs({ fh_hand_hire = hire, fh_hand_fire = fire }) do
    RegisterCommand(cmd, function(source, args)
        if source ~= 0 and not IsPlayerAceAllowed(source, 'command.' .. cmd) then return end
        local target, kind = tonumber(args[1]), args[2]
        local msg
        if not (target and target > 0 and target % 1 == 0) then msg = cmd .. ': fh_bad_target'
        elseif type(kind) ~= 'string' or not cfg.hands[kind] then msg = cmd .. ': unknown_hand'
        else
            local ok, why = fn(target, kind)
            msg = ok and ('%s: ok (%s)'):format(cmd, kind) or ('%s: %s'):format(cmd, tostring(why))
        end
        if source == 0 then print('[fh_hands] ' .. msg)
        else TriggerClientEvent('chat:addMessage', source, { args = { 'fh', msg } }) end
    end, true)
end

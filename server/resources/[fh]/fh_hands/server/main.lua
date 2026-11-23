-- fh_hands: hire/fire hands, wage ticks, task registry. State is persisted per citizenid in fh_hands (migration 0005);
-- timers run server-side from the stored last_tick, so offline time is caught up (capped) the next time the owner is online.
local cfg = FhHandsConfig
local logic = FhHandsLogic
local charger = FhHandsCharge

assert(logic.validateConfig(cfg))

local tasks = {} -- kind -> fn(ctx) -> ok, info
local hands = {} -- [citizenid] = { src = n, list = { [hand_kind] = { last_tick, unpaid, status } } }

-- Idempotent, same DDL as server/migrations/0005_hands.sql (belt and braces for a DB that skipped the migration).
CreateThread(function()
    pcall(MySQL.query.await, [[CREATE TABLE IF NOT EXISTS `fh_hands` (
      `citizenid` varchar(50) NOT NULL,
      `hand_kind` varchar(50) NOT NULL,
      `hired_at` bigint(20) NOT NULL,
      `last_tick` bigint(20) NOT NULL,
      `unpaid` int(11) NOT NULL DEFAULT 0,
      `status` varchar(16) NOT NULL DEFAULT 'working',
      PRIMARY KEY (`citizenid`, `hand_kind`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci]])
    -- fh_core item registry: we own 'feed'.
    local ok, err = exports.fh_core:registerItems({
        [cfg.feed.item] = { label = 'Feed', weight = 500, size_class = 'bulky', stackable = true, value_base = 2 },
    })
    if not ok then print(('^1[fh_hands] feed item register failed: %s^7'):format(tostring(err))) end
end)

local function citizenOf(src)
    local P = exports['rsg-core']:GetPlayer(src)
    return P and P.PlayerData and P.PlayerData.citizenid or nil
end

local function load(src, citizenid)
    local rows = MySQL.query.await('SELECT hand_kind, last_tick, unpaid, status FROM fh_hands WHERE citizenid = ?', { citizenid }) or {}
    local e = { src = src, list = {} }
    for _, r in ipairs(rows) do
        if cfg.hands[r.hand_kind] then
            e.list[r.hand_kind] = { last_tick = r.last_tick, unpaid = r.unpaid, status = r.status }
        end
    end
    hands[citizenid] = e
    return e
end

local function save(citizenid, kind, h)
    MySQL.update('UPDATE fh_hands SET last_tick = ?, unpaid = ?, status = ? WHERE citizenid = ? AND hand_kind = ?',
        { h.last_tick, h.unpaid, h.status, citizenid, kind })
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
    if not called then return false, 'task_error' end
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
local function processOwner(citizenid, now)
    local e = hands[citizenid]
    if not e then return end
    for kind, h in pairs(e.list) do
        local def = cfg.hands[kind]
        local n, newLast = logic.ticksDue(h.last_tick, now, cfg.tickSeconds, cfg.maxCatchupTicks)
        if n > 0 then
            h.last_tick = newLast
            for _ = 1, n do
                -- Unpaid path: 'fh_insufficient_funds' (broke owner) and 'charge_unavailable' (fh_economy has no charge yet,
                -- idea-600) both leave the wage unpaid: the hand idles and eventually quits. Never a negative balance.
                local paid, whyUnpaid = charger.charge(e.src, def.wage, 'wage:' .. kind, cfg.regionId)
                if not paid then
                    TriggerEvent('fh:hands:unpaid', { src = e.src, citizenid = citizenid, hand_kind = kind, reason = whyUnpaid })
                end
                local nextState, run = logic.step(h, paid == true, cfg.quitAfterUnpaid)
                h.unpaid, h.status = nextState.unpaid, nextState.status
                if run then runTask(def.task, { src = e.src, citizenid = citizenid, hand_kind = kind }) end
                if h.status == 'quit' then
                    e.list[kind] = nil
                    MySQL.update('DELETE FROM fh_hands WHERE citizenid = ? AND hand_kind = ?', { citizenid, kind })
                    TriggerEvent('fh:hands:quit', { src = e.src, citizenid = citizenid, hand_kind = kind })
                    break
                end
            end
            if e.list[kind] then save(citizenid, kind, h) end
        end
    end
end

CreateThread(function()
    while true do
        Wait(cfg.pollSeconds * 1000)
        local now = os.time()
        for citizenid in pairs(hands) do processOwner(citizenid, now) end
    end
end)

AddEventHandler('RSGCore:Server:OnPlayerLoaded', function(Player)
    local src = Player and Player.PlayerData and Player.PlayerData.source
    local cid = Player and Player.PlayerData and Player.PlayerData.citizenid
    if not (src and cid) then return end
    load(src, cid)
    processOwner(cid, os.time()) -- offline catch-up (capped by ticksDue)
end)

AddEventHandler('playerDropped', function()
    local src = source
    for cid, e in pairs(hands) do if e.src == src then hands[cid] = nil end end
end)

-- ---------------------------------------------------------------- exports
local function entry(src)
    if type(src) ~= 'number' then return nil end
    local cid = citizenOf(src)
    if not cid then return nil end
    local e = hands[cid] or load(src, cid)
    e.src = src
    return e, cid
end

---Hire a hand of `kind`. Gated by fh_progression canUnlock('hire_hand'). Starts the wage clock now.
---@return boolean ok, string|nil err
local function hire(src, kind)
    local def = type(kind) == 'string' and cfg.hands[kind]
    if not def then return false, 'unknown_hand' end
    local e, cid = entry(src)
    if not e then return false, 'no_player' end
    local okU, allowed = pcall(function() return exports.fh_progression:canUnlock(src, cfg.unlockId) end)
    if not okU or allowed ~= true then return false, 'locked' end
    if e.list[kind] then return false, 'already_hired' end
    local now = os.time()
    local ins = pcall(MySQL.insert.await,
        'INSERT INTO fh_hands (citizenid, hand_kind, hired_at, last_tick, unpaid, status) VALUES (?, ?, ?, ?, 0, ?)',
        { cid, kind, now, now, 'working' })
    if not ins then return false, 'db_failed' end
    e.list[kind] = { last_tick = now, unpaid = 0, status = 'working' }
    TriggerEvent('fh:hands:hired', { src = src, citizenid = cid, hand_kind = kind })
    return true
end

---@return boolean ok, string|nil err
local function fire(src, kind)
    local e, cid = entry(src)
    if not e then return false, 'no_player' end
    if type(kind) ~= 'string' or not e.list[kind] then return false, 'not_hired' end
    local ok = pcall(MySQL.update.await, 'DELETE FROM fh_hands WHERE citizenid = ? AND hand_kind = ?', { cid, kind })
    if not ok then return false, 'db_failed' end
    e.list[kind] = nil
    TriggerEvent('fh:hands:fired', { src = src, citizenid = cid, hand_kind = kind })
    return true
end

---@return table hands kind -> { unpaid, status, last_tick } (copy)
local function getHands(src)
    local e = entry(src)
    local out = {}
    if e then for k, h in pairs(e.list) do out[k] = { unpaid = h.unpaid, status = h.status, last_tick = h.last_tick } end end
    return out
end

exports('hire', hire)
exports('fire', fire)
exports('getHands', getHands)
exports('registerTask', registerTask)

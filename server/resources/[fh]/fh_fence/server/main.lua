-- fh_fence server: the roving fence follows a deterministic schedule (FhFenceLogic.schedule). The server owns all
-- decisions; the client only shows a menu. Money: buy = FhFenceCharge (charge.lua, B7 charge), sell = exports.fh_economy:pay.
-- Items move through fh_core's container API: a per-player `fence_stash` stages what is bought / sold (server/trade.lua);
-- known counts leave it via fh_core removeItem (all-or-nothing, B7).
-- Natives: GetPlayerPed, GetEntityCoords, GetConvar (fh_core/docs/natives.md). NOT runtime-tested (no Cfx key yet).
local cfg = FhFenceConfig
local logic = FhFenceLogic

local current = nil -- { id = stopId, reqId, tried = spawn requested at this stop }

local function log(fmt, ...) print(('[fh_fence] ' .. fmt):format(...)) end

local skew = 0 -- seconds added to the clock by the admin `fh_fence_next` test command (0 in normal play)

local function schedule() return logic.schedule(cfg, os.time() + skew) end

-- ---------------------------------------------------------------- items

local function registerItems()
    local ok, err, name = exports.fh_core:registerItems(cfg.items)
    if not ok then log('item registration failed: %s (%s)', tostring(err), tostring(name)) end
end

CreateThread(function()
    while GetResourceState('fh_core') ~= 'started' do Wait(500) end
    registerItems()
end)

AddEventHandler('onResourceStart', function(res)
    if res == 'fh_core' then CreateThread(registerItems) end
end)

-- ---------------------------------------------------------------- NPC at the current stop

-- Reuses fh_core's convar (fh_core/docs/spike-gated.md): `true` (default) = conservative, so the unverified NPC is
-- NOT spawned; the owner sets `fh_spike_gated false` once the spawn spike passes. Read every tick: a live flip applies.
local function spawnEnabled() return logic.spawnEnabled(GetConvar('fh_spike_gated', 'true')) end

local function despawn()
    if current and current.reqId then pcall(function() exports.fh_core:despawn(current.reqId) end) end
    if current then current.reqId = nil end
end

local function spawn(stop)
    local c = stop.coords
    local reqId, why = exports.fh_core:requestSpawn({
        kind = cfg.npc.kind, model = cfg.npc.model, coords = vector3(c.x, c.y, c.z), heading = c.h or 0.0,
        tag = 'fh_fence',
    }, { near = vector3(c.x, c.y, c.z) })
    if not reqId then log('spawn refused: %s', tostring(why)) end
    return reqId
end

local function tick()
    local s = schedule()
    if not s then return end
    if not current or current.id ~= s.stop then
        despawn()
        current = { id = s.stop }
        log('fence now at %s', s.stop)
    end
    if not spawnEnabled() then
        despawn()
        current.tried = false
    elseif not current.reqId and not current.tried then
        current.tried = true -- one request per stop (a refusal is logged, not retried every tick)
        current.reqId = spawn(cfg.stops[s.stop])
    end
end

CreateThread(function()
    while GetResourceState('fh_core') ~= 'started' do Wait(500) end
    while true do
        local ok, err = pcall(tick)
        if not ok then log('tick error: %s', tostring(err)) end
        Wait(5000)
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then despawn() end
end)

AddEventHandler('onResourceStart', function(res)
    if res == 'fh_core' then current = nil end -- fh_core restart dropped our spawn request
end)

exports('getSchedule', function() return schedule() end)

-- ---------------------------------------------------------------- shared helpers

---No yield (trade.lua takes the lock right after it). nil when rsg-core is down or the player is not loaded.
local function citizenOf(src)
    local ok, P = pcall(function() return exports['rsg-core']:GetPlayer(src) end)
    return ok and P and P.PlayerData and P.PlayerData.citizenid or nil
end

local function unlocked(src, id)
    local ok, res = pcall(function() return exports.fh_progression:canUnlock(src, id) end)
    return ok and res == true
end

local function visibleStock(src, stopId)
    return logic.filterStock(cfg.stock[stopId], unlocked(src, 'fence_rare_stock'), unlocked(src, 'fence_treasure_leads'))
end

---Current stop if the player is in range. @return table|nil stop, string stopIdOrReason
local function stopFor(src)
    local s = schedule()
    if not s then return nil, 'no_schedule' end
    local stop = cfg.stops[s.stop]
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return nil, 'no_player' end
    local p = GetEntityCoords(ped)
    if not logic.inRange({ x = p.x, y = p.y, z = p.z }, stop.coords, cfg.range) then return nil, 'out_of_range' end
    return stop, s.stop
end

local function ensureStash(ref, stop)
    local c = stop.coords
    return exports.fh_core:registerContainer(ref, { coords = vector3(c.x, c.y, c.z), label = stop.label })
end

---Calls an export; a throw (resource stopped) becomes false/nil + 'fh_unavailable' so trade.lua's rollback runs.
local function safe(fn)
    return function(...)
        local r = table.pack(pcall(fn, ...))
        if not r[1] then
            log('export call failed: %s', tostring(r[2]))
            return false, 'fh_unavailable'
        end
        return table.unpack(r, 2, r.n)
    end
end

local core = function(name) return safe(function(...) return exports.fh_core[name](exports.fh_core, ...) end) end

local trader = FhFenceTrade.new(cfg, logic, {
    citizenOf = citizenOf,
    stopFor = stopFor,
    currentStop = function()
        local sc = schedule()
        return sc and cfg.stops[sc.stop] or nil
    end,
    visibleStock = visibleStock,
    ensureStash = safe(ensureStash),
    snapshot = core('snapshot'),
    view = core('view'),
    canFit = core('canFit'),
    addItem = core('addItem'),
    clear = core('clearContainer'),
    removeItem = core('removeItem'),
    transferAll = core('transferAll'),
    move = core('move'),
    charge = FhFenceCharge.charge, -- pcall-wrapped itself; refusals -> false, err
    pay = safe(function(...) return exports.fh_economy:pay(...) end),
    log = function(msg) print('[fh_fence] ' .. msg) end,
    now = os.time,
})

AddEventHandler('playerDropped', function() trader.dropped(source) end)

-- ---------------------------------------------------------------- callbacks

lib.callback.register('fh:fence:where', function()
    local s = schedule()
    if not s then return nil end
    local stop = cfg.stops[s.stop]
    return { id = s.stop, label = stop.label, coords = stop.coords, range = cfg.range, remaining = s.remaining }
end)

lib.callback.register('fh:fence:menu', function(src)
    local stop, id = stopFor(src)
    if not stop then return nil, id end
    local sells = {}
    for item, price in pairs(cfg.buys) do sells[#sells + 1] = { item = item, price = price } end
    table.sort(sells, function(a, b) return a.item < b.item end)
    return { label = stop.label, stock = visibleStock(src, id), sells = sells }
end)

-- Both run under a per-citizenid lock with all rollback rules in server/trade.lua.
-- buy -> true, delivered, refunded | false, code.  sell -> true, sold, total | false, code.
lib.callback.register('fh:fence:buy', function(src, item, qty) return trader.buy(src, item, qty) end)
lib.callback.register('fh:fence:sell', function(src, item, qty) return trader.sell(src, item, qty) end)

-- fh_ui `fence` screen. The client opens it with the data from `fh:fence:screen`; its buy/sell actions arrive as the
-- server events fh_ui relays (`fh:fence:ui_buy` / `fh:fence:ui_sell`, one table { src, screen, action, payload }) and
-- run the same trader calls as the callbacks above. The result goes back as `fh:ui:update` with an inline `notice`.
local snapshot = core('snapshot')
local function screenFor(src)
    local stop, id = stopFor(src)
    if not stop then return nil, id end
    local sells = {}
    for item, price in pairs(cfg.buys) do sells[#sells + 1] = { item = item, price = price } end
    table.sort(sells, function(a, b) return a.item < b.item end)
    local menu = { label = stop.label, stock = visibleStock(src, id), sells = sells }
    local labels, held = {}, {}
    for name, def in pairs(cfg.items) do labels[name] = def.label end
    local items = snapshot({ type = 'backpack', id = src })
    for _, it in pairs(items or {}) do held[it.name] = (held[it.name] or 0) + (tonumber(it.amount) or 1) end
    return logic.screenData(menu, { maxQty = cfg.maxQty, labels = labels, held = held })
end

lib.callback.register('fh:fence:screen', function(src)
    local data, err = screenFor(src)
    if not data then return nil, err end
    return data
end)

local function uiTrade(kind)
    return function(ev)
        if type(ev) ~= 'table' or type(ev.src) ~= 'number' or type(ev.payload) ~= 'table' then return end
        local item, qty = ev.payload.id, ev.payload.qty
        local r = table.pack((kind == 'buy' and trader.buy or trader.sell)(ev.src, item, qty))
        local data = screenFor(ev.src) -- nil when the player walked out of range: notice only
        data = data or {}
        data.notice = logic.notice(kind, qty, r[1], r[2], r[3])
        TriggerClientEvent('fh:ui:update', ev.src, { screen = 'fence', data = data })
    end
end
AddEventHandler('fh:fence:ui_buy', uiTrade('buy'))
AddEventHandler('fh:fence:ui_sell', uiTrade('sell'))

-- ---------------------------------------------------------------- admin test command
-- `fh_fence_next`: jump the fence to its next stop now. It only skews the clock schedule() reads, so the NPC move,
-- stock and every trade (stopFor -> schedule, under trader's per-citizen lock) behave exactly as at a normal rotation:
-- a trade already running keeps its lock and its stop check is done at its start, like when the dwell timer expires.
-- Restricted: console, or ACE `command.fh_fence_next` (server.cfg: add_ace group.admin command allow).
RegisterCommand('fh_fence_next', function(source)
    if source ~= 0 and not IsPlayerAceAllowed(source, 'command.fh_fence_next') then return end
    local jump = logic.secondsToNext(cfg, os.time() + skew)
    local msg
    if not jump then
        msg = 'fh_fence_next: no schedule'
    else
        skew = skew + jump
        pcall(tick) -- apply at once instead of waiting for the 5 s poll
        local s = schedule()
        msg = ('fh_fence_next: now at %s (next %s)'):format(s and s.stop or '?', s and s.nextStop or '?')
    end
    if source == 0 then print('[fh_fence] ' .. msg)
    else TriggerClientEvent('chat:addMessage', source, { args = { 'fh', msg } }) end
end, true)

-- `fh_fence_settle <serverId>`: clears a player's `fence_pending` stash (left by a failed partial delivery / restore,
-- see the WARNING lines). Runs through trader.settle, i.e. under the same per-citizenid lock as buy / sell: a trade in
-- flight gives `fence_busy`. Goods go to the player all-or-nothing (`no_room`: nothing changed); fence-owned leftovers
-- are swept instead. Restricted: console, or ACE `command.fh_fence_settle` (server.cfg: add_ace group.admin command allow).
RegisterCommand('fh_fence_settle', function(source, args)
    if source ~= 0 and not IsPlayerAceAllowed(source, 'command.fh_fence_settle') then return end
    local target, err = logic.parseSettleArgs(args)
    local msg
    if not target then
        msg = 'fh_fence_settle: ' .. err
    else
        local ok, a, b = trader.settle(target)
        if ok then
            msg = b == 'swept' and ('fh_fence_settle: ok (%d: fence-owned leftovers swept)'):format(target)
                or ('fh_fence_settle: ok (%d units to %d)'):format(a, target)
        else
            msg = 'fh_fence_settle: ' .. tostring(a)
        end
    end
    if source == 0 then print('[fh_fence] ' .. msg)
    else TriggerClientEvent('chat:addMessage', source, { args = { 'fh', msg } }) end
end, true)

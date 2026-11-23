-- fh_fence server: the roving fence follows a deterministic schedule (FhFenceLogic.schedule). The server owns all
-- decisions; the client only shows a menu. Money: buy = FhFenceCharge (compat_charge.lua), sell = exports.fh_economy:pay.
-- Items move through fh_core's container API: a per-player `fence_stash` stages what is bought / sold.
-- Natives: GetPlayerPed, GetEntityCoords, GetConvar (fh_core/docs/natives.md). NOT runtime-tested (no Cfx key yet).
local cfg = FhFenceConfig
local logic = FhFenceLogic

local current = nil -- { id, reqId }

local function log(fmt, ...) print(('[fh_fence] ' .. fmt):format(...)) end

local function schedule() return logic.schedule(cfg, os.time()) end

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

-- Reuses fh_core's convar (fh_core/docs/spike-gated.md). Spawn only while it is enabled, per the P2 brief.
local function spawnEnabled() return logic.parseFlag(GetConvar('fh_spike_gated', 'true'), true) end

local function despawn()
    if current and current.reqId then pcall(function() exports.fh_core:despawn(current.reqId) end) end
    if current then current.reqId = nil end
end

local function spawn(stop)
    if not spawnEnabled() then return end
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
    if current and current.id == s.stop then return end
    despawn()
    current = { id = s.stop }
    current.reqId = spawn(cfg.stops[s.stop])
    log('fence now at %s', s.stop)
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

local function citizenOf(src)
    local P = exports['rsg-core']:GetPlayer(src)
    return P and P.PlayerData and P.PlayerData.citizenid or nil
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

local function stashRef(citizenid) return { type = 'fence_stash', id = citizenid .. ':fence' } end

local function ensureStash(ref, stop)
    local c = stop.coords
    return exports.fh_core:registerContainer(ref, { coords = vector3(c.x, c.y, c.z), label = stop.label })
end

local function refund(src, amount, region)
    local ok, err = exports.fh_economy:pay(src, amount, 'fence_refund', region)
    if not ok then log('REFUND FAILED src=%s amount=%s: %s', tostring(src), tostring(amount), tostring(err)) end
end

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

lib.callback.register('fh:fence:buy', function(src, item, qty)
    local stop, id = stopFor(src)
    if not stop then return false, id end
    local quote, why = logic.quoteBuy(visibleStock(src, id), item, qty, cfg.maxQty)
    if not quote then return false, why end
    local cid = citizenOf(src)
    if not cid then return false, 'no_player' end
    local backpack, stash = { type = 'backpack', id = src }, stashRef(cid)

    local fits, fitWhy = exports.fh_core:canFit(backpack, item, qty)
    if not fits then return false, fitWhy or 'no_room' end
    local ok, err = ensureStash(stash, stop)
    if not ok then return false, err end
    ok, err = exports.fh_core:addItem(stash, item, qty, logic.leadInfo(quote.entry)) -- stage first: no money lost on failure
    if not ok then return false, err end

    ok, err = FhFenceCharge.charge(src, quote.total, 'fence_buy:' .. item, stop.region_id)
    if not ok then
        exports.fh_core:clearContainer(stash)
        return false, err
    end
    local moved, movedWhy = exports.fh_core:transferAll(stash, backpack, src)
    local left = exports.fh_core:snapshot(stash)
    if not moved or (left and next(left) ~= nil) then
        exports.fh_core:clearContainer(stash)
        refund(src, quote.total, stop.region_id)
        return false, type(movedWhy) == 'string' and movedWhy or 'transfer_failed'
    end
    return true
end)

lib.callback.register('fh:fence:sell', function(src, item, qty)
    local stop, id = stopFor(src)
    if not stop then return false, id end
    local pending, why = logic.quoteSell(cfg, item, qty)
    if not pending then return false, why end
    local cid = citizenOf(src)
    if not cid then return false, 'no_player' end
    local backpack, stash = { type = 'backpack', id = src }, stashRef(cid)
    local ok, err = ensureStash(stash, stop)
    if not ok then return false, err end

    local items = exports.fh_core:snapshot(backpack)
    local v = exports.fh_core:view(stash)
    if not items or not v then return false, 'fh_unavailable' end
    local free = {}
    for slot = 1, v.slots do if not v.items[slot] then free[#free + 1] = slot end end

    local need, sold, slots = qty, 0, {}
    for slot in pairs(items) do slots[#slots + 1] = slot end
    table.sort(slots)
    for _, slot in ipairs(slots) do
        local it = items[slot]
        if need > 0 and it.name == item and free[1] then
            local take = math.min(need, it.amount or 1)
            local mok = exports.fh_core:move(backpack, stash, slot, table.remove(free, 1), take, src)
            if mok then need, sold = need - take, sold + take end
        end
    end
    if sold == 0 then
        exports.fh_core:clearContainer(stash)
        return false, 'not_enough_items'
    end
    local total = cfg.buys[item] * sold
    local paid, payWhy = exports.fh_economy:pay(src, total, 'fence_sell:' .. item, stop.region_id)
    if not paid then
        exports.fh_core:transferAll(stash, backpack, src) -- give the goods back
        exports.fh_core:clearContainer(stash)
        return false, payWhy or 'pay_failed'
    end
    exports.fh_core:clearContainer(stash)
    return true, sold, total
end)

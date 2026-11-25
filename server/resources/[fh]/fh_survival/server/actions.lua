-- fh_survival actions (plan survival-01, S3): usable food + canteen, refill/wash in water, campfire warmth.
-- Every need is granted through exports.fh_buffs:apply. Decisions live in shared/items.lua (pure, specced).
-- Never touches health. Water is checked server-side against config zones unless WaterCheck = 'native'.
local cfg = FhSurvivalConfig
local I = FhSurvivalItems
local DUR = FhSurvivalNeeds.durations(cfg.Durations) -- validated, defaults filled

local function now() return GetGameTimer() / 1000.0 end

local function notify(src, msg) TriggerClientEvent('fh:survival:notify', src, msg) end

local function applyBuff(src, id, mag, dur)
    local ok, res, err = pcall(function() return exports.fh_buffs:apply(src, id, mag, dur) end)
    if not ok or res == false then
        print(('[fh_survival] apply %s refused for %s: %s'):format(id, tostring(src), tostring(ok and err or res)))
        return false
    end
    return true
end

-- ---- item registration (exports.fh_core:registerItems, B7; re-run when fh_core restarts) ----

local function registerItems()
    local ok, err, bad = exports.fh_core:registerItems(I.ITEMS)
    if not ok then
        print(('[fh_survival] registerItems failed: %s (%s)'):format(tostring(err), tostring(bad)))
    end
end

-- ---- inventory glue ----

local function itemAt(src, name, slot)
    local ok, item = pcall(function()
        if slot then
            local it = exports['rsg-inventory']:GetItemBySlot(src, slot)
            if it and it.name == name then return it end
        end
        return exports['rsg-inventory']:GetItemByName(src, name)
    end)
    return ok and item or nil
end

local lastUse = {} -- [src] = seconds; stops double-fire of a use callback

local function onUse(src, item)
    if type(item) ~= 'table' or type(item.name) ~= 'string' then return end
    local eff = I.effectOf(item.name, cfg.Durations)
    if not eff then return end
    local t = now()
    if lastUse[src] and t - lastUse[src] < 1.0 then return end
    lastUse[src] = t
    local live = itemAt(src, item.name, item.slot)
    if not live then return end -- not actually in the inventory
    -- Consume first, grant after: a failed inventory update never leaves a free buff. fh_buffs has no remove, so if it
    -- refuses the buff (e.g. no cap for `hydrated` yet) the consumption is refunded instead.
    local inv = exports['rsg-inventory']
    if eff.kind == 'food' then
        local pok, removed = pcall(function() return inv:RemoveItem(src, item.name, 1, live.slot, 'survival use') end)
        local removedOk = pok and removed
        -- Consume first, grant after (I.consumeOutcome): a failed remove grants nothing; a refused buff is refunded.
        local applied = removedOk and applyBuff(src, eff.buff_id, eff.magnitude, eff.duration)
        local outcome = I.consumeOutcome(removedOk, applied)
        if outcome == 'blocked' then
            print(('[fh_survival] RemoveItem %s failed for %s; nothing granted'):format(item.name, tostring(src)))
            notify(src, I.refuseMessage(eff.buff_id))
            return
        elseif outcome == 'refund' then
            local rok, added = pcall(function() return inv:AddItem(src, item.name, 1, nil, live.info, 'survival refund') end)
            if not (rok and added) then print(('[fh_survival] refund of %s to %s FAILED'):format(item.name, tostring(src))) end
            notify(src, I.refuseMessage(eff.buff_id))
            return
        end
        notify(src, eff.buff_id == 'hydrated' and 'You feel refreshed.' or 'You feel fed.')
    else -- canteen
        local ok, res = I.useCanteen(live.info, cfg.CanteenMax)
        if not ok then notify(src, res == 'empty' and 'The canteen is empty. Refill it at water.' or 'The canteen is damaged.') return end
        local pok, saved = pcall(function() return inv:SetItemInfo(src, live.slot, res) end)
        if not (pok and saved) then
            print(('[fh_survival] SetItemInfo %s failed for %s; nothing granted'):format(item.name, tostring(src)))
            notify(src, 'You cannot drink right now.')
            return
        end
        if not applyBuff(src, eff.buff_id, eff.magnitude, eff.duration) then
            local rok, back = pcall(function() return inv:SetItemInfo(src, live.slot, live.info or {}) end)
            if not (rok and back) then print(('[fh_survival] charge refund of %s to %s FAILED'):format(item.name, tostring(src))) end
            notify(src, 'You cannot drink right now.')
            return
        end
        notify(src, ('You drink. %d charges left.'):format(res.charges))
    end
end

-- Live item registry (RSGCore.Shared.Items) for the skip-if-missing check on foreign rows. A fresh core object
-- each call, so an rsg-core restart (which resets Shared.Items) is seen.
local function sharedItems()
    local ok, core = pcall(function() return exports['rsg-core']:GetCoreObject() end)
    if not (ok and type(core) == 'table' and type(core.Shared) == 'table' and type(core.Shared.Items) == 'table') then
        return {}
    end
    return core.Shared.Items
end

local function registerUsables()
    local known = sharedItems()
    local register, skipped = I.usableRows(function(name) return known[name] ~= nil end)
    if #skipped > 0 then
        print(('[fh_survival] skipped %d useable(s) not in RSGCore.Shared.Items: %s'):format(#skipped, table.concat(skipped, ', ')))
    end
    for _, name in ipairs(register) do
        local ok, err = pcall(function() exports['rsg-core']:CreateUseableItem(name, onUse) end)
        if not ok then print(('[fh_survival] CreateUseableItem %s failed: %s'):format(name, tostring(err))) end
    end
end

-- ---- water: refill + wash ----

local function coordsOf(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return nil end
    local c = GetEntityCoords(ped)
    return { x = c.x, y = c.y, z = c.z }
end

---Zones mode: server ped vs WaterZones. Native mode: trust the client's IsEntityInWater report (cooldown still applies).
local function inWater(src, clientFlag)
    if I.waterMode(cfg.WaterCheck) == 'native' then return clientFlag == true end
    local pos = coordsOf(src)
    return pos ~= nil and I.inWaterZone(pos, cfg.WaterZones)
end

local lastWash = {} -- [src] = seconds
local lastRefill = {}

RegisterNetEvent('fh:survival:refill', function(clientInWater)
    local src = source
    local t = now()
    if lastRefill[src] and t - lastRefill[src] < 1.0 then return end
    lastRefill[src] = t
    if not inWater(src, clientInWater) then notify(src, 'You need to stand in water to refill.') return end
    local live = itemAt(src, 'fh_canteen')
    if not live then notify(src, 'You have no canteen.') return end
    local ok, res = I.refillCanteen(live.info, cfg.CanteenMax)
    if not ok then notify(src, res == 'full' and 'The canteen is already full.' or 'The canteen is damaged.') return end
    local pok, saved = pcall(function() return exports['rsg-inventory']:SetItemInfo(src, live.slot, res) end)
    if pok and saved then notify(src, 'You refill the canteen.') end
end)

RegisterNetEvent('fh:survival:wash', function(clientInWater)
    local src = source
    if not inWater(src, clientInWater) then notify(src, 'You need to stand in water to wash.') return end
    local t = now()
    local ok, rem = I.washReady(lastWash[src], t, cfg.WashCooldownSeconds)
    if not ok then notify(src, ('You washed recently. Try again in %d s.'):format(math.ceil(rem or 0))) return end
    if applyBuff(src, 'clean', 1.0, DUR.clean) then
        lastWash[src] = t -- cooldown starts only on a successful wash
        notify(src, 'You wash off the grime.')
    end
end)

-- ---- warmth: campfire proximity ----

local dynamicHeat = {} -- [id] = { x, y, z?, radius? } from exports.fh_survival:setHeatSource

local function heatSources()
    local list = {}
    for _, s in ipairs(cfg.Campfires or {}) do list[#list + 1] = s end
    for _, s in pairs(dynamicHeat) do list[#list + 1] = s end
    return list
end

exports('setHeatSource', function(id, coords, radius)
    if type(id) ~= 'string' or type(coords) ~= 'table' or type(coords.x) ~= 'number' or type(coords.y) ~= 'number' then return false end
    dynamicHeat[id] = { x = coords.x, y = coords.y, z = coords.z, radius = radius }
    return true
end)
exports('removeHeatSource', function(id) dynamicHeat[id] = nil return true end)

CreateThread(function()
    while true do
        Wait(math.max(1, cfg.HeatCheckSeconds or 10) * 1000)
        local sources = heatSources()
        if #sources > 0 then
            for _, id in ipairs(GetPlayers()) do
                local src = tonumber(id)
                local pos = src and coordsOf(src)
                if pos and I.nearHeat(pos, sources, cfg.HeatRadius) then
                    applyBuff(src, 'warm', 1.0, DUR.warm)
                end
            end
        end
    end
end)

-- ---- lifecycle ----

AddEventHandler('playerDropped', function() lastUse[source] = nil lastWash[source] = nil lastRefill[source] = nil end)

AddEventHandler('onResourceStart', function(res)
    if res == GetCurrentResourceName() then
        CreateThread(function() registerItems() registerUsables() end)
    elseif res == 'fh_core' then
        registerItems()
    elseif res == 'rsg-core' then
        registerUsables()
    end
end)

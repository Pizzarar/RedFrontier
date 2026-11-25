-- Rest (plan survival-01, S4): bedroll item (rested 1.0 anywhere) and homestead bed (1.0 + comfort*k, capped).
-- Applies only through exports.fh_buffs:apply; never touches health.
local cfg = FhSurvivalConfig
local N = FhSurvivalNeeds
local R = FhSurvivalRest

local function citizenOf(src)
    local ok, p = pcall(function() return exports['rsg-core']:GetPlayer(src) end)
    return ok and p and p.PlayerData and p.PlayerData.citizenid or nil
end

---@param kind string 'bedroll' | 'bed'
---@return boolean ok, number|string magnitudeOrErr
local function rest(src, kind)
    local info = kind == 'bed' and FhSurvivalHomestead.info(src, citizenOf(src)) or nil
    local mag, err = R.magnitude(N, kind, info, cfg.ComfortK, cfg.RestedCap)
    if not mag then return false, err end
    local dur = N.durations(cfg.Durations).rested
    local ok, res, aerr = pcall(function() return exports.fh_buffs:apply(src, 'rested', mag, dur) end)
    if not ok or res == false then return false, ok and tostring(aerr) or 'buffs_unavailable' end
    return true, mag
end

exports('restBedroll', function(src) return rest(src, 'bedroll') end)
exports('restAtBed', function(src) return rest(src, 'bed') end)

local function now() return GetGameTimer() / 1000.0 end

local lastRestBed = {} -- [src] = seconds; per-player cooldown on fh:survival:restBed (idea-948)

-- The server re-checks proximity itself; a client can only ask.
RegisterNetEvent('fh:survival:restBed', function()
    local src = source
    local t = now()
    local ready, rem = R.cooldownReady(lastRestBed[src], t, cfg.RestBedCooldownSeconds)
    if not ready then
        TriggerClientEvent('fh:survival:notify', src, ('Please wait %d s before resting again.'):format(math.ceil(rem or 0)))
        return
    end
    lastRestBed[src] = t
    local ok, res = rest(src, 'bed')
    local msg
    if ok then msg = 'You rest and feel rested.'
    elseif res == 'no_bed' then msg = 'You need to be at your bed to rest.'
    else msg = 'You cannot rest right now.' end
    TriggerClientEvent('fh:survival:notify', src, msg)
end)

AddEventHandler('playerDropped', function() lastRestBed[source] = nil end)

-- ---- bedroll item ----
-- The item definition lives in shared/items.lua (FhSurvivalItems.ITEMS) and is registered with the S3 items by
-- server/actions.lua through exports.fh_core:registerItems. Only the usable-item callback is ours.
local BEDROLL = FhSurvivalItems.BEDROLL

local function registerUsable()
    pcall(function()
        exports['rsg-core']:CreateUseableItem(BEDROLL, function(source) rest(source, 'bedroll') end)
    end)
end

CreateThread(function()
    while GetResourceState('rsg-core') ~= 'started' do Wait(500) end
    registerUsable()
end)
-- rsg-core restart drops UsableItems callbacks.
AddEventHandler('onResourceStart', function(res)
    if res == 'rsg-core' then CreateThread(registerUsable) end
end)

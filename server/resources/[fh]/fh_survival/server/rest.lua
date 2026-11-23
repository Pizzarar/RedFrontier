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

-- The server re-checks proximity itself; a client can only ask.
RegisterNetEvent('fh:survival:restBed', function() rest(source, 'bed') end)

-- ---- bedroll item (guarded: fh_core registerItems may be missing/older) ----
local function registerUsable()
    pcall(function()
        exports['rsg-core']:CreateUseableItem(cfg.BedrollItem, function(source) rest(source, 'bedroll') end)
    end)
end

local function registerBedroll()
    local def = { [cfg.BedrollItem] = { label = 'Bedroll', weight = 2500, size_class = 'bulky', stackable = false, value_base = 12, useable = true } }
    local ok, res, err = pcall(function() return exports.fh_core:registerItems(def) end)
    if not ok or res == false then print(('[fh_survival] bedroll item registration skipped: %s'):format(tostring(ok and err or res))) end
    registerUsable()
end

CreateThread(function()
    while GetResourceState('fh_core') ~= 'started' do Wait(500) end
    registerBedroll()
end)
-- fh_core restart drops its item registry; rsg-core restart drops UsableItems callbacks.
AddEventHandler('onResourceStart', function(res)
    if res == 'fh_core' then CreateThread(registerBedroll)
    elseif res == 'rsg-core' then CreateThread(registerUsable) end
end)

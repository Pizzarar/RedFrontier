-- fh_homestead H20b client: horse refill on mount. CLIENT ONLY ASKS; the server (server/trough.lua) re-checks owner,
-- radius, feedbag, cooldown and consumes the feedbag, and only then tells this client to refill.
-- Everything here is behind FhHomesteadConfig.trough.troughRefill (default false): with the flag off no native is called
-- and no request is sent. Natives are unverified in game (see OWNER-TESTS): GetMount, SetAttributeCoreValue.
local MOUNTED = false

local function cfgOn()
    local c = FhHomesteadConfig and FhHomesteadConfig.trough
    return type(c) == 'table' and c.troughRefill == true
end

-- core indexes of a horse: 0 health, 1 stamina (unverified)
local CORE_HEALTH, CORE_STAMINA, CORE_MAX = 0, 1, 100
local SET_ATTRIBUTE_CORE_VALUE = 0xC6258F41D86676E0 -- unverified hash

local function mountOf()
    local ped = PlayerPedId()
    if not ped or ped == 0 then return 0 end
    local ok, mount = pcall(GetMount, ped)
    return ok and tonumber(mount) or 0
end

FH.onNet('fh:homestead:trough_refilled', function()
    if not cfgOn() then return end
    local horse = mountOf()
    if horse == 0 or not DoesEntityExist(horse) then return end
    for _, core in ipairs({ CORE_HEALTH, CORE_STAMINA }) do
        pcall(Citizen.InvokeNative, SET_ATTRIBUTE_CORE_VALUE, horse, core, CORE_MAX)
    end
end)

FH.thread(function()
    while true do
        Wait(cfgOn() and 1000 or 10000)
        if cfgOn() then
            local on = mountOf() ~= 0
            if on and not MOUNTED then TriggerServerEvent('fh:homestead:trough_refill') end
            MOUNTED = on
        else
            MOUNTED = false
        end
    end
end)

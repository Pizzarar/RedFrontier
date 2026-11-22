-- spk_camp client: (1) fallback camp builder, (2) owner-side arming loop (relationship, weapon, combat).
-- Arming is client-side because those natives are not available on the server.
local tracked = {}   -- netId -> true (from server sync)
local armed = {}     -- netId -> true while WE own and have armed it
local GROUP = joaat('SPK_OUTLAWS')

local function note(msg, kind)
    print('[spk_camp] ' .. msg)
    lib.notify({ title = 'spk_camp', description = msg, type = kind or 'inform', duration = 6000 })
end

local function load(model)
    local hash = joaat(model)
    if not IsModelInCdimage(hash) then return nil end
    RequestModel(hash, false)
    local t = GetGameTimer() + 5000
    while not HasModelLoaded(hash) and GetGameTimer() < t do Wait(50) end
    return HasModelLoaded(hash) and hash or nil
end

local function groundZ(x, y, z)
    local ok, gz = GetGroundZFor_3dCoord(x, y, z + 20.0, false)
    return ok and gz or z
end

RegisterNetEvent('spk_camp:build', function(center)
    local list = {}
    local pedHash = load(Config.pedModel)
    if not pedHash then return note('ped model failed to load: ' .. Config.pedModel, 'error') end
    for _ = 1, Config.pedCount do
        local x, y = center.x + math.random(-3, 3) + 0.0, center.y + math.random(-3, 3) + 0.0
        local ped = CreatePed(pedHash, x, y, groundZ(x, y, center.z), math.random(0, 359) + 0.0, true, false, false, false)
        if ped ~= 0 then
            Citizen.InvokeNative(0x283978A15512B2FE, ped, true) -- _SET_RANDOM_OUTFIT_VARIATION, else peds can be invisible
            SetEntityAsMissionEntity(ped, true, true)
            list[#list + 1] = { netId = NetworkGetNetworkIdFromEntity(ped), kind = 'ped', model = Config.pedModel }
        end
    end
    SetModelAsNoLongerNeeded(pedHash)
    local made = 0
    for _, m in ipairs(Config.propModels) do
        if made >= 3 then break end
        local h = load(m)
        if h then
            local x, y = center.x + (made + 1) * 2.0, center.y
            local o = CreateObject(h, x, y, groundZ(x, y, center.z), true, false, false, false, false)
            if o ~= 0 then
                PlaceObjectOnGroundProperly(o, true)
                SetEntityAsMissionEntity(o, true, true)
                list[#list + 1] = { netId = NetworkGetNetworkIdFromEntity(o), kind = 'prop', model = m }
                made = made + 1
            end
            SetModelAsNoLongerNeeded(h)
        else
            print('[spk_camp] prop model skipped (not in cdimage / not loaded): ' .. m)
        end
    end
    note(('built %d entities locally, reporting to server'):format(#list))
    TriggerServerEvent('spk_camp:built', list)
end)

RegisterNetEvent('spk_camp:sync', function(ids)
    tracked = {}
    for _, id in ipairs(ids) do tracked[id] = true end
    if next(tracked) == nil then armed = {} end
end)

local function arm(ped)
    AddRelationshipGroup('SPK_OUTLAWS')
    SetPedRelationshipGroupHash(ped, GROUP)
    SetRelationshipBetweenGroups(5, GROUP, joaat('PLAYER')) -- 5 = hate
    SetRelationshipBetweenGroups(5, joaat('PLAYER'), GROUP)
    local w = joaat(Config.weapon)
    GiveWeaponToPed(ped, w, 100, true, false, 0, false, 0.5, 1.0, 0, false, 0.0, false)
    SetCurrentPedWeapon(ped, w, true, 0, false, false)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedAccuracy(ped, 30)
    SetPedKeepTask(ped, true)
end

CreateThread(function()
    TriggerServerEvent('spk_camp:requestSync')
    while true do
        Wait(2000)
        local me, myPed = PlayerId(), PlayerPedId()
        for netId in pairs(tracked) do
            local ped = NetworkDoesNetworkIdExist(netId) and NetToPed(netId) or 0
            if ped ~= 0 and DoesEntityExist(ped) then
                local owner = NetworkGetEntityOwner(ped) == me
                if owner and not armed[netId] then
                    armed[netId] = true
                    arm(ped)
                    note(('I now OWN ped netId=%d (armed it)'):format(netId))
                elseif not owner and armed[netId] then
                    armed[netId] = nil
                    print(('[spk_camp] lost ownership of netId=%d'):format(netId))
                end
                if owner and not IsPedDeadOrDying(ped, false) then
                    local d = #(GetEntityCoords(ped) - GetEntityCoords(myPed))
                    if d < Config.aggroRange and not IsPedDeadOrDying(myPed, false) then
                        TaskCombatPed(ped, myPed, 0, 16)
                    end
                end
            end
        end
    end
end)

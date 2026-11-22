-- spk_wheel client. Underscore natives are called by hash (names come from alloc8or rdr3 nativedb).
local N_BREAK_OFF_DRAFT_WHEEL  = 0xC372B6A88F6E4AD8 -- _BREAK_OFF_DRAFT_WHEEL(vehicle, wheelIndex, force)
local N_BREAK_OFF_VEHICLE_WHEEL = 0xD4F5EFB55769D272 -- _BREAK_OFF_VEHICLE_WHEEL(vehicle, wheelIndex) -> Entity
local N_IS_WHEEL_DESTROYED     = 0xCB2CA620C48BC875 -- _IS_VEHICLE_WHEEL_DESTROYED(vehicle, wheel)
local N_ANY_WHEELS_DESTROYED   = 0x18714953CCED17D3 -- _ARE_ANY_VEHICLE_WHEELS_DESTROYED(vehicle)
local N_IS_DRAFT_VEHICLE       = 0xEA44E97849E9F3DD -- IS_DRAFT_VEHICLE(vehicle)
local N_SET_WHEELS_CAN_BREAK   = 0x839137C40275FB77 -- SET_VEHICLE_WHEELS_CAN_BREAK(vehicle, bool)
local N_SET_FIXED              = 0x79811282A9D1AE56 -- SET_VEHICLE_FIXED(vehicle)
local N_MODIFY_TOP_SPEED       = 0x35AD938C74CACD6A -- MODIFY_VEHICLE_TOP_SPEED(vehicle, value)
local N_GET_ENTITY_SPEED       = 0xFB6BA510A533DF81 -- GET_ENTITY_SPEED(entity) -> float
local N_GET_VEHICLE_PED_IS_IN  = 0x9A9112A0FE9A4713 -- GET_VEHICLE_PED_IS_IN(ped, lastVehicle)
local N_PLAYER_PED_ID          = 0x096275889B8E0EE0 -- PLAYER_PED_ID()
local N_DOES_ENTITY_EXIST      = 0xD42BD6EB2E0F1677 -- DOES_ENTITY_EXIST(entity)

local N_CREATE_VEHICLE         = 0xAF35D0D2583051B0 -- CREATE_VEHICLE(modelHash, x, y, z, heading, isNetwork, bScriptHostVeh, bDontAutoCreateDraftAnimals, p8)
local N_SET_PED_INTO_VEHICLE   = 0xF75B0D629E1C063D -- SET_PED_INTO_VEHICLE(ped, vehicle, seatIndex)
local N_REQUEST_MODEL          = 0xFA28FE3A6246FC30 -- REQUEST_MODEL(model, p1)
local N_HAS_MODEL_LOADED       = 0x1283B8B89DD5D1B6 -- HAS_MODEL_LOADED(model)
local N_IS_MODEL_IN_CDIMAGE    = 0xD6F3B6D7716CFF8E -- IS_MODEL_IN_CDIMAGE(model)
local N_SET_MODEL_NO_LONGER    = 0x4AD96EF928BD4F9A -- SET_MODEL_AS_NO_LONGER_NEEDED(model)
local N_GET_OFFSET             = 0x1899F328B0E12848 -- GET_OFFSET_FROM_ENTITY_IN_WORLD_COORDS(entity, x, y, z) -> vector3
local N_GET_ENTITY_HEADING     = 0xC230DD956E2F5507 -- GET_ENTITY_HEADING(entity)

local function bool(v) return v == true or (type(v) == 'number' and v ~= 0) end
local function say(msg)
    print('[spk_wheel] ' .. msg)
    lib.notify({ title = 'spk_wheel', description = msg, type = 'inform', duration = 6000 })
end
local function speed(veh) return Citizen.InvokeNative(N_GET_ENTITY_SPEED, veh, Citizen.ResultAsFloat()) end
local function wheelState(veh)
    local t = {}
    for i = 0, 7 do
        t[#t + 1] = i .. '=' .. tostring(bool(Citizen.InvokeNative(N_IS_WHEEL_DESTROYED, veh, i)))
    end
    return table.concat(t, ' ')
end

-- /spk_wheel wagon: spawn a networked cart01 ~5m to the player's right and seat the player as driver.
local function spawnWagon()
    local model = joaat('cart01') -- name verified in femga/rdr3_discoveries vehicles_list.lua (0xCEDED274)
    local ped = Citizen.InvokeNative(N_PLAYER_PED_ID, Citizen.ResultAsInteger())
    if not bool(Citizen.InvokeNative(N_IS_MODEL_IN_CDIMAGE, model)) then return say('cart01 not in CD image') end
    Citizen.InvokeNative(N_REQUEST_MODEL, model, false)
    local t = GetGameTimer() + 5000
    while not bool(Citizen.InvokeNative(N_HAS_MODEL_LOADED, model)) do
        if GetGameTimer() > t then return say('cart01 model load timed out') end
        Wait(50)
    end
    local pos = Citizen.InvokeNative(N_GET_OFFSET, ped, 5.0, 0.0, 0.0, Citizen.ResultAsVector())
    local h = Citizen.InvokeNative(N_GET_ENTITY_HEADING, ped, Citizen.ResultAsFloat())
    local veh = Citizen.InvokeNative(N_CREATE_VEHICLE, model, pos.x, pos.y, pos.z, h, true, false, false, false, Citizen.ResultAsInteger())
    Citizen.InvokeNative(N_SET_MODEL_NO_LONGER, model)
    if veh == 0 or not bool(Citizen.InvokeNative(N_DOES_ENTITY_EXIST, veh)) then return say('CreateVehicle(cart01) returned no entity') end
    Citizen.InvokeNative(N_SET_PED_INTO_VEHICLE, ped, veh, -1) -- seat -1 = driver
    say(('spawned cart01 (entity %d), you are in the driver seat. Now run /spk_wheel or /spk_chase.'):format(veh))
end

local broken = nil -- vehicle we broke, so "fix" can undo the speed change

RegisterNetEvent('spk_wheel:run', function(arg)
    if arg == 'wagon' then return spawnWagon() end
    local ped = Citizen.InvokeNative(N_PLAYER_PED_ID, Citizen.ResultAsInteger())
    local veh = Citizen.InvokeNative(N_GET_VEHICLE_PED_IS_IN, ped, false, Citizen.ResultAsInteger())
    if not bool(Citizen.InvokeNative(N_DOES_ENTITY_EXIST, veh)) or veh == 0 then
        return say('not in a vehicle/wagon (get in a wagon first)')
    end
    local draft = bool(Citizen.InvokeNative(N_IS_DRAFT_VEHICLE, veh))
    say(('vehicle %d draft=%s speed=%.1f'):format(veh, tostring(draft), speed(veh)))
    say('before: anyDestroyed=' .. tostring(bool(Citizen.InvokeNative(N_ANY_WHEELS_DESTROYED, veh))) .. ' | ' .. wheelState(veh))

    if arg == 'fix' then
        Citizen.InvokeNative(N_SET_FIXED, veh)
        Citizen.InvokeNative(N_MODIFY_TOP_SPEED, veh, 0.0)
        broken = nil
        Wait(500)
        say('SET_VEHICLE_FIXED called. after: anyDestroyed=' .. tostring(bool(Citizen.InvokeNative(N_ANY_WHEELS_DESTROYED, veh))) .. ' | ' .. wheelState(veh))
        return
    end

    local wheel = tonumber(arg) or 0
    Citizen.InvokeNative(N_SET_WHEELS_CAN_BREAK, veh, true)
    if arg == 'alt' or not draft then
        Citizen.InvokeNative(N_BREAK_OFF_VEHICLE_WHEEL, veh, wheel)
        say('called _BREAK_OFF_VEHICLE_WHEEL wheel ' .. wheel)
    else
        Citizen.InvokeNative(N_BREAK_OFF_DRAFT_WHEEL, veh, wheel, 1000.0)
        say('called _BREAK_OFF_DRAFT_WHEEL wheel ' .. wheel)
    end
    -- slowdown: MODIFY_VEHICLE_TOP_SPEED semantics on RDR3 unverified (GTA5: percent). Log speed to judge.
    Citizen.InvokeNative(N_MODIFY_TOP_SPEED, veh, -50.0)
    broken = veh
    Wait(1000)
    say('after: anyDestroyed=' .. tostring(bool(Citizen.InvokeNative(N_ANY_WHEELS_DESTROYED, veh))) .. ' | ' .. wheelState(veh) .. (' | speed=%.1f'):format(speed(veh)))
    say('Look at the wagon: did a wheel visibly come off? Try other indexes: /spk_wheel 1, 2, 3 (index->wheel map unknown). Is it slower?')
end)

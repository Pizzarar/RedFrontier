-- fh_cargo client (R2): applies the server's wagon wheel state. The server decides everything; this only
-- (a) caps the wagon speed, (b) when the server says native=true (fh_spike_gated=false) breaks the wheel.
-- Natives are by hash (same as [spikes]/spk_wheel, spike S3, UNVERIFIED until its RESULT): see spk_wheel/client.lua.
local N_BREAK_OFF_DRAFT_WHEEL = 0xC372B6A88F6E4AD8 -- (vehicle, wheelIndex, force)
local N_SET_FIXED = 0x79811282A9D1AE56             -- SET_VEHICLE_FIXED(vehicle)
local N_MODIFY_TOP_SPEED = 0x35AD938C74CACD6A      -- MODIFY_VEHICLE_TOP_SPEED(vehicle, value)

local capped = {} -- [netId] = speed limit m/s while broken

RegisterNetEvent('fh:cargo:wheel_state', function(st)
    if type(st) ~= 'table' or type(st.netId) ~= 'number' then return end
    local veh = NetworkGetEntityFromNetworkId(st.netId)
    if not veh or veh == 0 or not DoesEntityExist(veh) then return end
    if st.broken then
        capped[st.netId] = tonumber(st.speedLimit)
        if st.native then Citizen.InvokeNative(N_BREAK_OFF_DRAFT_WHEEL, veh, 0, 1000.0) end
    else
        capped[st.netId] = nil
        Citizen.InvokeNative(N_SET_FIXED, veh) -- TODO(spk_wheel RESULT): confirm this restores a native-broken wheel
    end
end)

-- Cap the speed of a broken wagon. TODO(natives): MODIFY_VEHICLE_TOP_SPEED semantics unverified; fall back to
-- SetEntityMaxSpeed if it does not bite.
CreateThread(function()
    while true do
        Wait(250)
        for netId, limit in pairs(capped) do
            local veh = NetworkGetEntityFromNetworkId(netId)
            if veh and veh ~= 0 and DoesEntityExist(veh) and limit then
                Citizen.InvokeNative(N_MODIFY_TOP_SPEED, veh, limit)
            end
        end
    end
end)

-- TODO(R2 off-road): detect road vs off-road with a verified native, then TriggerServerEvent('fh:cargo:offroad_hint', bool).
-- Until then the hint is never sent and the server treats every wagon as on-road.

-- fh_cargo client (R2): applies the server's wagon wheel state. The server decides everything; this only
-- (a) caps the wagon speed, (b) when the server says native=true (fh_spike_gated=false) breaks the wheel.
-- Natives are by hash (same as [spikes]/spk_wheel, spike S3, UNVERIFIED until its RESULT): see spk_wheel/client.lua.
local N_BREAK_OFF_DRAFT_WHEEL = 0xC372B6A88F6E4AD8 -- (vehicle, wheelIndex, force)
local N_SET_FIXED = 0x79811282A9D1AE56             -- SET_VEHICLE_FIXED(vehicle)
local N_MODIFY_TOP_SPEED = 0x35AD938C74CACD6A      -- MODIFY_VEHICLE_TOP_SPEED(vehicle, value)

local capped = {} -- [netId] = speed limit m/s while broken

RegisterNetEvent('fh:cargo:wheel_state', function(st)
    if type(st) ~= 'table' or type(st.netId) ~= 'number' then return end
    local plan = FhCargoRules.clientWheelPlan(st)
    capped[st.netId] = plan.cap -- nil on repair/clear: no leaked entry
    local veh = NetworkGetEntityFromNetworkId(st.netId)
    if not veh or veh == 0 or not DoesEntityExist(veh) then return end
    if plan.breakNative then Citizen.InvokeNative(N_BREAK_OFF_DRAFT_WHEEL, veh, 0, 1000.0) end
    -- SET_VEHICLE_FIXED only on the ungated native path (it would also touch unrelated damage when gated).
    if plan.fixNative then Citizen.InvokeNative(N_SET_FIXED, veh) end -- TODO(spk_wheel RESULT): confirm it restores a native-broken wheel
    -- Undo the break's speed cap. TODO(natives): 0.0 as "no modifier" is unverified (same as the cap itself).
    if plan.resetCap then Citizen.InvokeNative(N_MODIFY_TOP_SPEED, veh, 0.0) end
end)

-- Cap the speed of a broken wagon. TODO(natives): MODIFY_VEHICLE_TOP_SPEED semantics unverified; fall back to
-- SetEntityMaxSpeed if it does not bite.
CreateThread(function()
    while true do
        Wait(250)
        for netId, limit in pairs(capped) do
            local veh = NetworkGetEntityFromNetworkId(netId)
            if veh and veh ~= 0 and DoesEntityExist(veh) then
                if limit then Citizen.InvokeNative(N_MODIFY_TOP_SPEED, veh, limit) end
            else
                capped[netId] = nil -- wagon deleted/despawned: drop the entry (assigning nil to a visited key is safe)
            end
        end
    end
end)

-- TODO(R2 off-road): detect road vs off-road with a verified native, then TriggerServerEvent('fh:cargo:offroad_hint', bool).
-- Until then the hint is never sent and the server treats every wagon as on-road.

AddEventHandler('onClientResourceStop', function(res)
    if res == GetCurrentResourceName() then capped = {} end
end)

-- ---------------------------------------------------------------- R17 / ui-inbox-03 I3: wagon yard (fh_ui `wagonyard`)
-- /wagonpost asks the server to open the fh_ui `wagonyard` screen; the server checks the player stands in a trade post
-- (exports.fh_trade:nearestPost) and opens/updates the screen. All actions relay through fh_ui (fh:cargo:ui_buy/call/stow).
RegisterCommand('wagonpost', function() TriggerServerEvent('fh:cargo:menu_open') end, false)

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

-- ---------------------------------------------------------------- R17: wagon post menu (ox_lib stopgap, @ui screen later)
-- /wagonpost asks the server for the menu; the server checks the player stands in a trade post and replies with the rows.
-- Every action goes back as { action, tier } only: post, region, ownership and price are all decided server-side.
local MSG = {
    fh_not_at_post = 'Stand at a trade post first.', fh_not_owned = 'You do not own that wagon.',
    fh_wagon_live = 'You already have a wagon out. Stow it first.', fh_no_wagon = 'You have no wagon out.',
    fh_wagon_far = 'Your wagon is too far from the post.', fh_wagon_not_ready = 'Your wagon is still arriving.',
    fh_busy = 'One moment...', fh_buy_busy = 'One moment...', fh_already_owned = 'You already own that wagon.',
    fh_locked = 'You have not earned that wagon yet.', fh_db_error = 'The wagon ledger is unavailable.',
}

RegisterCommand('wagonpost', function() TriggerServerEvent('fh:cargo:menu_open') end, false)

local function act(action, tier) TriggerServerEvent('fh:cargo:menu_action', { action = action, tier = tier }) end

RegisterNetEvent('fh:cargo:menu', function(data)
    if type(data) ~= 'table' or type(data.tiers) ~= 'table' then return end
    local buy, call = {}, {}
    for _, t in ipairs(data.tiers) do
        local price = tonumber(t.price) or 0
        if t.owned then
            call[#call + 1] = { title = ('Call %s'):format(tostring(t.label)), icon = 'horse',
                onSelect = function() act('call', t.key) end }
        end
        buy[#buy + 1] = {
            title = ('%s%s'):format(tostring(t.label), t.owned and ' (owned)' or ''),
            description = t.owned and 'Owned' or (t.locked and ('Locked: ' .. tostring(t.reason)) or ('$' .. price)),
            disabled = t.owned == true or t.locked == true,
            onSelect = function() act('buy', t.key) end,
        }
    end
    local opts = {
        { title = 'Buy a wagon', menu = 'fh_cargo_buy', icon = 'coins' },
        { title = 'Stow my wagon', icon = 'warehouse', disabled = data.live == nil, onSelect = function() act('stow') end },
    }
    for i, c in ipairs(call) do c.disabled = data.live ~= nil; table.insert(opts, i, c) end -- keeps t1,t2,t3 order above Buy/Stow
    lib.registerContext({ id = 'fh_cargo_buy', title = 'Buy a wagon', menu = 'fh_cargo_post', options = buy })
    lib.registerContext({ id = 'fh_cargo_post', title = tostring(data.post and data.post.label or 'Wagons'), options = opts })
    lib.showContext('fh_cargo_post')
end)

RegisterNetEvent('fh:cargo:menu_result', function(r)
    if type(r) ~= 'table' then return end
    if r.ok then
        lib.notify({ title = 'Wagons', type = 'success', description = ({ buy = 'Wagon bought.', call = 'Wagon on its way.',
            stow = 'Wagon stowed. Cargo kept.' })[r.action] or 'Done.' })
    else
        local e = tostring(r.err)
        lib.notify({ title = 'Wagons', type = 'error', description = MSG[e] or e })
    end
end)

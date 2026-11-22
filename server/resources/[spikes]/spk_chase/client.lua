-- spk_chase client: spawn 3 hostile mounted riders behind the player's wagon, pursue + shoot for 60s,
-- log each rider's distance to the wagon every 5s and flag stalls (>60m) and bunching (<3m apart).
local Cfg = {
    riderModel = 'g_m_m_unibanditos_01',  -- GUESS (model, not a native)
    horseModel = 'a_c_horse_morgan_bay',  -- GUESS (model, not a native)
    weapon = 'WEAPON_REPEATER_CARBINE',   -- GUESS
    count = 3,
    spawnBehind = 40.0,
    duration = 60000,
    tick = 5000,
    stallDist = 60.0,
    bunchDist = 3.0,
    closeEnough = 35.0,                   -- beyond this we re-issue "go to wagon" instead of combat
}
local GROUP = joaat('SPK_CHASERS')
local riders, running = {}, false   -- riders = { {ped=, horse=} }

local function note(msg, kind)
    print('[spk_chase] ' .. msg)
    lib.notify({ title = 'spk_chase', description = msg, type = kind or 'inform', duration = 6000 })
end

local function load(model)
    local hash = joaat(model)
    if not IsModelInCdimage(hash) then return nil end
    RequestModel(hash, false)
    local t = GetGameTimer() + 5000
    while not HasModelLoaded(hash) and GetGameTimer() < t do Wait(50) end
    return HasModelLoaded(hash) and hash or nil
end

local function clear()
    running = false
    for _, r in ipairs(riders) do
        for _, e in ipairs({ r.ped, r.horse }) do
            if e and DoesEntityExist(e) then
                SetEntityAsMissionEntity(e, true, true)
                DeleteEntity(e)
            end
        end
    end
    riders = {}
end

local function spawnRider(wagon, i, riderHash, horseHash)
    local off = GetOffsetFromEntityInWorldCoords(wagon, (i - 2) * 4.0, -Cfg.spawnBehind - i * 6.0, 0.0)
    local ok, gz = GetGroundZFor_3dCoord(off.x, off.y, off.z + 20.0, false)
    local z = ok and gz or off.z
    local heading = GetEntityHeading(wagon)
    local horse = CreatePed(horseHash, off.x, off.y, z, heading, true, false, false, false)
    local ped = CreatePed(riderHash, off.x, off.y, z, heading, true, false, false, false)
    if horse == 0 or ped == 0 then return nil end
    Citizen.InvokeNative(0x283978A15512B2FE, horse, true) -- _SET_RANDOM_OUTFIT_VARIATION
    Citizen.InvokeNative(0x283978A15512B2FE, ped, true)
    SetEntityAsMissionEntity(horse, true, true)
    SetEntityAsMissionEntity(ped, true, true)
    SetPedOntoMount(ped, horse, -1, true)
    Wait(300)
    if not IsPedOnMount(ped) then
        print(('[spk_chase] rider %d: SetPedOntoMount did not mount, trying TaskMountAnimal'):format(i))
        TaskMountAnimal(ped, horse, 10000, -1, 1.0, 1, 0, 0)
        Wait(2500)
    end
    AddRelationshipGroup('SPK_CHASERS')
    SetPedRelationshipGroupHash(ped, GROUP)
    SetRelationshipBetweenGroups(5, GROUP, joaat('PLAYER')) -- 5 = hate (guess, GTA convention)
    SetRelationshipBetweenGroups(5, joaat('PLAYER'), GROUP)
    local w = joaat(Cfg.weapon)
    GiveWeaponToPed(ped, w, 200, true, false, 0, false, 0.5, 1.0, 0, false, 0.0, false)
    SetCurrentPedWeapon(ped, w, true, 0, false, false)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedAccuracy(ped, 25)
    SetPedKeepTask(ped, true)
    return { ped = ped, horse = horse }
end

local function pursue(r, wagon, me)
    if #(GetEntityCoords(r.ped) - GetEntityCoords(wagon)) > Cfg.closeEnough then
        TaskGoToEntity(r.ped, wagon, 6000, 12.0, 3.0, 0.0, 0)  -- speed 3.0 ~ gallop (guess)
        return 'goto'
    end
    TaskCombatPed(r.ped, me, 0, 16)
    return 'combat'
end

RegisterNetEvent('spk_chase:clear', function() clear() note('cleared') end)

RegisterNetEvent('spk_chase:run', function()
    if running then return note('already running, use /spk_chase clear', 'error') end
    local me = PlayerPedId()
    if not IsPedInAnyVehicle(me, false) then return note('get in a wagon first (IsPedInAnyVehicle=false)', 'error') end
    local wagon = GetVehiclePedIsIn(me, false)
    note(('vehicle model hash=%s (no native to confirm "is wagon"; assuming it is)'):format(GetEntityModel(wagon)))
    local riderHash, horseHash = load(Cfg.riderModel), load(Cfg.horseModel)
    if not riderHash or not horseHash then
        return note(('model failed (rider=%s horse=%s): fix Cfg models'):format(tostring(riderHash), tostring(horseHash)), 'error')
    end
    running = true
    for i = 1, Cfg.count do
        local r = spawnRider(wagon, i, riderHash, horseHash)
        if r then riders[#riders + 1] = r end
    end
    SetModelAsNoLongerNeeded(riderHash)
    SetModelAsNoLongerNeeded(horseHash)
    note(('spawned %d/%d mounted riders (client-side, networked)'):format(#riders, Cfg.count))

    local stalls, bunches, samples = 0, 0, 0
    local endAt = GetGameTimer() + Cfg.duration
    while running and GetGameTimer() < endAt do
        local modes = {}
        for i, r in ipairs(riders) do
            modes[i] = (DoesEntityExist(r.ped) and not IsPedDeadOrDying(r.ped, false)) and pursue(r, wagon, me) or 'dead'
        end
        Wait(Cfg.tick)
        if not running then break end
        samples = samples + 1
        local wp, parts, flags = GetEntityCoords(wagon), {}, {}
        for i, r in ipairs(riders) do
            if DoesEntityExist(r.ped) then
                local d = #(GetEntityCoords(r.ped) - wp)
                local mount = IsPedOnMount(r.ped) and 'mounted' or 'UNMOUNTED'
                parts[#parts + 1] = ('R%d %.0fm %s %s spd=%.1f'):format(i, d, mount, modes[i], GetEntitySpeed(r.horse))
                if d > Cfg.stallDist then flags[#flags + 1] = ('STALL R%d'):format(i); stalls = stalls + 1 end
                for j = i + 1, #riders do
                    if DoesEntityExist(riders[j].ped) and #(GetEntityCoords(r.ped) - GetEntityCoords(riders[j].ped)) < Cfg.bunchDist then
                        flags[#flags + 1] = ('BUNCH R%d-R%d'):format(i, j); bunches = bunches + 1
                    end
                end
            end
        end
        note(('t=%ds | %s | %s'):format(samples * Cfg.tick // 1000, table.concat(parts, ' | '), #flags > 0 and table.concat(flags, ',') or 'ok'), #flags > 0 and 'warning' or 'inform')
    end
    if running then
        note(('DONE: %d samples, %d stall flags, %d bunch flags. Judge: GO if ~0 of each. Riders left alive; /spk_chase clear to remove.'):format(samples, stalls, bunches), 'success')
    end
    running = false
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then clear() end
end)

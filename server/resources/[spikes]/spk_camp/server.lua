-- spk_camp server: holds camp state, guards against dupes, keeps entities alive.
-- FINDING (fxserver source, ServerSetters.cpp is wrapped in #ifndef STATE_RDR3): server-side CreatePed /
-- CreateObjectNoOffset are probably NOT compiled into RedM. We try them in a pcall; if they fail we fall
-- back to "server decides, one client creates networked entities, server adopts them".

local camp = { state = 'none', ents = {} } -- state: none | building | built ; ents = { {netId, kind, model} }
local buildDeadline = 0

local function say(src, msg)
    print(('[spk_camp] %s'):format(msg))
    if src and src > 0 then
        TriggerClientEvent('ox_lib:notify', src, { title = 'spk_camp', description = msg, type = 'inform', duration = 8000 })
    end
end

local function entOf(netId)
    local e = NetworkGetEntityFromNetworkId(netId)
    if e and e ~= 0 and DoesEntityExist(e) then return e end
    return nil
end

local function liveCount()
    local n = 0
    for _, r in ipairs(camp.ents) do if entOf(r.netId) then n = n + 1 end end
    return n
end

local function syncAll(target)
    local ids = {}
    for _, r in ipairs(camp.ents) do if r.kind == 'ped' then ids[#ids + 1] = r.netId end end
    TriggerClientEvent('spk_camp:sync', target or -1, ids)
end

-- Try real server-side spawn of ONE ped to learn whether the native exists on this build.
local function tryServerSpawn(center)
    local ok, ped = pcall(CreatePed, 0, joaat(Config.pedModel), center.x, center.y, center.z, 0.0, true, false)
    if ok and ped and ped ~= 0 and DoesEntityExist(ped) then return ped end
    return nil, ok and 'CreatePed returned 0' or tostring(ped)
end

-- Probe server-side CreateVehicle (wagon). Expected FAILED on RedM (CREATE_VEHICLE_SERVER_SETTER is inside
-- #ifndef STATE_RDR3 in ServerSetters.cpp). Probe vehicle is deleted at once and never joins camp state.
local function probeVehicle(src, center)
    local model = 'cart01' -- verified in femga/rdr3_discoveries vehicles/vehicles_list.lua (0xCEDED274)
    local ok, veh = pcall(CreateVehicle, joaat(model), center.x, center.y, center.z, 0.0, true, false)
    if ok and veh and veh ~= 0 and DoesEntityExist(veh) then
        local netId = NetworkGetNetworkIdFromEntity(veh)
        DeleteEntity(veh)
        return say(src, ('server CreateVehicle(%s): OK netId=%s'):format(model, tostring(netId)))
    end
    say(src, ('server CreateVehicle(%s): FAILED: %s'):format(model, ok and 'CreateVehicle returned 0' or tostring(veh)))
end

local function adopt(netId, kind, model)
    local e = entOf(netId)
    if not e then return false end
    SetEntityOrphanMode(e, 2) -- 2 = KeepEntity: server won't delete it when the owner leaves
    camp.ents[#camp.ents + 1] = { netId = netId, kind = kind, model = model }
    return true
end

local function spawn(src)
    if camp.state == 'built' and liveCount() > 0 then
        return say(src, ('camp already exists (%d entities). Use /spk_camp status or clear.'):format(liveCount()))
    end
    if camp.state == 'building' and GetGameTimer() < buildDeadline then
        return say(src, 'camp is being built, wait.')
    end
    camp = { state = 'building', ents = {} }
    buildDeadline = GetGameTimer() + 20000

    local ped = GetPlayerPed(src)
    local pos, h = GetEntityCoords(ped), GetEntityHeading(ped)
    local rad = math.rad(h)
    local center = vector3(pos.x - math.sin(rad) * Config.distance, pos.y + math.cos(rad) * Config.distance, pos.z)

    local probe, why = tryServerSpawn(center)
    probeVehicle(src, center)
    if probe then
        say(src, 'server-side CreatePed WORKS on this build; spawning camp from server.')
        adopt(NetworkGetNetworkIdFromEntity(probe), 'ped', Config.pedModel)
        for _ = 2, Config.pedCount do
            local p = CreatePed(0, joaat(Config.pedModel), center.x + math.random(-3, 3), center.y + math.random(-3, 3), center.z, math.random(0, 359) + 0.0, true, false)
            adopt(NetworkGetNetworkIdFromEntity(p), 'ped', Config.pedModel)
        end
        for i = 1, math.min(3, #Config.propModels) do
            local ok, o = pcall(CreateObjectNoOffset, joaat(Config.propModels[i]), center.x + i * 2.0, center.y, center.z, true, false, false)
            if ok and o and o ~= 0 then adopt(NetworkGetNetworkIdFromEntity(o), 'prop', Config.propModels[i]) end
        end
        camp.state = 'built'
        syncAll()
        return say(src, ('built %d entities server-side. Weapons/hostility are client natives: the owner client arms them.'):format(#camp.ents))
    end

    say(src, ('server-side CreatePed unavailable (%s). Fallback: your client creates networked entities, server adopts + sets orphan mode.'):format(why))
    TriggerClientEvent('spk_camp:build', src, center)
end

RegisterNetEvent('spk_camp:built', function(list)
    local src = source
    if camp.state ~= 'building' then return print('[spk_camp] ignoring spk_camp:built, state=' .. camp.state) end
    if type(list) ~= 'table' then list = {} end
    Wait(500) -- let OneSync register the new netIds
    for _, r in ipairs(list) do
        if type(r) == 'table' and (r.kind == 'ped' or r.kind == 'prop') and not adopt(r.netId, r.kind, r.model) then
            print(('[spk_camp] netId %s from client does NOT exist server-side'):format(tostring(r.netId)))
        end
    end
    camp.state = (#camp.ents > 0) and 'built' or 'none'
    syncAll()
    say(src, ('camp adopted by server: %d of %d reported entities exist server-side.'):format(#camp.ents, #list))
end)

RegisterNetEvent('spk_camp:requestSync', function() syncAll(source) end)

local function status(src)
    say(src, ('camp state=%s, tracked=%d, existing=%d'):format(camp.state, #camp.ents, liveCount()))
    for _, r in ipairs(camp.ents) do
        local e = entOf(r.netId)
        local line
        if e then
            local hp = GetEntityHealth(e)
            local dead = (r.kind == 'ped') and (hp <= 0)
            line = ('netId=%d %s %s exists=true owner=%s hp=%s %s'):format(r.netId, r.kind, r.model, tostring(NetworkGetEntityOwner(e)), tostring(hp), dead and 'DEAD' or 'alive')
        else
            line = ('netId=%d %s %s exists=false'):format(r.netId, r.kind, r.model)
        end
        say(src, line)
    end
end

local function clear(src)
    for _, r in ipairs(camp.ents) do
        local e = entOf(r.netId)
        if e then DeleteEntity(e) end
    end
    camp = { state = 'none', ents = {} }
    syncAll()
    say(src, 'camp cleared.')
end

lib.addCommand('spk_camp', {
    help = 'spk_camp [status|clear]: spawn the test outlaw camp 30m ahead',
    params = { { name = 'action', type = 'string', optional = true } },
}, function(src, args)
    if args.action == 'status' then return status(src) end
    if args.action == 'clear' then return clear(src) end
    if src == 0 then return print('[spk_camp] spawn must be run in-game (needs a player position)') end
    spawn(src)
end)

AddEventHandler('playerJoining', function() syncAll(source) end)

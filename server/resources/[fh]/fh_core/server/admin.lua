-- fh_core admin commands (ox_lib lib.addCommand, restricted to group.admin). Arg parsing lives in shared/admin_args.lua.
-- Natives used: GetPlayerPed, GetEntityCoords, SetEntityCoords, GetEntityHeading (see docs/natives.md). Not runtime-tested yet (no Cfx key).
-- Spawn commands go through the spawn-request contract (server/spawn.lua): server CreatePed/CreateVehicle are compiled
-- out on RDR3. Wagons stay out of scope until M4.

local function reply(src, msg)
    if src == 0 then print('[fh_core] ' .. msg) else TriggerClientEvent('chat:addMessage', src, { args = { 'fh', msg } }) end
end

-- lib.addCommand without `params` leaves `args` empty and gives the raw line ("fh_give 1 bread 2"): split it here so
-- the parsers (and their error codes) stay in shared/admin_args.lua.
local function split(raw)
    local out = {}
    for tok in tostring(raw or ''):gmatch('%S+') do out[#out + 1] = tok end
    table.remove(out, 1) -- command name
    return out
end

local function targetPed(id)
    local ped = GetPlayerPed(id)
    if ped == 0 then return nil end
    return ped
end

-- ---------------------------------------------------------------- world-03 J: walk tooling (fh_tp place ids, fh_tour, fh_mark)
-- Cached place index (FhPlaceResolver.index) over FhRegions + the `@`-included lane configs (see fxmanifest).
local walkPlaces, walkById
local function walkIndex()
    if not walkPlaces then
        walkPlaces, walkById = FhPlaceResolver.index(FhRegions, { homestead = FhHomesteadConfig, zones = FhZonesConfig })
    end
    return walkPlaces, walkById
end

-- world-04 M: ids in tour messages for admins / fh_dev (server-decided in access.lua, exports.fh_core:canSeeIds).
local function idTag(src, place)
    local ok, show = pcall(function() return exports.fh_core:canSeeIds(src) end)
    return FhPlaceResolver.idTag(place, ok and show == true)
end

local tours = {} -- [src] = { region, order, index }

AddEventHandler('playerDropped', function()
    tours[tonumber(source)] = nil
end)

-- Teleport src to a place's z-hint, then ask that client to ground-snap (fh:tp:snap, client/ground_snap.lua).
-- Sends kind/class/verified so the client picks the right probe depth (tight for town lots and verified places).
-- Returns false when src has no ped (the caller replies with its own fh_no_player prefix).
local function teleportPlace(src, place)
    local ped = targetPed(src)
    if not ped then return false end
    SetEntityCoords(ped, place.x, place.y, place.z, false, false, false, false)
    TriggerClientEvent('fh:tp:snap', src, {
        id = place.id, x = place.x, y = place.y, z = place.z,
        kind = place.kind, class = place.class, verified = place.verified,
    })
    return true
end

lib.addCommand('fh_give', {
    help = 'Give an item via the container API: fh_give <id> <item> [count]',
    restricted = 'group.admin',
}, function(src, args, raw)
    local p, err = FhAdminArgs.parseGive(split(raw), function(n) return FhItems.resolve(n) ~= nil end)
    if not p then return reply(src, 'fh_give: ' .. err) end
    local ped = targetPed(p.target)
    if not ped then return reply(src, 'fh_give: fh_no_player') end
    local bag, why = exports.fh_core:createDropBag(GetEntityCoords(ped), { { name = p.item, amount = p.count, info = {} } },
        { label = 'admin give' })
    if not bag then return reply(src, 'fh_give: ' .. tostring(why)) end
    local ok, moved, leftovers = exports.fh_core:transferAll({ type = 'drop_bag', id = bag },
        { type = 'backpack', id = p.target }, p.target)
    if not ok then return reply(src, ('fh_give: %s (items left in drop %s)'):format(tostring(moved), bag)) end
    local movedN, leftN = 0, 0
    for _, m in ipairs(type(moved) == 'table' and moved or {}) do movedN = movedN + (tonumber(m.amount) or 0) end
    for _, l in ipairs(type(leftovers) == 'table' and leftovers or {}) do leftN = leftN + (tonumber(l.amount) or 0) end
    reply(src, ('fh_give: gave %dx %s to %d (of %d requested)%s'):format(movedN, p.item, p.target, p.count,
        leftN > 0 and (', %d did not fit and remain in drop %s'):format(leftN, bag) or ''))
end)

lib.addCommand('fh_heat', {
    help = 'Set heat (0-100): fh_heat <id> <faction> <value> (fh_heat <id> <value> = stub when fh_heat is not running)',
    restricted = 'group.admin',
}, function(src, args, raw)
    local p, err = FhAdminArgs.parseHeat(split(raw))
    if not p then return reply(src, 'fh_heat: ' .. err) end
    if GetResourceState('fh_heat') == 'started' then
        -- Delegate to fh_heat (roads lane): set(src, faction, value) -> true, new | false, err.
        if not p.faction then return reply(src, 'fh_heat: fh_bad_faction (usage: fh_heat <id> <faction> <value>)') end
        local okCall, ok, res = pcall(function() return exports.fh_heat:set(p.target, p.faction, p.value) end)
        if not okCall then return reply(src, 'fh_heat: fh_heat_unavailable') end
        if not ok then return reply(src, 'fh_heat: ' .. tostring(res)) end
        return reply(src, ('fh_heat: set %d %s to %s'):format(p.target, p.faction, tostring(res)))
    end
    reply(src, ('fh_heat: heat stub (fh_heat not started), would set %d%s to %s'):format(p.target,
        p.faction and (' ' .. p.faction) or '', p.value))
end)

lib.addCommand('fh_tp', {
    help = 'Teleport yourself: fh_tp <x> <y> <z> | fh_tp <id> | fh_tp <placeId>',
    restricted = 'group.admin',
}, function(src, args, raw)
    if src == 0 then return reply(src, 'fh_tp: in-game only') end
    local p, err = FhAdminArgs.parseTp(split(raw))
    if not p then return reply(src, 'fh_tp: ' .. err) end
    if p.place then
        local _, byId = walkIndex()
        local place = byId[p.place]
        if not place then return reply(src, 'fh_tp: fh_unknown_place') end
        if not teleportPlace(src, place) then return reply(src, 'fh_tp: fh_no_player') end
        return reply(src, ('fh_tp: moved to %s (%s) %.0f %.0f %.0f'):format(place.label or place.id, place.kind,
            place.x, place.y, place.z))
    end
    local c = p.coords
    if p.target then
        local tped = targetPed(p.target)
        if not tped then return reply(src, 'fh_tp: fh_no_player') end
        c = GetEntityCoords(tped)
    end
    local ped = targetPed(src)
    if not ped then return reply(src, 'fh_tp: fh_no_player') end
    SetEntityCoords(ped, c.x, c.y, c.z, false, false, false, false)
    reply(src, ('fh_tp: moved to %.1f %.1f %.1f'):format(c.x, c.y, c.z))
end)

lib.addCommand('fh_tour', {
    help = 'Tour a region\'s unverified places: fh_tour <region> | fh_tour next',
    restricted = 'group.admin',
}, function(src, args, raw)
    if src == 0 then return reply(src, 'fh_tour: in-game only') end
    local p, err = FhAdminArgs.parseTour(split(raw))
    if not p then return reply(src, 'fh_tour: ' .. err) end
    if p.next then
        local t = tours[src]
        if not t then return reply(src, 'fh_tour: no active tour (start one with fh_tour <region>)') end
        local place = FhPlaceResolver.advanceTour(t)
        if not place then
            tours[src] = nil
            return reply(src, ('fh_tour: %s complete (%d places)'):format(t.region, #t.order))
        end
        if not teleportPlace(src, place) then return reply(src, 'fh_tour: fh_no_player') end
        return reply(src, ('fh_tour: %d/%d %s%s (%s)'):format(t.index, #t.order, place.label or place.id, idTag(src, place), place.kind))
    end
    if not FhRegions.getRegion(p.region) then return reply(src, 'fh_tour: fh_unknown_region') end
    local order = FhPlaceResolver.tour(walkIndex(), p.region)
    if #order == 0 then return reply(src, ('fh_tour: %s has no unverified places'):format(p.region)) end
    tours[src] = { region = p.region, order = order, index = 1 }
    if not teleportPlace(src, order[1]) then return reply(src, 'fh_tour: fh_no_player') end
    reply(src, ('fh_tour: %s — 1/%d %s%s (%s) [fh_tour next]'):format(p.region, #order, order[1].label or order[1].id,
        idTag(src, order[1]), order[1].kind))
end)

lib.addCommand('fh_mark', {
    help = 'Mark the nearest place within 30 m: fh_mark ok|bad [note]',
    restricted = 'group.admin',
}, function(src, args, raw)
    if src == 0 then return reply(src, 'fh_mark: in-game only') end
    local p, err = FhAdminArgs.parseMark(split(raw))
    if not p then return reply(src, 'fh_mark: ' .. err) end
    local ped = targetPed(src)
    if not ped then return reply(src, 'fh_mark: fh_no_player') end
    local here = FhSpawnRules.readCoords(GetEntityCoords(ped))
    local place, dist = FhPlaceResolver.nearest(walkIndex(), here, 30)
    if not place then return reply(src, 'fh_mark: no place within 30 m') end
    local record = FhPlaceResolver.markRecord(place, p.verdict, p.note, here, os.time(), src)
    local saved, werr = FhPlaceResolver.recordWalkMark({
        load = function() return LoadResourceFile(GetCurrentResourceName(), 'world_walk.json') end,
        save = function(s) SaveResourceFile(GetCurrentResourceName(), 'world_walk.json', s, -1) end,
        encode = json.encode, decode = json.decode,
    }, record)
    if not saved then return reply(src, 'fh_mark: ' .. tostring(werr)) end
    reply(src, ('fh_mark: %s %s (%s) at %.0f %.0f %.0f%s'):format(place.id, p.verdict, place.kind, here.x, here.y,
        here.z, dist and (' — %d m'):format(math.floor(dist + 0.5)) or ''))
end)

lib.addCommand('fh_dump', {
    help = 'Print a container snapshot: fh_dump <containerType> <id>',
    restricted = 'group.admin',
}, function(src, args, raw)
    local p, err = FhAdminArgs.parseDump(split(raw), FhContainers)
    if not p then return reply(src, 'fh_dump: ' .. err) end
    local items, why = exports.fh_core:snapshot(p.ref)
    if not items then return reply(src, 'fh_dump: ' .. tostring(why)) end
    print(('[fh_core] fh_dump %s %s: %s'):format(p.ref.type, tostring(p.ref.id), json.encode(items)))
    local stacks = 0
    for _ in pairs(items) do stacks = stacks + 1 end
    reply(src, ('fh_dump: %d stack(s), full JSON in server console'):format(stacks))
end)

-- fh_spawn_horse / fh_spawn_ped [model]: 2 m in front of the caller, through FhSpawn.requestSpawn (server/spawn.lua).
local function spawnCommand(kind)
    return function(src, args, raw)
        local name = 'fh_spawn_' .. kind
        if src == 0 then return reply(src, name .. ': in-game only') end
        local p, err = FhAdminArgs.parseSpawn(split(raw), kind)
        if not p then return reply(src, name .. ': ' .. err) end
        local ped = targetPed(src)
        if not ped then return reply(src, name .. ': fh_no_player') end
        local here = FhSpawnRules.readCoords(GetEntityCoords(ped))
        local heading = GetEntityHeading(ped)
        local id, why = FhSpawn.requestSpawn({
            kind = kind, model = p.model, coords = FhSpawnRules.offsetForward(here, heading, 2.0), heading = heading,
            owner = { kind = 'admin', id = src }, tag = 'admin:' .. kind,
        }, {
            onReady = function(netId, requestId)
                reply(src, ('%s: request %d ready, netId %d (fh_despawn %d)'):format(name, requestId, netId, requestId))
            end,
            onFailed = function(reason, requestId)
                reply(src, ('%s: request %d failed: %s'):format(name, requestId, tostring(reason)))
            end,
        })
        if not id then return reply(src, name .. ': ' .. tostring(why)) end
        reply(src, ('%s: request %d sent (%s)'):format(name, id, p.model))
    end
end

lib.addCommand('fh_spawn_horse', {
    help = 'Spawn a horse in front of you via the spawn-request contract: fh_spawn_horse [model]',
    restricted = 'group.admin',
}, spawnCommand('horse'))

lib.addCommand('fh_spawn_ped', {
    help = 'Spawn a ped in front of you via the spawn-request contract: fh_spawn_ped [model]',
    restricted = 'group.admin',
}, spawnCommand('ped'))

lib.addCommand('fh_despawn', {
    help = 'Despawn a spawn request: fh_despawn <requestId>',
    restricted = 'group.admin',
}, function(src, args, raw)
    local p, err = FhAdminArgs.parseDespawn(split(raw))
    if not p then return reply(src, 'fh_despawn: ' .. err) end
    local ok, why = FhSpawn.despawn(p.requestId)
    if not ok then return reply(src, 'fh_despawn: ' .. tostring(why)) end
    reply(src, ('fh_despawn: request %d despawned'):format(p.requestId))
end)

lib.addCommand('fh_where', {
    help = 'Print your current coords and heading: fh_where',
    restricted = 'group.admin',
}, function(src)
    if src == 0 then return reply(src, 'fh_where: in-game only') end
    local ped = targetPed(src)
    if not ped then return reply(src, 'fh_where: fh_no_player') end
    local c = GetEntityCoords(ped)
    local h = GetEntityHeading(ped)
    local line = ('fh_where: vector3(%.2f, %.2f, %.2f) heading=%.1f'):format(c.x, c.y, c.z, h or 0.0)
    print('[fh_core] ' .. line)
    reply(src, line)
end)

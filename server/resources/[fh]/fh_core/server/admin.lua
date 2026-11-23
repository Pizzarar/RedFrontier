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
    help = 'Teleport yourself: fh_tp <x> <y> <z> | fh_tp <id>',
    restricted = 'group.admin',
}, function(src, args, raw)
    if src == 0 then return reply(src, 'fh_tp: in-game only') end
    local p, err = FhAdminArgs.parseTp(split(raw))
    if not p then return reply(src, 'fh_tp: ' .. err) end
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

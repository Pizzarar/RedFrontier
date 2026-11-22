-- fh_core admin commands (ox_lib lib.addCommand, restricted to group.admin). Arg parsing lives in shared/admin_args.lua.
-- Natives used: GetPlayerPed, GetEntityCoords, SetEntityCoords (see docs/natives.md). Not runtime-tested yet (no Cfx key).
-- TODO(B4c): spawn wagon/horse commands go through the spawn-request contract; server CreatePed/CreateVehicle are
-- compiled out on RDR3.

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
    local p, err = FhAdminArgs.parseGive(split(raw), function(n) return FhItems.definition(n) ~= nil end)
    if not p then return reply(src, 'fh_give: ' .. err) end
    local ped = targetPed(p.target)
    if not ped then return reply(src, 'fh_give: fh_no_player') end
    local bag, why = exports.fh_core:createDropBag(GetEntityCoords(ped), { { name = p.item, amount = p.count, info = {} } },
        { label = 'admin give' })
    if not bag then return reply(src, 'fh_give: ' .. tostring(why)) end
    local ok, moved, leftovers = exports.fh_core:transferAll({ type = 'drop_bag', id = bag },
        { type = 'backpack', id = p.target }, p.target)
    if not ok then return reply(src, ('fh_give: %s (items left in drop %s)'):format(tostring(moved), bag)) end
    local left = leftovers and #leftovers or 0
    reply(src, ('fh_give: gave %dx %s to %d%s'):format(p.count, p.item, p.target,
        left > 0 and (', ' .. left .. ' stack(s) did not fit and remain in drop ' .. bag) or ''))
end)

lib.addCommand('fh_heat', {
    help = 'Set heat (stub, 0-100): fh_heat <id> <value>',
    restricted = 'group.admin',
}, function(src, args, raw)
    local p, err = FhAdminArgs.parseHeat(split(raw))
    if not p then return reply(src, 'fh_heat: ' .. err) end
    -- TODO(fh_zones): apply heat for real; no DB yet.
    reply(src, ('fh_heat: heat stub, would set %d to %s'):format(p.target, p.value))
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

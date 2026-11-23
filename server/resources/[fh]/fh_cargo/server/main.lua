-- fh_cargo server (spec L6, M4): wagon tiers, cargo loading, fast-travel veto. Thin: every decision is in
-- shared/cargo_rules.lua (specced); this file gathers facts and calls fh_core exports. fh_core is not edited.
-- Natives used: GetPlayerPed, GetEntityCoords, GetEntityHeading, NetworkGetEntityFromNetworkId, DoesEntityExist
-- (see fh_core/docs/natives.md). NOT runtime-tested (no Cfx key yet).
local rules = FhCargoRules
local cfg = FhCargoConfig

-- wagons[wagonId] = { id, owner = citizenid, tier = 't1'.., requestId, netId, ready }
local wagons = {}

local function core() return exports['rsg-core']:GetCoreObject() end

local function citizenidOf(src)
    local p = core().Functions.GetPlayer(src)
    return p and p.PlayerData.citizenid or nil
end

local function reply(src, msg)
    if src == 0 then print('[fh_cargo] ' .. msg) else TriggerClientEvent('chat:addMessage', src, { args = { 'fh', msg } }) end
end

local function split(raw)
    local out = {}
    for tok in tostring(raw or ''):gmatch('%S+') do out[#out + 1] = tok end
    table.remove(out, 1) -- command name
    return out
end

local function sizeClassOf(name, item)
    local def = core().Shared.Items[name]
    return (def and def.size_class) or (item and item.size_class)
end

local function ref(w) return { type = 'wagon', id = rules.stashId(w.id) } end

---Live position of the wagon entity (server-side), or nil while it is not spawned.
local function wagonCoords(w)
    if not w.netId then return nil end
    local ent = NetworkGetEntityFromNetworkId(w.netId)
    if not ent or ent == 0 or not DoesEntityExist(ent) then return nil end
    return GetEntityCoords(ent)
end

local function cargoCount(items)
    local n = 0
    for _, it in pairs(items or {}) do
        if sizeClassOf(it.name, it) == 'cargo' then n = n + (tonumber(it.amount) or 1) end
    end
    return n
end

local function register(w, coords)
    local t = rules.TIERS[w.tier]
    local ok, why = exports.fh_core:registerContainer(ref(w), {
        coords = coords, slots = t.slots, maxWeight = t.maxWeight, label = t.label,
    })
    if not ok then print(('^1[fh_cargo] wagon container register failed for %s: %s^7'):format(w.id, tostring(why))) end
    return ok, why
end

---Request a networked wagon of `tierKey` for `src`'s character at `coords` (vector4/table). Returns wagonId or nil, reason.
local function spawnWagon(src, tierKey, coords)
    local tier = rules.TIERS[tierKey]
    if not tier then return nil, 'fh_bad_tier' end
    local citizenid = citizenidOf(src)
    if not citizenid then return nil, 'fh_no_character' end
    local id = rules.wagonId(citizenid, tierKey)
    local old = wagons[id]
    if old and old.requestId then exports.fh_core:despawn(old.requestId) end
    local w = { id = id, owner = citizenid, tier = tierKey }
    -- TODO(R0 @core idea-602): fh_core requestSpawn has no kind 'wagon' yet (spawn_rules.KINDS = ped/object/horse), so
    -- this returns nil, 'fh_spawn_kind_unsupported'/'fh_spawn_bad_kind' until R0 merges. Written against the intended
    -- contract: same spec/opts as ped/horse, onReady(netId) adopts the wagon entity.
    local reqId, err = exports.fh_core:requestSpawn({
        kind = 'wagon', model = cfg.Models[tierKey], coords = coords,
        owner = { kind = 'wagon', id = id }, tag = 'wagon:' .. id,
    }, {
        onReady = function(netId)
            w.netId = netId
            local c = wagonCoords(w) or coords
            register(w, c)
            TriggerEvent('fh:cargo:wagon_spawned', { src = src, citizenid = citizenid, wagon = id, tier = tierKey, netId = netId })
        end,
        onFailed = function(reason) reply(src, 'fh_wagon: spawn failed: ' .. tostring(reason)) end,
    })
    if not reqId then return nil, err end
    w.requestId = reqId
    wagons[id] = w
    return id
end

---Own wagons that are spawned, with coords.
local function ownWagons(citizenid)
    local out = {}
    for _, w in pairs(wagons) do
        if w.owner == citizenid then
            local c = wagonCoords(w)
            if c then out[#out + 1] = { w = w, coords = c } end
        end
    end
    return out
end

---Nearest own wagon to `pos`.
local function nearestOwn(citizenid, pos)
    local best, bestD
    for _, e in ipairs(ownWagons(citizenid)) do
        local d = #(vector3(e.coords.x, e.coords.y, e.coords.z) - vector3(pos.x, pos.y, pos.z))
        if not bestD or d < bestD then best, bestD = e, d end
    end
    return best
end

local function transfer(src, args)
    local p, perr = rules.parseTransferArgs(args)
    if not p then return nil, perr end
    local citizenid = citizenidOf(src)
    if not citizenid then return nil, 'fh_no_character' end
    local ped = GetPlayerPed(src)
    if ped == 0 then return nil, 'fh_no_player' end
    local pos = GetEntityCoords(ped)
    local own = nearestOwn(citizenid, pos)
    if not own then return nil, 'fh_no_wagon' end
    local openRef = exports.fh_core:openRef(src)
    if not openRef then return nil, 'fh_nothing_open' end
    local openView = exports.fh_core:view(openRef)
    if not openView then return nil, 'fh_nothing_open' end
    local wagonView = exports.fh_core:view(ref(own.w))
    local plan, why = rules.planTransfer({
        dir = p.dir, slot = p.slot, amount = p.amount, citizenid = citizenid, playerCoords = pos,
        wagon = { id = own.w.id, owner = own.w.owner, tier = own.w.tier, coords = own.coords },
        wagonView = wagonView,
        open = { type = openRef.type, id = openRef.id, coords = openView.coords, items = openView.items,
            slots = openView.slots, maxWeight = openView.maxWeight },
        reach = cfg.Reach, sizeClassOf = sizeClassOf,
    })
    if not plan then return nil, why end
    exports.fh_core:setContainerCoords(ref(own.w), own.coords) -- keep the stash where the wagon is
    local ok, mwhy = exports.fh_core:move(plan.fromRef, plan.toRef, plan.fromSlot, plan.toSlot, plan.amount, src)
    if not ok then return nil, mwhy end
    TriggerEvent(p.dir == 'load' and 'fh:cargo:loaded' or 'fh:cargo:unloaded',
        { src = src, citizenid = citizenid, wagon = own.w.id, item = plan.name, count = plan.amount, container = openRef })
    return plan
end

lib.addCommand('fh_cargo', {
    help = 'Move cargo between your wagon and the container you have open: fh_cargo load|unload <slot> [amount]',
}, function(src, _, raw)
    local plan, why = transfer(src, split(raw))
    if not plan then return reply(src, 'fh_cargo: ' .. tostring(why)) end
    reply(src, ('fh_cargo: moved %dx %s'):format(plan.amount, plan.name))
end)

lib.addCommand('fh_wagon', {
    help = 'Dev: spawn a wagon of a tier (t1 cart / t2 wagon / t3 freight): fh_wagon <tier>',
    restricted = 'group.admin',
}, function(src, _, raw)
    if src == 0 then return reply(src, 'fh_wagon: in-game only') end
    local tier, terr = rules.parseTier(split(raw)[1])
    if not tier then return reply(src, 'fh_wagon: ' .. terr .. ' (t1 cart | t2 wagon | t3 freight)') end
    local ped = GetPlayerPed(src)
    if ped == 0 then return reply(src, 'fh_wagon: fh_no_player') end
    local c, h = GetEntityCoords(ped), GetEntityHeading(ped)
    local rad = math.rad(h)
    local d = cfg.SpawnAheadMetres
    local at = vector4(c.x - math.sin(rad) * d, c.y + math.cos(rad) * d, c.z, h)
    local id, err = spawnWagon(src, tier.key, at)
    if not id then
        if err == 'fh_spawn_kind_unsupported' or err == 'fh_spawn_bad_kind' then
            return reply(src, 'fh_wagon: fh_core cannot spawn wagons yet (needs spawn kind "wagon", R0 idea-602)')
        end
        return reply(src, 'fh_wagon: ' .. tostring(err))
    end
    reply(src, ('fh_wagon: requested %s %s (%s)'):format(tier.key, tier.label, id))
end)

---Fast-travel veto for whatever system adds fast travel. Blocked while carrying cargo or while the player's own
---wagon holds cargo within reach. Emits fh:cargo:fasttravel_blocked when it blocks.
---@return boolean ok, string|nil reason
local function canFastTravel(src)
    local citizenid = citizenidOf(src)
    if not citizenid then return false, 'fh_no_character' end
    local ped = GetPlayerPed(src)
    if ped == 0 then return false, 'fh_no_player' end
    local carried = 0
    for _, t in ipairs({ 'equipped', 'backpack' }) do
        carried = carried + cargoCount(exports.fh_core:snapshot({ type = t, id = src }))
    end
    local list = {}
    for _, e in ipairs(ownWagons(citizenid)) do
        list[#list + 1] = { id = e.w.id, coords = e.coords, cargoCount = cargoCount(exports.fh_core:snapshot(ref(e.w))) }
    end
    local ok, reason, blocker = rules.fastTravelVerdict({
        carriedCargo = carried, wagons = list, playerCoords = GetEntityCoords(ped), reach = cfg.FastTravelReach,
    })
    if not ok then
        TriggerEvent('fh:cargo:fasttravel_blocked', { src = src, citizenid = citizenid, reason = reason, wagon = blocker and blocker.id })
    end
    return ok, reason
end

exports('canFastTravel', canFastTravel)
exports('spawnWagon', spawnWagon)
exports('getWagon', function(wagonId)
    local w = wagons[wagonId]
    if not w then return nil end
    return { id = w.id, owner = w.owner, tier = w.tier, netId = w.netId, coords = wagonCoords(w) }
end)

-- If fh_core restarts, its registered-container table is gone: register ours again.
AddEventHandler('onResourceStart', function(res)
    if res ~= 'fh_core' then return end
    for _, w in pairs(wagons) do
        local c = wagonCoords(w)
        if c then register(w, c) end
    end
end)

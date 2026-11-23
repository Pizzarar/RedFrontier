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

---nil when the container could not be read (callers must fail closed).
local function cargoCount(items)
    if type(items) ~= 'table' then return nil end
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
    local w = { id = id, owner = citizenid, tier = tierKey }
    -- TODO(R0 @core idea-602): fh_core requestSpawn has no kind 'wagon' yet (spawn_rules.KINDS = ped/object/horse), so
    -- this returns nil, 'fh_spawn_kind_unsupported'/'fh_spawn_bad_kind' until R0 merges. Written against the intended
    -- contract: same spec/opts as ped/horse, onReady(netId) adopts the wagon entity.
    local reqId, err = exports.fh_core:requestSpawn({
        kind = 'wagon', model = cfg.Models[tierKey], coords = coords,
        owner = { kind = 'wagon', id = id }, tag = 'wagon:' .. id,
    }, {
        onReady = function(netId)
            if wagons[id] ~= w then return end -- replaced by a newer request
            w.netId = netId
            local c = wagonCoords(w) or coords
            register(w, c)
            TriggerEvent('fh:cargo:wagon_spawned', { src = src, citizenid = citizenid, wagon = id, tier = tierKey, netId = netId })
        end,
        onFailed = function(reason) reply(src, 'fh_wagon: spawn failed: ' .. tostring(reason)) end,
    })
    if not reqId then return nil, err end -- the old wagon (if any) is untouched
    local old = wagons[id]
    w.requestId = reqId
    wagons[id] = w
    if old and old.requestId then exports.fh_core:despawn(old.requestId) end
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
    local carried, unknown = 0, nil
    for _, t in ipairs({ 'equipped', 'backpack' }) do
        local snap, serr = exports.fh_core:snapshot({ type = t, id = src })
        local n = cargoCount(snap)
        if n == nil then unknown = unknown or tostring(serr or 'fh_cargo_unknown') else carried = carried + n end
    end
    local list = {}
    for _, e in ipairs(ownWagons(citizenid)) do
        local snap, serr = exports.fh_core:snapshot(ref(e.w))
        local n = cargoCount(snap)
        if n == nil then unknown = unknown or tostring(serr or 'fh_cargo_unknown') end
        list[#list + 1] = { id = e.w.id, coords = e.coords, cargoCount = n or 0 }
    end
    local ok, reason, blocker = rules.fastTravelVerdict({
        unknown = unknown, carriedCargo = carried, wagons = list, playerCoords = GetEntityCoords(ped), reach = cfg.FastTravelReach,
    })
    if not ok then
        TriggerEvent('fh:cargo:fasttravel_blocked', { src = src, citizenid = citizenid, reason = reason, wagon = blocker and blocker.id })
    end
    return ok, reason
end

---Nearest live wagon `src` may load into within `range` m of `coords` (nil = src's ped). Returns a fh_core
---container ref ({ type = 'wagon', id = stash }) or nil. Never throws (hunting calls this).
local function nearestWagon(src, coords, range)
    local ok, res = pcall(function()
        src = tonumber(src)
        if not src then return nil end
        local citizenid = citizenidOf(src)
        if not citizenid then return nil end
        if coords == nil then
            local ped = GetPlayerPed(src)
            if ped == 0 then return nil end
            coords = GetEntityCoords(ped)
        end
        local list = {}
        for _, e in ipairs(ownWagons(citizenid)) do
            list[#list + 1] = { id = e.w.id, owner = e.w.owner, coords = e.coords, w = e.w }
        end
        local best = rules.nearestWagon(citizenid, coords, range, list)
        return best and ref(best.w) or nil
    end)
    if ok then return res end
    return nil
end

exports('canFastTravel', canFastTravel)
exports('nearestWagon', nearestWagon)
exports('spawnWagon', spawnWagon)
exports('getWagon', function(wagonId)
    local w = wagons[wagonId]
    if not w then return nil end
    return { id = w.id, owner = w.owner, tier = w.tier, netId = w.netId, coords = wagonCoords(w) }
end)

-- ---------------------------------------------------------------- R2: wheel break + repair
-- Server tick evaluates the break roll from server-known state only: wagon entity velocity (server native), tier,
-- carried weight. The only client input is a bool off-road hint from the wagon owner (rules.sanitizeSpeed clamps
-- any speed we read). Natives used: GetEntityVelocity (server, OneSync). NOT runtime-tested.
local function holdRefs(src) return { { type = 'equipped', id = src }, { type = 'backpack', id = src } } end
local repairs = {} -- [src] = repair state

local function gated() return GetConvar('fh_spike_gated', 'true') ~= 'false' end

local function registerWheelItems()
    -- TODO(B7 @core): registerItems / removeItem ship with fh_core B7; fail gracefully when missing.
    local ok, res, err, bad = pcall(function() return exports.fh_core:registerItems(rules.ITEMS) end)
    if not ok or res == false then
        print(('^3[fh_cargo] could not register hammer/wagon_wheel (fh_core registerItems: %s %s)^7')
            :format(tostring(ok and err or res), tostring(bad)))
    end
end

local function wagonWeight(w)
    local sum = 0
    for _, it in pairs(exports.fh_core:snapshot(ref(w)) or {}) do
        sum = sum + (tonumber(it.weight) or 0) * (tonumber(it.amount) or 0)
    end
    return sum
end

local function limitFor(w) return rules.effectiveSpeedLimit(w.tier, wagonWeight(w), w.broken) end

---Tell the owner's client the wagon state: it applies the speed cap and (ungated only) the native wheel break.
local function pushState(w, src, native)
    if not src or not w.netId then return end
    TriggerClientEvent('fh:cargo:wheel_state', src, {
        netId = w.netId, broken = w.broken == true, speedLimit = limitFor(w), native = native == true,
    })
end

local function ownerSrc(w)
    for _, id in ipairs(GetPlayers()) do
        local s = tonumber(id)
        if citizenidOf(s) == w.owner then return s end
    end
end

local function breakWheel(w)
    w.broken = true
    local src = ownerSrc(w)
    local native = rules.nativeBreakAllowed(gated())
    pushState(w, src, native)
    TriggerEvent('fh:cargo:wheel_broken', { src = src, citizenid = w.owner, wagon = w.id, tier = w.tier, native = native })
end

local function repairWheel(w, src)
    w.broken = false
    pushState(w, src, rules.nativeBreakAllowed(gated())) -- native=true only ungated: client then runs SET_VEHICLE_FIXED
    TriggerEvent('fh:cargo:wheel_repaired', { src = src, citizenid = w.owner, wagon = w.id, tier = w.tier })
end

-- Owner client's off-road hint: a bool, accepted only from the wagon owner.
RegisterNetEvent('fh:cargo:offroad_hint', function(offRoad)
    local cid = citizenidOf(source)
    if not cid or type(offRoad) ~= 'boolean' then return end
    for _, w in pairs(wagons) do
        if w.owner == cid then w.offRoad = offRoad end
    end
end)

CreateThread(function()
    while true do
        Wait(1000)
        for _, w in pairs(wagons) do
            if w.netId and not w.broken then
                local ent = NetworkGetEntityFromNetworkId(w.netId)
                if ent and ent ~= 0 and DoesEntityExist(ent) then
                    local v = GetEntityVelocity(ent)
                    local speed = rules.sanitizeSpeed(math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z), w.tier)
                    if speed and rules.rollWheelBreak({
                        tier = w.tier, speed = speed, offRoad = w.offRoad == true,
                        loadFraction = rules.loadFraction(w.tier, wagonWeight(w)),
                    }, math.random) then
                        breakWheel(w)
                    end
                end
            end
        end
    end
end)

---Consume one wagon_wheel, all-or-nothing. TODO(B7 @core): fh_core removeItem(ref, item, amt) -> true | false, reason.
local function consumeWheel(src)
    local refs, snaps = holdRefs(src), {}
    for i, r in ipairs(refs) do snaps[i] = exports.fh_core:snapshot(r) end
    local holder = rules.findHolder(refs, snaps, 'wagon_wheel', 1)
    if not holder then return false, 'fh_not_enough' end
    local ok, res, why = pcall(function() return exports.fh_core:removeItem(holder, 'wagon_wheel', 1) end)
    if not ok then return false, 'fh_core_no_removeitem' end -- export missing: B7 not merged
    if res ~= true then return false, why or 'fh_not_enough' end
    return true
end

local function startRepair(src)
    if repairs[src] then return nil, 'fh_repair_busy' end
    local citizenid = citizenidOf(src)
    if not citizenid then return nil, 'fh_no_character' end
    local ped = GetPlayerPed(src)
    if ped == 0 then return nil, 'fh_no_player' end
    local pos = GetEntityCoords(ped)
    local own = nearestOwn(citizenid, pos)
    if not own then return nil, 'fh_no_wagon' end
    local refs, snaps = holdRefs(src), {}
    for i, r in ipairs(refs) do snaps[i] = exports.fh_core:snapshot(r) end
    local ok, why = rules.planRepair({
        citizenid = citizenid, playerCoords = pos, reach = cfg.Reach,
        wagon = { id = own.w.id, owner = own.w.owner, tier = own.w.tier, coords = own.coords, broken = own.w.broken },
        hasHammer = rules.findHolder(refs, snaps, 'hammer', 1) ~= nil,
        hasWheel = rules.findHolder(refs, snaps, 'wagon_wheel', 1) ~= nil,
    })
    if not ok then return nil, why end
    local w = own.w
    local st = { startedAt = GetGameTimer(), duration = rules.WHEEL.repairMs, startCoords = pos }
    repairs[src] = st
    CreateThread(function()
        while true do
            Wait(250)
            local p = GetPlayerPed(src)
            local c = p ~= 0 and GetEntityCoords(p) or nil
            local wc = wagonCoords(w)
            local state, reason = 'cancel', 'fh_no_player'
            if wagons[w.id] ~= w or not wc then state, reason = 'cancel', 'fh_no_wagon' -- gone/unloaded: consume nothing
            elseif c then state, reason = rules.repairStep(st, GetGameTimer(), c, wc, cfg.Reach) end
            if state == 'continue' and not w.broken then state, reason = 'cancel', 'fh_wheel_ok' end
            if state == 'done' then
                repairs[src] = nil
                local rrefs, rsnaps = holdRefs(src), {}
                for i, r in ipairs(rrefs) do rsnaps[i] = exports.fh_core:snapshot(r) end
                local fok, fwhy = rules.repairFinalCheck({
                    broken = w.broken, wagonCoords = wagons[w.id] == w and wc or nil,
                    hasHammer = rules.findHolder(rrefs, rsnaps, 'hammer', 1) ~= nil,
                    hasWheel = rules.findHolder(rrefs, rsnaps, 'wagon_wheel', 1) ~= nil,
                })
                if not fok then return reply(src, 'fh_repair: cancelled (' .. tostring(fwhy) .. ')') end
                local used, uwhy = consumeWheel(src) -- re-checked now: nothing repairs unless the wheel was consumed
                if not used then return reply(src, 'fh_repair: ' .. tostring(uwhy)) end
                repairWheel(w, src)
                return reply(src, 'fh_repair: wheel repaired')
            elseif state == 'cancel' then
                repairs[src] = nil
                return reply(src, 'fh_repair: cancelled (' .. tostring(reason) .. ')')
            end
        end
    end)
    return true
end

AddEventHandler('playerDropped', function() repairs[source] = nil end)

lib.addCommand('fh_repair', {
    help = 'Repair a broken wheel on your own wagon: needs a hammer and a wagon_wheel; stay close until done',
}, function(src)
    local ok, why = startRepair(src)
    if not ok then return reply(src, 'fh_repair: ' .. tostring(why)) end
    reply(src, 'fh_repair: working on the wheel, stay by the wagon')
end)

lib.addCommand('fh_wheelbreak', {
    help = 'Dev: break the wheel of your nearest own wagon',
    restricted = 'group.admin',
}, function(src)
    local cid = citizenidOf(src)
    local ped = GetPlayerPed(src)
    if not cid or ped == 0 then return reply(src, 'fh_wheelbreak: fh_no_player') end
    local own = nearestOwn(cid, GetEntityCoords(ped))
    if not own then return reply(src, 'fh_wheelbreak: fh_no_wagon') end
    if own.w.broken then return reply(src, 'fh_wheelbreak: already broken') end
    breakWheel(own.w)
end)

exports('isWheelBroken', function(wagonId) local w = wagons[wagonId]; return w ~= nil and w.broken == true end)
exports('getSpeedLimit', function(wagonId)
    local w = wagons[wagonId]
    return w and limitFor(w) or nil
end)

AddEventHandler('onResourceStart', function(res)
    if res == GetCurrentResourceName() or res == 'fh_core' then registerWheelItems() end
end)

-- If fh_core restarts, its registered-container table is gone: register ours again.
AddEventHandler('onResourceStart', function(res)
    if res ~= 'fh_core' then return end
    for _, w in pairs(wagons) do
        local c = wagonCoords(w)
        if c then register(w, c) end
    end
end)

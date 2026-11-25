-- fh_heat R6 server: roadblocks (always on), night ambush + mounted chase (only when fh_spike_gated=false).
-- Thin: every decision is FhRoadblockRules (spec/roadblock_rules_spec.lua); this file feeds it state and calls
-- exports.fh_core:requestSpawn / despawn. Natives: GetPlayers, GetPlayerPed, GetEntityCoords, GetEntityHeading,
-- GetConvar, GetGameTimer; all UNVERIFIED in game (no Cfx key yet). Spawn contract: fh_core README "Spawn contract".
local cfg = FhHeatConfig
local rules = FhRoadblockRules
local heatRules = FhHeatRules
local regions = FhRegions

local groups = {}    -- groupId -> { id, kind, key, src, cid, faction, reqs = {}, expiresAt, ... }
local byKey = {}     -- kind .. key -> groupId (one live per kind + player + faction)
local lastAt = {}    -- kind .. key -> seconds of last spawn (cooldown)
local liveCount = {} -- kind -> live groups
local nextId = 0

local function log(fmt, ...) print(('[fh_heat] ' .. fmt):format(...)) end
local function nowS() return GetGameTimer() / 1000.0 end
local function gated() return rules.parseFlag(GetConvar('fh_spike_gated', 'true'), true) end

local function emit(name, payload)
    local ok, e = pcall(TriggerEvent, name, payload)
    if not ok then log('ERROR emitting %s: %s', name, tostring(e)) end
end

local function playerPos(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return nil end
    local c = GetEntityCoords(ped)
    return c.x, c.y, c.z, ped
end

local function citizenid(src)
    local p = exports['rsg-core']:GetPlayer(src)
    return p and p.PlayerData and p.PlayerData.citizenid or nil
end

local function mk(kind, cid, faction) return kind .. '\0' .. rules.key(cid, faction) end

-- H9b (@homestead, NOT on main yet): an owned town lot is law-safe, so law encounters (roadblock / ambush / chase)
-- must not spawn for a player standing inside their OWN lot. exports.fh_homestead:lawSafeAt(coords, citizenid) ->
-- plotId|nil (nil for claims, unowned lots, a stranger's lot, bad coords; never throws). It must work without
-- fh_homestead: call only when started, pcall'd; any missing export / error / nil = not safe = behave as today.
local lawSafeLogged = {} -- "cid\0plotId" -> true: one debug log per player per plot (the sweep ticks often)
local function lawSafeLookup(coords, cid)
    if GetResourceState('fh_homestead') ~= 'started' then return nil end
    return exports.fh_homestead:lawSafeAt(coords, cid)
end

---@return boolean blocked  true = inside the player's own law-safe lot: skip spawning this encounter
local function lawSafeBlocked(src, cid, x, y, z)
    local plot = rules.lawSafeBlocks(lawSafeLookup, { x = x, y = y, z = z }, cid)
    if not plot then return false end
    local key = tostring(cid) .. '\0' .. tostring(plot)
    if not lawSafeLogged[key] then
        lawSafeLogged[key] = true
        log('%s/%s law-safe in own lot %s: skipping spawn', tostring(src), tostring(cid), tostring(plot))
    end
    return true
end

local noConfigLogged = {} -- "kind\0faction" -> true: log once per kind + faction when no spawn row resolves
local function resolveFactionConfig(kind, blockCfg, faction)
    local fcfg = rules.factionConfig(blockCfg, faction, regions)
    if fcfg then return fcfg end
    local key = tostring(kind) .. '\0' .. tostring(faction)
    if not noConfigLogged[key] then
        noConfigLogged[key] = true
        log('%s: no ped config for faction %s (skipping spawn)', tostring(kind), tostring(faction))
    end
    return nil
end

-- ---------------------------------------------------------------- group lifecycle

local function clearGroup(g, reason)
    if not groups[g.id] then return end
    groups[g.id] = nil
    byKey[g.mapKey] = nil
    liveCount[g.kind] = math.max(0, (liveCount[g.kind] or 1) - 1)
    for _, rid in ipairs(g.reqs) do pcall(function() exports.fh_core:despawn(rid) end) end
    log('%s %s cleared (%s)', g.kind, g.id, reason)
    if g.kind == 'roadblock' then
        emit('fh:heat:roadblock_cleared', { src = g.src, citizenid = g.cid, faction = g.faction, roadblock_id = g.id,
            chokepoint_id = g.chokepoint_id, reason = reason })
    else
        emit('fh:heat:' .. g.kind .. '_cleared', { src = g.src, citizenid = g.cid, faction = g.faction,
            group_id = g.id, reason = reason })
    end
end

-- Request one entity of a group. spec: { kind, model, x, y, z, heading, weapon, index, role }
local function requestOne(g, spec, onNet)
    local tag = ('fh_heat:%s:%s:%d'):format(g.kind, g.faction, spec.index)
    if spec.role then tag = tag .. ':' .. spec.role end
    local id, err = exports.fh_core:requestSpawn({
        kind = spec.kind or 'ped', model = spec.model, coords = vector4(spec.x, spec.y, spec.z, spec.heading or 0.0),
        owner = { kind = 'fh_heat_' .. g.kind, id = g.id }, tag = tag,
    }, {
        near = vector3(spec.x, spec.y, spec.z),
        onReady = function(netId, requestId)
            if not groups[g.id] then pcall(function() exports.fh_core:despawn(requestId) end) return end
            if onNet then onNet(netId) end
        end,
        onFailed = function(reason) log('%s %s entity %d spawn failed: %s', g.kind, g.id, spec.index, tostring(reason)) end,
    })
    if not id then log('%s %s entity %d refused: %s', g.kind, g.id, spec.index, tostring(err)) return end
    g.reqs[#g.reqs + 1] = id
end

local function newGroup(kind, src, cid, faction, minutes, extra)
    nextId = nextId + 1
    local g = { id = ('%s_%d'):format(kind, nextId), kind = kind, src = src, cid = cid, faction = faction, reqs = {},
        expiresAt = nowS() + minutes * 60, mapKey = mk(kind, cid, faction) }
    for k, v in pairs(extra or {}) do g[k] = v end
    groups[g.id] = g
    byKey[g.mapKey] = g.id
    lastAt[g.mapKey] = nowS()
    liveCount[kind] = (liveCount[kind] or 0) + 1
    return g
end

-- ---------------------------------------------------------------- roadblock (always on)

local function tryRoadblock(src, cid, faction, oldLevel, level)
    local rc = cfg.roadblock
    if not rc or rc.enabled == false then return end
    if not rules.crossedUp(cfg.thresholds, oldLevel, level, rc.minLevel) then return end
    local fcfg = resolveFactionConfig('roadblock', rc, faction)
    if not fcfg then return end
    local x, y, z = playerPos(src)
    if not x then return end
    if lawSafeBlocked(src, cid, x, y, z) then return end
    local t = regions.territoryAt(x, y)
    local choke, cerr = rules.pickChokepoint(rc.chokepoints, t and t.region, x, y, rc.maxPlayerDistance)
    if not choke then return log('roadblock skipped for %s/%s: %s', tostring(cid), faction, tostring(cerr)) end
    local mapKey = mk('roadblock', cid, faction)
    local ok, why = rules.canSpawn({ liveKey = byKey[mapKey] ~= nil, liveCount = liveCount.roadblock or 0,
        lastAt = lastAt[mapKey], now = nowS(), cooldown = rc.cooldownSeconds, maxConcurrent = rc.maxConcurrent })
    if not ok then return log('roadblock skipped for %s/%s: %s', tostring(cid), faction, why) end
    local plan = rules.pedPlan(fcfg, choke, rc.pedSpacing)
    if #plan == 0 then return log('roadblock: empty ped plan for %s', faction) end
    local g = newGroup('roadblock', src, cid, faction, rc.despawnMinutes, { chokepoint_id = choke.id })
    for _, p in ipairs(plan) do requestOne(g, p) end
    log('roadblock %s: %s at %s for %s (%d peds, level %s)', g.id, faction, choke.id, tostring(cid), #plan, tostring(level))
    emit('fh:heat:roadblock_spawned', { src = src, citizenid = cid, faction = faction, roadblock_id = g.id,
        chokepoint_id = choke.id, region_id = choke.region, level = level, peds = #plan,
        expires_at = os.time() + rc.despawnMinutes * 60 })
end

-- ---------------------------------------------------------------- night ambush + chase (gated)

local function gameHour()
    local ok, h = pcall(function() return GetClockHours() end) -- client native; not verified server-side
    if ok and type(h) == 'number' then return h end
    return tonumber(os.date('%H')) -- wall clock fallback: a gap, see README
end

local function tryAmbush(src, cid, faction, level, quiet)
    local ac = cfg.ambush
    local mapKey = mk('ambush', cid, faction)
    if gated() then -- no gameHour() / natives while gated
        if not quiet then log('%s', rules.gatedPlan(true, 'night ambush').log) end
        return
    end
    local ok, why, msg = rules.ambushDecision(ac, { gated = false, level = level, thresholds = cfg.thresholds,
        hour = gameHour(), now = nowS(), lastAt = lastAt[mapKey], liveKey = byKey[mapKey] ~= nil })
    if not ok then
        if why == 'gated' and not quiet then log('%s', msg) end
        return
    end
    local fcfg = resolveFactionConfig('ambush', ac, faction)
    if not fcfg then return end
    local x, y, z = playerPos(src)
    if not x then return end
    if lawSafeBlocked(src, cid, x, y, z) then return end
    local plan = rules.ringPlan(fcfg, x, y, z, ac.radius, math.random(0, 359))
    local g = newGroup('ambush', src, cid, faction, ac.despawnMinutes)
    for _, p in ipairs(plan) do requestOne(g, p) end
    log('ambush %s: %s around %s (%d peds)', g.id, faction, tostring(cid), #plan)
    emit('fh:heat:ambush_spawned', { src = src, citizenid = cid, faction = faction, group_id = g.id, level = level,
        peds = #plan })
end

local function playerMounted(ped)
    -- UNVERIFIED server natives; any failure counts as "not mounted" (chase stays off rather than guess).
    local ok, v = pcall(function() return IsPedOnMount(ped) or IsPedInAnyVehicle(ped, false) end)
    return ok and v == true
end

local function tryChase(src, cid, faction, level, quiet)
    local cc = cfg.chase
    local mapKey = mk('chase', cid, faction)
    if gated() then -- no playerMounted() native calls while gated
        if not quiet then log('%s', rules.gatedPlan(true, 'mounted chase').log) end
        return
    end
    local x, y, z, ped = playerPos(src)
    local ok, why, msg = rules.chaseDecision(cc, { gated = false, level = level, thresholds = cfg.thresholds,
        mounted = x and playerMounted(ped), now = nowS(), lastAt = lastAt[mapKey], liveKey = byKey[mapKey] ~= nil })
    if not ok then
        if why == 'gated' and not quiet then log('%s', msg) end
        return
    end
    local fcfg = resolveFactionConfig('chase', cc, faction)
    if not fcfg then return end
    if lawSafeBlocked(src, cid, x, y, z) then return end
    local rad = math.rad(GetEntityHeading(ped))
    local bx, by = x + math.sin(rad) * cc.behind, y - math.cos(rad) * cc.behind -- behind = against the facing vector
    local plan = rules.pedPlan(fcfg, { coords = { x = bx, y = by, z = z }, heading = (GetEntityHeading(ped) + 180.0) % 360.0 }, 3.0) -- pedPlan adds 180: net = facing the player
    local g = newGroup('chase', src, cid, faction, cc.despawnMinutes, { mounts = {} })
    for _, p in ipairs(plan) do
        local pair = {}
        g.mounts[p.index] = pair
        -- both callbacks call this; rules.claimMount fires it once, only when both netIds are known and g is live
        local function maybeMount()
            if rules.claimMount(pair, groups[g.id] ~= nil) then
                -- the target's client mounts + attacks (client/main.lua); the spawner's client set up the AI
                TriggerClientEvent('fh:heat:chase', g.src, { rider = pair.rider, horse = pair.horse, faction = faction })
            end
        end
        requestOne(g, { kind = 'horse', model = cc.horseModel, x = p.x, y = p.y, z = p.z, heading = p.heading,
            index = p.index, role = 'mount' }, function(netId) pair.horse = netId maybeMount() end)
        requestOne(g, { kind = 'ped', model = p.model, x = p.x, y = p.y + 1.0, z = p.z, heading = p.heading,
            weapon = p.weapon, index = p.index, role = 'rider' }, function(netId) pair.rider = netId maybeMount() end)
    end
    log('chase %s: %s riders behind %s (%d)', g.id, faction, tostring(cid), #plan)
    emit('fh:heat:chase_started', { src = src, citizenid = cid, faction = faction, group_id = g.id, level = level,
        riders = #plan })
end

-- ---------------------------------------------------------------- hooks

AddEventHandler('fh:heat:threshold', function(e)
    if type(e) ~= 'table' or type(e.src) ~= 'number' or not e.faction or not e.citizenid then return end
    -- pcall: a bad record must never break fh_heat's own event emission
    local ok, err = pcall(function()
        -- a drop below minLevel clears this player's live roadblock now; the sweep below also catches it
        local g = groups[byKey[mk('roadblock', e.citizenid, e.faction)] or '']
        if g and not rules.atLeast(cfg.thresholds, e.level, cfg.roadblock.minLevel) then clearGroup(g, 'heat_dropped') end
        tryRoadblock(e.src, e.citizenid, e.faction, e.old_level, e.level)
        tryAmbush(e.src, e.citizenid, e.faction, e.level, false)
        tryChase(e.src, e.citizenid, e.faction, e.level, false)
    end)
    if not ok then log('ERROR threshold handler: %s', tostring(err)) end
end)

-- Sweep: expiry, heat dropped (decay), player gone; and, ungated only, ambush / chase for players already above level.
CreateThread(function()
    local every = math.floor((cfg.roadblock and cfg.roadblock.tickSeconds or 15) * 1000)
    while true do
        Wait(every)
        heatRules.safeTick(function()
            local now = nowS()
            local maxCd = math.max((cfg.roadblock or {}).cooldownSeconds or 0, (cfg.ambush or {}).cooldownSeconds or 0,
                (cfg.chase or {}).cooldownSeconds or 0)
            for k, t in pairs(lastAt) do if now - t > maxCd then lastAt[k] = nil end end -- cooldown over: drop (live groups keep expiry, not lastAt)
            local online = {}
            for _, s in ipairs(GetPlayers()) do online[tonumber(s)] = true end
            local snapshot = {}
            for _, g in pairs(groups) do snapshot[#snapshot + 1] = g end
            for _, g in ipairs(snapshot) do
                local level
                local okL, lv = pcall(function() return exports.fh_heat:level(g.src, g.faction) end)
                if okL then level = lv end
                -- ambush / chase end on expiry or player gone only; roadblocks also when heat drops
                local minLevel = g.kind == 'roadblock' and cfg.roadblock.minLevel or (cfg[g.kind] or {}).minLevel
                local reason = rules.clearReason(g, now, cfg.thresholds, g.kind == 'roadblock' and level or minLevel,
                    minLevel, online[g.src] == true)
                if reason then clearGroup(g, reason) end
            end
            if not gated() then
                for src in pairs(online) do
                    local cid = citizenid(src)
                    if cid then
                        for faction in pairs(regions.factions) do
                            local okL, lv = pcall(function() return exports.fh_heat:level(src, faction) end)
                            if okL and lv then
                                tryAmbush(src, cid, faction, lv, true)
                                tryChase(src, cid, faction, lv, true)
                            end
                        end
                    end
                end
            end
        end, function(e) log('ERROR roadblock sweep: %s', e) end)
    end
end)

AddEventHandler('playerDropped', function()
    local src = source
    local drop = {}
    for _, g in pairs(groups) do if g.src == src then drop[#drop + 1] = g end end
    for _, g in ipairs(drop) do clearGroup(g, 'player_dropped') end
end)

AddEventHandler('onResourceStop', function(name)
    if name ~= GetCurrentResourceName() then return end
    local all = {}
    for _, g in pairs(groups) do all[#all + 1] = g end
    for _, g in ipairs(all) do clearGroup(g, 'resource_stop') end
end)

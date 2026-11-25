-- fh_alife pure A-Life rules: camp ownership graph + retake squads. No natives, no DB, no os.time/GetGameTimer:
-- the caller injects `rng` (default math.random) and advances time in integer ticks. Specced in spec/alife_rules_spec.lua.
--
-- Model (A1):
--  * node graph: one camp node per fh_zones camp, one town node per FhRegions region.
--  * owners: campId -> factionId; the default owner is the camp territory's `faction` (regions.territories).
--  * squads: plain data { id, faction, strength, from, to, etaTick, goal = 'ambush'|'reinforce'|'retake' }.
--  * tick(n) advances the clock and resolves squads whose etaTick has passed. The weighted dice rolls squad
--    strength and etaTick at spawn; a retake squad dislodges the camp when its strength, less the region's outlaw
--    road losses (regionPressure), beats the law's holding reinforce strength. A failed retake regroups (new squad).
--  * effects are plain tables { type = 'broadcast'|'shortage'|'flipped'|..., ... } the server applies.
--
-- a-life-02 B1 (roads and raids). Implemented A-Life — Thanks to S.T.A.L.K.E.R. A-Life by GSC Game World.
--  * ambush nodes: one node per entry of @world `regions[id].ambush = { { id?, x, y, z, label?, verified? } }` in
--    enabled regions only (FhRegions.isEnabled, feature-detected). id = entry id, else '<region>:ambush:<index>'.
--    A region with no (or an empty) `ambush` list gets no nodes and so no raids: a clean no-op.
--  * ambush squads (goal 'ambush'): an outlaw-held camp rolls raids.chancePct per tick to send a squad to a free node
--    of its region. phase 'travel' -> 'hold' (holdTicks) -> 'return' -> back at camp (removed). One live squad per
--    node, at most raids.regionCap per region ('return' squads no longer hold a node and do not count).
--  * onSquadKill: each kill takes 1 strength; a non-law squad's losses add to regionPressure[region][faction]
--    (capped at raids.pressureMax), which the next retake roll by that faction in that region subtracts and clears.
--  * reinforce squads (goal 'reinforce', data only, no rng): a law-held camp with none gets one of
--    reinforce.strength; it travels reinforce.travelTicks, then holds while the camp stays law-held.
--  * save format v2 = v1 + regionPressure + the squad fields node/region/phase/travel. v1 saves load (migrated).
-- a-life-03 C1 (wilderness-claim raids, shared/raid_rules.lua). Raid squads live in state.squads with goal 'raid' so
-- onSquadKill's regionPressure and the B2 death watch apply to them unchanged; raid_rules owns their lifecycle, so
-- tick() here never advances or resolves a 'raid' squad. Save format v3 = v2 + raidCooldowns { [plotId] = untilTick }
-- (+ 'raid' squads). v1 and v2 saves load (no raids, no cooldowns). v3 also carries raidLoot (a-life-03 C2c, optional:
-- a v3 save without it loads with an empty ledger): { [campId] = { { name, amount, info? }, ... } } oldest first, the
-- goods raiders took from claims, delivered to the camp stash when the camp is cleared (raid_rules lootAdd/lootTake).
-- Law detection: a faction is law if its `kind == 'law'`; when `kind` is absent, fall back to { lawmen, rhodes_law }.
local M = {}

M.VERSION = 3

-- Save versions deserialize accepts (v1 = a-life-01: owners + retake squads only; v2 = a-life-02).
local LOADABLE = { [1] = true, [2] = true, [3] = true }

-- Fallback set used only when a faction has no `kind` field (hardcoded aliases; rhodes_law is an alias of lawmen).
local LAW_FALLBACK = { lawmen = true, rhodes_law = true }

local function finite(n) return type(n) == 'number' and n == n and n > -math.huge and n < math.huge end

---Is a faction law? `factions` = FhRegions.factions. `kind == 'law'` wins; otherwise the fallback set.
function M.isLawFaction(factions, id)
    if type(id) ~= 'string' then return false end
    local f = type(factions) == 'table' and factions[id] or nil
    if f and f.kind ~= nil then return f.kind == 'law' end
    return LAW_FALLBACK[id] == true
end

---The first law faction in regions[regionId].factions, or nil.
function M.regionLawFaction(regions, regionId)
    local r = type(regions) == 'table' and regions.regions and regions.regions[regionId] or nil
    if not r then return nil end
    for _, fid in ipairs(r.factions or {}) do
        if M.isLawFaction(regions.factions, fid) then return fid end
    end
    return nil
end

---Is a region enabled? Feature-detects regions.isEnabled (world-01 block D); without it every region is enabled.
local function regionEnabled(regions, regionId)
    if type(regions) ~= 'table' or type(regions.isEnabled) ~= 'function' then return true end
    local ok, on = pcall(regions.isEnabled, regionId)
    return ok and on == true
end
M.regionEnabled = regionEnabled

local function sortedKeys(t)
    local ks = {}
    for k in pairs(t or {}) do if type(k) == 'string' then ks[#ks + 1] = k end end
    table.sort(ks)
    return ks
end

---Node graph: one camp node per camp (id = camp id), one town node per region (id = region id), and one ambush node
---per valid `regions[id].ambush` entry of an enabled region. `ambushByRegion[regionId]` lists the region's ambush node
---ids in data order (absent = no ambush nodes). Malformed entries (non-table, non-finite x/y/z) and ids already taken
---by another node are skipped. `cfg` is accepted for future edges (e.g. road links).
function M.buildGraph(cfg, regions, camps)
    local nodes, ambushByRegion = {}, {}
    for _, camp in pairs(camps or {}) do
        if type(camp) == 'table' and type(camp.id) == 'string' then
            nodes[camp.id] = { id = camp.id, type = 'camp', region = camp.region, territory = camp.territory }
        end
    end
    local regionTable = (type(regions) == 'table' and type(regions.regions) == 'table') and regions.regions or {}
    for id in pairs(regionTable) do
        if type(id) == 'string' then nodes[id] = { id = id, type = 'town', region = id } end
    end
    for _, rid in ipairs(sortedKeys(regionTable)) do
        local region = regionTable[rid]
        local list = type(region) == 'table' and region.ambush or nil
        if type(list) == 'table' and regionEnabled(regions, rid) then
            for i, a in ipairs(list) do
                if type(a) == 'table' and finite(a.x) and finite(a.y) and finite(a.z) then
                    local nid = (type(a.id) == 'string' and a.id ~= '') and a.id or ('%s:ambush:%d'):format(rid, i)
                    if not nodes[nid] then
                        nodes[nid] = { id = nid, type = 'ambush', region = rid, index = i, x = a.x, y = a.y, z = a.z,
                            label = (type(a.label) == 'string' and a.label ~= '') and a.label or nil,
                            verified = a.verified == true }
                        ambushByRegion[rid] = ambushByRegion[rid] or {}
                        local l = ambushByRegion[rid]
                        l[#l + 1] = nid
                    end
                end
            end
        end
    end
    return { nodes = nodes, ambushByRegion = ambushByRegion }
end

---Bundle the sim's static context (cfg + regions + camps + graph) for the transition functions.
function M.context(cfg, regions, camps)
    return { cfg = cfg, regions = regions, camps = camps or {}, graph = M.buildGraph(cfg, regions, camps) }
end

function M.newState()
    return { version = M.VERSION, tick = 0, owners = {}, squads = {}, nextSquadId = 1, regionPressure = {},
        raidCooldowns = {}, raidLoot = {} }
end

---Plain-table serialization (JSON-safe; the server json.encode's it for KVP). Deserialize reverses it.
function M.serialize(state)
    return { version = state.version, tick = state.tick, owners = state.owners, squads = state.squads,
        nextSquadId = state.nextSquadId, regionPressure = state.regionPressure or {},
        raidCooldowns = state.raidCooldowns or {}, raidLoot = state.raidLoot or {} }
end

---One raid-loot ledger entry, normalised: { name, amount (integer >= 1), info (table or nil) } or nil when malformed.
function M.cleanLootEntry(e)
    if type(e) ~= 'table' or type(e.name) ~= 'string' or e.name == '' or not finite(e.amount) then return nil end
    local n = math.floor(e.amount)
    if n < 1 then return nil end
    return { name = e.name, amount = n, info = type(e.info) == 'table' and e.info or nil }
end

local PHASES = { travel = true, hold = true, ['return'] = true }

local function nonNegInt(n)
    if not finite(n) then return nil end
    n = math.floor(n)
    return n >= 0 and n or nil
end

---Shape check for one saved squad (v1 rules, plus the v2 fields for ambush/reinforce squads). Non-finite or negative
---strength/travel fall back to 0/1. @return table|nil squad
local function cleanSquad(sq)
    if type(sq) ~= 'table' or type(sq.id) ~= 'string' or type(sq.faction) ~= 'string'
        or type(sq.to) ~= 'string' or not finite(sq.etaTick) then return nil end
    if sq.goal == 'ambush' or sq.goal == 'reinforce' then
        if not PHASES[sq.phase] then return nil end
        if sq.goal == 'ambush' and (type(sq.node) ~= 'string' or type(sq.from) ~= 'string') then return nil end
        sq.strength = nonNegInt(sq.strength) or 0
        sq.travel = math.max(1, nonNegInt(sq.travel) or 1)
    end
    return sq
end

---Drop squads that point at nodes the current graph no longer has (an ambush node removed from @world data, a
---disabled region, a removed camp). A dropped squad's strength returns to its camp: no regionPressure is added.
---@return table effects  { type = 'squad_returned', reason = 'node_missing', ... } per dropped squad
function M.pruneSquads(ctx, state)
    local effects = {}
    local nodes = ctx and ctx.graph and ctx.graph.nodes or {}
    for _, id in ipairs(sortedKeys(state.squads)) do
        local sq = state.squads[id]
        local missing
        if sq.goal == 'ambush' then
            local n = nodes[sq.node]
            missing = not n or n.type ~= 'ambush'
        elseif sq.goal == 'reinforce' then
            missing = not (ctx.camps and ctx.camps[sq.to])
        end
        if missing then
            state.squads[id] = nil
            effects[#effects + 1] = { type = 'squad_returned', reason = 'node_missing', squad_id = id, goal = sq.goal,
                faction = sq.faction, camp_id = sq.goal == 'ambush' and sq.from or sq.to, node = sq.node,
                region_id = sq.region, strength = sq.strength or 0 }
        end
    end
    return effects
end

---Rebuild state from a saved table (v1, v2 or v3). With `ctx`, squads whose node is gone are pruned (see pruneSquads).
---@return table|nil state, string|nil err, table effects (prune effects; {} without ctx or on error)
function M.deserialize(t, ctx)
    if type(t) ~= 'table' then return nil, 'fh_alife_bad_state', {} end
    if not LOADABLE[t.version] then return nil, 'fh_alife_version', {} end
    local s = M.newState()
    s.tick = math.tointeger(t.tick) or 0
    s.nextSquadId = math.tointeger(t.nextSquadId) or 1
    s.owners = type(t.owners) == 'table' and t.owners or {}
    s.squads = {}
    if type(t.squads) == 'table' then
        for _, raw in pairs(t.squads) do
            local sq = cleanSquad(raw)
            if sq then s.squads[sq.id] = sq end
        end
    end
    if type(t.regionPressure) == 'table' then
        for rid, byFaction in pairs(t.regionPressure) do
            if type(rid) == 'string' and type(byFaction) == 'table' then
                for fid, v in pairs(byFaction) do
                    local n = nonNegInt(v)
                    if type(fid) == 'string' and n and n > 0 then
                        s.regionPressure[rid] = s.regionPressure[rid] or {}
                        s.regionPressure[rid][fid] = n
                    end
                end
            end
        end
    end
    if type(t.raidCooldowns) == 'table' then
        for plotId, untilTick in pairs(t.raidCooldowns) do
            local n = nonNegInt(untilTick)
            if type(plotId) == 'string' and n then s.raidCooldowns[plotId] = n end
        end
    end
    if type(t.raidLoot) == 'table' then
        for campId, list in pairs(t.raidLoot) do
            if type(campId) == 'string' and type(list) == 'table' then
                local out = {}
                for i = 1, #list do
                    local e = M.cleanLootEntry(list[i])
                    if e then out[#out + 1] = e end
                end
                if #out > 0 then s.raidLoot[campId] = out end
            end
        end
    end
    local effects = ctx and M.pruneSquads(ctx, s) or {}
    return s, nil, effects
end

-- ---------------------------------------------------------------- helpers

local function defaultOwner(regions, camps, campId)
    local camp = camps[campId]
    local terr = camp and camp.territory and regions and regions.territories and regions.territories[camp.territory]
    return terr and terr.faction or nil
end

local function factionLabel(regions, id, regionId)
    if regions and type(regions.factionLabel) == 'function' then
        local ok, label = pcall(regions.factionLabel, id, regionId)
        if ok and type(label) == 'string' and label ~= '' then return label end
    end
    local f = regions and regions.factions and regions.factions[id]
    return f and f.label or id
end

local function campLabel(regions, camps, campId)
    local camp = camps[campId]
    local terr = camp and camp.territory and regions and regions.territories and regions.territories[camp.territory]
    return terr and terr.label or campId
end

local function shortageEffect(ctx, regionId, which)
    local spec = ctx.cfg.shortages and ctx.cfg.shortages[regionId]
    if not spec or type(spec.item) ~= 'string' or not finite(spec[which]) then return nil end
    return { type = 'shortage', region = regionId, item = spec.item, level = spec[which] }
end

-- ---------------------------------------------------------------- queries

---Effective owner: an explicit flip if present, else the territory's default faction.
function M.getOwner(ctx, state, campId)
    if state.owners[campId] then return state.owners[campId] end
    return defaultOwner(ctx.regions, ctx.camps, campId)
end

function M.isLawHeld(ctx, state, campId)
    local o = M.getOwner(ctx, state, campId)
    return o ~= nil and M.isLawFaction(ctx.regions.factions, o)
end

---Strength the law holds a camp with: the sum of its arrived (phase 'hold') reinforce squads.
function M.holderStrength(state, campId)
    local n = 0
    for _, sq in pairs(state.squads) do
        if sq.goal == 'reinforce' and sq.to == campId and sq.phase == 'hold' then n = n + (sq.strength or 0) end
    end
    return n
end

---Outlaw road losses pending against `faction`'s next retake roll in `regionId`.
function M.getPressure(state, regionId, faction)
    local r = state.regionPressure and state.regionPressure[regionId]
    return (r and r[faction]) or 0
end

---Ambush node tables of a region in data order ({} when the region has none: /alife prints "no ambush nodes").
function M.ambushNodes(ctx, regionId)
    local out = {}
    for _, nid in ipairs((ctx.graph.ambushByRegion or {})[regionId] or {}) do out[#out + 1] = ctx.graph.nodes[nid] end
    return out
end

---Display label of a node: its @world `label`, else its id.
function M.nodeLabel(ctx, nodeId)
    local n = ctx.graph.nodes[nodeId]
    return (n and n.label) or tostring(nodeId)
end

---Squads sorted by id, optionally only one goal.
function M.listSquads(state, goal)
    local out = {}
    for _, id in ipairs(sortedKeys(state.squads)) do
        local sq = state.squads[id]
        if goal == nil or sq.goal == goal then out[#out + 1] = sq end
    end
    return out
end

---The live (not returning) ambush squad holding or heading to a node, or nil.
local function nodeSquad(state, nodeId)
    for _, id in ipairs(sortedKeys(state.squads)) do
        local sq = state.squads[id]
        if sq.goal == 'ambush' and sq.node == nodeId and sq.phase ~= 'return' then return sq end
    end
    return nil
end

local function liveAmbushInRegion(state, regionId)
    local n = 0
    for _, sq in pairs(state.squads) do
        if sq.goal == 'ambush' and sq.region == regionId and sq.phase ~= 'return' then n = n + 1 end
    end
    return n
end

---One /alife line for a region's ambush nodes: "<region>: no ambush nodes" or
---"<region>: N ambush node(s): <label>=free, <label>=sq3 outlaws x4 hold, ...".
function M.describeAmbush(ctx, state, regionId)
    local nodes = M.ambushNodes(ctx, regionId)
    if #nodes == 0 then return ('%s: no ambush nodes'):format(tostring(regionId)) end
    local parts = {}
    for _, node in ipairs(nodes) do
        local sq = nodeSquad(state, node.id)
        parts[#parts + 1] = sq and ('%s=%s %s x%d %s'):format(M.nodeLabel(ctx, node.id), sq.id, sq.faction,
            sq.strength or 0, sq.phase) or ('%s=free'):format(M.nodeLabel(ctx, node.id))
    end
    return ('%s: %d ambush node(s): %s'):format(tostring(regionId), #nodes, table.concat(parts, ', '))
end

-- ---------------------------------------------------------------- transitions

---Set a camp's owner. @return string|nil from (previous effective owner)
function M.flip(ctx, state, campId, to)
    local from = M.getOwner(ctx, state, campId)
    state.owners[campId] = to
    return from
end

---Spawn a retake squad for a law-held camp (the territory's default faction marches back).
---@return table|nil squad
function M.spawnRetakeSquad(ctx, state, campId, rng)
    rng = rng or math.random
    local camp = ctx.camps[campId]
    if not camp then return nil end
    local faction = defaultOwner(ctx.regions, ctx.camps, campId)
    if not faction then return nil end
    local r = ctx.cfg.retake or {}
    local id = 'sq' .. tostring(state.nextSquadId)
    state.nextSquadId = state.nextSquadId + 1
    local squad = {
        id = id,
        faction = faction,
        strength = rng(r.strengthMin or 1, r.strengthMax or 1),
        from = camp.region, -- town node
        to = campId,        -- camp node
        etaTick = state.tick + rng(r.minTicks or 1, r.maxTicks or 1),
        goal = 'retake',
    }
    state.squads[id] = squad
    return squad
end

local function newSquadId(state)
    local id = 'sq' .. tostring(state.nextSquadId)
    state.nextSquadId = state.nextSquadId + 1
    return id
end

---Spend `amount` damage on a camp's holding reinforce squads (id order); a squad at 0 is removed.
local function damageHolders(state, campId, amount)
    for _, id in ipairs(sortedKeys(state.squads)) do
        if amount <= 0 then return end
        local sq = state.squads[id]
        if sq.goal == 'reinforce' and sq.to == campId and sq.phase == 'hold' then
            local hit = math.min(amount, sq.strength or 0)
            sq.strength = (sq.strength or 0) - hit
            amount = amount - hit
            if sq.strength <= 0 then state.squads[id] = nil end
        end
    end
end

---Resolve a retake squad whose etaTick passed (the caller already removed it from state.squads). The roll:
---effective = strength - regionPressure[region][faction] (the pressure is consumed by this roll). The retake lands
---when effective > holderStrength (law's holding reinforce squads, which are then removed); otherwise it fails, the
---holders lose `effective` strength and the faction regroups (a new retake squad). With no pressure and no
---reinforcements any strength >= 1 dislodges the empty camp, as in a-life-01.
---@return table effects
function M.resolveSquad(ctx, state, squad, rng)
    rng = rng or math.random
    if squad.goal ~= 'retake' then return {} end
    local campId = squad.to
    local camp = ctx.camps[campId]
    if not camp then return {} end
    local from = M.getOwner(ctx, state, campId)
    if from == squad.faction then return {} end
    local pressure = M.getPressure(state, camp.region, squad.faction)
    if pressure > 0 then state.regionPressure[camp.region][squad.faction] = nil end
    local effective = math.max(0, (squad.strength or 0) - pressure)
    local holder = M.holderStrength(state, campId)
    if effective <= holder then
        damageHolders(state, campId, effective)
        local effects = {
            { type = 'retake_failed', camp_id = campId, region_id = camp.region, faction = squad.faction,
                strength = squad.strength or 0, pressure = pressure, holder = holder },
            { type = 'broadcast', message = ('%s failed to retake the %s'):format(
                factionLabel(ctx.regions, squad.faction, camp.region), campLabel(ctx.regions, ctx.camps, campId)) },
        }
        if M.isLawHeld(ctx, state, campId) then M.spawnRetakeSquad(ctx, state, campId, rng) end
        return effects
    end
    for _, id in ipairs(sortedKeys(state.squads)) do
        local sq = state.squads[id]
        if sq.goal == 'reinforce' and sq.to == campId then state.squads[id] = nil end
    end
    M.flip(ctx, state, campId, squad.faction)
    local effects = {
        { type = 'flipped', camp_id = campId, region_id = camp.region, from = from, to = squad.faction },
        { type = 'broadcast', message = ('%s have retaken the %s'):format(factionLabel(ctx.regions, squad.faction, camp.region),
            campLabel(ctx.regions, ctx.camps, campId)) },
    }
    local sh = shortageEffect(ctx, camp.region, 'raised')
    if sh then effects[#effects + 1] = sh end
    return effects
end

---Advance an ambush or reinforce squad whose etaTick passed through its phases. @return table effects
local function advanceSquad(ctx, state, sq)
    local t = state.tick
    if sq.goal == 'ambush' then
        if sq.phase == 'travel' then
            local holdTicks = math.max(1, math.floor(((ctx.cfg.raids or {}).holdTicks) or 1))
            sq.phase, sq.etaTick = 'hold', t + holdTicks
            return { { type = 'ambush_holding', squad_id = sq.id, node = sq.node, region_id = sq.region,
                faction = sq.faction, strength = sq.strength, label = M.nodeLabel(ctx, sq.node) } }
        elseif sq.phase == 'hold' then
            sq.phase, sq.etaTick = 'return', t + (sq.travel or 1)
            return {}
        end
        state.squads[sq.id] = nil
        return { { type = 'squad_returned', reason = 'returned', squad_id = sq.id, goal = sq.goal, faction = sq.faction,
            camp_id = sq.from, node = sq.node, region_id = sq.region, strength = sq.strength or 0 } }
    end
    -- reinforce (data only, silent): travel -> hold; hold renews while the camp stays held by its faction.
    local holdTicks = math.max(1, math.floor(((ctx.cfg.reinforce or {}).holdTicks) or 1))
    if sq.phase == 'travel' then
        sq.phase, sq.etaTick = 'hold', t + holdTicks
    elseif sq.phase == 'hold' and M.getOwner(ctx, state, sq.to) == sq.faction then
        sq.etaTick = t + holdTicks
    elseif sq.phase == 'hold' then
        sq.phase, sq.etaTick = 'return', t + (sq.travel or 1)
    else
        state.squads[sq.id] = nil
    end
    return {}
end

---Law-held camps in enabled regions without a reinforce squad get one (deterministic: no rng).
function M.planReinforcements(ctx, state)
    local rc = ctx.cfg.reinforce or {}
    local strength = math.floor(finite(rc.strength) and rc.strength or 0)
    if strength < 1 then return end
    local travel = math.max(1, math.floor(finite(rc.travelTicks) and rc.travelTicks or 1))
    local covered = {}
    for _, sq in pairs(state.squads) do
        if sq.goal == 'reinforce' then covered[sq.to] = true end
    end
    for _, campId in ipairs(sortedKeys(ctx.camps)) do
        local camp = ctx.camps[campId]
        if not covered[campId] and M.isLawHeld(ctx, state, campId) and regionEnabled(ctx.regions, camp.region) then
            local id = newSquadId(state)
            state.squads[id] = { id = id, goal = 'reinforce', faction = M.getOwner(ctx, state, campId),
                strength = strength, from = camp.region, to = campId, region = camp.region, phase = 'travel',
                travel = travel, etaTick = state.tick + travel }
        end
    end
end

---Outlaw raids: each outlaw-held camp (sorted) in a region with ambush nodes rolls raids.chancePct (rng(1, 100)) to
---send a squad to a free node, while the region is under raids.regionCap. Rolls, in order: chance, node, travel,
---strength. A region with no ambush nodes rolls nothing. @return table effects ({ type = 'ambush_sent', ... })
function M.planRaids(ctx, state, rng)
    rng = rng or math.random
    local rc = ctx.cfg.raids or {}
    local chance = finite(rc.chancePct) and rc.chancePct or 0
    local cap = math.floor(finite(rc.regionCap) and rc.regionCap or 0)
    local effects = {}
    if chance <= 0 or cap < 1 then return effects end
    for _, campId in ipairs(sortedKeys(ctx.camps)) do
        local camp = ctx.camps[campId]
        local nodeIds = (ctx.graph.ambushByRegion or {})[camp.region]
        local owner = M.getOwner(ctx, state, campId)
        if nodeIds and #nodeIds > 0 and owner and not M.isLawFaction(ctx.regions.factions, owner)
            and liveAmbushInRegion(state, camp.region) < cap then
            local free = {}
            for _, nid in ipairs(nodeIds) do
                if not nodeSquad(state, nid) then free[#free + 1] = nid end
            end
            if #free > 0 and rng(1, 100) <= chance then
                local node = free[rng(1, #free)]
                local travel = math.max(1, math.floor(rng(rc.travelMin or 1, rc.travelMax or 1)))
                local id = newSquadId(state)
                local sq = { id = id, goal = 'ambush', faction = owner,
                    strength = rng(rc.strengthMin or 1, rc.strengthMax or 1), from = campId, to = node, node = node,
                    region = camp.region, phase = 'travel', travel = travel, etaTick = state.tick + travel }
                state.squads[id] = sq
                effects[#effects + 1] = { type = 'ambush_sent', squad_id = id, camp_id = campId, node = node,
                    region_id = camp.region, faction = owner, strength = sq.strength, label = M.nodeLabel(ctx, node) }
            end
        end
    end
    return effects
end

---A squad member died (B2 death watch). Takes `n` (default 1) off strength. A non-law squad's losses add to
---regionPressure[region][faction] (capped at raids.pressureMax). At 0 the squad is wiped and removed.
---@return table effects, string|nil err
function M.onSquadKill(ctx, state, squadId, n)
    local sq = state.squads[squadId]
    if not sq then return {}, 'fh_alife_no_squad' end
    n = (finite(n) and math.floor(n) >= 1) and math.floor(n) or 1
    local lost = math.min(n, math.max(0, sq.strength or 0))
    sq.strength = (sq.strength or 0) - lost
    local regionId = sq.region or (ctx.camps[sq.from] and ctx.camps[sq.from].region)
    if lost > 0 and regionId and not M.isLawFaction(ctx.regions.factions, sq.faction) then
        state.regionPressure[regionId] = state.regionPressure[regionId] or {}
        local p = (state.regionPressure[regionId][sq.faction] or 0) + lost
        local maxP = (ctx.cfg.raids or {}).pressureMax
        if finite(maxP) then p = math.min(p, math.max(0, math.floor(maxP))) end
        state.regionPressure[regionId][sq.faction] = p > 0 and p or nil
    end
    if sq.strength > 0 then return {} end
    state.squads[squadId] = nil
    return { { type = 'squad_wiped', squad_id = squadId, goal = sq.goal, faction = sq.faction, node = sq.node,
        camp_id = sq.from, region_id = regionId, label = sq.node and M.nodeLabel(ctx, sq.node) or nil } }
end

---Advance the sim by `n` ticks (default 1). Each step: prune squads whose node is gone, resolve squads due at or
---before the new tick (etaTick, then id order), then plan reinforcements and raids. 'raid' squads (a-life-03) are
---skipped here: the caller runs FhAlifeRaidRules.tick after each step. @return table effects
function M.tick(ctx, state, n, rng)
    rng = rng or math.random
    state.regionPressure = state.regionPressure or {}
    local steps = finite(n) and math.max(1, math.floor(n)) or 1
    local effects = {}
    local function add(list) for _, e in ipairs(list) do effects[#effects + 1] = e end end
    for _ = 1, steps do
        state.tick = state.tick + 1
        add(M.pruneSquads(ctx, state))
        local due = {}
        for _, squad in pairs(state.squads) do
            if (squad.etaTick or 0) <= state.tick then due[#due + 1] = squad end
        end
        table.sort(due, function(a, b)
            if a.etaTick ~= b.etaTick then return a.etaTick < b.etaTick end
            return a.id < b.id
        end)
        for _, squad in ipairs(due) do
            -- an earlier resolution may have removed it; 'raid' squads belong to raid_rules.tick
            if state.squads[squad.id] == squad and squad.goal ~= 'raid' then
                if squad.goal == 'ambush' or squad.goal == 'reinforce' then
                    add(advanceSquad(ctx, state, squad))
                else
                    state.squads[squad.id] = nil
                    add(M.resolveSquad(ctx, state, squad, rng))
                end
            end
        end
        M.planReinforcements(ctx, state)
        add(M.planRaids(ctx, state, rng))
    end
    return effects
end

---The owner cleared a camp: law holds it now. Effects: flip to region law, shortage relief (on the transition), broadcast.
---Also schedules the retake squad when one is not already en route. Camp_clear HEAT is not emitted here: fh_heat owns it
---via its own fh:zones:camp_cleared listener, so a clear must never double-apply heat.
---A region with no law faction (regionLawFaction -> nil) is logged and the flip is skipped: no flip effects
---(flipped / broadcast / shortage / retake) and no error.
---@param participants string[] citizenids inside the camp at clear (accepted for API stability; fh_alife no longer uses it)
---@param log fun(msg:string)? called once with a reason string when there is no law faction to flip to
---@return table effects
function M.onCampCleared(ctx, state, campId, participants, rng, log)
    rng = rng or math.random
    local camp = ctx.camps[campId]
    if not camp then return {} end
    local law = M.regionLawFaction(ctx.regions, camp.region)
    local oldOwner = M.getOwner(ctx, state, campId)
    local effects = {}
    local justFlipped = law ~= nil and law ~= oldOwner

    if not law then
        if log then log(('no law faction for region %s; camp %s stays %s (no flip)'):format(
            camp.region, campId, tostring(oldOwner))) end
    end

    if justFlipped then
        M.flip(ctx, state, campId, law)
        effects[#effects + 1] = { type = 'flipped', camp_id = campId, region_id = camp.region, from = oldOwner, to = law }
        effects[#effects + 1] = { type = 'broadcast', message = ('%s has taken the %s'):format(factionLabel(ctx.regions, law, camp.region),
            campLabel(ctx.regions, ctx.camps, campId)) }
    end

    if M.isLawHeld(ctx, state, campId) then
        if justFlipped then
            local sh = shortageEffect(ctx, camp.region, 'relieved')
            if sh then effects[#effects + 1] = sh end
        end
        local pending = false
        for _, sq in pairs(state.squads) do
            if sq.to == campId and sq.goal == 'retake' then pending = true break end
        end
        if not pending then M.spawnRetakeSquad(ctx, state, campId, rng) end
    end

    return effects
end

if GetCurrentResourceName then
    FhAlifeRules = M
else
    return M
end

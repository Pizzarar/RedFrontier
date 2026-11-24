-- fh_alife pure A-Life rules: camp ownership graph + retake squads. No natives, no DB, no os.time/GetGameTimer:
-- the caller injects `rng` (default math.random) and advances time in integer ticks. Specced in spec/alife_rules_spec.lua.
--
-- Model (A1):
--  * node graph: one camp node per fh_zones camp, one town node per FhRegions region.
--  * owners: campId -> factionId; the default owner is the camp territory's `faction` (regions.territories).
--  * squads: plain data { id, faction, strength, from, to, etaTick, goal = 'raid'|'reinforce'|'retake' }.
--  * tick(n) advances the clock and resolves squads whose etaTick has passed. The weighted dice rolls squad
--    strength and etaTick at spawn; a retake squad of any strength >= 1 dislodges the (empty) camp on arrival.
--  * effects are plain tables { type = 'broadcast'|'heat'|'shortage'|'flipped', ... } the server applies.
-- Law detection: a faction is law if its `kind == 'law'`; when `kind` is absent, fall back to { lawmen, rhodes_law }.
local M = {}

M.VERSION = 1

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

---Node graph: one camp node per camp (id = camp id), one town node per region (id = region id). `cfg` is accepted for
---future edges (e.g. road links); the A1 graph is nodes only.
function M.buildGraph(cfg, regions, camps)
    local nodes = {}
    for _, camp in pairs(camps or {}) do
        if type(camp) == 'table' and type(camp.id) == 'string' then
            nodes[camp.id] = { id = camp.id, type = 'camp', region = camp.region, territory = camp.territory }
        end
    end
    for id, region in pairs((regions and regions.regions) or {}) do
        nodes[id] = { id = id, type = 'town', region = id }
    end
    return { nodes = nodes }
end

---Bundle the sim's static context (cfg + regions + camps + graph) for the transition functions.
function M.context(cfg, regions, camps)
    return { cfg = cfg, regions = regions, camps = camps or {}, graph = M.buildGraph(cfg, regions, camps) }
end

function M.newState()
    return { version = M.VERSION, tick = 0, owners = {}, squads = {}, nextSquadId = 1 }
end

---Plain-table serialization (JSON-safe; the server json.encode's it for KVP). Deserialize reverses it.
function M.serialize(state)
    return { version = state.version, tick = state.tick, owners = state.owners, squads = state.squads,
        nextSquadId = state.nextSquadId }
end

---@return table|nil state, string|nil err
function M.deserialize(t)
    if type(t) ~= 'table' then return nil, 'fh_alife_bad_state' end
    if t.version ~= M.VERSION then return nil, 'fh_alife_version' end
    local s = M.newState()
    s.tick = math.tointeger(t.tick) or 0
    s.nextSquadId = math.tointeger(t.nextSquadId) or 1
    s.owners = type(t.owners) == 'table' and t.owners or {}
    s.squads = type(t.squads) == 'table' and t.squads or {}
    return s
end

-- ---------------------------------------------------------------- helpers

local function defaultOwner(regions, camps, campId)
    local camp = camps[campId]
    local terr = camp and camp.territory and regions and regions.territories and regions.territories[camp.territory]
    return terr and terr.faction or nil
end

local function factionLabel(regions, id)
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

---Resolve a squad whose etaTick passed. A retake squad flips the camp back to its faction (the weighted dice rolled
---strength at spawn; any strength >= 1 dislodges the empty camp, so the retake lands on arrival).
---@return table effects
function M.resolveSquad(ctx, state, squad, rng)
    rng = rng or math.random
    if squad.goal ~= 'retake' then return {} end
    local campId = squad.to
    local camp = ctx.camps[campId]
    if not camp then return {} end
    if (squad.strength or 0) < 1 then return {} end
    local from = M.getOwner(ctx, state, campId)
    if from == squad.faction then return {} end
    M.flip(ctx, state, campId, squad.faction)
    local effects = {
        { type = 'flipped', camp_id = campId, region_id = camp.region, from = from, to = squad.faction },
        { type = 'broadcast', message = ('%s have retaken the %s'):format(factionLabel(ctx.regions, squad.faction),
            campLabel(ctx.regions, ctx.camps, campId)) },
    }
    local sh = shortageEffect(ctx, camp.region, 'raised')
    if sh then effects[#effects + 1] = sh end
    return effects
end

---Advance the sim by `n` ticks (default 1), resolving squads due at or before the new tick. @return table effects
function M.tick(ctx, state, n, rng)
    rng = rng or math.random
    local steps = finite(n) and math.max(1, math.floor(n)) or 1
    local effects = {}
    for _ = 1, steps do
        state.tick = state.tick + 1
        local due = {}
        for _, squad in pairs(state.squads) do
            if (squad.etaTick or 0) <= state.tick then due[#due + 1] = squad end
        end
        table.sort(due, function(a, b)
            if a.etaTick ~= b.etaTick then return a.etaTick < b.etaTick end
            return a.id < b.id
        end)
        for _, squad in ipairs(due) do
            state.squads[squad.id] = nil
            for _, e in ipairs(M.resolveSquad(ctx, state, squad, rng)) do effects[#effects + 1] = e end
        end
    end
    return effects
end

---The owner cleared a camp: law holds it now. Effects: flip to region law, heat per participant against the old owner,
---shortage relief (on the transition), broadcast. Also schedules the retake squad when one is not already en route.
---@param participants string[] citizenids inside the camp at clear
---@return table effects
function M.onCampCleared(ctx, state, campId, participants, rng)
    rng = rng or math.random
    local camp = ctx.camps[campId]
    if not camp then return {} end
    local law = M.regionLawFaction(ctx.regions, camp.region)
    local oldOwner = M.getOwner(ctx, state, campId)
    local effects = {}
    local justFlipped = law ~= nil and law ~= oldOwner

    if justFlipped then
        M.flip(ctx, state, campId, law)
        effects[#effects + 1] = { type = 'flipped', camp_id = campId, region_id = camp.region, from = oldOwner, to = law }
        effects[#effects + 1] = { type = 'broadcast', message = ('%s has taken the %s'):format(factionLabel(ctx.regions, law),
            campLabel(ctx.regions, ctx.camps, campId)) }
    end

    if oldOwner then
        for _, pid in ipairs(participants or {}) do
            if type(pid) == 'string' and pid ~= '' then
                effects[#effects + 1] = { type = 'heat', citizenid = pid, faction = oldOwner }
            end
        end
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

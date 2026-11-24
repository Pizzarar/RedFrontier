-- fh_alife contracts rules (a-life-02 B3): the alife_contract job type's offers and verdicts. Pure Lua: no
-- natives, no DB, no clock — the caller injects `ctx` (FhAlifeRules.context) and `state`. Specced in
-- spec/contracts_rules_spec.lua.
--
-- Implemented A-Life — Thanks to S.T.A.L.K.E.R. A-Life by GSC Game World.
--
-- alife_contract offers, per enabled region (FhRegions.isEnabled):
--   * "clear <camp>" for every outlaw-held camp in the region, paying on fh:zones:camp_cleared (credit via
--     payload.participants, exactly like the built-in camp_clear job type).
--   * "break the ambush at <node label or id>" for every ambush node a squad is currently holding (phase 'hold'),
--     paying on fh:alife:squad_wiped (payload { squadId, nodeId, region, faction }; for a player to be credited the
--     emitter must also carry participants, as camp_cleared does — see B2's emitter).
-- A region with no ambush nodes offers only camp jobs, with no errors. A disabled region offers nothing.
local M = {}

M.JOB_TYPE = 'alife_contract'
M.CAMP_EVENT = 'fh:zones:camp_cleared'
M.SQUAD_EVENT = 'fh:alife:squad_wiped'

-- Reward tuning lives here for now (a-life-02 B3 adds no config hook); move to FhAlifeConfig if it should vary.
M.REWARDS = {
    camp = { money = 40, rep = 3 }, -- matches the built-in camp_clear template (heartlands)
    ambush = { money = 30, rep = 2 },
}

-- Fallback set used only when a faction has no `kind` field (same aliases as alife_rules.lua).
local LAW_FALLBACK = { lawmen = true, rhodes_law = true }

local function sortedKeys(t)
    local ks = {}
    for k in pairs(t or {}) do if type(k) == 'string' then ks[#ks + 1] = k end end
    table.sort(ks)
    return ks
end

---Is a region enabled? Feature-detects regions.isEnabled (world-01 block D); without it every region is enabled.
local function regionEnabled(ctx, regionId)
    local regions = ctx and ctx.regions
    if type(regions) ~= 'table' or type(regions.isEnabled) ~= 'function' then return true end
    local ok, on = pcall(regions.isEnabled, regionId)
    return ok and on == true
end

---Is a faction law? `factions` = FhRegions.factions. `kind == 'law'` wins; otherwise the fallback set.
local function isLawFaction(factions, id)
    if type(id) ~= 'string' then return false end
    local f = type(factions) == 'table' and factions[id] or nil
    if f and f.kind ~= nil then return f.kind == 'law' end
    return LAW_FALLBACK[id] == true
end

---Default owner of a camp: its territory's faction, or nil.
local function defaultOwner(ctx, campId)
    local camp = ctx.camps and ctx.camps[campId] or nil
    local terr = camp and camp.territory and ctx.regions and ctx.regions.territories
        and ctx.regions.territories[camp.territory] or nil
    return terr and terr.faction or nil
end

---Effective owner: an explicit flip if present, else the territory's default faction.
function M.getOwner(ctx, state, campId)
    if state and state.owners and state.owners[campId] then return state.owners[campId] end
    return defaultOwner(ctx, campId)
end

---Is a camp law-held? (An outlaw-held camp — the "clear <camp>" target — is simply not law-held.)
function M.isLawHeld(ctx, state, campId)
    local o = M.getOwner(ctx, state, campId)
    return o ~= nil and isLawFaction(ctx.regions and ctx.regions.factions, o)
end

---The ambush squad currently holding `nodeId` (phase 'hold'), or nil. Travel/return squads never count: a squad is
---only breakable once it has materialised on the node (a-life-02 B1 "wake when near").
function M.holdingSquad(state, nodeId)
    for _, sq in pairs((state and state.squads) or {}) do
        if sq.goal == 'ambush' and sq.node == nodeId and sq.phase == 'hold' then return sq end
    end
    return nil
end

local function campLabel(ctx, campId)
    local camp = ctx.camps and ctx.camps[campId] or nil
    local terr = camp and camp.territory and ctx.regions and ctx.regions.territories
        and ctx.regions.territories[camp.territory] or nil
    if terr and terr.label then return terr.label end
    return (camp and camp.name) or campId
end

local function nodeLabel(ctx, nodeId)
    local n = ctx.graph and ctx.graph.nodes and ctx.graph.nodes[nodeId] or nil
    return (n and n.label) or tostring(nodeId)
end

---Camp ids of a region, sorted by id (stable order; the board sort re-orders them regardless).
local function campsInRegion(ctx, regionId)
    local out = {}
    for _, campId in ipairs(sortedKeys(ctx.camps or {})) do
        local camp = ctx.camps[campId]
        if camp.region == regionId then out[#out + 1] = campId end
    end
    return out
end

local function rewards(regionId, spec)
    return { money = spec.money, rep = { region_id = regionId, delta = spec.rep } }
end

local function campOffer(ctx, regionId, campId)
    local label = campLabel(ctx, campId)
    return {
        key = 'camp_' .. campId,
        title = 'Clear out: ' .. label,
        text = 'Wipe out the outlaws at the ' .. label .. '.',
        on = M.CAMP_EVENT,
        where = { camp_id = campId },
        rewards = rewards(regionId, M.REWARDS.camp),
    }
end

local function ambushOffer(ctx, regionId, nodeId)
    local label = nodeLabel(ctx, nodeId)
    return {
        key = 'ambush_' .. nodeId,
        title = 'Break the ambush: ' .. label,
        text = 'A gang is waiting in ambush at ' .. label .. '. Break it up.',
        on = M.SQUAD_EVENT,
        where = { nodeId = nodeId },
        rewards = rewards(regionId, M.REWARDS.ambush),
    }
end

---Candidate offers of the alife_contract job type for a region. Fresh tables every call; {} for a disabled or
---unknown region (no error). Outlaw-held camps become "clear <camp>"; nodes a squad holds become
---"break the ambush at <node>". A region with no ambush nodes yields camp offers only.
function M.offers(ctx, state, regionId)
    if not regionEnabled(ctx, regionId) then return {} end
    local out = {}
    for _, campId in ipairs(campsInRegion(ctx, regionId)) do
        if not M.isLawHeld(ctx, state, campId) then out[#out + 1] = campOffer(ctx, regionId, campId) end
    end
    local nodeIds = (ctx.graph and ctx.graph.ambushByRegion and ctx.graph.ambushByRegion[regionId]) or {}
    for _, nodeId in ipairs(nodeIds) do
        if M.holdingSquad(state, nodeId) then out[#out + 1] = ambushOffer(ctx, regionId, nodeId) end
    end
    return out
end

---The accepted-offer snapshot (progress.job), the source of truth for what a job needs.
local function snapOf(job_type, state)
    local snap = type(state) == 'table' and type(state.progress) == 'table' and state.progress.job or nil
    if type(snap) ~= 'table' or snap.job_type ~= job_type then return nil end
    return snap
end

---hooks.onEvent decision for alife_contract. Only the offer's own event plus its flat `where` predicates match;
---credit (payload.participants / citizenid) is the engine's `eligible` gate, which runs before this hook is called.
---A "clear <camp>" job advances on fh:zones:camp_cleared where camp_id matches; a "break the ambush" job advances
---on fh:alife:squad_wiped where nodeId matches. @return 'progress' | nil
function M.verdict(job_type, eventName, payload, state)
    local snap = snapOf(job_type, state)
    if not snap or type(payload) ~= 'table' then return nil end
    if eventName ~= snap.on then return nil end
    local where = snap.where
    if type(where) ~= 'table' then return nil end
    for field, want in pairs(where) do
        if payload[field] ~= want then return nil end
    end
    return 'progress'
end

if GetCurrentResourceName then
    FhAlifeContracts = M
else
    return M
end

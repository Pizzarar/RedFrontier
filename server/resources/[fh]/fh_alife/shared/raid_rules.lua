-- fh_alife pure wilderness-claim raid rules (plan a-life-03 C1). No natives, no DB, no server I/O, no clock: the caller
-- injects `rng` (default math.random), plot facts and online/home flags, and runs tick() once per sim tick, right
-- after FhAlifeRules.tick(ctx, state, 1). Specced in spec/raid_rules_spec.lua.
-- Implemented A-Life — Thanks to S.T.A.L.K.E.R. A-Life by GSC Game World.
--
-- Inputs (coordinate-free). Plot facts = fh_homestead plotInfo plus the C0 fields:
--   { plotId?, class, raidable, lawSafe?, owner, coords?, region, fenceBuilt }   (coords are never read here)
-- world (per tick) = { plots = { [plotId] = facts }, online = { [citizenid] = true }, home = { [plotId] = true } };
--   home[plotId] = the claim owner is at the claim (within claimRaids.raidRadius, computed by the server).
--
-- Model:
--  * eligible claim: raidable == true, class a non-empty string other than 'town_lot', lawSafe ~= true, an owner
--    citizenid, and that owner online. Town lots never raid (raidable false or class 'town_lot' or lawSafe).
--  * odds per tick and eligible claim: chance = baseChance x (outlaw-held camps in the claim's region) x
--    (1 - fenceMitigation when fenceBuilt), capped at 1, rolled as rng(1, 10000) <= chance x 10000. A region with
--    no outlaw-held camp (or a disabled region, or chance 0) makes no rng call at all.
--  * gates: per-claim cooldown (cooldownTicks, starts at the warning), one live raid per claim, and at most liveCap
--    live (not returning) raids in the world. Claims are considered in plot id order.
--  * raiding camp: the first (sorted id) outlaw-held camp in the claim's region.
--  * raid squad = a state.squads entry with goal 'raid' (so FhAlifeRules.onSquadKill's regionPressure applies):
--    { id, goal = 'raid', faction, strength, from = campId, to = plotId, plot = plotId, region, citizenid,
--      phase = 'warn'|'fight'|'return', mode = nil|'fight'|'steal', travel, etaTick, cancelled = reason|nil }
--  * lifecycle: warn --(warnTicks)--> arrive: owner home -> 'fight' (fightTicks on foot at the claim, squad goal
--    'raid', spawn owner tag OWNER_TAG) then withdraw; owner away -> steal (effect raid_steal; the server picks with
--    pickSteal and moves chest 1 -> the camp's stash) -> 'return' (travel ticks) -> removed (raid_returned).
--    Before 'return', at any phase: owner offline, plot gone / no longer raidable, or owner changed -> cancelled
--    (straight to 'return', nothing stolen). During 'warn' the raiding camp lost (law took it) -> cancelled too.
--  * repelled: onSquadKill wiping a raid squad -> squad_wiped + raid_repelled; regionPressure exactly as a-life-02.
--  * save: FhAlifeRules v3 (raidCooldowns + 'raid' squads). deserialize drops raids whose plot or camp is gone.
local Rules = FhAlifeRules
assert(type(Rules) == 'table', 'fh_alife raid_rules: load shared/alife_rules.lua first (FhAlifeRules)')

local M = {}

M.GOAL = 'raid'
M.OWNER_TAG = 'alife_raid' -- C2: requestSpawn owner = { kind = OWNER_TAG, id = squadId }

-- Fallbacks when FhAlifeConfig.claimRaids lacks a knob (config.lua documents each).
M.DEFAULTS = {
    baseChance = 0.01, fenceMitigation = 0.5, cooldownTicks = 180, liveCap = 2, warnTicks = 5, fightTicks = 10,
    returnTicks = 3, strengthMin = 3, strengthMax = 5, stealStacks = 2, stealMaxFraction = 0.5,
}

local ROLL = 10000 -- odds resolution: chance is rolled as rng(1, ROLL) <= chance * ROLL
local PHASES = { warn = true, fight = true, ['return'] = true }
local MODES = { fight = true, steal = true }

local function finite(n) return type(n) == 'number' and n == n and n > -math.huge and n < math.huge end

local function sortedKeys(t)
    local ks = {}
    for k in pairs(t or {}) do if type(k) == 'string' then ks[#ks + 1] = k end end
    table.sort(ks)
    return ks
end

local function knob(ctx, k)
    local c = ctx and ctx.cfg and ctx.cfg.claimRaids
    local v = type(c) == 'table' and c[k] or nil
    if finite(v) then return v end
    return M.DEFAULTS[k]
end

local function intKnob(ctx, k, min) return math.max(min, math.floor(knob(ctx, k))) end

local function clamp01(v) return math.min(1, math.max(0, v)) end

local function factionsOf(ctx) return ctx.regions and ctx.regions.factions or nil end

local function campLabel(ctx, campId)
    local camp = ctx.camps and ctx.camps[campId]
    local terr = camp and camp.territory and ctx.regions and ctx.regions.territories
        and ctx.regions.territories[camp.territory]
    return (terr and terr.label) or tostring(campId)
end

-- ---------------------------------------------------------------- eligibility + odds

---Is a plot a raid target at all (ignoring online)? Town lots and plots with a missing/bad class never are.
---@return boolean ok, string|nil reason  'not_raidable' | 'no_owner'
function M.isRaidablePlot(plot)
    if type(plot) ~= 'table' or plot.raidable ~= true or plot.lawSafe == true then return false, 'not_raidable' end
    if type(plot.class) ~= 'string' or plot.class == '' or plot.class == 'town_lot' then return false, 'not_raidable' end
    if type(plot.owner) ~= 'string' or plot.owner == '' then return false, 'no_owner' end
    return true
end

---Eligible now: isRaidablePlot and the owner is online. `online` = { [citizenid] = true } or a boolean for this owner.
---@return boolean ok, string|nil reason  'not_raidable' | 'no_owner' | 'owner_offline'
function M.eligible(plot, online)
    local ok, why = M.isRaidablePlot(plot)
    if not ok then return false, why end
    local on = online == true or (type(online) == 'table' and online[plot.owner] == true)
    if not on then return false, 'owner_offline' end
    return true
end

---Outlaw-held (owner set and not law) camps of a region, sorted by id. {} for a disabled or unknown region.
function M.outlawCamps(ctx, state, regionId)
    local out = {}
    if type(regionId) ~= 'string' or not Rules.regionEnabled(ctx.regions, regionId) then return out end
    for _, campId in ipairs(sortedKeys(ctx.camps)) do
        local camp = ctx.camps[campId]
        if type(camp) == 'table' and camp.region == regionId then
            local o = Rules.getOwner(ctx, state, campId)
            if o and not Rules.isLawFaction(factionsOf(ctx), o) then out[#out + 1] = campId end
        end
    end
    return out
end

---The camp that raids claims in a region: the first outlaw-held camp by id, or nil.
function M.raidingCamp(ctx, state, regionId) return M.outlawCamps(ctx, state, regionId)[1] end

---Per-tick raid chance of a claim (0..1) and the count of outlaw-held camps in its region. Eligibility not checked.
---@return number chance, integer camps
function M.raidChance(ctx, state, plot)
    local n = #M.outlawCamps(ctx, state, type(plot) == 'table' and plot.region or nil)
    if n == 0 then return 0, 0 end
    local p = math.max(0, knob(ctx, 'baseChance')) * n
    if plot.fenceBuilt == true then p = p * (1 - clamp01(knob(ctx, 'fenceMitigation'))) end
    return math.min(1, p), n
end

-- ---------------------------------------------------------------- queries

---Every raid squad (any phase), sorted by id.
function M.listRaids(state) return Rules.listSquads(state, M.GOAL) end

---The live (not returning) raid on a plot, or nil.
function M.raidForPlot(state, plotId)
    for _, sq in ipairs(M.listRaids(state)) do
        if sq.plot == plotId and sq.phase ~= 'return' then return sq end
    end
    return nil
end

---Live (not returning) raids in the world.
function M.liveRaidCount(state)
    local n = 0
    for _, sq in pairs(state.squads) do
        if sq.goal == M.GOAL and sq.phase ~= 'return' then n = n + 1 end
    end
    return n
end

---Is a claim on raid cooldown at state.tick? @return boolean, integer|nil untilTick
function M.onCooldown(state, plotId)
    local u = state.raidCooldowns and state.raidCooldowns[plotId]
    if u ~= nil and state.tick < u then return true, u end
    return false, nil
end

---One /alife line: "sq7 raid plot_a by outlaws x4 from <camp label> warn (eta tick 12)".
function M.describeRaid(ctx, sq)
    local extra = sq.cancelled and (' cancelled:' .. tostring(sq.cancelled)) or (sq.mode and (' ' .. sq.mode) or '')
    return ('%s raid %s by %s x%d from %s %s%s (eta tick %d)'):format(sq.id, tostring(sq.plot), tostring(sq.faction),
        sq.strength or 0, campLabel(ctx, sq.from), sq.phase, extra, sq.etaTick or 0)
end

-- ---------------------------------------------------------------- transitions

local function base(sq)
    return { squad_id = sq.id, plot_id = sq.plot, citizenid = sq.citizenid, camp_id = sq.from, region_id = sq.region,
        faction = sq.faction, strength = sq.strength or 0 }
end

local function withType(t, e) e.type = t return e end

---Create a raid in 'warn' on `plotId` from `campId` and start the claim's cooldown. Rolls strength (one rng call).
local function startRaid(ctx, state, plotId, plot, campId, rng)
    local warn = intKnob(ctx, 'warnTicks', 1)
    local sMin = intKnob(ctx, 'strengthMin', 1)
    local sMax = math.max(sMin, intKnob(ctx, 'strengthMax', 1))
    local strength = math.max(1, math.floor(tonumber(rng(sMin, sMax)) or sMin))
    local id = 'sq' .. tostring(state.nextSquadId)
    state.nextSquadId = state.nextSquadId + 1
    local sq = { id = id, goal = M.GOAL, faction = Rules.getOwner(ctx, state, campId), strength = strength,
        from = campId, to = plotId, plot = plotId, region = plot.region, citizenid = plot.owner, phase = 'warn',
        travel = intKnob(ctx, 'returnTicks', 1), etaTick = state.tick + warn }
    state.squads[id] = sq
    state.raidCooldowns = state.raidCooldowns or {}
    state.raidCooldowns[plotId] = state.tick + intKnob(ctx, 'cooldownTicks', 0)
    local e = withType('raid_warned', base(sq))
    e.camp_label, e.arrive_tick, e.warn_ticks = campLabel(ctx, campId), sq.etaTick, warn
    return sq, e
end

---Why a live raid must be cancelled now, or nil. Checked every tick for phases 'warn' and 'fight'.
local function cancelReason(ctx, state, sq, plot, online)
    if type(plot) ~= 'table' then return 'plot_gone' end
    if not M.isRaidablePlot(plot) then return 'not_raidable' end
    if plot.owner ~= sq.citizenid then return 'owner_changed' end
    if online[sq.citizenid] ~= true then return 'owner_offline' end
    if sq.phase == 'warn' and (not (ctx.camps and ctx.camps[sq.from])
        or Rules.getOwner(ctx, state, sq.from) ~= sq.faction) then return 'camp_lost' end
    return nil
end

local function toReturn(state, sq)
    sq.phase, sq.etaTick = 'return', state.tick + math.max(1, math.floor(tonumber(sq.travel) or 1))
end

---Normalise world.plots ({ [plotId] = facts }) to copies keyed by plot id, each with plotId set.
local function normPlots(plots)
    local out = {}
    if type(plots) ~= 'table' then return out end
    for k, facts in pairs(plots) do
        local id = type(k) == 'string' and k or (type(facts) == 'table' and facts.plotId) or nil
        if type(id) == 'string' and type(facts) == 'table' then
            local c = {}
            for fk, fv in pairs(facts) do c[fk] = fv end
            c.plotId = id
            out[id] = c
        end
    end
    return out
end

---One raid step at state.tick (call right after FhAlifeRules.tick(ctx, state, 1); this never advances the clock).
---Order: drop expired cooldowns; live raids by id (cancel checks, then due arrivals / withdrawals / homecomings);
---then plan new raids by plot id. Rolls per planned claim: chance, then strength on a hit.
---@param world table { plots = { [plotId] = facts }, online = { [citizenid] = true }, home = { [plotId] = true } }
---@return table effects  raid_warned | raid_fight | raid_steal | raid_withdrew | raid_cancelled | raid_returned
function M.tick(ctx, state, world, rng)
    rng = rng or math.random
    world = type(world) == 'table' and world or {}
    state.raidCooldowns = state.raidCooldowns or {}
    local plots = normPlots(world.plots)
    local online = type(world.online) == 'table' and world.online or {}
    local home = type(world.home) == 'table' and world.home or {}
    local t = state.tick
    local effects = {}

    for _, pid in ipairs(sortedKeys(state.raidCooldowns)) do
        if state.raidCooldowns[pid] <= t then state.raidCooldowns[pid] = nil end
    end

    for _, sq in ipairs(M.listRaids(state)) do
        if state.squads[sq.id] == sq then
            if sq.phase ~= 'return' then
                local why = cancelReason(ctx, state, sq, plots[sq.plot], online)
                if why then
                    local e = withType('raid_cancelled', base(sq))
                    e.reason, e.phase = why, sq.phase
                    sq.cancelled = why
                    toReturn(state, sq)
                    effects[#effects + 1] = e
                elseif sq.etaTick <= t and sq.phase == 'warn' then
                    if home[sq.plot] == true then
                        sq.mode, sq.phase = 'fight', 'fight'
                        sq.etaTick = t + intKnob(ctx, 'fightTicks', 1)
                        local e = withType('raid_fight', base(sq))
                        e.goal, e.owner_tag, e.until_tick = M.GOAL, M.OWNER_TAG, sq.etaTick
                        effects[#effects + 1] = e
                    else
                        sq.mode = 'steal'
                        toReturn(state, sq)
                        local e = withType('raid_steal', base(sq))
                        e.camp_label = campLabel(ctx, sq.from)
                        effects[#effects + 1] = e
                    end
                elseif sq.etaTick <= t and sq.phase == 'fight' then
                    toReturn(state, sq)
                    local e = withType('raid_withdrew', base(sq))
                    e.reason = 'fight_over'
                    effects[#effects + 1] = e
                end
            elseif sq.etaTick <= t then
                state.squads[sq.id] = nil
                local e = withType('raid_returned', base(sq))
                e.mode, e.cancelled = sq.mode, sq.cancelled
                effects[#effects + 1] = e
            end
        end
    end

    local cap = intKnob(ctx, 'liveCap', 0)
    local live = M.liveRaidCount(state)
    for _, pid in ipairs(sortedKeys(plots)) do
        if live >= cap then break end
        local plot = plots[pid]
        if M.eligible(plot, online) and not M.onCooldown(state, pid) and not M.raidForPlot(state, pid) then
            local chance = M.raidChance(ctx, state, plot)
            if chance > 0 and (tonumber(rng(1, ROLL)) or ROLL + 1) <= chance * ROLL then
                local _, e = startRaid(ctx, state, pid, plot, M.raidingCamp(ctx, state, plot.region), rng)
                effects[#effects + 1] = e
                live = live + 1
            end
        end
    end
    return effects
end

---Admin /alife raid <plotId>: start a raid now, skipping odds, cooldown and liveCap. Still needs an eligible claim,
---an outlaw-held camp in its region and no live raid on it. Starts the cooldown like a rolled raid.
---@return table|nil squad, table|string effects-or-err  ({ raid_warned } on success)
function M.forceRaid(ctx, state, plotId, plot, online, rng)
    rng = rng or math.random
    if type(plotId) ~= 'string' or plotId == '' then return nil, 'fh_alife_bad_plot' end
    local ok, why = M.eligible(plot, online)
    if not ok then return nil, 'fh_alife_' .. why end
    if M.raidForPlot(state, plotId) then return nil, 'fh_alife_raid_live' end
    local campId = M.raidingCamp(ctx, state, plot.region)
    if not campId then return nil, 'fh_alife_no_camp' end
    state.raidCooldowns = state.raidCooldowns or {}
    local sq, e = startRaid(ctx, state, plotId, plot, campId, rng)
    return sq, { e }
end

---Death watch entry for every squad (delegates to FhAlifeRules.onSquadKill). Wiping a raid squad also yields
---{ type = 'raid_repelled', squad_id, plot_id, citizenid, camp_id, region_id, faction }.
---@return table effects, string|nil err
function M.onSquadKill(ctx, state, squadId, n)
    local sq = state.squads[squadId]
    local effects, err = Rules.onSquadKill(ctx, state, squadId, n)
    if err or not sq or sq.goal ~= M.GOAL then return effects, err end
    for _, e in ipairs(effects) do
        if e.type == 'squad_wiped' then
            local r = withType('raid_repelled', base(sq))
            r.strength = nil
            effects[#effects + 1] = r
            break
        end
    end
    return effects, nil
end

---Steal pick from chest 1. `items` = fh_core snapshot slot map ({ [slot] = { name, amount, ... } }) or an array
---(entry.slot wins over the key). Valid stacks (non-empty name, amount >= 1) in slot order form the pool; up to
---stealStacks picks, each: stack = pool[rng(1, #pool)] (removed), take = rng(1, max(1, floor(amount x
---stealMaxFraction))). So at least 1 item per picked stack, never more than the fraction of a stack (a 1-item stack
---can be taken whole: the at-least-1 rule wins). Empty chest -> {} with no rng call.
---@return table picks  { { slot, name, amount, of } } in pick order (amount = taken, of = the stack's amount)
function M.pickSteal(ctx, items, rng)
    rng = rng or math.random
    local pool, seen = {}, {}
    if type(items) == 'table' then
        local keys = {}
        for k in pairs(items) do
            local n = tonumber(k)
            if n and n == math.floor(n) then keys[#keys + 1] = { k = k, n = n } end
        end
        table.sort(keys, function(a, b) return a.n < b.n end)
        for _, kk in ipairs(keys) do
            local it = items[kk.k]
            if type(it) ~= 'table' then it = {} end
            local slot = (type(it.slot) == 'number' and math.tointeger(it.slot)) or math.tointeger(kk.n)
            local amount = finite(it.amount) and math.floor(it.amount) or 0
            if slot and not seen[slot] and type(it.name) == 'string' and it.name ~= '' and amount >= 1 then
                seen[slot] = true
                pool[#pool + 1] = { slot = slot, name = it.name, amount = amount }
            end
        end
    end
    local picks = {}
    local k = math.min(intKnob(ctx, 'stealStacks', 0), #pool)
    local frac = clamp01(knob(ctx, 'stealMaxFraction'))
    for _ = 1, k do
        local j = math.floor(tonumber(rng(1, #pool)) or 1)
        j = math.min(#pool, math.max(1, j))
        local st = table.remove(pool, j)
        local maxTake = math.min(st.amount, math.max(1, math.floor(st.amount * frac)))
        local take = math.floor(tonumber(rng(1, maxTake)) or 1)
        take = math.min(maxTake, math.max(1, take))
        picks[#picks + 1] = { slot = st.slot, name = st.name, amount = take, of = st.amount }
    end
    return picks
end

-- ---------------------------------------------------------------- save

---Same plain table as FhAlifeRules.serialize (v3: includes raid squads and raidCooldowns).
M.serialize = Rules.serialize

local function cleanRaid(sq)
    if type(sq.plot) ~= 'string' or type(sq.from) ~= 'string' or type(sq.region) ~= 'string'
        or type(sq.citizenid) ~= 'string' or not PHASES[sq.phase]
        or (sq.mode ~= nil and not MODES[sq.mode]) or sq.to ~= sq.plot then return false end
    local s = finite(sq.strength) and math.floor(sq.strength) or 0
    sq.strength = math.max(0, s)
    sq.travel = math.max(1, finite(sq.travel) and math.floor(sq.travel) or 1)
    if sq.cancelled ~= nil and type(sq.cancelled) ~= 'string' then sq.cancelled = nil end
    return true
end

---Drop raid squads that are malformed, whose camp is gone from ctx.camps, or (when `plots` is given) whose plot is
---gone: unknown id, no longer raidable, or no owner. No error, nothing stolen, strength just returns to its camp.
---@param plots table|nil { [plotId] = facts }; nil skips the plot check (tick cancels raids on missing plots)
---@return table effects  { type = 'raid_dropped', reason = 'bad_shape'|'camp_missing'|'plot_missing', ... }
function M.pruneRaids(ctx, state, plots)
    local effects = {}
    for _, sq in ipairs(M.listRaids(state)) do
        local why
        if not cleanRaid(sq) then why = 'bad_shape'
        elseif not (ctx and ctx.camps and ctx.camps[sq.from]) then why = 'camp_missing'
        elseif type(plots) == 'table' and not M.isRaidablePlot(plots[sq.plot]) then why = 'plot_missing' end
        if why then
            state.squads[sq.id] = nil
            effects[#effects + 1] = { type = 'raid_dropped', reason = why, squad_id = sq.id,
                plot_id = type(sq.plot) == 'string' and sq.plot or nil,
                camp_id = type(sq.from) == 'string' and sq.from or nil }
        end
    end
    return effects
end

---FhAlifeRules.deserialize (v1/v2/v3) plus pruneRaids. @return table|nil state, string|nil err, table effects
function M.deserialize(t, ctx, plots)
    local s, err, effects = Rules.deserialize(t, ctx)
    if not s then return nil, err, effects or {} end
    effects = effects or {}
    for _, e in ipairs(M.pruneRaids(ctx, s, plots)) do effects[#effects + 1] = e end
    return s, nil, effects
end

if GetCurrentResourceName then
    FhAlifeRaidRules = M
else
    return M
end

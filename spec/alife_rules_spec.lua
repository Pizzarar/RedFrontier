-- Pure A-Life rules spec (plan a-life-01 A1). Run from repo root: `lua spec/alife_rules_spec.lua` (or tools/run-specs.py).
-- Loads shared/alife_rules.lua against the real FhRegions + FhZonesConfig camp list. No natives: rng is injected.
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local case, eq, same = T.it, T.eq, T.same
local R = dofile(here .. '../server/resources/[fh]/fh_alife/shared/alife_rules.lua')

-- Load FhRegions/FhPlaceResolver + vector3 stand-in (world-02 block F), then the configs (fh_zones resolves camps).
local Regions = dofile(here .. 'support/world_config.lua')
dofile(here .. '../server/resources/[fh]/fh_zones/config.lua')
dofile(here .. '../server/resources/[fh]/fh_alife/config.lua')
local cfg = FhAlifeConfig
local camps = FhZonesConfig.camps

---Real FhRegions with per-region `ambush` lists overlaid (@world H format). isEnabled/factions/territories are the
---real ones (via __index), so enabled gates match regions.lua.
local function fixtureRegions(ambush)
    local rr = {}
    for id, r in pairs(Regions.regions) do
        local copy = {}
        for k, v in pairs(r) do copy[k] = v end
        copy.ambush = ambush[id]
        rr[id] = copy
    end
    return setmetatable({ regions = rr }, { __index = Regions })
end

-- The real regions.lua carries @world H ambush nodes (world-03 H). The a-life-01 cases and the B1 "no ambush" cases
-- run on the real registry with every `ambush` list stripped, so the raid roll never fires there; the case
-- "B1 real regions.lua ambush data" checks the unstripped registry.
local NoAmbush = fixtureRegions({})
local ctx = R.context(cfg, NoAmbush, camps)
local heartlandsCamp = 'heartlands_t1_01'

---Deterministic rng: returns the next pre-set value (ignores lo/hi), like camp_rules_spec's seq.
local function seq(...)
    local vals, i = { ... }, 0
    return function() i = i + 1 return vals[i] end
end

---Park-Miller LCG: a seeded integer rng(lo, hi) for bounds checks.
local function lcg(seed)
    local s = seed
    return function(lo, hi)
        s = (s * 16807) % 2147483647
        return lo + (s % (hi - lo + 1))
    end
end

case('isLawFaction: fallback set when kind is absent', function()
    assert(R.isLawFaction(Regions.factions, 'lawmen'))
    assert(R.isLawFaction(Regions.factions, 'rhodes_law'), 'rhodes_law is a lawmen alias')
    assert(not R.isLawFaction(Regions.factions, 'outlaws'))
    assert(not R.isLawFaction(Regions.factions, 'raiders'))
    assert(not R.isLawFaction(Regions.factions, 'bogus'))
    assert(not R.isLawFaction(Regions.factions, nil))
    assert(R.isLawFaction(nil, 'lawmen'), 'no factions table -> fall back to the hardcoded set')
end)

case('isLawFaction: kind wins over the fallback set', function()
    local factions = {
        lawmen = { id = 'lawmen', kind = 'law' },
        outlaws = { id = 'outlaws', kind = 'outlaw' },
        neutral = { id = 'neutral', kind = 'neutral' },
        rhodes_law = { id = 'rhodes_law', kind = 'outlaw' }, -- kind present: overrides the fallback alias
    }
    assert(R.isLawFaction(factions, 'lawmen'))
    assert(not R.isLawFaction(factions, 'outlaws'))
    assert(not R.isLawFaction(factions, 'neutral'))
    assert(not R.isLawFaction(factions, 'rhodes_law'), 'kind=outlaw beats the rhodes_law fallback alias')
end)

case('regionLawFaction: first law faction in the region list', function()
    eq('lawmen', R.regionLawFaction(Regions, 'heartlands'))
    eq('lawmen', R.regionLawFaction(Regions, 'scarlett_meadows'))
    eq(nil, R.regionLawFaction(Regions, 'bogus'))
    local kindRegions = {
        factions = {
            a = { id = 'a', kind = 'neutral' },
            b = { id = 'b', kind = 'law' },
            c = { id = 'c', kind = 'outlaw' },
        },
        regions = { r1 = { id = 'r1', factions = { 'a', 'b', 'c' } } },
    }
    eq('b', R.regionLawFaction(kindRegions, 'r1'))
end)

case('buildGraph: one camp node per camp, one town node per region', function()
    eq('camp', ctx.graph.nodes[heartlandsCamp].type)
    eq('camp', ctx.graph.nodes['scarlett_meadows_t1_01'].type)
    eq('town', ctx.graph.nodes['heartlands'].type)
    eq('town', ctx.graph.nodes['scarlett_meadows'].type)
    eq('heartlands', ctx.graph.nodes[heartlandsCamp].region)
end)

case('getOwner: default owner is the territory faction', function()
    local st = R.newState()
    eq('outlaws', R.getOwner(ctx, st, heartlandsCamp))
    eq('raiders', R.getOwner(ctx, st, 'scarlett_meadows_t1_01'))
    eq(nil, R.getOwner(ctx, st, 'bogus'))
    eq(false, R.isLawHeld(ctx, st, heartlandsCamp))
end)

case('onCampCleared: flips to law, shortage relief, broadcast, schedules retake, no heat', function()
    local st = R.newState()
    local effects = R.onCampCleared(ctx, st, heartlandsCamp, { 'CID1', 'CID2' }, seq(5, 25))
    same({
        { type = 'flipped', camp_id = heartlandsCamp, region_id = 'heartlands', from = 'outlaws', to = 'lawmen' },
        { type = 'broadcast', message = 'New Hanover Law has taken the Heartland Bluffs Camp' },
        { type = 'shortage', region = 'heartlands', item = 'trade_salt', level = 0 },
    }, effects)
    for _, e in ipairs(effects) do
        assert(e.type ~= 'heat', 'fh_alife must not emit heat (fh_heat owns camp_clear heat)')
    end
    eq('lawmen', R.getOwner(ctx, st, heartlandsCamp))
    eq(true, R.isLawHeld(ctx, st, heartlandsCamp))
    local _, squad = next(st.squads)
    assert(squad, 'retake squad scheduled')
    eq('outlaws', squad.faction); eq('retake', squad.goal); eq(5, squad.strength)
    eq('heartlands', squad.from); eq(heartlandsCamp, squad.to); eq(25, squad.etaTick)
end)

case('onCampCleared: emits no heat effect (fh_heat owns camp_clear heat)', function()
    local st = R.newState()
    for _, e in ipairs(R.onCampCleared(ctx, st, heartlandsCamp, { 'CID1', 'CID2' }, seq(5, 25))) do
        assert(e.type ~= 'heat', 'unexpected heat effect: ' .. tostring(e.type))
    end
end)

case('onCampCleared: unknown camp produces no effects', function()
    local st = R.newState()
    eq(0, #R.onCampCleared(ctx, st, 'bogus', { 'CID1' }, seq(5, 25)))
    eq(0, #st.squads)
end)

case('onCampCleared: region with no law faction -> logs, skips the flip, no effects, no error', function()
    -- A region whose factions are all non-law (kind present, none 'law'): regionLawFaction -> nil.
    local lawless = {
        factions = {
            outlaws = { id = 'outlaws', label = 'Heartland Outlaws', kind = 'outlaw' },
            neutral = { id = 'neutral', label = 'Neutral', kind = 'neutral' },
        },
        regions = { badlands = { id = 'badlands', label = 'Badlands', factions = { 'outlaws', 'neutral' }, territories = {} } },
        territories = {
            badlands_t1_camp = { id = 'badlands_t1_camp', label = 'Badlands Outlaw Camp', region = 'badlands', faction = 'outlaws' },
        },
    }
    local lawlessCamps = { badlands_t1_01 = { id = 'badlands_t1_01', region = 'badlands', territory = 'badlands_t1_camp' } }
    local c = R.context(cfg, lawless, lawlessCamps)
    local st = R.newState()
    local logged
    local effects = R.onCampCleared(c, st, 'badlands_t1_01', { 'CID1' }, seq(5, 25), function(msg) logged = msg end)
    assert(logged and logged:find('no law faction', 1, true), 'logged a reason: ' .. tostring(logged))
    -- no flip effects (flipped / broadcast / shortage) and no heat (fh_heat owns camp_clear heat)
    same({}, effects)
    eq('outlaws', R.getOwner(c, st, 'badlands_t1_01'), 'owner unchanged')
    eq(false, R.isLawHeld(c, st, 'badlands_t1_01'))
    eq(0, (function() local n = 0 for _ in pairs(st.squads) do n = n + 1 end return n end)(), 'no retake squad')
end)

case('retake within configured ticks with seeded rng', function()
    for seed = 1, 50 do
        local st = R.newState()
        R.onCampCleared(ctx, st, heartlandsCamp, {}, lcg(seed))
        local _, squad = next(st.squads)
        assert(squad)
        local delta = squad.etaTick - 0 -- flipped at tick 0
        assert(delta >= cfg.retake.minTicks and delta <= cfg.retake.maxTicks, 'eta delta ' .. tostring(delta))
        assert(squad.strength >= cfg.retake.strengthMin and squad.strength <= cfg.retake.strengthMax,
            'strength ' .. tostring(squad.strength))
    end
end)

case('broadcast labels: Regions.factionLabel(faction, region) used when present, falls back on error/nil', function()
    local function withLabel(fn)
        local r = setmetatable({ factionLabel = fn }, { __index = NoAmbush })
        return R.context(cfg, r, camps)
    end
    local seen = {}
    local c1 = withLabel(function(f, reg) seen[#seen + 1] = { f, reg } return 'STUB ' .. f .. '@' .. reg end)
    local e = R.onCampCleared(c1, R.newState(), heartlandsCamp, {}, seq(5, 25))
    eq('STUB lawmen@heartlands has taken the Heartland Bluffs Camp', e[2].message)
    same({ 'lawmen', 'heartlands' }, seen[1])
    local st = R.newState()
    R.onCampCleared(c1, st, heartlandsCamp, {}, seq(4, 22))
    eq('STUB outlaws@heartlands have retaken the Heartland Bluffs Camp', R.tick(c1, st, 99, seq())[2].message)
    for _, bad in ipairs({ function() error('boom') end, function() return nil end }) do
        local e2 = R.onCampCleared(withLabel(bad), R.newState(), heartlandsCamp, {}, seq(5, 25))
        eq('Lawmen has taken the Heartland Bluffs Camp', e2[2].message)
    end
end)

case('tick resolves the retake: flips back, broadcasts, raises the shortage', function()
    local st = R.newState()
    R.onCampCleared(ctx, st, heartlandsCamp, {}, seq(4, 22))
    eq(0, #R.tick(ctx, st, 21, seq()), 'not due yet at etaTick 22')
    eq('lawmen', R.getOwner(ctx, st, heartlandsCamp))
    local effects = R.tick(ctx, st, 1, seq())
    same({
        { type = 'flipped', camp_id = heartlandsCamp, region_id = 'heartlands', from = 'lawmen', to = 'outlaws' },
        { type = 'broadcast', message = 'Mountain Gang have retaken the Heartland Bluffs Camp' },
        { type = 'shortage', region = 'heartlands', item = 'trade_salt', level = 0.5 },
    }, effects)
    eq('outlaws', R.getOwner(ctx, st, heartlandsCamp))
    eq(false, R.isLawHeld(ctx, st, heartlandsCamp))
    eq(0, (function() local n = 0 for _ in pairs(st.squads) do n = n + 1 end return n end)())
end)

case('outlaw-flip raises the shortage; law-flip relieves it', function()
    local st = R.newState()
    local relieved, raised
    for _, e in ipairs(R.onCampCleared(ctx, st, heartlandsCamp, {}, seq(4, 22))) do
        if e.type == 'shortage' then relieved = e end
    end
    for _, e in ipairs(R.tick(ctx, st, 22, seq())) do
        if e.type == 'shortage' then raised = e end
    end
    assert(relieved and relieved.level == 0, 'law flip must relieve')
    assert(raised and raised.level == cfg.shortages.heartlands.raised, 'outlaw flip must raise')
end)

case('serialize/deserialize roundtrip', function()
    local st = R.newState()
    R.onCampCleared(ctx, st, heartlandsCamp, { 'CID1' }, seq(4, 22))
    R.tick(ctx, st, 10, seq())
    local st2, err = R.deserialize(R.serialize(st))
    eq(nil, err)
    eq(st.tick, st2.tick); eq(st.nextSquadId, st2.nextSquadId)
    eq(st.owners[heartlandsCamp], st2.owners[heartlandsCamp])
    for id, sq in pairs(st.squads) do
        local q = st2.squads[id]
        assert(q, 'squad ' .. id .. ' survived')
        eq(sq.faction, q.faction); eq(sq.etaTick, q.etaTick); eq(sq.strength, q.strength); eq(sq.goal, q.goal)
    end
end)

case('deserialize rejects junk', function()
    local s, err = R.deserialize(nil)
    eq(nil, s); eq('fh_alife_bad_state', err)
    s, err = R.deserialize({ version = 999 })
    eq(nil, s); eq('fh_alife_version', err)
end)

case('deserialize drops malformed squads, keeps valid', function()
    local good = { id = 'sq1', faction = 'outlaws', to = 'c1', etaTick = 5 }
    local s = R.deserialize({ version = R.VERSION, tick = 0, nextSquadId = 3, owners = {}, squads = {
        sq1 = good, bad1 = 'x', bad2 = { faction = 'a', to = 'b', etaTick = 1 },
        bad3 = { id = 'sq3', faction = 'a', to = 'b' }, bad4 = { id = 'sq4', faction = 5, to = 'b', etaTick = 1 } } })
    eq(good, s.squads.sq1)
    eq(nil, s.squads.bad1); eq(nil, s.squads.bad2); eq(nil, s.squads.bad3); eq(nil, s.squads.bad4)
end)

case('deserialize rejects numeric id / NaN eta, re-keys by id', function()
    local nan = 0 / 0
    local s = R.deserialize({ version = R.VERSION, squads = {
        a = { id = 7, faction = 'x', to = 'c', etaTick = 1 },
        b = { id = 'sqN', faction = 'x', to = 'c', etaTick = nan },
        c = { id = 'sqI', faction = 'x', to = 'c', etaTick = math.huge },
        wrongkey = { id = 'sqK', faction = 'x', to = 'c', etaTick = 2 } } })
    eq(nil, s.squads.a); eq(nil, s.squads[7]); eq(nil, s.squads.sqN); eq(nil, s.squads.sqI)
    eq(nil, s.squads.wrongkey)
    eq('sqK', s.squads.sqK.id)
end)

-- ---------------------------------------------------------------- a-life-02 B1: roads and raids

local function count(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end
local function noRng() error('rng must not be called') end


local function cfgWith(over)
    local c = {}
    for k, v in pairs(cfg) do c[k] = v end
    for k, v in pairs(over or {}) do c[k] = v end
    return c
end

local HEART_AMBUSH = {
    { id = 'heartlands_amb_bend', x = 100.0, y = 500.0, z = 110.0, label = 'Dakota bend', verified = true },
    { x = 120.0, y = 520.0, z = 111.0 }, -- no id -> heartlands:ambush:2, no label
}
local heartCtx = R.context(cfg, fixtureRegions({ heartlands = HEART_AMBUSH }), camps)
local heartCamps = { 'heartlands_t1_01', 'heartlands_t1_02', 'heartlands_t1_03', 'heartlands_t2_01' }

---State with every heartlands camp owned by law except `outlawCamps`, so planRaids only sees those.
local function stateWithOutlawCamps(outlawCamps)
    local st = R.newState()
    local keep = {}
    for _, c in ipairs(outlawCamps or {}) do keep[c] = true end
    for id in pairs(camps) do if not keep[id] then st.owners[id] = 'lawmen' end end
    return st
end

case('B1 no ambush data: all 15 regions, absent or empty ambush -> no nodes, no raids, no rng, no error', function()
    local ids = {}
    for id in pairs(Regions.regions) do ids[#ids + 1] = id end
    eq(15, #ids, 'regions.lua has 15 regions')
    local emptyAll = {}
    for _, id in ipairs(ids) do emptyAll[id] = {} end
    for _, regs in ipairs({ NoAmbush, fixtureRegions(emptyAll) }) do
        local c = R.context(cfg, regs, camps)
        same({}, c.graph.ambushByRegion)
        for _, node in pairs(c.graph.nodes) do assert(node.type ~= 'ambush', 'unexpected ambush node ' .. node.id) end
        local st = R.newState() -- every camp outlaw-held by default: raids would roll if any node existed
        for _, id in ipairs(ids) do
            same({}, R.ambushNodes(c, id))
            eq(id .. ': no ambush nodes', R.describeAmbush(c, st, id))
        end
        local effects = R.tick(c, st, 200, noRng)
        eq(0, #effects)
        eq(0, count(st.squads), 'no squads at all')
        same({}, st.regionPressure)
    end
end)

case('B1 real regions.lua ambush data (@world H): enabled regions get their nodes, disabled regions are skipped', function()
    local g = R.buildGraph(cfg, Regions, camps)
    local enabled = 0
    for id, r in pairs(Regions.regions) do
        if Regions.isEnabled(id) then
            enabled = enabled + 1
            local want = {}
            for _, a in ipairs(r.ambush or {}) do want[#want + 1] = a.id end
            assert(#want >= 2, id .. ' expected >=2 ambush nodes in regions.lua')
            same(want, g.ambushByRegion[id], id .. ' ambushByRegion')
            for _, nid in ipairs(want) do eq('ambush', g.nodes[nid] and g.nodes[nid].type, nid) end
        else
            eq(nil, g.ambushByRegion[id], id .. ' is disabled: no ambush nodes')
            for _, a in ipairs(r.ambush or {}) do eq(nil, g.nodes[a.id], a.id .. ' (disabled region)') end
        end
    end
    assert(enabled >= 1 and next(g.ambushByRegion) ~= nil, 'expected a non-empty ambushByRegion')
end)

case('B1 buildGraph: ambush nodes keyed by id, else <region>:ambush:<index>; x/y/z, label, verified kept', function()
    local a = heartCtx.graph.nodes['heartlands_amb_bend']
    same({ id = 'heartlands_amb_bend', type = 'ambush', region = 'heartlands', index = 1, x = 100.0, y = 500.0,
        z = 110.0, label = 'Dakota bend', verified = true }, a)
    local b = heartCtx.graph.nodes['heartlands:ambush:2']
    eq('ambush', b.type); eq(120.0, b.x); eq(520.0, b.y); eq(111.0, b.z); eq(nil, b.label); eq(false, b.verified)
    same({ 'heartlands_amb_bend', 'heartlands:ambush:2' }, heartCtx.graph.ambushByRegion.heartlands)
    eq('Dakota bend', R.nodeLabel(heartCtx, 'heartlands_amb_bend'))
    eq('heartlands:ambush:2', R.nodeLabel(heartCtx, 'heartlands:ambush:2'))
    -- camp/town nodes unchanged
    eq('camp', heartCtx.graph.nodes[heartlandsCamp].type); eq('town', heartCtx.graph.nodes.heartlands.type)
end)

case('B1 buildGraph: skips disabled regions, malformed entries and taken ids; no isEnabled -> all regions', function()
    eq(false, Regions.isEnabled('bluewater_marsh'), 'fixture assumes bluewater_marsh is disabled')
    local regs = fixtureRegions({
        heartlands = {
            'junk', { id = 'nan', x = 0 / 0, y = 1, z = 1 }, { id = 'noz', x = 1, y = 1 },
            { id = heartlandsCamp, x = 1, y = 1, z = 1 }, -- collides with a camp node
            { id = 'dup', x = 1, y = 1, z = 1 }, { id = 'dup', x = 2, y = 2, z = 2 },
            { id = '', x = 3, y = 3, z = 3 }, -- empty id -> index key
        },
        bluewater_marsh = { { id = 'bw1', x = 1, y = 1, z = 1 } },
    })
    local g = R.buildGraph(cfg, regs, camps)
    same({ 'dup', 'heartlands:ambush:7' }, g.ambushByRegion.heartlands)
    eq(1, g.nodes.dup.x, 'first dup wins')
    eq('camp', g.nodes[heartlandsCamp].type)
    eq(nil, g.nodes.bw1); eq(nil, g.ambushByRegion.bluewater_marsh)
    -- no isEnabled function (older FhRegions): no gate
    local plain = { regions = { r1 = { id = 'r1', ambush = { { x = 1, y = 2, z = 3 } } } }, factions = {} }
    same({ 'r1:ambush:1' }, R.buildGraph(cfg, plain, {}).ambushByRegion.r1)
    -- isEnabled that errors: region treated as disabled, no error
    local boom = { regions = plain.regions, factions = {}, isEnabled = function() error('x') end }
    eq(nil, R.buildGraph(cfg, boom, {}).ambushByRegion.r1)
end)

case('B1 planRaids: chance roll hit sends a squad to the picked node; miss sends none', function()
    local st = stateWithOutlawCamps({ heartlandsCamp })
    same({}, R.planRaids(heartCtx, st, seq(cfg.raids.chancePct + 1)), 'miss')
    eq(0, count(st.squads))
    -- rolls: chance, node index (2 of 2 free), travel, strength
    local effects = R.planRaids(heartCtx, st, seq(cfg.raids.chancePct, 2, 3, 4))
    same({ { type = 'ambush_sent', squad_id = 'sq1', camp_id = heartlandsCamp, node = 'heartlands:ambush:2',
        region_id = 'heartlands', faction = 'outlaws', strength = 4, label = 'heartlands:ambush:2' } }, effects)
    same({ id = 'sq1', goal = 'ambush', faction = 'outlaws', strength = 4, from = heartlandsCamp,
        to = 'heartlands:ambush:2', node = 'heartlands:ambush:2', region = 'heartlands', phase = 'travel',
        travel = 3, etaTick = 3 }, st.squads.sq1)
end)

case('B1 caps: one live squad per node, region cap, law-held camps never raid', function()
    -- 4 outlaw camps, 2 nodes, cap 2: only 2 squads, one per node, however many ticks pass.
    local st = R.newState()
    local always = function(lo) return lo end -- chance 1 <= pct, first free node, min travel/strength
    for _ = 1, 3 do R.planRaids(heartCtx, st, always) end
    local nodes = {}
    for _, sq in pairs(st.squads) do
        assert(not nodes[sq.node], 'two squads on ' .. sq.node)
        nodes[sq.node] = true
    end
    eq(2, count(st.squads))
    -- region cap 1 with 2 free nodes -> 1 squad
    local c1 = R.context(cfgWith({ raids = setmetatable({ regionCap = 1 }, { __index = cfg.raids }) }),
        fixtureRegions({ heartlands = HEART_AMBUSH }), camps)
    local st1 = R.newState()
    for _ = 1, 3 do R.planRaids(c1, st1, always) end
    eq(1, count(st1.squads))
    -- a returning squad frees its node and its cap slot
    st1.squads.sq1.phase = 'return'
    R.planRaids(c1, st1, always)
    eq(2, count(st1.squads))
    eq('heartlands_amb_bend', st1.squads.sq2.node, 'the returning squad no longer holds node 1')
    -- every heartlands camp law-held: no raids, no rng
    local stLaw = stateWithOutlawCamps({})
    same({}, R.planRaids(heartCtx, stLaw, noRng))
end)

case('B1 ambush lifecycle: travel -> hold (ambush_holding) -> return -> back at camp (squad_returned)', function()
    local st = stateWithOutlawCamps({ heartlandsCamp })
    R.planRaids(heartCtx, st, seq(1, 1, 2, 3)) -- node 1, travel 2, strength 3
    local sq = st.squads.sq1
    eq('travel', sq.phase); eq(2, sq.etaTick)
    local no = function() return 100 end -- chance misses from here on (100 > chancePct)
    eq(0, #R.tick(heartCtx, st, 1, no))
    same({ { type = 'ambush_holding', squad_id = 'sq1', node = 'heartlands_amb_bend', region_id = 'heartlands',
        faction = 'outlaws', strength = 3, label = 'Dakota bend' } }, R.tick(heartCtx, st, 1, no))
    eq('hold', sq.phase); eq(2 + cfg.raids.holdTicks, sq.etaTick)
    eq('heartlands: 2 ambush node(s): Dakota bend=sq1 outlaws x3 hold, heartlands:ambush:2=free',
        R.describeAmbush(heartCtx, st, 'heartlands'))
    eq(0, #R.tick(heartCtx, st, cfg.raids.holdTicks, no))
    eq('return', sq.phase); eq(2 + cfg.raids.holdTicks + 2, sq.etaTick)
    eq(0, #R.tick(heartCtx, st, 1, no))
    same({ { type = 'squad_returned', reason = 'returned', squad_id = 'sq1', goal = 'ambush', faction = 'outlaws',
        camp_id = heartlandsCamp, node = 'heartlands_amb_bend', region_id = 'heartlands', strength = 3 } },
        R.tick(heartCtx, st, 1, no))
    eq(nil, st.squads.sq1)
    same({}, st.regionPressure, 'returning survivors add no pressure')
end)

case('B1 onSquadKill: -1 strength per kill, outlaw losses add regionPressure, wipe removes the squad', function()
    local st = stateWithOutlawCamps({ heartlandsCamp })
    R.planRaids(heartCtx, st, seq(1, 1, 2, 3))
    same({}, (R.onSquadKill(heartCtx, st, 'sq1')))
    eq(2, st.squads.sq1.strength); eq(1, R.getPressure(st, 'heartlands', 'outlaws'))
    same({ { type = 'squad_wiped', squad_id = 'sq1', goal = 'ambush', faction = 'outlaws', node = 'heartlands_amb_bend',
        camp_id = heartlandsCamp, region_id = 'heartlands', label = 'Dakota bend' } },
        (R.onSquadKill(heartCtx, st, 'sq1', 5)))
    eq(nil, st.squads.sq1)
    eq(3, R.getPressure(st, 'heartlands', 'outlaws'), 'only the 2 actually lost count')
    local e, err = R.onSquadKill(heartCtx, st, 'sq1')
    same({}, e); eq('fh_alife_no_squad', err)
    -- pressureMax caps it
    st.regionPressure.heartlands.outlaws = cfg.raids.pressureMax
    R.planRaids(heartCtx, st, seq(1, 1, 2, 3))
    R.onSquadKill(heartCtx, st, 'sq2')
    eq(cfg.raids.pressureMax, R.getPressure(st, 'heartlands', 'outlaws'))
    -- law squad losses add no pressure
    local stL = R.newState()
    stL.squads.sqL = { id = 'sqL', goal = 'reinforce', faction = 'lawmen', strength = 2, from = 'heartlands',
        to = heartlandsCamp, region = 'heartlands', phase = 'hold', travel = 3, etaTick = 9 }
    R.onSquadKill(ctx, stL, 'sqL')
    same({}, stL.regionPressure)
end)

case('B1 reinforce: a law-held camp gets one data-only squad (no rng), holds while law keeps the camp', function()
    local st = R.newState()
    R.onCampCleared(ctx, st, heartlandsCamp, {}, seq(4, 22))
    eq(0, #R.tick(ctx, st, 1, noRng))
    local rf = R.listSquads(st, 'reinforce')
    eq(1, #rf)
    same({ id = 'sq2', goal = 'reinforce', faction = 'lawmen', strength = cfg.reinforce.strength, from = 'heartlands',
        to = heartlandsCamp, region = 'heartlands', phase = 'travel', travel = cfg.reinforce.travelTicks,
        etaTick = 1 + cfg.reinforce.travelTicks }, rf[1])
    eq(0, R.holderStrength(st, heartlandsCamp))
    R.tick(ctx, st, cfg.reinforce.travelTicks + cfg.reinforce.holdTicks, noRng)
    eq(1, #R.listSquads(st, 'reinforce'), 'still one, renewed')
    eq('hold', rf[1].phase); eq(cfg.reinforce.strength, R.holderStrength(st, heartlandsCamp))
end)

case('B1 pressure math: retake roll = strength - pressure vs holders; fail regroups, pressure is consumed', function()
    local st = R.newState()
    R.onCampCleared(ctx, st, heartlandsCamp, {}, seq(4, 22)) -- retake strength 4 at tick 22
    R.tick(ctx, st, 21, noRng)
    eq(2, R.holderStrength(st, heartlandsCamp))
    st.regionPressure.heartlands = { outlaws = 3 } -- 3 outlaws killed on the road: effective 4 - 3 = 1 <= 2
    local effects = R.tick(ctx, st, 1, seq(5, 25)) -- the regroup squad rolls strength 5, eta +25
    same({
        { type = 'retake_failed', camp_id = heartlandsCamp, region_id = 'heartlands', faction = 'outlaws', strength = 4,
            pressure = 3, holder = 2 },
        { type = 'broadcast', message = 'Mountain Gang failed to retake the Heartland Bluffs Camp' },
    }, effects)
    eq('lawmen', R.getOwner(ctx, st, heartlandsCamp))
    eq(0, R.getPressure(st, 'heartlands', 'outlaws'), 'pressure consumed by the roll')
    eq(1, R.holderStrength(st, heartlandsCamp), 'holders took the effective 1')
    local retakes = R.listSquads(st, 'retake')
    eq(1, #retakes); eq(5, retakes[1].strength); eq(22 + 25, retakes[1].etaTick)
    -- next retake, pressure 1: effective 4 > holder 1 -> lands; reinforce squads are removed
    st.regionPressure.heartlands = { outlaws = 1 }
    local e2 = R.tick(ctx, st, 25, noRng)
    eq('flipped', e2[1].type); eq('outlaws', R.getOwner(ctx, st, heartlandsCamp))
    eq(0, count(st.squads)); eq(0, R.getPressure(st, 'heartlands', 'outlaws'))
end)

case('B1 pressure: strength - pressure 0 with no holders still fails (no flip), clamps at 0', function()
    local st = R.newState()
    R.flip(ctx, st, heartlandsCamp, 'lawmen')
    st.regionPressure.heartlands = { outlaws = 6 }
    local e = R.resolveSquad(ctx, st, { id = 'sqX', goal = 'retake', faction = 'outlaws', strength = 4,
        from = 'heartlands', to = heartlandsCamp, etaTick = 0 }, seq(3, 20))
    eq('retake_failed', e[1].type); eq(6, e[1].pressure); eq(0, e[1].holder)
    eq('lawmen', R.getOwner(ctx, st, heartlandsCamp))
end)

case('B1 save v2 roundtrip: ambush/reinforce squads and regionPressure survive', function()
    local st = stateWithOutlawCamps({ heartlandsCamp })
    R.planRaids(heartCtx, st, seq(1, 1, 2, 3))
    R.tick(heartCtx, st, 2, function() return 100 end)
    st.regionPressure.heartlands = { outlaws = 2 }
    local saved = R.serialize(st)
    eq(R.VERSION, saved.version)
    local st2, err, eff = R.deserialize(saved, heartCtx)
    eq(nil, err); same({}, eff)
    same(st.squads, st2.squads); same(st.regionPressure, st2.regionPressure); same(st.owners, st2.owners)
end)

case('B1 old save (a-life-01 v1) loads: owners and retake squads kept, regionPressure empty, saved as current', function()
    local v1 = { version = 1, tick = 7, nextSquadId = 2, owners = { [heartlandsCamp] = 'lawmen' },
        squads = { sq1 = { id = 'sq1', faction = 'outlaws', strength = 4, from = 'heartlands', to = heartlandsCamp,
            etaTick = 22, goal = 'retake' } } }
    local st, err, eff = R.deserialize(v1, ctx)
    eq(nil, err); same({}, eff)
    eq(7, st.tick); eq('lawmen', st.owners[heartlandsCamp]); eq(4, st.squads.sq1.strength)
    same({}, st.regionPressure)
    eq(R.VERSION, R.serialize(st).version)
    local effects = R.tick(ctx, st, 15, noRng) -- reinforce arrives, retake lands at 22 (4 > 2)
    eq('flipped', effects[1].type)
end)

case('B1 load with a missing node: squad dropped, strength returned to camp, never errors', function()
    local st = stateWithOutlawCamps({ heartlandsCamp })
    R.planRaids(heartCtx, st, seq(1, 2, 2, 3)) -- node heartlands:ambush:2
    local saved = R.serialize(st)
    -- @world data changed: node 2 removed
    local c = R.context(cfg, fixtureRegions({ heartlands = { HEART_AMBUSH[1] } }), camps)
    local st2, err, eff = R.deserialize(saved, c)
    eq(nil, err)
    same({ { type = 'squad_returned', reason = 'node_missing', squad_id = 'sq1', goal = 'ambush', faction = 'outlaws',
        camp_id = heartlandsCamp, node = 'heartlands:ambush:2', region_id = 'heartlands', strength = 3 } }, eff)
    eq(0, count(st2.squads)); same({}, st2.regionPressure)
    -- deserialize without ctx (a-life-01 server call): the first tick prunes it instead
    local st3 = R.deserialize(saved)
    eq(1, count(st3.squads))
    local e3 = R.tick(ctx, st3, 1, noRng) -- ctx has no ambush data at all
    eq('node_missing', e3[1].reason); eq(0, #R.listSquads(st3, 'ambush'))
end)

case('B1 deserialize: malformed v2 squads and pressure are dropped', function()
    local s = R.deserialize({ version = 2, squads = {
        a = { id = 'a', goal = 'ambush', faction = 'outlaws', to = 'n', node = 'n', from = 'c', etaTick = 1, phase = 'zzz' },
        b = { id = 'b', goal = 'ambush', faction = 'outlaws', to = 'n', from = 'c', etaTick = 1, phase = 'hold' },
        c = { id = 'c', goal = 'ambush', faction = 'outlaws', to = 'n', node = 'n', from = 'c', etaTick = 1,
            phase = 'hold', strength = 0 / 0, travel = -4 },
    }, regionPressure = { heartlands = { outlaws = 2, raiders = -1, bad = 0 / 0 }, [5] = { x = 1 }, other = 'x' } })
    eq(nil, s.squads.a); eq(nil, s.squads.b)
    eq(0, s.squads.c.strength); eq(1, s.squads.c.travel)
    same({ heartlands = { outlaws = 2 } }, s.regionPressure)
end)

T.finish()

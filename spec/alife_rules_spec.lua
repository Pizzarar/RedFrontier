-- Pure A-Life rules spec (plan a-life-01 A1). Run from repo root: `lua spec/alife_rules_spec.lua` (or tools/run-specs.py).
-- Loads shared/alife_rules.lua against the real FhRegions + FhZonesConfig camp list. No natives: rng is injected.
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local case, eq, same = T.it, T.eq, T.same
local R = dofile(here .. '../server/resources/[fh]/fh_alife/shared/alife_rules.lua')
local Regions = require('regions')

-- fh_zones / fh_alife configs use vector3 (a Cfx global): a table stand-in is enough for the pure checks.
vector3 = function(x, y, z) return { x = x, y = y, z = z } end
vector4 = function(x, y, z, w) return { x = x, y = y, z = z, w = w } end
dofile(here .. '../server/resources/[fh]/fh_zones/config.lua')
dofile(here .. '../server/resources/[fh]/fh_alife/config.lua')
local cfg = FhAlifeConfig
local camps = FhZonesConfig.camps
local ctx = R.context(cfg, Regions, camps)
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
    eq('rhodes_law', R.regionLawFaction(Regions, 'scarlett_meadows'))
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
        { type = 'broadcast', message = 'Valentine Law has taken the Heartlands Outlaw Camp' },
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
        local r = setmetatable({ factionLabel = fn }, { __index = Regions })
        return R.context(cfg, r, camps)
    end
    local seen = {}
    local c1 = withLabel(function(f, reg) seen[#seen + 1] = { f, reg } return 'STUB ' .. f .. '@' .. reg end)
    local e = R.onCampCleared(c1, R.newState(), heartlandsCamp, {}, seq(5, 25))
    eq('STUB lawmen@heartlands has taken the Heartlands Outlaw Camp', e[2].message)
    same({ 'lawmen', 'heartlands' }, seen[1])
    local st = R.newState()
    R.onCampCleared(c1, st, heartlandsCamp, {}, seq(4, 22))
    eq('STUB outlaws@heartlands have retaken the Heartlands Outlaw Camp', R.tick(c1, st, 99, seq())[2].message)
    for _, bad in ipairs({ function() error('boom') end, function() return nil end }) do
        local e2 = R.onCampCleared(withLabel(bad), R.newState(), heartlandsCamp, {}, seq(5, 25))
        eq('Valentine Law has taken the Heartlands Outlaw Camp', e2[2].message)
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
        { type = 'broadcast', message = 'Heartland Outlaws have retaken the Heartlands Outlaw Camp' },
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

T.finish()

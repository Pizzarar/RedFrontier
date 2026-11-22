-- Run from repo root: `lua spec/camp_rules_spec.lua` (or via tools/run-specs.py).
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local case, eq = T.it, T.eq
local R = dofile(here .. '../server/resources/[fh]/fh_zones/shared/camp_rules.lua')
local Containers = require('containers')
local Items = require('items')
local Regions = require('regions')

-- fh_zones config uses vector3 (a Cfx global): a table stand-in is enough for the pure checks
vector3 = function(x, y, z) return { x = x, y = y, z = z } end
vector4 = function(x, y, z, w) return { x = x, y = y, z = z, w = w } end
dofile(here .. '../server/resources/[fh]/fh_zones/config.lua')
local cfg = FhZonesConfig
local camp = cfg.camps.heartlands_t1_01

local function seq(...)
    local vals, i = { ... }, 0
    return function() i = i + 1; return vals[i] end
end

case('transition: full cycle idle -> active -> cleared -> respawn_wait -> idle', function()
    eq('active', R.transition('idle', 'activate'))
    eq('cleared', R.transition('active', 'clear'))
    eq('respawn_wait', R.transition('cleared', 'wait'))
    eq('idle', R.transition('respawn_wait', 'respawn'))
end)
case('transition: illegal moves are refused', function()
    local n, err = R.transition('idle', 'clear')
    eq(nil, n); eq('fh_camp_bad_transition', err)
    local _, e2 = R.transition('active', 'activate'); eq('fh_camp_bad_transition', e2)
    local _, e3 = R.transition('respawn_wait', 'clear'); eq('fh_camp_bad_transition', e3)
    local _, e4 = R.transition('bogus', 'activate'); eq('fh_camp_bad_state', e4)
end)
case('inRadius: inside, edge, outside, bad coords', function()
    local c = { x = 0, y = 0, z = 0 }
    assert(R.inRadius(c, 10, { x = 6, y = 8, z = 0 }))
    assert(not R.inRadius(c, 10, { x = 6, y = 8, z = 0.5 }))
    assert(not R.inRadius(c, 10, nil))
    assert(not R.inRadius(c, 10, { x = 0 / 0, y = 0, z = 0 }))
    assert(not R.inRadius(c, nil, c))
end)
case('shouldActivate: only an idle camp, only with a player inside', function()
    local near, far = { x = -145, y = 845, z = 117 }, { x = 500, y = 0, z = 0 }
    assert(R.shouldActivate('idle', camp, { far, near }))
    assert(not R.shouldActivate('idle', camp, { far }))
    assert(not R.shouldActivate('idle', camp, {}))
    for _, st in ipairs({ 'active', 'cleared', 'respawn_wait' }) do assert(not R.shouldActivate(st, camp, { near }), st) end
end)
case('allDead: needs one death, tolerates failed spawns, not alive peds', function()
    assert(R.allDead({ { dead = true }, { dead = true } }))
    assert(R.allDead({ { dead = true }, { failed = true } }))
    assert(not R.allDead({ { dead = true }, { dead = false } }))
    assert(not R.allDead({ { failed = true }, { failed = true } }))
    assert(not R.allDead({}))
    assert(not R.allDead(nil))
end)
case('re-adoption: a dead ped stays dead for the roll-up even if its record gets a new netId', function()
    -- server keeps `dead` on the ped entry; onReady swapping netId must not revive it (camp state, not entity state)
    local ped = { dead = true, netId = 11 }
    ped.netId = 12
    assert(R.allDead({ ped }))
end)
case('canReport: near the camp (activation radius + margin) only', function()
    assert(R.canReport(camp, { x = -145, y = 845, z = 117 }))
    assert(R.canReport(camp, { x = -145 + 45 + 20, y = 845, z = 117 }))
    assert(not R.canReport(camp, { x = -145 + 45 + 40, y = 845, z = 117 }))
    assert(not R.canReport(camp, nil))
end)
case('respawnDue', function()
    assert(R.respawnDue(100, 100)); assert(R.respawnDue(101, 100))
    assert(not R.respawnDue(99, 100)); assert(not R.respawnDue(99, nil))
end)
case('rollLoot: injected RNG, chance gate and condition range', function()
    local tbl = { { name = 'a', chance = 0.5 }, { name = 'b', chance = 1.0, condition = { 20, 45 } } }
    -- a: roll 499999 < 500000 passes; b: roll 0 passes, then condition roll 33
    local got = R.rollLoot(tbl, seq(499999, 0, 33))
    eq(2, #got); eq('a', got[1].name); eq(1, got[1].amount); eq('b', got[2].name); eq(33, got[2].info.condition)
    -- a: roll 500000 misses (not < 500000)
    got = R.rollLoot(tbl, seq(500000, 0, 20))
    eq(1, #got); eq('b', got[1].name); eq(20, got[1].info.condition)
    eq(0, #R.rollLoot({ { name = 'x', chance = 0 } }, seq(0)))
    eq(0, #R.rollLoot(nil))
end)
case('rollLoot: condition is clamped into 0-100', function()
    local got = R.rollLoot({ { name = 'r', chance = 1, condition = { 90, 150 } } }, seq(0, 150))
    eq(100, got[1].info.condition)
end)
case('config loot: worn rifle carries a condition in range, safe is cargo', function()
    local got = R.rollLoot(camp.loot.table, math.random)
    local rifle, safe
    for _, it in ipairs(got) do if it.name == 'worn_rifle' then rifle = it elseif it.name == 'small_safe' then safe = it end end
    assert(rifle and safe, 'both entries drop at chance 1.0')
    local c = Items.condition(rifle)
    assert(c and c >= 20 and c <= 45, 'condition ' .. tostring(c))
    eq('cargo', cfg.items.small_safe.size_class)
    assert(Items.validate(cfg.items.worn_rifle)); assert(Items.validate(cfg.items.small_safe))
end)
case('container rules: the safe fits the camp chest but never a backpack/equipped/saddlebag/drop bag', function()
    local safe = cfg.items.small_safe.size_class
    assert(Containers.accepts('chest', safe))
    for _, t in ipairs({ 'backpack', 'equipped', 'saddlebag', 'drop_bag' }) do
        local ok, why = Containers.accepts(t, safe)
        assert(not ok and why == 'fh_size_class', t)
    end
    assert(Containers.accepts('backpack', cfg.items.worn_rifle.size_class) == false, 'bulky rifle: not in a backpack either')
    assert(Containers.accepts('saddlebag', cfg.items.worn_rifle.size_class))
end)
case('tags: round trip and junk', function()
    local tag = R.tagFor('heartlands_t1_01', 3)
    local id, idx = R.parseTag(tag)
    eq('heartlands_t1_01', id); eq(3, idx)
    eq(nil, R.parseTag('nope')); eq(nil, R.parseTag(5))
    eq('fh:camp:c1', R.stashId('c1'))
end)
case('config: camp is in the M1 region, 3-5 peds, valid fields', function()
    eq('heartlands', camp.region)
    assert(Regions.getRegion(camp.region))
    local terr = Regions.getTerritory(camp.territory)
    assert(terr and terr.region == camp.region)
    assert(#camp.peds >= 3 and #camp.peds <= 5)
    for _, p in ipairs(camp.peds) do assert(p.model and p.coords and p.heading and p.weapon) end
    assert(camp.respawnMinutes > 0 and camp.activationRadius > 0)
end)

T.finish()

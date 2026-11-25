-- Run from repo root: `lua spec/camp_rules_spec.lua` (or via tools/run-specs.py).
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local case, eq, same = T.it, T.eq, T.same
local R = dofile(here .. '../server/resources/[fh]/fh_zones/shared/camp_rules.lua')
local Containers = require('containers')
local Items = require('items')
local Regions = require('regions')

-- Load FhRegions/FhPlaceResolver + vector3 stand-in (world-02 block F), then the fh_zones config (resolves camps).
dofile(here .. 'support/world_config.lua')
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
case('allFailed: only when every ped failed; abort goes active -> idle', function()
    assert(R.allFailed({ { failed = true }, { failed = true } }))
    assert(not R.allFailed({ { failed = true }, { dead = true } }))
    assert(not R.allFailed({ { failed = true }, {} }))
    assert(not R.allFailed({})); assert(not R.allFailed(nil))
    eq('idle', R.transition('active', 'abort'))
    local _, e = R.transition('idle', 'abort'); eq('fh_camp_bad_transition', e)
    local _, e2 = R.transition('respawn_wait', 'abort'); eq('fh_camp_bad_transition', e2)
end)
case('cooldownOver: nil = no cooldown, else now >= retryAt', function()
    assert(R.cooldownOver(5, nil)); assert(R.cooldownOver(100, 100)); assert(not R.cooldownOver(99, 100))
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
case('rollLoot: injected RNG, chance gate and quality range', function()
    local tbl = { { name = 'a', chance = 0.5 }, { name = 'b', chance = 1.0, quality = { 20, 45 } } }
    -- a: roll 499999 < 500000 passes; b: roll 0 passes, then condition roll 33
    local got = R.rollLoot(tbl, seq(499999, 0, 33))
    eq(2, #got); eq('a', got[1].name); eq(1, got[1].amount); eq('b', got[2].name); eq(33, got[2].info.quality)
    -- a: roll 500000 misses (not < 500000)
    got = R.rollLoot(tbl, seq(500000, 0, 20))
    eq(1, #got); eq('b', got[1].name); eq(20, got[1].info.quality); eq(nil, got[1].info.condition)
    eq(0, #R.rollLoot({ { name = 'x', chance = 0 } }, seq(0)))
    eq(0, #R.rollLoot(nil))
end)
case('rollLoot: quality is clamped into 0-100', function()
    local got = R.rollLoot({ { name = 'r', chance = 1, quality = { 90, 150 } } }, seq(0, 150))
    eq(100, got[1].info.quality)
end)
case('rollLoot: amount range hits both bounds, never outside; fixed amount unchanged', function()
    local tbl = { { name = 'g', chance = 1, amount = { 2, 3 } }, { name = 'f', chance = 1, amount = 4 } }
    eq(2, R.rollLoot(tbl, seq(0, 2, 0))[1].amount)
    local got = R.rollLoot(tbl, seq(0, 3, 0))
    eq(3, got[1].amount); eq(4, got[2].amount)
    for _ = 1, 200 do
        local a = R.rollLoot(tbl)[1].amount
        assert(a == 2 or a == 3, 'amount ' .. tostring(a))
    end
end)
case('rollLoot: malformed amount ranges fall back to 1', function()
    for _, a in ipairs({ { 3, 2 }, { 0, 2 }, {} }) do
        eq(1, R.rollLoot({ { name = 'g', chance = 1, amount = a } }, seq(0, 2))[1].amount)
    end
end)
case('config loot: gun_parts entry 0.8 chance, amount 2-3, not registered by fh_zones', function()
    local e
    for _, x in ipairs(camp.loot.table) do if x.name == 'gun_parts' then e = x end end
    assert(e, 'gun_parts entry'); eq(0.8, e.chance); eq(2, e.amount[1]); eq(3, e.amount[2])
    eq(nil, cfg.items.gun_parts)
    eq('gun_parts', R.rollLoot({ e }, seq(799999, 0))[1].name)
    eq(0, #R.rollLoot({ e }, seq(800000, 0)))
end)
case('config loot: worn rifle carries info.quality in the worn range 20-45 (not the 100 default), safe is bulky', function()
    local got = R.rollLoot(camp.loot.table, math.random)
    local rifle, safe
    for _, it in ipairs(got) do if it.name == 'worn_rifle' then rifle = it elseif it.name == 'small_safe' then safe = it end end
    assert(rifle and safe, 'both entries drop at chance 1.0')
    local c = rifle.info and rifle.info.quality
    assert(c and c >= 20 and c <= 45, 'quality ' .. tostring(c))
    eq(nil, rifle.info.condition)
    eq('bulky', cfg.items.small_safe.size_class)
    assert(Items.validate(cfg.items.worn_rifle)); assert(Items.validate(cfg.items.small_safe))
end)
case('container rules: the bulky safe fits chest/saddlebag/drop bag, not backpack/equipped; cargo only wagon/chest', function()
    local safe = cfg.items.small_safe.size_class
    for _, t in ipairs({ 'chest', 'saddlebag', 'wagon', 'drop_bag' }) do assert(Containers.accepts(t, safe), t) end
    for _, t in ipairs({ 'backpack', 'equipped' }) do
        local ok, why = Containers.accepts(t, safe)
        assert(not ok and why == 'fh_size_class', t)
    end
    assert(Containers.accepts('backpack', cfg.items.worn_rifle.size_class) == false, 'bulky rifle: not in a backpack either')
    assert(Containers.accepts('saddlebag', cfg.items.worn_rifle.size_class))
    assert(Items.FAST_TRAVEL.bulky == true and Items.FAST_TRAVEL.cargo == false)
end)
case('cargo test item: refused by backpack and saddlebag, accepted by chest', function()
    local fc = require('config')
    local def = fc.Items.test_cargo_crate
    assert(def and Items.validate(def)); eq('cargo', def.size_class)
    for _, t in ipairs({ 'backpack', 'saddlebag', 'equipped', 'drop_bag' }) do
        local ok, why = Containers.accepts(t, 'cargo'); assert(not ok and why == 'fh_size_class', t)
    end
    assert(Containers.accepts('chest', 'cargo'))
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

case('participants: in range, out of range, nobody in range', function()
    local c, r = { x = 0, y = 0, z = 0 }, 45.0
    local near, edge, far = { x = 10, y = 0, z = 0 }, { x = 45, y = 0, z = 0 }, { x = 100, y = 0, z = 0 }
    local got = R.participants(c, r, { { citizenid = 'A1', pos = near }, { citizenid = 'B2', pos = far }, { citizenid = 'C3', pos = edge }, { pos = near } })
    eq(2, #got); eq('A1', got[1]); eq('C3', got[2])
    local none = R.participants(c, r, { { citizenid = 'B2', pos = far } })
    eq('table', type(none)); eq(0, #none)
    eq(0, #R.participants(c, r, {})); eq(0, #R.participants(c, r, nil))
end)

case('participants: entries with missing or invalid pos are skipped', function()
    local c = { x = 0, y = 0, z = 0 }
    local got = R.participants(c, 45.0, {
        { citizenid = 'A1' }, { citizenid = 'B2', pos = 'nope' }, { citizenid = 'C3', pos = { x = 1, y = 0 } },
        { citizenid = 'D4', pos = { x = 0 / 0, y = 0, z = 0 } }, { citizenid = 'E5', pos = { x = 1, y = 1, z = 1 } },
    })
    eq(1, #got); eq('E5', got[1])
end)
case('safeParticipants: throwing lookup falls back to {} with the error', function()
    local c = { x = 0, y = 0, z = 0 }
    local got, err = R.safeParticipants(c, 45.0, function() error('rsg-core down') end)
    eq('table', type(got)); eq(0, #got); assert(err and err:find('rsg-core down', 1, true))
    local ok, e2 = R.safeParticipants(c, 45.0, function() return { { citizenid = 'A1', pos = { x = 1, y = 0, z = 0 } } } end)
    eq(1, #ok); eq('A1', ok[1]); eq(nil, e2)
end)

case('shouldWake: law-held camp never wakes; unknown (nil) behaves as today', function()
    local near, far = { x = -145, y = 845, z = 117 }, { x = 500, y = 0, z = 0 }
    -- lawHeld = true skips activation even with a player inside the radius
    assert(not R.shouldWake('idle', camp, { near }, true))
    assert(not R.shouldWake('idle', camp, { far, near }, true))
    -- lawHeld = false / nil = today's behaviour (cooldown is the caller's concern)
    assert(R.shouldWake('idle', camp, { far, near }, false))
    assert(R.shouldWake('idle', camp, { far, near }, nil))
    assert(not R.shouldWake('idle', camp, { far }, false))
    -- non-idle never wakes regardless of lawHeld
    for _, st in ipairs({ 'active', 'cleared', 'respawn_wait' }) do assert(not R.shouldWake(st, camp, { near }, nil), st) end
end)

case('shouldWake: a camp in a disabled region (enabled=false) never wakes', function()
    local near = { x = -145, y = 845, z = 117 }
    local function mk(enabled)
        return { enabled = enabled, center = camp.center, activationRadius = camp.activationRadius }
    end
    assert(not R.shouldWake('idle', mk(false), { near }, nil))
    assert(R.shouldWake('idle', mk(true), { near }, nil))
    assert(R.shouldWake('idle', mk(nil), { near }, nil)) -- nil enabled = today's behaviour
end)

case('pickLootTable: tiered owner map entry, flat (v1) map entry, else fall back to the camp table', function()
    local outlawT1 = cfg.lootByFaction.outlaws.T1
    local raiderT2 = cfg.lootByFaction.raiders.T2
    eq(outlawT1, R.pickLootTable(cfg.lootByFaction, 'outlaws', camp.loot.table, 'T1'))
    eq(raiderT2, R.pickLootTable(cfg.lootByFaction, 'raiders', camp.loot.table, 'T2'))
    -- a tier with no entry on a tiered map -> the camp's own table
    eq(camp.loot.table, R.pickLootTable(cfg.lootByFaction, 'outlaws', camp.loot.table, 'T9'))
    -- backward compat: a flat [faction] -> entries array (v1 shape) still resolves, with or without a tier
    local flat = { { name = 'worn_rifle', chance = 1.0, amount = 1, condition = { 20, 45 } } }
    eq(flat, R.pickLootTable({ outlaws = flat }, 'outlaws', camp.loot.table))
    eq(flat, R.pickLootTable({ outlaws = flat }, 'outlaws', camp.loot.table, 'T1'))
    -- unknown owner / nil owner / nil map -> the camp's own table
    eq(camp.loot.table, R.pickLootTable(cfg.lootByFaction, 'bogus_faction', camp.loot.table, 'T1'))
    eq(camp.loot.table, R.pickLootTable(cfg.lootByFaction, nil, camp.loot.table))
    eq(camp.loot.table, R.pickLootTable(nil, 'outlaws', camp.loot.table))
end)

case('config: lootByFaction is keyed faction -> tier; camps keep only their own loot table', function()
    eq('table', type(cfg.lootByFaction.outlaws.T1))
    eq('table', type(cfg.lootByFaction.lawmen.T3))
    eq(nil, cfg.lootByFaction.rhodes_law) -- alias excluded: rhodes_law resolves to lawmen via getFaction
    eq(nil, cfg.camps.heartlands_t1_01.lootByFaction) -- top-level only; @world's per-camp tables untouched
    eq(nil, cfg.camps.scarlett_meadows_t1_01.lootByFaction)
end)

T.finish()

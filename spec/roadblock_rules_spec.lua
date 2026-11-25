-- Run from repo root: `lua spec/roadblock_rules_spec.lua` (or via tools/run-specs.py).
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local case = T.it
local R = dofile(here .. '../server/resources/[fh]/fh_heat/shared/roadblock_rules.lua')

local th = { { name = 'watched', min = 25 }, { name = 'wanted', min = 50 }, { name = 'hunted', min = 75 } }

case('parseFlag: convar text, junk gives the default', function()
    T.eq(true, R.parseFlag('true', false)); T.eq(false, R.parseFlag('false', true)); T.eq(false, R.parseFlag('0', true))
    T.eq(true, R.parseFlag('', true)); T.eq(true, R.parseFlag(nil, true)); T.eq(true, R.parseFlag('maybe', true))
end)
case('rank / atLeast', function()
    T.eq(0, R.rank(th, nil)); T.eq(0, R.rank(th, 'nope')); T.eq(2, R.rank(th, 'wanted'))
    assert(R.atLeast(th, 'hunted', 'wanted')); assert(R.atLeast(th, 'wanted', 'wanted'))
    assert(not R.atLeast(th, 'watched', 'wanted')); assert(not R.atLeast(th, nil, 'wanted'))
    assert(not R.atLeast(th, 'hunted', 'bogus'))
end)
case('crossedUp: only a rise onto/past minLevel', function()
    assert(R.crossedUp(th, 'watched', 'wanted', 'wanted'))
    assert(R.crossedUp(th, nil, 'hunted', 'wanted'))        -- jumped over it
    assert(not R.crossedUp(th, 'wanted', 'hunted', 'wanted')) -- already past it
    assert(not R.crossedUp(th, 'wanted', 'watched', 'wanted')) -- falling
    assert(not R.crossedUp(th, nil, 'watched', 'wanted'))
    assert(not R.crossedUp(th, 'watched', 'wanted', 'bogus'))
end)

local chokes = {
    { id = 'a', region = 'heartlands', coords = { x = 0, y = 0, z = 1 } },
    { id = 'b', region = 'heartlands', coords = { x = 100, y = 0, z = 1 } },
    { id = 'c', region = 'other',     coords = { x = 1000, y = 0, z = 1 } },
}
case('pickChokepoint: nearest, prefers the player region, distance cap, errors', function()
    T.eq('b', R.pickChokepoint(chokes, 'heartlands', 90, 0).id)
    T.eq('c', R.pickChokepoint(chokes, nil, 990, 0).id)            -- no region: nearest overall
    T.eq('b', R.pickChokepoint(chokes, 'heartlands', 990, 0).id)   -- region wins over a nearer foreign one
    T.eq('a', R.pickChokepoint(chokes, 'unknown_region', 1, 0).id) -- region has none: fall back to all
    local c, err = R.pickChokepoint(chokes, 'heartlands', 5000, 0, 1000); assert(c == nil and err == 'fh_chokepoint_too_far')
    c, err = R.pickChokepoint({}, nil, 0, 0); assert(c == nil and err == 'fh_no_chokepoint')
    c, err = R.pickChokepoint(chokes, nil, 'x', 0); assert(c == nil and err == 'fh_bad_coords')
    T.eq('a', R.pickChokepoint({ chokes[2], chokes[1] }, nil, 50, 0).id) -- tie: lowest id, order independent
end)
case('canSpawn: duplicate, cooldown, max concurrent, ok', function()
    local base = { liveCount = 0, now = 1000, cooldown = 600, maxConcurrent = 2 }
    local function with(o) local t = {} for k, v in pairs(base) do t[k] = v end for k, v in pairs(o) do t[k] = v end return t end
    local ok, why = R.canSpawn(with({ liveKey = true })); assert(not ok and why == 'already_live')
    ok, why = R.canSpawn(with({ lastAt = 700 })); assert(not ok and why == 'cooldown')
    ok = R.canSpawn(with({ lastAt = 400 })); assert(ok)
    ok, why = R.canSpawn(with({ liveCount = 2 })); assert(not ok and why == 'max_concurrent')
    ok = R.canSpawn(with({ liveCount = 1 })); assert(ok)
    T.eq(R.key('c1', 'outlaws'), R.key('c1', 'outlaws')); assert(R.key('c1', 'outlaws') ~= R.key('c1', 'lawmen'))
end)
case('clearReason: dropped, expired, heat dropped, keep', function()
    local rb = { expiresAt = 100 }
    T.eq('player_dropped', R.clearReason(rb, 10, th, 'wanted', 'wanted', false))
    T.eq('expired', R.clearReason(rb, 100, th, 'wanted', 'wanted', true))
    T.eq('heat_dropped', R.clearReason(rb, 10, th, 'watched', 'wanted', true))
    T.eq('heat_dropped', R.clearReason(rb, 10, th, nil, 'wanted', true))
    assert(R.clearReason(rb, 10, th, 'hunted', 'wanted', true) == nil)
end)
case('pedPlan: count, centred line across the road, faces traffic', function()
    local f = { model = 'm', count = 3, weapon = 'w' }
    local p = R.pedPlan(f, { coords = { x = 10, y = 20, z = 5 }, heading = 0.0 }, 2.0)
    T.eq(3, #p)
    -- heading 0: road runs along +y, line runs along x
    assert(math.abs(p[2].x - 10) < 1e-9 and math.abs(p[2].y - 20) < 1e-9)
    assert(math.abs(math.abs(p[1].x - p[3].x) - 4.0) < 1e-9 and math.abs(p[1].y - 20) < 1e-9)
    T.eq(180.0, p[1].heading); T.eq('w', p[1].weapon); T.eq(5, p[1].z)
    T.eq(0, #R.pedPlan({ model = 'm', count = 0 }, { coords = { x = 0, y = 0, z = 0 } }))
    T.eq(0, #R.pedPlan(nil, { coords = { x = 0, y = 0, z = 0 } }))
    T.eq(0, #R.pedPlan(f, nil))
end)
case('isNight: wraps midnight, empty window is never night', function()
    assert(R.isNight(23, 21, 5)); assert(R.isNight(2, 21, 5)); assert(not R.isNight(5, 21, 5)); assert(not R.isNight(12, 21, 5))
    assert(R.isNight(3, 1, 4)); assert(not R.isNight(4, 1, 4)); assert(not R.isNight(3, 3, 3)); assert(not R.isNight(nil, 21, 5))
end)
case('ringPlan: n points on the radius, facing the centre', function()
    local r = R.ringPlan({ model = 'm', count = 4 }, 0, 0, 3, 50, 0)
    T.eq(4, #r)
    for _, q in ipairs(r) do assert(math.abs(math.sqrt(q.x * q.x + q.y * q.y) - 50) < 1e-6) end
    -- point at +x (angle 0) must face -x: heading 90 (0 = +y, counter-clockwise)
    assert(math.abs(r[1].heading - 90) < 1e-6)
    T.eq(0, #R.ringPlan({ model = 'm', count = 0 }, 0, 0, 0, 5))
end)
case('gatedPlan: gated is a no-op with a log line naming S2', function()
    local g = R.gatedPlan(true, 'mounted chase'); assert(g.run == false and g.log:find('spk_chase') and g.log:find('mounted chase'))
    assert(R.gatedPlan(false, 'x').run == true)
end)
local amb = { enabled = true, minLevel = 'hunted', nightFrom = 21, nightTo = 5, cooldownSeconds = 900 }
local chase = { enabled = true, minLevel = 'hunted', cooldownSeconds = 900 }
case('ambushDecision: gated first, then level, night, live, cooldown', function()
    local s = { gated = true, level = 'hunted', thresholds = th, hour = 23, now = 5000 }
    local ok, why, log = R.ambushDecision(amb, s); assert(not ok and why == 'gated' and log)
    s.gated = false; assert(R.ambushDecision(amb, s))
    s.hour = 12; ok, why = R.ambushDecision(amb, s); assert(not ok and why == 'not_night'); s.hour = 23
    s.level = 'wanted'; ok, why = R.ambushDecision(amb, s); assert(not ok and why == 'below_threshold'); s.level = 'hunted'
    s.liveKey = true; ok, why = R.ambushDecision(amb, s); assert(not ok and why == 'already_live'); s.liveKey = nil
    s.lastAt = 4500; ok, why = R.ambushDecision(amb, s); assert(not ok and why == 'cooldown')
    ok, why = R.ambushDecision({ enabled = false }, { gated = false }); assert(not ok and why == 'disabled')
end)
case('chaseDecision: gated first, needs a mounted player', function()
    local s = { gated = true, level = 'hunted', thresholds = th, mounted = true, now = 5000 }
    local ok, why = R.chaseDecision(chase, s); assert(not ok and why == 'gated')
    s.gated = false; assert(R.chaseDecision(chase, s))
    s.mounted = false; ok, why = R.chaseDecision(chase, s); assert(not ok and why == 'not_mounted'); s.mounted = true
    s.level = 'wanted'; ok, why = R.chaseDecision(chase, s); assert(not ok and why == 'below_threshold')
    s.level = 'hunted'; s.lastAt = 4999; ok, why = R.chaseDecision(chase, s); assert(not ok and why == 'cooldown')
end)

case('claimMount: rider-first and horse-first each mount exactly once; dead group never', function()
    local function run(order, live)
        local pair, fired = {}, 0
        for _, who in ipairs(order) do
            pair[who] = 1
            if R.claimMount(pair, live) then fired = fired + 1 end
        end
        pair.rider = 2 -- a re-adopt with a new netId must not mount again
        if R.claimMount(pair, live) then fired = fired + 1 end
        return fired
    end
    T.eq(1, run({ 'rider', 'horse' }, true)); T.eq(1, run({ 'horse', 'rider' }, true))
    T.eq(0, run({ 'rider', 'horse' }, false)); T.eq(0, run({ 'rider' }, true))
end)

case('lawSafeBlocks: own lot blocks; nil lookup / throw / nil result / stranger lot = not blocked', function()
    local coords = { x = 1, y = 2, z = 3 }
    local own = function(c, cid) if cid == 'CID1' then return 'town_lot_01' end end
    -- owner in their own law-safe lot: the lookup returns the plot id -> blocked (returns that id)
    T.eq('town_lot_01', R.lawSafeBlocks(own, coords, 'CID1'))
    -- a stranger's lot returns nil (non-owner) -> not blocked
    assert(R.lawSafeBlocks(own, coords, 'CID2') == nil)
    -- nil citizenid -> not blocked (lawSafeAt returns nil for a non-owner / nil citizenid)
    assert(R.lawSafeBlocks(own, coords, nil) == nil)
    -- missing lookup -> not blocked
    assert(R.lawSafeBlocks(nil, coords, 'CID1') == nil)
    -- a throwing lookup -> not blocked
    assert(R.lawSafeBlocks(function() error('boom') end, coords, 'CID1') == nil)
    -- a nil result -> not blocked
    assert(R.lawSafeBlocks(function() return nil end, coords, 'CID1') == nil)
end)

case('factionConfig: id hit, alias_of hit, kind fallback, neutral -> nil, unknown -> nil', function()
    local regions = require('regions')
    local cfgEnv = setmetatable({}, { __index = _G })
    local cfgPath = here .. '../server/resources/[fh]/fh_heat/config.lua'
    local fh = assert(io.open(cfgPath, 'rb')); local src = fh:read('a'); fh:close()
    assert(load(src, '@' .. cfgPath, 't', cfgEnv))()
    local heatCfg = cfgEnv.FhHeatConfig

    for _, tableName in ipairs({ 'roadblock', 'ambush', 'chase' }) do
        local tbl = heatCfg[tableName]
        -- 1. id hit
        local row, how = R.factionConfig(tbl, 'outlaws', regions)
        T.eq('id', how, tableName .. ' outlaws matched by id')
        T.eq('g_m_m_unibanditos_01', row.model)
        row, how = R.factionConfig(tbl, 'lawmen', regions)
        T.eq('id', how, tableName .. ' lawmen matched by id')
        T.eq('s_m_m_valdeputy_01', row.model)
        -- 2. alias_of hit (rhodes_law -> lawmen via regions.getFaction)
        row, how = R.factionConfig(tbl, 'rhodes_law', regions)
        T.eq('alias', how, tableName .. ' rhodes_law matched by alias')
        T.eq(tbl.factions.lawmen, row)
        -- 3. kind fallback (desert_gang has kind='outlaw', not hardcoded in factions)
        row, how = R.factionConfig(tbl, 'desert_gang', regions)
        T.eq('kind', how, tableName .. ' desert_gang matched by kind')
        T.eq(tbl.byKind.outlaw, row)
        -- 4. neutral factions -> nil (no spawn)
        for _, nf in ipairs({ 'rail_mining', 'settlers', 'traders', 'bounty_hunters' }) do
            row, how = R.factionConfig(tbl, nf, regions)
            assert(row == nil and how == nil, tableName .. ' neutral ' .. nf .. ' -> nil')
        end
        -- 5. unknown faction id -> nil (no throw)
        row, how = R.factionConfig(tbl, 'no_such_faction', regions)
        assert(row == nil and how == nil, tableName .. ' unknown -> nil')
    end

    -- Explicit id row wins over alias_of and byKind; law kind fallback works when no id row exists
    local custom = {
        factions = { rhodes_law = { model = 'custom_rhodes', count = 2 } },
        byKind = { law = { model = 'generic_law', count = 3 }, outlaw = { model = 'generic_outlaw', count = 3 } },
    }
    local r1, h1 = R.factionConfig(custom, 'rhodes_law', regions)
    T.eq('id', h1); T.eq('custom_rhodes', r1.model)
    local r2, h2 = R.factionConfig(custom, 'lawmen', regions)
    T.eq('kind', h2); T.eq('generic_law', r2.model)

    -- Bad / missing args -> nil, never throw
    assert(R.factionConfig(nil, 'outlaws', regions) == nil)
    assert(R.factionConfig(custom, nil, regions) == nil)
    assert(R.factionConfig(custom, '', regions) == nil)
    assert(R.factionConfig(custom, 'desert_gang', nil) == nil)
end)

T.finish()

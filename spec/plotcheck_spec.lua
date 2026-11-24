-- Run from repo root: `~/.venvs/rf/bin/python tools/run-specs.py spec/plotcheck_spec.lua`.
-- homestead-03 H16: pure math of /fh_plotcheck (shared/plotcheck.lua). No natives.
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local case = T.it
local C = dofile(here .. '../server/resources/[fh]/fh_homestead/shared/plotcheck.lua')

local function V(x, y, z) return { x = x, y = y, z = z } end
local fence = { fence = { tiers = { [1] = { unlocks = { safeRadiusBonus = 10.0 } } } }, chest_2 = { tiers = { [1] = { unlocks = {} } } } }
local function plot(id, x, y, class, extra)
    local p = { id = id, class = class, center = V(x, y, 100), radius = 25.0, slots = class == 'claim' and fence or {} }
    for k, v in pairs(extra or {}) do p[k] = v end
    return p
end

case('maxRadius: claim = max(radius, base) + fence bonus; lot = its radius', function()
    T.eq(35.0, C.maxRadius(plot('a', 0, 0, 'claim'), 25.0))
    T.eq(40.0, C.maxRadius(plot('a', 0, 0, 'claim', { radius = 30.0 }), 20.0)) -- radius wins over a smaller base
    T.eq(14.0, C.maxRadius(plot('l', 0, 0, 'town_lot', { radius = 14.0 }), 25.0))
    T.eq(0, C.maxRadius(nil, 25.0))
end)

case('dist2d ignores z and rejects garbage', function()
    T.eq(5.0, C.dist2d(V(0, 0, 0), V(3, 4, 999)))
    T.eq(nil, C.dist2d(V(0, 0, 0), nil))
    T.eq(nil, C.dist2d({ x = 0 / 0, y = 0 }, V(1, 1, 1)))
end)

case('overlaps: claim fence reach vs neighbour, touching is not overlap, lots count', function()
    local plots = {
        a = plot('a', 0, 0, 'claim'),                                 -- max 35
        b = plot('b', 60, 0, 'claim'),                                -- 60 < 70 -> overlap
        c = plot('c', 300, 0, 'claim'),
        lot = plot('lot', 0, 45, 'town_lot', { radius = 14.0 }),      -- 45 < 49 -> overlap with a
        edge = plot('edge', 0, -49, 'town_lot', { radius = 14.0 }),   -- exactly 49 -> touching
    }
    local ov = C.overlaps(plots, 'a', 25.0)
    T.eq(2, #ov)
    T.eq('b', ov[1].id); T.eq(60.0, ov[1].dist); T.eq(70.0, ov[1].limit)
    T.eq('lot', ov[2].id)
    T.eq(0, #C.overlaps(plots, 'c', 25.0))
    T.eq(0, #C.overlaps(plots, 'nope', 25.0))
end)

case('nearestTown: closest by 2D distance over all regions, nil without towns', function()
    local regions = { r1 = { towns = { { id = 'v', label = 'Valentine', x = 100, y = 0 } } },
        r2 = { towns = {} }, r3 = { towns = { { id = 'r', x = 30, y = 40 } } } }
    local t = C.nearestTown(V(0, 0, 50), regions)
    T.eq('r', t.id); T.eq(50.0, t.dist); T.eq('r', t.label)
    T.eq(nil, C.nearestTown(V(0, 0, 0), { r2 = { towns = {} } }))
    T.eq(nil, C.nearestTown(V(0, 0, 0), nil))
end)

case('classifyZ thresholds and not-found', function()
    T.eq('ok', (C.classifyZ(100.0, 101.9, true)))
    T.eq('ok', (C.classifyZ(100.0, 98.0, true)))
    T.eq('warn', (C.classifyZ(100.0, 105.0, true)))
    T.eq('warn', (C.classifyZ(100.0, 90.0, true)))
    T.eq('bad', (C.classifyZ(100.0, 111.0, true)))
    T.eq('no_ground', (C.classifyZ(100.0, 100.0, false))) -- hint fallback is never "ok"
    T.eq('no_ground', (C.classifyZ(100.0, nil, true)))
    local _, d = C.classifyZ(100.0, 95.0, true)
    T.eq(-5.0, d)
end)

case('isWater: surface above ground by more than the margin', function()
    T.eq(true, C.isWater(101.0, 100.0, 100.0))
    T.eq(false, C.isWater(100.1, 100.0, 100.0))
    T.eq(false, C.isWater(nil, 100.0, 100.0))
    T.eq(true, C.isWater(105.0, nil, 100.0)) -- no ground: compare with the config z
    T.eq(false, C.isWater(105.0, nil, nil))
end)

case('targets: all / one / unknown', function()
    local plots = { b = {}, a = {} }
    T.same({ 'a', 'b' }, C.targets(plots, nil))
    T.same({ 'a', 'b' }, C.targets(plots, 'all'))
    T.same({ 'b' }, C.targets(plots, 'b'))
    local t, err = C.targets(plots, 'zzz')
    T.eq(nil, t); T.eq('unknown_plot', err)
end)

case('cleanResults drops unknown ids, garbage numbers and duplicates', function()
    local plots = { a = {} }
    local out = C.cleanResults(plots, { { id = 'a', found = true, groundZ = 101.5, waterKnown = true, waterZ = 0 / 0 },
        { id = 'a', found = true, groundZ = 1 }, { id = 'ghost', found = true }, 'junk', { id = 5 } })
    T.eq(101.5, out.a.groundZ); T.eq(true, out.a.found); T.eq(nil, out.a.waterZ); T.eq(true, out.a.waterKnown)
    T.eq(nil, out.ghost)
    T.same({}, C.cleanResults(plots, 'nope'))
end)

case('report: flags ground/water/overlap, omits town line without regions, no report = flagged', function()
    local plots = { a = plot('a', 0, 0, 'claim', { verified = false }), b = plot('b', 60, 0, 'claim') }
    local r = C.report(plots, 'a', { found = true, groundZ = 112.0, waterKnown = true, waterZ = 113.0 }, { baseSafeRadius = 25.0 })
    T.eq(3, r.flags) -- bad z, water, overlap
    T.eq(3, #r.lines) -- no nearest-town line
    assert(r.head:find('unverified', 1, true))
    assert(r.lines[1]:find('BAD', 1, true))
    local ok = C.report({ c = plot('c', 0, 0, 'claim') }, 'c', { found = true, groundZ = 100.5, waterKnown = true },
        { baseSafeRadius = 25.0, regions = { r = { towns = { { id = 't', label = 'Town', x = 300, y = 400 } } } } })
    T.eq(0, ok.flags); T.eq(4, #ok.lines)
    assert(ok.lines[4]:find('Town 500 m', 1, true))
    local none = C.report({ c = plot('c', 0, 0, 'claim') }, 'c', nil, {})
    T.eq(2, #none.lines) -- no-report line + overlap line
    T.eq(1, none.flags)
    local ng = C.report({ c = plot('c', 0, 0, 'claim') }, 'c', { found = false, waterKnown = false }, {})
    assert(ng.lines[1]:find('NOT FOUND', 1, true)); assert(ng.lines[2]:find('unknown', 1, true))
end)
T.finish()

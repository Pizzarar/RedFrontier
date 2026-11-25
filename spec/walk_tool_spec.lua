-- world-03 J walk tooling: FhPlaceResolver place index, nearest-within-30 m, tour ordering and the mark append
-- (with LoadResourceFile/SaveResourceFile injected). Run:
--   ~/.venvs/rf/bin/python tools/run-specs.py spec/walk_tool_spec.lua
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local it, eq = T.it, T.eq
local fh = here .. '../server/resources/[fh]/'

dofile(here .. 'support/world_config.lua') -- _G.FhRegions + _G.FhPlaceResolver + vector3/4 stand-ins
dofile(fh .. 'fh_homestead/config.lua')    -- _G.FhHomesteadConfig
dofile(fh .. 'fh_zones/config.lua')        -- _G.FhZonesConfig (camps resolve against FhRegions at load)

local P = require('place_resolver')
local regions = require('regions')

local places, byId = P.index(regions, { homestead = _G.FhHomesteadConfig, zones = _G.FhZonesConfig })

-- ---------------------------------------------------------------- index

it('index covers towns, territories, posts, claims, lots and camps', function()
    eq('town', byId.valentine.kind)
    eq('heartlands', byId.valentine.region)
    eq('camp', byId.heartlands_t1_camp.kind) -- territory
    eq('post', byId.valentine_post.kind)
    eq('claim', byId.heartlands_01.kind)
    eq('lot', byId.heartlands_lot_01.kind)
    eq('camp', byId.heartlands_t1_01.kind) -- resolved fh_zones camp
end)

it('a camp aliases its territory: one entry per camp, both ids resolve', function()
    eq(byId.heartlands_t1_camp, byId.heartlands_t1_01, 'camp and territory are the same place')
    eq('heartlands_t1_camp', byId.heartlands_t1_01.id, 'canonical id is the territory (added first)')
end)

it('index carries class for lots/claims (drives the tight town-lot probe)', function()
    eq('town_lot', byId.heartlands_lot_01.class)
    eq('lot', byId.heartlands_lot_01.kind)
    eq('claim', byId.heartlands_01.class)
    eq(nil, byId.valentine.class, 'towns carry no class')
end)

it('index lists each physical spot once (no duplicate coordinates)', function()
    local seen = {}
    for _, p in ipairs(places) do
        local key = tostring(p.x) .. ',' .. tostring(p.y) .. ',' .. tostring(p.z)
        assert(not seen[key], 'duplicate coords ' .. key .. ' (' .. p.id .. ' vs ' .. tostring(seen[key]) .. ')')
        seen[key] = p.id
    end
end)

it('index order is deterministic: sorted by kind then id', function()
    for i = 2, #places do
        local a, b = places[i - 1], places[i]
        local ok = (a.kind < b.kind) or (a.kind == b.kind and a.id < b.id)
        assert(ok, 'places out of order at ' .. i .. ': ' .. a.kind .. '/' .. a.id .. ' then ' .. b.kind .. '/' .. b.id)
    end
end)

it('index entry shape is { x, y, z, kind, region, verified }', function()
    local p = byId.heartlands_01
    eq('number', type(p.x))
    eq('number', type(p.y))
    eq('number', type(p.z))
    eq('claim', p.kind)
    eq('heartlands', p.region)
    eq(false, p.verified)
end)

it('verified defaults to false (unverified) when the source carries no flag', function()
    eq(false, byId.valentine.verified)          -- town
    eq(false, byId.valentine_post.verified)     -- post
    eq(false, byId.heartlands_t1_camp.verified) -- territory
end)

it('index includes ambush nodes when present and skips them when absent', function()
    local r = {
        regions = { r1 = { id = 'r1', towns = {},
            ambush = { { id = 'r1_amb_1', x = 1, y = 2, z = 3, label = 'Road bend', verified = false } } } },
        territories = {}, posts = {},
    }
    local _, b = P.index(r, {})
    eq('ambush', b.r1_amb_1.kind)
    eq(false, b.r1_amb_1.verified)
    -- block H is landing in parallel; a region with no ambush is simply skipped
    local p2 = P.index({ regions = { r2 = { id = 'r2', towns = {} } }, territories = {}, posts = {} }, {})
    eq(0, #p2)
end)

it('index tolerates absent sources', function()
    local p, b = P.index(nil, nil)
    eq(0, #p)
    eq(nil, next(b))
end)

-- ---------------------------------------------------------------- nearest

it('nearest returns the closest place within 30 m (2D)', function()
    local pts = {
        { id = 'a', x = 0, y = 0, z = 999, kind = 'claim' },
        { id = 'b', x = 0, y = 40, z = 0, kind = 'claim' },
    }
    local p, d = P.nearest(pts, { x = 0, y = 0, z = 0 }, 30)
    eq('a', p.id)
    eq(0, d)
    eq(nil, P.nearest(pts, { x = 0, y = 100, z = 0 }, 30))
end)

it('nearest ignores z (only x/y proximity)', function()
    local pts = { { id = 'a', x = 0, y = 20, z = 0, kind = 'claim' } }
    local p = P.nearest(pts, { x = 0, y = 0, z = 500 }, 30)
    eq('a', p and p.id)
end)

-- ---------------------------------------------------------------- tour

it('tour orders unverified places greedy from the first town (origin excluded)', function()
    local pts = {
        { id = 'town1', x = 0, y = 0, kind = 'town', region = 'r', verified = false },
        { id = 'far', x = 100, y = 0, kind = 'claim', region = 'r', verified = false },
        { id = 'near', x = 10, y = 0, kind = 'claim', region = 'r', verified = false },
        { id = 'done', x = 50, y = 0, kind = 'claim', region = 'r', verified = true }, -- verified: skipped
        { id = 'other', x = 0, y = 0, kind = 'claim', region = 's', verified = false }, -- other region: skipped
    }
    local ids = {}
    for _, p in ipairs(P.tour(pts, 'r')) do ids[#ids + 1] = p.id end
    T.same({ 'near', 'far' }, ids)
end)

it('tour with no town starts from the first candidate', function()
    local pts = {
        { id = 'a', x = 0, y = 0, kind = 'claim', region = 'r', verified = false },
        { id = 'b', x = 10, y = 0, kind = 'claim', region = 'r', verified = false },
    }
    local order = P.tour(pts, 'r')
    T.same({ 'a', 'b' }, { order[1].id, order[2].id })
end)

it('tour returns empty for a region with no unverified places', function()
    local pts = { { id = 't', x = 0, y = 0, kind = 'town', region = 'r', verified = true } }
    eq(0, #P.tour(pts, 'r'))
end)

it('heartlands tour visits unverified places once each, with one town as the origin', function()
    local order = P.tour(places, 'heartlands')
    assert(#order > 0, 'heartlands has unverified places')
    local seen, towns = {}, 0
    for _, p in ipairs(order) do
        eq('heartlands', p.region)
        eq(false, p.verified)
        local key = tostring(p.x) .. ',' .. tostring(p.y)
        assert(not seen[key], 'duplicate tour coords ' .. key .. ' (' .. p.id .. ')')
        seen[key] = true
        if p.kind == 'town' then towns = towns + 1 end
    end
    eq(1, towns, 'heartlands has two towns: one is the origin (excluded), the other is a stop')
end)

it('advanceTour returns the next place and nil at the end', function()
    local s = { order = { { id = 'a' }, { id = 'b' } }, index = 1 }
    eq('b', P.advanceTour(s).id)
    eq(nil, P.advanceTour(s))
end)

-- ---------------------------------------------------------------- mark

it('markRecord builds the { id, verdict, note, x, y, z, ts, by } shape', function()
    local r = P.markRecord({ id = 'heartlands_01' }, 'bad', 'floats above ground', { x = 1, y = 2, z = 3 }, 1000, 7)
    eq('heartlands_01', r.id)
    eq('bad', r.verdict)
    eq('floats above ground', r.note)
    eq(1, r.x)
    eq(2, r.y)
    eq(3, r.z)
    eq(1000, r.ts)
    eq(7, r.by)
end)

it('appendMark appends and caps at the limit (keeps the last N)', function()
    local out = P.appendMark(nil, { id = 'a', verdict = 'ok' })
    eq(1, #out)
    eq('a', out[1].id)
    local out2 = P.appendMark({ { id = 'x' }, { id = 'y' } }, { id = 'z', verdict = 'bad' }, 2)
    eq(2, #out2)
    eq('y', out2[1].id)
    eq('z', out2[2].id)
end)

-- A minimal JSON codec for the flat {id,verdict} records used in the injected I/O tests below.
local function enc(t)
    local parts = {}
    for _, e in ipairs(t) do
        parts[#parts + 1] = ('{"id":"%s","verdict":"%s"}'):format(tostring(e.id), tostring(e.verdict))
    end
    return '[' .. table.concat(parts, ',') .. ']'
end
local function dec(raw)
    local out = {}
    for id, verdict in tostring(raw):gmatch('"id":"([^"]*)","verdict":"([^"]*)"') do
        out[#out + 1] = { id = id, verdict = verdict }
    end
    return out
end

it('recordWalkMark reads, appends and writes valid JSON via injected deps', function()
    local saved
    local deps = {
        load = function() return '[{"id":"old","verdict":"ok"}]' end,
        save = function(s) saved = s end,
        encode = enc, decode = dec,
    }
    local out = P.recordWalkMark(deps, { id = 'heartlands_01', verdict = 'bad', x = 1, y = 2, z = 3, ts = 1000, by = 7 })
    eq(2, #out)
    eq('old', out[1].id)
    eq('heartlands_01', out[2].id)
    eq('[{"id":"old","verdict":"ok"},{"id":"heartlands_01","verdict":"bad"}]', saved)
end)

it('recordWalkMark starts a fresh array on a missing or corrupt file', function()
    local saved1
    P.recordWalkMark({ load = function() return nil end, save = function(s) saved1 = s end, encode = enc, decode = dec },
        { id = 'a', verdict = 'ok' })
    eq('[{"id":"a","verdict":"ok"}]', saved1)

    local saved2
    local out = P.recordWalkMark({
        load = function() return '{{{{' end,
        save = function(s) saved2 = s end,
        encode = enc, decode = function() error('corrupt json') end,
    }, { id = 'b', verdict = 'bad' })
    eq(1, #out)
    eq('b', out[1].id)
    eq('[{"id":"b","verdict":"bad"}]', saved2)
end)

it('recordWalkMark rejects missing deps', function()
    local _, e = P.recordWalkMark(nil, { id = 'a', verdict = 'ok' })
    eq('fh_mark_bad_deps', e)
end)

T.finish()

-- Run from repo root: `lua spec/quests_region_gate_spec.lua` (or via tools/run-specs.py).
-- quests-02 C0: job-type data per region (data/regions/<id>.lua, one per FhRegions id) and the enabled gate on the
-- board (board.collect) and on accept (board.offerRegion). The gate reads FhRegions.isEnabled, so flipping a
-- region's `enabled` flag is the only change needed to show its offers.
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local describe, it, eq, same = T.describe, T.it, T.eq, T.same
local root = here .. '../server/resources/[fh]/fh_quests/'
package.path = root .. 'shared/?.lua;' .. package.path
local JT = dofile(root .. 'shared/jobtypes.lua')
local B = require('board')
local regions = require('regions')

local DISABLED = 'bluewater_marsh'

-- The server's job-type registry shape (Q.jobTypes[name] = { hooks = { offers } }), built from the built-ins.
local function jobTypes()
    local t = {}
    for _, name in ipairs(JT.TYPES) do
        t[name] = { hooks = { offers = function(region_id) return JT.offers(name, region_id) end } }
    end
    return t
end

local function count(lists)
    local n = 0
    for _, l in pairs(lists) do n = n + #l end
    return n
end

-- Give a disabled region the heartlands templates (as C5 will), run f, then restore data and flag.
local function withData(region_id, f)
    local before, flag = JT.DATA[region_id], regions.regions[region_id].enabled
    JT.registerRegion(region_id, JT.DATA.heartlands)
    local ok, err = pcall(f)
    JT.registerRegion(region_id, before)
    regions.regions[region_id].enabled = flag
    if not ok then error(err, 0) end
end

describe('quests region gate: data files', function()
    it('every FhRegions id has data/regions/<id>.lua and it registers a table for that id', function()
        local n = 0
        for id in pairs(regions.regions) do
            local f = io.open(root .. 'data/regions/' .. id .. '.lua', 'r')
            assert(f, 'missing data/regions/' .. id .. '.lua')
            f:close()
            eq('table', type(JT.DATA[id]), id)
            n = n + 1
        end
        eq(15, n)
    end)
    it('every builder is registered and the heartlands templates load', function()
        for _, name in ipairs(JT.TYPES) do eq('function', type(JT.BUILDERS[name]), name) end
        eq(6, #JT.offers('hunt_request', 'heartlands'))
        eq(1, #JT.offers('camp_clear', 'heartlands'))
        eq(2, #JT.offers('bounty', 'heartlands'))
        eq(1, #JT.offers('supply_run', 'heartlands'))
    end)
    it('the test region is disabled today', function()
        eq(false, regions.isEnabled(DISABLED))
        eq(true, regions.isEnabled('heartlands'))
    end)
end)

describe('quests region gate: board offers', function()
    it('a disabled region with data yields 0 offers', function()
        withData(DISABLED, function()
            assert(#JT.offers('hunt_request', DISABLED) > 0, 'the job type itself has templates')
            local lists = B.collect(DISABLED, jobTypes(), regions.isEnabled)
            eq(0, count(lists))
            eq(0, #B.rotate(DISABLED, 490001, lists))
        end)
    end)
    it('flipping enabled shows its offers with no code change', function()
        withData(DISABLED, function()
            regions.regions[DISABLED].enabled = true
            local lists = B.collect(DISABLED, jobTypes(), regions.isEnabled)
            eq(10, count(lists))
            local n = #B.rotate(DISABLED, 490001, lists)
            assert(n >= 3 and n <= 5, 'board of ' .. n)
        end)
    end)
    it('an enabled region collects every job type; unknown regions collect nothing', function()
        local lists = B.collect('heartlands', jobTypes(), regions.isEnabled)
        eq(6, #lists.hunt_request); eq(1, #lists.camp_clear); eq(2, #lists.bounty); eq(1, #lists.supply_run)
        eq(0, count(B.collect('nowhere', jobTypes(), regions.isEnabled)))
    end)
    it('the gate covers external job types too (a freight-like hook is never asked in a disabled region)', function()
        local asked = 0
        local jts = { freight = { hooks = { offers = function() asked = asked + 1; return { { key = 'x' } } end } } }
        eq(0, count(B.collect(DISABLED, jts, regions.isEnabled)))
        eq(0, asked)
        eq(1, count(B.collect('heartlands', jts, regions.isEnabled)))
    end)
    it('a hook that throws or returns a non-table is skipped and reported; the rest still show', function()
        local jts = jobTypes()
        jts.broken = { hooks = { offers = function() error('boom') end } }
        jts.odd = { hooks = { offers = function() return 'nope' end } }
        local lists, failed = B.collect('heartlands', jts, regions.isEnabled)
        eq(nil, lists.broken); eq(nil, lists.odd)
        eq(10, count(lists))
        eq(1, #failed); eq('broken', failed[1].name)
        assert(tostring(failed[1].err):find('boom'))
    end)
end)

describe('quests region gate: accept', function()
    it('an offer id in an enabled region names that region', function()
        eq('heartlands', B.offerRegion('heartlands:490001:bounty:bounty_silas_crow', regions.isEnabled))
    end)
    it('accept is refused in a disabled region, an unknown region, or for a malformed id', function()
        eq(nil, B.offerRegion(DISABLED .. ':490001:bounty:bounty_silas_crow', regions.isEnabled))
        eq(nil, B.offerRegion('nowhere:490001:bounty:x', regions.isEnabled))
        eq(nil, B.offerRegion('no_colon', regions.isEnabled))
        eq(nil, B.offerRegion(42, regions.isEnabled))
        eq(nil, B.offerRegion(nil, regions.isEnabled))
    end)
    it('flipping enabled makes the same offer id acceptable', function()
        local flag = regions.regions[DISABLED].enabled
        regions.regions[DISABLED].enabled = true
        local got = B.offerRegion(DISABLED .. ':490001:bounty:bounty_silas_crow', regions.isEnabled)
        regions.regions[DISABLED].enabled = flag
        eq(DISABLED, got)
    end)
end)

T.finish()

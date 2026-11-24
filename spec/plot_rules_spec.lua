-- Run from repo root: `lua spec/plot_rules_spec.lua` (or via tools/run-specs.py).
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local case = T.it
local R = dofile(here .. '../server/resources/[fh]/fh_homestead/shared/plot_rules.lua')

local plot = { id = 'p1', center = { x = 0, y = 0, z = 0 }, radius = 10.0 }
local plots = { p1 = plot, p2 = { id = 'p2', center = { x = 100, y = 0, z = 0 }, radius = 5.0 } }
local empty = { byPlot = {}, byOwner = {} }

case('inRadius: inside, edge, outside, bad coords', function()
    assert(R.inRadius(plot, { x = 3, y = 4, z = 0 }))
    assert(R.inRadius(plot, { x = 10, y = 0, z = 0 }))
    assert(not R.inRadius(plot, { x = 10.1, y = 0, z = 0 }))
    assert(not R.inRadius(plot, { x = 0, y = 0, z = 11 }))
    assert(not R.inRadius(plot, nil))
    assert(not R.inRadius(plot, { x = 0 / 0, y = 0, z = 0 }))
    assert(not R.inRadius({ center = plot.center }, { x = 0, y = 0, z = 0 }))
end)
case('plotAt: picks the containing plot or nil', function()
    assert(R.plotAt(plots, { x = 101, y = 0, z = 0 }).id == 'p2')
    assert(R.plotAt(plots, { x = 50, y = 0, z = 0 }) == nil)
end)
case('canClaim: free plot, in radius', function()
    assert(R.canClaim(plot, { x = 1, y = 1, z = 0 }, 'ABC', empty))
end)
case('canClaim: refusals', function()
    local function why(p, c, id, cl) local _, e = R.canClaim(p, c, id, cl) return e end
    local here0 = { x = 0, y = 0, z = 0 }
    assert(why(plot, { x = 50, y = 0, z = 0 }, 'ABC', empty) == 'fh_not_in_plot')
    assert(why(plot, here0, 'ABC', { byPlot = { p1 = 'XYZ' }, byOwner = { XYZ = 'p1' } }) == 'fh_plot_taken')
    assert(why(plot, here0, 'ABC', { byPlot = { p2 = 'ABC' }, byOwner = { ABC = 'p2' } }) == 'fh_already_has_plot')
    assert(why(plot, here0, nil, empty) == 'fh_no_character')
    assert(why(plot, here0, '', empty) == 'fh_no_character')
    assert(why(nil, here0, 'ABC', empty) == 'fh_no_plot')
end)
case('canUnclaim: owner, admin, stranger, free plot', function()
    local cl = { byPlot = { p1 = 'ABC' }, byOwner = { ABC = 'p1' } }
    assert(R.canUnclaim('p1', 'ABC', false, cl))
    assert(R.canUnclaim('p1', 'OTHER', true, cl))
    local ok, e = R.canUnclaim('p1', 'OTHER', false, cl)
    assert(not ok and e == 'fh_not_owner')
    ok, e = R.canUnclaim('p2', 'ABC', true, cl)
    assert(not ok and e == 'fh_plot_free')
end)
case('canOpenChest: owner only', function()
    local cl = { byPlot = { p1 = 'ABC' }, byOwner = { ABC = 'p1' } }
    assert(R.canOpenChest('p1', 'ABC', cl))
    local ok, e = R.canOpenChest('p1', 'OTHER', cl)
    assert(not ok and e == 'fh_not_owner')
    ok, e = R.canOpenChest('p1', nil, cl)
    assert(not ok and e == 'fh_not_owner')
    ok, e = R.canOpenChest('p2', 'ABC', cl)
    assert(not ok and e == 'fh_plot_free')
end)
case('chestStashId format', function()
    assert(R.chestStashId('heartlands_01') == 'fh:chest:heartlands_01:1')
    assert(R.chestStashId('a', 2) == 'fh:chest:a:2')
end)
case('validCoords/inRadius/plotAt accept vector3-like values that are not plain tables', function()
    -- CfxLua vector3 is not type 'table'. Stub: a proxy whose x/y/z are only reachable through __index (no raw fields).
    local function vec(x, y, z)
        local data = { x = x, y = y, z = z }
        return setmetatable({}, { __index = data })
    end
    assert(R.validCoords(vec(1, 2, 3)))
    assert(not R.validCoords(vec(1, 2, 0 / 0)))
    assert(not R.validCoords(42) and not R.validCoords('str') and not R.validCoords(nil))
    local vplot = { id = 'v', center = vec(0, 0, 0), radius = 10.0 }
    assert(R.inRadius(vplot, vec(3, 4, 0)))
    assert(not R.inRadius(vplot, vec(30, 4, 0)))
    assert(R.plotAt({ v = vplot }, vec(1, 1, 1)) == vplot)
    assert(R.canClaim(vplot, vec(1, 1, 1), 'ABC', empty))
end)

-- homestead-02 H6: per-class uniqueness (one claim + one town lot per character).
local here0 = { x = 0, y = 0, z = 0 }
local claimPlot = { id = 'c1', center = here0, radius = 10.0 }                       -- no class = claim
local lotPlot = { id = 'l1', center = here0, radius = 10.0, class = 'town_lot', claimable = true }
local function why(p, cl) local ok, e = R.canClaim(p, here0, 'ABC', cl) return ok, e end

case('classOf: missing/blank class is claim, explicit class kept', function()
    assert(R.classOf(claimPlot) == 'claim')
    assert(R.classOf({ class = '' }) == 'claim')
    assert(R.classOf({ class = 'claim' }) == 'claim')
    assert(R.classOf(lotPlot) == 'town_lot')
    assert(R.classOf(nil) == 'claim')
end)
case('canClaim per class: a claim owner may take a lot, a lot owner may take a claim', function()
    local hasClaim = { byPlot = { c0 = 'ABC' }, byOwner = { claim = { ABC = 'c0' }, town_lot = {} } }
    assert(why(lotPlot, hasClaim))
    local hasLot = { byPlot = { l0 = 'ABC' }, byOwner = { claim = {}, town_lot = { ABC = 'l0' } } }
    assert(why(claimPlot, hasLot))
end)
case('canClaim per class: second claim refused fh_already_has_plot, second lot refused fh_already_has_lot', function()
    local both = { byPlot = { c0 = 'ABC', l0 = 'ABC' }, byOwner = { claim = { ABC = 'c0' }, town_lot = { ABC = 'l0' } } }
    local ok, e = why(claimPlot, both)
    assert(not ok and e == 'fh_already_has_plot', tostring(e))
    ok, e = why(lotPlot, both)
    assert(not ok and e == 'fh_already_has_lot', tostring(e))
    -- explicit class = 'claim' behaves like a missing class
    ok, e = why({ id = 'c2', center = here0, radius = 10.0, class = 'claim' }, both)
    assert(not ok and e == 'fh_already_has_plot', tostring(e))
    -- another character's lot does not block ABC
    assert(why(lotPlot, { byPlot = { l0 = 'XYZ' }, byOwner = { town_lot = { XYZ = 'l0' } } }))
end)
case('canClaim: claimable=false refused fh_not_claimable (nil/true allowed)', function()
    local ok, e = why({ id = 'l2', center = here0, radius = 10.0, class = 'town_lot', claimable = false }, empty)
    assert(not ok and e == 'fh_not_claimable', tostring(e))
    ok, e = why({ id = 'c3', center = here0, radius = 10.0, claimable = false }, empty)
    assert(not ok and e == 'fh_not_claimable', tostring(e))
    assert(why(lotPlot, empty))
    assert(why(claimPlot, empty))
end)
case('canClaim: old flat byOwner { [cid] = plot_id } still read, as class claim', function()
    local flat = { byPlot = { p2 = 'ABC' }, byOwner = { ABC = 'p2' } }
    local ok, e = why(claimPlot, flat)
    assert(not ok and e == 'fh_already_has_plot', tostring(e))
    assert(why(claimPlot, { byPlot = { p2 = 'XYZ' }, byOwner = { XYZ = 'p2' } }))   -- other cid's flat entry
    assert(why(lotPlot, flat))                                                         -- flat entries are claims only
end)
case('canClaim region gate (world-02 G1): disabled refused, enabled ok, nil region ok, no gate = allowed', function()
    local gate = function(id) return id ~= 'off_region' end
    local function rg(p, g) local ok, e = R.canClaim(p, here0, 'ABC', empty, g) return ok, e end
    local rp = { id = 'rp', center = here0, radius = 10.0, region = 'off_region' }
    local ok, e = rg(rp, gate)
    assert(not ok and e == 'fh_region_disabled', tostring(e))
    rp.region = 'on_region'
    assert(rg(rp, gate), 'enabled region allowed')
    rp.region = nil
    assert(rg(rp, gate), 'nil region (legacy) is always allowed')
    rp.region = ''
    assert(rg(rp, gate), 'empty region (legacy) is always allowed')
    -- no isEnabled arg and no FhRegions global: today's behaviour, the region is not checked
    assert(R.canClaim({ id = 'p2', center = here0, radius = 10.0, region = 'off_region' }, here0, 'ABC', empty))
end)
T.finish()

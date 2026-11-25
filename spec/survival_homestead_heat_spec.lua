-- Run from repo root: `lua spec/survival_homestead_heat_spec.lua` (or via tools/run-specs.py).
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
package.path = here .. '../server/resources/[fh]/fh_survival/shared/?.lua;' .. package.path
local case = T.it
local H = require('homestead_heat')

local camp1 = { plot_id = 'p1', slot_id = 's2', station_type = 'campfire', coords = { x = 1, y = 2, z = 3 } }
local camp2 = { plot_id = 'p2', slot_id = 's2', station_type = 'campfire', coords = { x = 50, y = 60, z = 7 } }
local bench = { plot_id = 'p1', slot_id = 's1', station_type = 'workbench', coords = { x = 4, y = 5, z = 6 } }

case('nearby campfire -> source added', function()
    local adds, removes = H.reconcile(true, {}, { camp1 }, 8.0)
    assert(#adds == 1 and #removes == 0)
    local a = adds[1]
    assert(a.id == 'hs:p1:s2' and a.coords.x == 1 and a.coords.y == 2 and a.coords.z == 3 and a.radius == 8.0)
end)

case('no player near fire any more -> source removed', function()
    local adds, removes = H.reconcile(true, { ['hs:p1:s2'] = true }, {}, 8.0)
    assert(#adds == 0 and #removes == 1 and removes[1] == 'hs:p1:s2')
end)

case('homestead stopped -> ours cleared, nothing added (seeded fires untouched)', function()
    local adds, removes = H.reconcile(false, { ['hs:p1:s2'] = true }, { camp1 }, 8.0)
    assert(#adds == 0, 'no source is added while stopped')
    assert(#removes == 1 and removes[1] == 'hs:p1:s2', 'our own source is cleared')
end)

case('non-campfire station ignored', function()
    local adds, removes = H.reconcile(true, {}, { bench }, 8.0)
    assert(#adds == 0 and #removes == 0)
end)

case('player moves to another plot campfire: old removed, new added', function()
    local adds, removes = H.reconcile(true, { ['hs:p1:s2'] = true }, { camp2 }, 8.0)
    assert(#removes == 1 and removes[1] == 'hs:p1:s2')
    assert(#adds == 1 and adds[1].id == 'hs:p2:s2')
end)

case('already-registered fire is stable (no re-add, no remove)', function()
    local adds, removes = H.reconcile(true, { ['hs:p1:s2'] = true }, { camp1 }, 8.0)
    assert(#adds == 0 and #removes == 0)
end)

case('malformed stations are skipped', function()
    local adds, removes = H.reconcile(true, {}, {
        { station_type = 'campfire' }, -- no ids/coords
        { plot_id = 'p1', slot_id = 's2', station_type = 'campfire', coords = { x = 'a', y = 2 } },
        'junk',
    }, 8.0)
    assert(#adds == 0 and #removes == 0)
end)

case('two players near the same campfire emit a single add', function()
    local adds, removes = H.reconcile(true, {}, { camp1, camp1 }, 8.0)
    assert(#adds == 1 and adds[1].id == 'hs:p1:s2', 'one add for a duplicated station')
    assert(#removes == 0)
end)

case('two players near an already-active campfire stay stable', function()
    local adds, removes = H.reconcile(true, { ['hs:p1:s2'] = true }, { camp1, camp1 }, 8.0)
    assert(#adds == 0 and #removes == 0)
end)

case('multiple players near different campfires register both and drop stale ones', function()
    local adds, removes = H.reconcile(true, { ['hs:p1:s2'] = true, ['hs:p9:s2'] = true }, { camp1, camp2 }, 8.0)
    assert(#adds == 1 and adds[1].id == 'hs:p2:s2')
    assert(#removes == 1 and removes[1] == 'hs:p9:s2')
end)

case('nil active and nil stations are safe', function()
    local adds, removes = H.reconcile(true, nil, nil, 8.0)
    assert(#adds == 0 and #removes == 0)
end)

case('searchRadius validates positive finite numbers and falls back to default', function()
    assert(H.searchRadius(30.0) == 30.0)
    assert(H.searchRadius(nil) == H.DEFAULT_SEARCH_RADIUS)
    assert(H.searchRadius(0) == H.DEFAULT_SEARCH_RADIUS)
    assert(H.searchRadius(-5) == H.DEFAULT_SEARCH_RADIUS)
    assert(H.searchRadius(0 / 0) == H.DEFAULT_SEARCH_RADIUS)
    assert(H.searchRadius('25') == H.DEFAULT_SEARCH_RADIUS)
end)

T.finish()

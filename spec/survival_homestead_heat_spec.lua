-- Run from repo root: `lua spec/survival_homestead_heat_spec.lua` (or via tools/run-specs.py).
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
package.path = here .. '../server/resources/[fh]/fh_survival/shared/?.lua;' .. package.path
local case = T.it
local H = require('homestead_heat')

local camp = { plot_id = 'p1', slot_id = 's2', station_type = 'campfire', coords = { x = 1, y = 2, z = 3 } }
local bench = { plot_id = 'p1', slot_id = 's1', station_type = 'workbench', coords = { x = 4, y = 5, z = 6 } }

case('owned fire -> source added', function()
    local adds, removes = H.reconcile(true, {}, { camp }, 8.0)
    assert(#adds == 1 and #removes == 0)
    local a = adds[1]
    assert(a.id == 'hs:p1:s2' and a.coords.x == 1 and a.coords.y == 2 and a.coords.z == 3 and a.radius == 8.0)
end)

case('fire removed -> source removed', function()
    local adds, removes = H.reconcile(true, { ['hs:p1:s2'] = true }, {}, 8.0)
    assert(#adds == 0 and #removes == 1 and removes[1] == 'hs:p1:s2')
end)

case('homestead stopped -> ours cleared, nothing added (seeded fires untouched)', function()
    local adds, removes = H.reconcile(false, { ['hs:p1:s2'] = true }, { camp }, 8.0)
    assert(#adds == 0, 'no source is added while stopped')
    assert(#removes == 1 and removes[1] == 'hs:p1:s2', 'our own source is cleared')
end)

case('non-campfire station ignored', function()
    local adds, removes = H.reconcile(true, {}, { bench }, 8.0)
    assert(#adds == 0 and #removes == 0)
end)

case('station moved to a new slot: old removed, new added', function()
    local moved = { plot_id = 'p1', slot_id = 's3', station_type = 'campfire', coords = { x = 7, y = 8, z = 9 } }
    local adds, removes = H.reconcile(true, { ['hs:p1:s2'] = true }, { moved }, 8.0)
    assert(#removes == 1 and removes[1] == 'hs:p1:s2')
    assert(#adds == 1 and adds[1].id == 'hs:p1:s3')
end)

case('already-registered fire is stable (no re-add, no remove)', function()
    local adds, removes = H.reconcile(true, { ['hs:p1:s2'] = true }, { camp }, 8.0)
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

case('nil owned and nil stations are safe', function()
    local adds, removes = H.reconcile(true, nil, nil, 8.0)
    assert(#adds == 0 and #removes == 0)
end)

T.finish()

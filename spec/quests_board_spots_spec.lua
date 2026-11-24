-- Run from repo root: `lua spec/quests_board_spots_spec.lua` (or via tools/run-specs.py).
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local case = T.it
local B = dofile(here .. '../server/resources/[fh]/fh_quests/shared/board_spots.lua')

case('board spots cover the known regions with coordinates', function()
    T.eq(2, #B.spots)
    local regions = {}
    for _, s in ipairs(B.spots) do regions[s.region_id] = true end
    assert(regions.heartlands, 'heartlands board missing')
    assert(regions.scarlett_meadows, 'scarlett_meadows board missing')
    for _, s in ipairs(B.spots) do
        assert(type(s.coords.x) == 'number' and type(s.coords.y) == 'number' and type(s.coords.z) == 'number')
    end
end)

case('regionFor picks the nearest board to the player', function()
    T.eq('heartlands', B.regionFor({ x = -297, y = 795, z = 118 }))
    T.eq('scarlett_meadows', B.regionFor({ x = 1288, y = -1278, z = 77 }))
    -- A point between the two, nearer to the Heartlands board.
    T.eq('heartlands', B.regionFor({ x = 0, y = 0, z = 100 }))
    -- A point near Rhodes.
    T.eq('scarlett_meadows', B.regionFor({ x = 1300, y = -1300, z = 77 }))
end)

case('regionFor falls back to DEFAULT_REGION when the position or spots are unusable', function()
    T.eq('heartlands', B.regionFor(nil))
    T.eq('heartlands', B.regionFor({ x = 1, y = 2 })) -- no z
    T.eq('heartlands', B.regionFor({ x = 0, y = 0, z = 0 }, {})) -- no spots
    T.eq('heartlands', B.regionFor({ x = 0, y = 0, z = 0 }, { { region_id = 'other', coords = { x = 1, y = 2 } } })) -- unusable spot
end)

case('regionFor skips disabled-region spots (enabled gate)', function()
    local enabled = { heartlands = true, scarlett_meadows = false }
    local isEnabled = function(id) return enabled[id] == true end
    -- nearest board is Rhodes (disabled): skipped, so the pick falls back to Heartlands
    T.eq('heartlands', B.regionFor({ x = 1288, y = -1278, z = 77 }, B.spots, isEnabled))
    T.eq('heartlands', B.regionFor({ x = 1300, y = -1300, z = 77 }, B.spots, isEnabled))
    -- no filter: today's behaviour
    T.eq('scarlett_meadows', B.regionFor({ x = 1288, y = -1278, z = 77 }, B.spots, nil))
end)

T.finish()

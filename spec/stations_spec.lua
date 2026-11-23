local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local case = T.it
local dir = here .. '../server/resources/[fh]/fh_homestead/'
local S = dofile(dir .. 'shared/stations.lua')
dofile(dir .. 'config.lua')
local plots = FhHomesteadConfig.plots
local p1 = plots.heartlands_01
-- offsets from plot center: workbench (6,4), campfire (6,-4), tanning_rack (10,0)
local function at(plot, dx, dy) return { x = plot.center.x + dx, y = plot.center.y + dy, z = plot.center.z } end

case('unbuilt stations are not listed; non-station slots never are', function()
    T.eq(0, #S.builtStations(p1, {}))
    T.eq(0, #S.builtStations(p1, { cabin = 2, fence = 1, trophy_wall = 1, chest_2 = 1 }))
    T.eq(0, #S.builtStations(p1, { station_1 = 0 }))
end)
case('built stations listed with type and coords', function()
    local l = S.builtStations(p1, { station_1 = 1, station_2 = 1 })
    T.eq(2, #l)
    T.eq('station_1', l[1].slot_id); T.eq('workbench', l[1].station_type); T.eq('heartlands_01', l[1].plot_id)
    T.eq(p1.center.x + 6.0, l[1].coords.x); T.eq(p1.center.y + 4.0, l[1].coords.y)
end)
case('nearest within radius (inclusive); outside refused', function()
    local l = S.builtStations(p1, { station_1 = 1, station_3 = 1 })
    local s, d = S.nearest(l, at(p1, 6.0, 5.0), 3.0)
    T.eq('station_1', s.slot_id); T.eq(1.0, d)
    assert(S.nearest(l, at(p1, 6.0, 7.0), 3.0) ~= nil, 'exactly at maxDist counts')
    assert(S.nearest(l, at(p1, 6.0, 7.5), 3.0) == nil)
end)
case('nearest picks the closest of several', function()
    local l = S.builtStations(p1, { station_1 = 1, station_2 = 1, station_3 = 1 })
    T.eq('station_3', S.nearest(l, at(p1, 9.0, 0.5), 20).slot_id)
end)
case('type match filters', function()
    local l = S.builtStations(p1, { station_1 = 1, station_2 = 1 })
    local c = at(p1, 6.0, 4.0) -- on the workbench
    T.eq('station_2', S.nearest(l, c, 10, 'campfire').slot_id)
    assert(S.nearest(l, c, 10, 'tanning_rack') == nil)
end)
case('multiple plots: allStations covers all, onlyPlot restricts', function()
    local t = { heartlands_01 = { station_1 = 1 }, heartlands_02 = { station_1 = 1, station_2 = 1 } }
    T.eq(3, #S.allStations(plots, t))
    T.eq(2, #S.allStations(plots, t, nil, 'heartlands_02'))
    T.eq(0, #S.allStations(plots, t, nil, 'heartlands_03'))
    local s = S.nearest(S.allStations(plots, t), at(plots.heartlands_02, 6.0, 4.0), 1.0)
    T.eq('heartlands_02', s.plot_id)
end)
case('unknown station type / bad slots ignored', function()
    local plot = { id = 'x', center = { x = 0, y = 0, z = 0 }, slots = {
        a = { kind = 'station', stationType = 'workbench', prop = { offset = { x = 1, y = 0, z = 0 } } },
        b = { kind = 'station', prop = { offset = { x = 1, y = 0, z = 0 } } },
        c = { kind = 'station', stationType = 'forge', prop = { offset = { x = 'bad', y = 0, z = 0 } } },
        d = 'junk' } }
    local l = S.builtStations(plot, { a = 1, b = 1, c = 1, d = 1 })
    T.eq(1, #l)
    assert(S.nearest(l, { x = 0, y = 0, z = 0 }, 5, 'nonexistent') == nil)
end)
case('nil / garbage safety', function()
    T.eq(0, #S.builtStations(nil, nil))
    T.eq(0, #S.allStations(nil, nil))
    assert(S.nearest(nil, { x = 0, y = 0, z = 0 }) == nil)
    assert(S.nearest({}, nil) == nil)
    assert(S.nearest({}, { x = 0 / 0, y = 0, z = 0 }) == nil)
    assert(S.slotCoords(nil, nil) == nil)
    assert(S.isStationBuilt(nil, 0, 1) == false)
end)
case('station_built only on 0 -> >=1 of a station slot', function()
    local st, ch = p1.slots.station_1, p1.slots.cabin
    assert(S.isStationBuilt(st, 0, 1)); assert(S.isStationBuilt(st, nil, 1))
    assert(not S.isStationBuilt(st, 1, 1)); assert(not S.isStationBuilt(st, 1, 0))
    assert(not S.isStationBuilt(ch, 0, 1))
end)
T.finish()

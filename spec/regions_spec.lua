-- Run from repo root: `lua spec/regions_spec.lua` (or via busted).
local case = dofile('./spec/_harness.lua').case
local regions = require('regions')

local t1 = regions.getTerritory('heartlands_t1_camp')

case('lookups return known ids and nil otherwise', function()
    assert(regions.getRegion('heartlands').id == 'heartlands')
    assert(regions.getRegion('atlantis') == nil)
    assert(regions.getFaction('outlaws') ~= nil)
    assert(t1 and t1.tier == 'T1' and t1.region == 'heartlands')
    assert(regions.isKnownRegion('heartlands') == true)
    assert(regions.isKnownRegion('x') == false and regions.isKnownRegion(nil) == false)
end)
case('every territory references a known region and faction', function()
    for _, t in pairs(regions.territories) do
        assert(regions.regions[t.region], t.id)
        assert(regions.factions[t.faction], t.id)
        assert(t.radius > 0)
    end
end)
case('territoryAt finds the territory at its center and inside the radius', function()
    assert(regions.territoryAt(t1.center.x, t1.center.y) == t1)
    assert(regions.territoryAt(t1.center.x + t1.radius - 0.5, t1.center.y) == t1)
end)
case('territoryAt is nil outside the radius and for bad input', function()
    assert(regions.territoryAt(t1.center.x + t1.radius + 1, t1.center.y) == nil)
    assert(regions.territoryAt(0, 0) == nil)
    assert(regions.territoryAt(nil, 5) == nil)
    assert(regions.territoryAt('1', '2') == nil)
end)

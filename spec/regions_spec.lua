-- Run from repo root: `lua spec/regions_spec.lua` (or via busted).
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local case = T.it
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

-- ---------------------------------------------------------------- world-01: 15 regions

local ALL_REGIONS = {
    'heartlands', 'scarlett_meadows', 'bayou_nwa', 'bluewater_marsh', 'roanoke_ridge',
    'grizzlies_east', 'grizzlies_west', 'cumberland_forest', 'big_valley', 'great_plains',
    'tall_trees', 'hennigans_stead', 'cholla_springs', 'gaptooth_ridge', 'rio_bravo',
}
local ENABLED = { heartlands = true, scarlett_meadows = true, bayou_nwa = true, great_plains = true }
local STATES = { new_hanover = true, lemoyne = true, ambarino = true, west_elizabeth = true, new_austin = true }

case('the 15 regions are known and carry state/towns/enabled', function()
    assert(#ALL_REGIONS == 15, #ALL_REGIONS)
    for _, id in ipairs(ALL_REGIONS) do
        local r = regions.getRegion(id)
        assert(r ~= nil, id)
        assert(r.id == id, id)
        assert(type(r.label) == 'string' and r.label ~= '', id .. ' label')
        assert(STATES[r.state], id .. ' state ' .. tostring(r.state))
        assert(type(r.enabled) == 'boolean', id .. ' enabled')
        assert(type(r.towns) == 'table', id .. ' towns')
        assert(type(r.factions) == 'table', id .. ' factions')
        for _, f in ipairs(r.factions) do
            assert(regions.getFaction(f) ~= nil, id .. ' faction ' .. tostring(f))
        end
        for _, town in ipairs(r.towns) do
            assert(type(town.id) == 'string', id .. ' town id')
            assert(type(town.label) == 'string', id .. ' town label')
            assert(type(town.x) == 'number' and type(town.y) == 'number' and type(town.z) == 'number', id .. ' town coords')
        end
    end
end)

case('isKnownRegion is true for all 15 and false for guarma / junk', function()
    for _, id in ipairs(ALL_REGIONS) do
        assert(regions.isKnownRegion(id) == true, id)
    end
    assert(regions.isKnownRegion('guarma') == false, 'no Guarma')
    assert(regions.getRegion('guarma') == nil)
end)

case('enabled is true only for the four spawn-anchored regions', function()
    for _, id in ipairs(ALL_REGIONS) do
        local want = ENABLED[id] == true
        assert(regions.regions[id].enabled == want, id .. ' enabled=' .. tostring(regions.regions[id].enabled))
    end
end)

-- ---------------------------------------------------------------- world-01: 8 factions + alias

local FACTION_KIND = {
    lawmen = 'law', rhodes_law = 'law',
    raiders = 'outlaw', outlaws = 'outlaw', desert_gang = 'outlaw',
    rail_mining = 'neutral', settlers = 'neutral', traders = 'neutral', bounty_hunters = 'neutral',
}

case('the 8 factions plus the alias exist with id, label and kind', function()
    for id, kind in pairs(FACTION_KIND) do
        local f = regions.factions[id]
        assert(f ~= nil, id)
        assert(f.id == id, id)
        assert(type(f.label) == 'string' and f.label ~= '', id .. ' label')
    end
end)

case('kind values: law / outlaw / neutral', function()
    for id, kind in pairs(FACTION_KIND) do
        assert(regions.factions[id].kind == kind, id .. ' kind=' .. tostring(regions.factions[id].kind))
    end
    -- no RDR2 gang/company names survived the relabel
    for id, f in pairs(regions.factions) do
        assert(f.label ~= 'Lemoyne Raiders', id)
        assert(f.label ~= 'Heartland Outlaws', id)
        assert(f.label ~= 'Valentine Law', id)
    end
end)

case('rhodes_law is an alias that resolves to lawmen', function()
    local alias = regions.factions.rhodes_law
    assert(alias ~= nil and alias.alias_of == 'lawmen', 'rhodes_law alias_of')
    local resolved = regions.getFaction('rhodes_law')
    assert(resolved == regions.factions.lawmen, 'getFaction resolves the alias')
    assert(resolved.kind == 'law')
    assert(regions.getFaction('lawmen') == regions.factions.lawmen)
end)

T.finish()

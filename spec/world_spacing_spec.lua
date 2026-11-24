-- Run from repo root: `python tools/run-specs.py spec/world_spacing_spec.lua`.
-- world-01 (block C): outlaw camps keep >=200 m (2D) from every homestead claim, every town center (all 15
-- regions) and every town lot; every camp is owned (via its territory) by an outlaw faction in an enabled region.
-- Pure data checks against the live fh_zones / fh_homestead configs and the fh_core region registry.
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local case = T.it
local fh = here .. '../server/resources/[fh]/'

-- fh_zones config uses vector3 (a Cfx global); a table stand-in is enough for the pure checks.
vector3 = function(x, y, z) return { x = x, y = y, z = z } end
vector4 = function(x, y, z, w) return { x = x, y = y, z = z, w = w } end
dofile(fh .. 'fh_zones/config.lua')
dofile(fh .. 'fh_homestead/config.lua')
local zones = assert(_G.FhZonesConfig, 'FhZonesConfig missing')
local homestead = assert(_G.FhHomesteadConfig, 'FhHomesteadConfig missing')
local regions = require('regions')

local function dist2d(a, b)
    local dx, dy = a.x - b.x, a.y - b.y
    return math.sqrt(dx * dx + dy * dy)
end

local claims, lots = {}, {}
for id, p in pairs(homestead.plots) do
    if p.class == 'claim' then claims[id] = p
    elseif p.class == 'town_lot' then lots[id] = p end
end

case('every camp keeps the A-Life field shape and is known', function()
    assert(next(zones.camps) ~= nil, 'no camps in FhZonesConfig.camps')
    for id, c in pairs(zones.camps) do
        assert(c.id == id, id .. ' id field mismatch')
        assert(type(c.region) == 'string' and type(c.territory) == 'string' and c.center and c.peds and c.loot,
            id .. ' missing a required field (id/region/territory/center/activationRadius/peds/loot)')
        assert(type(c.activationRadius) == 'number' and c.activationRadius > 0, id .. ' activationRadius')
        assert(type(c.respawnMinutes) == 'number' and c.respawnMinutes > 0, id .. ' respawnMinutes')
        assert(type(c.peds) == 'table' and #c.peds >= 3 and #c.peds <= 5, id .. ' ped count')
        assert(type(c.loot.table) == 'table', id .. ' loot.table')
    end
end)

case('every camp is owned (via territory) by an outlaw faction in an enabled region', function()
    for id, c in pairs(zones.camps) do
        local r = regions.getRegion(c.region)
        assert(r ~= nil, id .. ' unknown region ' .. tostring(c.region))
        assert(r.enabled == true, id .. ' region ' .. c.region .. ' not enabled')
        local t = regions.getTerritory(c.territory)
        assert(t ~= nil, id .. ' missing territory ' .. tostring(c.territory))
        assert(t.region == c.region, id .. ' territory region mismatch')
        local f = regions.getFaction(t.faction)
        assert(f ~= nil, id .. ' missing faction ' .. tostring(t.faction))
        assert(f.kind == 'outlaw', id .. ' faction ' .. tostring(t.faction) .. ' kind=' .. tostring(f.kind))
        -- territory center is the A-Life node source; the camp center must sit on it.
        assert(dist2d(c.center, t.center) < 1.0, id .. ' camp/territory center mismatch')
    end
end)

case('every camp.enabled mirrors FhRegions.isEnabled(region) (world-01 block D gate)', function()
    for id, c in pairs(zones.camps) do
        assert((c.enabled == true) == regions.isEnabled(c.region), id .. ' enabled mismatch')
    end
end)

case('each enabled region has 3-4 camps', function()
    local counts = {}
    for _, c in pairs(zones.camps) do counts[c.region] = (counts[c.region] or 0) + 1 end
    for id, r in pairs(regions.regions) do
        if r.enabled then
            local n = counts[id] or 0
            assert(n >= 3 and n <= 4, id .. ' has ' .. tostring(n) .. ' camps (want 3-4)')
        end
    end
end)

case('every camp is >=200 m from every claim, town center and town lot', function()
    for id, c in pairs(zones.camps) do
        for cid, p in pairs(claims) do
            local d = dist2d(c.center, p.center)
            assert(d >= 200.0, id .. ' is ' .. tostring(d) .. ' m from claim ' .. cid)
        end
        for _, r in pairs(regions.regions) do
            for _, town in ipairs(r.towns or {}) do
                local d = dist2d(c.center, town)
                assert(d >= 200.0, id .. ' is ' .. tostring(d) .. ' m from town ' .. tostring(town.id))
            end
        end
        for lid, p in pairs(lots) do
            local d = dist2d(c.center, p.center)
            assert(d >= 200.0, id .. ' is ' .. tostring(d) .. ' m from town lot ' .. lid)
        end
    end
end)

T.finish()

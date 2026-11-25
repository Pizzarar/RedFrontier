-- Run from repo root: `python tools/run-specs.py spec/world_spacing_spec.lua`.
-- world-01 (block C): outlaw camps keep >=200 m (2D) from every homestead claim, every town center (all 15
-- regions) and every town lot; every camp is owned (via its territory) by an outlaw faction in an enabled region.
-- Pure data checks against the live fh_zones / fh_homestead configs and the fh_core region registry.
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local case = T.it
local fh = here .. '../server/resources/[fh]/'

-- Load FhRegions/FhPlaceResolver + vector3 stand-in (world-02 block F), then the configs (fh_zones resolves camps).
local regions = dofile(here .. 'support/world_config.lua')
dofile(fh .. 'fh_zones/config.lua')
dofile(fh .. 'fh_homestead/config.lua')
local zones = assert(_G.FhZonesConfig, 'FhZonesConfig missing')
local homestead = assert(_G.FhHomesteadConfig, 'FhHomesteadConfig missing')

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

case('every camp is owned (via territory) by an outlaw faction in a known region', function()
    for id, c in pairs(zones.camps) do
        local r = regions.getRegion(c.region)
        assert(r ~= nil, id .. ' unknown region ' .. tostring(c.region))
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

case('every region (enabled or disabled) has 3-4 camps', function()
    local counts = {}
    for _, c in pairs(zones.camps) do counts[c.region] = (counts[c.region] or 0) + 1 end
    for id, r in pairs(regions.regions) do
        local n = counts[id] or 0
        assert(n >= 3 and n <= 4, id .. ' has ' .. tostring(n) .. ' camps (want 3-4)')
    end
end)

case('every territory has exactly one camp (no orphan territories or duplicate camps)', function()
    local seen = {}
    for id, c in pairs(zones.camps) do
        assert(regions.getTerritory(c.territory) ~= nil, id .. ' territory missing')
        assert(not seen[c.territory], c.territory .. ' claimed by more than one camp')
        seen[c.territory] = true
    end
    for tid in pairs(regions.territories) do
        assert(seen[tid], tid .. ' has no camp')
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

case('every pair of camp territories does not overlap (center distance >= r1+r2)', function()
    local ids = {}
    for tid in pairs(regions.territories) do ids[#ids + 1] = tid end
    table.sort(ids)
    for i = 1, #ids do
        for j = i + 1, #ids do
            local a, b = regions.territories[ids[i]], regions.territories[ids[j]]
            local d = dist2d(a.center, b.center)
            assert(d >= a.radius + b.radius,
                ids[i] .. ' overlaps ' .. ids[j] .. ' (' .. tostring(d) .. ' < ' .. tostring(a.radius + b.radius) .. ')')
        end
    end
end)

-- ---------------------------------------------------------------- world-03 (block H): ambush nodes
-- a-life-02 B1 (fh_alife shared/alife_rules.lua buildGraph) reads regions[id].ambush = { { id, x, y, z, label,
-- verified }, ... }: a finite x/y/z makes a node; id/label/verified are optional but every node here carries them.
-- No heading/radius: fh_alife owns ambushRadius. Ids are stable (saved squads key on them), so <region>_amb_N.
local ambushIds = {}
for _, r in pairs(regions.regions) do
    for _, a in ipairs(r.ambush or {}) do ambushIds[a.id] = true end
end

case('every region has 2-3 ambush nodes in the a-life field shape', function()
    for id, r in pairs(regions.regions) do
        assert(type(r.ambush) == 'table', id .. ' missing ambush')
        local n = #r.ambush
        assert(n >= 2 and n <= 3, id .. ' has ' .. tostring(n) .. ' ambush nodes (want 2-3)')
        for _, a in ipairs(r.ambush) do
            assert(type(a.id) == 'string' and a.id ~= '', id .. ' ambush id')
            assert(type(a.x) == 'number' and type(a.y) == 'number' and type(a.z) == 'number', a.id .. ' coords')
            assert(type(a.label) == 'string' and a.label ~= '', a.id .. ' label')
            assert(a.verified == false, a.id .. ' verified')
            assert(a.radius == nil and a.heading == nil, a.id .. ' must not carry radius/heading')
        end
    end
end)

case('ambush ids are globally unique and follow <region>_amb_N', function()
    local seen = {}
    for id, r in pairs(regions.regions) do
        for i, a in ipairs(r.ambush) do
            assert(not seen[a.id], a.id .. ' duplicate id')
            seen[a.id] = true
            assert(a.id == id .. '_amb_' .. tostring(i), a.id .. ' expected ' .. id .. '_amb_' .. tostring(i))
        end
    end
end)

case('ambush labels are unique across all regions', function()
    local seen = {}
    for _, r in pairs(regions.regions) do
        for _, a in ipairs(r.ambush) do
            assert(not seen[a.label], a.label .. ' duplicated label (from ' .. a.id .. ')')
            seen[a.label] = true
        end
    end
end)

case('every ambush node is >=200 m from every claim, town center and town lot', function()
    for _, r in pairs(regions.regions) do
        for _, a in ipairs(r.ambush) do
            for cid, p in pairs(claims) do
                local d = dist2d(a, p.center)
                assert(d >= 200.0, a.id .. ' is ' .. tostring(d) .. ' m from claim ' .. cid)
            end
            for _, rr in pairs(regions.regions) do
                for _, town in ipairs(rr.towns or {}) do
                    local d = dist2d(a, town)
                    assert(d >= 200.0, a.id .. ' is ' .. tostring(d) .. ' m from town ' .. tostring(town.id))
                end
            end
            for lid, p in pairs(lots) do
                local d = dist2d(a, p.center)
                assert(d >= 200.0, a.id .. ' is ' .. tostring(d) .. ' m from town lot ' .. lid)
            end
        end
    end
end)

case('no ambush node sits inside any territory radius (enabled or not)', function()
    for _, r in pairs(regions.regions) do
        for _, a in ipairs(r.ambush) do
            for tid, t in pairs(regions.territories) do
                local d = dist2d(a, t.center)
                assert(d >= t.radius, a.id .. ' sits inside territory ' .. tid)
            end
        end
    end
end)

-- /where (fh_ui places.lua gather) never lists ambush nodes: they are not places, so no source feeds them in.
local placesModule = dofile(fh .. 'fh_ui/shared/places.lua')
case('/where gather does not list ambush nodes (they are not places)', function()
    assert(next(ambushIds) ~= nil, 'expected ambush data present')
    local gathered = placesModule.gather({ homestead = homestead, zones = zones }, { isEnabled = regions.isEnabled })
    for _, p in ipairs(gathered) do
        assert(ambushIds[p.id] == nil, p.id .. ' ambush node leaked into /where')
        assert(p.kind ~= 'ambush', p.id .. ' unexpected ambush kind')
    end
end)

T.finish()

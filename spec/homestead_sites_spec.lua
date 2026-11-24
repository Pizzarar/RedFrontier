-- Run from repo root: `lua spec/homestead_sites_spec.lua` (or via tools/run-specs.py).
-- world-01 block B: fh_homestead plots are real, spaced countryside sites. Pure data checks against the live
-- config (fh_homestead/config.lua) and the region registry (fh_core/shared/regions.lua).
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local case = T.it
local fh = here .. '../server/resources/[fh]/'

dofile(fh .. 'fh_homestead/config.lua')
local cfg = assert(_G.FhHomesteadConfig, 'config defines FhHomesteadConfig')
local regions = require('regions')

local LEGACY = { 'heartlands_01', 'heartlands_02', 'heartlands_03', 'heartlands_04',
    'scarlett_meadows_01', 'scarlett_meadows_02', 'scarlett_meadows_03', 'scarlett_meadows_04' }

local function dist2d(a, b)
    local dx, dy = a.x - b.x, a.y - b.y
    return math.sqrt(dx * dx + dy * dy)
end

case('the legacy DB-key plot ids all still exist', function()
    for _, id in ipairs(LEGACY) do
        assert(cfg.plots[id] ~= nil, id .. ' missing')
        assert(cfg.plots[id].id == id, id .. ' id field mismatch')
    end
end)

case('every plot is in a known region (enabled or disabled) and has a name + class', function()
    for id, p in pairs(cfg.plots) do
        assert(p.id == id, id .. ' id field mismatch')
        assert(regions.isKnownRegion(p.region), id .. ' unknown region ' .. tostring(p.region))
        assert(type(p.name) == 'string' and p.name ~= '', id .. ' missing name')
        assert(p.class == 'claim' or p.class == 'town_lot', id .. ' bad class ' .. tostring(p.class))
    end
end)

case('every claim is >=150 m (2D) from every town center and every other claim', function()
    local claims = {}
    for id, p in pairs(cfg.plots) do
        if p.class == 'claim' then claims[id] = p end
    end
    assert(next(claims) ~= nil, 'no claims found')
    for id, p in pairs(claims) do
        for _, r in pairs(regions.regions) do
            for _, town in ipairs(r.towns or {}) do
                local d = dist2d(p.center, town)
                assert(d >= 150.0, id .. ' is ' .. tostring(d) .. ' m from town ' .. tostring(town.id))
            end
        end
        for otherId, q in pairs(claims) do
            if otherId ~= id then
                local d = dist2d(p.center, q.center)
                assert(d >= 150.0, id .. ' is ' .. tostring(d) .. ' m from claim ' .. otherId)
            end
        end
    end
end)

case('town lots are claimable (buyable, homestead H10) and radius 12-15', function()
    local lotsByRegion = {}
    for id, p in pairs(cfg.plots) do
        if p.class == 'town_lot' then
            lotsByRegion[p.region] = (lotsByRegion[p.region] or 0) + 1
            assert(p.claimable == true, id .. ' town lot must be claimable=true (H10)')
            assert(type(p.radius) == 'number' and p.radius >= 12.0 and p.radius <= 15.0,
                id .. ' town lot radius out of 12-15: ' .. tostring(p.radius))
        end
    end
    for id, r in pairs(regions.regions) do
        if #r.towns >= 1 then
            local n = lotsByRegion[id] or 0
            assert(n >= 1, id .. ' has ' .. tostring(n) .. ' town lots (want >=1)')
        end
    end
end)

case('each region has >=3 claims', function()
    local counts = {}
    for id, p in pairs(cfg.plots) do
        if p.class == 'claim' then counts[p.region] = (counts[p.region] or 0) + 1 end
    end
    for id, r in pairs(regions.regions) do
        local n = counts[id] or 0
        assert(n >= 3, id .. ' has ' .. tostring(n) .. ' claims (want >=3)')
    end
end)

case('claims are claimable (no claimable=false)', function()
    for id, p in pairs(cfg.plots) do
        if p.class == 'claim' then assert(p.claimable ~= false, id .. ' claim must be claimable') end
    end
end)

case('H10 every town lot has a whole positive price (own or townLot.price), a known region, no overlap', function()
    local n = 0
    for id, p in pairs(cfg.plots) do
        if p.class == 'town_lot' then
            n = n + 1
            local price = math.tointeger(p.price or (cfg.townLot and cfg.townLot.price))
            assert(price and price > 0, id .. ' price')
            assert(type(p.region) == 'string' and regions.regions[p.region], id .. ' region')
            for oid, o in pairs(cfg.plots) do
                if oid ~= id then
                    local d = math.sqrt((p.center.x - o.center.x) ^ 2 + (p.center.y - o.center.y) ^ 2 + (p.center.z - o.center.z) ^ 2)
                    assert(d > p.radius + o.radius, id .. ' overlaps ' .. oid)
                end
            end
        end
    end
    T.eq(18, n)
end)

T.finish()

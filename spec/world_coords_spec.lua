-- world-02 (block F, idea-809): no camp or trade-post coordinate is defined in two places.
-- fh_zones camps and fh_trade posts keep only gameplay fields; center/region (camps) and region/x/y/z (posts)
-- resolve from FhRegions at load via FhPlaceResolver. This spec:
--   1. loads the configs WITHOUT the resolver and asserts the sources hardcode no center/region/x/y/z,
--   2. loads them WITH the resolver and asserts every camp territory + post id resolves in FhRegions,
--   3. asserts the resolved values equal the world-01 snapshots (14 camps + 4 posts).
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local case = T.it
local fh = here .. '../server/resources/[fh]/'

-- Sets _G.FhRegions + _G.FhPlaceResolver + vector3 (world-02 block F); returns the FhRegions module.
local Regions = dofile(here .. 'support/world_config.lua')

local function vec3(x, y, z) return { x = x, y = y, z = z } end
local function count(t) local n = 0 for _ in pairs(t or {}) do n = n + 1 end return n end

-- Pre-collapse values (world-01 block C snapshots).
local CAMPS = {
    heartlands_t1_01        = { center = { -145, 845, 117 },    region = 'heartlands' },
    scarlett_meadows_t1_01  = { center = { 850, -1050, 75 },    region = 'scarlett_meadows' },
    heartlands_t1_02        = { center = { 850, 850, 100 },     region = 'heartlands' },
    heartlands_t1_03        = { center = { -900, 500, 105 },    region = 'heartlands' },
    heartlands_t2_01        = { center = { 600, 200, 90 },      region = 'heartlands' },
    scarlett_meadows_t1_02  = { center = { 1500, -1650, 70 },   region = 'scarlett_meadows' },
    scarlett_meadows_t2_01  = { center = { 1700, -1750, 65 },   region = 'scarlett_meadows' },
    bayou_nwa_t1_01         = { center = { 2050, -1500, 25 },   region = 'bayou_nwa' },
    bayou_nwa_t1_02         = { center = { 2400, -950, 25 },    region = 'bayou_nwa' },
    bayou_nwa_t1_03         = { center = { 2200, -1650, 25 },   region = 'bayou_nwa' },
    bayou_nwa_t2_01         = { center = { 2550, -1750, 20 },   region = 'bayou_nwa' },
    great_plains_t1_01      = { center = { -1600, -1350, 40 },  region = 'great_plains' },
    great_plains_t1_02      = { center = { -1050, -900, 45 },   region = 'great_plains' },
    great_plains_t2_01      = { center = { -700, -1600, 40 },   region = 'great_plains' },
}

local POSTS = {
    valentine_post = { xyz = { -176, 630, 114 }, region = 'heartlands' },
    rhodes_post = { xyz = { 1288, -1278, 77 }, region = 'scarlett_meadows' },
    saint_denis_post = { xyz = { 2700, -1430, 45 }, region = 'bayou_nwa' },
    blackwater_post = { xyz = { -865, -1350, 44 }, region = 'great_plains' },
}

-- Raw source load: the resolver globals are absent, so config.lua does NOT resolve at load.
local function rawEnv()
    return setmetatable({ FhRegions = false, FhPlaceResolver = false, vector3 = vec3, vector4 = vec3 }, { __index = _G })
end
local zraw = rawEnv(); assert(loadfile(fh .. 'fh_zones/config.lua', 't', zraw))()
local traw = rawEnv(); assert(loadfile(fh .. 'fh_trade/config.lua', 't', traw))()

-- Resolved load: _G.FhRegions/_G.FhPlaceResolver are set (via the helper), so config.lua resolves at load.
local zres = setmetatable({ vector3 = vec3 }, { __index = _G }); assert(loadfile(fh .. 'fh_zones/config.lua', 't', zres))()
local tres = setmetatable({}, { __index = _G }); assert(loadfile(fh .. 'fh_trade/config.lua', 't', tres))()

case('source: fh_zones camps hardcode no center/region (single source is FhRegions)', function()
    for id, c in pairs(zraw.FhZonesConfig.camps) do
        assert(c.center == nil, id .. ' hardcodes center')
        assert(c.region == nil, id .. ' hardcodes region')
    end
end)

case('source: fh_trade posts hardcode no region/x/y/z', function()
    for _, p in ipairs(traw.FhTradeConfig.posts) do
        assert(p.region == nil and p.x == nil and p.y == nil and p.z == nil, p.id .. ' hardcodes region/x/y/z')
    end
end)

case('resolved: 14 camps match the world-01 snapshot; every territory resolves in FhRegions', function()
    assert(count(zres.FhZonesConfig.camps) == 14, 'camp count ' .. count(zres.FhZonesConfig.camps))
    assert(count(CAMPS) == 14)
    for id, snap in pairs(CAMPS) do
        local c = zres.FhZonesConfig.camps[id]
        assert(c, id .. ' missing from resolved camps')
        assert(c.center and c.center.x == snap.center[1] and c.center.y == snap.center[2] and c.center.z == snap.center[3],
            id .. ' center ' .. tostring(c.center and c.center.x))
        assert(c.region == snap.region, id .. ' region ' .. tostring(c.region))
        local terr = Regions.territories[c.territory]
        assert(terr, id .. ' territory ' .. tostring(c.territory) .. ' not in FhRegions')
        assert(terr.region == c.region, id .. ' territory region mismatch')
    end
end)

case('resolved: 4 posts match the world-01 snapshot; every post id resolves in FhRegions.posts', function()
    assert(#tres.FhTradeConfig.posts == 4, 'post count ' .. #tres.FhTradeConfig.posts)
    local byId = {}
    for _, p in ipairs(tres.FhTradeConfig.posts) do byId[p.id] = p end
    for id, snap in pairs(POSTS) do
        local p = byId[id]
        assert(p, id .. ' missing from resolved posts')
        assert(p.x == snap.xyz[1] and p.y == snap.xyz[2] and p.z == snap.xyz[3], id .. ' xyz')
        assert(p.region == snap.region, id .. ' region ' .. tostring(p.region))
        local rp = Regions.posts[id]
        assert(rp, id .. ' not in FhRegions.posts')
        assert(rp.region == p.region, id .. ' FhRegions.posts region mismatch')
    end
end)

T.finish()

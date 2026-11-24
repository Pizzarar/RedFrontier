-- world-02 (block F, idea-809): no camp or trade-post coordinate is defined in two places.
-- fh_zones camps and fh_trade posts keep only gameplay fields; center/region (camps) and region/x/y/z (posts)
-- resolve from FhRegions at load via FhPlaceResolver. This spec:
--   1. loads the configs WITHOUT the resolver and asserts the sources hardcode no center/region/x/y/z,
--   2. loads them WITH the resolver and asserts every camp territory + post id resolves in FhRegions,
--   3. asserts the resolved values equal the FhRegions single source (territory center/region, post x/y/z).
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local case = T.it
local fh = here .. '../server/resources/[fh]/'

-- Sets _G.FhRegions + _G.FhPlaceResolver + vector3 (world-02 block F); returns the FhRegions module.
local Regions = dofile(here .. 'support/world_config.lua')

local function vec3(x, y, z) return { x = x, y = y, z = z } end
local function count(t) local n = 0 for _ in pairs(t or {}) do n = n + 1 end return n end

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

case('resolved: every camp resolves center/region from its FhRegions territory (single source)', function()
    assert(count(zres.FhZonesConfig.camps) > 0, 'no camps resolved')
    for id, c in pairs(zres.FhZonesConfig.camps) do
        local terr = Regions.territories[c.territory]
        assert(terr, id .. ' territory ' .. tostring(c.territory) .. ' not in FhRegions')
        assert(c.center and c.center.x == terr.center.x and c.center.y == terr.center.y and c.center.z == terr.center.z,
            id .. ' center ' .. tostring(c.center and c.center.x))
        assert(c.region == terr.region, id .. ' region ' .. tostring(c.region))
    end
end)

case('resolved: every post resolves region/x/y/z from FhRegions.posts (single source)', function()
    assert(#tres.FhTradeConfig.posts > 0, 'no posts resolved')
    for _, p in ipairs(tres.FhTradeConfig.posts) do
        local rp = Regions.posts[p.id]
        assert(rp, p.id .. ' not in FhRegions.posts')
        assert(p.x == rp.x and p.y == rp.y and p.z == rp.z, p.id .. ' xyz')
        assert(p.region == rp.region, p.id .. ' region ' .. tostring(p.region))
    end
end)

T.finish()

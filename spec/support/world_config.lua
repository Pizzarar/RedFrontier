-- Loads FhRegions + FhPlaceResolver and exposes them as the GLOBALS that fh_zones/config.lua and
-- fh_trade/config.lua resolve against at load (world-02 block F). dofile this BEFORE dofile'ing either
-- config, so the shared configs fill camp center/region and post region/x/y/z the same way the fxmanifests do.
-- Requires fh_prelude (package.path -> fh_core/shared) to have been dofile'd first.
local Regions = require('regions')
_G.FhRegions = Regions
_G.FhPlaceResolver = require('place_resolver')

-- The shared configs and the resolver use vector3 (a CfxLua global); a table stand-in is enough for pure checks.
vector3 = vector3 or function(x, y, z) return { x = x, y = y, z = z } end
vector4 = vector4 or function(x, y, z, w) return { x = x, y = y, z = z, w = w } end

return Regions

-- Pure homestead garden rules (homestead-04 H18): crop lookup, seed->crop mapping, growth timer, harvest yield.
-- No natives, no DB; specced under Lua (spec/garden_spec.lua). Server commands and persistence live in H19.
local M = {}

M.DEFAULT_BEDS = 3
M.DEFAULT_GROWTH_SECONDS = 7200 -- 2 real hours
M.DEFAULT_YIELD = 3

local function finite(n) return type(n) == 'number' and n == n and n > -math.huge and n < math.huge end
local function nonNeg(n) return finite(n) and n >= 0 end
local function posWhole(n) return finite(n) and n >= 1 and math.floor(n) == n end

local function gardenConfig(cfg)
    if type(cfg) == 'table' then
        if type(cfg.garden) == 'table' then return cfg.garden end
        return cfg
    end
    if type(_G.FhHomesteadConfig) == 'table' and type(_G.FhHomesteadConfig.garden) == 'table' then
        return _G.FhHomesteadConfig.garden
    end
    return {}
end

local function defaultGrowth(g)
    return nonNeg(g.growthSeconds) and g.growthSeconds or M.DEFAULT_GROWTH_SECONDS
end

local function defaultYield(g)
    return posWhole(g.yield) and g.yield or M.DEFAULT_YIELD
end

local function normalizeCrop(seed, entry, g)
    if type(seed) ~= 'string' or seed == '' or type(entry) ~= 'table' then return nil end
    if type(entry.item) ~= 'string' or entry.item == '' then return nil end
    local growth = nonNeg(entry.growthSeconds) and entry.growthSeconds or defaultGrowth(g)
    local yieldCount = posWhole(entry.yield) and entry.yield or defaultYield(g)
    return {
        seed = seed,
        item = entry.item,
        growthSeconds = growth,
        yield = yieldCount,
    }
end

---Configured number of garden beds per tier-1 garden slot.
function M.beds(cfg)
    local g = gardenConfig(cfg)
    return posWhole(g.beds) and g.beds or M.DEFAULT_BEDS
end

---Look up a crop definition by seed item name (e.g. 'seedcarrot').
---Refuses unknown/invalid seeds with nil, 'fh_unknown_seed'.
---@return table|nil def { seed, item, growthSeconds, yield }, string|nil err
function M.cropForSeed(seed, cfg)
    if type(seed) ~= 'string' or seed == '' then return nil, 'fh_unknown_seed' end
    local g = gardenConfig(cfg)
    local crops = type(g.crops) == 'table' and g.crops or nil
    local def = crops and normalizeCrop(seed, crops[seed], g) or nil
    if not def then return nil, 'fh_unknown_seed' end
    return def
end

---Map a seed item name to its harvested veg item name (e.g. 'seedcarrot' -> 'carrot').
---Refuses unknown/invalid seeds with nil, 'fh_unknown_seed'.
---@return string|nil item, string|nil err
function M.seedToCrop(seed, cfg)
    local def, err = M.cropForSeed(seed, cfg)
    if not def then return nil, err end
    return def.item
end

---Look up a crop definition by seed name ('seedcarrot'), harvested veg item name ('carrot'), or a crop def table.
---Refuses unknown/invalid inputs with nil, 'fh_unknown_seed'.
---@return table|nil def, string|nil err
function M.crop(cropOrSeed, cfg)
    local g = gardenConfig(cfg)
    if type(cropOrSeed) == 'table' then
        if type(cropOrSeed.seed) == 'string' and cropOrSeed.seed ~= '' then
            local bySeed = M.cropForSeed(cropOrSeed.seed, g)
            if bySeed then return bySeed end
        end
        return nil, 'fh_unknown_seed'
    end
    if type(cropOrSeed) ~= 'string' or cropOrSeed == '' then return nil, 'fh_unknown_seed' end
    local bySeed = M.cropForSeed(cropOrSeed, g)
    if bySeed then return bySeed end
    local crops = type(g.crops) == 'table' and g.crops or nil
    if not crops then return nil, 'fh_unknown_seed' end
    local seeds = {}
    for k in pairs(crops) do if type(k) == 'string' then seeds[#seeds + 1] = k end end
    table.sort(seeds)
    for _, s in ipairs(seeds) do
        local def = normalizeCrop(s, crops[s], g)
        if def and def.item == cropOrSeed then return def end
    end
    return nil, 'fh_unknown_seed'
end

---Growth duration in seconds for a crop (by seed or veg item name), or nil, 'fh_unknown_seed'.
function M.growthSeconds(crop, cfg)
    local def, err = M.crop(crop, cfg)
    if not def then return nil, err end
    return def.growthSeconds
end

---True when a bed planted at `plantedAt` (unix seconds) is ready to harvest at `now`.
---Returns false for nil, non-numeric, NaN, infinite, negative timestamps, or unknown crops.
function M.ready(plantedAt, now, crop, cfg)
    if not nonNeg(plantedAt) or not nonNeg(now) then return false end
    local g = gardenConfig(cfg)
    local growth
    if crop == nil then
        growth = defaultGrowth(g)
    else
        local def = M.crop(crop, g)
        if not def then return false end
        growth = def.growthSeconds
    end
    return (now - plantedAt) >= growth
end

---Remaining seconds until a planted bed is ready (0 when ready), or nil on bad inputs / unknown crop.
function M.remaining(plantedAt, now, crop, cfg)
    if not nonNeg(plantedAt) or not nonNeg(now) then return nil end
    local g = gardenConfig(cfg)
    local growth
    if crop == nil then
        growth = defaultGrowth(g)
    else
        local def = M.crop(crop, g)
        if not def then return nil end
        growth = def.growthSeconds
    end
    local rem = growth - (now - plantedAt)
    return rem > 0 and rem or 0
end

---Harvest yield count for a crop (by seed or veg item name) from config, or nil, 'fh_unknown_seed'.
function M.yield(crop, cfg)
    local def, err = M.crop(crop, cfg)
    if not def then return nil, err end
    return def.yield
end

if _G.GetCurrentResourceName then _G.FhGarden = M end
return M

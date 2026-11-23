-- fh_hunting pelt quality (spec L8). Pure Lua, no natives: resolve() turns a skin report into 1-3 stars,
-- plausibility() decides whether the server should believe the report at all.
-- Both sources ('roll' and 'native', Config.PeltQualitySource) end in the same resolve() result.
local M = {}

local function finite(n) return type(n) == 'number' and n == n and n > -math.huge and n < math.huge end

local function cfgOf(c) return c or FhHuntingConfig end

---Zone for a bone: a name (any case) or a numeric id from Config.BoneZones, else Config.DefaultZone.
function M.zoneOfBone(bone, cfg)
    cfg = cfgOf(cfg)
    local key = type(bone) == 'string' and bone:lower() or bone
    return (key ~= nil and cfg.BoneZones[key]) or cfg.DefaultZone
end

---Resolve pelt quality.
---input = {
---  legendary  = bool,           -- legendary bear: always 3 stars, whatever the source says
---  source     = 'roll'|'native' -- defaults to cfg.PeltQualitySource
---  -- roll:   bone (name or id) or zone, hits (damaging hits taken), explosive (bool), rng (function() -> [0,1))
---  -- native: nativeQuality (_GET_PED_QUALITY), cleanliness (_GET_PED_DAMAGE_CLEANLINESS); either may be nil
---}
---@return boolean ok, number|string starsOrErr, table|nil detail  detail = { source, zone?, rolled? }
function M.resolve(input, cfg)
    cfg = cfgOf(cfg)
    if type(input) ~= 'table' then return false, 'fh_bad_input' end
    if input.legendary then return true, 3, { source = 'legendary' } end
    local source = input.source or cfg.PeltQualitySource
    if source == 'native' then
        local q, c
        if input.nativeQuality ~= nil then q = cfg.NativeQualityStars[input.nativeQuality] or 1 end -- ruined / unknown = worst
        if input.cleanliness ~= nil then c = cfg.NativeCleanlinessStars[input.cleanliness] or 1 end
        if not q and not c then return false, 'fh_no_native_quality' end
        return true, math.min(q or 3, c or 3), { source = 'native' }
    elseif source ~= 'roll' then
        return false, 'fh_bad_source'
    end

    local zone
    if input.explosive or (finite(input.hits) and input.hits >= cfg.MultiHitMin) then
        zone = 'gut'
    else
        zone = input.zone or M.zoneOfBone(input.bone, cfg)
    end
    local def = cfg.Zones[zone]
    if not def then return false, 'fh_bad_zone' end
    local stars, rolled = def.stars, false
    if (def.downgradeChance or 0) > 0 and stars > 1 then
        if type(input.rng) ~= 'function' then return false, 'fh_no_rng' end
        if input.rng() < def.downgradeChance then stars, rolled = stars - 1, true end
    end
    return true, stars, { source = 'roll', zone = zone, rolled = rolled }
end

---Server-side sanity check of a skin request before anything is paid or granted.
---check = { dead = bool (server-read), distance = metres skinner->carcass (server-read), claimed = bool }
---@return boolean ok, string|nil reason
function M.plausibility(check, cfg)
    cfg = cfgOf(cfg)
    if type(check) ~= 'table' then return false, 'fh_bad_check' end
    if check.claimed then return false, 'fh_already_claimed' end
    if check.dead ~= true then return false, 'fh_not_dead' end
    if not finite(check.distance) or check.distance < 0 or check.distance > cfg.SkinRange then
        return false, 'fh_too_far'
    end
    return true
end

if GetCurrentResourceName then
    FhHuntingQuality = M
else
    return M
end

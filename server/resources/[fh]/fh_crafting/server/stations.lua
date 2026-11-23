-- Station adapter (plan crafting-01 C2). Mirrors the @homestead H3 exports exactly, so C5 only swaps the body:
--   isNearStation(src, stationType, maxDist?) / getStations(citizenid) / stationAt(coords, maxDist?)
-- Real source: exports.fh_homestead when GetResourceState('fh_homestead') == 'started' and the export exists.
-- Dev fallback: FhCraftingConfig.devStations, consulted only while convar fh_dev = 1 (also when fh_homestead runs but
-- the player has no built station there). Workaround -> C5 keeps it behind fh_dev only.
FhCraftStations = {}

local cfg, flow = FhCraftingConfig, FhCraftFlow
local HOMESTEAD = 'fh_homestead'

local function devOn() return GetConvarInt('fh_dev', 0) == 1 end

local function maxDistOr(maxDist)
    return type(maxDist) == 'number' and maxDist >= 0 and maxDist or cfg.stationMaxDist
end

---Call an fh_homestead export. Returns called (false when not started / export missing / threw), result.
---The export lookup sits inside the pcall: cfx raises 'No such export' when indexing a missing export.
local function homestead(fn, ...)
    if GetResourceState(HOMESTEAD) ~= 'started' then return false end
    local ok, res = pcall(function(...) return exports[HOMESTEAD][fn](exports[HOMESTEAD], ...) end, ...)
    if not ok then
        if not tostring(res):find('No such export', 1, true) then
            print(('^1[fh_crafting] fh_homestead.%s failed: %s^7'):format(fn, tostring(res)))
        end
        return false
    end
    return true, res
end

local function pedCoords(src)
    local ped = type(src) == 'number' and GetPlayerPed(src) or 0
    if not ped or ped == 0 then return nil end
    return GetEntityCoords(ped)
end

---@param src number
---@param stationType string 'gunsmith'|'reload'|'apothecary'
---@param maxDist number|nil default FhCraftingConfig.stationMaxDist
---@return boolean ok
---@return string|nil reason 'bad_type' | 'no_station'   (H3 returns the boolean only; the reason is additive)
function FhCraftStations.isNearStation(src, stationType, maxDist)
    if type(stationType) ~= 'string' or not FhCraftRules.STATION_TYPES[stationType] then return false, 'bad_type' end
    maxDist = maxDistOr(maxDist)
    local called, near = homestead('isNearStation', src, stationType, maxDist)
    if called and near == true then return true end
    if devOn() then
        local coords = pedCoords(src)
        if coords and flow.nearestDev(cfg.devStations, coords, maxDist, stationType) then return true end
    end
    return false, 'no_station'
end

---C1 name, kept for fh_gunsmith (C3) and the isNearStation export.
FhCraftStations.isNear = FhCraftStations.isNearStation

---Built stations on the character's own plot (H3 shape). Under fh_dev, dev stations are appended with dev = true.
---@return table list
function FhCraftStations.getStations(citizenid)
    local list = {}
    local called, res = homestead('getStations', citizenid)
    if called and type(res) == 'table' then
        for _, s in ipairs(res) do list[#list + 1] = s end
    end
    if devOn() then
        for t, c in pairs(cfg.devStations or {}) do
            list[#list + 1] = { station_type = t, coords = { x = c.x, y = c.y, z = c.z }, dev = true }
        end
    end
    return list
end

---Nearest built station to coords within maxDist: { plot_id, slot_id, station_type } (H3 shape) or nil.
---Under fh_dev, falls back to the nearest dev station: { station_type, dev = true }.
function FhCraftStations.stationAt(coords, maxDist)
    maxDist = maxDistOr(maxDist)
    local called, res = homestead('stationAt', coords, maxDist)
    if called and type(res) == 'table' then return res end
    if devOn() then
        local t = flow.nearestDev(cfg.devStations, coords, maxDist)
        if t then return { station_type = t, dev = true } end
    end
    return nil
end

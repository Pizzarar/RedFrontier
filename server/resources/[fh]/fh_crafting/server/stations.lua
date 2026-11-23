-- Station adapter (plan crafting-01 C2). Mirrors the @homestead H3 exports exactly, so C5 only swaps the body:
--   isNearStation(src, stationType, maxDist?) / getStations(citizenid) / stationAt(coords, maxDist?)
-- Real source (C5b): exports.fh_homestead (H3) when GetResourceState('fh_homestead') == 'started' and the export exists.
-- Crafting types are mapped to homestead types (FhCraftingConfig.stationTypeMap) before every H3 call. Before the
-- homestead slot load finishes H3 returns {} / nil / false / 'fh_not_ready': all of those mean "no station".
-- Dev fallback: FhCraftingConfig.devStations, consulted ONLY while convar fh_dev = 1. With fh_homestead missing and
-- fh_dev off, isNearStation refuses 'no_homestead' (an H3 export that throws: 'homestead_error', logged).
FhCraftStations = {}

local cfg, flow = FhCraftingConfig, FhCraftFlow
local HOMESTEAD = 'fh_homestead'

---Build the adapter around injectable env (specs pass fakes; the default env wraps the cfx natives).
---env: resourceState(name) -> string, callExport(resource, fn, ...) -> any (may throw), devOn() -> boolean,
---     pedCoords(src) -> coords|nil, log(msg)
local function build(env)
    local A = {}

    local function maxDistOr(maxDist)
        return type(maxDist) == 'number' and maxDist >= 0 and maxDist or cfg.stationMaxDist
    end

    ---Call an fh_homestead export (H3). Returns called, result, why. why = 'no_homestead' (not started / export
    ---missing) or 'homestead_error' (the export threw; logged). The lookup sits inside the pcall: cfx raises
    ---'No such export' when indexing a missing export.
    local function homestead(fn, ...)
        if env.resourceState(HOMESTEAD) ~= 'started' then return false, nil, 'no_homestead' end
        local args = table.pack(...)
        local ok, res = pcall(function() return env.callExport(HOMESTEAD, fn, table.unpack(args, 1, args.n)) end)
        if not ok then
            if tostring(res):find('No such export', 1, true) then return false, nil, 'no_homestead' end
            env.log(('[fh_crafting] fh_homestead.%s failed: %s'):format(fn, tostring(res)))
            return false, nil, 'homestead_error'
        end
        return true, res
    end

    ---@param src number
    ---@param stationType string 'gunsmith'|'reload'|'apothecary'
    ---@param maxDist number|nil default FhCraftingConfig.stationMaxDist, passed to H3
    ---@return boolean ok
    ---@return string|nil reason 'bad_type' | 'no_station' | 'no_homestead' | 'homestead_error'
    function A.isNearStation(src, stationType, maxDist)
        if type(stationType) ~= 'string' or not FhCraftRules.STATION_TYPES[stationType] then return false, 'bad_type' end
        maxDist = maxDistOr(maxDist)
        local h3Type = cfg.stationTypeMap and cfg.stationTypeMap[stationType] or stationType
        local called, near, why = homestead('isNearStation', src, h3Type, maxDist)
        if called and near == true then return true end
        if env.devOn() then -- fh_dev only: dev stations
            local coords = env.pedCoords(src)
            if coords and flow.nearestDev(cfg.devStations, coords, maxDist, stationType) then return true end
        end
        if not called then return false, why end
        return false, 'no_station'
    end
    A.isNear = A.isNearStation

    ---Built stations on the character's own plot (H3 shape). Under fh_dev, dev stations are appended (dev = true).
    ---@return table list
    function A.getStations(citizenid)
        local list = {}
        local called, res = homestead('getStations', citizenid)
        if called and type(res) == 'table' then
            for _, s in ipairs(res) do list[#list + 1] = s end
        end
        if env.devOn() then
            for t, c in pairs(cfg.devStations or {}) do
                list[#list + 1] = { station_type = t, coords = { x = c.x, y = c.y, z = c.z }, dev = true }
            end
        end
        return list
    end

    ---Nearest built station within maxDist: { plot_id, slot_id, station_type } (H3 shape) or nil.
    ---Under fh_dev, falls back to the nearest dev station: { station_type, dev = true }.
    function A.stationAt(coords, maxDist)
        maxDist = maxDistOr(maxDist)
        local called, res = homestead('stationAt', coords, maxDist)
        -- {} (not ready) is not a station: a real hit always carries station_type.
        if called and type(res) == 'table' and res.station_type ~= nil then return res end
        if env.devOn() then
            local t = flow.nearestDev(cfg.devStations, coords, maxDist)
            if t then return { station_type = t, dev = true } end
        end
        return nil
    end

    return A
end

FhCraftStations = build({
    resourceState = function(n) return GetResourceState(n) end,
    callExport = function(res, fn, ...) return exports[res][fn](exports[res], ...) end,
    devOn = function() return GetConvarInt('fh_dev', 0) == 1 end,
    pedCoords = function(src)
        local ped = type(src) == 'number' and GetPlayerPed(src) or 0
        if not ped or ped == 0 then return nil end
        return GetEntityCoords(ped)
    end,
    log = function(m) print('^1' .. m .. '^7') end,
})
FhCraftStations.new = build

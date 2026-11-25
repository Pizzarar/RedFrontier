-- Pure station selection/geometry (H3). No natives; specced under lupa. Coords are {x,y,z} tables or vectors.
-- A station is a slot with kind='station' built to tier>=1. Its world position = plot.center + slot prop offset.
-- Use policy (documented decision): stations are OWNER-ONLY. isNearStation only counts stations on the plot the
-- asking character owns. Opening it to non-owners later means passing a different plot filter, not a rewrite.
local M = {}

local function finite(n) return type(n) == 'number' and n == n and n > -math.huge and n < math.huge end

local function validCoords(c)
    local ok, x, y, z = pcall(function() return c.x, c.y, c.z end)
    return ok and finite(x) and finite(y) and finite(z)
end

M.DEFAULT_MAX_DIST = 3.0
-- Built station props are ground-snapped client-side (fh_homestead/client/main.lua), while s.coords holds the config z-hint.
-- Match fh_core FhConfig.Access.SnapToleranceAbove / SnapToleranceBelow (20.0 m).
M.SNAP_ABOVE = 20.0
M.SNAP_BELOW = 20.0

local function snappedDist(stationCoords, playerCoords)
    if not validCoords(stationCoords) or not validCoords(playerCoords) then return nil end
    local dzPlayer = playerCoords.z - stationCoords.z
    if dzPlayer > M.SNAP_ABOVE or dzPlayer < -M.SNAP_BELOW then return nil end
    local dx, dy = playerCoords.x - stationCoords.x, playerCoords.y - stationCoords.y
    return math.sqrt(dx * dx + dy * dy)
end

---World coords of a slot: plot center + prop offset (verified prop when verifiedProps and present).
function M.slotCoords(plot, slot, verifiedProps)
    if type(plot) ~= 'table' or type(slot) ~= 'table' or not validCoords(plot.center) then return nil end
    local prop = (verifiedProps and slot.propVerified) or slot.prop
    local o = type(prop) == 'table' and prop.offset or nil
    if o ~= nil and not validCoords(o) then return nil end
    o = o or { x = 0, y = 0, z = 0 }
    return { x = plot.center.x + o.x, y = plot.center.y + o.y, z = plot.center.z + o.z }
end

---Built stations of one plot. tiers = { [slotId] = tier }. Sorted by slot id.
---@return table[] { plot_id, slot_id, station_type, coords }
function M.builtStations(plot, tiers, verifiedProps)
    local out = {}
    if type(plot) ~= 'table' or type(plot.slots) ~= 'table' then return out end
    tiers = type(tiers) == 'table' and tiers or {}
    local ids = {}
    for id in pairs(plot.slots) do ids[#ids + 1] = id end
    table.sort(ids)
    for _, id in ipairs(ids) do
        local slot = plot.slots[id]
        local tier = tonumber(tiers[id]) or 0
        if type(slot) == 'table' and slot.kind == 'station' and type(slot.stationType) == 'string' and tier >= 1 then
            local c = M.slotCoords(plot, slot, verifiedProps)
            if c then out[#out + 1] = { plot_id = plot.id, slot_id = id, station_type = slot.stationType, coords = c } end
        end
    end
    return out
end

---All built stations over plots. tiersByPlot = { [plotId] = tiers }. onlyPlot (optional) restricts to one plot id.
function M.allStations(plots, tiersByPlot, verifiedProps, onlyPlot)
    local out, ids = {}, {}
    for id in pairs(plots or {}) do if onlyPlot == nil or onlyPlot == id then ids[#ids + 1] = id end end
    table.sort(ids)
    tiersByPlot = tiersByPlot or {}
    for _, id in ipairs(ids) do
        for _, s in ipairs(M.builtStations(plots[id], tiersByPlot[id], verifiedProps)) do out[#out + 1] = s end
    end
    return out
end

---Nearest station in list within maxDist (inclusive) of coords, optionally of one station_type. Ties: first in list.
---@return table|nil station, number|nil dist
function M.nearest(stations, coords, maxDist, stationType)
    if type(stations) ~= 'table' or not validCoords(coords) then return nil end
    maxDist = finite(maxDist) and maxDist or M.DEFAULT_MAX_DIST
    local best, bestD
    for _, s in ipairs(stations) do
        if stationType == nil or s.station_type == stationType then
            local d = snappedDist(s.coords, coords)
            if d and d <= maxDist and (bestD == nil or d < bestD) then best, bestD = s, d end
        end
    end
    return best, bestD
end

---True when a station slot goes from tier 0 to >=1 (decides station_built).
function M.isStationBuilt(slot, oldTier, newTier)
    return type(slot) == 'table' and slot.kind == 'station' and (tonumber(oldTier) or 0) < 1 and (tonumber(newTier) or 0) >= 1
end

if GetCurrentResourceName then
    FhStations = M
else
    return M
end

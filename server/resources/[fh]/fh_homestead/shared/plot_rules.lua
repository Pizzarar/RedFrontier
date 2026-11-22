-- Pure plot-claim rules (spec L138-139): no natives, specced under busted. Coords are tables {x,y,z} or vectors.
local M = {}

local function finite(n) return type(n) == 'number' and n == n and n > -math.huge and n < math.huge end

---@return boolean ok
function M.validCoords(c)
    -- CfxLua vector3 is not type 'table': read the fields under pcall (as fh_core containers.lua does)
    local ok, x, y, z = pcall(function() return c.x, c.y, c.z end)
    return ok and finite(x) and finite(y) and finite(z)
end

---@return number|nil dist
function M.dist(a, b)
    if not M.validCoords(a) or not M.validCoords(b) then return nil end
    local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

---True when coords are within plot.radius of plot.center (inclusive).
function M.inRadius(plot, coords)
    if type(plot) ~= 'table' or not finite(plot.radius) then return false end
    local d = M.dist(plot.center, coords)
    return d ~= nil and d <= plot.radius
end

---First configured plot containing coords, or nil. Iterates in sorted-id order so overlapping plots are deterministic.
function M.plotAt(plots, coords)
    local ids = {}
    for id in pairs(plots or {}) do ids[#ids + 1] = id end
    table.sort(ids)
    for _, id in ipairs(ids) do
        if M.inRadius(plots[id], coords) then return plots[id] end
    end
    return nil
end

---claims = { byPlot = { [plot_id] = citizenid }, byOwner = { [citizenid] = plot_id } }
---@return boolean ok, string|nil reason
function M.canClaim(plot, coords, citizenid, claims)
    if type(citizenid) ~= 'string' or citizenid == '' then return false, 'fh_no_character' end
    if type(plot) ~= 'table' then return false, 'fh_no_plot' end
    if not M.inRadius(plot, coords) then return false, 'fh_not_in_plot' end
    claims = claims or {}
    if claims.byPlot and claims.byPlot[plot.id] then return false, 'fh_plot_taken' end
    if claims.byOwner and claims.byOwner[citizenid] then return false, 'fh_already_has_plot' end
    return true
end

---Owner or admin may release; the plot must be claimed.
---@return boolean ok, string|nil reason
function M.canUnclaim(plotId, citizenid, isAdmin, claims)
    local owner = claims and claims.byPlot and claims.byPlot[plotId]
    if not owner then return false, 'fh_plot_free' end
    if isAdmin or (type(citizenid) == 'string' and owner == citizenid) then return true end
    return false, 'fh_not_owner'
end

---Only the plot owner may open its chest.
function M.canOpenChest(plotId, citizenid, claims)
    local owner = claims and claims.byPlot and claims.byPlot[plotId]
    if not owner then return false, 'fh_plot_free' end
    if owner ~= citizenid then return false, 'fh_not_owner' end
    return true
end

function M.chestStashId(plotId, n) return ('fh:chest:%s:%d'):format(plotId, n or 1) end

if GetCurrentResourceName then
    FhPlotRules = M
else
    return M
end

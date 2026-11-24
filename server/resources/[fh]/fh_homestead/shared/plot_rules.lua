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

---Plot class (fh_plots.class): 'claim' (homestead claim) or 'town_lot'. A plot with no class is a claim.
function M.classOf(plot)
    local c = type(plot) == 'table' and plot.class or nil
    if type(c) ~= 'string' or c == '' then return 'claim' end
    return c
end

---Refusal reason when a character already holds a plot of this class.
local function alreadyHasReason(class)
    if class == 'town_lot' then return 'fh_already_has_lot' end
    return 'fh_already_has_plot'
end

---True when citizenid already holds a plot of `class`. byOwner is per class ({ [class] = { [citizenid] = plot_id } });
---the old flat shape ({ [citizenid] = plot_id }, pre-class server) is still read, and every entry in it is a claim.
local function ownsInClass(byOwner, class, citizenid)
    if type(byOwner) ~= 'table' then return false end
    local bucket = byOwner[class]
    if type(bucket) == 'table' and bucket[citizenid] ~= nil then return true end
    if class == 'claim' then
        local flat = byOwner[citizenid]
        if flat ~= nil and type(flat) ~= 'table' then return true end
    end
    return false
end

---claims = { byPlot = { [plot_id] = citizenid }, byOwner = { [class] = { [citizenid] = plot_id } } }
---(byOwner may also be the old flat { [citizenid] = plot_id }, read as class 'claim').
---One plot per character per class: a character may hold one claim and one town lot.
---isEnabled (optional, world-02 G1): fn(region_id) -> boolean. When a plot carries a region and this (or the FhRegions
---global) reports it disabled, the claim is refused 'fh_region_disabled'. A nil/empty region (legacy plot) or no gate
---available (no arg and no FhRegions) keeps today's behaviour: allowed.
---@return boolean ok, string|nil reason
function M.canClaim(plot, coords, citizenid, claims, isEnabled)
    if type(citizenid) ~= 'string' or citizenid == '' then return false, 'fh_no_character' end
    if type(plot) ~= 'table' then return false, 'fh_no_plot' end
    if plot.claimable == false then return false, 'fh_not_claimable' end
    if not M.inRadius(plot, coords) then return false, 'fh_not_in_plot' end
    if type(plot.region) == 'string' and plot.region ~= '' then
        local gate = isEnabled
        if type(gate) ~= 'function' then
            gate = (type(FhRegions) == 'table' and type(FhRegions.isEnabled) == 'function') and FhRegions.isEnabled or nil
        end
        if gate and gate(plot.region) == false then return false, 'fh_region_disabled' end
    end
    claims = claims or {}
    if claims.byPlot and claims.byPlot[plot.id] then return false, 'fh_plot_taken' end
    local class = M.classOf(plot)
    if ownsInClass(claims.byOwner, class, citizenid) then return false, alreadyHasReason(class) end
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

-- Pure homestead comfort calc (H4). No natives; specced under lupa. Needs FhBuildRules (shared/build_rules.lua) loaded first.
-- total = slot comfort (build_rules.totalComfort, numbers live in config.lua only) + trophy points.
-- Trophy points count only when the trophy_wall slot is built (tier >= 1), at most cfg.trophyMaxByWallTier[wallTier] trophies
-- (best-valued first, ties by id, so the result is deterministic), and the trophy total is capped at cfg.trophyComfortCap.
-- Homestead only reports a number; applying buffs from it is Survival's job.
local M = {}

local function rules() return FhBuildRules end

local function validPoints(p) return type(p) == 'number' and p == p and p > 0 and p < math.huge end
M.validPoints = validPoints

-- Storage limits (migration 0006): trophy_id varchar(64), points int unsigned. Checked before any item moves.
M.MAX_ID_LEN = 64
M.MAX_POINTS = 4294967295

---Validate a trophy id and its points the way they will be stored.
---@return boolean ok, string|number errOrPoints (points floored to a whole number)
function M.checkTrophy(trophyId, points)
    if type(trophyId) ~= 'string' or trophyId == '' or #trophyId > M.MAX_ID_LEN then return false, 'fh_bad_trophy' end
    if not validPoints(points) then return false, 'fh_bad_points' end
    points = math.floor(points)
    if points < 1 or points > M.MAX_POINTS then return false, 'fh_bad_points' end
    return true, points
end

---Trophy comfort alone. trophies = { [trophy_id] = points }.
function M.trophyPoints(tiers, trophies, cfg)
    cfg = cfg or {}
    local wall = (type(tiers) == 'table' and tonumber(tiers.trophy_wall)) or 0
    if wall < 1 or type(trophies) ~= 'table' then return 0 end
    local list = {}
    for id, pts in pairs(trophies) do
        if validPoints(pts) then list[#list + 1] = { id = tostring(id), pts = pts } end
    end
    table.sort(list, function(a, b) if a.pts ~= b.pts then return a.pts > b.pts end return a.id < b.id end)
    local maxN = type(cfg.trophyMaxByWallTier) == 'table' and cfg.trophyMaxByWallTier[wall] or nil
    local sum = 0
    for i, t in ipairs(list) do
        if maxN and i > maxN then break end
        sum = sum + t.pts
    end
    local cap = cfg.trophyComfortCap
    if type(cap) == 'number' and sum > cap then sum = cap end
    return sum
end

---@param plotConfig table|nil plot from FhHomesteadConfig.plots
---@param tiers table|nil { [slot_id] = tier }
---@param trophies table|nil { [trophy_id] = points }
---@param cfg table|nil FhHomesteadConfig (trophyComfortCap, trophyMaxByWallTier)
---@return number total, number slotPart, number trophyPart
function M.compute(plotConfig, tiers, trophies, cfg)
    tiers = type(tiers) == 'table' and tiers or {}
    local slotPart = (plotConfig and rules() and rules().totalComfort(plotConfig, tiers)) or 0
    local trophyPart = M.trophyPoints(tiers, trophies, cfg)
    return slotPart + trophyPart, slotPart, trophyPart
end

-- ---- placement (pure; the server injects the natives-backed deps) ----
---Item id a trophy id was made from ('trophy_deer#2' -> 'trophy_deer').
function M.itemOf(trophyId)
    if type(trophyId) ~= 'string' then return nil end
    return trophyId:match('^(.+)#%d+$') or trophyId
end

---Smallest free '<item>#<n>' id for a new placement.
function M.nextId(trophies, itemId)
    local n = 1
    while type(trophies) == 'table' and trophies[itemId .. '#' .. n] do n = n + 1 end
    return itemId .. '#' .. n
end

---Checks (cheap first), then lookup, then capacity and storage limits, and only then removeItem (the one step that
---costs the player). The caller must hold the plot's in-flight lock so the capacity check still holds after removeItem.
---ctx = { citizenid, ownerCitizenid, tiers, trophies, cfg, itemId,
---        lookup = function(itemId) -> points|nil [, err], removeItem = function(itemId) -> ok [, err] }
---@return boolean ok, string|number errOrPoints, string|nil trophyId
function M.place(ctx)
    if type(ctx) ~= 'table' or type(ctx.itemId) ~= 'string' or ctx.itemId == '' or #ctx.itemId > M.MAX_ID_LEN then
        return false, 'fh_bad_trophy'
    end
    if not ctx.citizenid then return false, 'fh_no_character' end
    if not ctx.ownerCitizenid then return false, 'fh_plot_free' end
    if ctx.citizenid ~= ctx.ownerCitizenid then return false, 'fh_not_owner' end
    local wall = (type(ctx.tiers) == 'table' and tonumber(ctx.tiers.trophy_wall)) or 0
    if wall < 1 then return false, 'fh_no_trophy_wall' end
    local points, err = ctx.lookup(ctx.itemId)
    if err then return false, err end
    if not validPoints(points) then return false, 'fh_not_a_trophy' end
    local cfg = ctx.cfg or {}
    local trophies = type(ctx.trophies) == 'table' and ctx.trophies or {}
    local count = 0
    for _, p in pairs(trophies) do if validPoints(p) then count = count + 1 end end
    local maxN = type(cfg.trophyMaxByWallTier) == 'table' and cfg.trophyMaxByWallTier[wall] or nil
    if maxN and count >= maxN then return false, 'fh_wall_full' end
    if type(cfg.trophyComfortCap) == 'number' and M.trophyPoints(ctx.tiers, trophies, cfg) >= cfg.trophyComfortCap then
        return false, 'fh_trophy_cap'
    end
    -- everything the store would refuse is refused here, before the item leaves the chest
    local trophyId = M.nextId(trophies, ctx.itemId)
    local valid, pts = M.checkTrophy(trophyId, points)
    if not valid then return false, pts end
    local ok, why = ctx.removeItem(ctx.itemId)
    if not ok then return false, why or 'fh_removeitem_failed' end
    return true, pts, trophyId
end

---Unplace checks: owner-only, trophy must be on the wall.
function M.canUnplace(ctx)
    if type(ctx) ~= 'table' or not ctx.citizenid then return false, 'fh_no_character' end
    if not ctx.ownerCitizenid then return false, 'fh_plot_free' end
    if ctx.citizenid ~= ctx.ownerCitizenid then return false, 'fh_not_owner' end
    if type(ctx.trophyId) ~= 'string' or type(ctx.trophies) ~= 'table' or not ctx.trophies[ctx.trophyId] then
        return false, 'fh_no_trophy'
    end
    return true
end

if GetCurrentResourceName then
    FhComfort = M
else
    return M
end

-- fh_alife server/homestead.lua (plan a-life-03 C2): soft, read-only link to fh_homestead for claim raids. Loaded
-- before main.lua (its boot load() reads plots). fh_homestead is NOT a manifest dependency: when it is not started
-- or an export throws, plots() returns nil and no raid can start (live raids then cancel through raid_rules.tick).
-- Plot facts come only from exports.fh_homestead:claimedPlots() + plotInfo(plotId) (C0 adds coords/region/
-- fenceBuilt); chest 1's stash id comes from fh_homestead's own FhPlotRules.chestStashId (shared include), so
-- fh_alife never copies homestead config or rules.
-- Implemented A-Life — Thanks to S.T.A.L.K.E.R. A-Life by GSC Game World.
local H = {}

local function started() return GetResourceState('fh_homestead') == 'started' end

---plotInfo(plotId) facts, or nil (homestead down, export error, unknown plot).
function H.plotInfo(plotId)
    if type(plotId) ~= 'string' or not started() then return nil end
    local ok, info = pcall(function() return exports.fh_homestead:plotInfo(plotId) end)
    if ok and type(info) == 'table' then return info end
    return nil
end

---Every claimed plot (any class) as { [plotId] = plotInfo facts }, plus the claimedPlots() count. nil, 0 when
---fh_homestead is not started or claimedPlots throws. An empty list may also mean the claim cache has not loaded yet
---(fh_homestead has no ready export); callers treat 0 claims during their boot grace as "not loaded".
---@return table|nil plots, integer claims
function H.plots()
    if not started() then return nil, 0 end
    local ok, ids = pcall(function() return exports.fh_homestead:claimedPlots() end)
    if not ok or type(ids) ~= 'table' then return nil, 0 end
    local out = {}
    for _, id in ipairs(ids) do
        local info = H.plotInfo(id)
        if info then out[id] = info end
    end
    return out, #ids
end

---Chest 1 of a plot as an fh_core container ref (fh_homestead/server/main.lua chestRef: rules.chestStashId(id, 1)).
function H.chestRef(plotId) return { type = 'chest', id = FhPlotRules.chestStashId(plotId, 1) } end

FhAlifeHomestead = H

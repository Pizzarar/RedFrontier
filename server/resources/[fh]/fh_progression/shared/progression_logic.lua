-- Rep -> tier and unlock checks (M7). Pure Lua, no FiveM globals; unit-tested.
-- cfg = { tiers = { [region_id] = { t2 = n, t3 = n } }, unlocks = { [id] = { region_id, min_tier } } }
local logic = {}

---Tier (1..3) for a rep value in a region. Unknown region or non-number value -> 1 plus a reason.
---@return integer tier, string? reason
function logic.tierForRep(cfg, region, value)
    local t = type(cfg) == 'table' and type(cfg.tiers) == 'table' and cfg.tiers[region] or nil
    if type(t) ~= 'table' then return 1, 'unknown_region' end
    if type(value) ~= 'number' or value ~= value then return 1, 'bad_value' end
    if t.t3 and value >= t.t3 then return 3 end
    if t.t2 and value >= t.t2 then return 2 end
    return 1
end

---@param repByRegion table<string, number>|nil
---@return boolean ok, string? reason
function logic.canUnlock(cfg, repByRegion, unlock_id)
    local u = type(cfg) == 'table' and type(cfg.unlocks) == 'table' and cfg.unlocks[unlock_id] or nil
    if type(u) ~= 'table' then return false, 'unknown_unlock' end
    if type(cfg.tiers) ~= 'table' or type(cfg.tiers[u.region_id]) ~= 'table' then return false, 'unknown_region' end
    local value = type(repByRegion) == 'table' and repByRegion[u.region_id] or 0
    local tier, why = logic.tierForRep(cfg, u.region_id, value)
    if why then return false, why end
    if tier < u.min_tier then return false, 'tier_too_low' end
    return true
end

if _G.GetCurrentResourceName then _G.FhProgressionLogic = logic end
return logic

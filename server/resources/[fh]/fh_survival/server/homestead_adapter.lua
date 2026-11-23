-- Homestead adapter (plan survival-01, S4). pcalls fh_homestead exports that may not exist yet (H3/H4); S4b drops
-- the fallback once they are on main. Decision logic is FhSurvivalRest.resolve (pure, spec'd).
FhSurvivalHomestead = {}

---@return { bed: boolean, comfort: number }
function FhSurvivalHomestead.info(src, citizenid)
    local nearOk, near = pcall(function() return exports.fh_homestead:isNearStation(src, 'bed') end)
    local comfortOk, comfort = false, nil
    if nearOk and near == true and citizenid then
        comfortOk, comfort = pcall(function() return exports.fh_homestead:getComfort(citizenid) end)
    end
    return FhSurvivalRest.resolve(nearOk, near, comfortOk, comfort)
end

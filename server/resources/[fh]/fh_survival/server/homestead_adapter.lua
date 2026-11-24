-- Homestead adapter (plan survival-01, S4b). Calls fh_homestead's H3 isNearStation / H4 getComfort exports
-- directly; fh_homestead is a declared dependency (fxmanifest). If fh_homestead is not started, the adapter
-- reports no bed and comfort 0 rather than blanket-pcall past a real error. Decision logic is
-- FhSurvivalRest.resolve (pure, spec'd).
FhSurvivalHomestead = {}

---@return { bed: boolean, comfort: number }
function FhSurvivalHomestead.info(src, citizenid)
    if GetResourceState('fh_homestead') ~= 'started' then
        return FhSurvivalRest.resolve(false, 0)
    end
    local near = exports.fh_homestead:isNearStation(src, 'bed')
    local comfort = 0
    if near == true and citizenid then
        comfort = exports.fh_homestead:getComfort(citizenid)
    end
    return FhSurvivalRest.resolve(near, comfort)
end

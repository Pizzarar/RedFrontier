-- Rest + comfort decisions (plan survival-01, S4). Pure Lua: no FiveM/RedM globals.
-- The homestead exports (H3 isNearStation, H4 getComfort) may be missing; the adapter passes in the raw pcall
-- results and this module decides. A missing/failed export means no bed (bedroll only) and comfort 0.
local R = {}

local function isNum(v) return type(v) == 'number' and v == v and v ~= math.huge and v ~= -math.huge end

---Interpret the two pcall results of the homestead adapter.
---@param nearOk boolean pcall status of isNearStation(src,'bed')
---@param nearVal any its return value (only `true` counts)
---@param comfortOk boolean pcall status of getComfort(citizenid)
---@param comfortVal any its return value (number >= 0, else 0)
---@return { bed: boolean, comfort: number }
function R.resolve(nearOk, nearVal, comfortOk, comfortVal)
    local bed = nearOk == true and nearVal == true
    local comfort = 0
    if bed and comfortOk == true and isNum(comfortVal) and comfortVal > 0 then comfort = comfortVal end
    return { bed = bed, comfort = comfort }
end

---Rested magnitude for a rest action. kind 'bedroll' = 1.0 anywhere; kind 'bed' needs `info.bed` and uses
---FhSurvivalNeeds.restedMagnitude (1.0 + comfort*k, capped). A 'bed' request without a bed is refused.
---@param needs table shared/needs.lua module (restedMagnitude)
---@param kind string 'bedroll' | 'bed'
---@param info table? result of R.resolve
---@return number|false magnitude, string? err
function R.magnitude(needs, kind, info, k, cap)
    if kind == 'bedroll' then return 1.0 end
    if kind == 'bed' then
        if type(info) ~= 'table' or info.bed ~= true then return false, 'no_bed' end
        return needs.restedMagnitude(info.comfort, k, cap)
    end
    return false, 'bad_kind'
end

if _G.GetCurrentResourceName then _G.FhSurvivalRest = R end
return R

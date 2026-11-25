-- Rest + comfort decisions (plan survival-01, S4). Pure Lua: no FiveM/RedM globals.
-- The homestead adapter calls fh_homestead's H3 isNearStation / H4 getComfort directly (S4b) and passes the raw
-- values in; this module decides. Not near a bed means no bed (bedroll only) and comfort 0.
local R = {}

R.DEFAULT_BED_COOLDOWN = 10

local function isNum(v) return type(v) == 'number' and v == v and v ~= math.huge and v ~= -math.huge end

---Per-player cooldown check for fh:survival:restBed. lastAt nil = never rested.
---A clock that went backwards counts as still cooling down.
---@return boolean ok, number|nil remainingSeconds
function R.cooldownReady(lastAt, now, cooldown)
    if not isNum(now) then return false, nil end
    if not (isNum(cooldown) and cooldown >= 0) then cooldown = R.DEFAULT_BED_COOLDOWN end
    if lastAt == nil then return true end
    if not isNum(lastAt) then return false, cooldown end
    local rem = lastAt + cooldown - now
    if rem > 0 then return false, rem end
    return true
end

---Interpret the homestead adapter's raw export results.
---@param nearVal any isNearStation(src,'bed') return value (only `true` counts)
---@param comfortVal any getComfort(citizenid) return value (number >= 0, else 0)
---@return { bed: boolean, comfort: number }
function R.resolve(nearVal, comfortVal)
    local bed = nearVal == true
    local comfort = 0
    if bed and isNum(comfortVal) and comfortVal > 0 then comfort = comfortVal end
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

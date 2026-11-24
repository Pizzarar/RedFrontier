-- fh_crafting herb gathering pure rules (plan crafting-02 C9a). No natives; loadable from other resources via
-- '@fh_crafting/shared/gather_rules.lua' (global FhGatherRules). Reach uses the same squared-distance rule as
-- FhContainers.canReach (fh_core/shared/containers.lua:70), with the default interact distance (fh_core/config.lua
-- Access.InteractDistance = 3.5). Coords accept vector3 or {x,y,z}: read through pcall the same way as
-- fh_gunsmith/shared/restore_flow.lua's xyz helper.
local M = {}

M.REACH = 3.5 -- metres, same as FhContainers' default interact distance

---Accepts vector3 or {x=,y=,z=}; returns x,y,z or nil. Rejects nil, NaN, and infinities.
local function xyz(v)
    if v == nil then return nil end
    local ok, x, y, z = pcall(function() return v.x, v.y, v.z end)
    local function fin(n) return type(n) == 'number' and n == n and n ~= math.huge and n ~= -math.huge end
    if not ok or not fin(x) or not fin(y) or not fin(z) then return nil end
    return x, y, z
end

M.validCoords = xyz

---Can a player at `playerCoords` pick `patch` at time `now` (seconds)? `lastPicked` is the patch's shared cooldown
---timestamp (seconds), nil when never picked. A patch without a valid coords table is unknown; a missing/invalid
---player position is too far; a patch still inside `respawnSeconds` of its last pick is regrowing.
---@param patch table { id, herb, coords, yield, respawnSeconds }
---@param playerCoords vector3|table {x,y,z}|nil
---@param now number seconds
---@param lastPicked number|nil seconds
---@return boolean ok
---@return string|nil reason 'fh_unknown_patch' | 'fh_too_far' | 'fh_regrowing'
function M.canPick(patch, playerCoords, now, lastPicked)
    if type(patch) ~= 'table' then return false, 'fh_unknown_patch' end
    local cx, cy, cz = xyz(patch.coords)
    if not cx then return false, 'fh_unknown_patch' end
    local px, py, pz = xyz(playerCoords)
    if not px then return false, 'fh_too_far' end
    local dx, dy, dz = cx - px, cy - py, cz - pz
    if dx * dx + dy * dy + dz * dz > M.REACH * M.REACH then return false, 'fh_too_far' end
    local lp = tonumber(lastPicked)
    if lp then
        local respawn = tonumber(patch.respawnSeconds) or 0
        if (tonumber(now) or 0) < lp + respawn then return false, 'fh_regrowing' end
    end
    return true
end

---Roll a yield for `patch` using an injected rng so specs stay deterministic. `rng(min, max)` returns an integer in
---[min, max] inclusive (defaults to math.random). A missing/bad `yield` reads as {1, 2}.
---@param patch table { yield = {min, max} }
---@param rng function|nil (min, max) -> integer
---@return integer amount
function M.rollYield(patch, rng)
    rng = rng or math.random
    local y = type(patch) == 'table' and patch.yield or nil
    local lo = (type(y) == 'table' and type(y[1]) == 'number') and math.floor(y[1]) or 1
    local hi = (type(y) == 'table' and type(y[2]) == 'number') and math.floor(y[2]) or lo
    if lo < 1 then lo = 1 end
    if hi < lo then hi = lo end
    return rng(lo, hi)
end

---Validate the herbPatches config. `known` is an item-name -> true set; pass it to also reject patches whose herb is
---not a known item (the specs pass the real set). Every patch must have a unique string id, a known herb, valid
---coords, a `yield` of {min, max} with 1 <= min <= max, and a positive `respawnSeconds`.
---@param patches list|nil
---@param known table|nil item -> true
---@return boolean ok
---@return table errors list of strings
function M.validatePatches(patches, known)
    local errs, seen = {}, {}
    if type(patches) ~= 'table' or #patches == 0 then return false, { 'herbPatches is empty or not a list' } end
    for i, p in ipairs(patches) do
        if type(p) ~= 'table' then
            errs[#errs + 1] = ('patch[%d]: not a table'):format(i)
        else
            local id = p.id
            local tag = (type(id) == 'string' and id ~= '') and id or ('#' .. i)
            if type(id) ~= 'string' or id == '' then
                errs[#errs + 1] = ('patch[%d]: missing id'):format(i)
            elseif seen[id] then
                errs[#errs + 1] = (tag .. ': duplicate id')
            else
                seen[id] = true
            end
            if known and (type(p.herb) ~= 'string' or not known[p.herb]) then
                errs[#errs + 1] = (tag .. ': unknown herb ' .. tostring(p.herb))
            elseif not known and type(p.herb) ~= 'string' then
                errs[#errs + 1] = (tag .. ': missing herb')
            end
            if not xyz(p.coords) then
                errs[#errs + 1] = (tag .. ': coords missing or invalid')
            end
            local y = p.yield
            if type(y) ~= 'table' or type(y[1]) ~= 'number' or type(y[2]) ~= 'number'
                or y[1] < 1 or y[2] < y[1] or y[1] ~= math.floor(y[1]) or y[2] ~= math.floor(y[2]) then
                errs[#errs + 1] = (tag .. ': yield must be {min, max} with 1 <= min <= max')
            end
            if not (type(p.respawnSeconds) == 'number' and p.respawnSeconds > 0) then
                errs[#errs + 1] = (tag .. ': respawnSeconds must be a positive number')
            end
        end
    end
    return #errs == 0, errs
end

if GetCurrentResourceName then
    FhGatherRules = M
else
    return M
end

-- fh_hunting wagon adapter (spec L8). Pure Lua. Wraps exports.fh_cargo:nearestWagon(src, coords, range)
-- -> { type = 'wagon', id = 'fh:wagon:<id>' } | nil (roads-r1) into what the skin/sell flows use: { ref, coords }.
-- Anything but a well-formed wagon (nil, a thrown error because fh_cargo is missing or stopped, a malformed value)
-- is "no wagon": the skin is refused and the carcass stays claimable.
local M = {}

-- The one position reader (sell.lua reuses it). Under CfxLua 5.4 / LuaGLM type(vector3(..)) is 'vector3' (also
-- 'vector2'/'vector4'), not 'table'/'userdata', so there is NO type gate: any value is probed through a pcall (a
-- number/nil/boolean throws or yields nothing) and accepted only when x, y, z (or [1], [2], [3] for a plain array)
-- are finite numbers. A string indexes to nil and is rejected.
local function num(n) return type(n) == 'number' and n == n and n > -math.huge and n < math.huge end

---@return number|nil x, number|nil y, number|nil z
function M.xyz(v)
    if v == nil then return nil end
    local ok, x, y, z = pcall(function() return v.x, v.y, v.z end)
    if not ok then return nil end
    if num(x) and num(y) and num(z) then return x, y, z end
    if x ~= nil or y ~= nil or z ~= nil then return nil end
    -- Only when x, y, z are all absent: a plain array. Own pcall, so a strict-metatable userdata that errors on
    -- integer keys was already accepted above through x/y/z.
    local ok2, a, b, c = pcall(function() return v[1], v[2], v[3] end)
    if ok2 and num(a) and num(b) and num(c) then return a, b, c end
    return nil
end

function M.hasXyz(c) return (M.xyz(c)) ~= nil end

---@param nearest function  (src, coords, range) -> table|nil ; the caller wraps the export call, this pcalls it
---@param src number
---@param coords table|nil  { x, y, z } server-read player position
---@param range number      Config.WagonRange
---@return table|nil w { ref = { type = 'wagon', id }, coords }
function M.find(nearest, src, coords, range)
    if type(nearest) ~= 'function' or not M.hasXyz(coords) then return nil end
    local ok, w = pcall(nearest, src, coords, range)
    if not ok or type(w) ~= 'table' then return nil end
    if w.type ~= 'wagon' or type(w.id) ~= 'string' or w.id == '' then return nil end
    -- fh_cargo already applied `range`; report the player's own position as the wagon position so the skin flow's
    -- own WagonRange re-check (shared/skin.lua) passes for exactly the wagons fh_cargo accepted.
    return { ref = { type = 'wagon', id = w.id }, coords = coords }
end

if GetCurrentResourceName then
    FhHuntingWagon = M
else
    return M
end

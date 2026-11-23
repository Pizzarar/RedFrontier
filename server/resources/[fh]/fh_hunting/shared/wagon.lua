-- fh_hunting wagon adapter (spec L8). Pure Lua. Wraps exports.fh_cargo:nearestWagon(src, coords, range)
-- -> { type = 'wagon', id = 'fh:wagon:<id>' } | nil (roads-r1) into what the skin/sell flows use: { ref, coords }.
-- Anything but a well-formed wagon (nil, a thrown error because fh_cargo is missing or stopped, a malformed value)
-- is "no wagon": the skin is refused and the carcass stays claimable.
local M = {}

-- coords may be a { x, y, z } table or a vector3 (userdata); both must have numeric x, y, z.
function M.hasXyz(c)
    local t = type(c)
    if t ~= 'table' and t ~= 'userdata' then return false end
    local ok, x, y, z = pcall(function() return c.x, c.y, c.z end)
    return ok and type(x) == 'number' and type(y) == 'number' and type(z) == 'number'
end

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

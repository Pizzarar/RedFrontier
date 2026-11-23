-- fh_hunting wagon adapter (spec L8). Pure Lua. Wraps exports.fh_cargo:nearestWagon(src, coords, range)
-- -> { type = 'wagon', id = 'fh:wagon:<id>' } | nil (roads-r1) into what the skin/sell flows use: { ref, coords }.
-- Anything but a well-formed wagon (nil, a thrown error because fh_cargo is missing or stopped, a malformed value)
-- is "no wagon": the skin is refused and the carcass stays claimable.
local M = {}

---@param nearest function  (src, coords, range) -> table|nil ; the caller wraps the export call, this pcalls it
---@param src number
---@param coords table|nil  { x, y, z } server-read player position
---@param range number      Config.WagonRange
---@return table|nil w { ref = { type = 'wagon', id }, coords }
function M.find(nearest, src, coords, range)
    if type(nearest) ~= 'function' or type(coords) ~= 'table' then return nil end
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

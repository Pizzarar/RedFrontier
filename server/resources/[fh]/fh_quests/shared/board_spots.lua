-- Jobs board entry-point spots, shared by the client board prop/zone (client/board.lua) and fh_ui's map blips
-- (mapblips). Pure data + a pure nearest-board region pick. No natives, so the specs can load it. Board spot
-- coordinates and the prop model are guesses: TODO-verify-in-game.
local M = {
    spots = {
        { id = 'heartlands_board', region_id = 'heartlands', label = 'Jobs board',
          coords = { x = -297.0, y = 795.0, z = 118.0 },
          model = 'p_notice_board01x' }, -- model unverified; if invalid only the target zone is made
        { id = 'scarlett_meadows_board', region_id = 'scarlett_meadows', label = 'Jobs board',
          coords = { x = 1288.0, y = -1278.0, z = 77.0 }, -- Rhodes general store / trade post (unverified)
          model = 'p_notice_board01x' }, -- model unverified; if invalid only the target zone is made
    },
    DEFAULT_REGION = 'heartlands',
}

local function finite(n) return type(n) == 'number' and n == n and n > -math.huge and n < math.huge end

local function coords(c)
    if c == nil then return nil end
    local ok, x, y, z = pcall(function() return c.x, c.y, c.z end)
    if ok and finite(x) and finite(y) and finite(z) then return x, y, z end
    return nil
end

---Nearest board spot's region_id for a player position, or M.DEFAULT_REGION when no spot has a usable position.
--- player = {x,y,z} (or vector3). spots defaults to M.spots; pass an empty list to force the fallback.
function M.regionFor(player, spots)
    spots = spots or M.spots
    local best, bestD = nil, nil
    for _, s in ipairs(spots) do
        local bx, by, bz = coords(s and s.coords)
        local px, py, pz = coords(player)
        if bx and px then
            local dx, dy, dz = px - bx, py - by, pz - bz
            local d = math.sqrt(dx * dx + dy * dy + dz * dz)
            if bestD == nil or d < bestD then
                best, bestD = s.region_id, d
            end
        end
    end
    return best or M.DEFAULT_REGION
end

if GetCurrentResourceName then
    FhQuestsBoardSpots = M
else
    return M
end

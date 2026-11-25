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
        -- quests-02 C5: one board spot per region with data. Coords are TODO-verify-in-game, near each region's town.
        { id = 'bayou_nwa_board', region_id = 'bayou_nwa', label = 'Jobs board',
          coords = { x = 2695.0, y = -1448.0, z = 45.0 }, -- near Saint Denis
          model = 'p_notice_board01x' },
        { id = 'great_plains_board', region_id = 'great_plains', label = 'Jobs board',
          coords = { x = -859.0, y = -1338.0, z = 44.0 }, -- near Blackwater
          model = 'p_notice_board01x' },
        { id = 'bluewater_marsh_board', region_id = 'bluewater_marsh', label = 'Jobs board',
          coords = { x = 2300.0, y = -600.0, z = 20.0 }, -- near the Bluewater Marsh trade post
          model = 'p_notice_board01x' },
        { id = 'roanoke_ridge_board', region_id = 'roanoke_ridge', label = 'Jobs board',
          coords = { x = 2921.0, y = 1290.0, z = 96.0 }, -- near Annesburg
          model = 'p_notice_board01x' },
        { id = 'grizzlies_east_board', region_id = 'grizzlies_east', label = 'Jobs board',
          coords = { x = 1673.0, y = 1900.0, z = 200.0 }, -- near Wapiti
          model = 'p_notice_board01x' },
        { id = 'grizzlies_west_board', region_id = 'grizzlies_west', label = 'Jobs board',
          coords = { x = -1300.0, y = 1600.0, z = 240.0 }, -- near Colter
          model = 'p_notice_board01x' },
        { id = 'cumberland_forest_board', region_id = 'cumberland_forest', label = 'Jobs board',
          coords = { x = -810.0, y = 1340.0, z = 130.0 }, -- near Bacchus Station
          model = 'p_notice_board01x' },
        { id = 'big_valley_board', region_id = 'big_valley', label = 'Jobs board',
          coords = { x = -1814.0, y = -440.0, z = 120.0 }, -- near Strawberry
          model = 'p_notice_board01x' },
        { id = 'tall_trees_board', region_id = 'tall_trees', label = 'Jobs board',
          coords = { x = -1795.0, y = -1600.0, z = 150.0 }, -- near Manzanita Post
          model = 'p_notice_board01x' },
        { id = 'hennigans_stead_board', region_id = 'hennigans_stead', label = 'Jobs board',
          coords = { x = -2283.0, y = -2493.0, z = 60.0 }, -- near MacFarlane's Ranch
          model = 'p_notice_board01x' },
        { id = 'cholla_springs_board', region_id = 'cholla_springs', label = 'Jobs board',
          coords = { x = -3711.0, y = -2581.0, z = 70.0 }, -- near Armadillo
          model = 'p_notice_board01x' },
        { id = 'gaptooth_ridge_board', region_id = 'gaptooth_ridge', label = 'Jobs board',
          coords = { x = -5522.0, y = -2938.0, z = 90.0 }, -- near Tumbleweed
          model = 'p_notice_board01x' },
        { id = 'rio_bravo_board', region_id = 'rio_bravo', label = 'Jobs board',
          coords = { x = -2000.0, y = -3000.0, z = 55.0 }, -- near the Rio Bravo trade post
          model = 'p_notice_board01x' },
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
--- isEnabled (optional fn(region_id) -> bool, world-01 block D): spots whose region is disabled are skipped, so the
--- /jobs pick never offers a disabled region.
function M.regionFor(player, spots, isEnabled)
    spots = spots or M.spots
    local best, bestD = nil, nil
    for _, s in ipairs(spots) do
        if isEnabled == nil or isEnabled(s.region_id) then
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
    end
    return best or M.DEFAULT_REGION
end

if GetCurrentResourceName then
    FhQuestsBoardSpots = M
else
    return M
end

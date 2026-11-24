-- Jobs board entry-point spots, shared by the client board prop/zone (client/board.lua) and fh_ui's map blips
-- (mapblips). Pure data: no natives, so the specs can load it. Board spot coordinates and the prop model are
-- guesses: TODO-verify-in-game.
local M = {
    spots = {
        { id = 'heartlands_board', region_id = 'heartlands', label = 'Jobs board',
          coords = { x = -297.0, y = 795.0, z = 118.0 },
          model = 'p_notice_board01x' }, -- model unverified; if invalid only the target zone is made
    },
    DEFAULT_REGION = 'heartlands',
}

if GetCurrentResourceName then
    FhQuestsBoardSpots = M
else
    return M
end

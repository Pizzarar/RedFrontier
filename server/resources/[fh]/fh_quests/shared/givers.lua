-- Family quest giver NPCs (Q4): id, quest line and fixed spawn point. Coordinates, headings and models are guesses
-- near the Heartlands homestead area: TODO-verify-in-game. Pure data, shared by the server spawner and the client.
local M = {
    npc_hale = { npc = 'npc_hale', intro = {
            'Name is Ruth Hale. Three daughters, one mule, no roof.',
            'Land office says there is a plot out past the ridge. Go put your name on it.', },
        quest = 'family_hale', label = 'Ruth Hale', model = 'u_f_m_tumgeneralstoreowner_01',
        coords = { x = -296.0, y = 788.0, z = 118.2, w = 90.0 } },
    npc_marrow = { npc = 'npc_marrow', intro = {
            'Sheriff Dell Marrow. My brother rode with the ridge gang. I buried him anyway.',
            'Their camp is still smoking. Put it out, and I will not ask how.', },
        quest = 'family_marrow', label = 'Sheriff Marrow', model = 'u_m_m_valsheriff_01',
        coords = { x = -280.0, y = 805.0, z = 118.5, w = 180.0 } },
    npc_whitlock = { npc = 'npc_whitlock', intro = {
            'Eli Whitlock. Forty winters trapping, one bear I never could close on.',
            'Big as a wagon, white at the muzzle. Everybody laughs until they find the tracks.', },
        quest = 'family_whitlock', label = 'Eli Whitlock', model = 'cs_mp_oldtimer',
        coords = { x = -315.0, y = 780.0, z = 118.0, w = 270.0 } },
}
M.ORDER = { 'npc_hale', 'npc_marrow', 'npc_whitlock' }

if GetCurrentResourceName then
    FhQuestsGivers = M
else
    return M
end

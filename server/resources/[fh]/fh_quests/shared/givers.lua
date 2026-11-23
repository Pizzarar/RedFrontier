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

M.REACH = 5.0 -- metres: how close a player must be to a giver to talk to it / start its line (server-checked)

---The giver record for an npc id, or nil (only real givers: never a helper field of this table).
function M.get(npc_id)
    if type(npc_id) ~= 'string' then return nil end
    for _, id in ipairs(M.ORDER) do
        if id == npc_id then return M[id] end
    end
    return nil
end

---The giver whose quest line is `quest_id`, or nil.
function M.byQuest(quest_id)
    for _, id in ipairs(M.ORDER) do
        if M[id].quest == quest_id then return M[id] end
    end
    return nil
end

---Is a player at `pos` ({x,y,z}, vector3 or table) within `radius` (default M.REACH) of `giver`? Bad input = false.
function M.within(giver, pos, radius)
    if type(giver) ~= 'table' or type(giver.coords) ~= 'table' or pos == nil then return false end
    local px, py, pz = pos.x, pos.y, pos.z
    if type(px) ~= 'number' or type(py) ~= 'number' or type(pz) ~= 'number' then return false end
    if px ~= px or py ~= py or pz ~= pz then return false end -- NaN
    local c = giver.coords
    local dx, dy, dz = px - c.x, py - c.y, pz - c.z
    local r = radius or M.REACH
    return dx * dx + dy * dy + dz * dz <= r * r
end

if GetCurrentResourceName then
    FhQuestsGivers = M
else
    return M
end

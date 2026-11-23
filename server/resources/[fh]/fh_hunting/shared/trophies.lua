-- Trophy comfort data (spec L8 H5). Pure: no natives. The item itself is registered by animals.itemDefs()
-- (trophy_legendary_bear, bulky). Homestead owns placement and reads the value via exports.fh_hunting:getTrophyComfort.
-- Only the legendary bear trophy exists: the plan defines no trophy for normal-game animals (pelts are not trophies).
local M = {}

M.comfort = {
    trophy_legendary_bear = 25,
}

---Comfort value of a trophy item id: number, or nil for pelts, unknown ids and non-strings.
function M.getComfort(itemId)
    if type(itemId) ~= 'string' then return nil end
    return M.comfort[itemId]
end

if GetCurrentResourceName then
    FhHuntingTrophies = M
else
    return M
end

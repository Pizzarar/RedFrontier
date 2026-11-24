-- Trophy comfort data (spec L8 H5). Pure: no natives. The items themselves are registered by animals.itemDefs() (one
-- bulky trophy_<id> per legendary). Homestead owns placement and reads the value via exports.fh_hunting:getTrophyComfort.
-- Derived from data/legendaries/<region_id>.lua (trophy.comfort); normal-game animals have no trophy (pelts are not
-- trophies).
local M = {}

local function legendaries()
    if FhHuntingLegendaries then return FhHuntingLegendaries end
    local dir = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
    return package.loaded.fh_hunting_legendaries or dofile(dir .. 'legendaries.lua')
end

M.comfort = {}
for _, e in ipairs(legendaries().list) do M.comfort[e.trophy.item] = e.trophy.comfort end

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

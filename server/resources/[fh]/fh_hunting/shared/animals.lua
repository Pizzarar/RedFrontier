-- fh_hunting animal table (spec L8). Pure Lua. One pelt item per animal; stars live in the item's info, not the id.
-- size_class: 'bulky' = saddlebag OK (small / medium game); 'cargo' = wagon or chest only (big game, every legendary).
-- The plain rows live in shared/plain_animals.lua (the legendary loader validates against the same table).
-- Legendary rows are derived from data/legendaries/<region_id>.lua (shared/legendaries.lua, plan hunting-02): one per
-- registry entry, enabled region or not (the items must exist before a region is switched on).
local M = {}

local DIR = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'

-- The legendary registry: the FXServer global, else the spec-side singleton (shared/legendaries.lua).
local function legendaries()
    if FhHuntingLegendaries then return FhHuntingLegendaries end
    return package.loaded.fh_hunting_legendaries or dofile(DIR .. 'legendaries.lua')
end

-- The plain rows: the FXServer global, else the spec-side singleton (shared/plain_animals.lua).
local function plainAnimals()
    if FhHuntingPlainAnimals then return FhHuntingPlainAnimals end
    return package.loaded.fh_hunting_plain_animals or dofile(DIR .. 'plain_animals.lua')
end

M.legendaryBearPelt = 'pelt_legendary_bear'
M.legendaryBearTrophy = 'trophy_legendary_bear'

-- Order is the display order: the plain rows (copied list; the row tables are shared and never mutated), then the
-- legendaries in registry order.
M.list, M.byKey, M.byPelt, M.byLegendary, M.warnings = {}, {}, {}, {}, {}
for _, a in ipairs(plainAnimals().list) do
    M.list[#M.list + 1] = a
    M.byKey[a.key] = a
    M.byPelt[a.pelt] = a
end

---The animal row of a legendary entry: always 3 stars, always cargo; the trophy is the bulky keepsake.
function M.legendaryRow(e)
    return { key = e.id, label = e.label, model = e.species_model, pelt = e.pelt.item, size_class = 'cargo',
        value = e.pelt.value, weight = e.pelt.weight, image = e.pelt.image, legendary = true, fixedStars = 3,
        trophy = e.trophy.item, region_id = e.region_id, peltLabel = e.pelt.label, trophyDef = e.trophy }
end

-- Legendary rows, after the plain ones (display order = registry order). The loader already rejects entries that
-- collide with a plain row or have no plain species row, so this guard only fires if a registry bypassed that check;
-- it is printed at resource start like the loader's warnings.
for _, e in ipairs(legendaries().list) do
    local row = M.legendaryRow(e)
    if M.byKey[row.key] or M.byPelt[row.pelt] or M.byPelt[row.trophy] then
        M.warnings[#M.warnings + 1] = 'legendary ' .. row.key .. ' collides with an existing animal or item'
    else
        M.list[#M.list + 1] = row
        M.byKey[row.key] = row
        M.byPelt[row.pelt] = row
        M.byLegendary[row.key] = row
    end
end

---Jenkins one-at-a-time hash of the lowercased name, as an unsigned 32-bit number (GetEntityModel, unsigned).
function M.joaat(name)
    local h = 0
    name = name:lower()
    for i = 1, #name do
        h = (h + name:byte(i)) & 0xFFFFFFFF
        h = (h + (h << 10)) & 0xFFFFFFFF
        h = (h ~ (h >> 6)) & 0xFFFFFFFF
    end
    h = (h + (h << 3)) & 0xFFFFFFFF
    h = (h ~ (h >> 11)) & 0xFFFFFFFF
    h = (h + (h << 15)) & 0xFFFFFFFF
    return h
end

-- Regular animals only: a legendary shares its model with a plain animal and is identified by the hunt chain's adopted
-- spawn (the skin flow passes its legendary id), never by the model alone.
M.byModel, M.byHash = {}, {}
for _, a in ipairs(M.list) do
    if not a.legendary then
        M.byModel[a.model] = a
        M.byHash[M.joaat(a.model)] = a
    end
end

---Animal entry for a model name, a hash (signed or unsigned), or an animal key. `legendary` selects a legendary
---regardless of the model: a legendary id (unknown / stub ids give nil), or `true` for the Legendary Bear (H4 compat).
---@return table|nil animal
function M.get(model, legendary)
    if legendary == true then return M.byLegendary.legendary_bear end
    if type(legendary) == 'string' then return M.byLegendary[legendary] end
    if legendary then return nil end
    if type(model) == 'string' then return M.byModel[model:lower()] or M.byKey[model:lower()] end
    -- integers only: `&` on a float with a fraction, NaN or inf raises, and a float hash is never a model
    if math.type(model) == 'integer' then return M.byHash[model & 0xFFFFFFFF] end
    return nil
end

function M.sizeClass(model, legendary)
    local a = M.get(model, legendary)
    return a and a.size_class or nil
end

---fh_core registerItems definitions (§4.1): one pelt per animal plus one trophy per legendary.
---Pelts are not stackable: the star rating lives in per-instance info, so two pelts of one animal can differ.
function M.itemDefs()
    local defs = {}
    for _, a in ipairs(M.list) do
        defs[a.pelt] = {
            label = a.peltLabel or (a.label .. ' Pelt'), weight = a.weight, size_class = a.size_class, stackable = false,
            value_base = a.value, illicit = false, image = a.image, useable = false,
            description = a.legendary and 'A pelt from a legendary hunt.' or ('A skinned ' .. a.label:lower() .. ' pelt.'),
        }
        local t = a.trophyDef
        if t then
            defs[t.item] = {
                label = t.label, weight = t.weight or 4000, size_class = 'bulky', stackable = false,
                value_base = 0, illicit = false, image = t.image or a.image, useable = false,
                description = t.description or ('A keepsake from the ' .. a.label:lower() .. ' hunt.'),
            }
        end
    end
    return defs
end

if GetCurrentResourceName then
    for _, w in ipairs(M.warnings) do print('^3[fh_hunting] animals: ' .. w .. '^7') end
    FhHuntingAnimals = M
else
    return M
end

-- fh_hunting animal table (spec L8). Pure Lua. One pelt item per animal; stars live in the item's info, not the id.
-- size_class: 'bulky' = saddlebag OK (small / medium game); 'cargo' = wagon or chest only (big game, every legendary).
-- model: the ped model name. UNVERIFIED in game: confirm each against the natives probe before H2 ships.
-- image: reuses the rsg-inventory images where one matches, else a generic pelt image.
local M = {}

M.legendaryBearPelt = 'pelt_legendary_bear'
M.legendaryBearTrophy = 'trophy_legendary_bear'

-- Order is the display order. value = base price of a 2-star pelt, before the star / legendary multipliers.
M.list = {
    { key = 'rabbit',   label = 'Rabbit',   model = 'a_c_rabbit_01',     pelt = 'pelt_rabbit',   size_class = 'bulky', value = 3,  weight = 300,   image = 'resource_pelt_rabbit.png' },
    { key = 'fox',      label = 'Fox',      model = 'a_c_fox_01',        pelt = 'pelt_fox',      size_class = 'bulky', value = 8,  weight = 600,   image = 'resource_pelt_fox.png' },
    { key = 'coyote',   label = 'Coyote',   model = 'a_c_coyote_01',     pelt = 'pelt_coyote',   size_class = 'bulky', value = 8,  weight = 800,   image = 'resource_pelt_coyote.png' },
    { key = 'deer',     label = 'Deer',     model = 'a_c_deer_01',       pelt = 'pelt_deer',     size_class = 'bulky', value = 14, weight = 2500,  image = 'good_pelt.png' },
    { key = 'boar',     label = 'Boar',     model = 'a_c_boar_01',       pelt = 'pelt_boar',     size_class = 'bulky', value = 12, weight = 2500,  image = 'good_pelt.png' },
    { key = 'wolf',     label = 'Wolf',     model = 'a_c_wolf',          pelt = 'pelt_wolf',     size_class = 'bulky', value = 20, weight = 2000,  image = 'resource_pelt_wolf.png' },
    { key = 'bear',     label = 'Bear',     model = 'a_c_bear_01',       pelt = 'pelt_bear',     size_class = 'cargo', value = 45, weight = 20000, image = 'perfect_pelt.png' },
    { key = 'bison',    label = 'Bison',    model = 'a_c_buffalo_01',    pelt = 'pelt_bison',    size_class = 'cargo', value = 40, weight = 25000, image = 'perfect_pelt.png' },
    { key = 'elk',      label = 'Elk',      model = 'a_c_elk_01',        pelt = 'pelt_elk',      size_class = 'cargo', value = 38, weight = 18000, image = 'perfect_pelt.png' },
    { key = 'moose',    label = 'Moose',    model = 'a_c_moose_01',      pelt = 'pelt_moose',    size_class = 'cargo', value = 50, weight = 25000, image = 'perfect_pelt.png' },
    { key = 'alligator', label = 'Alligator', model = 'a_c_alligator_01', pelt = 'pelt_alligator', size_class = 'cargo', value = 55, weight = 20000, image = 'perfect_pelt.png' },
    -- Legendary Bear: one chain (H4). Always 3 stars, always cargo; the trophy is the bulky keepsake.
    { key = 'legendary_bear', label = 'Legendary Bear', model = 'a_c_bear_01', pelt = 'pelt_legendary_bear',
      size_class = 'cargo', value = 60, weight = 30000, image = 'legendary_bear_pelt.png',
      legendary = true, fixedStars = 3, trophy = 'trophy_legendary_bear' },
}

M.byKey, M.byPelt = {}, {}
for _, a in ipairs(M.list) do
    M.byKey[a.key] = a
    M.byPelt[a.pelt] = a
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

-- Regular animals only: the legendary shares its model with the plain bear and is identified by the hunt chain
-- (H4 passes legendary = true), never by the model alone.
M.byModel, M.byHash = {}, {}
for _, a in ipairs(M.list) do
    if not a.legendary then
        M.byModel[a.model] = a
        M.byHash[M.joaat(a.model)] = a
    end
end

---Animal entry for a model name, a hash (signed or unsigned), or an animal key. `legendary` selects the legendary
---bear regardless of the model.
---@return table|nil animal
function M.get(model, legendary)
    if legendary then return M.byKey.legendary_bear end
    if type(model) == 'string' then return M.byModel[model:lower()] or M.byKey[model:lower()] end
    -- integers only: `&` on a float with a fraction, NaN or inf raises, and a float hash is never a model
    if math.type(model) == 'integer' then return M.byHash[model & 0xFFFFFFFF] end
    return nil
end

function M.sizeClass(model, legendary)
    local a = M.get(model, legendary)
    return a and a.size_class or nil
end

---fh_core registerItems definitions (§4.1): one pelt per animal plus the legendary trophy.
---Pelts are not stackable: the star rating lives in per-instance info, so two pelts of one animal can differ.
function M.itemDefs()
    local defs = {}
    for _, a in ipairs(M.list) do
        defs[a.pelt] = {
            label = a.label .. ' Pelt', weight = a.weight, size_class = a.size_class, stackable = false,
            value_base = a.value, illicit = false, image = a.image, useable = false,
            description = a.legendary and 'A pelt from a legendary hunt.' or ('A skinned ' .. a.label:lower() .. ' pelt.'),
        }
    end
    defs[M.legendaryBearTrophy] = {
        label = 'Legendary Bear Trophy', weight = 4000, size_class = 'bulky', stackable = false,
        value_base = 0, illicit = false, image = 'legendary_bear_pelt.png', useable = false,
        description = 'A keepsake from the legendary bear hunt.',
    }
    return defs
end

if GetCurrentResourceName then
    FhHuntingAnimals = M
else
    return M
end

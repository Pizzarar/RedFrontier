-- fh_hunting plain (non-legendary) animal rows (spec L8). Pure data, no natives. The one source both the legendary
-- loader (shared/legendaries.lua: rejects an entry whose id or items collide with a row here, or whose species_model
-- has no row here) and the animal table (shared/animals.lua: these rows first, then one row per legendary) read, so
-- the registry and every consumer agree on which legendaries exist. Rows are shared: consumers never mutate them.
-- size_class: 'bulky' = saddlebag OK (small / medium game); 'cargo' = wagon or chest only (big game).
-- model: the ped model name. UNVERIFIED in game: confirm each against the natives probe before H2 ships.
-- image: reuses the rsg-inventory images where one matches, else a generic pelt image.
local M = {}

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
}

-- byItem: every item id a plain row owns (its pelt), so a legendary's pelt_/trophy_ ids can be checked against it.
M.byKey, M.byModel, M.byItem = {}, {}, {}
for _, a in ipairs(M.list) do
    M.byKey[a.key] = a
    M.byModel[a.model] = a
    M.byItem[a.pelt] = a
end

if GetCurrentResourceName then
    FhHuntingPlainAnimals = M
else
    package.loaded.fh_hunting_plain_animals = package.loaded.fh_hunting_plain_animals or M
    return package.loaded.fh_hunting_plain_animals
end

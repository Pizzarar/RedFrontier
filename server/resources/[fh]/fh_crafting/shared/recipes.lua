-- fh_crafting recipes (plan crafting-01 C1). Pure data: no natives.
-- Recipe: { id, station_type in {gunsmith, reload, apothecary, cook}, inputs = {{item, amount}}, outputs = {{item, amount}}, label }
-- gunsmith restore is NOT a recipe (fh_gunsmith, C3); the station type stays valid for future recipes.
-- Item names: resource_gunpowder, ammo_box_revolver, ammo_box_rifle and herb_* already exist in rsg-core shared items.
-- gun parts, lead and casings are registered by fh_crafting (config.lua).
local M = {}

M.list = {
    { id = 'ammo_revolver', station_type = 'reload', label = 'Reload revolver ammo',
      inputs = { { item = 'resource_gunpowder', amount = 1 }, { item = 'lead', amount = 2 }, { item = 'casings', amount = 2 } },
      outputs = { { item = 'ammo_box_revolver', amount = 1 } } },
    { id = 'ammo_rifle', station_type = 'reload', label = 'Reload rifle ammo',
      inputs = { { item = 'resource_gunpowder', amount = 2 }, { item = 'lead', amount = 2 }, { item = 'casings', amount = 2 } },
      outputs = { { item = 'ammo_box_rifle', amount = 1 } } },
    { id = 'tonic_vigor', station_type = 'apothecary', label = 'Brew Vigor Tonic',
      inputs = { { item = 'herb_american_ginseng', amount = 2 }, { item = 'herb_wild_mint', amount = 1 } },
      outputs = { { item = 'tonic_vigor', amount = 1 } } },
    { id = 'tonic_steady', station_type = 'apothecary', label = 'Brew Steady Tonic',
      inputs = { { item = 'herb_oregano', amount = 2 }, { item = 'herb_red_sage', amount = 1 } },
      outputs = { { item = 'tonic_steady', amount = 1 } } },
    -- Campfire cooking (plan crafting-03 C10a, idea-852). All items are rsg-core; survival maps the outputs to well_fed.
    { id = 'cook_meat', station_type = 'cook', label = 'Cook meat',
      inputs = { { item = 'raw_meat', amount = 1 } },
      outputs = { { item = 'cooked_meat', amount = 1 } } },
    { id = 'cook_stew', station_type = 'cook', label = 'Cook stew',
      inputs = { { item = 'raw_meat', amount = 2 }, { item = 'carrot', amount = 1 }, { item = 'potato', amount = 1 } },
      outputs = { { item = 'stew', amount = 1 } } },
    { id = 'cook_stew_veg', station_type = 'cook', label = 'Cook vegetable stew',
      inputs = { { item = 'carrot', amount = 1 }, { item = 'potato', amount = 1 }, { item = 'corn', amount = 1 } },
      outputs = { { item = 'stew_veg', amount = 1 } } },
}

M.byId = {}
for _, r in ipairs(M.list) do M.byId[r.id] = r end

function M.get(id) return M.byId[id] end

if GetCurrentResourceName then FhCraftRecipes = M else return M end

-- fh_crafting server (spec L5). C1: item registration, recipe validation and the adapter exports.
local cfg, rules, recipes, gather = FhCraftingConfig, FhCraftRules, FhCraftRecipes, FhGatherRules

local function registerItems()
    local ok, err, bad = exports.fh_core:registerItems(cfg.items)
    if not ok then print(('^1[fh_crafting] registerItems failed: %s (%s)^7'):format(tostring(err), tostring(bad))) end
    return ok
end

---Items a gather patch may name: everything fh_crafting registers (config.items) plus the rsg-core items it uses but
---does not re-register (config.lua:4). Mirrors the spec EXISTING set so the runtime check and the specs agree.
local function knownItems()
    local known = {}
    for name in pairs(cfg.items or {}) do known[name] = true end
    for _, name in ipairs({ 'resource_gunpowder', 'ammo_box_revolver', 'ammo_box_rifle',
        'herb_american_ginseng', 'herb_oregano', 'herb_red_sage', 'herb_wild_mint' }) do
        known[name] = true
    end
    return known
end

local function validate()
    local ok, errs = rules.validateRecipes(recipes.list)
    if not ok then
        for _, e in ipairs(errs) do print(('^1[fh_crafting] recipe error: %s^7'):format(e)) end
    end
    local okP, errsP = gather.validatePatches(cfg.herbPatches, knownItems())
    if not okP then
        for _, e in ipairs(errsP) do print(('^1[fh_crafting] herb patch error: %s^7'):format(e)) end
    end
end

-- fh_core keeps runtime definitions in memory, so a restart of fh_core loses them: register again.
AddEventHandler('onResourceStart', function(res)
    if res == GetCurrentResourceName() then validate() end
    if res == GetCurrentResourceName() or res == 'fh_core' then registerItems() end
end)

exports('getRecipes', function() return recipes.list end)
exports('isNearStation', function(src, stationType, maxDist) return FhCraftStations.isNearStation(src, stationType, maxDist) end)
exports('getStations', function(citizenid) return FhCraftStations.getStations(citizenid) end)
exports('stationAt', function(coords, maxDist) return FhCraftStations.stationAt(coords, maxDist) end)
exports('craft', function(src, recipeId) return FhCraft.craft(src, recipeId) end)
exports('invCount', function(src, item) return FhCraftInv.count(src, item) end)
exports('invTake', function(src, item, amount) return FhCraftInv.take(src, item, amount) end)
exports('invGive', function(src, item, amount, info) return FhCraftInv.give(src, item, amount, info) end)
exports('invSlot', function(src, slot) return FhCraftInv.slot(src, slot) end)
exports('invSetInfo', function(src, slot, info, expectName) return FhCraftInv.setInfo(src, slot, info, expectName) end)

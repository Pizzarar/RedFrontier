-- fh_hunting server (spec L8). H1: item registration and the pure-rule exports. The skin flow is H2.
local animals, price, cfg = FhHuntingAnimals, FhHuntingPrice, FhHuntingConfig

local function registerItems()
    local ok, err, bad = exports.fh_core:registerItems(animals.itemDefs())
    if not ok then print(('^1[fh_hunting] registerItems failed: %s (%s)^7'):format(tostring(err), tostring(bad))) end
    return ok
end

-- fh_core keeps runtime definitions in memory, so a restart of fh_core loses them: register again.
AddEventHandler('onResourceStart', function(res)
    if res == GetCurrentResourceName() or res == 'fh_core' then registerItems() end
end)

exports('getAnimal', function(model, legendary) return animals.get(model, legendary) end)
exports('getPeltItem', function(model, legendary)
    local a = animals.get(model, legendary)
    return a and a.pelt or nil
end)
-- Payout for a pelt item and star rating: amount | nil, err. The base value comes from the animal table.
exports('price', function(peltItem, stars)
    local a = animals.byPelt[peltItem]
    if not a then return nil, 'fh_unknown_pelt' end
    return price.price(a.value, a.fixedStars or stars, a.legendary == true, cfg)
end)

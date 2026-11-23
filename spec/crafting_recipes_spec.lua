-- Run from repo root: `lua spec/crafting_recipes_spec.lua` (or via tools/run-specs.py).
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local describe, it, eq = T.describe, T.it, T.eq
local base = here .. '../server/resources/[fh]/fh_crafting/'
local cfg = dofile(base .. 'config.lua')
local R = dofile(base .. 'shared/craft_rules.lua')
local Recipes = dofile(base .. 'shared/recipes.lua')

-- Items that already exist in rsg-core shared items (not re-registered by fh_crafting).
local EXISTING = {
    resource_gunpowder = true, ammo_box_revolver = true, ammo_box_rifle = true,
    herb_american_ginseng = true, herb_wild_mint = true, herb_oregano = true, herb_red_sage = true,
}

describe('crafting recipes', function()
    it('validate clean', function()
        local ok, errs = R.validateRecipes(Recipes.list)
        eq(true, ok, table.concat(errs or {}, '; '))
    end)
    it('ships reload and apothecary recipes', function()
        eq('reload', Recipes.get('ammo_revolver').station_type)
        eq('reload', Recipes.get('ammo_rifle').station_type)
        eq('apothecary', Recipes.get('tonic_vigor').station_type)
        eq('apothecary', Recipes.get('tonic_steady').station_type)
    end)
    it('every input/output item is registered by fh_crafting or a known existing item', function()
        for _, r in ipairs(Recipes.list) do
            for _, side in ipairs({ r.inputs, r.outputs }) do
                for _, e in ipairs(side) do
                    eq(true, cfg.items[e.item] ~= nil or EXISTING[e.item] == true, r.id .. ': unknown item ' .. e.item)
                end
            end
        end
    end)
    it('existing items are not re-registered', function()
        for name in pairs(EXISTING) do eq(nil, cfg.items[name], name) end
    end)
    it('registers the new items and tonics are usable', function()
        for _, n in ipairs({ 'gun_parts', 'lead', 'casings', 'tonic_vigor', 'tonic_steady' }) do
            eq(true, cfg.items[n] ~= nil, n)
        end
        eq(true, cfg.items.tonic_vigor.useable); eq(true, cfg.items.tonic_steady.useable)
    end)
    it('tonic recipes output items tonicFor knows', function()
        eq(true, R.tonicFor('tonic_vigor', cfg) ~= nil); eq(true, R.tonicFor('tonic_steady', cfg) ~= nil)
    end)
    it('config: dev stations for every type, max dist', function()
        for st in pairs(R.STATION_TYPES) do eq(true, cfg.devStations[st] ~= nil, st) end
        eq(3.0, cfg.stationMaxDist)
    end)
end)

T.finish()

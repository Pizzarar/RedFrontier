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
    raw_meat = true, cooked_meat = true, carrot = true, potato = true, corn = true, stew = true, stew_veg = true,
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
    it('ships the cook recipes (C10a)', function()
        for id, ins, out in (function()
            local t = { { 'cook_meat', { raw_meat = 1 }, 'cooked_meat' }, { 'cook_stew', { raw_meat = 2, carrot = 1, potato = 1 }, 'stew' },
                { 'cook_stew_veg', { carrot = 1, potato = 1, corn = 1 }, 'stew_veg' } }
            local i = 0
            return function() i = i + 1; if t[i] then return t[i][1], t[i][2], t[i][3] end end
        end)() do
            local r = Recipes.get(id)
            eq('cook', r.station_type, id)
            eq(1, #r.outputs, id); eq(out, r.outputs[1].item, id); eq(1, r.outputs[1].amount, id)
            local have = {}
            for _, e in ipairs(r.inputs) do have[e.item] = e.amount end
            for item, n in pairs(ins) do eq(n, have[item], id .. ' ' .. item) end
            eq(true, (R.canCraft(ins, r)), id .. ' craftable with exact inputs')
            eq(false, (R.canCraft({}, r)), id .. ' not craftable empty')
        end
    end)
    it('cook resolves to the campfire station', function()
        eq('campfire', cfg.stationTypeMap.cook)
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

-- Run from repo root: `lua spec/crafting_rules_spec.lua` (or via tools/run-specs.py).
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local describe, it, eq, same = T.describe, T.it, T.eq, T.same
local base = here .. '../server/resources/[fh]/fh_crafting/'
local cfg = dofile(base .. 'config.lua')
local R = dofile(base .. 'shared/craft_rules.lua')

local recipe = { id = 'x', station_type = 'reload', inputs = { { item = 'a', amount = 2 }, { item = 'b', amount = 1 } },
    outputs = { { item = 'c', amount = 1 } } }

describe('crafting: canCraft', function()
    it('ok when counts suffice', function()
        local ok, missing = R.canCraft({ a = 2, b = 5 }, recipe)
        eq(true, ok); eq(0, #missing)
    end)
    it('reports missing with need and have', function()
        local ok, missing = R.canCraft({ a = 1 }, recipe)
        eq(false, ok)
        same({ { item = 'a', need = 2, have = 1 }, { item = 'b', need = 1, have = 0 } }, missing)
    end)
    it('nil counts = nothing', function()
        local ok, missing = R.canCraft(nil, recipe)
        eq(false, ok); eq(2, #missing)
    end)
end)

describe('crafting: restoreCap', function()
    it('60/80/100 per star', function()
        eq(60, R.restoreCap(1)); eq(80, R.restoreCap(2)); eq(100, R.restoreCap(3))
    end)
    it('nil or invalid stars = 1 star', function()
        eq(60, R.restoreCap(nil)); eq(60, R.restoreCap('junk')); eq(60, R.restoreCap(0)); eq(100, R.restoreCap(9))
    end)
end)

describe('crafting: restore', function()
    it('each part gives +20', function()
        local c, used, why = R.restore(10, 3, 2)
        eq(50, c); eq(2, used); eq(nil, why)
    end)
    it('never past the cap, uses the fewest parts', function()
        local c, used = R.restore(50, 1, 5)   -- cap 60: one part reaches it
        eq(60, c); eq(1, used)
        c, used = R.restore(0, 2, 10)         -- cap 80: four parts
        eq(80, c); eq(4, used)
        c, used = R.restore(95, 3, 3)
        eq(100, c); eq(1, used)
    end)
    it('partial parts use all available', function()
        local c, used = R.restore(0, 3, 2)
        eq(40, c); eq(2, used)
    end)
    it('at_cap uses no parts', function()
        local c, used, why = R.restore(60, 1, 5)
        eq(60, c); eq(0, used); eq('at_cap', why)
        _, used, why = R.restore(100, 3, 5)
        eq('at_cap', why)
    end)
    it('no_parts', function()
        local c, used, why = R.restore(10, 2, 0)
        eq(10, c); eq(0, used); eq('no_parts', why)
        _, _, why = R.restore(10, 2, nil)
        eq('no_parts', why)
    end)
    it('no_condition refuses', function()
        local c, used, why = R.restore(nil, 2, 5)
        eq(nil, c); eq(0, used); eq('no_condition', why)
    end)
    it('nil stars caps at 60', function()
        local c = R.restore(55, nil, 5)
        eq(60, c)
    end)
end)

describe('crafting: tonicFor', function()
    it('vigor and steady', function()
        same({ buff_id = 'tonic_vigor', magnitude = 1.15, duration_s = 600 }, R.tonicFor('tonic_vigor', cfg))
        same({ buff_id = 'tonic_steady', magnitude = 1.10, duration_s = 300 }, R.tonicFor('tonic_steady', cfg))
    end)
    it('other items are nil', function() eq(nil, R.tonicFor('bread', cfg)); eq(nil, R.tonicFor(nil, cfg)) end)
end)

describe('crafting: validateRecipe(s)', function()
    local function good() return { id = 'g', station_type = 'gunsmith', inputs = { { item = 'a', amount = 1 } },
        outputs = { { item = 'b', amount = 1 } } } end
    it('accepts a good recipe for every station type', function()
        for _, st in ipairs({ 'gunsmith', 'reload', 'apothecary', 'cook' }) do
            local r = good(); r.station_type = st
            eq(true, (R.validateRecipe(r)))
        end
    end)
    it('bad station_type', function()
        local r = good(); r.station_type = 'forge'
        eq(false, (R.validateRecipe(r)))
    end)
    it('bad amounts', function()
        for _, a in ipairs({ 0, -1, 1.5, '2' }) do
            local r = good(); r.inputs[1].amount = a
            eq(false, (R.validateRecipe(r)), tostring(a))
        end
        local r = good(); r.outputs[1].amount = 0
        eq(false, (R.validateRecipe(r)))
    end)
    it('empty inputs or outputs', function()
        local r = good(); r.inputs = {}
        eq(false, (R.validateRecipe(r)))
        r = good(); r.outputs = nil
        eq(false, (R.validateRecipe(r)))
    end)
    it('duplicate ids', function()
        local ok, errs = R.validateRecipes({ good(), good() })
        eq(false, ok); eq(1, #errs)
    end)
    it('a clean list passes', function()
        local b = good(); b.id = 'h'
        eq(true, (R.validateRecipes({ good(), b })))
    end)
end)

T.finish()

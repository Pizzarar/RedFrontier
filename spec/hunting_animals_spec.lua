-- Run from repo root: `lua spec/hunting_animals_spec.lua` (or via tools/run-specs.py).
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local describe, it, eq = T.describe, T.it, T.eq
local base = here .. '../server/resources/[fh]/fh_hunting/'
local A = dofile(base .. 'shared/animals.lua')
-- The legendary registry animals.lua derived its extra rows from (the loader's default registry singleton).
local L = package.loaded.fh_hunting_legendaries or dofile(base .. 'shared/legendaries.lua')
-- fh_core's item validator is the contract registerItems applies, so the definitions must pass it.
local Items = dofile(here .. '../server/resources/[fh]/fh_core/shared/items.lua')

describe('hunting animals: size_class per animal', function()
    for _, key in ipairs({ 'rabbit', 'fox', 'coyote', 'deer', 'boar', 'wolf' }) do
        it(key .. ' pelt is bulky', function() eq('bulky', A.byKey[key].size_class) end)
    end
    for _, key in ipairs({ 'bear', 'bison', 'elk', 'moose', 'alligator', 'legendary_bear' }) do
        it(key .. ' pelt is cargo', function() eq('cargo', A.byKey[key].size_class) end)
    end
    it('every legendary is cargo', function()
        for _, a in ipairs(A.list) do
            if a.legendary then eq('cargo', a.size_class, a.key) end
        end
    end)
    it('sizeClass looks up by model, key and hash', function()
        eq('bulky', A.sizeClass('a_c_deer_01'))
        eq('cargo', A.sizeClass('A_C_BEAR_01'))
        eq('cargo', A.sizeClass(A.joaat('a_c_buffalo_01')))
        eq(nil, A.sizeClass('a_c_unknown'))
    end)
end)

describe('hunting animals: table shape', function()
    it('has the eleven plain animals plus one row per legendary entry', function() eq(11 + #L.list, #A.list) end)
    it('pelt ids are unique, pelt_<key>, and every animal has a positive base value', function()
        local seen = {}
        for _, a in ipairs(A.list) do
            assert(not seen[a.pelt], 'duplicate ' .. a.pelt)
            seen[a.pelt] = true
            eq('pelt_' .. a.key, a.pelt)
            assert(a.value > 0 and a.weight > 0, a.key)
        end
    end)
    it('the legendary bear is always 3 stars and carries a bulky trophy', function()
        local l = A.byKey.legendary_bear
        eq('pelt_legendary_bear', l.pelt); eq(3, l.fixedStars); eq(true, l.legendary)
        eq('trophy_legendary_bear', l.trophy)
        eq('bulky', A.itemDefs().trophy_legendary_bear.size_class)
    end)
    it('the model alone never gives the legendary; the chain flag does', function()
        eq('pelt_bear', A.get('a_c_bear_01').pelt)
        eq('pelt_legendary_bear', A.get('a_c_bear_01', true).pelt)
    end)
end)

describe('hunting animals: lookup', function()
    it('joaat matches the known Jenkins vectors', function()
        eq(0, A.joaat(''))
        eq(0xCA2E9442, A.joaat('a'))
    end)
    it('a hash resolves, signed or unsigned', function()
        local h = A.joaat('a_c_wolf')
        eq('pelt_wolf', A.get(h).pelt)
        eq('pelt_wolf', A.get(h - 0x100000000).pelt)
    end)
    it('a model name is case-insensitive; junk gives nil', function()
        eq('pelt_deer', A.get('A_C_Deer_01').pelt)
        eq(nil, A.get(nil)); eq(nil, A.get({})); eq(nil, A.get(12345))
    end)
    it('a float, NaN or inf hash gives nil instead of raising', function()
        eq(nil, A.get(1.5)); eq(nil, A.get(0 / 0)); eq(nil, A.get(math.huge)); eq(nil, A.get(-math.huge))
        eq(nil, A.get(A.joaat('a_c_wolf') + 0.0))
    end)
end)

describe('hunting animals: item definitions', function()
    local defs = A.itemDefs()
    it('one definition per animal plus one trophy per legendary', function()
        local n = 0
        for _ in pairs(defs) do n = n + 1 end
        eq(#A.list + #L.list, n)
        for _, a in ipairs(A.list) do assert(defs[a.pelt], a.pelt) end
        for _, e in ipairs(L.list) do assert(defs[e.trophy.item], e.trophy.item) end
    end)
    it('every definition passes the fh_core validator and keeps the animal size_class', function()
        for name, d in pairs(defs) do
            local ok, err = Items.validate(d)
            assert(ok, name .. ': ' .. tostring(err))
        end
        eq('bulky', defs.pelt_fox.size_class)
        eq('cargo', defs.pelt_moose.size_class)
    end)
    it('pelts are not stackable (stars live in info)', function()
        for _, a in ipairs(A.list) do eq(false, defs[a.pelt].stackable, a.pelt) end
    end)
end)

T.finish()

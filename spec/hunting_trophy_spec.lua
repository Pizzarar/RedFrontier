-- Run from repo root: `lua spec/hunting_trophy_spec.lua` (or via tools/run-specs.py).
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local describe, it, eq = T.describe, T.it, T.eq
local base = here .. '../server/resources/[fh]/fh_hunting/'
local Tr = dofile(base .. 'shared/trophies.lua')
local A = dofile(base .. 'shared/animals.lua')

describe('hunting trophy comfort', function()
    it('legendary bear trophy has a positive number', function()
        local c = Tr.getComfort('trophy_legendary_bear')
        eq('number', type(c))
        eq(true, c > 0)
    end)
    it('every trophy with comfort is a registered item', function()
        local defs = A.itemDefs()
        for id in pairs(Tr.comfort) do eq(true, defs[id] ~= nil, id) end
    end)
    it('pelts are not trophies', function()
        for _, a in ipairs(A.list) do eq(nil, Tr.getComfort(a.pelt), a.pelt) end
    end)
    it('unknown, nil and non-string ids give nil', function()
        eq(nil, Tr.getComfort('nope'))
        eq(nil, Tr.getComfort(nil))
        eq(nil, Tr.getComfort(42))
        eq(nil, Tr.getComfort({}))
        eq(nil, Tr.getComfort(true))
    end)
end)

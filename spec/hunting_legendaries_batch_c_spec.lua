-- Run from repo root: `lua spec/hunting_legendaries_batch_c_spec.lua` (or via tools/run-specs.py).
-- hunting-02 B4 (Batch C): the four disabled-region legendaries this block fills in
-- (hennigans_stead, cholla_springs, gaptooth_ridge, rio_bravo). Each entry must load and validate, sit in its own
-- region, share a plain species model, and derive a 3-star cargo pelt row and a bulky trophy row.
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local describe, it, eq, same = T.describe, T.it, T.eq, T.same
local base = here .. '../server/resources/[fh]/fh_hunting/'
local L = dofile(base .. 'shared/legendaries.lua')
local A = dofile(base .. 'shared/animals.lua')
local Tr = dofile(base .. 'shared/trophies.lua')
local regions = require('regions')

-- The four Batch C entries, in region order.
local BATCH = {
    { region = 'hennigans_stead', id = 'legendary_saltbrush_buck',   label = 'Saltbrush Buck',   species = 'a_c_deer_01' },
    { region = 'cholla_springs',  id = 'legendary_cinderjaw_coyote', label = 'Cinderjaw Coyote', species = 'a_c_coyote_01' },
    { region = 'gaptooth_ridge',  id = 'legendary_sandveil_fox',     label = 'Sandveil Fox',     species = 'a_c_fox_01' },
    { region = 'rio_bravo',       id = 'legendary_canyonback_boar',  label = 'Canyonback Boar',  species = 'a_c_boar_01' },
}

describe('hunting legendaries batch C: data files', function()
    it('each batch region loads a valid entry with its own id, label and species', function()
        same({}, L.warnings) -- no file in the ladder (including these four) fails validation
        for _, b in ipairs(BATCH) do
            local e = L.byRegion[b.region]
            assert(e, b.region .. ' has no entry')
            eq(b.id, e.id, b.region)
            eq(b.id, e.chain_id, b.region)
            eq(b.region, e.region_id, b.region)
            eq(b.label, e.label, b.region)
            eq(b.species, e.species_model, b.region)
        end
    end)

    it('each entry uses a species with a plain animal row and no plain animal uses its id', function()
        for _, b in ipairs(BATCH) do
            local e = L.byRegion[b.region]
            assert(A.byModel[e.species_model], b.id .. ': no plain row for ' .. e.species_model)
            assert(not A.byModel[e.id], b.id .. ': id collides with a plain animal key')
            eq(A.byLegendary[e.id], A.byKey[e.id], b.id)
        end
    end)

    it('each entry derives a 3-star cargo pelt row and a bulky trophy row', function()
        local defs = A.itemDefs()
        for _, b in ipairs(BATCH) do
            local e = L.byRegion[b.region]
            local pelt, trophy = 'pelt_' .. b.id, 'trophy_' .. b.id
            eq(pelt, e.pelt.item, b.region)
            eq(trophy, e.trophy.item, b.region)
            local row = A.byKey[b.id]
            assert(row, b.id .. ' has no animal row')
            eq('cargo', row.size_class, b.id)
            eq(3, row.fixedStars, b.id)
            eq(true, row.legendary, b.id)
            eq(pelt, row.pelt, b.id)
            eq(trophy, row.trophy, b.id)
            -- item rows exist and match the data
            assert(defs[pelt], 'no item def for ' .. pelt)
            assert(defs[trophy], 'no item def for ' .. trophy)
            eq('cargo', defs[pelt].size_class, pelt)
            eq(e.pelt.value, defs[pelt].value_base, pelt)
            eq('bulky', defs[trophy].size_class, trophy)
            eq(25, Tr.getComfort(trophy), b.id)
        end
    end)

    it('all four batch regions are disabled today, so their entries are not active', function()
        for _, b in ipairs(BATCH) do
            eq(false, regions.isEnabled(b.region), b.region)
        end
        local active = {}
        for _, e in ipairs(L:active()) do active[e.id] = true end
        for _, b in ipairs(BATCH) do
            eq(nil, active[b.id], b.id .. ' should not be active while its region is disabled')
        end
    end)
end)

T.finish()

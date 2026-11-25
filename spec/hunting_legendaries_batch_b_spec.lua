-- Run from repo root: `lua spec/hunting_legendaries_batch_b_spec.lua` (or via tools/run-specs.py).
-- hunting-02 B3 (Batch B): the five disabled-region legendaries this block fills in
-- (grizzlies_east, grizzlies_west, cumberland_forest, big_valley, tall_trees). Each entry must load and validate,
-- sit in its own region, share a plain species model, and derive a 3-star cargo pelt row and a bulky trophy row.
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local describe, it, eq, same = T.describe, T.it, T.eq, T.same
local base = here .. '../server/resources/[fh]/fh_hunting/'
local L = dofile(base .. 'shared/legendaries.lua')
local A = dofile(base .. 'shared/animals.lua')
local Tr = dofile(base .. 'shared/trophies.lua')
local regions = require('regions')

-- The five Batch B entries, in region order.
local BATCH = {
    { region = 'grizzlies_east',    id = 'legendary_frostmane_moose',  label = 'Legendary Frostmane Moose',  species = 'a_c_moose_01' },
    { region = 'grizzlies_west',    id = 'legendary_palehorn_elk',     label = 'Legendary Palehorn Elk',     species = 'a_c_elk_01' },
    { region = 'cumberland_forest', id = 'legendary_greyhowl_wolf',    label = 'Legendary Greyhowl Wolf',    species = 'a_c_wolf' },
    { region = 'big_valley',        id = 'legendary_copperhide_deer',  label = 'Legendary Copperhide Deer',  species = 'a_c_deer_01' },
    { region = 'tall_trees',        id = 'legendary_embercoat_coyote', label = 'Legendary Embercoat Coyote', species = 'a_c_coyote_01' },
}

describe('hunting legendaries batch B: data files', function()
    it('each batch region loads a valid entry with its own id, label and species', function()
        same({}, L.warnings) -- no file in the ladder (including these five) fails validation
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

    it('all five batch regions are disabled today, so their entries are not active', function()
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

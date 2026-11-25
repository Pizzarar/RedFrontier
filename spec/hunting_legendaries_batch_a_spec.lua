-- Run from repo root: `lua spec/hunting_legendaries_batch_a_spec.lua` (or via tools/run-specs.py).
-- hunting-02 B2 Batch A: the five filled data/legendaries/<region_id>.lua entries (scarlett_meadows, bayou_nwa,
-- great_plains, bluewater_marsh, roanoke_ridge). Each entry must load, validate, sit in its region, reuse a plain
-- animal species, and derive a 3-star cargo pelt row plus a bulky trophy item row.
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local describe, it, eq, same = T.describe, T.it, T.eq, T.same
local base = here .. '../server/resources/[fh]/fh_hunting/'
local L = dofile(base .. 'shared/legendaries.lua')
local A = dofile(base .. 'shared/animals.lua')
local Items = dofile(here .. '../server/resources/[fh]/fh_core/shared/items.lua')
local regions = require('regions')

local BATCH = {
    { region = 'scarlett_meadows', id = 'legendary_redclay_stag',   species = 'a_c_deer_01',      value = 55 },
    { region = 'bayou_nwa',        id = 'legendary_mossback_gator', species = 'a_c_alligator_01', value = 65 },
    { region = 'great_plains',     id = 'legendary_dusthorn_bison', species = 'a_c_buffalo_01',   value = 60 },
    { region = 'bluewater_marsh',  id = 'legendary_brackhide_boar', species = 'a_c_boar_01',      value = 52 },
    { region = 'roanoke_ridge',    id = 'legendary_coalhorn_moose', species = 'a_c_moose_01',     value = 62 },
}

local function entry(b) return L.byRegion[b.region] end

describe('hunting legendaries batch A: data', function()
    it('all five regions hold an entry and the loader reports no warnings', function()
        same({}, L.warnings)
        for _, b in ipairs(BATCH) do
            local e = entry(b)
            assert(e, b.region .. ': missing entry')
            eq(b.id, e.id, b.region)
            eq(b.region, e.region_id, b.id)
            eq(b.id, e.chain_id, b.id)
        end
    end)
    it('each entry reuses a plain animal species and an id no plain animal uses', function()
        same({}, A.warnings)
        for _, b in ipairs(BATCH) do
            local e = entry(b)
            eq(b.species, e.species_model, b.id)
            assert(A.byModel[b.species], b.id .. ': no plain row for ' .. b.species)
            eq(A.byLegendary[b.id], A.byKey[b.id], b.id)
        end
    end)
    it('each entry has a valid pelt and trophy shape', function()
        for _, b in ipairs(BATCH) do
            local e = entry(b)
            eq('pelt_' .. b.id, e.pelt.item, b.id)
            eq('trophy_' .. b.id, e.trophy.item, b.id)
            eq(25, e.trophy.comfort, b.id)
            eq(b.value, e.pelt.value, b.id)
            assert(e.pelt.value > 0 and e.pelt.weight > 0, b.id)
        end
    end)
end)

describe('hunting legendaries batch A: derived rows', function()
    local defs = A.itemDefs()
    it('each pelt and trophy gets an item row that passes the fh_core validator', function()
        for _, b in ipairs(BATCH) do
            local r = A.byKey[b.id]
            assert(r, b.id .. ': no animal row')
            eq('pelt_' .. b.id, r.pelt, b.id)
            eq('cargo', r.size_class, b.id)
            eq(3, r.fixedStars, b.id)
            eq(true, r.legendary, b.id)
            eq('trophy_' .. b.id, r.trophy, b.id)
            local pelt, trophy = defs['pelt_' .. b.id], defs['trophy_' .. b.id]
            assert(pelt, b.id .. ': no pelt item row')
            assert(trophy, b.id .. ': no trophy item row')
            local ok, err = Items.validate(pelt)
            assert(ok, b.id .. ' pelt: ' .. tostring(err))
            ok, err = Items.validate(trophy)
            assert(ok, b.id .. ' trophy: ' .. tostring(err))
            eq('cargo', pelt.size_class, b.id)
            eq('bulky', trophy.size_class, b.id)
        end
    end)
end)

describe('hunting legendaries batch A: region gate', function()
    it('the three enabled regions are active, the two disabled are not', function()
        local active = {}
        for _, e in ipairs(L:active()) do active[e.id] = true end
        for _, b in ipairs(BATCH) do
            eq(regions.isEnabled(b.region), active[b.id] ~= nil, b.id)
        end
        eq(true, regions.isEnabled('scarlett_meadows'))
        eq(true, regions.isEnabled('bayou_nwa'))
        eq(true, regions.isEnabled('great_plains'))
        eq(false, regions.isEnabled('bluewater_marsh'))
        eq(false, regions.isEnabled('roanoke_ridge'))
    end)
end)

T.finish()

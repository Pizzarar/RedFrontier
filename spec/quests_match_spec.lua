-- Run from repo root: `lua spec/quests_match_spec.lua` (or via tools/run-specs.py).
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local describe, it, eq = T.describe, T.it, T.eq
local M = dofile(here .. '../server/resources/[fh]/fh_quests/shared/match.lua')

local function yes(where, payload) local ok, f = M.where(where, payload); assert(ok, 'expected match, failed on ' .. tostring(f)) end
local function no(where, payload) assert(not M.where(where, payload), 'expected no match') end

describe('quests match: eq', function()
    it('string, number and boolean compare by value', function()
        yes({ animal = 'wolf' }, { animal = 'wolf' })
        no({ animal = 'wolf' }, { animal = 'fox' })
        yes({ quality = 3 }, { quality = 3 })
        yes({ legendary = true }, { legendary = true })
        no({ legendary = true }, { legendary = false })
    end)
    it('no coercion between number and string', function()
        no({ quality = 3 }, { quality = '3' })
    end)
    it('table eq form behaves the same', function()
        yes({ animal = { eq = 'wolf' } }, { animal = 'wolf' })
        no({ animal = { eq = 'wolf' } }, { animal = 'fox' })
    end)
    it('a required field that is absent fails', function()
        no({ animal = 'wolf' }, {})
        no({ animal = { eq = 'wolf' } }, {})
        no({ quality = { min = 1 } }, {})
    end)
    it('every field must pass (AND) and the first failing field is reported in sorted order', function()
        local ok, f = M.where({ animal = 'wolf', quality = { min = 2 } }, { animal = 'fox', quality = 1 })
        eq(false, ok); eq('animal', f)
        ok, f = M.where({ animal = 'wolf', quality = { min = 2 } }, { animal = 'wolf', quality = 1 })
        eq(false, ok); eq('quality', f)
    end)
    it('nil where matches any table payload; a non-table payload never matches', function()
        yes(nil, {})
        no(nil, nil)
        no({ a = 1 }, 'x')
    end)
end)

describe('quests match: min / max / any', function()
    it('min is inclusive', function()
        yes({ quality = { min = 2 } }, { quality = 2 })
        yes({ quality = { min = 2 } }, { quality = 3 })
        no({ quality = { min = 2 } }, { quality = 1 })
    end)
    it('max is inclusive', function()
        yes({ price = { max = 50 } }, { price = 50 })
        no({ price = { max = 50 } }, { price = 51 })
    end)
    it('min and max together form a band', function()
        local w = { quality = { min = 2, max = 3 } }
        yes(w, { quality = 2 }); yes(w, { quality = 3 }); no(w, { quality = 1 }); no(w, { quality = 4 })
    end)
    it('bounds never pass a non-number or NaN', function()
        no({ quality = { min = 2 } }, { quality = '3' })
        no({ quality = { max = 2 } }, { quality = 0 / 0 })
    end)
    it('any matches one of the list', function()
        local w = { animal = { any = { 'wolf', 'coyote' } } }
        yes(w, { animal = 'coyote' })
        no(w, { animal = 'fox' })
    end)
end)

describe('quests match: optional fields', function()
    local w = { animal = { optional = true, eq = 'wolf' } }
    it('absent field passes', function() yes(w, {}) end)
    it('present field that matches passes', function() yes(w, { animal = 'wolf' }) end)
    it('present field that mismatches fails', function() no(w, { animal = 'fox' }) end)
    it('optional works with min/max/any', function()
        yes({ q = { optional = true, min = 2 } }, {})
        no({ q = { optional = true, min = 2 } }, { q = 1 })
        yes({ a = { optional = true, any = { 'x', 'y' } } }, { a = 'y' })
        no({ a = { optional = true, any = { 'x', 'y' } } }, { a = 'z' })
    end)
end)

describe('quests match: hunt_request on fh:hunting:pelt_sold (before and after Hunting H3)', function()
    -- "Sell a 2-star or better bulky wolf pelt"; animal/size_class only enforced once the payload carries them.
    local where = {
        animal = { optional = true, eq = 'wolf' },
        size_class = { optional = true, eq = 'bulky' },
        quality = { min = 2 },
    }
    it('without animal/size_class: falls back to quality only', function()
        yes(where, { citizenid = 'C1', item_id = 'pelt_wolf', quality = 2, price = 7, region_id = 'heartlands' })
        no(where, { citizenid = 'C1', item_id = 'pelt_wolf', quality = 1, price = 3, region_id = 'heartlands' })
    end)
    it('with animal/size_class: they must match too', function()
        local base = { citizenid = 'C1', item_id = 'pelt_wolf', animal = 'wolf', size_class = 'bulky', quality = 3,
            price = 12, region_id = 'heartlands' }
        yes(where, base)
        local fox = {}
        for k, v in pairs(base) do fox[k] = v end
        fox.animal, fox.item_id = 'fox', 'pelt_fox'
        no(where, fox)
        local cargo = {}
        for k, v in pairs(base) do cargo[k] = v end
        cargo.size_class = 'cargo'
        no(where, cargo)
        base.quality = 1
        no(where, base)
    end)
end)

describe('quests match: credits (citizen check)', function()
    it('same citizenid credits, another does not', function()
        eq(true, M.credits({ citizenid = 'C1' }, 'C1'))
        eq(false, M.credits({ citizenid = 'C2' }, 'C1'))
    end)
    it('no citizenid (only src, unresolved) credits nobody', function()
        eq(false, M.credits({ src = 4 }, 'C1'))
        eq(false, M.credits({ camp_id = 'x', region_id = 'heartlands' }, 'C1'))
    end)
    it('participants list (camp_cleared after Q0a) credits each listed citizen', function()
        local p = { camp_id = 'x', participants = { 'C1', 'C3' } }
        eq(true, M.credits(p, 'C1')); eq(true, M.credits(p, 'C3')); eq(false, M.credits(p, 'C2'))
    end)
    it('empty or bad citizenid never credits', function()
        eq(false, M.credits({ citizenid = '' }, ''))
        eq(false, M.credits({}, nil))
    end)
end)

describe('quests match: validate', function()
    local function bad(where, code)
        local ok, err = M.validate(where)
        eq(false, ok)
        if code then assert(err:find(code, 1, true), 'expected ' .. code .. ', got ' .. tostring(err)) end
    end
    it('accepts every documented form', function()
        assert(M.validate(nil))
        assert(M.validate({ a = 'x', b = 2, c = true, d = { eq = 'y' }, e = { min = 1 }, f = { max = 2 },
            g = { min = 1, max = 2 }, h = { any = { 'p', 'q' } }, i = { optional = true, eq = 'z' } }))
    end)
    it('rejects malformed predicates with the field named', function()
        bad({ a = {} }, 'fh_empty_predicate@a')
        bad({ a = { optional = true } }, 'fh_empty_predicate@a')
        bad({ a = { optional = 'yes', eq = 1 } }, 'fh_bad_optional')
        bad({ a = { foo = 1 } }, 'fh_unknown_predicate_key:foo@a')
        bad({ a = { min = 'x' } }, 'fh_bad_min')
        bad({ a = { max = 0 / 0 } }, 'fh_bad_max')
        bad({ a = { min = 3, max = 1 } }, 'fh_min_gt_max')
        bad({ a = { any = {} } }, 'fh_bad_any')
        bad({ a = { any = { {} } } }, 'fh_bad_any')
        bad({ a = { eq = 1, min = 0 } }, 'fh_eq_exclusive')
        bad({ a = { any = { 1 }, min = 0 } }, 'fh_any_exclusive')
        bad({ a = function() end }, 'fh_bad_predicate')
        bad({ [1] = 'x' }, 'fh_bad_where_field')
        bad('x', 'fh_bad_where')
    end)
end)

T.finish()

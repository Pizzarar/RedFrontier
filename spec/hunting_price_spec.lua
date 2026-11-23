-- Run from repo root: `lua spec/hunting_price_spec.lua` (or via tools/run-specs.py).
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local describe, it, eq = T.describe, T.it, T.eq
local base = here .. '../server/resources/[fh]/fh_hunting/'
local cfg = dofile(base .. 'config.lua')
local A = dofile(base .. 'shared/animals.lua')
local P = dofile(base .. 'shared/price.lua')

describe('hunting price: star multiplier', function()
    it('1 star is 0.4x, 2 stars 1.0x, 3 stars 1.8x', function()
        eq(40, P.price(100, 1, false, cfg))
        eq(100, P.price(100, 2, false, cfg))
        eq(180, P.price(100, 3, false, cfg))
    end)
    it('rounds to a whole number', function()
        eq(6, P.price(14, 1, false, cfg))   -- 5.6
        eq(25, P.price(14, 3, false, cfg))  -- 25.2
        eq(1, P.price(3, 1, false, cfg))    -- 1.2
    end)
    it('a zero base pays zero', function() eq(0, P.price(0, 3, true, cfg)) end)
end)

describe('hunting price: legendary x4', function()
    it('multiplies on top of the star multiplier', function()
        eq(720, P.price(100, 3, true, cfg))
        eq(400, P.price(100, 2, true, cfg))
        eq(160, P.price(100, 1, true, cfg))
    end)
    it('the legendary bear 3 star pelt pays 60 x 1.8 x 4', function()
        eq(432, P.price(A.byKey.legendary_bear.value, 3, true, cfg))
    end)
end)

describe('hunting price: config driven and bad input', function()
    it('follows the configured multipliers', function()
        local c = { QualityMult = { [1] = 1, [2] = 2, [3] = 3 }, LegendaryMult = 10 }
        eq(20, P.price(10, 2, false, c))
        eq(300, P.price(10, 3, true, c))
    end)
    it('rejects bad stars and bad base without paying', function()
        eq('fh_bad_stars', select(2, P.price(100, 0, false, cfg)))
        eq('fh_bad_stars', select(2, P.price(100, 4, false, cfg)))
        eq('fh_bad_stars', select(2, P.price(100, nil, false, cfg)))
        eq('fh_bad_base', select(2, P.price(-1, 2, false, cfg)))
        eq('fh_bad_base', select(2, P.price('100', 2, false, cfg)))
        eq(nil, (P.price(100, 5, false, cfg)))
    end)
end)

T.finish()

-- Run from repo root: `lua spec/hunting_sell_ui_spec.lua` (or via tools/run-specs.py).
-- The pure fh_ui `trapper` screen builders (shared/sell.lua): the screen data wrapper and the success notice.
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local describe, it, eq, same = T.describe, T.it, T.eq, T.same
local base = here .. '../server/resources/[fh]/fh_hunting/'
local cfg = dofile(base .. 'config.lua')
FhHuntingWagon = dofile(base .. 'shared/wagon.lua') -- the shared xyz reader sell.lua asserts at load
local S = dofile(base .. 'shared/sell.lua')

describe('hunting sell UI: pure screen data and notice builders', function()
    it('soldNotice formats the success message for one, two and three stars', function()
        eq('Sold Deer pelt (1 star) for $6.', S.soldNotice({ label = 'Deer pelt', stars = 1, price = 6 }))
        eq('Sold Deer pelt (2 stars) for $14.', S.soldNotice({ label = 'Deer pelt', stars = 2, price = 14 }))
        eq('Sold Deer pelt (3 stars) for $25.', S.soldNotice({ label = 'Deer pelt', stars = 3, price = 25 }))
    end)
    it('screenData sets the title from cfg.Trapper.label and passes rows through', function()
        local rows = { { container = 'saddlebag', slot = 1, item = 'pelt_deer', label = 'Deer pelt', stars = 3, legendary = false, price = 25 } }
        same({ title = 'Trapper', rows = rows }, S.screenData(cfg, rows))
    end)
    it('screenData without rows (e.g. walked out of range) omits rows and adds the notice', function()
        same({ title = 'Trapper', notice = 'Go to the trapper to sell.', notice_kind = 'error' },
            S.screenData(cfg, nil, 'Go to the trapper to sell.', 'error'))
    end)
    it('screenData omits notice_kind when nil, and title falls back without a Trapper config', function()
        same({ title = 'Trapper', rows = {}, notice = 'Sold for $25.' }, S.screenData(cfg, {}, 'Sold for $25.'))
        same({ title = 'Trapper' }, S.screenData({}, nil))
    end)
end)

T.finish()

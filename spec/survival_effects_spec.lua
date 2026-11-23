-- Run from repo root: `lua spec/survival_effects_spec.lua` (or via tools/run-specs.py).
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
package.path = here .. '../server/resources/[fh]/fh_survival/shared/?.lua;' .. package.path
local case = T.it
local E = require('effects')

case('notify mode: text with level, no natives', function()
    for l = 1, 3 do
        local p = E.params(l, 'notify')
        assert(p.level == l and p.native == false)
        assert(p.notify and p.notify:find('level ' .. l .. '/3', 1, true))
        assert(p.staminaRegen == 1.0 and p.deadeyeRegen == 1.0 and p.clipset == nil)
    end
    assert(E.params(0, 'notify').notify == nil)
end)

case('unknown or nil mode falls back to the safe notify path', function()
    assert(E.params(3, nil).native == false)
    assert(E.params(3, 'Native').native == false)
    assert(E.params(3, 'bogus', { Clipset = 'x' }).clipset == nil)
end)

case('native mode: regen reduced by level, clipset only at level 3', function()
    local cfg = { Clipset = 'some_clipset' }
    assert(E.params(0, 'native', cfg).staminaRegen == 1.0)
    assert(E.params(1, 'native', cfg).staminaRegen == 0.85 and E.params(1, 'native', cfg).clipset == nil)
    assert(E.params(2, 'native', cfg).deadeyeRegen == 0.7 and E.params(2, 'native', cfg).clipset == nil)
    local p3 = E.params(3, 'native', cfg)
    assert(p3.native == true and p3.staminaRegen == 0.5 and p3.clipset == 'some_clipset')
    assert(E.params(3, 'native', {}).clipset == nil, 'no clipset configured = none')
end)

case('regen is clamped: never zero, never boosted, junk = normal', function()
    assert(E.params(3, 'native', { Regen = { [3] = 0 } }).staminaRegen == 1.0)
    assert(E.params(3, 'native', { Regen = { [3] = 5 } }).staminaRegen == 1.0)
    assert(E.params(3, 'native', { Regen = { [3] = 'x' } }).staminaRegen == 1.0)
    assert(E.params(3, 'native', { Regen = { [3] = 0.2 } }).staminaRegen == 0.2)
end)

case('level input is clamped and junk is 0', function()
    assert(E.params(9, 'notify').level == 3)
    assert(E.params(-2, 'notify').level == 0)
    assert(E.params('x', 'notify').level == 0)
    assert(E.params(0 / 0, 'notify').level == 0)
    assert(E.params(1.9, 'notify').level == 1)
end)

case('custom text overrides default', function()
    assert(E.params(2, 'notify', { Text = { [2] = 'Hungry.' } }).notify == 'Hungry. (level 2/3)')
end)

case('shouldNotify only on a change to a non-zero level', function()
    assert(E.shouldNotify(0, 1) and E.shouldNotify(1, 3) and E.shouldNotify(3, 2))
    assert(not E.shouldNotify(2, 2) and not E.shouldNotify(2, 0) and not E.shouldNotify(nil, 0))
end)

T.finish()

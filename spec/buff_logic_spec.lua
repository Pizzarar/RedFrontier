-- Run from repo root: `lua spec/buff_logic_spec.lua` (or via busted).
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
package.path = here .. '../server/resources/[fh]/fh_buffs/shared/?.lua;' .. package.path
local case = T.it
local logic = require('buff_logic')

local caps = { well_fed = 1.25, rested = 1.2 }

case('apply creates a buff', function()
    local st = {}
    local ok, r = logic.apply(st, caps, 'well_fed', 1.1, 60, 100)
    assert(ok and r.magnitude == 1.1 and r.expires_at == 160 and r.refreshed == false)
end)
case('magnitude is capped per buff', function()
    local st = {}
    local ok, r = logic.apply(st, caps, 'well_fed', 9, 60, 0)
    assert(ok and r.magnitude == 1.25)
end)
case('same buff refreshes duration and keeps the max magnitude', function()
    local st = {}
    logic.apply(st, caps, 'well_fed', 1.2, 60, 0)
    local ok, r = logic.apply(st, caps, 'well_fed', 1.1, 30, 20) -- lower mag, still active
    assert(ok and r.refreshed == true)
    assert(r.magnitude == 1.2, 'keeps max')
    assert(r.expires_at == 50, 'duration refreshed to now+duration')
    ok, r = logic.apply(st, caps, 'well_fed', 1.25, 10, 25)
    assert(r.magnitude == 1.25 and r.expires_at == 35)
end)
case('different buffs stack', function()
    local st = {}
    logic.apply(st, caps, 'well_fed', 1.1, 60, 0)
    logic.apply(st, caps, 'rested', 1.1, 60, 0)
    local snap = logic.snapshot(st, 1)
    assert(snap.well_fed and snap.rested)
end)
case('an expired buff is replaced, not max-merged', function()
    local st = {}
    logic.apply(st, caps, 'well_fed', 1.25, 10, 0)
    local ok, r = logic.apply(st, caps, 'well_fed', 1.1, 10, 50) -- old one expired at 10
    assert(ok and r.refreshed == false and r.magnitude == 1.1)
end)
case('expire drops finished buffs and get/snapshot hides them', function()
    local st = {}
    logic.apply(st, caps, 'well_fed', 1.1, 10, 0)
    logic.apply(st, caps, 'rested', 1.1, 100, 0)
    local gone = logic.expire(st, 10)
    assert(#gone == 1 and gone[1] == 'well_fed')
    local snap = logic.snapshot(st, 11)
    assert(snap.well_fed == nil and snap.rested ~= nil)
end)
case('invalid input is refused without touching state', function()
    local st = {}
    local cases = {
        { 'nope', 1, 10, 'unknown_buff' },
        { 'well_fed', 0, 10, 'invalid_magnitude' },
        { 'well_fed', -1, 10, 'invalid_magnitude' },
        { 'well_fed', 1, 0, 'invalid_duration' },
        { 'well_fed', 1, -5, 'invalid_duration' },
        { 'well_fed', '1', 10, 'invalid_magnitude' },
        { 'well_fed', math.huge, 10, 'invalid_magnitude' },
        { 'well_fed', 0/0, 10, 'invalid_magnitude' },
        { 'well_fed', 1, math.huge, 'invalid_duration' },
        { nil, 1, 10, 'unknown_buff' },
    }
    for _, c in ipairs(cases) do
        local ok, err = logic.apply(st, caps, c[1], c[2], c[3], 0)
        assert(ok == false and err == c[4], tostring(c[4]))
    end
    assert(next(st) == nil)
end)

T.finish()

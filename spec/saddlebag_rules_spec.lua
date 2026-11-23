-- Run from repo root: `lua spec/saddlebag_rules_spec.lua` (or via tools/run-specs.py).
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local case = T.it
local R = dofile(here .. '../server/resources/[fh]/fh_core/shared/saddlebag_rules.lua')

local me = { x = 0, y = 0, z = 0 }
local horse = { exists = true, isHorse = true, coords = { x = 2, y = 0, z = 0 } }
local function why(ok, r) return not ok and r or nil end

case('stashId: per character, nil without one', function()
    assert(R.stashId('ABC123') == 'fh:saddle:ABC123')
    assert(R.stashId('') == nil and R.stashId(nil) == nil and R.stashId(5) == nil)
end)
case('canAccess: horse within reach', function()
    assert(R.canAccess('C1', horse, me, 3.5))
    assert(R.canAccess('C1', { exists = true, isHorse = true, coords = { x = 3.5, y = 0, z = 0 } }, me, 3.5)) -- edge
end)
case('canAccess: mounted (same position) passes', function()
    assert(R.canAccess('C1', { exists = true, isHorse = true, coords = me }, me, 3.5))
end)
case('canAccess: too far', function()
    assert(why(R.canAccess('C1', { exists = true, isHorse = true, coords = { x = 3.6, y = 0, z = 0 } }, me, 3.5)) == 'fh_out_of_reach')
    assert(why(R.canAccess('C1', { exists = true, isHorse = true, coords = { x = 0, y = 0, z = 9 } }, me, 3.5)) == 'fh_out_of_reach')
end)
case('canAccess: no entity, not a horse, no character', function()
    assert(why(R.canAccess('C1', nil, me, 3.5)) == 'fh_no_horse')
    assert(why(R.canAccess('C1', { exists = false }, me, 3.5)) == 'fh_no_horse')
    assert(why(R.canAccess('C1', { exists = true, isHorse = false, coords = me }, me, 3.5)) == 'fh_not_a_horse')
    assert(why(R.canAccess(nil, horse, me, 3.5)) == 'fh_no_character')
end)
case('canAccess: bad coords or reach fail closed', function()
    assert(why(R.canAccess('C1', { exists = true, isHorse = true, coords = { x = 0 / 0, y = 0, z = 0 } }, me, 3.5)) == 'fh_no_player_coords')
    assert(why(R.canAccess('C1', horse, nil, 3.5)) == 'fh_no_player_coords')
    assert(why(R.canAccess('C1', horse, me, nil)) == 'fh_out_of_reach')
end)

T.finish()

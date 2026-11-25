-- fh_anim pure logic + table shape. Run from repo root via tools/run-specs.py.
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local res = here .. '../server/resources/[fh]/fh_anim/'
local case, eq = T.it, T.eq
local logic = dofile(res .. 'shared/anim_logic.lua')
local tbl = dofile(res .. 'shared/anims.lua')

local KEYS = { 'skin', 'gather', 'eat', 'drink', 'craft', 'cook', 'chest_open', 'trough', 'plant', 'harvest', 'refill', 'wash' }

case('table has every key with a valid shape', function()
    for _, k in ipairs(KEYS) do
        local e = tbl[k]
        assert(e, 'missing ' .. k)
        assert(type(e.ms) == 'number' and e.ms > 0, k .. ' ms')
        if e.scenario then assert(type(e.scenario) == 'string', k)
        else assert(type(e.dict) == 'string' and type(e.clip) == 'string' and (e.flag == 31 or e.flag == 49), k) end
    end
end)

case('lookup: flag off, unknown key, bad input -> nil', function()
    eq(nil, logic.lookup(tbl, false, 'eat'), 'flag off')
    eq(nil, logic.lookup(tbl, true, 'nope'), 'unknown')
    eq(nil, logic.lookup(tbl, true, nil), 'nil key')
    eq(nil, logic.lookup(nil, true, 'eat'), 'nil table')
    eq(nil, logic.lookup({ x = { dict = 'd' } }, true, 'x'), 'malformed')
    eq(tbl.eat, logic.lookup(tbl, true, 'eat'))
end)

case('guard blocks each unsafe state, passes clean', function()
    assert(logic.guard({}))
    for _, k in ipairs({ 'mounted', 'inVehicle', 'swimming', 'dead', 'ragdoll', 'inScenario' }) do
        local ok, why = logic.guard({ [k] = true })
        eq(false, ok, k)
        eq(k, why, k)
    end
end)

case('isOurs / shouldClear only for our active anim', function()
    local a = { key = 'skin', id = 3 }
    assert(logic.isOurs(a, { key = 'skin', id = 3 }))
    assert(not logic.isOurs(a, { key = 'skin', id = 4 }), 'newer anim replaced it')
    assert(not logic.isOurs(nil, a))
    assert(logic.shouldClear(a, 'skin', true))
    assert(logic.shouldClear(a, nil, true))
    assert(not logic.shouldClear(a, 'gather', true), 'other key')
    assert(not logic.shouldClear(a, 'skin', false), 'not playing any more')
    assert(not logic.shouldClear(nil, 'skin', true), 'nothing active')
end)

case('seq: newer start cancels an older yielding begin (eat vs skin)', function()
    local S = logic.newState()
    local eat = logic.claim(S, 'eat')      -- play('eat') yields in requestAnimDict
    local skin = logic.claim(S, 'skin')    -- start('skin') runs meanwhile
    assert(not logic.isCurrent(S, eat), 'eat must not overwrite skin')
    assert(logic.isCurrent(S, skin))
end)

case('seq: stop(key) cancels a yielding begin of that key only', function()
    local S = logic.newState()
    local craft = logic.claim(S, 'craft')
    eq(false, logic.invalidate(S, 'skin'), 'other key: no-op')
    assert(logic.isCurrent(S, craft))
    eq(true, logic.invalidate(S, 'craft'), 'stop(craft)')
    assert(not logic.isCurrent(S, craft), 'craft must not start after stop')
    eq(false, logic.invalidate(S, 'craft'), 'nothing left to stop')
    local again = logic.claim(S, 'craft')
    assert(logic.isCurrent(S, again) and not logic.isCurrent(S, craft), 'stale token stays stale')
end)

case('post-yield guard re-check catches mount/death', function()
    local ok, why = logic.guard({ mounted = true })
    eq(false, ok); eq('mounted', why)
    ok, why = logic.guard({ dead = true })
    eq(false, ok); eq('dead', why)
end)

case('FXServer load path sets globals (stub GetCurrentResourceName)', function()
    GetCurrentResourceName = function() return 'fh_anim' end
    local r1 = dofile(res .. 'shared/anim_logic.lua')
    local r2 = dofile(res .. 'shared/anims.lua')
    local gl, gt = FhAnimLogic, FhAnimTable
    GetCurrentResourceName, FhAnimLogic, FhAnimTable = nil, nil, nil
    eq(nil, r1, 'no return in-game'); eq(nil, r2)
    assert(gl and gl.lookup and gl.guard, 'FhAnimLogic global')
    assert(gt and gt.skin, 'FhAnimTable global')
end)

T.finish()

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

case('config: Enabled is true by default', function()
    local env = {}
    assert(loadfile(res .. 'config.lua', 't', env))()
    eq(true, env.Config.Enabled)
end)

local function clientRig(reqAnimDict, overrides)
    overrides = overrides or {}
    local exported = {}
    local env = setmetatable({
        FhAnimLogic = logic,
        FhAnimTable = tbl,
        Config = { Enabled = true },
        PlayerPedId = function() return 1 end,
        IsPedOnMount = function() return false end,
        IsPedInAnyVehicle = function() return false end,
        IsPedSwimming = function() return false end,
        IsEntityDead = function() return false end,
        IsPedRagdoll = function() return false end,
        IsPedActiveInScenario = function() return false end,
        IsEntityPlayingAnim = function() return false end,
        ClearPedTasks = function() end,
        TaskStartScenarioInPlaceHash = overrides.TaskStartScenarioInPlaceHash or function() end,
        joaat = function(s) return 12345 end,
        CreateThread = function(fn) fn() end,
        Wait = function(ms) end,
        lib = {
            requestAnimDict = reqAnimDict or function(dict, timeout) return dict end,
            playAnim = function(...) end,
        },
        exports = function(name, fn) exported[name] = fn end,
        RegisterNetEvent = function() end,
    }, { __index = _G })
    env._G = env
    local fn, err = loadfile(res .. 'client/main.lua', 't', env)
    assert(fn, err)()
    return exported, env
end

case('client: requestAnimDict error returns false, no throw, claim released', function()
    local exp = clientRig(function(dict, timeout)
        error("attempted to load invalid animDict '" .. tostring(dict) .. "'")
    end)
    eq(false, exp.play('eat'), 'play returns false on requestAnimDict error')
    eq(false, exp.stop('eat'), 'claim released after play failure (nothing to stop)')
    eq(false, exp.start('eat'), 'start returns false on requestAnimDict error')
    eq(false, exp.stop('eat'), 'claim released after start failure (nothing to stop)')
end)

case('client: requestAnimDict timeout returns false, no throw, timeout <= 1s, claim released', function()
    local observedTimeout = nil
    local exp = clientRig(function(dict, timeout)
        observedTimeout = timeout
        error("failed to load animDict within timeout")
    end)
    eq(false, exp.play('eat'), 'play returns false on timeout')
    eq(1000, observedTimeout, 'timeout capped to 1000ms')
    eq(false, exp.stop('eat'), 'claim released after play timeout')
    observedTimeout = nil
    eq(false, exp.start('eat'), 'start returns false on timeout')
    eq(1000, observedTimeout, 'timeout capped to 1000ms')
    eq(false, exp.stop('eat'), 'claim released after start timeout')
end)

case('client: scenario native error does not throw out of play/start', function()
    local exp = clientRig(nil, {
        TaskStartScenarioInPlaceHash = function() error('scenario native failed') end
    })
    eq(false, exp.play('skin'), 'play returns false on scenario native throw')
    eq(false, exp.start('skin'), 'start returns false on scenario native throw')
end)

T.finish()

-- Run from repo root: `lua spec/cargo_wheel_spec.lua` (or via tools/run-specs.py).
-- R2: wheel break roll (pure, injected RNG), speed sanity, repair planning/progress, holder lookup, native gating.
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local case = T.it
local R = dofile(here .. '../server/resources/[fh]/fh_cargo/shared/cargo_rules.lua')

local function rng(v) return function() return v end end

case('breakChance: zero when stopped or crawling, rises with speed', function()
    assert(R.breakChance({ tier = 't2', speed = 0, offRoad = false, loadFraction = 0 }) == 0)
    assert(R.breakChance({ tier = 't2', speed = R.WHEEL.minSpeed - 0.01 }) == 0)
    local slow = R.breakChance({ tier = 't2', speed = 2 })
    local fast = R.breakChance({ tier = 't2', speed = 7 })
    assert(slow > 0 and fast > slow, 'faster = riskier')
end)

case('breakChance: off-road and load both raise it; always within 0..1', function()
    local base = R.breakChance({ tier = 't2', speed = 6, offRoad = false, loadFraction = 0 })
    local off = R.breakChance({ tier = 't2', speed = 6, offRoad = true, loadFraction = 0 })
    local full = R.breakChance({ tier = 't2', speed = 6, offRoad = false, loadFraction = 1 })
    assert(off > base and full > base)
    local worst = R.breakChance({ tier = 't1', speed = 1e9, offRoad = true, loadFraction = 99 })
    assert(worst >= 0 and worst <= 1, 'clamped, got ' .. worst)
    assert(R.breakChance({ tier = 'nope', speed = 5 }) == 0, 'unknown tier never breaks')
    assert(R.breakChance({ tier = 't2', speed = 0 / 0 }) == 0, 'NaN speed is ignored')
    assert(R.breakChance({ tier = 't2', speed = 'fast' }) == 0, 'non-number speed is ignored')
    assert(R.breakChance({ tier = 't2', speed = 6, loadFraction = -5 }) == R.breakChance({ tier = 't2', speed = 6 }),
        'negative load clamps to empty')
end)

case('rollWheelBreak: deterministic with injected RNG', function()
    local p = { tier = 't2', speed = 6, offRoad = true, loadFraction = 1 }
    local c = R.breakChance(p)
    assert(c > 0 and c < 1)
    assert(R.rollWheelBreak(p, rng(c - 1e-9)) == true)
    assert(R.rollWheelBreak(p, rng(c)) == false, 'rng must be strictly below the chance')
    assert(R.rollWheelBreak(p, rng(0.999999)) == false)
    assert(R.rollWheelBreak({ tier = 't2', speed = 0 }, rng(0)) == false, 'zero chance never breaks, even at rng 0')
    assert(R.rollWheelBreak(p, nil) == false, 'no RNG = no break')
end)

case('sanitizeSpeed: clamps reported speed to what the tier can plausibly do', function()
    local cap = R.TIERS.t2.speed * R.WHEEL.speedSlack
    assert(R.sanitizeSpeed(5, 't2') == 5)
    assert(R.sanitizeSpeed(999, 't2') == cap)
    assert(R.sanitizeSpeed(-3, 't2') == 0)
    assert(R.sanitizeSpeed('9', 't2') == nil and R.sanitizeSpeed(nil, 't2') == nil and R.sanitizeSpeed(0 / 0, 't2') == nil)
    assert(R.sanitizeSpeed(5, 'zz') == nil)
end)

case('loadFraction: grams over tier max, clamped', function()
    assert(R.loadFraction('t1', 60000) == 0.5)
    assert(R.loadFraction('t1', 9e9) == 1 and R.loadFraction('t1', -1) == 0 and R.loadFraction('zz', 1) == 0)
end)

case('speed cap: broken wheel caps below the tier cap; fixed wagon is unchanged', function()
    local ok = R.effectiveSpeedLimit('t2', 0, false)
    local broken = R.effectiveSpeedLimit('t2', 0, true)
    assert(ok == R.TIERS.t2.speed)
    assert(broken < ok and broken > 0)
    assert(R.effectiveSpeedLimit('t2', 300000, true) < R.speedLimit('t2', 300000), 'load penalty still applies')
end)

case('nativeBreakAllowed: only when the spike gate is open', function()
    assert(R.nativeBreakAllowed(true) == false, 'gated = state + speed cap only')
    assert(R.nativeBreakAllowed(false) == true)
    assert(R.nativeBreakAllowed(nil) == false, 'unknown = gated')
end)

local me = { x = 0, y = 0, z = 0 }
local function rp(over)
    local p = {
        citizenid = 'C1', playerCoords = me, hasHammer = true, hasWheel = true,
        wagon = { id = 'C1:t2', owner = 'C1', tier = 't2', coords = { x = 2, y = 0, z = 0 }, broken = true },
    }
    for k, v in pairs(over or {}) do p[k] = v end
    return p
end
local function why(p) local ok, r = R.planRepair(p); return ok and 'ok' or r end

case('planRepair: needs own, broken wagon in reach, hammer and a wheel', function()
    assert(why(rp()) == 'ok')
    assert(why(rp({ wagon = false })) == 'fh_no_wagon')
    assert(why(rp({ citizenid = 'C2' })) == 'fh_not_owner')
    assert(why(rp({ playerCoords = { x = 50, y = 0, z = 0 } })) == 'fh_out_of_reach')
    assert(why(rp({ wagon = { id = 'C1:t2', owner = 'C1', tier = 't2', coords = { x = 2, y = 0, z = 0 }, broken = false } })) == 'fh_wheel_ok')
    assert(why(rp({ hasHammer = false })) == 'fh_need_hammer')
    assert(why(rp({ hasWheel = false })) == 'fh_not_enough')
end)

case('repairStep: continue, done after the duration, cancelled when the player walks away', function()
    local s = { startedAt = 1000, duration = 5000, startCoords = me }
    assert(R.repairStep(s, 2000, me) == 'continue')
    assert(R.repairStep(s, 5999, me) == 'continue')
    assert(R.repairStep(s, 6000, me) == 'done')
    assert(R.repairStep(s, 2000, { x = R.WHEEL.repairMoveMax + 1, y = 0, z = 0 }) == 'cancel')
    assert(R.repairStep(s, 2000, { x = R.WHEEL.repairMoveMax - 0.1, y = 0, z = 0 }) == 'continue')
    assert(R.repairStep(s, 2000, nil) == 'cancel', 'no position = cancel')
    local w, reason = R.repairStep(s, 2000, me, { x = 40, y = 0, z = 0 }, 5.0)
    assert(w == 'cancel' and reason == 'fh_out_of_reach', 'wagon out of reach cancels')
end)

case('repairFinalCheck: nil wagon coords cancel (nothing consumed); rechecks broken, hammer, wheel', function()
    local function c(o) local t = { broken = true, wagonCoords = me, hasHammer = true, hasWheel = true }
        for k, v in pairs(o or {}) do t[k] = v end return t end
    assert(R.repairFinalCheck(c()))
    local ok, r = R.repairFinalCheck({ broken = true, hasHammer = true, hasWheel = true })
    assert(ok == false and r == 'fh_no_wagon')
    ok, r = R.repairFinalCheck(c({ broken = false })); assert(ok == false and r == 'fh_wheel_ok')
    ok, r = R.repairFinalCheck(c({ hasHammer = false })); assert(ok == false and r == 'fh_need_hammer')
    ok, r = R.repairFinalCheck(c({ hasWheel = false })); assert(ok == false and r == 'fh_not_enough')
    ok, r = R.repairFinalCheck(nil); assert(ok == false)
end)

case('clientWheelPlan: SET_VEHICLE_FIXED and native break only when ungated; cap reset on repair', function()
    local gatedBreak = R.clientWheelPlan({ broken = true, speedLimit = 3.5, native = false })
    assert(gatedBreak.cap == 3.5 and not gatedBreak.breakNative and not gatedBreak.fixNative and not gatedBreak.resetCap)
    local gatedFix = R.clientWheelPlan({ broken = false, native = false })
    assert(not gatedFix.fixNative, 'gated: never SET_VEHICLE_FIXED')
    assert(gatedFix.resetCap and gatedFix.cap == nil, 'cap reset + entry cleared even when gated')
    local ugBreak = R.clientWheelPlan({ broken = true, speedLimit = 3.5, native = true })
    assert(ugBreak.breakNative and not ugBreak.fixNative)
    local ugFix = R.clientWheelPlan({ broken = false, native = true })
    assert(ugFix.fixNative and ugFix.resetCap and ugFix.cap == nil)
    local junk = R.clientWheelPlan(nil)
    assert(not junk.breakNative and not junk.fixNative)
end)

case('findHolder: first container with enough of the item', function()
    local refs = { { type = 'equipped', id = 1 }, { type = 'backpack', id = 1 } }
    local snaps = { [1] = { [1] = { name = 'hammer', amount = 1 } }, [2] = { [3] = { name = 'wagon_wheel', amount = 2 } } }
    assert(R.findHolder(refs, snaps, 'wagon_wheel', 1) == refs[2])
    assert(R.findHolder(refs, snaps, 'wagon_wheel', 3) == nil)
    assert(R.findHolder(refs, snaps, 'hammer', 1) == refs[1])
    assert(R.findHolder(refs, snaps, 'wagon_wheel', 0) == nil)
end)

case('ITEMS: valid fh_core item defs', function()
    local items = dofile(here .. '../server/resources/[fh]/fh_core/shared/items.lua')
    for _, name in ipairs({ 'hammer', 'wagon_wheel' }) do
        local def = R.ITEMS[name]
        assert(def, name)
        local ok, err = items.validate(def)
        assert(ok, name .. ': ' .. tostring(err))
    end
end)

T.finish()

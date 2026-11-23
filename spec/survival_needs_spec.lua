-- Run from repo root: `lua spec/survival_needs_spec.lua` (or via tools/run-specs.py).
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
package.path = here .. '../server/resources/[fh]/fh_survival/shared/?.lua;' .. package.path
local case = T.it
local N = require('needs')

local NOW = 1000
local function snap(t) -- buff id -> remaining seconds
    local s = {}
    for id, rem in pairs(t) do s[id] = { magnitude = 1.1, expires_at = NOW + rem } end
    return s
end
local ALL = { well_fed = 100, hydrated = 100, rested = 100, clean = 100, warm = 100 }

case('need -> buff map and default durations', function()
    assert(N.NEED_BUFF.food == 'well_fed' and N.NEED_BUFF.water == 'hydrated' and N.NEED_BUFF.rest == 'rested'
        and N.NEED_BUFF.clean == 'clean' and N.NEED_BUFF.warmth == 'warm')
    local d = N.DEFAULT_DURATIONS
    assert(d.well_fed == 3600 and d.hydrated == 2700 and d.rested == 7200 and d.clean == 5400 and d.warm == 1200)
    local c = N.durations({ well_fed = 10, hydrated = -5, rested = 'x' })
    assert(c.well_fed == 10 and c.hydrated == 2700 and c.rested == 7200 and c.warm == 1200)
end)

case('sluggish levels 0-3 from missing count', function()
    local function lvl(have)
        local s = {}
        for _, id in ipairs(have) do s[id] = { magnitude = 1, expires_at = NOW + 50 } end
        return (N.evaluate(s, NOW, {}))
    end
    assert(lvl({ 'well_fed', 'hydrated', 'rested', 'clean' }) == 0)
    assert(lvl({ 'hydrated', 'rested', 'clean' }) == 1)
    assert(lvl({ 'rested', 'clean' }) == 2)
    assert(lvl({ 'clean' }) == 3)
    assert(lvl({}) == 3, '4 missing still capped at 3')
end)

case('sluggishLevel config mapping and bad input', function()
    assert(N.sluggishLevel(2, { [0] = 0, 0, 1, 3 }) == 1)
    assert(N.sluggishLevel(9, { [0] = 0, 0, 1, 2 }) == 2, 'past last key uses last')
    assert(N.sluggishLevel(1, { [0] = 0, 99 }) == 3, 'clamped to 3')
    assert(N.sluggishLevel(-1) == 0 and N.sluggishLevel('x') == 0 and N.sluggishLevel(0 / 0) == 0)
end)

case('expired entries (expires_at <= now) are missing', function()
    local s = snap(ALL)
    s.well_fed.expires_at = NOW
    s.hydrated.expires_at = NOW - 5
    local m = N.missingNeeds(s, NOW)
    assert(#m == 2 and m[1] == 'food' and m[2] == 'water')
end)

case('warm counts only in cold regions', function()
    local s = snap({ well_fed = 9, hydrated = 9, rested = 9, clean = 9 }) -- no warm
    assert(#N.missingNeeds(s, NOW, 'valley', { frozen = true }) == 0)
    assert(#N.missingNeeds(s, NOW, nil, { frozen = true }) == 0)
    local m = N.missingNeeds(s, NOW, 'frozen', { frozen = true })
    assert(#m == 1 and m[1] == 'warmth')
    m = N.missingNeeds(s, NOW, 'frozen', { 'frozen' }) -- list form
    assert(#m == 1 and m[1] == 'warmth')
    assert(N.evaluate(s, NOW, { regionId = 'frozen', coldRegions = { frozen = true } }) == 1)
    assert(N.evaluate(s, NOW, { regionId = 'valley', coldRegions = { frozen = true } }) == 0)
end)

case('login grace: no row -> level 0 for the window, then normal', function()
    local opts = { hasRow = false, loginAt = 1000, grace = 600 }
    assert(N.evaluate({}, 1000, opts) == 0)
    assert(N.evaluate({}, 1599, opts) == 0)
    assert(N.evaluate({}, 1600, opts) == 3)
    assert(N.evaluate({}, 1100, { hasRow = true, loginAt = 1000 }) == 3, 'row exists -> no grace')
    assert(N.evaluate({}, 1599, { hasRow = false, loginAt = 1000 }) == 0, 'default grace 600')
    assert(N.evaluate({}, 1600, { hasRow = false, loginAt = 1000 }) == 3)
    local _, missing = N.evaluate({}, 1000, opts)
    assert(#missing == 4, 'missing still reported during grace')
end)

case('rested magnitude from comfort, capped', function()
    assert(N.restedMagnitude(0, 0.01) == 1.0)
    assert(math.abs(N.restedMagnitude(10, 0.01) - 1.1) < 1e-9)
    assert(N.restedMagnitude(1000, 0.01) == 1.20, 'cap clamp')
    assert(N.restedMagnitude(1000, 0.01, 1.15) == 1.15)
    assert(N.restedMagnitude(nil) == 1.0 and N.restedMagnitude('a') == 1.0 and N.restedMagnitude(-50) == 1.0)
    assert(N.restedMagnitude(0 / 0) == 1.0 and N.restedMagnitude(math.huge) == 1.0)
end)

case('canteen use and refill edge cases', function()
    local ok, n = N.canteenUse(3); assert(ok and n == 2)
    ok, n = N.canteenUse(1); assert(ok and n == 0)
    ok, n = N.canteenUse(0); assert(not ok and n == 'empty')
    for _, bad in ipairs({ -1, 1.5, 'x', 0 / 0 }) do
        ok, n = N.canteenUse(bad); assert(not ok and n == 'invalid_charges')
    end
    ok, n = N.canteenUse(nil); assert(not ok and n == 'invalid_charges')
    ok, n = N.canteenRefill(0, 5); assert(ok and n == 5)
    ok, n = N.canteenRefill(5, 5); assert(not ok and n == 'full')
    ok, n = N.canteenRefill(2); assert(ok and n == N.DEFAULT_CANTEEN_MAX)
    ok, n = N.canteenRefill(6, 5); assert(not ok and n == 'invalid_charges')
    ok, n = N.canteenRefill(1, 0); assert(not ok and n == 'invalid_max')
    ok, n = N.canteenRefill(-1, 5); assert(not ok and n == 'invalid_charges')
end)

case('save/restore: relog never extends past saved remaining', function()
    local s = snap({ well_fed = 500, hydrated = 0, rested = 7000, clean = -3, warm = 50 })
    local saved = N.saveRemaining(s, NOW)
    assert(saved.food.remaining == 500 and saved.rest.remaining == 7000 and saved.warmth.remaining == 50)
    assert(saved.water == nil and saved.clean == nil, 'expired/zero dropped')
    local list = N.restore(saved)
    assert(#list == 3)
    local needOf = { well_fed = 'food', rested = 'rest', warm = 'warmth' }
    for _, r in ipairs(list) do
        assert(r.magnitude == 1.1)
        assert(r.duration == saved[needOf[r.buff_id]].remaining)
    end
end)

case('restore clamps to configured max and drops bad entries', function()
    local saved = {
        food = { remaining = 9999, magnitude = 1.2 },
        water = { remaining = 0, magnitude = 1.0 },
        rest = { remaining = -5, magnitude = 1.0 },
        clean = { remaining = 100, magnitude = 0 },
        warmth = { remaining = 'x', magnitude = 1 },
    }
    local list = N.restore(saved, { well_fed = 1800 })
    assert(#list == 1 and list[1].buff_id == 'well_fed' and list[1].duration == 1800)
    assert(#N.restore(nil) == 0 and #N.restore({}) == 0)
    assert(next(N.saveRemaining(nil, NOW)) == nil)
end)

case('missingNeeds/evaluate with nil or non-number now: no error, everything counted is missing', function()
    local s = snap(ALL)
    for _, bad in ipairs({ 'x', 0 / 0, math.huge, -math.huge, {} }) do
        local m = N.missingNeeds(s, bad)
        assert(#m == 4 and m[1] == 'food' and m[4] == 'clean', 'bad now ' .. tostring(bad))
        assert(#N.missingNeeds(s, bad, 'frozen', { frozen = true }) == 5)
    end
    assert(#N.missingNeeds(s, nil) == 4, 'nil now')
    assert(N.evaluate(s, nil, {}) == 3, 'nil now -> no grace proof -> capped level')
    assert(N.evaluate(s, nil, { hasRow = false, loginAt = 1000 }) == 3, 'grace needs a numeric now')
end)

case('inGrace rejects negative / non-number grace (falls back to default)', function()
    assert(N.inGrace(false, 1000, 1100, -5) == true, 'negative grace -> default 600')
    assert(N.inGrace(false, 1000, 1599, -1) == true and N.inGrace(false, 1000, 1600, -1) == false)
    assert(N.inGrace(false, 1000, 1100, 0 / 0) == true and N.inGrace(false, 1000, 1100, math.huge) == true)
    assert(N.inGrace(false, 1000, 1000, 0) == false, 'grace 0 is valid: no window')
    assert(N.inGrace(true, 1000, 1000, 600) == false, 'row exists -> never in grace')
end)

case('saveRemaining ignores nil/invalid now and NaN/inf snapshot fields', function()
    local s = snap(ALL)
    for _, bad in ipairs({ 'x', 0 / 0, math.huge, -math.huge }) do
        assert(next(N.saveRemaining(s, bad)) == nil, 'bad now ' .. tostring(bad))
    end
    assert(next(N.saveRemaining(s, nil)) == nil, 'nil now')
    local weird = {
        well_fed = { magnitude = 1.1, expires_at = math.huge },
        hydrated = { magnitude = 1.1, expires_at = 0 / 0 },
        rested = { magnitude = 0 / 0, expires_at = NOW + 10 },
        clean = { magnitude = math.huge, expires_at = NOW + 10 },
        warm = { magnitude = 1.0, expires_at = NOW + 10 },
    }
    local saved = N.saveRemaining(weird, NOW)
    assert(saved.food == nil and saved.water == nil and saved.rest == nil and saved.clean == nil)
    assert(saved.warmth.remaining == 10)
end)

case('restore drops NaN/inf saved fields', function()
    local saved = {
        food = { remaining = math.huge, magnitude = 1.1 },
        water = { remaining = 0 / 0, magnitude = 1.1 },
        rest = { remaining = 100, magnitude = 0 / 0 },
        clean = { remaining = 100, magnitude = math.huge },
        warmth = { remaining = -math.huge, magnitude = 1.0 },
    }
    assert(#N.restore(saved) == 0)
    assert(#N.restore({ food = 'x', water = 5 }) == 0, 'non-table entries dropped')
end)

case('backward clock skew: saved remaining beyond max is clamped on restore', function()
    -- Server clock went backwards (or a cap was lowered): expires_at - now exceeds the configured max.
    local s = snap({ well_fed = 99999, rested = 7300 })
    local saved = N.saveRemaining(s, NOW)
    assert(saved.food.remaining == 99999 and saved.rest.remaining == 7300)
    local list = N.restore(saved)
    assert(#list == 2)
    local by = {}
    for _, r in ipairs(list) do by[r.buff_id] = r end
    assert(by.well_fed.duration == N.DEFAULT_DURATIONS.well_fed and by.rested.duration == N.DEFAULT_DURATIONS.rested)
    list = N.restore(saved, { well_fed = 60, rested = 9000 })
    by = {}
    for _, r in ipairs(list) do by[r.buff_id] = r end
    assert(by.well_fed.duration == 60 and by.rested.duration == 7300, 'clamp to cfg max, never extend past saved')
end)

T.finish()

-- Run from repo root: `lua spec/heat_rules_spec.lua` (or via tools/run-specs.py).
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local case = T.it
local R = dofile(here .. '../server/resources/[fh]/fh_heat/shared/heat_rules.lua')
local regions = require('regions')

local sources = { camp_clear = 25, illicit_sale = 10 }
local th = { { name = 'watched', min = 25 }, { name = 'wanted', min = 50 }, { name = 'hunted', min = 75 } }

case('clamp: 0..100, junk -> 0, rounded to 2 decimals', function()
    T.eq(0, R.clamp(-5)); T.eq(100, R.clamp(140)); T.eq(42.5, R.clamp(42.5))
    T.eq(0, R.clamp(nil)); T.eq(0, R.clamp(0 / 0)); T.eq(0, R.clamp('x'))
    T.eq(33.33, R.clamp(100 / 3))
end)
case('add: adds and clamps both ways; bad amounts refused', function()
    T.eq(35, R.add(10, 25)); T.eq(100, R.add(90, 25)); T.eq(0, R.add(10, -25)); T.eq(25, R.add(nil, 25))
    local v, err = R.add(10, 'a'); assert(v == nil and err == 'fh_bad_amount')
    v, err = R.add(10, 1 / 0); assert(v == nil and err == 'fh_bad_amount')
end)
case('sourceAmount: data driven, multiplier, unknown refused', function()
    T.eq(25, R.sourceAmount(sources, 'camp_clear'))
    T.eq(30, R.sourceAmount(sources, 'illicit_sale', 3))
    local a, err = R.sourceAmount(sources, 'nope'); assert(a == nil and err == 'fh_unknown_source')
    a, err = R.sourceAmount(sources, 'camp_clear', -1); assert(a == nil and err == 'fh_bad_amount')
end)
case('decay: only off the faction territory, per minute, floors at 0', function()
    T.eq(50, R.decay(50, 600, 2, true))          -- on territory: no lay-low
    T.eq(48, R.decay(50, 60, 2, false))
    T.eq(45, R.decay(50, 150, 2, false))
    T.eq(0, R.decay(5, 6000, 2, false))
    T.eq(50, R.decay(50, 0, 2, false)); T.eq(50, R.decay(50, -10, 2, false)); T.eq(50, R.decay(50, 60, 0, false))
end)
case('level: highest threshold reached, nil below the first', function()
    assert(R.level(th, 0) == nil and R.level(th, 24.9) == nil)
    T.eq('watched', R.level(th, 25)); T.eq('wanted', R.level(th, 60)); T.eq('hunted', R.level(th, 100))
    assert(R.level(th, nil) == nil and R.level(nil, 50) == nil)
end)
case('bountyCost: rounded up, partial payoff, capped to heat, no heat refused', function()
    local c, p = R.bountyCost(40, 4); T.eq(160, c); T.eq(40, p)
    c, p = R.bountyCost(40, 4, 10); T.eq(40, c); T.eq(10, p)
    c, p = R.bountyCost(40, 4, 999); T.eq(160, c); T.eq(40, p)
    c = R.bountyCost(10.5, 4); T.eq(42, c)
    c = R.bountyCost(0.1, 4); T.eq(1, c)
    local x, _, err = R.bountyCost(0, 4); assert(x == nil and err == 'fh_no_heat')
    x, _, err = R.bountyCost(10, 4, -1); assert(x == nil and err == 'fh_bad_amount')
    x, _, err = R.bountyCost(10, nil); assert(x == nil and err == 'fh_bad_amount')
end)
case('factionAt: territory faction from fh_core regions', function()
    local t = regions.getTerritory('heartlands_t1_camp')
    T.eq(t.faction, R.factionAt(regions, t.center.x, t.center.y))
    assert(R.factionAt(regions, 99999, 99999) == nil)
end)
case('lay low end to end: heat 30 off territory for 5 min at 2/min -> 20', function()
    local v = R.add(0, R.sourceAmount(sources, 'camp_clear')); v = R.add(v, 5)
    T.eq(30, v); T.eq(20, R.decay(v, 300, 2, false))
end)
case('payoff: charges the bounty cost, pays heat points; stubbed fh_economy.charge', function()
    local charged
    local ok, pts, cost = R.payoff(40, 4, 10, function(amt) charged = amt; return true end)
    assert(ok and pts == 10 and cost == 40 and charged == 40)
    ok, pts, cost = R.payoff(40, 4, nil, function(amt) charged = amt; return true end)
    assert(ok and pts == 40 and cost == 160 and charged == 160)
end)
case('payoff: insufficient funds pays nothing; missing charge / no heat fail gracefully', function()
    local ok, pts, cost, err = R.payoff(40, 4, nil, function() return false, 'fh_insufficient_funds' end)
    assert(not ok and pts == nil and cost == 160 and err == 'fh_insufficient_funds')
    ok, _, _, err = R.payoff(40, 4, nil, nil); assert(not ok and err == 'fh_economy_unavailable')
    local called = false
    ok, _, _, err = R.payoff(0, 4, nil, function() called = true; return true end)
    assert(not ok and err == 'fh_no_heat' and not called)
end)

-- ---------------------------------------------------------------- R5 fix round

case('runPayoff lock: concurrent payoff while the first charge is in flight -> exactly one charge', function()
    local locks, heat, charges = R.newLocks(), 40, 0
    local key = R.lockKey('CID1', 'outlaws')
    local function deps()
        return { locks = locks, key = key, heat = function() return heat end, perPoint = 4, points = nil,
            charge = function(amount)
                charges = charges + 1
                coroutine.yield('charging') -- the real charge awaits the DB here
                return true
            end,
            commit = function(paid) heat = heat - paid end }
    end
    local first = coroutine.create(function() return R.runPayoff(deps()) end)
    local _, state = coroutine.resume(first)
    T.eq('charging', state); assert(locks.held(key), 'lock held while in flight')
    -- second request (same citizen + faction) while the first is suspended inside charge
    local ok2, err2 = R.runPayoff(deps())
    assert(ok2 == false and err2 == 'fh_payoff_busy', 'second request refused')
    T.eq(1, charges, 'second request charged nothing')
    local _, ok1, paid1, cost1 = coroutine.resume(first)
    assert(ok1 == true and paid1 == 40 and cost1 == 160)
    T.eq(1, charges); T.eq(0, heat); assert(not locks.held(key), 'released after success')
    -- other faction / other citizen are independent keys
    assert(R.lockKey('CID1', 'outlaws') ~= R.lockKey('CID1', 'lawmen'))
    assert(R.lockKey('CID1', 'outlaws') ~= R.lockKey('CID2', 'outlaws'))
end)

case('runPayoff lock: always released on refusal, early return and error', function()
    local locks, key = R.newLocks(), R.lockKey('C', 'outlaws')
    local base = function(over)
        local d = { locks = locks, key = key, heat = function() return 40 end, perPoint = 4,
            charge = function() return true end, commit = function() end }
        for k, v in pairs(over) do d[k] = v end
        return d
    end
    local ok, err = R.runPayoff(base({ charge = function() return false, 'fh_insufficient_funds' end }))
    assert(not ok and err == 'fh_insufficient_funds' and not locks.held(key), 'refused charge releases')
    ok, err = R.runPayoff(base({ heat = function() return 0 end }))
    assert(not ok and err == 'fh_no_heat' and not locks.held(key), 'early return (no heat) releases')
    ok, err = R.runPayoff(base({ points = -1 }))
    assert(not ok and err == 'fh_bad_amount' and not locks.held(key), 'bad points releases')
    local logged
    ok, err = R.runPayoff(base({ heat = function() error('db down') end, onError = function(m) logged = m end }))
    assert(not ok and err == 'fh_payoff_error' and not locks.held(key) and logged, 'error before charge releases')
    local wasCharged
    ok, err = R.runPayoff(base({ commit = function() error('boom') end, onError = function(_, c) wasCharged = c end }))
    assert(not ok and err == 'fh_payoff_commit_failed' and wasCharged == true and not locks.held(key),
        'error after charge releases and reports charged')
    ok = R.runPayoff(base({})); assert(ok == true, 'next payoff goes through after all of the above')
end)

case('chargeRegion: territory region first, else faction home region, else nil', function()
    local t = regions.getTerritory('heartlands_t1_camp')
    T.eq('heartlands', R.chargeRegion(regions, 'outlaws', t.center.x, t.center.y))
    T.eq('heartlands', R.chargeRegion(regions, 'lawmen', 99999, 99999))   -- off territory: home region
    T.eq('heartlands', R.chargeRegion(regions, 'outlaws', nil, nil))      -- no ped coords
    assert(R.chargeRegion(regions, 'nobody', 99999, 99999) == nil)
    assert(regions.isKnownRegion(R.chargeRegion(regions, 'lawmen', nil, nil)), 'never an unknown region')
end)

case('parsePoints: only an omitted arg means all; junk / <= 0 / out of range refused', function()
    local ok, p = R.parsePoints(nil, 40); assert(ok == true and p == nil)
    ok, p = R.parsePoints('10', 40); assert(ok == true and p == 10)
    ok, p = R.parsePoints('40', 40); assert(ok == true and p == 40)
    ok, p = R.parsePoints('2.5', 40); assert(ok == true and p == 2.5)
    for _, bad in ipairs({ 'abc', '', '10abc', '-5', '0', '41', '1e400', '-1e400', 'nan', 'inf' }) do
        local o, q, e = R.parsePoints(bad, 40)
        assert(o == false and q == nil and e == 'fh_bad_points', 'refused: ' .. bad)
    end
end)

case('changeEvents: one table payload per event (fh_core/docs/events.md), threshold only on level change', function()
    local evs = R.changeEvents(7, 'CID1', 'outlaws', 20, 30, th, 'camp_clear')
    T.eq(2, #evs)
    T.eq('fh:heat:changed', evs[1][1])
    T.same({ src = 7, citizenid = 'CID1', faction = 'outlaws', old = 20, value = 30, delta = 10, level = 'watched',
        reason = 'camp_clear' }, evs[1][2])
    T.eq('fh:heat:threshold', evs[2][1])
    T.same({ src = 7, citizenid = 'CID1', faction = 'outlaws', old_level = nil, level = 'watched', value = 30 }, evs[2][2])
    for _, ev in ipairs(evs) do T.eq(2, #ev, 'name + exactly one payload table'); T.eq('table', type(ev[2])) end
    evs = R.changeEvents(7, 'CID1', 'outlaws', 30, 35, th); T.eq(1, #evs)
    T.eq(0, #R.changeEvents(7, 'CID1', 'outlaws', 30, 30, th))
end)

case('safeTick: an erroring tick is logged and the loop keeps running', function()
    local logged, ticks = {}, 0
    local tick = function(dt) ticks = ticks + 1; if dt == 'bad' then error('boom') end end
    local onErr = function(m) logged[#logged + 1] = m end
    for _, dt in ipairs({ 60, 'bad', 60 }) do R.safeTick(tick, onErr, dt) end
    T.eq(3, ticks, 'ticks after the error still ran'); T.eq(1, #logged)
    assert(logged[1]:find('boom'), 'error message logged')
    assert(R.safeTick(tick, function() error('logger broke') end, 'bad') == false, 'a broken logger cannot kill it')
end)

T.finish()

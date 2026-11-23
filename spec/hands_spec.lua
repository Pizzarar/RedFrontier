-- Run from repo root: `lua spec/hands_spec.lua`.
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
package.path = here .. '../server/resources/[fh]/fh_hands/shared/?.lua;' .. package.path
local case = T.it
local logic = require('hands_logic')
assert(loadfile(here .. '../server/resources/[fh]/fh_hands/config.lua'))()
local cfg = FhHandsConfig

case('real config validates', function() assert(logic.validateConfig(cfg) == true) end)
case('bad configs are refused', function()
    local function with(k, v) local c = {}; for a, b in pairs(cfg) do c[a] = b end; c[k] = v; return c end
    assert(logic.validateConfig(with('tickSeconds', 0)) == false)
    T.eq('bad_pollSeconds', select(2, logic.validateConfig(with('pollSeconds', 0))))
    T.eq('bad_pollSeconds', select(2, logic.validateConfig(with('pollSeconds', -5))))
    T.eq('bad_regionId', select(2, logic.validateConfig(with('regionId', ''))))
    T.eq('bad_unlockId', select(2, logic.validateConfig(with('unlockId', nil))))
    T.eq('bad_feed', select(2, logic.validateConfig(with('feed', { item = 'feed', cap = 40, perTick = 0 }))))
    T.eq('bad_feed', select(2, logic.validateConfig(with('feed', { cap = 40, perTick = 10 }))))
    T.eq('bad_feed', select(2, logic.validateConfig(with('feed', nil))))
    T.eq('bad_hand_x', select(2, logic.validateConfig(with('hands', { x = { wage = 5, task = '' } }))))
    assert(logic.validateConfig(with('maxCatchupTicks', 0)) == false)
    assert(logic.validateConfig(with('quitAfterUnpaid', 1.5)) == false)
    assert(logic.validateConfig(with('hands', { x = { wage = 0, task = 't' } })) == false)
    assert(logic.validateConfig(nil) == false)
end)

case('ticksDue: whole ticks, remainder kept', function()
    local n, last = logic.ticksDue(1000, 1000 + 250, 100, 6)
    assert(n == 2 and last == 1200)
    n, last = logic.ticksDue(1000, 1050, 100, 6)
    assert(n == 0 and last == 1000)
end)
case('ticksDue: offline catch-up is capped and last_tick jumps to now', function()
    local n, last = logic.ticksDue(0, 100000, 100, 6)
    assert(n == 6 and last == 100000)
    n, last = logic.ticksDue(0, 600, 100, 6) -- exactly the cap is not over it
    assert(n == 6 and last == 600)
end)
case('ticksDue: clock backwards and bad input give 0 ticks', function()
    local n, last = logic.ticksDue(5000, 100, 100, 6)
    assert(n == 0 and last == 100)
    n = logic.ticksDue(0, 100, 0, 6)
    assert(n == 0)
    n = logic.ticksDue(nil, 100, 10, 6)
    assert(n == 0)
end)

case('step: paid hand works and clears unpaid', function()
    local s, run = logic.step({ unpaid = 2, status = 'idle' }, true, 3)
    assert(run == true and s.unpaid == 0 and s.status == 'working')
end)
case('step: unpaid hand idles (no task) until quitAfter, then quits', function()
    local s, run = logic.step({ unpaid = 0, status = 'working' }, false, 3)
    assert(run == false and s.unpaid == 1 and s.status == 'idle')
    s, run = logic.step(s, false, 3)
    assert(run == false and s.unpaid == 2 and s.status == 'idle')
    s, run = logic.step(s, false, 3)
    assert(run == false and s.unpaid == 3 and s.status == 'quit')
end)
case('step: paying again before the limit resets the count', function()
    local s = logic.step({ unpaid = 0 }, false, 3)
    s = logic.step(s, true, 3)
    s = logic.step(s, false, 3)
    assert(s.unpaid == 1 and s.status == 'idle')
end)

case('topupAmount: up to perTick, never past cap, never negative', function()
    assert(logic.topupAmount(0, 40, 10) == 10)
    assert(logic.topupAmount(35, 40, 10) == 5)
    assert(logic.topupAmount(40, 40, 10) == 0)
    assert(logic.topupAmount(50, 40, 10) == 0)
    assert(logic.topupAmount(0, 40, 0) == 0)
    assert(logic.topupAmount('x', 40, 10) == 0)
end)
case('countItem sums matching stacks only', function()
    local items = { [1] = { name = 'feed', amount = 7 }, [2] = { name = 'bread', amount = 3 }, [5] = { name = 'feed', amount = 2 } }
    assert(logic.countItem(items, 'feed') == 9)
    assert(logic.countItem(nil, 'feed') == 0)
end)

-- ---------------------------------------------------------------- wage-tick sequence (runOwner) with a fake world
-- The fake DB / charge / scheduler model what main.lua wires up: every DB call and charge yields (MySQL await) when
-- run inside a coroutine, so two coroutines interleave at exactly the points the server can.
local IV = cfg.tickSeconds
local tcfg = { tickSeconds = IV, maxCatchupTicks = 6, quitAfterUnpaid = 3,
    hands = { ranch_hand = { wage = 5, task = 'feed_topup' }, stablehand = { wage = 3, task = 'feed_topup' } } }

local function y() if coroutine.isyieldable() then coroutine.yield() end end

local function sched()
    local S, cos = {}, {}
    function S.spawn(fn, ...)
        local args = table.pack(...)
        cos[#cos + 1] = coroutine.create(function() return fn(table.unpack(args, 1, args.n)) end)
    end
    function S.run()
        for _ = 1, 10000 do
            local alive = false
            for _, c in ipairs(cos) do
                if coroutine.status(c) == 'suspended' then
                    alive = true
                    local ok, err = coroutine.resume(c)
                    if not ok then error(err, 0) end
                end
            end
            if not alive then return end
        end
        error('scheduler did not finish')
    end
    return S
end

-- rows: kind -> { last_tick, unpaid, status }
local function world(rows)
    local W = { db = {}, charges = {}, events = {}, logs = {}, online = true, charging = false, script = {},
        hook = {}, tasks = 0, taskResult = { true, 1 }, failDb = {}, locks = {}, clock = 0 }
    for k, r in pairs(rows) do W.db[k] = { last_tick = r.last_tick, unpaid = r.unpaid or 0, status = r.status or 'working' } end
    local function fire(name) local f = W.hook[name]; if f then f() end end
    function W.load()
        local list = {}
        for k, r in pairs(W.db) do list[#list + 1] = { hand_kind = k, last_tick = r.last_tick, unpaid = r.unpaid, status = r.status } end
        return (logic.entryFromRows('CID1', 7, list, tcfg))
    end
    function W.io(e)
        return {
            online = function() return W.online end,
            setLast = function(kind, expect, set)
                fire('before:setLast'); y()
                if W.failDb.setLast then return false end
                local r, ok = W.db[kind], false
                if r and r.last_tick == expect then r.last_tick = set; ok = true end
                fire('after:setLast')
                return ok
            end,
            saveState = function(kind, last, unpaid, status)
                fire('before:saveState'); y()
                if W.failDb.saveState then return false end
                local r = W.db[kind]
                if r and r.last_tick == last then r.unpaid, r.status = unpaid, status end
                return true
            end,
            remove = function(kind)
                y()
                if W.failDb.remove then return false end
                local had = W.db[kind] ~= nil
                W.db[kind] = nil
                return had
            end,
            -- fh_economy charge: synchronous player lookup, per-citizenid lock (fh_charge_busy), ledger insert yields
            charge = function(amount, reason)
                if not W.online then return false, 'no_player' end
                local scripted = table.remove(W.script, 1)
                if scripted then return table.unpack(scripted) end
                if W.charging then return false, 'fh_charge_busy' end
                W.charging = true
                y()
                W.charging = false
                if not W.online then return false, 'no_player' end
                W.charges[#W.charges + 1] = { amount = amount, reason = reason }
                fire('after:charge')
                return true
            end,
            runTask = function() y(); W.tasks = W.tasks + 1; return table.unpack(W.taskResult) end,
            emit = function(name, p) W.events[#W.events + 1] = { name = name, p = p } end,
            log = function(m) W.logs[#W.logs + 1] = m end,
        }
    end
    function W.count(name) local n = 0; for _, ev in ipairs(W.events) do if ev.name == name then n = n + 1 end end; return n end
    function W.lockOpts(timeout)
        return { wait = y, clock = function() W.clock = W.clock + 1; return W.clock end, timeoutMs = timeout }
    end
    return W
end
local function once(f) local done = false; return function() if not done then done = true; f() end end end

case('runOwner: capped offline catch-up charges maxCatchup ticks and persists last_tick = now', function()
    local W = world({ ranch_hand = { last_tick = 0 } })
    local e = W.load()
    local now = 100 * IV
    T.eq('done', logic.runOwner(e, tcfg, now, W.io(e)))
    T.eq(6, #W.charges); T.eq(6, W.tasks)
    T.eq(now, W.db.ranch_hand.last_tick); T.eq(now, e.list.ranch_hand.last_tick)
    T.eq('wage:ranch_hand', W.charges[1].reason)
    -- running again at the same time is a no-op
    logic.runOwner(e, tcfg, now, W.io(e)); T.eq(6, #W.charges)
end)

case('runOwner: under the cap the remainder is kept', function()
    local W = world({ ranch_hand = { last_tick = 1000 } })
    local e = W.load()
    logic.runOwner(e, tcfg, 1000 + 2 * IV + 50, W.io(e))
    T.eq(2, #W.charges); T.eq(1000 + 2 * IV, W.db.ranch_hand.last_tick)
end)

case('interleave: poll tick, login reload+catch-up and a second poll on one owner charge each tick once', function()
    local W = world({ ranch_hand = { last_tick = 0 } })
    local now, S = 4 * IV, sched()
    local function poll()
        logic.withLock(W.locks, 'CID1', W.lockOpts(nil), function()
            local e = W.cache or W.load(); W.cache = e
            logic.runOwner(e, tcfg, now, W.io(e))
        end)
    end
    local function login()
        local ok = logic.withLock(W.locks, 'CID1', W.lockOpts(1000), function()
            W.cache = W.load() -- reads the DB only after the poll's claims landed
            logic.runOwner(W.cache, tcfg, now, W.io(W.cache))
        end)
        assert(ok)
    end
    S.spawn(poll); S.spawn(login); S.spawn(poll)
    S.run()
    T.eq(4, #W.charges); T.eq(now, W.db.ranch_hand.last_tick)
end)

case('interleave: even two stale entries running unlocked never double-charge (claims are CAS on the row)', function()
    local W = world({ ranch_hand = { last_tick = 0 } })
    local now, S = 3 * IV, sched()
    local a, b = W.load(), W.load()
    W.charging = false
    S.spawn(logic.runOwner, a, tcfg, now, W.io(a))
    S.spawn(logic.runOwner, b, tcfg, now, W.io(b))
    S.run()
    assert(#W.charges <= 3, 'charged ' .. #W.charges)
    -- whatever was not charged is still due (handed back on busy) or claimed by the other runner
    local e = W.load(); logic.runOwner(e, tcfg, now, W.io(e))
    T.eq(3, #W.charges); T.eq(now, W.db.ranch_hand.last_tick)
end)

case('crash after the claim, before the charge: restart skips that wage, never charges it twice', function()
    local W = world({ ranch_hand = { last_tick = 0 } })
    W.hook['after:setLast'] = once(function() error('crash') end)
    local e = W.load()
    assert(not pcall(logic.runOwner, e, tcfg, 3 * IV, W.io(e)))
    T.eq(0, #W.charges); T.eq(IV, W.db.ranch_hand.last_tick)
    local e2 = W.load(); logic.runOwner(e2, tcfg, 3 * IV, W.io(e2))
    T.eq(2, #W.charges); T.eq(3 * IV, W.db.ranch_hand.last_tick)
end)

case('crash after the charge, before the state save: restart does not re-charge', function()
    local W = world({ ranch_hand = { last_tick = 0, unpaid = 2, status = 'idle' } })
    W.hook['after:charge'] = once(function() error('crash') end)
    local e = W.load()
    assert(not pcall(logic.runOwner, e, tcfg, 3 * IV, W.io(e)))
    T.eq(1, #W.charges)
    local e2 = W.load(); logic.runOwner(e2, tcfg, 3 * IV, W.io(e2))
    T.eq(3, #W.charges); T.eq(0, W.db.ranch_hand.unpaid); T.eq('working', W.db.ranch_hand.status)
end)

case('fh_charge_busy: tick handed back, no strike, charged on the next poll', function()
    local W = world({ ranch_hand = { last_tick = 0 } })
    W.script = { { false, 'fh_charge_busy' } }
    local e = W.load()
    logic.runOwner(e, tcfg, 2 * IV, W.io(e))
    T.eq(0, #W.charges); T.eq(0, W.db.ranch_hand.last_tick); T.eq(0, e.list.ranch_hand.unpaid)
    T.eq(0, W.count('fh:hands:unpaid'))
    logic.runOwner(e, tcfg, 2 * IV, W.io(e))
    T.eq(2, #W.charges); T.eq(2 * IV, W.db.ranch_hand.last_tick)
end)

case('ledger_failed is transient like busy', function()
    local W = world({ ranch_hand = { last_tick = 0 } })
    W.script = { { false, 'ledger_failed' } }
    local e = W.load()
    logic.runOwner(e, tcfg, IV, W.io(e))
    T.eq(0, W.db.ranch_hand.last_tick); T.eq(0, W.count('fh:hands:unpaid')); T.eq(0, e.list.ranch_hand.unpaid)
end)

case('release fails after busy: DB keeps the claim, wage skipped once, never doubled', function()
    local W = world({ ranch_hand = { last_tick = 0 } })
    W.script = { { false, 'fh_charge_busy' } }
    local e = W.load()
    local io = W.io(e)
    local setLast = io.setLast
    local calls = 0
    io.setLast = function(...) calls = calls + 1; if calls == 2 then return false end; return setLast(...) end
    logic.runOwner(e, tcfg, 2 * IV, io)
    T.eq(IV, W.db.ranch_hand.last_tick); T.eq(IV, e.list.ranch_hand.last_tick); assert(#W.logs >= 1)
    logic.runOwner(e, tcfg, 2 * IV, W.io(e))
    T.eq(1, #W.charges)
end)

case('owner drops mid catch-up: no strike, the rest stays due and the cap still holds', function()
    local W = world({ ranch_hand = { last_tick = 0 } })
    local now = 100 * IV
    local n = 0
    W.hook['after:charge'] = function() n = n + 1; if n == 2 then W.online = false end end
    local e = W.load()
    T.eq('gone', logic.runOwner(e, tcfg, now, W.io(e)))
    T.eq(2, #W.charges); T.eq(now - 4 * IV, W.db.ranch_hand.last_tick)
    T.eq(0, W.count('fh:hands:unpaid')); T.eq(0, W.db.ranch_hand.unpaid)
    W.online = true; W.hook = {}
    local e2 = W.load(); logic.runOwner(e2, tcfg, now, W.io(e2))
    T.eq(6, #W.charges); T.eq(now, W.db.ranch_hand.last_tick)
end)

case('no_player / player_changed from charge hand the tick back and stop the owner', function()
    for _, why in ipairs({ 'no_player', 'player_changed' }) do
        local W = world({ ranch_hand = { last_tick = 0 }, stablehand = { last_tick = 0 } })
        W.script = { { false, why } }
        local e = W.load()
        T.eq('gone', logic.runOwner(e, tcfg, IV, W.io(e)))
        T.eq(0, #W.charges); T.eq(0, W.db.ranch_hand.last_tick); T.eq(0, W.db.stablehand.last_tick)
        T.eq(0, W.count('fh:hands:unpaid'))
    end
end)

case('offline owner: nothing is claimed or charged', function()
    local W = world({ ranch_hand = { last_tick = 0 } })
    W.online = false
    local e = W.load()
    T.eq('gone', logic.runOwner(e, tcfg, 5 * IV, W.io(e)))
    T.eq(0, #W.charges); T.eq(0, W.db.ranch_hand.last_tick)
end)

case('fh_insufficient_funds x3: idle, unpaid events, then quit and row deleted', function()
    local W = world({ ranch_hand = { last_tick = 0 } })
    W.script = { { false, 'fh_insufficient_funds' }, { false, 'fh_insufficient_funds' }, { false, 'fh_insufficient_funds' } }
    local e = W.load()
    logic.runOwner(e, tcfg, 2 * IV, W.io(e))
    T.eq(2, W.count('fh:hands:unpaid')); T.eq(2, W.db.ranch_hand.unpaid); T.eq('idle', W.db.ranch_hand.status)
    T.eq(0, W.tasks)
    logic.runOwner(e, tcfg, 3 * IV, W.io(e))
    T.eq(3, W.count('fh:hands:unpaid')); T.eq(1, W.count('fh:hands:quit'))
    T.eq(nil, W.db.ranch_hand); T.eq(nil, e.list.ranch_hand); T.eq(0, #W.charges)
    T.eq('fh_insufficient_funds', W.events[1].p.reason)
end)

case('charge_unavailable (no export) and unknown refusals are unpaid strikes, no task', function()
    for _, why in ipairs({ 'charge_unavailable', 'removemoney_refused', 'charge_refused' }) do
        local W = world({ ranch_hand = { last_tick = 0 } })
        W.script = { { false, why } }
        local e = W.load()
        logic.runOwner(e, tcfg, IV, W.io(e))
        T.eq(1, W.count('fh:hands:unpaid')); T.eq(1, W.db.ranch_hand.unpaid); T.eq(IV, W.db.ranch_hand.last_tick)
        T.eq(0, W.tasks)
    end
end)

case('quit whose delete fails is marked quit; the loader skips it and reports it for deletion', function()
    local W = world({ ranch_hand = { last_tick = 0, unpaid = 2, status = 'idle' } })
    W.script = { { false, 'fh_insufficient_funds' } }
    W.failDb.remove = true
    local e = W.load()
    logic.runOwner(e, tcfg, IV, W.io(e))
    T.eq('quit', W.db.ranch_hand.status); T.eq(1, W.count('fh:hands:quit'))
    local e2, quitKinds = logic.entryFromRows('CID1', 7,
        { { hand_kind = 'ranch_hand', last_tick = IV, unpaid = 3, status = 'quit' } }, tcfg)
    T.eq(nil, e2.list.ranch_hand); T.same({ 'ranch_hand' }, quitKinds)
end)

case('claim fails (row fired / changed elsewhere): no charge', function()
    local W = world({ ranch_hand = { last_tick = 0 } })
    local e = W.load()
    W.db.ranch_hand = nil
    logic.runOwner(e, tcfg, 3 * IV, W.io(e))
    T.eq(0, #W.charges); assert(#W.logs == 1)
end)

case('fire waits on the lock: a fired hand is never charged after the fire returns', function()
    local W = world({ ranch_hand = { last_tick = 0 } })
    local S, e = sched(), W.load()
    local fired, chargesAtFire
    S.spawn(function()
        logic.withLock(W.locks, 'CID1', W.lockOpts(nil), logic.runOwner, e, tcfg, 3 * IV, W.io(e))
    end)
    S.spawn(function()
        local ok, r = logic.withLock(W.locks, 'CID1', W.lockOpts(1000), function()
            if not e.list.ranch_hand then return false end
            y(); W.db.ranch_hand = nil; e.list.ranch_hand = nil
            chargesAtFire = #W.charges
            return true
        end)
        fired = ok and r
    end)
    S.run()
    T.eq(true, fired); T.eq(3, chargesAtFire); T.eq(3, #W.charges); T.eq(nil, W.db.ranch_hand)
end)

case('a hand removed from the list mid-run (unload / reload) stops being charged', function()
    local W = world({ ranch_hand = { last_tick = 0 } })
    local e = W.load()
    local n = 0
    W.hook['after:charge'] = function() n = n + 1; if n == 1 then e.list.ranch_hand = nil end end
    logic.runOwner(e, tcfg, 4 * IV, W.io(e))
    T.eq(1, #W.charges)
end)

case('hiring a second kind mid-run does not break the iteration (kinds are snapshotted)', function()
    local W = world({ ranch_hand = { last_tick = 0 } })
    local e = W.load()
    W.hook['after:charge'] = once(function() e.list.stablehand = { last_tick = 0, unpaid = 0, status = 'working' } end)
    T.eq('done', logic.runOwner(e, tcfg, 2 * IV, W.io(e)))
    T.eq(2, #W.charges); T.eq(0, e.list.stablehand.last_tick)
end)

case('two kinds: both processed, sorted, each charged its wage', function()
    local W = world({ ranch_hand = { last_tick = 0 }, stablehand = { last_tick = 0 } })
    local e = W.load()
    logic.runOwner(e, tcfg, IV, W.io(e))
    T.eq(2, #W.charges); T.eq('wage:ranch_hand', W.charges[1].reason); T.eq(3, W.charges[2].amount)
end)

case('clock went backwards: the re-base is persisted, then ticks resume from it', function()
    local W = world({ ranch_hand = { last_tick = 5000 } })
    local e = W.load()
    logic.runOwner(e, tcfg, 100, W.io(e))
    T.eq(0, #W.charges); T.eq(100, W.db.ranch_hand.last_tick); T.eq(100, e.list.ranch_hand.last_tick)
    logic.runOwner(e, tcfg, 100 + IV, W.io(e))
    T.eq(1, #W.charges)
end)

case('task failure is logged and emits fh:hands:task_failed; the wage stays paid', function()
    local W = world({ ranch_hand = { last_tick = 0 } })
    W.taskResult = { false, 'no_homestead' }
    local e = W.load()
    logic.runOwner(e, tcfg, IV, W.io(e))
    T.eq(1, #W.charges); T.eq(1, W.count('fh:hands:task_failed'))
    T.eq('no_homestead', W.events[1].p.reason); T.eq('feed_topup', W.events[1].p.task); assert(#W.logs == 1)
    W.taskResult = { nil }
    logic.runOwner(e, tcfg, 2 * IV, W.io(e))
    T.eq(2, W.count('fh:hands:task_failed'))
end)

case('state save failure is logged; the claimed tick is not charged again', function()
    local W = world({ ranch_hand = { last_tick = 0 } })
    W.failDb.saveState = true
    local e = W.load()
    logic.runOwner(e, tcfg, IV, W.io(e))
    T.eq(1, #W.charges); assert(#W.logs == 1)
    local e2 = W.load(); logic.runOwner(e2, tcfg, IV, W.io(e2))
    T.eq(1, #W.charges)
end)

case('tickPlan: per-tick targets end at newLast, over the cap they start at now - n*interval', function()
    T.same({ 1100, 1200 }, (logic.tickPlan(1000, 1250, 100, 6)))
    local plan, last = logic.tickPlan(0, 100000, 100, 3)
    T.same({ 99800, 99900, 100000 }, plan); T.eq(100000, last)
    plan, last = logic.tickPlan(5000, 100, 100, 6)
    T.eq(0, #plan); T.eq(100, last)
end)

case('chargeOutcome classifies every charge contract error', function()
    T.eq('paid', logic.chargeOutcome(true))
    T.eq('retry', logic.chargeOutcome(false, 'fh_charge_busy'))
    T.eq('retry', logic.chargeOutcome(false, 'ledger_failed'))
    T.eq('gone', logic.chargeOutcome(false, 'no_player'))
    T.eq('gone', logic.chargeOutcome(false, 'player_changed'))
    T.eq('unpaid', logic.chargeOutcome(false, 'fh_insufficient_funds'))
    T.eq('unpaid', logic.chargeOutcome(false, 'charge_unavailable'))
    T.eq('unpaid', logic.chargeOutcome(nil, nil))
end)

case('withLock: try-once is busy, waiters get it after release, errors release the key, timeouts give busy', function()
    local W = world({})
    local S, order = sched(), {}
    S.spawn(function()
        logic.withLock(W.locks, 'k', W.lockOpts(nil), function() order[#order + 1] = 'a1'; y(); y(); order[#order + 1] = 'a2' end)
    end)
    S.spawn(function()
        T.same({ false, 'busy' }, { logic.withLock(W.locks, 'k', W.lockOpts(nil), function() end) })
        local ok = logic.withLock(W.locks, 'k', W.lockOpts(1000), function() order[#order + 1] = 'b' end)
        assert(ok)
    end)
    S.run()
    T.same({ 'a1', 'a2', 'b' }, order); T.eq(nil, W.locks.k)
    local ok, why = logic.withLock(W.locks, 'k', W.lockOpts(nil), function() error('boom') end)
    T.eq(false, ok); T.eq('error', why); T.eq(nil, W.locks.k)
    T.same({ true, 1, 2 }, { logic.withLock(W.locks, 'k', W.lockOpts(nil), function() return 1, 2 end) })
    W.locks.k = true
    local S2 = sched()
    S2.spawn(function() T.same({ false, 'busy' }, { logic.withLock(W.locks, 'k', W.lockOpts(5), function() end) }) end)
    S2.run()
end)

case('entryFromRows: unknown kinds skipped, numbers coerced, bad status -> working', function()
    local e, q = logic.entryFromRows('C', 3, {
        { hand_kind = 'ranch_hand', last_tick = '1200', unpaid = '1', status = 'idle' },
        { hand_kind = 'stablehand', last_tick = 5, unpaid = 0, status = 'weird' },
        { hand_kind = 'nope', last_tick = 1, unpaid = 0, status = 'working' },
    }, tcfg)
    T.eq(1200, e.list.ranch_hand.last_tick); T.eq(1, e.list.ranch_hand.unpaid); T.eq('idle', e.list.ranch_hand.status)
    T.eq('working', e.list.stablehand.status); T.eq(nil, e.list.nope); T.eq(0, #q)
    T.eq('C', e.citizenid); T.eq(3, e.src)
end)

T.finish()

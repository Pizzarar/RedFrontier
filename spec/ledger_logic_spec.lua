-- Run from repo root: `lua spec/ledger_logic_spec.lua` (or via busted).
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
package.path = here .. '../server/resources/[fh]/fh_economy/shared/?.lua;' .. package.path
local case = T.it
local logic = require('ledger_logic')
local regions = require('regions')

local ctx = { isKnownRegion = regions.isKnownRegion, maxPay = 1000, maxRepDelta = 100, maxReason = 128 }

case('reason longer than maxReason is refused (pay and rep)', function()
    local long = string.rep('x', 129)
    local ok, err = logic.validatePay({ amount = 5, reason = long, region_id = 'heartlands' }, ctx)
    assert(ok == false and err == 'invalid_reason')
    ok, err = logic.validateRep({ delta = 5, reason = long, region_id = 'heartlands' }, ctx)
    assert(ok == false and err == 'invalid_reason')
    assert(logic.validatePay({ amount = 5, reason = string.rep('x', 128), region_id = 'heartlands' }, ctx) == true)
end)
case('validSrc accepts only positive integer numbers', function()
    assert(logic.validSrc(7) == true)
    for _, bad in ipairs({ '7', 0, -1, 1.5, 0/0, true }) do assert(logic.validSrc(bad) == false, tostring(bad)) end
    assert(logic.validSrc(nil) == false)
end)
local function pay(a, r, g) return logic.validatePay({ amount = a, reason = r, region_id = g }, ctx) end
local function rep(d, r, g) return logic.validateRep({ delta = d, reason = r, region_id = g }, ctx) end

case('pay accepts a valid payout', function()
    assert(pay(5, 'sell_pelt', 'heartlands') == true)
end)
case('pay refuses amount <= 0, nan, inf, non-number', function()
    for _, bad in ipairs({ 0, -1, 0/0, math.huge, '5', true }) do
        local ok, err = pay(bad, 'x', 'heartlands')
        assert(ok == false and err == 'invalid_amount', tostring(bad))
    end
    local ok, err = pay(nil, 'x', 'heartlands')
    assert(ok == false and err == 'invalid_amount')
end)
case('pay refuses amounts over the cap', function()
    local ok, err = pay(1001, 'x', 'heartlands')
    assert(ok == false and err == 'amount_too_large')
end)
case('pay refuses empty / blank / non-string reason', function()
    for _, bad in ipairs({ '', '   ', 5 }) do
        local ok, err = pay(5, bad, 'heartlands')
        assert(ok == false and err == 'invalid_reason')
    end
    local ok, err = pay(5, nil, 'heartlands')
    assert(ok == false and err == 'invalid_reason')
end)
case('pay refuses unknown or missing region', function()
    local ok, err = pay(5, 'x', 'atlantis')
    assert(ok == false and err == 'unknown_region')
    ok, err = pay(5, 'x', nil)
    assert(ok == false and err == 'unknown_region')
end)
case('rep accepts positive and negative deltas, refuses 0 and bad input', function()
    assert(rep(10, 'x', 'heartlands') == true)
    assert(rep(-10, 'x', 'heartlands') == true)
    local ok, err = rep(0, 'x', 'heartlands')
    assert(ok == false and err == 'invalid_delta')
    ok, err = rep(101, 'x', 'heartlands')
    assert(ok == false and err == 'delta_too_large')
    ok, err = rep(5, '', 'heartlands')
    assert(ok == false and err == 'invalid_reason')
    ok, err = rep(5, 'x', 'nowhere')
    assert(ok == false and err == 'unknown_region')
end)
case('applyRep clamps to bounds', function()
    assert(logic.applyRep(nil, 5, -10, 10) == 5)
    assert(logic.applyRep(8, 5, -10, 10) == 10)
    assert(logic.applyRep(-8, -5, -10, 10) == -10)
end)

-- B7 charge -----------------------------------------------------------------------------------------------------
local cctx = { isKnownRegion = regions.isKnownRegion, maxCharge = 500, maxReason = 128 }
case('validateCharge uses pay rules with maxCharge', function()
    assert(logic.validateCharge({ amount = 5, reason = 'wages', region_id = 'heartlands' }, cctx) == true)
    for _, bad in ipairs({ 0, -1, 0/0, math.huge, '5' }) do
        local ok, err = logic.validateCharge({ amount = bad, reason = 'x', region_id = 'heartlands' }, cctx)
        assert(ok == false and err == 'invalid_amount', tostring(bad))
    end
    local ok, err = logic.validateCharge({ amount = 501, reason = 'x', region_id = 'heartlands' }, cctx)
    assert(ok == false and err == 'amount_too_large')
    ok, err = logic.validateCharge({ amount = 5, reason = ' ', region_id = 'heartlands' }, cctx)
    assert(ok == false and err == 'invalid_reason')
    ok, err = logic.validateCharge({ amount = 5, reason = 'x', region_id = 'nowhere' }, cctx)
    assert(ok == false and err == 'unknown_region')
end)
case('canAfford: exact covers, short and junk balances do not', function()
    assert(logic.canAfford(10, 10) == true)
    assert(logic.canAfford(9.99, 10) == false)
    assert(logic.canAfford(nil, 1) == false and logic.canAfford(0/0, 1) == false and logic.canAfford('10', 1) == false)
end)

-- A fake wallet + ledger that records the order of side effects. `w.handle` is what io.player() hands out; the
-- `*DuringInsert` options act while the insert "yields" (spend, drop the player, switch character).
local function wallet(balance, opts)
    opts = opts or {}
    local w = { balance = balance, rows = {}, log = {}, nextId = 1, removedFrom = {} }
    w.handle = { cid = 'CID1' }
    w.io = {
        player = function()
            if w.gone then return nil, w.gone end
            return w.handle
        end,
        balance = function(h)
            assert(h == w.handle, 'balance read on a stale handle')
            return w.balance
        end,
        insert = function()
            w.log[#w.log + 1] = 'insert'
            if opts.insertFails then return nil end
            local id = w.nextId; w.nextId = id + 1
            w.rows[id] = { kind = 'charge' }
            if opts.spendDuringInsert then w.balance = w.balance - opts.spendDuringInsert end -- the insert yields
            if opts.dropDuringInsert then w.gone = 'no_player' end
            if opts.switchDuringInsert then w.gone = 'player_changed' end
            if opts.newHandleDuringInsert then w.handle = { cid = 'CID1' } end -- same character, re-fetched object
            return id
        end,
        remove = function(h)
            w.log[#w.log + 1] = 'remove'
            w.removedFrom[#w.removedFrom + 1] = h
            if opts.removeRefuses then return false end
            w.balance = w.balance - w.amount
            return true
        end,
        add = function(h)
            w.log[#w.log + 1] = 'add'
            w.addedTo = h
            if opts.addRefuses then return false end
            w.balance = w.balance + w.amount
            return true
        end,
        void = function(id) w.log[#w.log + 1] = 'void'; if opts.voidFails then return false end; w.rows[id] = nil; return true end,
        warn = function(id, why) w.warned, w.warnedWhy = id, why end,
    }
    w.charge = function(amount) w.amount = amount; return logic.runCharge(w.io, amount) end
    w.pay = function(amount) w.amount = amount; return logic.runPay(w.io) end
    return w
end
local function count(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end

case('charge ok: ledger row first, then money, returns the row id', function()
    local w = wallet(50)
    local ok, err, id = w.charge(20)
    assert(ok == true and err == nil and id == 1)
    assert(w.balance == 30 and count(w.rows) == 1 and w.rows[1].kind == 'charge')
    T.same({ 'insert', 'remove' }, w.log)
end)
case('charge exact balance -> 0, never negative', function()
    local w = wallet(20)
    assert(w.charge(20) == true and w.balance == 0)
    local ok, err = w.charge(0.01)
    assert(ok == false and err == 'fh_insufficient_funds' and w.balance == 0 and count(w.rows) == 1)
end)
case('charge short: fh_insufficient_funds, no row, no money taken', function()
    local w = wallet(5)
    local ok, err, id = w.charge(20)
    assert(ok == false and err == 'fh_insufficient_funds' and id == nil)
    assert(w.balance == 5 and count(w.rows) == 0 and #w.log == 0)
end)
case('charge: no player at the start -> no_player, nothing written', function()
    local w = wallet(50); w.gone = 'no_player'
    local ok, err = w.charge(20)
    assert(ok == false and err == 'no_player' and #w.log == 0 and w.balance == 50)
end)
case('charge: ledger insert fails -> ledger_failed, no money taken', function()
    local w = wallet(50, { insertFails = true })
    local ok, err = w.charge(20)
    assert(ok == false and err == 'ledger_failed' and w.balance == 50)
    T.same({ 'insert' }, w.log)
end)
case('charge: spent during the insert yield -> short, row voided, balance untouched', function()
    local w = wallet(50, { spendDuringInsert = 40 })
    local ok, err = w.charge(20)
    assert(ok == false and err == 'fh_insufficient_funds' and w.balance == 10 and count(w.rows) == 0)
    T.same({ 'insert', 'void' }, w.log)
end)
case('charge: player dropped during the insert yield -> no_player, row voided, no money taken', function()
    local w = wallet(50, { dropDuringInsert = true })
    local ok, err = w.charge(20)
    assert(ok == false and err == 'no_player' and w.balance == 50 and count(w.rows) == 0)
    T.same({ 'insert', 'void' }, w.log)
end)
case('charge: character switched during the insert yield -> player_changed, row voided, no money taken', function()
    local w = wallet(50, { switchDuringInsert = true })
    local ok, err = w.charge(20)
    assert(ok == false and err == 'player_changed' and w.balance == 50 and count(w.rows) == 0)
    T.same({ 'insert', 'void' }, w.log)
end)
case('charge: money is removed from the handle fetched after the yield, never the pre-yield one', function()
    local w = wallet(50, { newHandleDuringInsert = true })
    local before = w.handle
    assert(w.charge(20) == true)
    assert(#w.removedFrom == 1 and w.removedFrom[1] == w.handle and w.removedFrom[1] ~= before)
end)
case('charge: RemoveMoney refused with funds -> removemoney_refused, row voided', function()
    local w = wallet(50, { removeRefuses = true })
    local ok, err = w.charge(20)
    assert(ok == false and err == 'removemoney_refused' and w.balance == 50 and count(w.rows) == 0)
    T.same({ 'insert', 'remove', 'void' }, w.log)
end)
case('charge: void fails -> warned with the row id and the reason', function()
    local w = wallet(50, { removeRefuses = true, voidFails = true })
    assert(w.charge(20) == false and w.warned == 1 and w.warnedWhy == 'removemoney_refused')
    local d = wallet(50, { dropDuringInsert = true, voidFails = true })
    local ok, err = d.charge(20)
    assert(ok == false and err == 'no_player' and d.warned == 1 and d.warnedWhy == 'no_player' and d.balance == 50)
end)

-- B7 fix: pay re-fetches the player after the insert yield too ---------------------------------------------------
case('pay ok: ledger row first, then money on the fresh handle', function()
    local w = wallet(0, { newHandleDuringInsert = true })
    local before = w.handle
    local ok, err, id = w.pay(15)
    assert(ok == true and err == nil and id == 1 and w.balance == 15 and count(w.rows) == 1)
    assert(w.addedTo == w.handle and w.addedTo ~= before)
    T.same({ 'insert', 'add' }, w.log)
end)
case('pay: player dropped / switched during the insert yield -> fails closed, row voided, nothing added', function()
    for opt, code in pairs({ dropDuringInsert = 'no_player', switchDuringInsert = 'player_changed' }) do
        local w = wallet(0, { [opt] = true })
        local ok, err = w.pay(15)
        assert(ok == false and err == code and w.balance == 0 and count(w.rows) == 0 and w.addedTo == nil, opt)
        T.same({ 'insert', 'void' }, w.log)
    end
end)
case('pay: AddMoney refused -> addmoney_refused, row voided; a failed void is warned', function()
    local w = wallet(0, { addRefuses = true })
    local ok, err = w.pay(15)
    assert(ok == false and err == 'addmoney_refused' and count(w.rows) == 0)
    local v = wallet(0, { addRefuses = true, voidFails = true })
    assert(v.pay(15) == false and v.warned == 1 and v.warnedWhy == 'addmoney_refused')
end)
case('pay: ledger insert fails -> ledger_failed, nothing added', function()
    local w = wallet(0, { insertFails = true })
    local ok, err = w.pay(15)
    assert(ok == false and err == 'ledger_failed' and w.balance == 0)
    T.same({ 'insert' }, w.log)
end)

-- B7 fix: per-key serialization -----------------------------------------------------------------------------------
case('serialized: a second call for a held key fails with the busy error and does not run', function()
    local locks, ran = {}, 0
    local co = coroutine.create(function()
        return logic.serialized(locks, 'CID1', 'fh_charge_busy', function(x)
            ran = ran + 1; coroutine.yield(); return true, nil, x
        end, 7)
    end)
    assert(coroutine.resume(co)) -- first caller is now in flight (yielded)
    assert(locks.CID1 == true)
    local ok, err = logic.serialized(locks, 'CID1', 'fh_charge_busy', function() ran = ran + 10 end)
    assert(ok == false and err == 'fh_charge_busy' and ran == 1)
    -- another key is independent
    assert(logic.serialized(locks, 'CID2', 'fh_charge_busy', function() return 'other' end) == 'other')
    local _, a, b, c = coroutine.resume(co)
    assert(a == true and b == nil and c == 7 and locks.CID1 == nil)
    assert(logic.serialized(locks, 'CID1', 'fh_charge_busy', function() return 'again' end) == 'again')
end)
case('serialized: the lock is released when fn throws (error re-raised)', function()
    local locks = {}
    local ok, e = pcall(logic.serialized, locks, 'CID1', 'busy', function() error('boom', 0) end)
    assert(ok == false and e == 'boom' and locks.CID1 == nil)
end)

-- B7 getRep -----------------------------------------------------------------------------------------------------
case('repValue: no row -> 0, row -> integer (floored)', function()
    assert(logic.repValue(nil) == 0 and math.type(logic.repValue(nil)) == 'integer')
    assert(logic.repValue(42) == 42 and math.type(logic.repValue(42.0)) == 'integer')
    assert(logic.repValue(7.9) == 7 and logic.repValue(-2.5) == -3)
    assert(logic.repValue('15') == 15 and logic.repValue(0/0) == 0 and logic.repValue('x') == 0)
end)
case('validCitizenid: rsg-style ids pass; digits-only, padded, blank, junk, too long and non-strings do not', function()
    for _, good in ipairs({ 'ABC12345', 'CID1', 'a_b-c' }) do assert(logic.validCitizenid(good) == true, good) end
    for _, bad in ipairs({ '12', '', ' ', ' ABC12345', 'ABC12345 ', 'AB C', "x'--", string.rep('A', 51), 12, true }) do
        assert(logic.validCitizenid(bad) == false, tostring(bad))
    end
    assert(logic.validCitizenid(nil) == false and logic.validCitizenid(string.rep('A', 50)) == true)
end)

case('validateCredit: valid citizenid, positive whole-cent amount (whole floats normalised), pay rules with maxCredit', function()
    local cr = { isKnownRegion = regions.isKnownRegion, maxCredit = 100, maxReason = 128 }
    local ok, err, n = logic.validateCredit({ citizenid = 'ABC1', amount = 5.0, reason = 'r', region_id = 'heartlands' }, cr)
    assert(ok == true and err == nil and n == 5 and math.type(n) == 'integer')
    for _, good in ipairs({ 1.13, 0.5, 0.01, 99.99, 1.5 }) do
        ok, err, n = logic.validateCredit({ citizenid = 'ABC1', amount = good, reason = 'r', region_id = 'heartlands' }, cr)
        assert(ok == true and err == nil and n == good, tostring(good))
    end
    for _, bad in ipairs({ 0, -1, 1.555, 0.004, 0.005, 1.005, '5', 0 / 0, math.huge, false }) do
        ok, err = logic.validateCredit({ citizenid = 'ABC1', amount = bad, reason = 'r', region_id = 'heartlands' }, cr)
        assert(ok == false and err == 'invalid_amount', tostring(bad))
    end
    T.eq('amount_too_large', select(2, logic.validateCredit({ citizenid = 'ABC1', amount = 101, reason = 'r', region_id = 'heartlands' }, cr)))
    T.eq('invalid_citizenid', select(2, logic.validateCredit({ citizenid = '42', amount = 5, reason = 'r', region_id = 'heartlands' }, cr)))
    T.eq('invalid_reason', select(2, logic.validateCredit({ citizenid = 'ABC1', amount = 5, reason = ' ', region_id = 'heartlands' }, cr)))
    T.eq('unknown_region', select(2, logic.validateCredit({ citizenid = 'ABC1', amount = 5, reason = 'r', region_id = 'x' }, cr)))
end)

T.finish()

-- Stubbed-server spec (core-07 A1, money-path audit): loads fh_economy's real server/main.lua with an in-memory
-- MySQL (fh_ledger, fh_pending_credit with the claim guard, players) and rsg-core Players, and drives:
--   1. the logout window: rsg-core's Logout fires RSGCore:Server:OnPlayerUnload, SAVES the character, then Wait(200)s
--      before RSGCore.Players[src] = nil (rsg-core/server/player.lua Logout). Money moved on that Player after the
--      save is never persisted. pay / charge / credit / the claim must refuse (or queue) once the unload fired.
--   2. AddMoney / RemoveMoney throwing AFTER the balance moved (rsg-core does the money first, then client / log side
--      effects): pay / charge must report what really happened, not void a row for money that did move.
--   3. amounts the cash backend cannot hold: rsg-core money items work in whole cents (math.floor(a * 100 + 0.5)), so
--      a sub-cent amount moves nothing; pay / charge round to whole cents and refuse what rounds to 0.
--   4. (A1 review) the throw-after check compares in integer cents: with money items on, rsg-core's sync re-reads cash
--      as tonumber(('%.2f'):format(...)), so 0.14 + 1 ~= 1.14 as doubles.
--   5. (A1 review) the unload tracker does not grow forever: entries are cleared after the playerDropped native once
--      rsg-core no longer has that character on the src, never while it still does.
-- Not a substitute for a live boot.
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local R = here .. '../server/resources/[fh]/'

local ledger, pending, events, exported, handlers, warnings = {}, {}, {}, {}, {}, {}
local known = {}
local nextLedger, nextPending = 1, 1
local pauseAt

local function maybePause(label)
    if pauseAt == label and coroutine.isyieldable() then
        pauseAt = nil
        coroutine.yield(label)
    end
end
local function has(q, s) return q:find(s, 1, true) ~= nil end
local function ledgerInsert(v)
    local id = nextLedger; nextLedger = id + 1
    ledger[id] = { id = id, citizenid = v[1], kind = v[2], amount = v[3], reason = v[4], region_id = v[5] }
    return id
end

local MySQL = {
    insert = { await = function(q, v)
        assert(has(q, 'INSERT INTO fh_ledger'), q)
        local id = ledgerInsert(v)
        maybePause('insert')
        return id
    end },
    update = { await = function(q, v)
        if has(q, 'DELETE FROM fh_ledger WHERE id = ?') then
            ledger[v[1]] = nil
            return 1
        elseif has(q, 'UPDATE fh_pending_credit SET claimed_by = ? WHERE citizenid = ? AND claimed_by IS NULL') then
            local n = 0
            for _, r in pairs(pending) do
                if r.citizenid == v[2] and r.claimed_by == nil then r.claimed_by = v[1]; n = n + 1 end
            end
            maybePause('claim')
            return n
        elseif has(q, 'SET claimed_by = NULL WHERE id = ? AND claimed_by = ?') then
            local r = pending[v[1]]
            if r and r.claimed_by == v[2] then r.claimed_by = nil; return 1 end
            return 0
        elseif has(q, 'SET claimed_by = NULL WHERE claimed_by = ?') then
            local n = 0
            for _, r in pairs(pending) do if r.claimed_by == v[1] then r.claimed_by = nil; n = n + 1 end end
            return n
        end
        error('unexpected update: ' .. q)
    end },
    query = { await = function(q, v)
        assert(has(q, 'FROM fh_pending_credit WHERE claimed_by = ?'), q)
        local out = {}
        for _, r in pairs(pending) do
            if r.claimed_by == v[1] then out[#out + 1] = { id = r.id, amount = r.amount, reason = r.reason, region_id = r.region_id } end
        end
        table.sort(out, function(a, b) return a.id < b.id end)
        maybePause('select')
        return out
    end },
    scalar = { await = function(q, v)
        if has(q, 'FROM players WHERE citizenid = ?') then return known[v[1]] and 1 or nil end
        if has(q, 'COUNT(*) FROM fh_pending_credit') then return 0 end
        error('unexpected scalar: ' .. q)
    end },
    transaction = { await = function(queries)
        maybePause('tx')
        for _, x in ipairs(queries) do
            local q, v = x.query, x.values
            if has(q, 'INSERT INTO fh_ledger') then
                ledgerInsert(v)
            elseif has(q, 'INSERT INTO fh_pending_credit') then
                local id = nextPending; nextPending = id + 1
                pending[id] = { id = id, citizenid = v[1], amount = v[2], reason = v[3], region_id = v[4] }
            elseif has(q, 'DELETE FROM fh_pending_credit WHERE id = ? AND claimed_by = ?') then
                local r = pending[v[1]]
                if r and r.claimed_by == v[2] then pending[v[1]] = nil end
            else
                error('unexpected tx query: ' .. q)
            end
        end
        return true
    end },
    ready = function(cb) cb() end,
}

local players = {}
local moneyMode = 'ok' -- 'ok' | 'throw_after' | 'throw_before' | 'norm_throw_after'
-- rsg-core money-item sync (moneyitems.lua SynchronizeMoneyItems / calculateTotal): cash re-read from the items
local function norm(x) return tonumber(string.format('%.2f', x)) end
local function mkPlayer(src, cid, cash)
    known[cid] = true
    local P = { PlayerData = { source = src, citizenid = cid, money = { cash = cash } }, Functions = {} }
    -- rsg-core/server/player.lua: the balance moves first, then UpdatePlayerData / log / OnMoneyChange side effects
    P.Functions.AddMoney = function(mtype, amount)
        if moneyMode == 'throw_before' then error('boom before') end
        P.PlayerData.money[mtype] = P.PlayerData.money[mtype] + amount
        if moneyMode == 'norm_throw_after' then
            P.PlayerData.money[mtype] = norm(P.PlayerData.money[mtype])
            error('boom after the money-item sync')
        end
        if moneyMode == 'throw_after' then error('boom after (UpdatePlayerData)') end
        return true
    end
    P.Functions.RemoveMoney = function(mtype, amount)
        if moneyMode == 'throw_before' then error('boom before') end
        local nb = P.PlayerData.money[mtype] - amount
        if nb < 0 then return false end
        P.PlayerData.money[mtype] = nb
        if moneyMode == 'norm_throw_after' then
            P.PlayerData.money[mtype] = norm(nb)
            error('boom after the money-item sync')
        end
        if moneyMode == 'throw_after' then error('boom after (UpdatePlayerData)') end
        return true
    end
    players[src] = P
    return P
end

local exportsT = setmetatable({}, {
    __index = function(_, res)
        assert(res == 'rsg-core', res)
        return {
            GetPlayer = function(_, src) return players[src] end,
            GetPlayerByCitizenId = function(_, cid)
                for _, P in pairs(players) do if P.PlayerData.citizenid == cid then return P end end
                return nil
            end,
        }
    end,
    __call = function(_, name, fn) exported[name] = fn end,
})
local timers = {} -- SetTimeout callbacks, run by the spec
local env = setmetatable({
    SetTimeout = function(_, fn) timers[#timers + 1] = fn end,
    exports = exportsT, MySQL = MySQL, GetCurrentResourceName = function() return 'fh_economy' end,
    TriggerEvent = function(name, payload) events[#events + 1] = { name = name, payload = payload } end,
    AddEventHandler = function(name, fn) handlers[name] = fn end,
    RegisterCommand = function() end, json = { encode = function() return '' end },
    print = function(...) warnings[#warnings + 1] = table.concat({ ... }, ' ') end,
}, { __index = _G })
env._G = env
local tracker -- the unload tracker main.lua creates (captured to check it does not grow)
for _, p in ipairs({ R .. 'fh_core/shared/regions.lua', R .. 'fh_economy/config.lua',
    R .. 'fh_economy/shared/ledger_logic.lua', R .. 'fh_economy/server/main.lua' }) do
    if p:find('server/main.lua', 1, true) and env.FhLedgerLogic.unloadTracker then
        local mk = env.FhLedgerLogic.unloadTracker
        env.FhLedgerLogic.unloadTracker = function(...) tracker = mk(...); return tracker end
    end
    local fh = assert(io.open(p, 'rb')); local src = fh:read('a'); fh:close()
    assert(load(src, '@' .. p, 't', env))()
end
local logic = env.FhLedgerLogic
local pay, charge, credit = exported.pay, exported.charge, exported.credit

local function count(t, pred)
    local n = 0
    for _, r in pairs(t) do if not pred or pred(r) then n = n + 1 end end
    return n
end
local function kindRows(cid, kind) return count(ledger, function(r) return r.citizenid == cid and r.kind == kind end) end
local function pendingOf(cid) return count(pending, function(r) return r.citizenid == cid end) end
local function claimedOf(cid) return count(pending, function(r) return r.citizenid == cid and r.claimed_by ~= nil end) end

-- rsg-core's own sequence, as far as fh_economy can see it
local function loaded(P) local h = handlers['RSGCore:Server:PlayerLoaded']; if h then h(P) end end
-- Logout: OnPlayerUnload(src), Save(), Wait(200) -> the Player is STILL in RSGCore.Players during the wait
local function unloadStart(src) local h = handlers['RSGCore:Server:OnPlayerUnload']; if h then h(src) end end
local function unloadEnd(src) players[src] = nil end
-- playerDropped: RSGCore:Server:PlayerDropped(Player), Save() (may yield in SaveInventory), then Players[src] = nil
local function dropStart(P) local h = handlers['RSGCore:Server:PlayerDropped']; if h then h(P) end end
-- the playerDropped native (global `source`), and the SetTimeouts it scheduled
local function dropNative(src) local h = handlers['playerDropped']; if h then env.source = src; h(); env.source = nil end end
local function runTimers() local due = timers; timers = {}; for _, fn in ipairs(due) do fn() end end

local function suspendAt(label, fn, ...)
    pauseAt = label
    local co = coroutine.create(fn)
    local okR, where = coroutine.resume(co, ...)
    pauseAt = nil
    assert(okR, where)
    assert(coroutine.status(co) == 'suspended' and where == label, 'expected to be suspended at ' .. label)
    return function()
        local r = table.pack(coroutine.resume(co))
        assert(r[1], r[2])
        assert(coroutine.status(co) == 'dead', 'expected to finish after one resume')
        return table.unpack(r, 2, r.n)
    end
end

T.describe('fh_economy: the logout window (saved, still in RSGCore.Players)', function()
    T.it('pay suspended in its ledger insert while the character logs out: refused, row voided, no money', function()
        local P = mkPlayer(1, 'CIDL1', 10); loaded(P)
        local finish = suspendAt('insert', pay, 1, 25, 'bounty', 'heartlands')
        unloadStart(1) -- final save happened here; P is still in Players for 200 ms
        local ok, err = finish()
        T.eq(false, ok); T.eq('no_player', err)
        T.eq(10, P.PlayerData.money.cash); T.eq(0, kindRows('CIDL1', 'pay'))
        unloadEnd(1)
    end)
    T.it('charge suspended in its ledger insert while the character logs out: refused, row voided, nothing taken', function()
        local P = mkPlayer(2, 'CIDL2', 50); loaded(P)
        local finish = suspendAt('insert', charge, 2, 20, 'lot', 'heartlands')
        unloadStart(2)
        local ok, err = finish()
        T.eq(false, ok); T.eq('no_player', err)
        T.eq(50, P.PlayerData.money.cash); T.eq(0, kindRows('CIDL2', 'charge'))
        unloadEnd(2)
    end)
    T.it('pay / charge started inside the window: refused before anything is written', function()
        local P = mkPlayer(3, 'CIDL3', 50); loaded(P)
        unloadStart(3)
        T.eq('no_player', select(2, pay(3, 5, 'x', 'heartlands')))
        T.eq('no_player', select(2, charge(3, 5, 'x', 'heartlands')))
        T.eq(50, P.PlayerData.money.cash); T.eq(0, count(ledger, function(r) return r.citizenid == 'CIDL3' end))
        unloadEnd(3)
    end)
    T.it('credit inside the window is queued (not added to the saved-and-discarded Player), paid once on re-login', function()
        local P = mkPlayer(4, 'CIDL4', 0); loaded(P)
        unloadStart(4)
        local ok, err, mode = credit('CIDL4', 15, 'refund', 'heartlands')
        T.eq(true, ok); T.eq(nil, err); T.eq('pending', mode)
        T.eq(0, P.PlayerData.money.cash); T.eq(1, pendingOf('CIDL4')); T.eq(0, kindRows('CIDL4', 'credit'))
        unloadEnd(4)
        local P2 = mkPlayer(4, 'CIDL4', 0); loaded(P2); loaded(P2)
        T.eq(15, P2.PlayerData.money.cash); T.eq(0, pendingOf('CIDL4')); T.eq(1, kindRows('CIDL4', 'credit'))
    end)
    T.it('claim suspended mid-read while the character logs out: nothing paid, rows released, paid once later', function()
        known.CIDL5 = true
        assert(credit('CIDL5', 9, 'refund', 'heartlands') == true)
        local P = mkPlayer(5, 'CIDL5', 0)
        local finish = suspendAt('select', handlers['RSGCore:Server:PlayerLoaded'], P)
        unloadStart(5)
        finish()
        T.eq(0, P.PlayerData.money.cash); T.eq(1, pendingOf('CIDL5')); T.eq(0, claimedOf('CIDL5'))
        unloadEnd(5)
        local P2 = mkPlayer(5, 'CIDL5', 0); loaded(P2)
        T.eq(9, P2.PlayerData.money.cash); T.eq(0, pendingOf('CIDL5'))
    end)
    T.it('playerDropped (PlayerDropped fired, save in progress): pay in flight refused', function()
        local P = mkPlayer(6, 'CIDL6', 10); loaded(P)
        local finish = suspendAt('insert', pay, 6, 5, 'bounty', 'heartlands')
        dropStart(P)
        local ok, err = finish()
        T.eq(false, ok); T.eq('no_player', err); T.eq(10, P.PlayerData.money.cash); T.eq(0, kindRows('CIDL6', 'pay'))
        players[6] = nil
    end)
    T.it('re-login of the same character on the same src clears the window: pay works again', function()
        local P = mkPlayer(1, 'CIDL1', 10); loaded(P)
        T.eq(true, (pay(1, 5, 'bounty', 'heartlands')))
        T.eq(15, P.PlayerData.money.cash)
    end)
    T.it('another character loaded on a src that logged out is not blocked', function()
        local P = mkPlayer(2, 'CIDL2B', 10); loaded(P)
        T.eq(true, (pay(2, 5, 'bounty', 'heartlands')))
        T.eq(15, P.PlayerData.money.cash)
    end)
end)

T.describe('fh_economy: rsg-core money call throws', function()
    T.it('pay: AddMoney throws AFTER adding -> ok (money moved once, ledger row kept, paid event)', function()
        local P = mkPlayer(20, 'CIDT1', 127.2); loaded(P)
        moneyMode = 'throw_after'
        local ok, err, id = pay(20, 5, 'bounty', 'heartlands')
        moneyMode = 'ok'
        T.eq(true, ok); T.eq(nil, err)
        T.eq(127.2 + 5, P.PlayerData.money.cash); T.eq(1, kindRows('CIDT1', 'pay')); T.eq('pay', ledger[id].kind)
        T.eq('fh:economy:paid', events[#events].name)
    end)
    T.it('pay: AddMoney throws BEFORE adding -> addmoney_refused, row voided, no money', function()
        local P = players[20]
        local before = P.PlayerData.money.cash
        moneyMode = 'throw_before'
        local ok, err = pay(20, 5, 'bounty', 'heartlands')
        moneyMode = 'ok'
        T.eq(false, ok); T.eq('addmoney_refused', err); T.eq(before, P.PlayerData.money.cash); T.eq(1, kindRows('CIDT1', 'pay'))
    end)
    T.it('charge: RemoveMoney throws AFTER removing -> ok (money taken once, ledger row kept, charged event)', function()
        local P = mkPlayer(21, 'CIDT2', 127.2); loaded(P)
        moneyMode = 'throw_after'
        local ok, err, id = charge(21, 5, 'lot', 'heartlands')
        moneyMode = 'ok'
        T.eq(true, ok); T.eq(nil, err)
        T.eq(127.2 - 5, P.PlayerData.money.cash); T.eq(1, kindRows('CIDT2', 'charge')); T.eq('charge', ledger[id].kind)
        T.eq('fh:economy:charged', events[#events].name)
    end)
    T.it('charge: RemoveMoney throws BEFORE removing -> removemoney_refused, row voided, nothing taken', function()
        local P = players[21]
        local before = P.PlayerData.money.cash
        moneyMode = 'throw_before'
        local ok, err = charge(21, 5, 'lot', 'heartlands')
        moneyMode = 'ok'
        T.eq(false, ok); T.eq('removemoney_refused', err); T.eq(before, P.PlayerData.money.cash)
        T.eq(1, kindRows('CIDT2', 'charge'))
    end)
end)

T.describe('fh_economy: throw-after check in integer cents (money-item sync, %.2f balances)', function()
    T.it('movedBy compares in cents: true for real moves, false otherwise or on junk', function()
        assert(0.14 + 1 ~= 1.14 and 1.14 - 1 ~= 0.14, 'precondition: the float compare is inexact here')
        T.eq(true, logic.movedBy(0.14, 1.14, 1)); T.eq(true, logic.movedBy(1.14, 0.14, -1))
        T.eq(true, logic.movedBy(0.1 + 0.2, 1.3, 1)); T.eq(true, logic.movedBy(127.2, 132.2, 5))
        T.eq(false, logic.movedBy(0.14, 0.14, 1)); T.eq(false, logic.movedBy(0.14, 1.13, 1))
        T.eq(false, logic.movedBy(1.14, 1.14, -1))
        T.eq(false, logic.movedBy(nil, 1, 1)); T.eq(false, logic.movedBy(0, 0 / 0, 1)); T.eq(false, logic.movedBy(0, 1, math.huge))
    end)
    T.it('pay: balance 0.14, AddMoney(1) re-synced to 1.14 then throws -> ok, row kept (not voided / re-paid)', function()
        local P = mkPlayer(40, 'CIDN1', 0.14); loaded(P)
        moneyMode = 'norm_throw_after'
        local ok, err, id = pay(40, 1, 'bounty', 'heartlands')
        moneyMode = 'ok'
        T.eq(true, ok); T.eq(nil, err); T.eq(1.14, P.PlayerData.money.cash); T.eq('pay', ledger[id] and ledger[id].kind)
    end)
    T.it('charge: balance 1.14, RemoveMoney(1) re-synced to 0.14 then throws -> ok, row kept', function()
        local P = mkPlayer(41, 'CIDN2', 1.14); loaded(P)
        moneyMode = 'norm_throw_after'
        local ok, err, id = charge(41, 1, 'lot', 'heartlands')
        moneyMode = 'ok'
        T.eq(true, ok); T.eq(nil, err); T.eq(0.14, P.PlayerData.money.cash); T.eq('charge', ledger[id] and ledger[id].kind)
    end)
    T.it('credit online on 0.14: paid once, not queued for a second payment', function()
        local P = mkPlayer(42, 'CIDN3', 0.14); loaded(P)
        moneyMode = 'norm_throw_after'
        local ok, _, mode = credit('CIDN3', 1, 'refund', 'heartlands')
        moneyMode = 'ok'
        T.eq(true, ok); T.eq('paid', mode); T.eq(0, pendingOf('CIDN3'))
        loaded(P); T.eq(1.14, P.PlayerData.money.cash); T.eq(1, kindRows('CIDN3', 'credit'))
    end)
    T.it('load claim on 0.14: the queued credit is paid once and cleared, not released for a second payment', function()
        known.CIDN4 = true
        assert(credit('CIDN4', 1, 'refund', 'heartlands') == true)
        local P = mkPlayer(43, 'CIDN4', 0.14)
        moneyMode = 'norm_throw_after'; loaded(P); moneyMode = 'ok'
        T.eq(1.14, P.PlayerData.money.cash); T.eq(0, pendingOf('CIDN4'))
        loaded(P); T.eq(1.14, P.PlayerData.money.cash); T.eq(1, kindRows('CIDN4', 'credit'))
    end)
end)

T.describe('fh_economy: the unload tracker is cleared after playerDropped', function()
    T.it('logout then quit at character select: entry cleared once the timer runs', function()
        assert(tracker, 'main.lua builds its unload tracker with FhLedgerLogic.unloadTracker')
        local n0 = tracker.size()
        local P = mkPlayer(50, 'CIDU1', 10); loaded(P)
        unloadStart(50); T.eq(n0 + 1, tracker.size())
        unloadEnd(50)
        dropNative(50); T.eq(n0 + 1, tracker.size()) -- deferred, not cleared inside the handler
        runTimers(); T.eq(n0, tracker.size())
    end)
    T.it('drop while the save is still running (character still loaded): kept, still refused, cleared later', function()
        local n0 = tracker.size()
        local P = mkPlayer(51, 'CIDU2', 10); loaded(P)
        dropStart(P); dropNative(51)
        runTimers() -- rsg-core has not removed the Player yet
        T.eq(n0 + 1, tracker.size()); T.eq(1, #timers, 'rescheduled')
        T.eq('no_player', select(2, pay(51, 5, 'x', 'heartlands'))); T.eq(10, P.PlayerData.money.cash)
        players[51] = nil
        runTimers(); T.eq(n0, tracker.size()); T.eq(0, #timers)
    end)
    T.it('many players come and go on ever-higher server ids: no entries left behind', function()
        local n0 = tracker.size()
        for src = 100, 149 do
            local P = mkPlayer(src, 'CIDM' .. src, 1); loaded(P)
            if src % 2 == 0 then unloadStart(src); unloadEnd(src) else dropStart(P); players[src] = nil end
            dropNative(src)
        end
        T.eq(n0 + 50, tracker.size())
        runTimers(); T.eq(n0, tracker.size())
    end)
    T.it('a drop with nothing marked (never loaded a character) changes nothing', function()
        local n0 = tracker.size()
        dropNative(160); runTimers(); T.eq(n0, tracker.size()); T.eq(0, #timers)
    end)
end)

T.describe('fh_economy: whole cents only (rsg-core money items)', function()
    T.it('sub-cent pay / charge is refused before anything is written', function()
        local P = mkPlayer(30, 'CIDC1', 10); loaded(P)
        for _, a in ipairs({ 0.004, 0.001, 1e-300 }) do
            T.eq('invalid_amount', select(2, pay(30, a, 'x', 'heartlands')), tostring(a))
            T.eq('invalid_amount', select(2, charge(30, a, 'x', 'heartlands')), tostring(a))
        end
        T.eq(10, P.PlayerData.money.cash); T.eq(0, count(ledger, function(r) return r.citizenid == 'CIDC1' end))
    end)
    T.it('a fractional amount is rounded to whole cents; ledger, money and event carry the rounded amount', function()
        local P = mkPlayer(31, 'CIDC2', 10); loaded(P)
        local ok, _, id = pay(31, 2.499, 'x', 'heartlands')
        T.eq(true, ok); T.eq(2.5, ledger[id].amount); T.eq(12.5, P.PlayerData.money.cash)
        T.eq(2.5, events[#events].payload.amount)
        ok, _, id = charge(31, 0.995, 'x', 'heartlands')
        T.eq(true, ok); T.eq(1, ledger[id].amount); T.eq('integer', math.type(ledger[id].amount))
        T.eq(11.5, P.PlayerData.money.cash)
        ok, _, id = pay(31, 0.29, 'x', 'heartlands')
        T.eq(true, ok); T.eq(0.29, ledger[id].amount)
    end)
    T.it('whole amounts stay Lua integers (5.0 -> 5)', function()
        local P = mkPlayer(32, 'CIDC3', 10); loaded(P)
        local _, _, id = pay(32, 5.0, 'x', 'heartlands')
        T.eq('integer', math.type(ledger[id].amount)); T.eq(5, ledger[id].amount)
        _, _, id = charge(32, 7, 'x', 'heartlands')
        T.eq('integer', math.type(ledger[id].amount))
    end)
    T.it('the cap is checked on the amount as given', function()
        mkPlayer(33, 'CIDC4', 10)
        T.eq('amount_too_large', select(2, pay(33, 100000.004, 'x', 'heartlands')))
        T.eq('amount_too_large', select(2, charge(33, 1e308, 'x', 'heartlands')))
    end)
end)

T.finish()

-- Stubbed-server spec (core-04 E2, idea-700): loads fh_economy's real server/main.lua with an in-memory MySQL that
-- models fh_ledger, fh_pending_credit (incl. the claim guard `claimed_by IS NULL`) and the players table, plus
-- rsg-core Players. Drives credit() online / offline and the claim on RSGCore:Server:PlayerLoaded end to end.
-- `pauseAt = '<label>'` makes the next matching fake await yield the calling coroutine (as oxmysql's await does), so
-- a spec can interleave two claims or drop the player mid-yield. Not a substitute for a live boot.
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local R = here .. '../server/resources/[fh]/'

local ledger, pending, events, exported, handlers, warnings = {}, {}, {}, {}, {}, {}
local known = { CIDON = true, CIDOFF = true } -- rows in the `players` table
local nextLedger, nextPending = 1, 1
local fail = {} -- fail.insert / fail.tx / fail.claim / fail.select / fail.release / fail.void
local pauseAt

local function maybePause(label)
    if pauseAt == label and coroutine.isyieldable() then
        pauseAt = nil
        coroutine.yield(label)
    end
end

local function ledgerInsert(v)
    local id = nextLedger; nextLedger = id + 1
    ledger[id] = { id = id, citizenid = v[1], kind = v[2], amount = v[3], reason = v[4], region_id = v[5] }
    return id
end

local function has(q, s) return q:find(s, 1, true) ~= nil end

local MySQL = {
    insert = { await = function(q, v)
        assert(has(q, 'INSERT INTO fh_ledger'), q)
        if fail.insert then error('db down') end
        local id = ledgerInsert(v)
        maybePause('insert')
        return id
    end },
    update = { await = function(q, v)
        if has(q, 'DELETE FROM fh_ledger WHERE id = ?') then
            if fail.void then error('db down') end
            ledger[v[1]] = nil
            return 1
        elseif has(q, 'UPDATE fh_pending_credit SET claimed_by = ? WHERE citizenid = ?') then
            if fail.claim then error('db down') end
            -- the real UPDATE is atomic: decide and set every row in one step, no yield inside
            local guarded, n = has(q, 'claimed_by IS NULL'), 0
            for _, r in pairs(pending) do
                if r.citizenid == v[2] and (not guarded or r.claimed_by == nil) then r.claimed_by = v[1]; n = n + 1 end
            end
            maybePause('claim')
            return n
        elseif has(q, 'SET claimed_by = NULL WHERE id = ? AND claimed_by = ?') then
            if fail.release then error('db down') end
            local r = pending[v[1]]
            if r and r.claimed_by == v[2] then r.claimed_by = nil; return 1 end
            return 0
        elseif has(q, 'SET claimed_by = NULL WHERE claimed_by = ?') then
            if fail.release then error('db down') end
            local n = 0
            for _, r in pairs(pending) do if r.claimed_by == v[1] then r.claimed_by = nil; n = n + 1 end end
            return n
        end
        error('unexpected update: ' .. q)
    end },
    query = { await = function(q, v)
        assert(has(q, 'FROM fh_pending_credit WHERE claimed_by = ?'), q)
        if fail.select then error('db down') end
        local out = {}
        for _, r in pairs(pending) do
            if r.claimed_by == v[1] then
                out[#out + 1] = { id = r.id, amount = r.amount, reason = r.reason, region_id = r.region_id }
            end
        end
        table.sort(out, function(a, b) return a.id < b.id end)
        maybePause('select')
        return out
    end },
    scalar = { await = function(q, v)
        if has(q, 'FROM players WHERE citizenid = ?') then
            if fail.players then error('db down') end
            return known[v[1]] and 1 or nil
        elseif has(q, 'COUNT(*) FROM fh_pending_credit WHERE claimed_by IS NOT NULL') then
            local n = 0
            for _, r in pairs(pending) do if r.claimed_by ~= nil then n = n + 1 end end
            return n
        end
        error('unexpected scalar: ' .. q)
    end },
    transaction = { await = function(queries)
        if fail.tx then error('db down') end
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

-- Seeded before load: a row claimed by an earlier run, for the start-up audit warning.
pending[nextPending] = { id = nextPending, citizenid = 'CIDSTALE', amount = 7, reason = 'x', region_id = 'heartlands',
    claimed_by = 'oldboot:1:CIDSTALE' }
nextPending = nextPending + 1

local players = {}
local addMode = 'ok' -- 'ok' | 'refuse' | 'throw_before' | 'throw_after'
local function mkPlayer(src, cid, cash)
    local P = { PlayerData = { source = src, citizenid = cid, money = { cash = cash } }, Functions = {} }
    -- rsg-core/server/player.lua AddMoney: adds to PlayerData.money first, then client / log side effects
    P.Functions.AddMoney = function(mtype, amount)
        if addMode == 'refuse' then return false end
        if addMode == 'throw_before' then error('boom before') end
        P.PlayerData.money[mtype] = P.PlayerData.money[mtype] + amount
        if addMode == 'throw_after' then error('boom after (UpdatePlayerData)') end
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
local env = setmetatable({
    exports = exportsT, MySQL = MySQL, GetCurrentResourceName = function() return 'fh_economy' end,
    TriggerEvent = function(name, payload) events[#events + 1] = { name = name, payload = payload } end,
    AddEventHandler = function(name, fn) handlers[name] = fn end,
    RegisterCommand = function() end, json = { encode = function() return '' end },
    print = function(...) warnings[#warnings + 1] = table.concat({ ... }, ' ') end,
}, { __index = _G })
env._G = env
for _, p in ipairs({ R .. 'fh_core/shared/regions.lua', R .. 'fh_economy/config.lua',
    R .. 'fh_economy/shared/ledger_logic.lua', R .. 'fh_economy/server/main.lua' }) do
    local fh = assert(io.open(p, 'rb')); local src = fh:read('a'); fh:close()
    assert(load(src, '@' .. p, 't', env))()
end
local credit = exported.credit
local onLoaded = assert(handlers['RSGCore:Server:PlayerLoaded'], 'PlayerLoaded handler registered')

local function count(t, pred)
    local n = 0
    for _, r in pairs(t) do if not pred or pred(r) then n = n + 1 end end
    return n
end
local function kindRows(cid, kind) return count(ledger, function(r) return r.citizenid == cid and r.kind == kind end) end
local function pendingOf(cid) return count(pending, function(r) return r.citizenid == cid end) end
local function creditedEvents(cid)
    return count(events, function(e) return e.name == 'fh:economy:credited' and e.payload.citizenid == cid end)
end
local function loadChar(P) onLoaded(P) end

-- Start fn(...) in a coroutine that must suspend at the fake await `label`; returns a finisher.
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

-- Queue `amounts` for an offline, known citizenid (players table) and return how many pending rows it has.
local function queueOffline(cid, amounts)
    known[cid] = true
    for _, a in ipairs(amounts) do
        local ok, err, mode = credit(cid, a, 'plot_refund', 'heartlands')
        assert(ok == true and err == nil and mode == 'pending', tostring(err))
    end
    return pendingOf(cid)
end

T.describe('fh_economy start-up audit', function()
    T.it('a row claimed by an earlier run is warned about at start and not released', function()
        local w = warnings[1] or ''
        assert(w:find('WARNING', 1, true) and w:find('1 fh_pending_credit row', 1, true), w)
        T.eq('oldboot:1:CIDSTALE', pending[1].claimed_by)
        pending[1] = nil
    end)
end)

T.describe('fh_economy.credit online', function()
    T.it('online citizenid: cash added now, one ledger row kind=credit, credited event, no pending row', function()
        local P = mkPlayer(1, 'CIDON', 10)
        local ok, err, mode = credit('CIDON', 25, 'plot_refund', 'heartlands')
        T.eq(true, ok); T.eq(nil, err); T.eq('paid', mode)
        T.eq(35, P.PlayerData.money.cash)
        T.eq(1, kindRows('CIDON', 'credit')); T.eq(0, kindRows('CIDON', 'credit_pending')); T.eq(0, pendingOf('CIDON'))
        local e = events[#events]
        T.eq('fh:economy:credited', e.name)
        T.eq(1, e.payload.src); T.eq(25, e.payload.amount); T.eq(false, e.payload.queued)
        T.eq('credit', ledger[e.payload.ledger_id].kind)
    end)
    T.it('online but AddMoney refused: the credit row is voided and the credit is queued instead (not lost)', function()
        local P = players[1]
        addMode = 'refuse'
        local ok, err, mode = credit('CIDON', 5, 'plot_refund', 'heartlands')
        addMode = 'ok'
        T.eq(true, ok); T.eq(nil, err); T.eq('pending', mode)
        T.eq(35, P.PlayerData.money.cash)
        T.eq(1, kindRows('CIDON', 'credit')); T.eq(1, kindRows('CIDON', 'credit_pending')); T.eq(1, pendingOf('CIDON'))
        -- the immediate claim (the character is online) was refused too: the row is released, not stuck
        T.eq(nil, select(2, next(pending)).claimed_by)
        loadChar(P)
        T.eq(40, P.PlayerData.money.cash); T.eq(0, pendingOf('CIDON')); T.eq(2, kindRows('CIDON', 'credit'))
    end)
    T.it('player drops during the ledger insert yield: row voided, credit queued, paid once on the next load', function()
        local P = mkPlayer(2, 'CIDDROP', 0)
        local finish = suspendAt('insert', credit, 'CIDDROP', 15, 'plot_refund', 'heartlands')
        players[2] = nil
        local ok, err, mode = finish()
        T.eq(true, ok); T.eq(nil, err); T.eq('pending', mode)
        T.eq(0, P.PlayerData.money.cash); T.eq(0, kindRows('CIDDROP', 'credit')); T.eq(1, pendingOf('CIDDROP'))
        players[2] = P; loadChar(P); loadChar(P)
        T.eq(15, P.PlayerData.money.cash); T.eq(0, pendingOf('CIDDROP')); T.eq(1, kindRows('CIDDROP', 'credit'))
    end)
end)

T.describe('fh_economy.credit offline', function()
    T.it('offline known citizenid -> pending row + ledger credit_pending, no money anywhere, no credited event', function()
        local nEv = #events
        local ok, err, mode = credit('CIDOFF', 40, 'plot_refund', 'heartlands')
        T.eq(true, ok); T.eq(nil, err); T.eq('pending', mode)
        T.eq(1, pendingOf('CIDOFF')); T.eq(1, kindRows('CIDOFF', 'credit_pending')); T.eq(0, kindRows('CIDOFF', 'credit'))
        local _, r = next(pending)
        T.same({ citizenid = 'CIDOFF', amount = 40, reason = 'plot_refund', region_id = 'heartlands' },
            { citizenid = r.citizenid, amount = r.amount, reason = r.reason, region_id = r.region_id })
        T.eq(nil, r.claimed_by); T.eq(nEv, #events)
    end)
    T.it('unknown citizenid (no players row) -> unknown_citizenid, nothing written', function()
        local nL, nP = count(ledger), count(pending)
        T.eq('unknown_citizenid', select(2, credit('NOSUCH', 5, 'x', 'heartlands')))
        T.eq(nL, count(ledger)); T.eq(nP, count(pending))
    end)
    T.it('queue transaction fails -> ledger_failed, nothing written', function()
        local nL, nP = count(ledger), count(pending)
        fail.tx = true
        local ok, err = credit('CIDOFF', 5, 'x', 'heartlands'); fail.tx = false
        T.eq(false, ok); T.eq('ledger_failed', err); T.eq(nL, count(ledger)); T.eq(nP, count(pending))
    end)
    T.it('players lookup fails -> ledger_failed, nothing written', function()
        local nL, nP = count(ledger), count(pending)
        fail.players = true
        local ok, err = credit('CIDOFF', 5, 'x', 'heartlands'); fail.players = false
        T.eq(false, ok); T.eq('ledger_failed', err); T.eq(nL, count(ledger)); T.eq(nP, count(pending))
    end)
    T.it('character loads while the queue insert is in flight: claimed at once, paid exactly once', function()
        known.CIDRACE = true
        local finish = suspendAt('tx', credit, 'CIDRACE', 9, 'plot_refund', 'heartlands')
        local P = mkPlayer(3, 'CIDRACE', 0)
        loadChar(P) -- its claim ran before our row existed: nothing to claim
        T.eq(0, P.PlayerData.money.cash)
        local ok, _, mode = finish()
        T.eq(true, ok); T.eq('pending', mode)
        T.eq(9, P.PlayerData.money.cash); T.eq(0, pendingOf('CIDRACE')); T.eq(1, kindRows('CIDRACE', 'credit'))
        loadChar(P); T.eq(9, P.PlayerData.money.cash)
    end)
end)

T.describe('fh_economy.credit validation', function()
    T.it('bad amount / citizenid / reason / region refused before touching anything', function()
        local nL, nP, nEv = count(ledger), count(pending), #events
        for _, bad in ipairs({ 0, -5, 5.5, 0.5, '5', 0 / 0, math.huge, -math.huge, true }) do
            T.eq('invalid_amount', select(2, credit('CIDOFF', bad, 'x', 'heartlands')), tostring(bad))
        end
        T.eq('invalid_amount', select(2, credit('CIDOFF', nil, 'x', 'heartlands')))
        T.eq('amount_too_large', select(2, credit('CIDOFF', 1e9, 'x', 'heartlands')))
        T.eq('amount_too_large', select(2, credit('CIDOFF', 100001, 'x', 'heartlands')))
        T.eq('invalid_reason', select(2, credit('CIDOFF', 5, '', 'heartlands')))
        T.eq('invalid_reason', select(2, credit('CIDOFF', 5, string.rep('r', 129), 'heartlands')))
        T.eq('unknown_region', select(2, credit('CIDOFF', 5, 'x', 'nowhere')))
        for _, bad in ipairs({ '12', ' CIDOFF', '', "CIDOFF' OR 1=1", 12, {} }) do
            T.eq('invalid_citizenid', select(2, credit(bad, 5, 'x', 'heartlands')), tostring(bad))
        end
        T.eq(nL, count(ledger)); T.eq(nP, count(pending)); T.eq(nEv, #events)
    end)
    T.it('a whole float is taken as an integer amount', function()
        known.CIDFLT = true
        assert(credit('CIDFLT', 5.0, 'x', 'heartlands') == true)
        local r
        for _, x in pairs(pending) do if x.citizenid == 'CIDFLT' then r = x end end
        T.eq('integer', math.type(r.amount)); T.eq(5, r.amount)
    end)
end)

T.describe('fh_economy claim on character load', function()
    T.it('pays every pending row once, writes credit rows, deletes them; a second load pays nothing', function()
        T.eq(2, queueOffline('CIDA', { 10, 32 }))
        local P = mkPlayer(10, 'CIDA', 1)
        loadChar(P)
        T.eq(43, P.PlayerData.money.cash); T.eq(0, pendingOf('CIDA'))
        T.eq(2, kindRows('CIDA', 'credit')); T.eq(2, kindRows('CIDA', 'credit_pending'))
        T.eq(2, creditedEvents('CIDA')); T.eq(true, events[#events].payload.queued); T.eq(10, events[#events].payload.src)
        loadChar(P) -- double load / reconnect
        T.eq(43, P.PlayerData.money.cash); T.eq(2, kindRows('CIDA', 'credit')); T.eq(2, creditedEvents('CIDA'))
    end)
    T.it('concurrent claims (first suspended after it read its rows): paid exactly once', function()
        T.eq(2, queueOffline('CIDB', { 10, 20 }))
        local P = mkPlayer(11, 'CIDB', 0)
        local finishA = suspendAt('select', onLoaded, P) -- A claimed and read both rows, not yet paid
        loadChar(P) -- B: a second load event for the same character runs to the end meanwhile
        finishA()
        T.eq(30, P.PlayerData.money.cash); T.eq(0, pendingOf('CIDB')); T.eq(2, kindRows('CIDB', 'credit'))
        T.eq(2, creditedEvents('CIDB'))
    end)
    T.it('concurrent claims (first suspended right after its UPDATE): the second claims nothing, paid once', function()
        T.eq(1, queueOffline('CIDC', { 12 }))
        local P = mkPlayer(12, 'CIDC', 0)
        local finishA = suspendAt('claim', onLoaded, P)
        loadChar(P)
        T.eq(0, P.PlayerData.money.cash) -- B saw only A's claimed row
        finishA()
        T.eq(12, P.PlayerData.money.cash); T.eq(0, pendingOf('CIDC')); T.eq(1, kindRows('CIDC', 'credit'))
    end)
    T.it('AddMoney refused after the claim: nothing paid, rows released (not stuck), paid once on the next load', function()
        T.eq(2, queueOffline('CIDD', { 4, 6 }))
        local P = mkPlayer(13, 'CIDD', 0)
        addMode = 'refuse'; loadChar(P); addMode = 'ok'
        T.eq(0, P.PlayerData.money.cash); T.eq(2, pendingOf('CIDD')); T.eq(0, kindRows('CIDD', 'credit'))
        T.eq(0, count(pending, function(r) return r.citizenid == 'CIDD' and r.claimed_by ~= nil end))
        loadChar(P); loadChar(P)
        T.eq(10, P.PlayerData.money.cash); T.eq(0, pendingOf('CIDD')); T.eq(2, kindRows('CIDD', 'credit'))
    end)
    T.it('AddMoney throws BEFORE adding: treated as not paid, released, paid once later', function()
        T.eq(1, queueOffline('CIDE', { 8 }))
        local P = mkPlayer(14, 'CIDE', 0)
        addMode = 'throw_before'; loadChar(P); addMode = 'ok'
        T.eq(0, P.PlayerData.money.cash); T.eq(1, pendingOf('CIDE'))
        loadChar(P); loadChar(P)
        T.eq(8, P.PlayerData.money.cash); T.eq(0, pendingOf('CIDE'))
    end)
    T.it('AddMoney throws AFTER adding: counted as paid, row deleted, never paid again', function()
        T.eq(1, queueOffline('CIDF', { 8 }))
        local P = mkPlayer(15, 'CIDF', 0)
        addMode = 'throw_after'; loadChar(P); addMode = 'ok'
        T.eq(8, P.PlayerData.money.cash); T.eq(0, pendingOf('CIDF')); T.eq(1, kindRows('CIDF', 'credit'))
        loadChar(P); T.eq(8, P.PlayerData.money.cash)
    end)
    T.it('clearing the paid rows fails: money paid once, rows left CLAIMED (never re-paid), warning names them', function()
        T.eq(1, queueOffline('CIDG', { 5 }))
        local P = mkPlayer(16, 'CIDG', 0)
        local nWarn = #warnings
        fail.tx = true; loadChar(P); fail.tx = false
        T.eq(5, P.PlayerData.money.cash); T.eq(1, pendingOf('CIDG'))
        T.eq(1, count(pending, function(r) return r.citizenid == 'CIDG' and r.claimed_by ~= nil end))
        T.eq(nWarn + 1, #warnings)
        assert(warnings[#warnings]:find('PAID but not cleared', 1, true), warnings[#warnings])
        loadChar(P); loadChar(P)
        T.eq(5, P.PlayerData.money.cash)
    end)
    T.it('player drops during the claim yield: nothing paid, rows released, paid once on the next load', function()
        T.eq(1, queueOffline('CIDH', { 11 }))
        local P = mkPlayer(17, 'CIDH', 0)
        local finish = suspendAt('select', onLoaded, P)
        players[17] = nil
        finish()
        T.eq(0, P.PlayerData.money.cash); T.eq(1, pendingOf('CIDH'))
        T.eq(0, count(pending, function(r) return r.citizenid == 'CIDH' and r.claimed_by ~= nil end))
        players[17] = P; loadChar(P)
        T.eq(11, P.PlayerData.money.cash); T.eq(0, pendingOf('CIDH'))
    end)
    T.it('claim read fails: the claim is released, nothing paid, paid once on the next load', function()
        T.eq(1, queueOffline('CIDI', { 3 }))
        local P = mkPlayer(18, 'CIDI', 0)
        fail.select = true; loadChar(P); fail.select = false
        T.eq(0, P.PlayerData.money.cash)
        T.eq(0, count(pending, function(r) return r.citizenid == 'CIDI' and r.claimed_by ~= nil end))
        loadChar(P); T.eq(3, P.PlayerData.money.cash); T.eq(0, pendingOf('CIDI'))
    end)
    T.it("another character's rows are never claimed", function()
        T.eq(1, queueOffline('CIDJ', { 3 }))
        T.eq(1, queueOffline('CIDK', { 4 }))
        local P = mkPlayer(19, 'CIDJ', 0)
        loadChar(P)
        T.eq(3, P.PlayerData.money.cash); T.eq(1, pendingOf('CIDK'))
        T.eq(0, count(pending, function(r) return r.citizenid == 'CIDK' and r.claimed_by ~= nil end))
    end)
end)

T.finish()

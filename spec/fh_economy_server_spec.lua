-- Stubbed-server spec (B7): loads fh_economy's real server/main.lua with an in-memory MySQL and an rsg-core
-- Player whose RemoveMoney mirrors rsg-core/server/player.lua (DontAllowMinus). Drives charge and getRep end to end.
-- Not a substitute for a live boot: exports are captured in-process, MySQL is a fake.
-- B7 fix: when `pauseOnInsert` is set, the fake insert yields the calling coroutine (as oxmysql's await does), so a
-- spec can interleave callers and drop / switch the player while a charge or pay is suspended mid-yield.
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local R = here .. '../server/resources/[fh]/'

local ledger, repRows, events, exported = {}, {}, {}, {}
local failInsert, failDelete, pauseOnInsert = false, false, false
local warnings = {}
local nextId = 1
local MySQL = {
    insert = { await = function(q, v)
        assert(q:find('INSERT INTO fh_ledger', 1, true), q)
        if failInsert then error('db down') end
        local id = nextId; nextId = id + 1
        ledger[id] = { id = id, citizenid = v[1], kind = v[2], amount = v[3], reason = v[4], region_id = v[5] }
        if pauseOnInsert and coroutine.isyieldable() then coroutine.yield('insert') end
        return id
    end },
    update = { await = function(q, v)
        assert(q:find('DELETE FROM fh_ledger WHERE id = ?', 1, true), q)
        if failDelete then error('db down') end
        ledger[v[1]] = nil
        return 1
    end },
    scalar = { await = function(q, v)
        assert(q:find('FROM fh_rep', 1, true), q)
        local row = repRows[v[1] .. '|' .. v[2]]
        return row
    end },
    transaction = { await = function() return true end },
}

local players = {}
local refuseRemove = false
local function mkPlayer(src, cid, cash)
    local P = { PlayerData = { source = src, citizenid = cid, money = { cash = cash } }, Functions = {} }
    P.Functions.RemoveMoney = function(mtype, amount)
        if refuseRemove then return false end
        local nb = P.PlayerData.money[mtype] - amount
        if nb < 0 then return false end -- RSGConfig.Money.DontAllowMinus includes cash
        P.PlayerData.money[mtype] = nb
        return true
    end
    P.Functions.AddMoney = function(mtype, amount) P.PlayerData.money[mtype] = P.PlayerData.money[mtype] + amount; return true end
    players[src] = P
    return P
end

local exportsT = setmetatable({}, {
    __index = function(_, res)
        assert(res == 'rsg-core', res)
        return { GetPlayer = function(_, src) return players[src] end }
    end,
    __call = function(_, name, fn) exported[name] = fn end,
})
local env = setmetatable({
    exports = exportsT, MySQL = MySQL, GetCurrentResourceName = function() return 'fh_economy' end,
    TriggerEvent = function(name, payload) events[#events + 1] = { name = name, payload = payload } end,
    AddEventHandler = function() end, -- credit's PlayerLoaded claim (specced in fh_economy_credit_spec.lua)
    RegisterCommand = function() end, json = { encode = function() return '' end },
    print = function(...) warnings[#warnings + 1] = table.concat({ ... }, ' ') end,
}, { __index = _G })
env._G = env
for _, p in ipairs({ R .. 'fh_core/shared/regions.lua', R .. 'fh_economy/config.lua',
    R .. 'fh_economy/shared/ledger_logic.lua', R .. 'fh_economy/server/main.lua' }) do
    local fh = assert(io.open(p, 'rb')); local src = fh:read('a'); fh:close()
    assert(load(src, '@' .. p, 't', env))()
end
local charge, getRep, pay = exported.charge, exported.getRep, exported.pay
local function rows() local n = 0 for _ in pairs(ledger) do n = n + 1 end return n end

T.describe('fh_economy.charge (stubbed server)', function()
    local P = mkPlayer(1, 'CID1', 50)
    T.it('ok: cash debited, one ledger row kind=charge with the args, charged event', function()
        local ok, err, id = charge(1, 20, 'hand_wages', 'heartlands')
        assert(ok == true and err == nil and type(id) == 'number', tostring(err))
        T.eq(30, P.PlayerData.money.cash)
        T.eq(1, rows())
        T.same({ id = id, citizenid = 'CID1', kind = 'charge', amount = 20, reason = 'hand_wages', region_id = 'heartlands' },
            ledger[id])
        local e = events[#events]
        T.eq('fh:economy:charged', e.name)
        T.same({ src = 1, citizenid = 'CID1', amount = 20, reason = 'hand_wages', region_id = 'heartlands', ledger_id = id },
            e.payload)
    end)
    T.it('short: fh_insufficient_funds, no row, no cash change, no event', function()
        local nEvents = #events
        local ok, err = charge(1, 31, 'hand_wages', 'heartlands')
        T.eq(false, ok); T.eq('fh_insufficient_funds', err)
        T.eq(30, P.PlayerData.money.cash); T.eq(1, rows()); T.eq(nEvents, #events)
    end)
    T.it('exact balance -> 0, never negative', function()
        assert(charge(1, 30, 'stall_rent', 'heartlands') == true)
        T.eq(0, P.PlayerData.money.cash); T.eq(2, rows())
        T.eq('fh_insufficient_funds', select(2, charge(1, 1, 'stall_rent', 'heartlands')))
        T.eq(0, P.PlayerData.money.cash); T.eq(2, rows())
    end)
    T.it('RemoveMoney refused -> removemoney_refused and the row is voided', function()
        local Q = mkPlayer(2, 'CID2', 100)
        refuseRemove = true
        local ok, err = charge(2, 10, 'x', 'heartlands'); refuseRemove = false
        T.eq(false, ok); T.eq('removemoney_refused', err)
        T.eq(100, Q.PlayerData.money.cash); T.eq(2, rows())
    end)
    T.it('ledger insert fails -> ledger_failed, no cash change', function()
        local Q = players[2]
        failInsert = true
        local ok, err = charge(2, 10, 'x', 'heartlands'); failInsert = false
        T.eq(false, ok); T.eq('ledger_failed', err); T.eq(100, Q.PlayerData.money.cash); T.eq(2, rows())
    end)
    T.it('refuses bad args before touching anything', function()
        T.eq('invalid_amount', select(2, charge(2, -5, 'x', 'heartlands')))
        T.eq('invalid_amount', select(2, charge(2, 0, 'x', 'heartlands')))
        T.eq('amount_too_large', select(2, charge(2, 1e9, 'x', 'heartlands')))
        T.eq('invalid_reason', select(2, charge(2, 5, '', 'heartlands')))
        T.eq('unknown_region', select(2, charge(2, 5, 'x', 'nowhere')))
        T.eq('no_player', select(2, charge(99, 5, 'x', 'heartlands')))
        T.eq('no_player', select(2, charge('2', 5, 'x', 'heartlands')))
        T.eq(100, players[2].PlayerData.money.cash); T.eq(2, rows())
    end)
end)

-- Start fn(...) in a coroutine; it must suspend inside the fake insert. Returns a finisher that resumes it to the end
-- and returns fn's results.
local function suspendAtInsert(fn, ...)
    pauseOnInsert = true
    local co = coroutine.create(fn)
    local okR, where = coroutine.resume(co, ...)
    pauseOnInsert = false
    assert(okR, where)
    assert(coroutine.status(co) == 'suspended' and where == 'insert', 'expected to be suspended in the insert')
    return function()
        local r = table.pack(coroutine.resume(co))
        assert(r[1], r[2])
        assert(coroutine.status(co) == 'dead', 'expected to finish after one resume')
        return table.unpack(r, 2, r.n)
    end
end

T.describe('fh_economy.charge across the insert yield (B7 fix)', function()
    T.it('two interleaved charges, only one affordable: second caller gets fh_charge_busy, exactly one succeeds and exactly one row survives', function()
        local P = mkPlayer(10, 'CID10', 50)
        local before = rows()
        local finishA = suspendAtInsert(charge, 10, 40, 'fence_buy', 'heartlands')
        -- A is in flight (row inserted, money not yet taken). B for the same character must not interleave.
        local okB, errB, idB = charge(10, 40, 'fence_buy', 'heartlands')
        T.eq(false, okB); T.eq('fh_charge_busy', errB); T.eq(nil, idB)
        T.eq(50, P.PlayerData.money.cash); T.eq(before + 1, rows())
        local okA, errA, idA = finishA()
        assert(okA == true and errA == nil and type(idA) == 'number', tostring(errA))
        T.eq(10, P.PlayerData.money.cash); T.eq(before + 1, rows()); T.eq('charge', ledger[idA].kind)
        -- the lock is released: the next charge runs and is refused on funds, not on busy
        T.eq('fh_insufficient_funds', select(2, charge(10, 40, 'fence_buy', 'heartlands')))
        T.eq(10, P.PlayerData.money.cash); T.eq(before + 1, rows())
    end)
    T.it('busy is per character: another character charges while the first is in flight', function()
        mkPlayer(11, 'CID11', 50); local Q = mkPlayer(12, 'CID12', 50)
        local finish = suspendAtInsert(charge, 11, 10, 'x', 'heartlands')
        assert(charge(12, 10, 'x', 'heartlands') == true); T.eq(40, Q.PlayerData.money.cash)
        assert(finish() == true); T.eq(40, players[11].PlayerData.money.cash)
    end)
    T.it('player dropped mid-yield -> no_player, row voided, the stale Player is not debited', function()
        local P = mkPlayer(13, 'CID13', 50)
        local before = rows()
        local finish = suspendAtInsert(charge, 13, 20, 'x', 'heartlands')
        players[13] = nil -- dropped during the insert await
        local ok, err = finish()
        T.eq(false, ok); T.eq('no_player', err)
        T.eq(50, P.PlayerData.money.cash); T.eq(before, rows())
        -- the lock was released: the character comes back and can be charged
        players[13] = P
        assert(charge(13, 20, 'x', 'heartlands') == true); T.eq(30, P.PlayerData.money.cash)
    end)
    T.it('character switched mid-yield -> player_changed, row voided, neither character debited', function()
        local P = mkPlayer(14, 'CID14', 50)
        local before = rows()
        local finish = suspendAtInsert(charge, 14, 20, 'x', 'heartlands')
        local Other = mkPlayer(14, 'CID14B', 80) -- same server id, another character loaded
        local ok, err = finish()
        T.eq(false, ok); T.eq('player_changed', err)
        T.eq(50, P.PlayerData.money.cash); T.eq(80, Other.PlayerData.money.cash); T.eq(before, rows())
    end)
    T.it('a failed void is warned with the row id and the row is left for an audit', function()
        local P = mkPlayer(15, 'CID15', 50)
        local before, nWarn = rows(), #warnings
        local finish = suspendAtInsert(charge, 15, 20, 'x', 'heartlands')
        players[15] = nil; failDelete = true
        local ok, err = finish(); failDelete = false
        T.eq(false, ok); T.eq('no_player', err); T.eq(50, P.PlayerData.money.cash)
        T.eq(before + 1, rows()); T.eq(nWarn + 1, #warnings)
        local w = warnings[#warnings]
        assert(w:find('WARNING', 1, true) and w:find('could not void ledger row ' .. (nextId - 1), 1, true), w)
    end)
end)

T.describe('fh_economy.pay across the insert yield (B7 fix)', function()
    T.it('ok: cash credited, one ledger row kind=pay, paid event', function()
        local P = mkPlayer(20, 'CID20', 0)
        local before = rows()
        local ok, err, id = pay(20, 15, 'sell_pelt', 'heartlands')
        assert(ok == true and err == nil and type(id) == 'number', tostring(err))
        T.eq(15, P.PlayerData.money.cash); T.eq(before + 1, rows()); T.eq('pay', ledger[id].kind)
        T.eq('fh:economy:paid', events[#events].name)
    end)
    T.it('player dropped mid-yield -> no_player, row voided, the stale Player is not credited', function()
        local P = mkPlayer(21, 'CID21', 0)
        local before = rows()
        local finish = suspendAtInsert(pay, 21, 15, 'sell_pelt', 'heartlands')
        players[21] = nil
        local ok, err = finish()
        T.eq(false, ok); T.eq('no_player', err); T.eq(0, P.PlayerData.money.cash); T.eq(before, rows())
    end)
    T.it('character switched mid-yield -> player_changed, row voided, neither character credited', function()
        local P = mkPlayer(22, 'CID22', 0)
        local before = rows()
        local finish = suspendAtInsert(pay, 22, 15, 'sell_pelt', 'heartlands')
        local Other = mkPlayer(22, 'CID22B', 5)
        local ok, err = finish()
        T.eq(false, ok); T.eq('player_changed', err)
        T.eq(0, P.PlayerData.money.cash); T.eq(5, Other.PlayerData.money.cash); T.eq(before, rows())
    end)
end)

T.describe('fh_economy.getRep (stubbed server)', function()
    mkPlayer(3, 'CID3', 0)
    T.it('no row -> 0', function()
        local v = getRep(3, 'heartlands')
        T.eq(0, v); T.eq('integer', math.type(v))
    end)
    T.it('row -> its value as an integer', function()
        repRows['CID3|heartlands'] = 40.0
        local v = getRep(3, 'heartlands')
        T.eq(40, v); T.eq('integer', math.type(v))
    end)
    T.it('citizenid string reads the same row (offline loaders)', function()
        T.eq(40, getRep('CID3', 'heartlands'))
    end)
    T.it('unknown region / no player / numeric string -> nil, err', function()
        local v, err = getRep(3, 'nowhere'); T.eq(nil, v); T.eq('unknown_region', err)
        v, err = getRep(99, 'heartlands'); T.eq(nil, v); T.eq('no_player', err)
        v, err = getRep('3', 'heartlands'); T.eq(nil, v); T.eq('no_player', err)
    end)
    T.it('padded / blank / junk citizenid strings and non-number, non-string who -> no_player (not a silent 0)', function()
        for _, bad in ipairs({ ' CID3', 'CID3 ', '', ' ', "CID3' OR 1=1", string.rep('A', 51) }) do
            local v, err = getRep(bad, 'heartlands'); T.eq(nil, v, bad); T.eq('no_player', err, bad)
        end
        for _, bad in ipairs({ true, {}, 3.5 }) do
            local v, err = getRep(bad, 'heartlands'); T.eq(nil, v); T.eq('no_player', err)
        end
        T.eq('no_player', select(2, getRep(nil, 'heartlands')))
    end)
end)

T.finish()

-- Stubbed-server spec (B7): loads fh_economy's real server/main.lua with an in-memory MySQL and an rsg-core
-- Player whose RemoveMoney mirrors rsg-core/server/player.lua (DontAllowMinus). Drives charge and getRep end to end.
-- Not a substitute for a live boot: exports are captured in-process, MySQL is a fake.
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local R = here .. '../server/resources/[fh]/'

local ledger, repRows, events, exported = {}, {}, {}, {}
local failInsert, failDelete = false, false
local nextId = 1
local MySQL = {
    insert = { await = function(q, v)
        assert(q:find('INSERT INTO fh_ledger', 1, true), q)
        if failInsert then error('db down') end
        local id = nextId; nextId = id + 1
        ledger[id] = { id = id, citizenid = v[1], kind = v[2], amount = v[3], reason = v[4], region_id = v[5] }
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
    RegisterCommand = function() end, json = { encode = function() return '' end },
}, { __index = _G })
env._G = env
for _, p in ipairs({ R .. 'fh_core/shared/regions.lua', R .. 'fh_economy/config.lua',
    R .. 'fh_economy/shared/ledger_logic.lua', R .. 'fh_economy/server/main.lua' }) do
    local fh = assert(io.open(p, 'rb')); local src = fh:read('a'); fh:close()
    assert(load(src, '@' .. p, 't', env))()
end
local charge, getRep = exported.charge, exported.getRep
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
end)

T.finish()

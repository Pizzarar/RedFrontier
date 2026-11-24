-- Stubbed-server spec (idea-804): fh_economy.repByCitizenid on the real server/main.lua with an in-memory fh_rep /
-- fh_ledger / players model (the upsert's clamp is modelled from the transaction values). Not a live boot.
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local R = here .. '../server/resources/[fh]/'

local ledger, repRows, events, exported, nextId = {}, {}, {}, {}, 1
local known = { CIDON = true, CIDOFF = true }
local fail = {}
local function has(q, s) return q:find(s, 1, true) ~= nil end
local MySQL = {
    scalar = { await = function(q, v)
        if has(q, 'FROM players WHERE citizenid = ?') then return known[v[1]] and 1 or nil end
        assert(has(q, 'FROM fh_rep'), q)
        return repRows[v[1] .. '|' .. v[2]]
    end },
    transaction = { await = function(qs)
        if fail.tx then error('db down') end
        local u = qs[1].values -- cid, region, max, min, delta, max, min, delta
        local key = u[1] .. '|' .. u[2]
        local cur = repRows[key]
        if cur == nil then repRows[key] = math.min(u[3], math.max(u[4], u[5]))
        else repRows[key] = math.min(u[6], math.max(u[7], cur + u[8])) end
        local v = qs[2].values
        ledger[nextId] = { id = nextId, citizenid = v[1], kind = v[2], amount = v[3], reason = v[4], region_id = v[5] }
        nextId = nextId + 1
        return true
    end },
}
local players = { [7] = { PlayerData = { source = 7, citizenid = 'CIDON', money = { cash = 0 } } } }
local exportsT = setmetatable({}, {
    __index = function() return {
        GetPlayer = function(_, src) return players[src] end,
        GetPlayerByCitizenId = function(_, cid)
            for _, P in pairs(players) do if P.PlayerData.citizenid == cid then return P end end
        end,
    } end,
    __call = function(_, name, fn) exported[name] = fn end,
})
local env = setmetatable({
    exports = exportsT, MySQL = MySQL, GetCurrentResourceName = function() return 'fh_economy' end,
    TriggerEvent = function(name, payload) events[#events + 1] = { name = name, payload = payload } end,
    AddEventHandler = function() end, RegisterCommand = function() end, json = { encode = function() return '' end },
    print = function() end,
}, { __index = _G })
env._G = env
for _, p in ipairs({ R .. 'fh_core/shared/regions.lua', R .. 'fh_economy/config.lua',
    R .. 'fh_economy/shared/ledger_logic.lua', R .. 'fh_economy/server/main.lua' }) do
    local fh = assert(io.open(p, 'rb')); local src = fh:read('a'); fh:close()
    assert(load(src, '@' .. p, 't', env))()
end
local repBy, rep = exported.repByCitizenid, exported.rep
local function nLedger() local n = 0 for _ in pairs(ledger) do n = n + 1 end return n end

T.describe('fh_economy.repByCitizenid (stubbed server)', function()
    T.it('offline: writes the row + a kind=rep ledger row, event src = nil', function()
        local ok, err = repBy('CIDOFF', 'heartlands', 15, 'lot_abandon')
        assert(ok == true and err == nil, tostring(err))
        T.eq(15, repRows['CIDOFF|heartlands']); T.eq(1, nLedger())
        T.same({ id = 1, citizenid = 'CIDOFF', kind = 'rep', amount = 15, reason = 'lot_abandon', region_id = 'heartlands' }, ledger[1])
        local e = events[#events]
        T.eq('fh:economy:rep_changed', e.name)
        T.same({ src = nil, citizenid = 'CIDOFF', region_id = 'heartlands', delta = 15, value = 15, reason = 'lot_abandon' }, e.payload)
    end)
    T.it('accumulates and clamps at repMax / repMin', function()
        assert(repBy('CIDOFF', 'heartlands', -5, 'x'))
        T.eq(10, repRows['CIDOFF|heartlands'])
        for _ = 1, 12 do assert(repBy('CIDOFF', 'heartlands', 1000, 'x')) end
        T.eq(10000, repRows['CIDOFF|heartlands'])
        T.eq(10000, events[#events].payload.value)
        for _ = 1, 22 do assert(repBy('CIDOFF', 'heartlands', -1000, 'x')) end
        T.eq(-10000, repRows['CIDOFF|heartlands'])
    end)
    T.it('online citizenid: event carries the server id', function()
        assert(repBy('CIDON', 'heartlands', 3, 'x'))
        local e = events[#events]
        T.eq(7, e.payload.src); T.eq('CIDON', e.payload.citizenid); T.eq(3, repRows['CIDON|heartlands'])
    end)
    T.it('invalid / unknown citizenid refused, nothing written', function()
        local n, ne = nLedger(), #events
        for _, bad in ipairs({ ' CIDOFF', '', '123', "A' OR 1=1", 5, true }) do
            local ok, err = repBy(bad, 'heartlands', 1, 'x'); T.eq(false, ok); T.eq('invalid_citizenid', err)
        end
        local ok, err = repBy('CIDGHOST', 'heartlands', 1, 'x'); T.eq(false, ok); T.eq('unknown_citizenid', err)
        T.eq(n, nLedger()); T.eq(ne, #events)
    end)
    T.it('bad delta / reason / region refused like rep', function()
        for _, c in ipairs({ { 0, 'x', 'heartlands' }, { 'a', 'x', 'heartlands' }, { 1e9, 'x', 'heartlands' },
            { 1, '', 'heartlands' }, { 1, 'x', 'nowhere' } }) do
            local a1, e1 = repBy('CIDOFF', c[3], c[1], c[2])
            local a2, e2 = rep(7, c[3], c[1], c[2])
            T.eq(false, a1); T.eq(e2, e1); T.eq(a2, a1)
        end
    end)
    T.it('offline at call, online by the time the write lands: event carries the fresh src', function()
        known.CIDLATE = true
        local orig = MySQL.transaction.await
        MySQL.transaction.await = function(qs)
            local r = orig(qs)
            players[9] = { PlayerData = { source = 9, citizenid = 'CIDLATE', money = { cash = 0 } } } -- logs in mid-await
            return r
        end
        assert(repBy('CIDLATE', 'heartlands', 4, 'x'))
        MySQL.transaction.await = orig; players[9] = nil
        T.eq(9, events[#events].payload.src)
    end)
    T.it('transaction failure -> ledger_failed, no event', function()
        local ne = #events
        fail.tx = true
        local ok, err = repBy('CIDOFF', 'heartlands', 1, 'x'); fail.tx = false
        T.eq(false, ok); T.eq('ledger_failed', err); T.eq(ne, #events)
    end)
    T.it('rep(src) still works and carries src', function()
        assert(rep(7, 'heartlands', 2, 'x'))
        T.eq(7, events[#events].payload.src)
    end)
end)

T.finish()

-- Run from repo root: `lua spec/cargo_buy_spec.lua` (or via tools/run-specs.py).
-- roads-04 R16: owned wagons + buy (Tier A: money + persistence).
--  Part 1: pure rules (wagonPrice / ownedSet / ownedList / validCitizenid) and config sanity.
--  Part 2: FhCargoBuy.buy (server/wagon_buy.lua) with fakes; charge / insert / refund can yield (coroutines), so the
--          busy lock and the concurrent double buy are exercised for real.
--  Part 3: the real server/main.lua booted under stubbed natives/exports/MySQL: buyWagon / ownsWagon / ownedTiers wiring
--          (SQL, charge + credit args, captured citizenid) and the cargo persistence evidence (same stash id on
--          every respawn, never cleared or deleted by fh_cargo).
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local case = T.it
local CARGO = here .. '../server/resources/[fh]/fh_cargo/'
local R = dofile(CARGO .. 'shared/cargo_rules.lua')
local B = dofile(CARGO .. 'server/wagon_buy.lua')

local function loadConfig()
    local env = setmetatable({}, { __index = _G })
    assert(loadfile(CARGO .. 'config.lua', 't', env))()
    return env.FhCargoConfig
end
local CFG = loadConfig()

-- ---------------------------------------------------------------- part 1: pure rules + config

case('pure: wagonPrice reads whole positive prices of known tiers only', function()
    local p = { t1 = 100, t2 = 400.0, t3 = 0, bogus = 5 }
    T.eq(100, R.wagonPrice(p, 't1'))
    T.eq(400, R.wagonPrice(p, 't2'))
    T.eq(nil, R.wagonPrice(p, 't3'), 'zero price refused')
    T.eq(nil, R.wagonPrice(p, 'bogus'))
    T.eq(nil, R.wagonPrice({ t1 = 1.5 }, 't1'), 'fractional')
    T.eq(nil, R.wagonPrice({ t1 = -5 }, 't1'))
    T.eq(nil, R.wagonPrice({ t1 = 0 / 0 }, 't1'), 'NaN')
    T.eq(nil, R.wagonPrice({ t1 = math.huge }, 't1'))
    T.eq(nil, R.wagonPrice({ t1 = '100' }, 't1'), 'string')
    T.eq(nil, R.wagonPrice(nil, 't1'))
end)

case('pure: ownedSet / ownedList keep known tiers in tier order', function()
    local set = R.ownedSet({ { tier = 't3' }, { tier = 'nope' }, { tier = 't1' }, 'junk', { tier = 5 } })
    T.same({ t1 = true, t3 = true }, set)
    T.same({ 't1', 't3' }, R.ownedList(set))
    T.same({}, R.ownedList(R.ownedSet(nil)))
end)

case('pure: validCitizenid matches the fh_economy citizenid shape', function()
    assert(R.validCitizenid('ABC123'))
    assert(R.validCitizenid('a_b-c'))
    assert(not R.validCitizenid('12345'), 'all digits = a mistyped server id')
    assert(not R.validCitizenid(''))
    assert(not R.validCitizenid(' ABC'))
    assert(not R.validCitizenid(('x'):rep(51)))
    assert(not R.validCitizenid(7))
end)

case('config: prices exist for every tier, t1 < t2 < t3, under fh_economy maxCharge', function()
    local env = setmetatable({}, { __index = _G })
    assert(loadfile(here .. '../server/resources/[fh]/fh_economy/config.lua', 't', env))()
    local maxCharge = env.FhEconomyConfig.maxCharge
    local prev = 0
    for _, k in ipairs(R.ORDER) do
        local p = R.wagonPrice(CFG.Prices, k)
        assert(p, 'price for ' .. k)
        assert(p > prev, k .. ' price must be above the tier below')
        assert(p <= maxCharge, k .. ' price over fh_economy maxCharge')
        prev = p
    end
    assert(CFG.BuyChargeRetries == 1, 'brief: fh_charge_busy is retried exactly once')
end)

-- ---------------------------------------------------------------- part 2: FhCargoBuy.buy with fakes

local CFGT = { Prices = { t1 = 150, t2 = 600, t3 = 1800 }, BuyChargeRetries = 1, BuyRetryMs = 250 }

---Fake world. o: unlock = { ok, reason } | 'throw'; owned = { [cid..':'..tier] = true }; chargeScript = list of
---results ({ok, err} or 'throw') used in order, default {true}; insert = 1|0|nil|'throw'|fn; refund = {ok, err, mode}|'throw';
---yieldIn = { charge = true, insert = true, ... } -> that dep yields (coroutine) before returning.
local function world(o)
    o = o or {}
    local W = { cid = { [7] = 'CID1', [8] = 'CID2' }, charges = {}, inserts = {}, refunds = {}, unlocks = {},
        waits = {}, logs = {}, events = {}, owned = o.owned or {}, chargeN = 0 }
    local function y(name) if o.yieldIn and o.yieldIn[name] and coroutine.isyieldable() then coroutine.yield(name) end end
    W.deps = {
        citizenid = function(src) return W.cid[src] end,
        owned = function(cid, tier)
            y('owned')
            if o.ownedFails then return nil end
            return W.owned[cid .. ':' .. tier] == true
        end,
        canUnlock = function(src, id)
            W.unlocks[#W.unlocks + 1] = { src = src, id = id }
            y('canUnlock')
            if o.onUnlock then o.onUnlock(W) end
            if o.unlock == 'throw' then error('No such export canUnlock in resource fh_progression') end
            local u = o.unlock or { true }
            return u[1], u[2]
        end,
        charge = function(src, amount, reason, region)
            W.chargeN = W.chargeN + 1
            local r = (o.chargeScript or {})[W.chargeN] or { true }
            W.charges[#W.charges + 1] = { src = src, amount = amount, reason = reason, region = region, result = r }
            y('charge')
            if r == 'throw' then error('fh_economy exploded') end
            return r[1], r[2]
        end,
        insert = function(cid, tier)
            W.inserts[#W.inserts + 1] = { cid = cid, tier = tier }
            y('insert')
            local v = o.insert
            if type(v) == 'function' then return v(W, cid, tier) end
            if v == 'throw' then error('db down') end
            if v == nil and o.insertNil then return nil end
            if v == nil then
                if W.owned[cid .. ':' .. tier] then return 0 end
                W.owned[cid .. ':' .. tier] = true
                return 1
            end
            return v
        end,
        refund = function(cid, amount, reason, region)
            W.refunds[#W.refunds + 1] = { cid = cid, amount = amount, reason = reason, region = region }
            y('refund')
            if o.refund == 'throw' then error('credit threw') end
            local r = o.refund or { true, nil, 'paid' }
            return r[1], r[2], r[3]
        end,
        wait = function(ms) W.waits[#W.waits + 1] = ms end,
        log = function(msg) W.logs[#W.logs + 1] = msg end,
        emit = function(name, payload) W.events[#W.events + 1] = { name = name, payload = payload } end,
    }
    W.locks = {}
    function W.buy(src, tier, region) return B.buy(CFGT, R, W.deps, W.locks, src, tier, region or 'heartlands') end
    function W.logged(pat)
        for _, l in ipairs(W.logs) do if l:find(pat) then return l end end
    end
    function W.event(name)
        for _, e in ipairs(W.events) do if e.name == name then return e end end
    end
    return W
end

local function lockFree(W) T.eq(nil, next(W.locks), 'busy lock released') end

case('buy ok: t1 charged once at its price, row written for the captured citizenid, event emitted', function()
    local W = world()
    local ok, res = W.buy(7, 't1', 'heartlands')
    T.eq(true, ok)
    T.same({ tier = 't1', price = 150, citizenid = 'CID1' }, res)
    T.eq(1, #W.charges)
    T.same({ src = 7, amount = 150, reason = 'wagon_buy', region = 'heartlands' },
        { src = W.charges[1].src, amount = W.charges[1].amount, reason = W.charges[1].reason, region = W.charges[1].region })
    T.same({ { cid = 'CID1', tier = 't1' } }, W.inserts)
    T.eq(0, #W.unlocks, 't1 has no rep gate')
    T.eq(0, #W.refunds)
    local e = W.event('fh:cargo:wagon_bought')
    assert(e and e.payload.citizenid == 'CID1' and e.payload.price == 150 and e.payload.tier == 't1')
    lockFree(W)
end)

case('buy ok: aliases resolve (wagon -> t2), gate asked for wagon_t2', function()
    local W = world()
    local ok, res = W.buy(7, 'wagon')
    T.eq(true, ok)
    T.eq('t2', res.tier)
    T.eq(600, W.charges[1].amount)
    T.same({ { src = 7, id = 'wagon_t2' } }, W.unlocks)
end)

case('unknown tier refused before anything else (no DB, no gate, no charge)', function()
    local W = world()
    local ok, err = W.buy(7, 't9')
    T.eq(false, ok); T.eq('fh_bad_tier', err)
    T.eq(0, #W.charges); T.eq(0, #W.unlocks); T.eq(0, #W.inserts)
    lockFree(W)
end)

case('bad src / no character / bad region refused, nothing charged', function()
    local W = world()
    T.eq('fh_no_player', select(2, W.buy(0, 't1')))
    T.eq('fh_no_player', select(2, W.buy('7', 't1')))
    T.eq('fh_no_player', select(2, W.buy(0 / 0, 't1')), 'NaN src')
    T.eq('fh_no_player', select(2, W.buy(-math.huge, 't1')))
    T.eq('fh_no_character', select(2, W.buy(99, 't1')))
    T.eq('fh_unknown_region', select(2, W.buy(7, 't1', '')))
    T.eq(0, #W.charges)
    lockFree(W)
end)

case('already owned: refused before the rep gate and the charge', function()
    local W = world({ owned = { ['CID1:t2'] = true } })
    local ok, err = W.buy(7, 't2')
    T.eq(false, ok); T.eq('fh_already_owned', err)
    T.eq(0, #W.unlocks, 'owned check comes before canUnlock')
    T.eq(0, #W.charges)
    lockFree(W)
end)

case('ownership read failed: fail closed fh_db_error, nothing charged', function()
    local W = world({ ownedFails = true })
    T.eq('fh_db_error', select(2, W.buy(7, 't1')))
    T.eq(0, #W.charges)
end)

case('t2 at rep tier 1: refused with the returned reason (tier_too_low), not charged', function()
    local W = world({ unlock = { false, 'tier_too_low' } })
    local ok, err = W.buy(7, 't2')
    T.eq(false, ok); T.eq('tier_too_low', err)
    T.eq(0, #W.charges); T.eq(0, #W.inserts)
    lockFree(W)
end)

case('progression down (canUnlock throws / returns nil): fh_locked, not charged', function()
    local W = world({ unlock = 'throw' })
    T.eq('fh_locked', select(2, W.buy(7, 't3')))
    T.same({ { src = 7, id = 'wagon_t3' } }, W.unlocks)
    T.eq(0, #W.charges)
    local W2 = world({ unlock = { nil } })
    T.eq('fh_locked', select(2, W2.buy(7, 't2')))
    T.eq(0, #W2.charges)
    lockFree(W); lockFree(W2)
end)

case('character switched while canUnlock yielded: refused, the new character is never charged', function()
    local W = world({ onUnlock = function(W) W.cid[7] = 'OTHER' end })
    T.eq('player_changed', select(2, W.buy(7, 't2')))
    T.eq(0, #W.charges)
    local W2 = world({ onUnlock = function(W) W.cid[7] = nil end })
    T.eq('fh_no_character', select(2, W2.buy(7, 't2')))
    T.eq(0, #W2.charges)
end)

case('charge busy: retried once after BuyRetryMs, then ok', function()
    local W = world({ chargeScript = { { false, 'fh_charge_busy' }, { true } } })
    local ok = W.buy(7, 't1')
    T.eq(true, ok)
    T.eq(2, #W.charges)
    T.same({ 250 }, W.waits)
    T.eq(1, #W.inserts)
    T.eq(0, #W.refunds)
end)

case('charge busy twice: refused fh_charge_busy after one retry, no row, no refund', function()
    local W = world({ chargeScript = { { false, 'fh_charge_busy' }, { false, 'fh_charge_busy' }, { true } } })
    local ok, err = W.buy(7, 't1')
    T.eq(false, ok); T.eq('fh_charge_busy', err)
    T.eq(2, #W.charges, 'exactly one retry')
    T.eq(0, #W.inserts); T.eq(0, #W.refunds)
    lockFree(W)
end)

case('charge busy then character gone before the retry: refused, no second charge', function()
    local W = world({ chargeScript = { { false, 'fh_charge_busy' } } })
    W.deps.wait = function() W.cid[7] = nil end
    T.eq('fh_no_character', select(2, W.buy(7, 't1')))
    T.eq(1, #W.charges)
end)

case('charge refused (insufficient funds / other codes): no row, no refund, code passed through', function()
    for _, code in ipairs({ 'fh_insufficient_funds', 'removemoney_refused', 'player_changed', 'fh_economy_unavailable' }) do
        local W = world({ chargeScript = { { false, code } } })
        local ok, err = W.buy(7, 't1')
        T.eq(false, ok); T.eq(code, err)
        T.eq(1, #W.charges, code .. ': not retried')
        T.eq(0, #W.inserts, code .. ': no row'); T.eq(0, #W.refunds)
        lockFree(W)
    end
    local W = world({ chargeScript = { { false } } })
    T.eq('charge_refused', select(2, W.buy(7, 't1')))
    T.eq(0, #W.inserts)
end)

case('insert fails (nil) after charge: credit refund to the captured citizenid, same price + region', function()
    local W = world({ insertNil = true, yieldIn = { insert = true } })
    -- character switches while the insert yields: the refund must still go to CID1 (who paid)
    local co = coroutine.create(function() return W.buy(7, 't2', 'scarlett_meadows') end)
    local _, y1 = coroutine.resume(co)
    T.eq('insert', y1)
    W.cid[7] = 'SWITCHED'
    local _, ok, err = coroutine.resume(co)
    T.eq(false, ok); T.eq('fh_buy_refunded', err)
    T.same({ { cid = 'CID1', amount = 600, reason = 'wagon_buy_refund', region = 'scarlett_meadows' } }, W.refunds)
    assert(W.logged('insert failed after charge'), 'insert failure logged')
    lockFree(W)
end)

case('insert throws after charge: refunded too', function()
    local W = world({ insert = 'throw' })
    T.eq('fh_buy_refunded', select(2, W.buy(7, 't1')))
    T.eq(1, #W.refunds); T.eq('CID1', W.refunds[1].cid); T.eq(150, W.refunds[1].amount)
end)

case('credit refund fails: never silent (ALERT log + owed event), fh_refund_failed', function()
    for _, mode in ipairs({ { false, 'ledger_failed' }, 'throw' }) do
        local W = world({ insertNil = true, refund = mode })
        local ok, err = W.buy(7, 't1')
        T.eq(false, ok); T.eq('fh_refund_failed', err)
        local l = W.logged('ALERT wagon_buy REFUND FAILED')
        assert(l and l:find('CID1') and l:find('OWED %$150'), 'loud ALERT with cid + amount: ' .. tostring(l))
        local e = W.event('fh:cargo:wagon_buy_owed')
        assert(e and e.payload.citizenid == 'CID1' and e.payload.owed == 150, 'owed event')
        assert(not W.event('fh:cargo:wagon_bought'))
        lockFree(W)
    end
end)

case('refund queued (pending, player offline) counts as refunded', function()
    local W = world({ insertNil = true, refund = { true, nil, 'pending' } })
    T.eq('fh_buy_refunded', select(2, W.buy(7, 't1')))
    assert(W.logged('mode=pending'))
end)

case('concurrent double buy (same player): second refused busy while the first charge is in flight, one charge', function()
    local W = world({ yieldIn = { charge = true } })
    local co = coroutine.create(function() return W.buy(7, 't1') end)
    local _, y1 = coroutine.resume(co)
    T.eq('charge', y1)
    local ok2, err2 = W.buy(7, 't1')
    T.eq(false, ok2); T.eq('fh_buy_busy', err2)
    local _, ok1 = coroutine.resume(co)
    T.eq(true, ok1)
    T.eq(1, #W.charges); T.eq(1, #W.inserts); T.eq(0, #W.refunds)
    lockFree(W)
    T.eq('fh_already_owned', select(2, W.buy(7, 't1')), 'a later buy sees the row')
    T.eq(1, #W.charges)
end)

case('concurrent double buy past the lock (restart lost it): both charged, unique key keeps one, the other is refunded', function()
    local W = world({ yieldIn = { charge = true } })
    local locksA, locksB = {}, {} -- two lock tables = the in-memory lock did not see the other buy
    local a = coroutine.create(function() return B.buy(CFGT, R, W.deps, locksA, 7, 't1', 'heartlands') end)
    local b = coroutine.create(function() return B.buy(CFGT, R, W.deps, locksB, 7, 't1', 'heartlands') end)
    coroutine.resume(a); coroutine.resume(b) -- both passed the owned check, both are in charge
    local _, okA = coroutine.resume(a)
    local _, okB, errB, detailB = coroutine.resume(b)
    T.eq(true, okA)
    T.eq(false, okB); T.eq('fh_already_owned', errB); T.eq('refunded', detailB)
    T.eq(2, #W.charges)
    T.eq(1, #W.refunds, 'exactly one charge given back')
    T.same({ cid = 'CID1', amount = 150, reason = 'wagon_buy_refund', region = 'heartlands' }, W.refunds[1])
end)

case('charge throws (outcome unknown): fail closed fh_charge_error, no row, no refund, ALERT with cid/tier/price/region/err', function()
    local W = world({ chargeScript = { 'throw' } })
    local ok, err = W.buy(7, 't2', 'scarlett_meadows')
    T.eq(false, ok); T.eq('fh_charge_error', err)
    T.eq(1, #W.charges, 'not retried')
    T.eq(0, #W.inserts, 'no wagon granted'); T.eq(0, #W.refunds, 'no refund (could pay twice)')
    local l = W.logged('ALERT wagon_buy charge threw')
    assert(l and l:find('cid=CID1') and l:find('tier=t2') and l:find('amount=600') and l:find('region=scarlett_meadows')
        and l:find('fh_economy exploded') and l:find('fh_ledger'), 'ALERT carries what ops need: ' .. tostring(l))
    assert(not W.event('fh:cargo:wagon_bought'))
    lockFree(W)
    T.eq(nil, W.owned['CID1:t2'], 'not owned afterwards')
end)

case('insert returns a value whose tostring throws: still refunded exactly once, lock released', function()
    local W = world()
    W.deps.insert = function() return setmetatable({}, { __tostring = function() error('boom') end }) end
    local ok, err = W.buy(7, 't1')
    T.eq(false, ok); T.eq('fh_buy_refunded', err)
    T.eq(1, #W.charges)
    T.eq(1, #W.refunds, 'refunded exactly once')
    T.eq('CID1', W.refunds[1].cid)
    assert(W.logged('insert failed after charge.*<unprintable>'))
    lockFree(W)
end)

case('refund error with a throwing tostring: refund-failed path still logs ALERT + owed event, lock released', function()
    local bad = setmetatable({}, { __tostring = function() error('boom') end })
    local W = world({ insertNil = true, refund = { false, bad } })
    T.eq('fh_refund_failed', select(2, W.buy(7, 't1')))
    assert(W.logged('ALERT wagon_buy REFUND FAILED.*<unprintable>'))
    assert(W.event('fh:cargo:wagon_buy_owed'))
    lockFree(W)
end)

case('a throw inside the flow (character lookup) is caught: fh_buy_error, nothing charged, lock released', function()
    local W = world()
    local n = 0
    W.deps.citizenid = function(src)
        n = n + 1
        if n > 1 then error(setmetatable({}, { __tostring = function() error('boom') end })) end
        return 'CID1'
    end
    local ok, err = W.buy(7, 't1')
    T.eq(false, ok); T.eq('fh_buy_error', err)
    T.eq(0, #W.charges); T.eq(0, #W.refunds)
    assert(W.logged('ERROR wagon_buy cid=CID1.*<unprintable>'))
    lockFree(W)
end)

case('a throwing logger never breaks the flow', function()
    local W = world({ insertNil = true })
    W.deps.log = function() error('log sink down') end
    T.eq('fh_buy_refunded', select(2, W.buy(7, 't1')))
    T.eq(1, #W.refunds)
end)

-- ---------------------------------------------------------------- part 3: real server/main.lua under stubs

local function boot(o)
    o = o or {}
    local E = { exported = {}, sql = {}, charges = {}, credits = {}, registers = {}, despawns = {}, cleared = {},
        events = {}, char = { [7] = 'CID1' }, rows = o.rows or {}, prints = {} }
    local reqN = 0
    local exportsT = setmetatable({
        ['rsg-core'] = { GetCoreObject = function() return { Functions = {
            GetPlayer = function(src) local c = E.char[src] return c and { PlayerData = { citizenid = c } } or nil end,
        }, Shared = { Items = {} } } end },
        fh_core = {
            requestSpawn = function(_, spec, opts)
                reqN = reqN + 1
                local n = reqN
                E.ready = function() opts.onReady(100 + n) end -- fh_core calls onReady later, after the request returns
                return reqN
            end,
            despawn = function(_, id) E.despawns[#E.despawns + 1] = id end,
            registerContainer = function(_, ref, opts) E.registers[#E.registers + 1] = { ref = ref, opts = opts } return true end,
            clearContainer = function(_, ref) E.cleared[#E.cleared + 1] = ref return true end,
            deleteContainer = function(_, ref) E.cleared[#E.cleared + 1] = ref return true end,
        },
        fh_progression = { canUnlock = function() return o.unlock ~= false, o.unlock == false and 'tier_too_low' or nil end },
        fh_economy = {
            charge = function(_, src, amount, why, region)
                E.charges[#E.charges + 1] = { src = src, amount = amount, why = why, region = region }
                return true
            end,
            credit = function(_, cid, amount, why, region)
                E.credits[#E.credits + 1] = { cid = cid, amount = amount, why = why, region = region }
                return true, nil, 'paid'
            end,
        },
    }, { __call = function(_, name, fn) E.exported[name] = fn end })
    local MySQL = {
        query = { await = function(sql, params)
            E.sql[#E.sql + 1] = { sql = sql, params = params }
            if o.dbDown then error('db down') end
            local out = {}
            for _, r in ipairs(E.rows) do
                if r.citizenid == params[1] and (params[2] == nil or r.tier == params[2]) then
                    out[#out + 1] = params[2] and { ['1'] = 1 } or { tier = r.tier }
                end
            end
            return out
        end },
        update = { await = function(sql, params)
            E.sql[#E.sql + 1] = { sql = sql, params = params }
            if o.insertFails then error('Duplicate entry? no: connection lost') end
            for _, r in ipairs(E.rows) do if r.citizenid == params[1] and r.tier == params[2] then return 0 end end
            E.rows[#E.rows + 1] = { citizenid = params[1], tier = params[2] }
            return 1
        end },
    }
    local env = setmetatable({
        exports = exportsT, MySQL = MySQL,
        lib = { addCommand = function() end },
        GetCurrentResourceName = function() return 'fh_cargo' end,
        GetResourceState = function() return 'started' end,
        RegisterNetEvent = function() end, AddEventHandler = function() end,
        CreateThread = function() end, Wait = function() end,
        TriggerEvent = function(name, payload) E.events[#E.events + 1] = { name = name, payload = payload } end,
        TriggerClientEvent = function() end,
        GetPlayers = function() return {} end,
        GetConvar = function() return 'true' end,
        GetGameTimer = function() return 0 end,
        NetworkGetEntityFromNetworkId = function(n) return n end,
        DoesEntityExist = function() return true end,
        GetEntityCoords = function() return { x = 1, y = 2, z = 3 } end,
        print = function(s) E.prints[#E.prints + 1] = tostring(s) end,
    }, { __index = _G })
    env._G = env
    for _, p in ipairs({ CARGO .. 'shared/cargo_rules.lua', CARGO .. 'config.lua', CARGO .. 'server/wagon_buy.lua',
        CARGO .. 'server/main.lua' }) do
        local fh = assert(io.open(p, 'rb')); local src = fh:read('a'); fh:close()
        assert(load(src, '@' .. p, 't', env))()
    end
    return E
end

case('server: buyWagon charges via fh_economy and writes fh_wagons with INSERT IGNORE', function()
    local E = boot()
    local ok, err = E.exported.buyWagon(7, 't1', 'heartlands')
    T.eq(true, ok, tostring(err)); T.eq(nil, err)
    T.same({ { src = 7, amount = CFG.Prices.t1, why = 'wagon_buy', region = 'heartlands' } }, E.charges)
    local ins = E.sql[#E.sql]
    assert(ins.sql:find('^INSERT IGNORE INTO fh_wagons %(citizenid, tier%)'), ins.sql)
    T.same({ 'CID1', 't1' }, ins.params)
    T.same({ { citizenid = 'CID1', tier = 't1' } }, E.rows)
    T.eq(0, #E.credits)
    local ok2, err2 = E.exported.buyWagon(7, 't1', 'heartlands')
    T.eq(false, ok2); T.eq('fh_already_owned', err2)
    T.eq(1, #E.charges, 'not charged again')
end)

case('server: buyWagon insert failure refunds via fh_economy:credit by citizenid (loud log)', function()
    local E = boot({ insertFails = true })
    local ok, err = E.exported.buyWagon(7, 't1', 'heartlands')
    T.eq(false, ok); T.eq('fh_buy_refunded', err)
    T.same({ { cid = 'CID1', amount = CFG.Prices.t1, why = 'wagon_buy_refund', region = 'heartlands' } }, E.credits)
    local loud = false
    for _, p in ipairs(E.prints) do if p:find('insert failed after charge') then loud = true end end
    assert(loud, 'insert failure printed')
end)

case('server: t2 refused at rep tier 1 through the real canUnlock wiring', function()
    local E = boot({ unlock = false })
    local ok, err = E.exported.buyWagon(7, 't2', 'heartlands')
    T.eq(false, ok); T.eq('tier_too_low', err)
    T.eq(0, #E.charges)
end)

case('server: ownsWagon / ownedTiers by src or citizenid, fail closed on DB error', function()
    local E = boot({ rows = { { citizenid = 'CID1', tier = 't3' }, { citizenid = 'CID1', tier = 't1' } } })
    T.eq(true, E.exported.ownsWagon(7, 't1'))
    T.eq(true, E.exported.ownsWagon('CID1', 'freight'))
    T.eq(false, E.exported.ownsWagon('CID1', 't2'))
    T.same({ 't1', 't3' }, E.exported.ownedTiers(7))
    T.same({}, E.exported.ownedTiers('NOBODY'))
    T.eq('fh_bad_tier', select(2, E.exported.ownsWagon(7, 'x')))
    T.eq('fh_no_character', select(2, E.exported.ownsWagon(99, 't1')))
    T.eq('fh_bad_citizenid', select(2, E.exported.ownedTiers('123')))
    local D = boot({ dbDown = true })
    local v, e = D.exported.ownsWagon(7, 't1')
    T.eq(nil, v); T.eq('fh_db_error', e)
    T.eq('fh_db_error', select(2, D.exported.ownedTiers(7)))
    T.eq('fh_db_error', select(2, D.exported.buyWagon(7, 't1', 'heartlands')))
end)

case('persistence: every respawn of a tier re-registers the SAME stash id; fh_cargo never clears or deletes it', function()
    local E = boot()
    local id1 = E.exported.spawnWagon(7, 't1', { x = 0, y = 0, z = 0, w = 0 })
    E.ready()
    local id2 = E.exported.spawnWagon(7, 't1', { x = 50, y = 0, z = 0, w = 0 })
    E.ready()
    T.eq('CID1:t1', id1); T.eq(id1, id2)
    T.eq(2, #E.registers)
    T.same({ type = 'wagon', id = 'fh:wagon:CID1:t1' }, E.registers[1].ref)
    T.same(E.registers[1].ref, E.registers[2].ref)
    T.same({ 1 }, E.despawns, 'old entity despawned, container untouched')
    T.eq(0, #E.cleared, 'no clearContainer / deleteContainer')
    -- source-level guard: no fh_cargo file calls clearContainer / deleteContainer (they would drop the stash)
    for _, f in ipairs({ 'server/main.lua', 'server/wagon_buy.lua', 'client/main.lua' }) do
        local fh = assert(io.open(CARGO .. f, 'rb')); local s = fh:read('a'); fh:close()
        assert(not s:find('clearContainer') and not s:find('deleteContainer'), f .. ' must not wipe wagon stashes')
    end
end)

case('migration and the startup DDL define the same fh_wagons table (PK citizenid, tier)', function()
    local function norm(x) return (x:gsub('%-%-[^\n]*', ''):gsub('%s+', ' '):gsub(';', ''):match('CREATE TABLE.-COLLATE=utf8mb4_general_ci')) end
    local fh = assert(io.open(here .. '../server/migrations/0022_fh_wagons.sql', 'rb')); local mig = fh:read('a'); fh:close()
    fh = assert(io.open(CARGO .. 'server/main.lua', 'rb')); local main = fh:read('a'); fh:close()
    local m = norm(mig)
    assert(m and m:find('PRIMARY KEY %(`citizenid`, `tier`%)'), 'migration PK')
    T.eq(m, norm(main:match('%[%[(CREATE TABLE IF NOT EXISTS `fh_wagons`.-)%]%]')))
end)

T.finish()

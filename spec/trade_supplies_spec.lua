-- fh_trade supplies (BUY side, idea-716/719): pure shared/supplies.lua with stubbed charge / grant / refund deps.
-- Run from repo root: `~/.venvs/rf/bin/python tools/run-specs.py spec/trade_supplies_spec.lua`.
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local it, eq = T.it, T.eq
local fh = here .. '../server/resources/[fh]/'
local S = dofile(fh .. 'fh_trade/shared/supplies.lua')
dofile(here .. 'support/world_config.lua') -- FhRegions + FhPlaceResolver (world-02 block F)
dofile(fh .. 'fh_trade/config.lua')

local CFG = { maxBuyPerTx = 100, supplies = { lumber = 3, nails = 2 } }
local POST = { id = 'valentine_post', region = 'heartlands' }

-- Stub deps. `over` replaces any dep; calls are recorded in d.calls.
local function deps(over)
    local d = { calls = { charge = {}, grant = {}, refund = {} }, logs = {} }
    d.citizenid = function() return 'CID1' end
    d.charge = function(...) table.insert(d.calls.charge, { ... }) return true, nil, 77 end
    d.grant = function(...) table.insert(d.calls.grant, { ... }) return true end
    d.refund = function(...) table.insert(d.calls.refund, { ... }) return true, nil, 'paid' end
    d.log = function(fmt, ...) table.insert(d.logs, fmt:format(...)) end
    for k, v in pairs(over or {}) do
        local f = v
        if k == 'charge' or k == 'grant' or k == 'refund' then
            d[k] = function(...) table.insert(d.calls[k], { ... }) return f(...) end
        else d[k] = f end
    end
    return d
end
local function hasLog(d, pat) for _, l in ipairs(d.logs) do if l:find(pat) then return true end end return false end

-- ---------------------------------------------------------------- validation / prices

it('validate: price x amount, unknown item and bad amounts refused', function()
    local total, price = S.validate(CFG, 'lumber', 4)
    eq(12, total, 'total'); eq(3, price, 'price')
    eq(nil, (S.validate(CFG, 'trade_salt', 1)), 'not in supplies')
    eq('unknown_item', select(2, S.validate(CFG, 'trade_salt', 1)))
    eq('unknown_item', select(2, S.validate(CFG, nil, 1)))
    for _, a in ipairs({ 0, -1, 101, 1.5, 0 / 0, math.huge }) do
        eq('invalid_amount', select(2, S.validate(CFG, 'lumber', a)), 'amount ' .. tostring(a))
    end
    eq('invalid_amount', select(2, S.validate(CFG, 'lumber', '2')), 'string amount')
    eq('invalid_amount', select(2, S.validate(CFG, 'lumber', nil)), 'nil amount')
    eq(300, (S.validate(CFG, 'lumber', 100)), 'max amount ok')
end)

it('carrot/potato/corn: priced above every sell value, so buy -> sell is never a profit loop (idea-915)', function()
    for _, item in ipairs({ 'carrot', 'potato', 'corn' }) do
        local price = FhTradeConfig.supplies[item]
        assert(price and price >= 1, item .. ' not in supplies')
        assert(not FhTradeConfig.goods[item], item .. ' is a trade good (sellable via the price model)')
        local g = FhTradeConfig.goods[item]
        assert(not g or price > g.value_base, item .. ' price not above value_base')
    end
end)

it('real config: the 12 supplies are listed with positive whole-dollar prices, separate from trade goods', function()
    local want = { 'lumber', 'nails', 'lead', 'casings', 'resource_gunpowder', 'herb_american_ginseng', 'herb_oregano',
        'herb_red_sage', 'herb_wild_mint', 'carrot', 'potato', 'corn' }
    local n = 0
    for _ in pairs(FhTradeConfig.supplies) do n = n + 1 end
    eq(#want, n, 'supplies count')
    for _, item in ipairs(want) do
        local total, price = S.validate(FhTradeConfig, item, 1)
        assert(total and price >= 1 and price % 1 == 0, item .. ' has no whole-dollar price')
        -- Supplies are flat config prices; the R3 price model (goods) is never consulted or touched for them.
        assert(not FhTradeConfig.goods[item], item .. ' is also a trade good (would mix with the price model)')
    end
    assert(FhTradeConfig.maxBuyPerTx and FhTradeConfig.maxBuyPerTx >= 1, 'maxBuyPerTx')
    eq('carrot', S.list(FhTradeConfig)[1].item, 'list sorted')
end)

-- ---------------------------------------------------------------- happy path

it('buy: charges the post region with the exact total, then grants to the backpack; no refund', function()
    local d, lock = deps(), {}
    local ok, total, price = S.buy(CFG, d, lock, 5, POST, 'lumber', 4)
    assert(ok == true, 'buy failed: ' .. tostring(total))
    eq(12, total); eq(3, price)
    eq(1, #d.calls.charge, 'one charge')
    T.same({ 5, 12, 'trade_buy:lumber', 'heartlands' }, d.calls.charge[1], 'charge(src, total, reason, post region)')
    T.same({ 5, 'lumber', 4 }, d.calls.grant[1], 'grant(src, item, amount)')
    eq(0, #d.calls.refund, 'no refund')
    eq(nil, lock[5], 'lock released')
end)

it('buy: invalid item / amount / post / player -> no charge, no grant', function()
    for _, case in ipairs({
        { 5, POST, 'trade_salt', 1, 'unknown_item' }, { 5, POST, 'lumber', 0, 'invalid_amount' },
        { 5, nil, 'lumber', 1, 'no_post' }, { 5, { id = 'x' }, 'lumber', 1, 'no_post' }, { 0, POST, 'lumber', 1, 'no_player' },
    }) do
        local d, lock = deps(), {}
        local ok, err = S.buy(CFG, d, lock, case[1], case[2], case[3], case[4])
        assert(ok == false, 'accepted ' .. case[5]); eq(case[5], err)
        eq(0, #d.calls.charge, case[5] .. ': charged'); eq(0, #d.calls.grant, case[5] .. ': granted')
        eq(nil, lock[case[1]], case[5] .. ': lock held')
    end
end)

it('buy: no loaded character (no citizenid) -> no_player, nothing charged', function()
    local d, lock = deps({ citizenid = function() return nil end }), {}
    local ok, err = S.buy(CFG, d, lock, 5, POST, 'lumber', 1)
    assert(not ok); eq('no_player', err)
    eq(0, #d.calls.charge); eq(nil, lock[5])
end)

-- ---------------------------------------------------------------- charge failures

it('charge refused (insufficient funds) -> no item, no refund, error passed through', function()
    local d, lock = deps({ charge = function() return false, 'fh_insufficient_funds' end }), {}
    local ok, err = S.buy(CFG, d, lock, 5, POST, 'lumber', 2)
    assert(not ok); eq('fh_insufficient_funds', err)
    eq(0, #d.calls.grant, 'granted without payment'); eq(0, #d.calls.refund, 'refunded a failed charge')
    eq(nil, lock[5])
end)

it('fh_charge_busy is a plain refusal with its own code: no addItem, no refund', function()
    local d, lock = deps({ charge = function() return false, 'fh_charge_busy' end }), {}
    local ok, err = S.buy(CFG, d, lock, 5, POST, 'lumber', 2)
    assert(not ok); eq('fh_charge_busy', err)
    assert(err ~= 'busy' and err ~= 'fh_insufficient_funds', 'not distinct')
    eq(0, #d.calls.grant); eq(0, #d.calls.refund); eq(nil, lock[5])
end)

it('charge returns falsy with no code -> charge_failed; charge throws -> charge_error, no item', function()
    local d = deps({ charge = function() return nil end })
    eq('charge_failed', select(2, S.buy(CFG, d, {}, 5, POST, 'lumber', 1)))
    eq(0, #d.calls.grant)
    local d2, lock = deps({ charge = function() error('export missing') end }), {}
    local ok, err = S.buy(CFG, d2, lock, 5, POST, 'lumber', 1)
    assert(not ok); eq('charge_error', err)
    eq(0, #d2.calls.grant); eq(0, #d2.calls.refund); eq(nil, lock[5])
    assert(hasLog(d2, 'ALERT charge threw'), 'no ALERT log')
end)

it('charge returning a truthy non-true value is not treated as paid', function()
    local d = deps({ charge = function() return 1 end })
    local ok = S.buy(CFG, d, {}, 5, POST, 'lumber', 1)
    assert(not ok); eq(0, #d.calls.grant)
end)

-- ---------------------------------------------------------------- grant failures -> refund

it('grant refused (backpack full, addItem all-or-nothing) -> full refund to the charged citizenid', function()
    for _, why in ipairs({ 'fh_too_heavy', 'fh_no_slot', 'fh_size_class', 'fh_player_offline' }) do
        local d, lock = deps({ grant = function() return false, why end }), {}
        local ok, err, detail = S.buy(CFG, d, lock, 5, POST, 'lumber', 4)
        assert(not ok, why); eq('grant_failed_refunded', err, why); eq(why, detail, why)
        eq(1, #d.calls.charge, why .. ': charged more than once')
        eq(1, #d.calls.refund, why .. ': refund count')
        T.same({ 'CID1', 12, 'trade_buy_refund:lumber', 'heartlands' }, d.calls.refund[1], why .. ': refund(cid, exact total, reason, region)')
        eq(nil, lock[5], why .. ': lock held')
    end
end)

it('grant throws -> refunded and logged', function()
    local d, lock = deps({ grant = function() error('fh_core stopped') end }), {}
    local ok, err, detail = S.buy(CFG, d, lock, 5, POST, 'nails', 3)
    assert(not ok); eq('grant_failed_refunded', err); eq('threw', detail)
    T.same({ 'CID1', 6, 'trade_buy_refund:nails', 'heartlands' }, d.calls.refund[1])
    assert(hasLog(d, 'ALERT grant threw')); eq(nil, lock[5])
end)

it('refund fails or throws -> distinct refund_failed + ALERT log with the owed amount', function()
    for _, f in ipairs({ function() return false, 'ledger_failed' end, function() error('boom') end, function() return nil end }) do
        local d, lock = deps({ grant = function() return false, 'fh_too_heavy' end, refund = f }), {}
        local ok, err, detail = S.buy(CFG, d, lock, 5, POST, 'lumber', 4)
        assert(not ok); eq('refund_failed', err); eq('fh_too_heavy', detail)
        assert(err ~= 'grant_failed_refunded')
        assert(hasLog(d, 'ALERT refund FAILED for CID1') and hasLog(d, 'owed %$12'), 'no owed ALERT')
        eq(1, #d.calls.charge); eq(nil, lock[5])
    end
end)

-- ---------------------------------------------------------------- lock

it('lock: a second buy while one is in flight is refused busy (no second charge); released afterwards', function()
    local lock, inner = {}, nil
    local d
    d = deps({ charge = function(src)
        inner = { S.buy(CFG, d, lock, src, POST, 'lumber', 1) } -- re-entrant attempt while the charge "yields"
        return true
    end })
    local ok = S.buy(CFG, d, lock, 5, POST, 'lumber', 2)
    assert(ok == true, 'outer buy failed')
    eq(false, inner[1]); eq('busy', inner[2])
    eq(1, #d.calls.charge, 'second charge happened'); eq(1, #d.calls.grant)
    eq(nil, lock[5], 'lock held after success')
    assert(S.buy(CFG, deps(), lock, 5, POST, 'lumber', 1) == true, 'lock not reusable')
end)

it('lock: a held lock (e.g. a sale in flight, shared table) refuses the buy without touching anything', function()
    local d, lock = deps(), { [5] = true }
    eq('busy', select(2, S.buy(CFG, d, lock, 5, POST, 'lumber', 1)))
    eq(0, #d.calls.charge); eq(true, lock[5], 'released a lock it did not take')
end)

it('lock: released when a dep throws before the charge and when logging throws', function()
    local d, lock = deps({ citizenid = function() error('rsg-core down') end }), {}
    eq('internal_error', select(2, S.buy(CFG, d, lock, 5, POST, 'lumber', 1)))
    eq(nil, lock[5]); eq(0, #d.calls.charge)
    local d2, lock2 = deps({ grant = function() error('x') end, log = function() error('log broke') end }), {}
    eq('grant_failed_refunded', select(2, S.buy(CFG, d2, lock2, 5, POST, 'lumber', 1)), 'log throw changed the outcome')
    eq(nil, lock2[5]); eq(1, #d2.calls.refund)
end)

T.finish()

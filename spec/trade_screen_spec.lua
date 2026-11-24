-- fh_trade tradepost screen data + result notices (T1): pure shared/screen.lua.
-- Run from repo root: `~/.venvs/rf/bin/python tools/run-specs.py spec/trade_screen_spec.lua`.
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local it, eq, same = T.it, T.eq, T.same
local fh = here .. '../server/resources/[fh]/'
local Sc = dofile(fh .. 'fh_trade/shared/screen.lua')

local CFG = {
    maxSellPerTx = 100, maxBuyPerTx = 100,
    goods = { trade_salt = { label = 'Salt Sack', base = 6 }, trade_cloth = { label = 'Bolt of Cloth', base = 14 } },
    supplies = { lumber = 3, nails = 2 },
}
local POST = { label = 'Valentine Trade Post', region = 'heartlands' }

local DETAIL = { trade_salt = { shortage = 0.5, saturation = 0.0 }, trade_cloth = { shortage = 0.0, saturation = 0.4 } }
local function quote(region, item, now) return CFG.goods[item].base * 10, DETAIL[item] end
local function labelOf(item) return item end
local function reason(code)
    return ({ fh_not_enough = 'You do not have that many.', not_at_post = 'You are not at a trade post.' })[code]
        or ('Trade refused (' .. tostring(code) .. ').')
end

it('screenData: sorted goods carry shortage/saturation, supplies carry flat price, max_sell/max_buy', function()
    local d = Sc.screenData(CFG, POST, quote, labelOf, 0)
    eq('Valentine Trade Post', d.label); eq('heartlands', d.region)
    eq(100, d.max_sell); eq(100, d.max_buy)
    eq(2, #d.goods); eq('trade_cloth', d.goods[1].item); eq('trade_salt', d.goods[2].item)
    same({ item = 'trade_salt', label = 'Salt Sack', price = 60, shortage = 0.5, saturation = 0.0 }, d.goods[2])
    eq(2, #d.supplies); eq('lumber', d.supplies[1].item); eq(3, d.supplies[1].price)
end)

it('screenData: unusable post -> nil', function()
    eq(nil, Sc.screenData(CFG, nil, quote, labelOf, 0))
    eq(nil, Sc.screenData(CFG, { label = 'x' }, quote, labelOf, 0))
end)

it('sellNotice: success and refusal (wording via reason)', function()
    local msg, kind = Sc.sellNotice('Salt Sack', 3, true, 18, reason)
    eq('Sold 3x Salt Sack for $18.', msg); eq('ok', kind)
    msg, kind = Sc.sellNotice('Salt Sack', 3, false, 'fh_not_enough', reason)
    eq('You do not have that many.', msg); eq('error', kind)
    msg = Sc.sellNotice('Salt Sack', 3, false, 'not_at_post', reason)
    eq('You are not at a trade post.', msg)
end)

it('buyNotice: success and refusal (invalid_amount uses the buy max, unknown_item distinct)', function()
    local msg, kind = Sc.buyNotice(CFG, 'Lumber', 4, true, 12, nil, reason)
    eq('Bought 4x Lumber for $12.', msg); eq('ok', kind)
    msg, kind = Sc.buyNotice(CFG, 'Lumber', 4, false, 'invalid_amount', nil, reason)
    eq('Amount must be a whole number from 1 to 100.', msg); eq('error', kind)
    msg = Sc.buyNotice(CFG, 'Lumber', 4, false, 'unknown_item', nil, reason)
    eq('The post does not sell that.', msg)
end)

it('buyMessage: refund detail appended only for non-refund_failed refusals', function()
    eq('The post does not sell that.', Sc.buyMessage(CFG, 'unknown_item', nil, reason))
    local m = Sc.buyMessage(CFG, 'fh_too_heavy', 'fh_too_heavy', reason)
    assert(m:find('fh_too_heavy', 1, true) ~= nil, 'detail missing: ' .. m)
    local r = Sc.buyMessage(CFG, 'refund_failed', 'fh_too_heavy', reason)
    assert(r:find('fh_too_heavy', 1, true) == nil, 'refund_failed appended detail: ' .. r)
end)

T.finish()

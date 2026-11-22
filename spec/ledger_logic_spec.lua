-- Run from repo root: `lua spec/ledger_logic_spec.lua` (or via busted).
local case = dofile('./spec/_harness.lua').case
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

-- Run from repo root: `lua spec/fence_spec.lua`.
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
package.path = here .. '../server/resources/[fh]/fh_fence/shared/?.lua;' .. package.path
local case = T.it
local logic = require('fence_logic')
local regions = require('regions')

assert(loadfile(here .. '../server/resources/[fh]/fh_fence/config.lua'))()
local cfg = FhFenceConfig
assert(loadfile(here .. '../server/resources/[fh]/fh_progression/config.lua'))()

case('config: stops use known regions, rotation/stock/items consistent', function()
    for id, s in pairs(cfg.stops) do
        assert(regions.isKnownRegion(s.region_id), id)
        assert(type(s.coords.x) == 'number' and type(s.coords.y) == 'number' and type(s.coords.z) == 'number', id)
    end
    for _, id in ipairs(cfg.rotation) do assert(cfg.stops[id] and cfg.stock[id], id) end
    for stopId, st in pairs(cfg.stock) do
        for _, cat in ipairs({ 'common', 'rare', 'leads' }) do
            for _, e in ipairs(st[cat] or {}) do
                assert(type(e.price) == 'number' and e.price > 0, stopId .. cat)
                if cat ~= 'common' then assert(cfg.items[e.item], 'unregistered ' .. e.item) end
                if cat == 'leads' then assert(logic.leadInfo(e), 'lead info ' .. stopId) end
            end
        end
    end
    local u = FhProgressionConfig.unlocks
    assert(u.fence_rare_stock and u.fence_treasure_leads)
end)

local DWELL = cfg.dwellMinutes * 60
case('schedule: deterministic stop, next stop, remaining', function()
    local a = logic.schedule(cfg, 0)
    T.eq(cfg.rotation[1], a.stop)
    T.eq(cfg.rotation[2], a.nextStop)
    T.eq(DWELL, a.remaining)
    local b = logic.schedule(cfg, DWELL - 1)
    T.eq(cfg.rotation[1], b.stop); T.eq(1, b.remaining)
    local c = logic.schedule(cfg, DWELL)
    T.eq(cfg.rotation[2], c.stop); T.eq(cfg.rotation[1], c.nextStop)
    T.eq(cfg.rotation[1], logic.schedule(cfg, #cfg.rotation * DWELL).stop) -- wraps
    T.same(logic.schedule(cfg, 123456), logic.schedule(cfg, 123456))
end)
case('schedule: bad input returns nil + reason', function()
    local r, why = logic.schedule({ rotation = {}, dwellMinutes = 5, stops = {} }, 1); assert(r == nil); T.eq('bad_rotation', why)
    r, why = logic.schedule({ rotation = { 'x' }, dwellMinutes = 5, stops = {} }, 1); T.eq('unknown_stop', why)
    r, why = logic.schedule({ rotation = { 'x' }, dwellMinutes = 0, stops = { x = {} } }, 1); T.eq('bad_dwell', why)
    r, why = logic.schedule(cfg, -1); T.eq('bad_time', why)
    r, why = logic.schedule(nil, 1); T.eq('bad_rotation', why)
end)

case('filterStock gates rare and leads by tier flags', function()
    local st = cfg.stock.heartlands_camp
    T.eq(#st.common, #logic.filterStock(st, false, false))
    T.eq(#st.common + #st.rare, #logic.filterStock(st, true, false))
    T.eq(#st.common + #st.leads, #logic.filterStock(st, false, true))
    T.eq(#st.common + #st.rare + #st.leads, #logic.filterStock(st, true, true))
    T.eq(0, #logic.filterStock(nil, true, true))
end)

case('quoteBuy: price, qty and stock validation', function()
    local vis = logic.filterStock(cfg.stock.heartlands_road, true, true)
    local q = logic.quoteBuy(vis, 'fh_part_gunsmith', 3, cfg.maxQty)
    T.eq(3 * 90, q.total)
    local _, why = logic.quoteBuy(vis, 'fh_part_gunsmith', 0, cfg.maxQty); T.eq('bad_qty', why)
    _, why = logic.quoteBuy(vis, 'fh_part_gunsmith', 1.5, cfg.maxQty); T.eq('bad_qty', why)
    _, why = logic.quoteBuy(vis, 'fh_part_gunsmith', 21, cfg.maxQty); T.eq('bad_qty', why)
    _, why = logic.quoteBuy(vis, 'fh_treasure_lead', 2, cfg.maxQty); T.eq('bad_qty', why)
    _, why = logic.quoteBuy(vis, 'nope', 1, cfg.maxQty); T.eq('not_in_stock', why)
    _, why = logic.quoteBuy(vis, nil, 1, cfg.maxQty); T.eq('bad_item', why)
    -- gated stock is not buyable
    local low = logic.filterStock(cfg.stock.heartlands_road, false, false)
    _, why = logic.quoteBuy(low, 'fh_part_gunsmith', 1, cfg.maxQty); T.eq('not_in_stock', why)
    _, why = logic.quoteBuy(low, 'fh_treasure_lead', 1, cfg.maxQty); T.eq('not_in_stock', why)
end)

case('quoteSell: only bought items and qty (payout cap is fh_economy pay\'s amount_too_large)', function()
    T.eq(30 * 2, logic.quoteSell(cfg, 'fh_part_gunsmith', 2))
    local _, why = logic.quoteSell(cfg, 'bread', 1); T.eq('not_bought', why)
    _, why = logic.quoteSell(cfg, 'fh_part_gunsmith', 0); T.eq('bad_qty', why)
    _, why = logic.quoteSell(cfg, 'fh_part_gunsmith', cfg.maxQty + 1); T.eq('bad_qty', why)
    _, why = logic.quoteSell(cfg, 5, 1); T.eq('bad_item', why)
end)

case('leadInfo carries target coords and hint', function()
    local e = cfg.stock.heartlands_road.leads[1]
    local info = logic.leadInfo(e)
    T.same(e.lead.coords, info.target)
    T.eq(e.lead.hint, info.hint)
    assert(logic.leadInfo({}) == nil and logic.leadInfo({ lead = { coords = { x = 1 } } }) == nil)
end)

case('inRange and parseFlag', function()
    local stop = { x = 0, y = 0, z = 0 }
    assert(logic.inRange({ x = 3, y = 4, z = 0 }, stop, 5.0))
    assert(not logic.inRange({ x = 3, y = 4, z = 1 }, stop, 5.0))
    assert(not logic.inRange(nil, stop, 5.0) and not logic.inRange({ x = 'a', y = 0, z = 0 }, stop, 5.0))
    assert(logic.parseFlag('true', false) and not logic.parseFlag('0', true) and logic.parseFlag('x', true))
end)
case('spawnEnabled: fh_spike_gated true/unset/garbage = gated = no NPC; false = spawn (spike-gated.md polarity)', function()
    assert(not logic.spawnEnabled('true') and not logic.spawnEnabled(nil) and not logic.spawnEnabled('maybe'))
    assert(not logic.spawnEnabled('1') and not logic.spawnEnabled('on'))
    assert(logic.spawnEnabled('false') and logic.spawnEnabled('0') and logic.spawnEnabled('off'))
end)

case('sellOutcome: pay ok completes without restoring', function()
    local called = false
    local o = logic.sellOutcome(true, nil, function() called = true; return true end)
    T.eq('complete', o.action); assert(not called)
end)
case('sellOutcome: pay fails -> item given back and logged', function()
    for _, why in ipairs({ 'addmoney_refused', 'ledger_failed', 'no_player' }) do
        local called = false
        local o = logic.sellOutcome(false, why, function() called = true; return true end,
            { citizenid = 'C1', item = 'fh_part_gunsmith', qty = 2 })
        T.eq('refunded', o.action); T.eq(why, o.reason); assert(called)
        assert(o.log:find(why, 1, true))
    end
    T.eq('pay_failed', logic.sellOutcome(false, nil, function() return true end).reason)
end)
case('sellOutcome: pay AND restore fail -> WARNING with citizenid/item/qty', function()
    local o = logic.sellOutcome(false, 'ledger_failed', function() return false, 'fh_refused' end,
        { citizenid = 'C1', item = 'fh_part_gunsmith', qty = 2 })
    T.eq('warning', o.action)
    assert(o.log:find('WARNING', 1, true) and o.log:find('C1', 1, true)
        and o.log:find('fh_part_gunsmith', 1, true) and o.log:find('qty=2', 1, true) and o.log:find('fh_refused', 1, true))
end)

case('admin: secondsToNext lands exactly on the next stop', function()
    local now = 1700000000
    local s = logic.schedule(cfg, now)
    local jump = logic.secondsToNext(cfg, now)
    T.eq(s.remaining, jump)
    T.eq(s.nextStop, logic.schedule(cfg, now + jump).stop)
    assert(logic.secondsToNext({}, now) == nil)
end)

T.finish()

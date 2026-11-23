-- Run from repo root: `lua spec/fence_trade_spec.lua` (Lua 5.4: pcall must be yieldable).
-- Drives the real fh_fence/server/trade.lua with fake fh_core / fh_economy deps. Every fake dep yields first (when
-- called inside a coroutine), like an export that awaits MySQL, so `interleave` can run two trades step by step.
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local fence = here .. '../server/resources/[fh]/fh_fence/'
package.path = fence .. 'shared/?.lua;' .. fence .. 'server/?.lua;' .. package.path
local case = T.it
local logic = require('fence_logic')
local trade = require('trade')

assert(loadfile(fence .. 'config.lua'))()
local cfg = FhFenceConfig
local GUN, PRICE, SELL = 'fh_part_gunsmith', 90, 30 -- heartlands_road rare price, cfg.buys price

-- ---------------------------------------------------------------- fake world

local function copy(t)
    if type(t) ~= 'table' then return t end
    local o = {}
    for k, v in pairs(t) do o[k] = copy(v) end
    return o
end

local function count(box, name)
    local n = 0
    for _, it in pairs(box) do if it.name == name then n = n + it.amount end end
    return n
end

local function size(box) local n = 0; for _ in pairs(box) do n = n + 1 end; return n end

local SLOTS = 10

local function put(box, name, amount, info)
    local stack = cfg.items[name] == nil or cfg.items[name].stackable ~= false
    if stack then
        for _, it in pairs(box) do
            if it.name == name then it.amount = it.amount + amount; return end
        end
    end
    for s = 1, SLOTS do
        if not box[s] then box[s] = { name = name, amount = amount, info = info }; return end
    end
    error('fake box full')
end

local STASH = trade.stashRef('C1', cfg.fenceId).id

---o.players: cid -> { money, bag = {slot -> item}, room = units the backpack can still take }
local function world(o)
    o = o or {}
    local W = {
        players = { C1 = { money = 1000, bag = {}, room = 100 }, C2 = { money = 1000, bag = {}, room = 100 } },
        srcs = { [1] = 'C1', [2] = 'C1', [3] = 'C2' }, -- src 2 = C1 reconnected
        stashes = {}, fail = {}, hooks = {}, calls = {}, logs = {}, refunds = {}, clock = 0,
    }
    for cid, p in pairs(o.players or {}) do for k, v in pairs(p) do W.players[cid][k] = v end end
    if o.stash then W.stashes[STASH] = o.stash end

    local function P(src) return W.players[W.srcs[src]] end
    local function box(ref)
        if ref.type == 'backpack' then return P(ref.id).bag end
        W.stashes[ref.id] = W.stashes[ref.id] or {}
        return W.stashes[ref.id]
    end
    local function step(name, ...)
        if coroutine.isyieldable() then coroutine.yield(name) end
        W.calls[name] = (W.calls[name] or 0) + 1
        local h = W.hooks[name]
        if h then h(W, W.calls[name], ...) end
    end

    W.deps = {
        citizenOf = function(src) return W.srcs[src] end,
        stopFor = function()
            step('stopFor')
            return cfg.stops.heartlands_road, 'heartlands_road'
        end,
        visibleStock = function(_, id)
            step('visibleStock')
            return logic.filterStock(cfg.stock[id], true, true)
        end,
        ensureStash = function(ref) step('ensureStash'); box(ref); return true end,
        snapshot = function(ref)
            step('snapshot', ref)
            if ref.type == 'fence_stash' and W.fail.snapshotStash then return nil, 'fh_inventory_down' end
            return copy(box(ref))
        end,
        view = function(ref) step('view'); return { slots = SLOTS, items = copy(box(ref)) } end,
        canFit = function(ref, _, qty)
            step('canFit')
            if qty <= P(ref.id).room then return true end
            return false, 'no_room'
        end,
        addItem = function(ref, name, qty, info)
            step('addItem')
            if W.fail.addItem then return false, W.fail.addItem end
            put(box(ref), name, W.addShort and qty - 1 or qty, info)
            return true
        end,
        clear = function(ref)
            step('clear')
            if W.fail.clear then return false, W.fail.clear end
            local b = box(ref)
            for k in pairs(b) do b[k] = nil end
            return true
        end,
        transferAll = function(from, to)
            step('transferAll')
            if W.fail.transferAll then return false, W.fail.transferAll end
            local src, dst, moved = box(from), box(to), {}
            local slots = {}
            for s in pairs(src) do slots[#slots + 1] = s end
            table.sort(slots)
            for _, s in ipairs(slots) do
                local it = src[s]
                local n = it.amount
                if to.type == 'backpack' then n = math.min(n, P(to.id).room) end
                if n > 0 then
                    put(dst, it.name, n, it.info)
                    if to.type == 'backpack' then P(to.id).room = P(to.id).room - n end
                    it.amount = it.amount - n
                    if it.amount == 0 then src[s] = nil end
                    moved[#moved + 1] = { name = it.name, amount = n }
                end
            end
            return true, moved, {}
        end,
        move = function(from, to, fromSlot, toSlot, amount) -- name-agnostic, like the real one
            step('move')
            local s, d = box(from)[fromSlot], box(to)
            if not s or s.amount < amount then return false, 'fh_no_item' end
            if d[toSlot] then return false, 'fh_slot_taken' end
            d[toSlot] = { name = s.name, amount = amount, info = s.info }
            s.amount = s.amount - amount
            if s.amount == 0 then box(from)[fromSlot] = nil end
            if from.type == 'backpack' then P(from.id).room = P(from.id).room + amount end
            return true
        end,
        charge = function(src, amount)
            step('charge')
            if W.fail.charge then return false, W.fail.charge end
            if P(src).money < amount then return false, 'fh_insufficient_funds' end
            P(src).money = P(src).money - amount
            return true
        end,
        pay = function(src, amount, reason)
            step('pay')
            local f = W.fail.pay
            if f and reason:find(f.reason, 1, true) then return false, f.err end
            P(src).money = P(src).money + amount
            if reason == 'fence_refund' then W.refunds[#W.refunds + 1] = amount end
            return true
        end,
        log = function(m) W.logs[#W.logs + 1] = m end,
        now = function() return W.clock end,
    }
    W.T = trade.new(cfg, logic, W.deps)
    W.stash = function() return W.stashes[STASH] or {} end
    W.C1 = W.players.C1
    return W
end

local function logged(W, needle)
    for _, l in ipairs(W.logs) do if l:find(needle, 1, true) then return true end end
    return false
end

---Round-robin: resume each trade one yield at a time until all are done. Returns packed results.
local function interleave(fns)
    local cos, res = {}, {}
    for i, f in ipairs(fns) do cos[i] = coroutine.create(f) end
    repeat
        local live = false
        for i, co in ipairs(cos) do
            if coroutine.status(co) == 'suspended' then
                live = true
                local r = table.pack(coroutine.resume(co))
                if not r[1] then error(r[2]) end
                if coroutine.status(co) == 'dead' then res[i] = table.pack(table.unpack(r, 2, r.n)) end
            end
        end
    until not live
    return res
end

local function drain(co)
    local r
    while coroutine.status(co) == 'suspended' do
        r = table.pack(coroutine.resume(co))
        if not r[1] then error(r[2]) end
    end
    return table.pack(table.unpack(r, 2, r.n))
end

-- ---------------------------------------------------------------- contract

case('stashRef follows fh:fence:<citizenid>:<fence_id> (inventory.md:74)', function()
    local r = trade.stashRef('ABC123', cfg.fenceId)
    T.eq('fence_stash', r.type)
    T.eq('fh:fence:ABC123:' .. cfg.fenceId, r.id)
    assert(r.id:match('^fh:fence:[^:]+:[^:]+$'))
end)

-- ---------------------------------------------------------------- concurrency (finding 1)

case('concurrency: buy + buy interleaved (same citizen, two srcs) -> one trade, other fence_busy', function()
    local W = world()
    local r = interleave({ function() return W.T.buy(1, GUN, 2) end, function() return W.T.buy(2, GUN, 3) end })
    T.same({ true, 2, 0, n = 3 }, r[1])
    T.same({ false, 'fence_busy', n = 2 }, r[2])
    T.eq(2, count(W.C1.bag, GUN)); T.eq(1000 - 2 * PRICE, W.C1.money); T.eq(0, size(W.stash()))
    assert(not W.T.locks.held('C1'))
end)

case('concurrency: sell + buy interleaved -> buy busy, no item returned, money paid once', function()
    local W = world({ players = { C1 = { bag = { [1] = { name = GUN, amount = 4 } } } } })
    local r = interleave({ function() return W.T.sell(1, GUN, 4) end, function() return W.T.buy(1, GUN, 1) end })
    T.same({ true, 4, 4 * SELL, n = 3 }, r[1])
    T.same({ false, 'fence_busy', n = 2 }, r[2])
    T.eq(0, count(W.C1.bag, GUN)); T.eq(1000 + 4 * SELL, W.C1.money); T.eq(0, size(W.stash()))
end)

case('concurrency: sell + sell interleaved -> second busy, nothing wiped', function()
    local W = world({ players = { C1 = { bag = { [1] = { name = GUN, amount = 3 } } } } })
    local r = interleave({ function() return W.T.sell(1, GUN, 2) end, function() return W.T.sell(1, GUN, 1) end })
    T.same({ true, 2, 2 * SELL, n = 3 }, r[1])
    T.same({ false, 'fence_busy', n = 2 }, r[2])
    T.eq(1, count(W.C1.bag, GUN)); T.eq(1000 + 2 * SELL, W.C1.money); T.eq(0, size(W.stash()))
end)

case('concurrency: two different characters trade in parallel', function()
    local W = world()
    local r = interleave({ function() return W.T.buy(1, GUN, 1) end, function() return W.T.buy(3, GUN, 2) end })
    assert(r[1][1] and r[2][1])
    T.eq(1, count(W.players.C1.bag, GUN)); T.eq(2, count(W.players.C2.bag, GUN))
    T.eq(1000 - PRICE, W.players.C1.money); T.eq(1000 - 2 * PRICE, W.players.C2.money)
end)

case('lock: released after success, refusal and a thrown error', function()
    local W = world()
    T.same({ false, 'bad_qty', n = 2 }, table.pack(W.T.buy(1, GUN, 0)))
    assert(not W.T.locks.held('C1'))
    W.hooks.charge = function() error('boom') end
    T.same({ false, 'fence_error', n = 2 }, table.pack(W.T.buy(1, GUN, 1)))
    assert(not W.T.locks.held('C1')); assert(logged(W, 'ERROR buy citizenid=C1'))
    -- the throw left the stage in the stash: never handed out or wiped, the next trade is refused
    W.hooks.charge = nil
    T.same({ false, 'fence_pending', n = 2 }, table.pack(W.T.buy(1, GUN, 1)))
    T.eq(0, count(W.C1.bag, GUN)); T.eq(1000, W.C1.money); T.eq(1, count(W.stash(), GUN))
    assert(not W.T.locks.held('C1'))
end)

case('lock: player drop revokes; in-flight trade stops before staging; reconnect waits, then trades', function()
    local W = world()
    local a = coroutine.create(function() return W.T.buy(1, GUN, 2) end)
    assert(coroutine.resume(a)) -- A holds the lock, yielded in stopFor
    W.T.dropped(1)
    T.same({ false, 'fence_busy', n = 2 }, table.pack(W.T.buy(2, GUN, 1))) -- not interleaved with A
    T.same({ false, 'fence_busy', n = 2 }, drain(a)) -- A notices the revoke and stops
    T.eq(nil, W.calls.addItem); T.eq(1000, W.C1.money); T.eq(0, size(W.stash()))
    assert(not W.T.locks.held('C1'))
    T.same({ true, 1, 0, n = 3 }, table.pack(W.T.buy(2, GUN, 1)))
end)

case('lock: drop after staging -> the revoked buy discards its stage before charging', function()
    local W = world()
    W.hooks.addItem = function() W.T.dropped(1) end
    T.same({ false, 'fence_busy', n = 2 }, table.pack(W.T.buy(1, GUN, 2)))
    T.eq(nil, W.calls.charge); T.eq(0, size(W.stash())); T.eq(1000, W.C1.money)
end)

case('lock: a never-resuming trade is reclaimed after lockStaleSeconds; its late release keeps the new lock', function()
    local W = world()
    local a = coroutine.create(function() return W.T.buy(1, GUN, 2) end)
    assert(coroutine.resume(a))
    W.clock = cfg.lockStaleSeconds - 1
    T.same({ false, 'fence_busy', n = 2 }, table.pack(W.T.buy(2, GUN, 1)))
    W.clock = cfg.lockStaleSeconds
    local b = coroutine.create(function() return W.T.buy(2, GUN, 1) end)
    assert(coroutine.resume(b)) -- B reclaimed the lock and is in flight
    assert(logged(W, 'reclaimed a stale trade lock'))
    T.same({ false, 'fence_busy', n = 2 }, drain(a))
    assert(W.T.locks.held('C1')) -- A's exit did not free B's lock
    T.same({ true, 1, 0, n = 3 }, drain(b))
    T.eq(1, count(W.C1.bag, GUN)); T.eq(1000 - PRICE, W.C1.money)
end)

-- ---------------------------------------------------------------- stash leftovers (finding 3)

case('leftovers in the stash: buy and sell refused, nothing mixed, wiped or handed out', function()
    local W = world({ stash = { [1] = { name = GUN, amount = 2 } },
        players = { C1 = { bag = { [1] = { name = GUN, amount = 1 } } } } })
    T.same({ false, 'fence_pending', n = 2 }, table.pack(W.T.buy(1, GUN, 1)))
    T.same({ false, 'fence_pending', n = 2 }, table.pack(W.T.sell(1, GUN, 1)))
    T.eq(2, count(W.stash(), GUN)); T.eq(1, count(W.C1.bag, GUN)); T.eq(1000, W.C1.money)
    T.eq(nil, W.calls.clear); T.eq(nil, W.calls.transferAll); T.eq(nil, W.calls.charge)
    assert(logged(W, 'WARNING fence stash not empty'))
end)

-- ---------------------------------------------------------------- buy rollback (findings 1-2, charge contract)

case('buy: success stages, charges, delivers', function()
    local W = world()
    T.same({ true, 3, 0, n = 3 }, table.pack(W.T.buy(1, GUN, 3)))
    T.eq(3, count(W.C1.bag, GUN)); T.eq(1000 - 3 * PRICE, W.C1.money); T.eq(0, size(W.stash()))
end)

case('buy: every charge refusal (B7 contract) -> same code, no item moved, no money moved', function()
    for _, err in ipairs({ 'fh_charge_busy', 'fh_insufficient_funds', 'charge_unavailable', 'no_player' }) do
        local W = world()
        W.fail.charge = err
        T.same({ false, err, n = 2 }, table.pack(W.T.buy(1, GUN, 2)), err)
        T.eq(0, count(W.C1.bag, GUN), err); T.eq(1000, W.C1.money, err); T.eq(0, size(W.stash()), err)
        T.eq(nil, W.calls.transferAll, err)
    end
    local W = world({ players = { C1 = { money = PRICE - 1 } } })
    T.same({ false, 'fh_insufficient_funds', n = 2 }, table.pack(W.T.buy(1, GUN, 1)))
    T.eq(0, size(W.stash()))
end)

case('buy: charge refused and stash clear fails -> stage swept by the next trade, charged once', function()
    local W = world()
    W.fail.charge, W.fail.clear = 'fh_charge_busy', 'fh_inventory_down'
    T.same({ false, 'fh_charge_busy', n = 2 }, table.pack(W.T.buy(1, GUN, 2)))
    T.eq(2, count(W.stash(), GUN)); T.eq(0, count(W.C1.bag, GUN))
    W.fail.charge, W.fail.clear = nil, nil
    T.same({ true, 1, 0, n = 3 }, table.pack(W.T.buy(1, GUN, 1)))
    T.eq(1, count(W.C1.bag, GUN)); T.eq(1000 - PRICE, W.C1.money); T.eq(0, size(W.stash()))
end)

case('buy: stage refused or short -> no charge, stash empty', function()
    local W = world()
    W.fail.addItem = 'fh_refused'
    T.same({ false, 'fh_refused', n = 2 }, table.pack(W.T.buy(1, GUN, 2)))
    T.eq(nil, W.calls.charge); T.eq(0, size(W.stash()))
    W = world()
    W.addShort = true
    T.same({ false, 'stage_failed', n = 2 }, table.pack(W.T.buy(1, GUN, 2)))
    T.eq(nil, W.calls.charge); T.eq(0, size(W.stash())); T.eq(1000, W.C1.money)
end)

case('buy: backpack shrinks during charge -> partial delivery, refund ONLY the undelivered units', function()
    local W = world()
    W.hooks.charge = function() W.C1.room = 1 end
    T.same({ true, 1, 2 * PRICE, n = 3 }, table.pack(W.T.buy(1, GUN, 3)))
    T.eq(1, count(W.C1.bag, GUN)); T.eq(1000 - PRICE, W.C1.money); T.eq(0, size(W.stash()))
    T.same({ 2 * PRICE }, W.refunds)
end)

case('buy: nothing fits after charge -> full refund, no item', function()
    local W = world()
    W.hooks.charge = function() W.C1.room = 0 end
    T.same({ false, 'no_room', n = 2 }, table.pack(W.T.buy(1, GUN, 2)))
    T.eq(0, count(W.C1.bag, GUN)); T.eq(1000, W.C1.money); T.eq(0, size(W.stash()))
end)

case('buy: transferAll errors, stash readable -> undelivered counted from the stash, refunded', function()
    local W = world()
    W.hooks.charge = function() W.fail.transferAll = 'fh_inventory_down' end
    T.same({ false, 'no_room', n = 2 }, table.pack(W.T.buy(1, GUN, 3)))
    T.eq(1000, W.C1.money); T.eq(0, count(W.C1.bag, GUN)); T.eq(0, size(W.stash()))
end)

case('buy: stash unreadable after delivery -> moved list decides the refund (old nil-snapshot bypass)', function()
    local W = world()
    W.hooks.charge = function() W.C1.room = 1; W.fail.snapshotStash = true end
    T.same({ true, 1, 2 * PRICE, n = 3 }, table.pack(W.T.buy(1, GUN, 3)))
    T.eq(1, count(W.C1.bag, GUN)); T.eq(1000 - PRICE, W.C1.money)
end)

case('buy: delivery unknown (transfer AND snapshot fail) -> no refund, stash kept, flagged', function()
    local W = world()
    W.hooks.charge = function() W.fail.transferAll = 'fh_inventory_down'; W.fail.snapshotStash = true end
    T.same({ false, 'delivery_unknown', n = 2 }, table.pack(W.T.buy(1, GUN, 3)))
    T.eq(1000 - 3 * PRICE, W.C1.money); T.eq(3, count(W.stash(), GUN)); T.eq(0, #W.refunds)
    assert(logged(W, 'WARNING buy delivery unknown'))
    W.fail.transferAll, W.fail.snapshotStash = nil, nil
    T.same({ false, 'fence_pending', n = 2 }, table.pack(W.T.buy(1, GUN, 1))) -- not swept: those were paid for
end)

case('buy: partial delivery and clear fails -> no refund (no free items), owed amount logged', function()
    local W = world()
    W.hooks.charge = function() W.C1.room = 1; W.fail.clear = 'fh_inventory_down' end
    T.same({ false, 'delivery_incomplete', n = 2 }, table.pack(W.T.buy(1, GUN, 3)))
    T.eq(1, count(W.C1.bag, GUN)); T.eq(2, count(W.stash(), GUN)); T.eq(1000 - 3 * PRICE, W.C1.money)
    T.eq(0, #W.refunds); assert(logged(W, 'refund owed'))
    W.fail.clear = nil
    T.same({ false, 'fence_pending', n = 2 }, table.pack(W.T.buy(1, GUN, 1)))
end)

case('buy: refund pay fails -> logged as owed, reported refund 0', function()
    local W = world()
    W.hooks.charge = function() W.C1.room = 1 end
    W.fail.pay = { reason = 'fence_refund', err = 'ledger_failed' }
    T.same({ true, 1, 0, n = 3 }, table.pack(W.T.buy(1, GUN, 3)))
    T.eq(0, size(W.stash())); assert(logged(W, 'REFUND FAILED, refund owed'))
end)

-- ---------------------------------------------------------------- sell rollback

case('sell: goods -> stash -> pay -> clear', function()
    local W = world({ players = { C1 = { bag = { [1] = { name = GUN, amount = 3 }, [2] = { name = 'bread', amount = 1 } } } } })
    T.same({ true, 2, 2 * SELL, n = 3 }, table.pack(W.T.sell(1, GUN, 2)))
    T.eq(1, count(W.C1.bag, GUN)); T.eq(1, count(W.C1.bag, 'bread')); T.eq(1000 + 2 * SELL, W.C1.money)
    T.eq(0, size(W.stash()))
end)

case('sell: pay fails -> goods given back, no money', function()
    local W = world({ players = { C1 = { bag = { [1] = { name = GUN, amount = 3 } } } } })
    W.fail.pay = { reason = 'fence_sell', err = 'ledger_failed' }
    T.same({ false, 'ledger_failed', n = 2 }, table.pack(W.T.sell(1, GUN, 2)))
    T.eq(3, count(W.C1.bag, GUN)); T.eq(1000, W.C1.money); T.eq(0, size(W.stash()))
    assert(logged(W, 'item given back'))
end)

case('sell: pay AND restore fail -> goods kept in the stash for an admin, next trade refused', function()
    local W = world({ players = { C1 = { bag = { [1] = { name = GUN, amount = 3 } } } } })
    W.fail.pay = { reason = 'fence_sell', err = 'ledger_failed' }
    W.hooks.pay = function() W.fail.transferAll = 'fh_inventory_down' end
    T.same({ false, 'ledger_failed', n = 2 }, table.pack(W.T.sell(1, GUN, 2)))
    T.eq(1, count(W.C1.bag, GUN)); T.eq(2, count(W.stash(), GUN)); T.eq(1000, W.C1.money)
    assert(logged(W, 'WARNING sell'))
    W.fail.transferAll, W.fail.pay = nil, nil
    T.same({ false, 'fence_pending', n = 2 }, table.pack(W.T.sell(1, GUN, 1)))
    T.eq(2, count(W.stash(), GUN)) -- not swept: they are still the player's
end)

case('sell: paid but clear fails -> sold goods swept by the next trade', function()
    local W = world({ players = { C1 = { bag = { [1] = { name = GUN, amount = 3 } } } } })
    W.hooks.pay = function() W.fail.clear = 'fh_inventory_down' end
    T.same({ true, 2, 2 * SELL, n = 3 }, table.pack(W.T.sell(1, GUN, 2)))
    W.hooks.pay, W.fail.clear = nil, nil
    T.same({ true, 1, SELL, n = 3 }, table.pack(W.T.sell(1, GUN, 1)))
    T.eq(0, count(W.C1.bag, GUN)); T.eq(1000 + 3 * SELL, W.C1.money); T.eq(0, size(W.stash()))
end)

case('sell: backpack slot reused by another item mid-sell -> aborted, everything given back, no pay', function()
    local W = world({ players = { C1 = { bag = { [1] = { name = GUN, amount = 1 }, [2] = { name = GUN, amount = 1 } } } } })
    W.hooks.move = function(_, n) if n == 2 then W.C1.bag[2] = { name = 'bread', amount = 1 } end end
    T.same({ false, 'inventory_changed', n = 2 }, table.pack(W.T.sell(1, GUN, 2)))
    T.eq(1, count(W.C1.bag, GUN)); T.eq(1, count(W.C1.bag, 'bread')); T.eq(1000, W.C1.money)
    T.eq(nil, W.calls.pay); T.eq(0, size(W.stash()))
end)

case('sell: nothing to sell -> not_enough_items, nothing moved, lock free', function()
    local W = world()
    T.same({ false, 'not_enough_items', n = 2 }, table.pack(W.T.sell(1, GUN, 2)))
    T.eq(nil, W.calls.pay); T.eq(0, size(W.stash())); assert(not W.T.locks.held('C1'))
end)

case('sell: no_player when the citizen is unknown; nothing locked', function()
    local W = world()
    T.same({ false, 'no_player', n = 2 }, table.pack(W.T.sell(99, GUN, 1)))
    T.same({ false, 'no_player', n = 2 }, table.pack(W.T.buy(99, GUN, 1)))
end)

T.finish()

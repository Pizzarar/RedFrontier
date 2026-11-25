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
        for s, it in pairs(box) do
            if it.name == name then it.amount = it.amount + amount; return s end
        end
    end
    for s = 1, SLOTS do
        if not box[s] then box[s] = { name = name, amount = amount, info = info }; return s end
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
        currentStop = function() step('currentStop'); return cfg.stops.heartlands_road end,
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
        removeItem = function(ref, name, qty) -- fh_core B7: exactly qty or nothing (fh_not_enough)
            step('removeItem')
            if W.fail.removeItem then return false, W.fail.removeItem end
            local b = box(ref)
            if count(b, name) < qty then return false, 'fh_not_enough' end
            local slots = {}
            for s in pairs(b) do slots[#slots + 1] = s end
            table.sort(slots)
            for _, s in ipairs(slots) do
                local it = b[s]
                if qty > 0 and it.name == name then
                    local n = math.min(qty, it.amount)
                    it.amount, qty = it.amount - n, qty - n
                    if it.amount == 0 then b[s] = nil end
                end
            end
            return true
        end,
        transferAll = function(from, to)
            step('transferAll')
            if W.fail.transferAll then return false, W.fail.transferAll end
            local src, dst, moved, leftovers = box(from), box(to), {}, {}
            local slots = {}
            for s in pairs(src) do slots[#slots + 1] = s end
            table.sort(slots)
            for _, s in ipairs(slots) do
                local it = src[s]
                local n = it.amount
                if to.type == 'backpack' then n = math.min(n, P(to.id).room) end
                if n > 0 then -- plan steps like fh_inventory's: name, amount, fromSlot, toSlot
                    local toSlot = put(dst, it.name, n, it.info)
                    if to.type == 'backpack' then P(to.id).room = P(to.id).room - n end
                    it.amount = it.amount - n
                    if it.amount == 0 then src[s] = nil end
                    moved[#moved + 1] = { name = it.name, amount = n, fromSlot = s, toSlot = toSlot }
                end
                if it.amount > 0 then leftovers[#leftovers + 1] = { slot = s, name = it.name, amount = it.amount } end
            end
            return true, moved, leftovers
        end,
        move = function(from, to, fromSlot, toSlot, amount) -- name-agnostic, like the real one
            step('move')
            local s, d = box(from)[fromSlot], box(to)
            if not s or s.amount < amount then return false, 'fh_no_item' end
            if d[toSlot] and d[toSlot].name ~= s.name then return false, 'fh_slot_taken' end
            if d[toSlot] then d[toSlot].amount = d[toSlot].amount + amount
            else d[toSlot] = { name = s.name, amount = amount, info = s.info } end
            s.amount = s.amount - amount
            if s.amount == 0 then box(from)[fromSlot] = nil end
            if from.type == 'backpack' then P(from.id).room = P(from.id).room + amount end
            if to.type == 'backpack' then P(to.id).room = P(to.id).room - amount end
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

---Resume until the trade yields at dep `name` (before that dep acts). The lock is taken on the first resume.
local function runUntil(co, name)
    while true do
        local ok, y = coroutine.resume(co)
        if not ok then error(y) end
        if coroutine.status(co) == 'dead' then error('trade finished before reaching ' .. name) end
        if y == name then return end
    end
end

local function start(fn, name)
    local co = coroutine.create(fn)
    runUntil(co, name)
    return co
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

-- ---------------------------------------------------------------- reclaim (re-review finding 1, late-write residual)
-- A hangs >= lockStaleSeconds. Before its first side effect B may reclaim the lock, and A then changes nothing. Once A
-- has staged / moved / charged / paid (locks.write), the lock is pinned: B is fence_busy until A lands and finishes.

case('reclaim: stale SELL resumes after B staged a buy -> A hands out nothing (no restore of B\'s stage)', function()
    local W = world({ players = { C1 = { bag = { [1] = { name = GUN, amount = 2 } } } } })
    local a = start(function() return W.T.sell(1, GUN, 2) end, 'view') -- A read the backpack, about to move
    W.clock = cfg.lockStaleSeconds
    local b = start(function() return W.T.buy(2, GUN, 3) end, 'charge') -- B reclaimed, staged 3, about to charge
    T.eq(3, count(W.stash(), GUN))
    T.same({ false, 'fence_busy', n = 2 }, drain(a))
    T.eq(3, count(W.stash(), GUN)); T.eq(2, count(W.C1.bag, GUN)) -- B's unpaid stage untouched, A's goods kept
    T.eq(nil, W.calls.transferAll); T.eq(nil, W.calls.clear); T.eq(nil, W.calls.move)
    T.same({ true, 3, 0, n = 3 }, drain(b))
    T.eq(5, count(W.C1.bag, GUN)); T.eq(1000 - 3 * PRICE, W.C1.money); T.eq(0, size(W.stash()))
end)

---A is parked inside the side-effecting dep it yielded in (effect not done yet) far past lockStaleSeconds. Its lock is
---pinned: B's buy and sell and an admin settle (same citizen, src 2) are all fence_busy and make no dep call at all.
local function othersRefused(W)
    W.clock = W.clock + 10 * cfg.lockStaleSeconds
    local before = copy(W.calls)
    T.same({ false, 'fence_busy', n = 2 }, table.pack(W.T.buy(2, GUN, 1)))
    T.same({ false, 'fence_busy', n = 2 }, table.pack(W.T.sell(2, GUN, 1)))
    T.same({ false, 'fence_busy', n = 2 }, table.pack(W.T.settle(2)))
    T.same(before, W.calls)
    local n = 0
    for _, l in ipairs(W.logs) do if l:find('stale trade lock kept', 1, true) then n = n + 1 end end
    T.eq(1, n) -- one WARNING per pinned token, not one per refused attempt
    assert(not logged(W, 'reclaimed a stale trade lock'))
end

case('pinned: A\'s stage lands after lockStaleSeconds -> no reclaim, B busy; A completes, charged once', function()
    local W = world()
    local a = start(function() return W.T.buy(1, GUN, 2) end, 'addItem') -- A passed begin, stage in flight
    othersRefused(W)
    T.same({ true, 2, 0, n = 3 }, drain(a)) -- old code: B reclaimed, A's late stage landed in B's stash
    T.eq(2, count(W.C1.bag, GUN)); T.eq(1000 - 2 * PRICE, W.C1.money); T.eq(0, size(W.stash()))
    assert(not W.T.locks.held('C1'))
    T.same({ true, 1, 0, n = 3 }, table.pack(W.T.buy(2, GUN, 1))) -- the lock is free again
end)

case('pinned: A\'s charge lands after lockStaleSeconds -> B busy; A delivers, nothing left for settle', function()
    local W = world()
    local a = start(function() return W.T.buy(1, GUN, 2) end, 'charge') -- A staged 2, charge in flight
    othersRefused(W)
    T.same({ true, 2, 0, n = 3 }, drain(a)) -- old code: paid, then left undelivered for an admin
    T.eq(2, count(W.C1.bag, GUN)); T.eq(1000 - 2 * PRICE, W.C1.money); T.eq(0, size(W.stash())); T.eq(0, #W.refunds)
    T.same({ false, 'nothing_pending', n = 2 }, table.pack(W.T.settle(1)))
end)

case('pinned: A\'s charge is refused after lockStaleSeconds -> A discards its own stage; settle has nothing to hand out', function()
    local W = world()
    local a = start(function() return W.T.buy(1, GUN, 2) end, 'charge')
    othersRefused(W)
    W.fail.charge = 'fh_charge_busy'
    T.same({ false, 'fh_charge_busy', n = 2 }, drain(a))
    W.fail.charge = nil
    -- old code: the unpaid stage stayed pinned and settle would have given it to the player for free
    T.eq(0, size(W.stash())); T.eq(1000, W.C1.money); T.eq(0, count(W.C1.bag, GUN)); T.eq(1, W.calls.clear)
    T.same({ false, 'nothing_pending', n = 2 }, table.pack(W.T.settle(1)))
end)

case('pinned: A\'s sell pay lands after lockStaleSeconds -> A removes the sold goods; settle cannot give them back', function()
    local W = world({ players = { C1 = { bag = { [1] = { name = GUN, amount = 2 } } } } })
    local a = start(function() return W.T.sell(1, GUN, 2) end, 'pay') -- goods in stash, pay in flight
    othersRefused(W)
    T.same({ true, 2, 2 * SELL, n = 3 }, drain(a))
    -- old code: sold goods left pinned, settle would have handed them back to a player who was paid (dupe)
    T.eq(1, W.calls.removeItem); T.eq(0, size(W.stash())); T.eq(0, count(W.C1.bag, GUN))
    T.eq(1000 + 2 * SELL, W.C1.money)
    T.same({ false, 'nothing_pending', n = 2 }, table.pack(W.T.settle(1)))
end)

case('pinned: A\'s partial delivery lands after lockStaleSeconds -> A removes and refunds only the undelivered', function()
    local W = world()
    W.hooks.charge = function() W.C1.room = 1 end
    local a = start(function() return W.T.buy(1, GUN, 3) end, 'transferAll') -- paid, delivery in flight
    othersRefused(W)
    T.same({ true, 1, 2 * PRICE, n = 3 }, drain(a))
    T.eq(1, count(W.C1.bag, GUN)); T.eq(0, size(W.stash())); T.eq(1000 - PRICE, W.C1.money)
    T.same({ 2 * PRICE }, W.refunds)
end)

case('pinned: A\'s sell pay fails after lockStaleSeconds -> A gives its goods back; nothing pending', function()
    local W = world({ players = { C1 = { bag = { [1] = { name = GUN, amount = 2 } } } } })
    local a = start(function() return W.T.sell(1, GUN, 2) end, 'pay')
    othersRefused(W)
    W.fail.pay = { reason = 'fence_sell', err = 'ledger_failed' }
    T.same({ false, 'ledger_failed', n = 2 }, drain(a))
    W.fail.pay = nil
    T.eq(2, count(W.C1.bag, GUN)); T.eq(0, size(W.stash())); T.eq(1000, W.C1.money)
    assert(logged(W, 'item given back'))
end)

-- ---------------------------------------------------------------- sweep flag (re-review finding 2)

case('sweep flag does not outlive an emptied stash: later player goods are never swept', function()
    local W = world({ players = { C1 = { bag = { [1] = { name = GUN, amount = 3 } } } } })
    W.hooks.pay = function() W.fail.removeItem = 'fh_inventory_down' end
    T.same({ true, 1, SELL, n = 3 }, table.pack(W.T.sell(1, GUN, 1))) -- removal failed: sold goods flagged sweepable
    W.hooks.pay, W.fail.removeItem = nil, nil
    W.stashes[STASH] = {} -- emptied elsewhere (admin / fh_inventory restart)
    T.same({ true, 1, 0, n = 3 }, table.pack(W.T.buy(1, GUN, 1))) -- begin sees it empty: flag dropped
    W.fail.pay = { reason = 'fence_sell', err = 'ledger_failed' }
    W.hooks.pay = function() W.fail.transferAll = 'fh_inventory_down' end
    T.same({ false, 'ledger_failed', n = 2 }, table.pack(W.T.sell(1, GUN, 2))) -- player goods stuck in stash
    W.fail.pay, W.hooks.pay, W.fail.transferAll = nil, nil, nil
    T.same({ false, 'fence_pending', n = 2 }, table.pack(W.T.sell(1, GUN, 1)))
    T.eq(2, count(W.stash(), GUN)) -- not wiped
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
    for _, err in ipairs({ 'fh_insufficient_funds', 'fh_charge_busy', 'ledger_failed', 'removemoney_refused',
        'no_player', 'player_changed', 'charge_unavailable', 'amount_too_large' }) do
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

case('buy: fh_charge_busy fails fast, the retry is charged exactly once', function()
    local W = world()
    W.fail.charge = 'fh_charge_busy'
    T.same({ false, 'fh_charge_busy', n = 2 }, table.pack(W.T.buy(1, GUN, 2)))
    T.eq(1, W.calls.charge); T.eq(1000, W.C1.money); T.eq(0, size(W.stash())); assert(not W.T.locks.held('C1'))
    W.fail.charge = nil
    T.same({ true, 2, 0, n = 3 }, table.pack(W.T.buy(1, GUN, 2))) -- the player's retry
    T.eq(2, W.calls.charge); T.eq(1000 - 2 * PRICE, W.C1.money); T.eq(2, count(W.C1.bag, GUN))
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
    T.eq(1, W.calls.removeItem); T.eq(nil, W.calls.clear) -- exactly the undelivered units, no wipe
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

case('buy: partial delivery and removeItem fails -> no refund (no free items), owed amount logged', function()
    local W = world()
    W.hooks.charge = function() W.C1.room = 1; W.fail.removeItem = 'fh_inventory_down' end
    T.same({ false, 'delivery_incomplete', n = 2 }, table.pack(W.T.buy(1, GUN, 3)))
    T.eq(1, count(W.C1.bag, GUN)); T.eq(2, count(W.stash(), GUN)); T.eq(1000 - 3 * PRICE, W.C1.money)
    T.eq(0, #W.refunds); assert(logged(W, 'refund owed'))
    -- next trade: give the backpack room again so it reaches the stash check (canFit runs first)
    W.hooks.charge, W.fail.removeItem, W.C1.room = nil, nil, 10
    T.same({ false, 'fence_pending', n = 2 }, table.pack(W.T.buy(1, GUN, 1)))
    T.eq(2, count(W.stash(), GUN)); T.eq(1, count(W.C1.bag, GUN)); T.eq(1000 - 3 * PRICE, W.C1.money)
end)

case('buy: stash holds fewer than the undelivered count -> removeItem fh_not_enough removes nothing, no refund', function()
    local W = world()
    -- stash unreadable after delivery: moved list says 1 of 3 delivered -> 2 undelivered; one unit vanishes from the
    -- stash before the removal, so all-or-nothing removeItem takes none and nothing is refunded
    W.hooks.charge = function() W.C1.room = 1; W.fail.snapshotStash = true end
    W.hooks.removeItem = function() local b = W.stash(); for _, it in pairs(b) do it.amount = it.amount - 1 end end
    T.same({ false, 'delivery_incomplete', n = 2 }, table.pack(W.T.buy(1, GUN, 3)))
    T.eq(0, #W.refunds); T.eq(1000 - 3 * PRICE, W.C1.money); T.eq(1, count(W.stash(), GUN)) -- nothing removed
    assert(logged(W, 'fh_not_enough'))
end)

case('buy: refund pay fails -> logged as owed, reported refund 0', function()
    local W = world()
    W.hooks.charge = function() W.C1.room = 1 end
    W.fail.pay = { reason = 'fence_refund', err = 'ledger_failed' }
    T.same({ true, 1, 0, n = 3 }, table.pack(W.T.buy(1, GUN, 3)))
    T.eq(0, size(W.stash())); assert(logged(W, 'REFUND FAILED, refund owed'))
end)

-- ---------------------------------------------------------------- sell rollback

case('sell: goods -> stash -> pay -> removeItem(sold)', function()
    local W = world({ players = { C1 = { bag = { [1] = { name = GUN, amount = 3 }, [2] = { name = 'bread', amount = 1 } } } } })
    T.same({ true, 2, 2 * SELL, n = 3 }, table.pack(W.T.sell(1, GUN, 2)))
    T.eq(1, count(W.C1.bag, GUN)); T.eq(1, count(W.C1.bag, 'bread')); T.eq(1000 + 2 * SELL, W.C1.money)
    T.eq(0, size(W.stash())); T.eq(1, W.calls.removeItem); T.eq(nil, W.calls.clear)
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

case('sell: paid but removeItem fails -> sold goods swept by the next trade, paid once', function()
    local W = world({ players = { C1 = { bag = { [1] = { name = GUN, amount = 3 } } } } })
    W.hooks.pay = function() W.fail.removeItem = 'fh_not_enough' end
    T.same({ true, 2, 2 * SELL, n = 3 }, table.pack(W.T.sell(1, GUN, 2)))
    T.eq(2, count(W.stash(), GUN)); assert(logged(W, 'retried on the next trade'))
    W.hooks.pay, W.fail.removeItem = nil, nil
    T.same({ true, 1, SELL, n = 3 }, table.pack(W.T.sell(1, GUN, 1)))
    T.eq(0, count(W.C1.bag, GUN)); T.eq(1000 + 3 * SELL, W.C1.money); T.eq(0, size(W.stash()))
end)

case('sell: removeItem lands after lockStaleSeconds and fails -> lock was pinned, sold goods swept, never handed back', function()
    local W = world({ players = { C1 = { bag = { [1] = { name = GUN, amount = 2 } } } } })
    local a = start(function() return W.T.sell(1, GUN, 2) end, 'removeItem') -- paid, removal in flight
    othersRefused(W)
    W.fail.removeItem = 'fh_inventory_down'
    T.same({ true, 2, 2 * SELL, n = 3 }, drain(a))
    W.fail.removeItem = nil
    assert(logged(W, 'retried on the next trade')) -- A still owned the stash: the fence's goods are flagged
    T.same({ true, 0, 'swept', n = 3 }, table.pack(W.T.settle(1)))
    T.eq(0, size(W.stash())); T.eq(0, count(W.C1.bag, GUN)); T.eq(1000 + 2 * SELL, W.C1.money)
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

-- ---------------------------------------------------------------- admin settle (fh_fence_settle)

---Leaves C1's stash fence_pending the way production does: partial delivery whose removal failed (2 paid units).
local function pendingWorld()
    local W = world()
    W.hooks.charge = function() W.C1.room = 1; W.fail.removeItem = 'fh_inventory_down' end
    T.same({ false, 'delivery_incomplete', n = 2 }, table.pack(W.T.buy(1, GUN, 3)))
    W.hooks.charge, W.fail.removeItem, W.C1.room = nil, nil, 10
    T.same({ false, 'fence_pending', n = 2 }, table.pack(W.T.buy(1, GUN, 1)))
    W.calls = {}
    return W
end

case('settle: success -> pending goods to the player, stash empty, trading works again', function()
    local W = pendingWorld()
    T.same({ true, 2, 'delivered', n = 3 }, table.pack(W.T.settle(1)))
    T.eq(3, count(W.C1.bag, GUN)); T.eq(0, size(W.stash())); T.eq(1000 - 3 * PRICE, W.C1.money)
    T.eq(nil, W.calls.charge); T.eq(nil, W.calls.pay); assert(not W.T.locks.held('C1'))
    assert(logged(W, 'settle: citizenid=C1'))
    T.same({ true, 1, 0, n = 3 }, table.pack(W.T.buy(1, GUN, 1))) -- no longer fence_pending
    T.same({ false, 'nothing_pending', n = 2 }, table.pack(W.T.settle(1)))
end)

case('settle: no room -> refused, nothing moves (pre-check)', function()
    local W = pendingWorld()
    W.C1.room = 1
    T.same({ false, 'no_room', n = 2 }, table.pack(W.T.settle(1)))
    T.eq(2, count(W.stash(), GUN)); T.eq(1, count(W.C1.bag, GUN)); T.eq(nil, W.calls.transferAll)
    assert(not W.T.locks.held('C1'))
    W.C1.room = 10
    T.same({ false, 'fence_pending', n = 2 }, table.pack(W.T.buy(1, GUN, 1))) -- still pending, untouched
end)

case('settle: room vanishes during the transfer -> moved units put back, nothing changed', function()
    local W = pendingWorld()
    W.stashes[STASH] = { [1] = { name = GUN, amount = 1 }, [2] = { name = 'bread', amount = 2 } }
    W.hooks.transferAll = function() W.C1.room = 1 end -- after the pre-check: only the first unit fits
    T.same({ false, 'no_room', n = 2 }, table.pack(W.T.settle(1)))
    T.eq(1, count(W.stash(), GUN)); T.eq(2, count(W.stash(), 'bread'))
    T.eq(1, count(W.C1.bag, GUN)); T.eq(0, count(W.C1.bag, 'bread')) -- the bag is as before the settle
    T.eq(1, W.calls.move)
end)

case('settle: a reclaim attempt during the rollback is refused (pinned) -> every moved step is put back', function()
    local W = world({ stash = { [1] = { name = GUN, amount = 1 }, [2] = { name = 'bread', amount = 1 },
        [3] = { name = 'water', amount = 2 } } })
    W.hooks.transferAll = function() W.C1.room = 2 end -- 2 steps move (GUN, bread), water is left: rollback of 2 steps
    W.hooks.move = function(_, n)
        if n == 1 then W.clock = cfg.lockStaleSeconds; T.eq(nil, W.T.locks.acquire('C1', 9)) end
    end
    T.same({ false, 'no_room', n = 2 }, table.pack(W.T.settle(1)))
    T.eq(2, W.calls.move) -- old code: reclaimed after the first move, goods left split between stash and backpack
    T.eq(1, count(W.stash(), GUN)); T.eq(1, count(W.stash(), 'bread')); T.eq(2, count(W.stash(), 'water'))
    T.eq(0, count(W.C1.bag, GUN)); T.eq(0, count(W.C1.bag, 'bread'))
    assert(logged(W, 'stale trade lock kept')); assert(not W.T.locks.held('C1'))
end)

case('settle: busy lock -> fence_busy, nothing moves; works once the trade is done', function()
    local W = pendingWorld()
    W.stashes[STASH] = {}
    local a = start(function() return W.T.buy(1, GUN, 2) end, 'charge') -- a trade holds C1's lock
    T.same({ false, 'fence_busy', n = 2 }, table.pack(W.T.settle(2))) -- same citizen, other src
    T.eq(nil, W.calls.transferAll); T.eq(2, count(W.stash(), GUN))
    T.same({ true, 2, 0, n = 3 }, drain(a))
    W.stashes[STASH] = { [1] = { name = GUN, amount = 1 } }
    T.same({ true, 1, 'delivered', n = 3 }, table.pack(W.T.settle(1)))
end)

case('settle: a settle in flight holds the lock -> a trade is fence_busy', function()
    local W = pendingWorld()
    local a = start(function() return W.T.settle(1) end, 'transferAll')
    T.same({ false, 'fence_busy', n = 2 }, table.pack(W.T.buy(2, GUN, 1)))
    T.same({ true, 2, 'delivered', n = 3 }, drain(a))
end)

case('settle: fence-owned leftovers (sweep flag) are swept, never given to the player', function()
    local W = world()
    W.fail.charge, W.fail.clear = 'fh_charge_busy', 'fh_inventory_down'
    T.same({ false, 'fh_charge_busy', n = 2 }, table.pack(W.T.buy(1, GUN, 2))) -- unpaid stage left, sweepable
    W.fail.charge, W.fail.clear = nil, nil
    T.same({ true, 0, 'swept', n = 3 }, table.pack(W.T.settle(1)))
    T.eq(0, count(W.C1.bag, GUN)); T.eq(0, size(W.stash())); T.eq(1000, W.C1.money)
end)

case('settle: unknown player -> no_player, nothing locked', function()
    local W = pendingWorld()
    T.same({ false, 'no_player', n = 2 }, table.pack(W.T.settle(99)))
    T.eq(2, count(W.stash(), GUN))
end)

case('sell: no_player when the citizen is unknown; nothing locked', function()
    local W = world()
    T.same({ false, 'no_player', n = 2 }, table.pack(W.T.sell(99, GUN, 1)))
    T.same({ false, 'no_player', n = 2 }, table.pack(W.T.buy(99, GUN, 1)))
end)

-- ---------------------------------------------------------------- late write (trade.lua invariant 1, pinned lock)
-- The residual this closes: a trade's lock reclaimed while one of its fh_core calls is still in flight, the newer
-- trade uses the stash, then the old call lands in it. Now a lock is reclaimable only before its trade's first side
-- effect, so the only call that can land late is a read, and the old trade then changes nothing.

local function untouchedC2(W)
    T.eq(1000, W.players.C2.money); T.eq(0, size(W.players.C2.bag))
end

case('late write: reclaimed during a read, newer trade stages + finishes, old read lands -> old trade changes nothing', function()
    local W = world()
    local a = start(function() return W.T.buy(1, GUN, 2) end, 'snapshot') -- A in begin: reads the (empty) stash
    W.clock = cfg.lockStaleSeconds
    local b = start(function() return W.T.buy(2, GUN, 1) end, 'charge') -- B reclaimed, staged 1, about to charge
    assert(logged(W, 'reclaimed a stale trade lock'))
    T.same({ false, 'fence_busy', n = 2 }, drain(a)) -- A's stale "empty" read lands: A stops, stages nothing
    T.eq(1, W.calls.addItem); T.eq(1, count(W.stash(), GUN)); T.eq(nil, W.calls.clear) -- B's stage only, untouched
    T.same({ true, 1, 0, n = 3 }, drain(b))
    T.eq(1, count(W.C1.bag, GUN)); T.eq(1000 - PRICE, W.C1.money); T.eq(0, size(W.stash())); T.eq(1, W.calls.charge)
    untouchedC2(W)
    T.same({ false, 'nothing_pending', n = 2 }, table.pack(W.T.settle(1)))
end)

case('late write: every stash write kind lands after lockStaleSeconds -> pinned, others busy, A finishes its own rules', function()
    local scenarios = {
        { 'buy stage discard (clear) after a refused charge', 'clear', function(W)
            W.hooks.charge = function() W.fail.charge = 'fh_charge_busy' end
            return function() return W.T.buy(1, GUN, 2) end
        end, { false, 'fh_charge_busy', n = 2 }, function(W)
            T.eq(0, count(W.C1.bag, GUN)); T.eq(1000, W.C1.money)
        end },
        { 'begin sweep (clear) of fence-owned leftovers', 'clear', function(W)
            W.fail.charge, W.fail.clear = 'fh_charge_busy', 'fh_inventory_down'
            T.same({ false, 'fh_charge_busy', n = 2 }, table.pack(W.T.buy(1, GUN, 2))) -- unpaid stage, sweepable
            W.fail.charge, W.fail.clear, W.calls = nil, nil, {}
            return function() return W.T.buy(1, GUN, 1) end
        end, { true, 1, 0, n = 3 }, function(W)
            T.eq(1, count(W.C1.bag, GUN)); T.eq(1000 - PRICE, W.C1.money)
        end },
        { 'sell goods -> stash (move)', 'move', function(W)
            W.C1.bag = { [1] = { name = GUN, amount = 2 } }
            return function() return W.T.sell(1, GUN, 2) end
        end, { true, 2, 2 * SELL, n = 3 }, function(W)
            T.eq(0, count(W.C1.bag, GUN)); T.eq(1000 + 2 * SELL, W.C1.money)
        end },
        { 'buy partial removal (removeItem)', 'removeItem', function(W)
            W.hooks.charge = function() W.C1.room = 1 end
            return function() return W.T.buy(1, GUN, 3) end
        end, { true, 1, 2 * PRICE, n = 3 }, function(W)
            T.eq(1, count(W.C1.bag, GUN)); T.eq(1000 - PRICE, W.C1.money); T.same({ 2 * PRICE }, W.refunds)
        end },
        { 'settle hand-over (transferAll)', 'transferAll', function(W)
            W.stashes[STASH] = { [1] = { name = GUN, amount = 2 } }
            return function() return W.T.settle(1) end
        end, { true, 2, 'delivered', n = 3 }, function(W)
            T.eq(2, count(W.C1.bag, GUN)); T.eq(1000, W.C1.money)
        end },
    }
    for _, s in ipairs(scenarios) do
        local name, at, setup, want, check = s[1], s[2], s[3], s[4], s[5]
        local W = world()
        local a = start(setup(W), at)
        othersRefused(W)
        T.same(want, drain(a), name)
        T.eq(0, size(W.stash()), name); check(W); untouchedC2(W)
        assert(not W.T.locks.held('C1'), name)
    end
end)

case('late write: a late removal that FAILS leaves paid goods fence_pending; settle gives them to the payer', function()
    local W = world()
    W.hooks.charge = function() W.C1.room = 1 end
    local a = start(function() return W.T.buy(1, GUN, 3) end, 'removeItem') -- 1 delivered, removal of 2 in flight
    othersRefused(W)
    W.fail.removeItem = 'fh_inventory_down'
    T.same({ false, 'delivery_incomplete', n = 2 }, drain(a))
    W.hooks.charge, W.fail.removeItem, W.C1.room = nil, nil, 10
    T.eq(0, #W.refunds); assert(logged(W, 'refund owed'))
    T.same({ false, 'fence_pending', n = 2 }, table.pack(W.T.buy(2, GUN, 1))) -- reported, not mixed or swept
    T.eq(2, count(W.stash(), GUN))
    T.same({ true, 2, 'delivered', n = 3 }, table.pack(W.T.settle(2)))
    T.eq(3, count(W.C1.bag, GUN)); T.eq(1000 - 3 * PRICE, W.C1.money); T.eq(0, size(W.stash())) -- paid 3, holds 3
    untouchedC2(W)
end)

case('late write: a pinned trade that never returns keeps that citizen busy (documented cost); others trade', function()
    local W = world()
    local a = start(function() return W.T.buy(1, GUN, 2) end, 'transferAll') -- paid, delivery never returns
    W.clock = 1000 * cfg.lockStaleSeconds
    T.same({ false, 'fence_busy', n = 2 }, table.pack(W.T.buy(2, GUN, 1)))
    T.same({ false, 'fence_busy', n = 2 }, table.pack(W.T.settle(2)))
    assert(W.T.locks.held('C1')); T.eq(2, count(W.stash(), GUN)) -- A's paid goods stay with A's trade
    T.same({ true, 1, 0, n = 3 }, table.pack(W.T.buy(3, GUN, 1))) -- another citizen is not affected
    T.eq(coroutine.status(a), 'suspended')
end)

case('reclaim: unpinned SELL resumes after B flagged its own leftovers for sweep -> A leaves the flag; settle sweeps', function()
    -- (Gemini Prg23 HIGH) A's not-owned path used to clear B's sweep flag, so settle handed B's fence-owned goods out.
    local variants = {
        { 'B buy: charge refused, clear fails (unpaid stage)', function(W)
            W.fail.charge, W.fail.clear = 'fh_charge_busy', 'fh_inventory_down'
            T.same({ false, 'fh_charge_busy', n = 2 }, table.pack(W.T.buy(2, GUN, 3)))
            W.fail.charge, W.fail.clear = nil, nil
            return 1000 -- nothing charged
        end },
        { 'B sell: paid, removeItem fails (sold goods)', function(W)
            W.hooks.pay = function() W.fail.removeItem = 'fh_inventory_down' end
            T.same({ true, 3, 3 * SELL, n = 3 }, table.pack(W.T.sell(2, GUN, 3)))
            W.hooks.pay, W.fail.removeItem = nil, nil
            return 1000 + 3 * SELL -- paid once for the 3 the fence now owns
        end },
    }
    for _, v in ipairs(variants) do
        local name, runB = v[1], v[2]
        local W = world({ players = { C1 = { bag = { [1] = { name = GUN, amount = 5 } } } } })
        local a = start(function() return W.T.sell(1, GUN, 2) end, 'view') -- A read the backpack, nothing moved
        W.clock = cfg.lockStaleSeconds
        local money = runB(W) -- B reclaims; its fence-owned leftovers stay flagged for sweep
        local bag, moves = count(W.C1.bag, GUN), W.calls.move
        T.eq(3, count(W.stash(), GUN), name)
        T.same({ false, 'fence_busy', n = 2 }, drain(a), name)
        T.eq(moves, W.calls.move, name) -- A moved nothing
        T.same({ true, 0, 'swept', n = 3 }, table.pack(W.T.settle(1)), name) -- old code: 'delivered' (dupe)
        T.eq(bag, count(W.C1.bag, GUN), name); T.eq(money, W.C1.money, name); T.eq(0, size(W.stash()), name)
        T.eq(0, size(W.players.C2.bag), name); T.eq(1000, W.players.C2.money, name)
    end
end)

-- ---------------------------------------------------------------- G2b: lead item info holds no coords

---Every number anywhere in a value (keys included).
local function numbers(v, out)
    out = out or {}
    if type(v) == 'table' then for k, x in pairs(v) do numbers(k, out); numbers(x, out) end
    elseif type(v) == 'number' then out[#out + 1] = v end
    return out
end

case('lead buy: the item info written at purchase is { lead = <spot id> } only: no coords, no hint', function()
    assert(loadfile(fence .. 'server/config_leads.lua'))()
    local spots = FhFenceLeadSpots
    local id = cfg.stock.heartlands_road.leads[1].lead
    local W = world()
    local infos = {}
    local realAdd = W.deps.addItem
    W.deps.addItem = function(ref, name, qty, info)
        if name == 'fh_treasure_lead' then infos[#infos + 1] = copy(info) end
        return realAdd(ref, name, qty, info)
    end
    W.T = trade.new(cfg, logic, W.deps)
    T.same({ true, 1, 0, n = 3 }, table.pack(W.T.buy(1, 'fh_treasure_lead', 1)))
    T.same({ { lead = id } }, infos) -- what trade.lua staged (logic.leadInfo)
    local held
    for _, it in pairs(W.C1.bag) do if it.name == 'fh_treasure_lead' then held = it end end
    T.same({ lead = id }, assert(held, 'lead delivered').info)
    T.same({}, numbers(held.info))
    T.eq(nil, held.info.target); T.eq(nil, held.info.hint)
    assert(spots[id] and spots[id].coords, 'the id resolves only in the server-only spot table')
    T.eq(1000 - 250, W.C1.money); T.eq(0, size(W.stash()))
end)

case('menu stock: a lead row carries only its spot id; an id missing from the spot table is not listed', function()
    assert(loadfile(fence .. 'server/config_leads.lua'))()
    local spots = FhFenceLeadSpots
    local leadsLogic = dofile(fence .. 'shared/leads_logic.lua')
    local function leadOk(e) return leadsLogic.spotOf(spots, e.lead) ~= nil end -- server/main.lua visibleStock
    local rows = logic.filterStock(cfg.stock.heartlands_road, true, true, leadOk)
    local leadRows = 0
    for _, r in ipairs(rows) do
        if r.category == 'leads' then
            leadRows = leadRows + 1
            T.eq('string', type(r.lead))
            T.same({ item = 'fh_treasure_lead', price = 250, category = 'leads', lead = r.lead }, r) -- nothing else
            T.eq(1, logic.screenData({ stock = { r } }).stock[1].qty) -- still a fixed-qty lead row
        end
    end
    T.eq(1, leadRows)
    local broken = { common = {}, leads = { { item = 'fh_treasure_lead', price = 1, lead = 'lead_nowhere' } } }
    T.same({}, logic.filterStock(broken, true, true, leadOk))
    T.eq(1, #logic.filterStock(broken, true, true)) -- no predicate (specs / old callers): listed as before
    T.eq(nil, logic.leadInfo({ lead = { coords = { x = 1, y = 2, z = 3 } } })) -- an old-shape entry writes nothing
end)

T.finish()

-- Fence buy/sell transactions. Pure Lua: every FiveM / export call comes in through `deps`, so the specs can drive
-- the real code with fakes that yield (spec/fence_trade_spec.lua). Any dep may yield; the rules below hold anyway.
--
-- Invariants (Tier A):
--  1. One trade per citizenid at a time. The lock is taken before the first yield and released on every path
--     (the body runs under pcall); a second trade gets 'fence_busy' at once. A dropped player's lock is revoked: the
--     trade stops at its next alive check (before each mutation) and its exit releases the lock. A lock whose trade
--     never resumes is reclaimed after cfg.lockStaleSeconds; an old token's late release never frees a newer lock.
--     After EVERY yielding call a trade re-checks that it still owns the lock before touching the stash or money:
--     a reclaimed trade does no further stash/money side effect (it only logs what it leaves behind). Residual
--     window: one fh_core call that itself blocks >= lockStaleSeconds and lands after the new trade's checks.
--  2. The player's fence_stash (fh:fence:<citizenid>:<fence_id>, docs/decisions/inventory.md) must be EMPTY before a
--     trade stages anything, so it only ever holds the current trade's items. Leftovers from a crash or a failed
--     restore are never mixed in, given out or wiped: the trade is refused ('fence_pending') and a WARNING logged.
--     Only leftovers this module knows are the fence's own (unpaid buy stage, goods already paid for) are swept.
--  3. Buy: stage -> charge -> deliver. Charge failure (B7: fh_insufficient_funds, fh_charge_busy, ledger_failed,
--     removemoney_refused, no_player, player_changed; charge_unavailable; anything) discards the stage: no item
--     reaches the player, no money moves (B7 takes nothing on any refusal). It is never retried inside the trade:
--     the player retries (fh_charge_busy fails fast), so one buy is charged at most once. Partial delivery refunds
--     ONLY the undelivered units, and only after fh_core removeItem took exactly those units out of the stash
--     (all-or-nothing: fh_not_enough removes nothing, then no refund). Unknown delivery = no refund, keep stash.
--  4. Sell: goods -> stash (verified by snapshot) -> pay -> removeItem(sold). Pay failure gives the goods back; if
--     that fails the goods stay in the stash (still the player's, flagged for an admin), never lost, never paid twice.
--     A failed removeItem after pay leaves the sold (fence's) goods flagged for the next trade's sweep.
--  5. Settle (admin `fh_fence_settle`): runs under the same lock as a trade. A pending stash of player / paid-for goods
--     goes to the player all-or-nothing (room pre-check; a short transfer is put back step by step); fence-owned
--     leftovers (sweep flag) are swept, never given out. Afterwards the stash is empty and trades work again.
local M = {}

local function countOf(items, name)
    local n = 0
    for _, it in pairs(items or {}) do
        if it.name == name then n = n + (tonumber(it.amount) or 1) end
    end
    return n
end

local function onlyOf(items, name)
    for _, it in pairs(items or {}) do
        if it.name ~= name then return false end
    end
    return true
end

---Contract id: fh:fence:<citizenid>:<fence_id> (docs/decisions/inventory.md:74).
function M.stashRef(citizenid, fenceId)
    return { type = 'fence_stash', id = ('fh:fence:%s:%s'):format(tostring(citizenid), tostring(fenceId or 'roving')) }
end

-- ---------------------------------------------------------------- per-citizenid lock

---now() -> seconds; staleSeconds: a lock older than this is reclaimable (its trade never resumed: a hung await).
---onReclaim(tok) is told when that happens.
function M.newLocks(now, staleSeconds, onReclaim)
    now = now or os.time
    staleSeconds = staleSeconds or 120
    local held, seq = {}, 0 -- citizenid -> token
    local L = {}
    ---@return table|nil token (nil = someone else holds it)
    function L.acquire(cid, src)
        local cur = held[cid]
        if cur then
            if now() - cur.at < staleSeconds then return nil end
            if onReclaim then onReclaim(cur) end
        end
        seq = seq + 1
        local tok = { n = seq, cid = cid, src = src, at = now() }
        held[cid] = tok
        return tok
    end
    ---Only the holder releases: a reclaimed trade's late release never frees the newer lock.
    function L.release(tok)
        if tok and held[tok.cid] == tok then held[tok.cid] = nil end
    end
    ---owned: the lock is still this token's (not reclaimed). Required before EVERY stash / money side effect: a
    ---reclaimed trade must not touch a stash that a newer trade may be using.
    function L.owned(tok) return tok ~= nil and held[tok.cid] == tok end
    ---alive: owned and not revoked by a drop. Required before every FORWARD step (stage, charge, take goods).
    ---A revoked-but-owned trade may still roll back its own stash; nobody else can use it yet.
    function L.alive(tok) return L.owned(tok) and not tok.revoked end
    function L.held(cid) return held[cid] ~= nil end
    ---Player left mid-trade: revoke. The trade stops at its next alive check and its pcall exit releases the lock.
    ---Not released here: a reconnect (same citizenid, new src) would otherwise interleave with the trade still
    ---running. A trade that never resumes is reclaimed after staleSeconds.
    function L.dropSrc(src)
        for _, tok in pairs(held) do
            if tok.src == src then tok.revoked = true end
        end
    end
    return L
end

-- ---------------------------------------------------------------- trader

---deps (all may yield): citizenOf(src), stopFor(src) -> stop, stopId|reason, currentStop() -> stop|nil (no range check,
---admin settle), visibleStock(src, stopId),
---ensureStash(ref, stop), snapshot(ref), view(ref), canFit(ref, item, qty), addItem(ref, item, qty, info),
---clear(ref), removeItem(ref, item, qty) (all-or-nothing, fh_not_enough), transferAll(from, to, src) -> ok, moved,
---leftovers, move(from, to, fromSlot, toSlot, amount, src),
---charge(src, amount, reason, region_id), pay(src, amount, reason, region_id), log(msg), now() -> seconds.
---citizenOf must not yield (the lock is taken right after it). Failures are returned (false/nil, reason), not thrown;
---a throw is still caught, logged and releases the lock.
function M.new(cfg, logic, deps)
    local function log(fmt, ...) deps.log(fmt:format(...)) end
    local locks = M.newLocks(deps.now, cfg.lockStaleSeconds, function(tok)
        log('WARNING reclaimed a stale trade lock: citizenid=%s src=%s', tostring(tok.cid), tostring(tok.src))
    end)
    -- stash id -> true: what is in that stash is known to be the fence's (safe to wipe). Cleared whenever the stash
    -- is seen empty or player-owned / paid-for goods are left in it (pin).
    local sweep = {}
    local T = { locks = locks }
    local owned, alive = locks.owned, locks.alive

    local function run(op, src, fn, ...)
        local cid = deps.citizenOf(src)
        if not cid then return false, 'no_player' end
        local tok = locks.acquire(cid, src) -- no yield between the lookup and here
        if not tok then return false, 'fence_busy' end
        local res = table.pack(pcall(fn, tok, cid, ...))
        locks.release(tok)
        if not res[1] then
            log('ERROR %s citizenid=%s: %s (stash left as is: next trade checks it)', op, tostring(cid), tostring(res[2]))
            return false, 'fence_error'
        end
        return table.unpack(res, 2, res.n)
    end

    ---Player goods or paid-for goods stay in the stash: never sweep them.
    local function pin(stash) sweep[stash.id] = nil end

    ---A reclaimed trade stops here: no stash / money side effect, just say what it leaves behind.
    local function reclaimed(tok, op, what)
        log('WARNING %s reclaimed mid-trade (%s): citizenid=%s, stash not touched', op, what, tostring(tok.cid))
        return false, 'fence_busy'
    end

    ---Wipe the stash (caller checked owned). sweepable = what is in it is the fence's, so a later trade may finish.
    local function discard(stash, sweepable, why)
        local ok, err = deps.clear(stash)
        if ok then
            sweep[stash.id] = nil
            return true
        end
        sweep[stash.id] = sweepable and true or nil
        log('WARNING %s: clear %s failed (%s)%s', why, stash.id, tostring(err),
            sweepable and ', retried on the next trade' or ', left for an admin')
        return false
    end

    ---Owner-only cleanup of an unpaid stage: discard when still owned, else leave it (logged).
    local function dropStage(tok, stash, why)
        if owned(tok) then return discard(stash, true, why) end
        reclaimed(tok, 'buy', why .. ', unpaid stage may remain')
        return false
    end

    ---Register the stash and make sure it is empty (invariant 2). @return boolean ok, string|nil reason
    local function begin(tok, stash, stop, cid)
        local ok, err = deps.ensureStash(stash, stop)
        if not ok then return false, err or 'fh_unavailable' end
        local items = deps.snapshot(stash)
        if not owned(tok) then return false, 'fence_busy' end
        if not items then return false, 'fh_unavailable' end
        if next(items) == nil then
            pin(stash) -- emptied elsewhere: an old sweep flag must not outlive what it was about
            return true
        end
        if sweep[stash.id] and discard(stash, true, 'sweep') then
            items = deps.snapshot(stash)
            if not owned(tok) then return false, 'fence_busy' end
            if items and next(items) == nil then return true end
        end
        local parts = {}
        for slot, it in pairs(items or {}) do parts[#parts + 1] = ('%s:%sx%s'):format(slot, tostring(it.name), tostring(it.amount)) end
        table.sort(parts)
        log('WARNING fence stash not empty, trade refused: citizenid=%s stash=%s items=[%s]', tostring(cid), stash.id,
            table.concat(parts, ','))
        return false, 'fence_pending'
    end

    -- ------------------------------------------------------------ buy

    local function buy(tok, cid, src, item, qty)
        local stop, stopId = deps.stopFor(src)
        if not stop then return false, stopId end
        local quote, why = logic.quoteBuy(deps.visibleStock(src, stopId), item, qty, cfg.maxQty)
        if not quote then return false, why end
        local backpack, stash = { type = 'backpack', id = src }, M.stashRef(cid, cfg.fenceId)

        local fits, fitWhy = deps.canFit(backpack, item, qty)
        if not fits then return false, fitWhy or 'no_room' end
        local ok, err = begin(tok, stash, stop, cid)
        if not ok then return false, err end
        if not alive(tok) then return false, 'fence_busy' end

        -- 1. stage (nothing reaches the player yet)
        ok, err = deps.addItem(stash, item, qty, logic.leadInfo(quote.entry))
        if not ok then
            dropStage(tok, stash, 'buy stage refused')
            return false, owned(tok) and (err or 'fh_refused') or 'fence_busy'
        end
        if not owned(tok) then dropStage(tok, stash, 'after stage'); return false, 'fence_busy' end
        -- charge only for what is really staged (and only that is in the stash)
        local staged = deps.snapshot(stash)
        if not staged or not onlyOf(staged, item) or countOf(staged, item) ~= qty or not alive(tok) then
            dropStage(tok, stash, 'buy stage check')
            return false, alive(tok) and 'stage_failed' or 'fence_busy'
        end

        -- 2. charge: any failure = the stage is the fence's again, nothing delivered, no money moved
        ok, err = deps.charge(src, quote.total, 'fence_buy:' .. item, stop.region_id)
        if not ok then
            dropStage(tok, stash, 'buy charge refused')
            return false, owned(tok) and (err or 'charge_refused') or 'fence_busy'
        end
        if not owned(tok) then
            -- paid, but the stash may be someone else's now: deliver nothing, refund nothing, flag it
            pin(stash)
            log('WARNING buy paid then reclaimed, owed delivery or refund: citizenid=%s item=%s qty=%d paid=%d',
                tostring(cid), item, qty, quote.total)
            return false, 'fence_busy'
        end

        -- 3. deliver (revoked-but-owned still delivers: the money is taken). The stash holds only this trade's
        --    items, so what is left in it is exactly what was not delivered.
        local tok2, moved = deps.transferAll(stash, backpack, src)
        local left = deps.snapshot(stash)
        local undelivered
        if left then
            undelivered = countOf(left, item)
        elseif tok2 and type(moved) == 'table' then
            undelivered = qty - countOf(moved, item)
        else
            pin(stash)
            log('WARNING buy delivery unknown, no refund: citizenid=%s item=%s qty=%d paid=%d (items stay in %s)',
                tostring(cid), item, qty, quote.total, stash.id)
            return false, 'delivery_unknown'
        end
        undelivered = math.max(0, math.min(qty, undelivered))
        if undelivered == 0 then return true, qty, 0 end

        -- 4. partial: remove exactly the undelivered units first (owner only, all-or-nothing), then refund only those
        local refund = undelivered * quote.entry.price
        local rmOk, rmErr = false, 'reclaimed'
        if owned(tok) then rmOk, rmErr = deps.removeItem(stash, item, undelivered) end
        pin(stash) -- removed: the stash held only these units; not removed: they were paid for, never swept
        if not rmOk then
            log('WARNING buy refund owed: citizenid=%s item=%s undelivered=%d refund=%d (remove: %s)', tostring(cid),
                item, undelivered, refund, tostring(rmErr))
            return false, 'delivery_incomplete'
        end
        -- the units are gone: the refund is ours to finish even if the lock was reclaimed meanwhile (money only)
        local rok, rerr = deps.pay(src, refund, 'fence_refund', stop.region_id)
        if not rok then
            -- the undelivered units are already gone, so this is money owed (the charge ledger row proves it)
            log('WARNING REFUND FAILED, refund owed: citizenid=%s src=%s item=%s undelivered=%d amount=%d: %s',
                tostring(cid), tostring(src), item, undelivered, refund, tostring(rerr))
        end
        local delivered = qty - undelivered
        if delivered == 0 then return false, 'no_room' end
        return true, delivered, rok and refund or 0
    end

    -- ------------------------------------------------------------ sell

    local function sell(tok, cid, src, item, qty)
        local stop, stopId = deps.stopFor(src)
        if not stop then return false, stopId end
        local price, why = logic.quoteSell(cfg, item, qty)
        if not price then return false, why end
        local backpack, stash = { type = 'backpack', id = src }, M.stashRef(cid, cfg.fenceId)
        local ok, err = begin(tok, stash, stop, cid)
        if not ok then return false, err end

        local items = deps.snapshot(backpack)
        local v = deps.view(stash)
        if not items or not v then return false, 'fh_unavailable' end
        local free = {}
        for slot = 1, v.slots do if not v.items[slot] then free[#free + 1] = slot end end
        local slots = {}
        for slot in pairs(items) do slots[#slots + 1] = slot end
        table.sort(slots)

        -- 1. goods -> stash (alive before each move: a revoked or reclaimed trade takes nothing more)
        local need = qty
        for _, slot in ipairs(slots) do
            local it = items[slot]
            if need > 0 and it.name == item and free[1] then
                if not alive(tok) then break end
                local take = math.min(need, tonumber(it.amount) or 1)
                if deps.move(backpack, stash, slot, table.remove(free, 1), take, src) then need = need - take end
            end
        end

        ---Give the goods back. Owner only: a reclaimed trade must not empty a stash a newer trade may be using.
        local function restore()
            if not owned(tok) then pin(stash); return false, 'reclaimed' end
            deps.transferAll(stash, backpack, src)
            local left = deps.snapshot(stash)
            if left and next(left) == nil then return true end
            pin(stash) -- the player's goods: never swept
            return false, left and 'restore_incomplete' or 'restore_unknown'
        end

        -- 2. the stash is the truth: the backpack may have changed while we moved (slot reused by another item)
        local staged = deps.snapshot(stash)
        if not owned(tok) then
            pin(stash)
            return reclaimed(tok, 'sell', ('before pay, goods of %s may be in %s'):format(item, stash.id))
        end
        local sold = staged and countOf(staged, item) or 0
        if not staged or not onlyOf(staged, item) or sold > qty or sold == 0 or not alive(tok) then
            local rok, rerr = restore()
            if not rok then
                log('WARNING sell aborted and restore failed (%s): citizenid=%s item=%s (goods stay in %s)',
                    tostring(rerr), tostring(cid), item, stash.id)
            end
            if staged and onlyOf(staged, item) and sold == 0 then return false, 'not_enough_items' end
            return false, alive(tok) and 'inventory_changed' or 'fence_busy'
        end

        -- 3. pay; on failure give the goods back (sellOutcome; restore is owner-only)
        local total = cfg.buys[item] * sold
        local paid, payWhy = deps.pay(src, total, 'fence_sell:' .. item, stop.region_id)
        local out = logic.sellOutcome(paid, payWhy, restore, { citizenid = cid, item = item, qty = sold })
        if out.log then deps.log(out.log) end
        if out.action ~= 'complete' then return false, out.reason end

        -- 4. paid: the goods are the fence's. Remove exactly the sold units only while owned (all-or-nothing); a failure
        --    flags them for the next trade's sweep. A reclaimed trade leaves them (logged).
        if owned(tok) then
            local rok, rerr = deps.removeItem(stash, item, sold)
            if rok then
                pin(stash)
            else
                sweep[stash.id] = true
                log('WARNING sell: removing %dx %s from %s failed (%s), retried on the next trade', sold, item,
                    stash.id, tostring(rerr))
            end
        else
            log('WARNING sell paid then reclaimed: citizenid=%s item=%s qty=%d sold goods left in %s', tostring(cid),
                item, sold, stash.id)
        end
        return true, sold, total
    end

    -- ------------------------------------------------------------ admin settle

    local function totalsOf(items)
        local t, names = {}, {}
        for _, it in pairs(items or {}) do
            if not t[it.name] then names[#names + 1] = it.name end
            t[it.name] = (t[it.name] or 0) + (tonumber(it.amount) or 1)
        end
        table.sort(names)
        return t, names
    end

    local function describe(t, names)
        local parts = {}
        for _, n in ipairs(names) do parts[#parts + 1] = ('%sx%d'):format(n, t[n]) end
        return table.concat(parts, ',')
    end

    ---Clear a fence_pending stash (invariant 5). @return true, units, 'delivered'|'swept' | false, reason
    local function settle(tok, cid, src)
        local stop = deps.currentStop()
        if not stop then return false, 'no_schedule' end
        local backpack, stash = { type = 'backpack', id = src }, M.stashRef(cid, cfg.fenceId)
        local ok, err = deps.ensureStash(stash, stop)
        if not ok then return false, err or 'fh_unavailable' end
        local items = deps.snapshot(stash)
        if not owned(tok) then return false, 'fence_busy' end
        if not items then return false, 'fh_unavailable' end
        if next(items) == nil then
            pin(stash)
            return false, 'nothing_pending'
        end
        local want, names = totalsOf(items)
        if sweep[stash.id] then -- the fence's own (unpaid stage / goods already paid for): sweep, never give out
            if not alive(tok) then return false, 'fence_busy' end
            if not discard(stash, true, 'settle sweep') then return false, 'fh_unavailable' end
            log('settle: swept fence-owned leftovers: citizenid=%s stash=%s items=[%s]', tostring(cid), stash.id,
                describe(want, names))
            return true, 0, 'swept'
        end

        -- 1. room pre-check: a refusal changes nothing
        local units = 0
        for _, name in ipairs(names) do
            local fits = deps.canFit(backpack, name, want[name])
            if not fits then return false, 'no_room' end
            units = units + want[name]
        end
        if not alive(tok) then return false, 'fence_busy' end

        -- 2. hand everything over; the stash is the truth
        local tok2, moved = deps.transferAll(stash, backpack, src)
        local left = deps.snapshot(stash)
        if left and next(left) == nil then
            pin(stash)
            log('settle: citizenid=%s src=%s got [%s] from %s', tostring(cid), tostring(src), describe(want, names),
                stash.id)
            return true, units, 'delivered'
        end

        -- 3. short (backpack changed since the pre-check, or the transfer failed): put the moved steps back
        pin(stash) -- whatever is left is still the player's: never swept
        if not owned(tok) then
            return reclaimed(tok, 'settle', ('short transfer, goods split between %s and the backpack'):format(stash.id))
        end
        if tok2 and type(moved) == 'table' then
            for i = #moved, 1, -1 do
                local st = moved[i]
                if type(st) == 'table' and st.toSlot and st.fromSlot then
                    deps.move(backpack, stash, st.toSlot, st.fromSlot, st.amount, src)
                end
            end
        end
        local now = deps.snapshot(stash)
        local got = now and totalsOf(now) or nil
        local same = got ~= nil
        for _, name in ipairs(names) do if not got or got[name] ~= want[name] then same = false end end
        for name in pairs(got or {}) do if want[name] == nil then same = false end end
        if same then return false, 'no_room' end
        log('WARNING settle short and not fully put back: citizenid=%s src=%s wanted [%s] from %s, stash now %s',
            tostring(cid), tostring(src), describe(want, names), stash.id,
            got and ('[' .. describe(got, (select(2, totalsOf(now)))) .. ']') or 'unreadable')
        return false, 'settle_partial'
    end

    function T.buy(src, item, qty) return run('buy', src, buy, src, item, qty) end
    function T.settle(src) return run('settle', src, settle, src) end
    function T.sell(src, item, qty) return run('sell', src, sell, src, item, qty) end
    function T.dropped(src) locks.dropSrc(src) end
    return T
end

if _G.GetCurrentResourceName then _G.FhFenceTrade = M end
return M

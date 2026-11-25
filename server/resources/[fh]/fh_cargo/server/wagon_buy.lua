-- fh_cargo wagon buy (roads-04 R16, Tier A: money + persistence). Pure Lua: every export, DB and FiveM call comes in
-- through `deps`, so spec/cargo_buy_spec.lua drives this exact code with fakes that yield (coroutines).
--
-- Invariants:
--  1. One buy per player at a time: a busy lock keyed by src AND by citizenid (in memory). A second buy while one is
--     in flight gets 'fh_buy_busy' at once and is never charged. The lock is always released (success, refusal, throw).
--  2. Gate order (cheap and refusing before money moves): unknown tier (fh_bad_tier) -> no character -> already owned
--     (fh_already_owned, DB read) -> rep unlock for t2/t3 (fh_progression canUnlock 'wagon_t2'/'wagon_t3', fail closed
--     'fh_locked' when it is not started or throws, rules.wagonTierGate) -> charge. The character is re-checked after
--     every yield before the charge: fh_economy charges whichever character `src` has loaded at call time.
--  3. Charge: fh_economy:charge(src, price, 'wagon_buy', region). fh_charge_busy (nothing taken) is retried
--     cfg.BuyChargeRetries times after cfg.BuyRetryMs, then refused; every other refusal is refused as returned
--     (nothing taken, no row). A charge that THREW has an unknown outcome: the row is still written (never a refund
--     that could pay twice, never money taken with nothing given; at worst the wagon was free) and an ALERT is logged.
--  4. The fh_wagons row is written ONLY after the charge succeeded, for the citizenid captured before any yield.
--     INSERT IGNORE on PK (citizenid, tier): 1 = bought; 0 = a concurrent buy (e.g. across an fh_cargo restart that lost
--     the lock) already owns it, so this charge is refunded; nil / throw = DB failure, refunded. Refund =
--     fh_economy:credit(citizenid, price, 'wagon_buy_refund', region) (online or queued, by the captured citizenid).
--     A failed refund is never silent: ALERT log + fh:cargo:wagon_buy_owed.
local M = {}

---deps: citizenid(src) -> cid|nil (no yield); owned(cid, tier) -> true|false|nil (nil = DB read failed; may yield);
---canUnlock(src, unlockId) -> ok, reason (may yield, may throw); charge(src, amount, reason, region) -> ok, err
---(may yield, may throw); insert(cid, tier) -> 1|0|nil (may yield, may throw); refund(cid, amount, reason, region)
----> ok, err, mode (may yield, may throw); wait(ms); log(msg); emit(name, payload).
---@return boolean ok, string|table codeOrResult, any detail  ok -> { tier, price, citizenid }
function M.buy(cfg, rules, deps, locks, src, tierArg, region)
    local function log(fmt, ...) -- never throws (a bad format or a failing logger must not break the money path)
        local a = table.pack(...)
        pcall(function() deps.log(fmt:format(table.unpack(a, 1, a.n))) end)
    end
    local function emit(name, payload) if deps.emit then pcall(deps.emit, name, payload) end end

    if type(src) ~= 'number' or src <= 0 then return false, 'fh_no_player' end
    local tier = rules.parseTier(tierArg)
    if not tier then return false, 'fh_bad_tier' end
    local key = tier.key
    local price = rules.wagonPrice(cfg.Prices, key)
    if not price then
        log('ERROR no valid buy price for wagon tier %s (config Prices)', key)
        return false, 'fh_no_price'
    end
    if type(region) ~= 'string' or region == '' then return false, 'fh_unknown_region' end
    local cid = deps.citizenid(src)
    if not cid then return false, 'fh_no_character' end

    local kSrc, kCid = 'src:' .. src, 'cid:' .. cid
    if locks[kSrc] or locks[kCid] then return false, 'fh_buy_busy' end
    locks[kSrc], locks[kCid] = true, true

    -- charged = money taken (or unknown when unknown = true); inserted = row written; refundTried = refund() ran
    local st = { charged = false, inserted = false, unknown = false, refundTried = false }

    local function alive()
        local now = deps.citizenid(src)
        if now == cid then return true end
        return false, now == nil and 'fh_no_character' or 'player_changed'
    end

    ---Give the exact price back to the captured citizenid. Never silent on failure.
    local function refund(why)
        st.refundTried = true
        local called, ok, err, mode = pcall(function() return deps.refund(cid, price, rules.REFUND_REASON, region) end)
        if called and ok == true then
            log('wagon_buy refunded cid=%s tier=%s amount=%d region=%s (%s, mode=%s)', cid, key, price, region, why,
                tostring(mode))
            return true
        end
        local e = called and tostring(err or 'refused') or ('threw: ' .. tostring(ok))
        log('ALERT wagon_buy REFUND FAILED cid=%s tier=%s amount=%d region=%s (%s): %s. OWED $%d, credit it by hand',
            cid, key, price, region, why, e, price)
        emit('fh:cargo:wagon_buy_owed', { src = src, citizenid = cid, tier = key, owed = price, region = region,
            reason = why, err = e })
        return false
    end

    local function run()
        -- already owned (DB read, may yield)
        local oCalled, owned = pcall(deps.owned, cid, key)
        if not oCalled or owned == nil then
            log('ERROR fh_wagons read failed cid=%s tier=%s: %s', cid, key, tostring(oCalled and 'nil' or owned))
            return false, 'fh_db_error'
        end
        if owned == true then return false, 'fh_already_owned' end
        local a, aw = alive()
        if not a then return false, aw end

        -- rep unlock (t2/t3), fail closed
        local unlockId = rules.unlockForTier(key)
        if unlockId then
            local callOk, uok, ureason = pcall(deps.canUnlock, src, unlockId)
            local allowed, why = rules.wagonTierGate(key, callOk, uok, ureason)
            if not allowed then return false, why end
            a, aw = alive()
            if not a then return false, aw end
        end

        -- charge, fh_charge_busy retried
        local attempts = 1 + math.max(0, math.floor(tonumber(cfg.BuyChargeRetries) or 0))
        for i = 1, attempts do
            if i > 1 then
                deps.wait(tonumber(cfg.BuyRetryMs) or 250)
                a, aw = alive()
                if not a then return false, aw end
            end
            local called, ok, err = pcall(deps.charge, src, price, rules.BUY_REASON, region)
            if not called then
                st.charged, st.unknown = true, true
                log('ALERT wagon_buy charge threw cid=%s tier=%s amount=%d region=%s: %s. Outcome unknown: wagon granted, '
                    .. 'check fh_ledger for a wagon_buy charge', cid, key, price, region, tostring(ok))
                break
            end
            if ok == true then st.charged = true break end
            if err ~= 'fh_charge_busy' or i == attempts then
                return false, type(err) == 'string' and err ~= '' and err or 'charge_refused'
            end
        end

        -- row only now, for the captured citizenid
        local iCalled, n = pcall(deps.insert, cid, key)
        if iCalled and n == 1 then
            st.inserted = true
            return true
        end
        if st.unknown then -- never refund an unknown charge (could pay twice)
            log('ALERT wagon_buy row not written after an unknown charge cid=%s tier=%s amount=%d: %s', cid, key, price,
                tostring(iCalled and n or ('threw: ' .. tostring(n))))
            return false, iCalled and n == 0 and 'fh_already_owned' or 'fh_db_error'
        end
        if iCalled and n == 0 then -- a concurrent buy already owns it: give this charge back
            if refund('already_owned') then return false, 'fh_already_owned', 'refunded' end
            return false, 'fh_refund_failed'
        end
        log('ERROR fh_wagons insert failed after charge cid=%s tier=%s: %s', cid, key,
            tostring(iCalled and n or ('threw: ' .. tostring(n))))
        if refund('insert_failed') then return false, 'fh_buy_refunded' end
        return false, 'fh_refund_failed'
    end

    local called, ok, code, detail = pcall(run)
    if not called then
        log('ERROR wagon_buy cid=%s tier=%s: %s', cid, key, tostring(ok))
        ok, code, detail = false, 'fh_buy_error', nil
        if st.charged and not st.inserted and not st.unknown and not st.refundTried then -- threw after the charge
            code = refund('error') and 'fh_buy_refunded' or 'fh_refund_failed'
        end
    end
    locks[kSrc], locks[kCid] = nil, nil
    if ok then
        emit('fh:cargo:wagon_bought', { src = src, citizenid = cid, tier = key, price = price, region = region })
        return true, { tier = key, price = price, citizenid = cid }
    end
    return false, code, detail
end

if GetCurrentResourceName then
    FhCargoBuy = M
else
    return M
end

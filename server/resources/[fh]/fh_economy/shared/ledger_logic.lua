-- Pure validation for the money & rep ledger. No natives, no DB; unit-tested.
local logic = {}

local function validReason(s, maxLen)
    return type(s) == 'string' and s:match('%S') ~= nil and (not maxLen or #s <= maxLen)
end

---src must be a real number (server id), not a numeric string or identifier.
function logic.validSrc(src)
    return type(src) == 'number' and src == src and src > 0 and src % 1 == 0
end

local function isFinite(n)
    return type(n) == 'number' and n == n and n ~= math.huge and n ~= -math.huge
end

---@param args { amount:any, reason:any, region_id:any }
---@param ctx { isKnownRegion:fun(id:any):boolean, maxPay:number? }
---@return boolean ok, string? err
function logic.validatePay(args, ctx)
    args = args or {}
    if not isFinite(args.amount) or args.amount <= 0 then return false, 'invalid_amount' end
    if ctx.maxPay and args.amount > ctx.maxPay then return false, 'amount_too_large' end
    if not validReason(args.reason, ctx.maxReason) then return false, 'invalid_reason' end
    if not ctx.isKnownRegion(args.region_id) then return false, 'unknown_region' end
    return true
end

---@param args { delta:any, reason:any, region_id:any }
---@param ctx { isKnownRegion:fun(id:any):boolean, maxRepDelta:number? }
---@return boolean ok, string? err
function logic.validateRep(args, ctx)
    args = args or {}
    if not isFinite(args.delta) or args.delta == 0 then return false, 'invalid_delta' end
    if ctx.maxRepDelta and math.abs(args.delta) > ctx.maxRepDelta then return false, 'delta_too_large' end
    if not validReason(args.reason, ctx.maxReason) then return false, 'invalid_reason' end
    if not ctx.isKnownRegion(args.region_id) then return false, 'unknown_region' end
    return true
end

---Charge (debit) uses the same rules as pay, with its own cap (ctx.maxCharge).
---@param args { amount:any, reason:any, region_id:any }
---@param ctx { isKnownRegion:fun(id:any):boolean, maxCharge:number?, maxReason:number? }
---@return boolean ok, string? err
function logic.validateCharge(args, ctx)
    return logic.validatePay(args, { isKnownRegion = ctx.isKnownRegion, maxPay = ctx.maxCharge,
        maxReason = ctx.maxReason })
end

---Credit (idea-700, offline-safe payout): a valid citizenid (logic.validCitizenid) and a positive INTEGER amount
---(5.0 is taken as 5; 5.5, numeric strings, NaN and inf are refused), then the same rules as pay / charge with its own
---cap (ctx.maxCredit).
---@param args { citizenid:any, amount:any, reason:any, region_id:any }
---@param ctx { isKnownRegion:fun(id:any):boolean, maxCredit:number?, maxReason:number? }
---@return boolean ok, string? err, integer? amount  the amount as a Lua integer when ok
function logic.validateCredit(args, ctx)
    args = args or {}
    if not logic.validCitizenid(args.citizenid) then return false, 'invalid_citizenid' end
    local n = isFinite(args.amount) and math.tointeger(args.amount) or nil
    if not n or n <= 0 then return false, 'invalid_amount' end
    local ok, err = logic.validatePay({ amount = n, reason = args.reason, region_id = args.region_id },
        { isKnownRegion = ctx.isKnownRegion, maxPay = ctx.maxCredit, maxReason = ctx.maxReason })
    if not ok then return false, err end
    return true, nil, n
end

---True when `balance` covers `amount`. A missing / junk balance never covers anything.
function logic.canAfford(balance, amount)
    return isFinite(balance) and isFinite(amount) and balance >= amount
end

---Per-key in-flight guard (B7 fix). Runs `fn(...)` while `locks[key]` is held; a second call for the same key while
---the first is still in flight (it yields on MySQL awaits) does not wait: it returns `false, busyErr` at once and
---touches nothing. The lock is released on every exit, including an error thrown by `fn` (re-raised after release).
---@return any ... fn's results, or false, busyErr
function logic.serialized(locks, key, busyErr, fn, ...)
    if locks[key] then return false, busyErr end
    locks[key] = true
    local res = table.pack(pcall(fn, ...))
    locks[key] = nil
    if not res[1] then error(res[2], 0) end
    return table.unpack(res, 2, res.n)
end

local function voidOrWarn(io, id, why)
    if not io.void(id) then io.warn(id, why) end
end

---The charge sequence, with every side effect injected so the order and the rollback are specced:
---  1. the player is loaded and covers amount, else `no_player` / `fh_insufficient_funds` (nothing written)
---  2. ledger row FIRST (kind='charge'), as pay does; no row -> `ledger_failed` (no money taken)
---  3. the insert yielded: look the player up AGAIN (`io.player()`); the handle from before the yield is never used
---     after it. Gone or another character -> that error, row voided, no money taken from anyone.
---  4. re-check the balance on the fresh handle and remove the money with no yield in between, so the balance can
---     never go negative even if rsg-core's DontAllowMinus changes; short or refused -> void our own row again
---Never money taken without a row, never a row without the money taken (a failed void is warned, as in pay).
---Callers serialize it per citizenid (logic.serialized) so two charges never interleave steps 1-4.
---io = { player = fun():handle|nil, string?  -- fresh lookup on every call; nil + err when gone / switched
---       balance = fun(handle):number|nil, insert = fun():id|nil, remove = fun(handle):boolean,
---       void = fun(id):boolean, warn = fun(id, err) }
---@return boolean ok, string? err, integer? ledgerId
function logic.runCharge(io, amount)
    local p, why = io.player()
    if not p then return false, why or 'no_player' end
    if not logic.canAfford(io.balance(p), amount) then return false, 'fh_insufficient_funds' end
    local id = io.insert()
    if not id then return false, 'ledger_failed' end
    p, why = io.player()
    local err
    if not p then
        err = why or 'no_player'
    elseif not logic.canAfford(io.balance(p), amount) then
        err = 'fh_insufficient_funds'
    elseif not io.remove(p) then
        err = 'removemoney_refused'
    end
    if err then
        voidOrWarn(io, id, err)
        return false, err
    end
    return true, nil, id
end

---The pay sequence (same shape as runCharge): player loaded, ledger row FIRST, look the player up AGAIN after the
---insert yield, then add the money on the fresh handle. Gone / switched / refused -> void our own row (warn if the
---void fails); money is never added to a Player object captured before the yield.
---io = { player = fun():handle|nil, string?, insert = fun():id|nil, add = fun(handle):boolean,
---       void = fun(id):boolean, warn = fun(id, err) }
---@return boolean ok, string? err, integer? ledgerId
function logic.runPay(io)
    local p, why = io.player()
    if not p then return false, why or 'no_player' end
    local id = io.insert()
    if not id then return false, 'ledger_failed' end
    p, why = io.player()
    local err
    if not p then
        err = why or 'no_player'
    elseif not io.add(p) then
        err = 'addmoney_refused'
    end
    if err then
        voidOrWarn(io, id, err)
        return false, err
    end
    return true, nil, id
end

---citizenid accepted by getRep's offline read: 1-50 chars (fh_rep.citizenid is varchar(50)) of letters, digits,
---`_` or `-`, and not all digits (that is a mistyped server id). Padded / blank / junk strings are refused instead of
---silently reading "no row" = 0.
function logic.validCitizenid(s)
    return type(s) == 'string' and #s <= 50 and s:match('^[%w_%-]+$') ~= nil and s:match('^%d+$') == nil
end

---fh_rep.value as read from the DB -> integer rep (0 when there is no row). Rounded down: a threshold check
---`rep >= n` never passes early on a fractional value.
function logic.repValue(v)
    v = tonumber(v)
    if not isFinite(v) then return 0 end
    return math.floor(v)
end

---Apply a rep delta to the current value, clamped to [min, max].
function logic.applyRep(current, delta, min, max)
    local v = (current or 0) + delta
    if min and v < min then v = min end
    if max and v > max then v = max end
    return v
end

if _G.GetCurrentResourceName then _G.FhLedgerLogic = logic end
return logic

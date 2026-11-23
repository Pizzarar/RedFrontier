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

---True when `balance` covers `amount`. A missing / junk balance never covers anything.
function logic.canAfford(balance, amount)
    return isFinite(balance) and isFinite(amount) and balance >= amount
end

---The charge sequence, with every side effect injected so the order and the rollback are specced:
---  1. balance covers amount, else `fh_insufficient_funds` (nothing written)
---  2. ledger row FIRST (kind='charge'), as pay does; no row -> `ledger_failed` (no money taken)
---  3. re-check the balance (the insert yielded) and remove the money with no yield in between, so the balance can
---     never go negative even if rsg-core's DontAllowMinus changes; short or refused -> void our own row again
---Never money taken without a row, never a row without the money taken (a failed void is warned, as in pay).
---io = { balance = fun():number|nil, insert = fun():id|nil, remove = fun():boolean, void = fun(id):boolean,
---       warn = fun(id) }
---@return boolean ok, string? err, integer? ledgerId
function logic.runCharge(io, amount)
    if not logic.canAfford(io.balance(), amount) then return false, 'fh_insufficient_funds' end
    local id = io.insert()
    if not id then return false, 'ledger_failed' end
    local short = not logic.canAfford(io.balance(), amount)
    if short or not io.remove() then
        if not io.void(id) then io.warn(id) end
        if short or not logic.canAfford(io.balance(), amount) then return false, 'fh_insufficient_funds' end
        return false, 'removemoney_refused'
    end
    return true, nil, id
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

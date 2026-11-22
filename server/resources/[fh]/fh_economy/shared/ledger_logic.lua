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

---Apply a rep delta to the current value, clamped to [min, max].
function logic.applyRep(current, delta, min, max)
    local v = (current or 0) + delta
    if min and v < min then v = min end
    if max and v > max then v = max end
    return v
end

if _G.GetCurrentResourceName then _G.FhLedgerLogic = logic end
return logic

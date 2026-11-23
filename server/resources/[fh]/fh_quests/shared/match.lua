-- fh_quests step predicates (Q1). Pure Lua, no natives.
-- A step's `where` is a table of payload field -> predicate. Every field must pass (AND).
--
-- Predicate forms (see README "where grammar"):
--   'bear' / 3 / true           eq: the payload value must equal it (no type coercion: 3 ~= '3')
--   { eq = 'bear' }             eq, table form (lets eq combine with optional)
--   { min = 2 }                 number >= 2
--   { max = 5 }                 number <= 5
--   { min = 2, max = 5 }        both bounds
--   { any = { 'wolf', 'fox' } } equals one of the list
--   { optional = true, ... }    absent (nil) field passes; a present field must match the rest.
--                               { optional = true } alone accepts anything, so validate() rejects it.
-- A non-optional predicate fails when the field is absent.
local M = {}

local KEYS = { eq = true, min = true, max = true, any = true, optional = true }

local function scalar(v)
    local t = type(v)
    return t == 'string' or t == 'number' or t == 'boolean'
end

local function finite(n) return type(n) == 'number' and n == n and n > -math.huge and n < math.huge end

---Is `pred` a well-formed predicate?
---@return boolean ok, string|nil err
function M.validatePredicate(pred)
    if scalar(pred) then
        if type(pred) == 'number' and not finite(pred) then return false, 'fh_bad_eq' end
        return true
    end
    if type(pred) ~= 'table' then return false, 'fh_bad_predicate' end
    local n = 0
    for k in pairs(pred) do
        if not KEYS[k] then return false, 'fh_unknown_predicate_key:' .. tostring(k) end
        if k ~= 'optional' then n = n + 1 end
    end
    if n == 0 then return false, 'fh_empty_predicate' end
    if pred.optional ~= nil and pred.optional ~= true then return false, 'fh_bad_optional' end
    if pred.eq ~= nil then
        if not scalar(pred.eq) or (type(pred.eq) == 'number' and not finite(pred.eq)) then return false, 'fh_bad_eq' end
        if pred.min ~= nil or pred.max ~= nil or pred.any ~= nil then return false, 'fh_eq_exclusive' end
    end
    if pred.min ~= nil and not finite(pred.min) then return false, 'fh_bad_min' end
    if pred.max ~= nil and not finite(pred.max) then return false, 'fh_bad_max' end
    if pred.min ~= nil and pred.max ~= nil and pred.min > pred.max then return false, 'fh_min_gt_max' end
    if pred.any ~= nil then
        if type(pred.any) ~= 'table' or #pred.any == 0 then return false, 'fh_bad_any' end
        for k, v in pairs(pred.any) do
            if math.type(k) ~= 'integer' or k < 1 or k > #pred.any or not scalar(v) then return false, 'fh_bad_any' end
        end
        if pred.min ~= nil or pred.max ~= nil then return false, 'fh_any_exclusive' end
    end
    return true
end

---Is `where` a well-formed field -> predicate table (nil = match everything)?
---@return boolean ok, string|nil err  err names the field: '<code>@<field>'
function M.validate(where)
    if where == nil then return true end
    if type(where) ~= 'table' then return false, 'fh_bad_where' end
    for field, pred in pairs(where) do
        if type(field) ~= 'string' or field == '' then return false, 'fh_bad_where_field' end
        local ok, err = M.validatePredicate(pred)
        if not ok then return false, err .. '@' .. field end
    end
    return true
end

---Does one payload value satisfy one predicate?
function M.test(pred, value)
    if scalar(pred) then return value == pred end
    if type(pred) ~= 'table' then return false end
    if value == nil then return pred.optional == true end
    if pred.eq ~= nil and value ~= pred.eq then return false end
    if pred.min ~= nil and not (finite(value) and value >= pred.min) then return false end
    if pred.max ~= nil and not (finite(value) and value <= pred.max) then return false end
    if pred.any ~= nil then
        local hit = false
        for _, v in ipairs(pred.any) do
            if v == value then hit = true break end
        end
        if not hit then return false end
    end
    return true
end

---Does `payload` satisfy every field of `where`? nil where matches any table payload.
---@return boolean ok, string|nil field  the first failing field (sorted order, so the result is stable)
function M.where(where, payload)
    if type(payload) ~= 'table' then return false, nil end
    if where == nil then return true end
    local fields = {}
    for field in pairs(where) do fields[#fields + 1] = field end
    table.sort(fields)
    for _, field in ipairs(fields) do
        if not M.test(where[field], payload[field]) then return false, field end
    end
    return true
end

---Does this payload credit `citizenid`? payload.citizenid equal, or listed in payload.participants
---(the array form @core adds to fh:zones:camp_cleared, Q0a). The server resolves `src` to citizenid before this.
function M.credits(payload, citizenid)
    if type(payload) ~= 'table' or type(citizenid) ~= 'string' or citizenid == '' then return false end
    if payload.citizenid == citizenid then return true end
    if type(payload.participants) == 'table' then
        for _, cid in ipairs(payload.participants) do
            if cid == citizenid then return true end
        end
    end
    return false
end

if GetCurrentResourceName then
    FhQuestsMatch = M
else
    return M
end

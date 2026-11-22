-- Pure-Lua helpers shared by client and server. No FiveM/RedM natives here so busted can load it.
local util = {}

---Clamp n into [lo, hi].
function util.clamp(n, lo, hi)
    if lo > hi then lo, hi = hi, lo end
    if n < lo then return lo end
    if n > hi then return hi end
    return n
end

---Recursively copy tables (cycle-safe). Metatables are not copied.
function util.deepCopy(v, seen)
    if type(v) ~= 'table' then return v end
    seen = seen or {}
    if seen[v] then return seen[v] end
    local out = {}
    seen[v] = out
    for k, x in pairs(v) do out[util.deepCopy(k, seen)] = util.deepCopy(x, seen) end
    return out
end

-- FXServer loads shared scripts as plain chunks; expose as a global there, module under busted.
if _G.GetCurrentResourceName then _G.FhUtil = util end
return util

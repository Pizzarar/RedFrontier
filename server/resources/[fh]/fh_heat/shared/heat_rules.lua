-- Pure heat math (spec L7): no natives, specced in spec/heat_rules_spec.lua. Heat is a number 0..100 per
-- (character, faction); the server owns it, this file only computes.
local M = {}

local function finite(n) return type(n) == 'number' and n == n and n > -math.huge and n < math.huge end
M.finite = finite

---Clamp to [lo, hi]; non-numbers count as lo. Rounded to 2 decimals so float drift never accumulates.
function M.clamp(v, lo, hi)
    lo, hi = lo or 0, hi or 100
    if not finite(v) then return lo end
    v = math.floor(v * 100 + 0.5) / 100
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

---@return number|nil new, string|nil err
function M.add(old, amount, lo, hi)
    if not finite(amount) then return nil, 'fh_bad_amount' end
    return M.clamp((finite(old) and old or 0) + amount, lo, hi)
end

---Heat for a named source (config.sources) times an optional multiplier (default 1).
---@return number|nil amount, string|nil err
function M.sourceAmount(sources, key, mult)
    local base = type(sources) == 'table' and sources[key] or nil
    if not finite(base) then return nil, 'fh_unknown_source' end
    if mult ~= nil and (not finite(mult) or mult < 0) then return nil, 'fh_bad_amount' end
    return base * (mult or 1)
end

---Lay-low decay: only while OFF that faction's territory. seconds = time since the last tick.
function M.decay(value, seconds, ratePerMinute, onTerritory, lo, hi)
    if onTerritory or not finite(seconds) or seconds <= 0 or not finite(ratePerMinute) or ratePerMinute <= 0 then
        return M.clamp(value, lo, hi)
    end
    return M.clamp(value - ratePerMinute * seconds / 60, lo, hi)
end

---Threshold level name for a heat value (highest min <= heat), or nil below the first. thresholds ascending.
function M.level(thresholds, heat)
    local best
    if not finite(heat) then return nil end
    for _, t in ipairs(thresholds or {}) do
        if heat >= t.min then best = t.name end
    end
    return best
end

---Money to pay off `points` heat (default: all of `heat`). Whole currency, rounded up. Points are capped to heat.
---@return integer|nil cost, number|nil points, string|nil err
function M.bountyCost(heat, perPoint, points)
    if not finite(heat) or not finite(perPoint) or perPoint < 0 then return nil, nil, 'fh_bad_amount' end
    if heat <= 0 then return nil, nil, 'fh_no_heat' end
    if points == nil then points = heat end
    if not finite(points) or points <= 0 then return nil, nil, 'fh_bad_amount' end
    if points > heat then points = heat end
    return math.ceil(points * perPoint), points
end

---Bounty payoff with an injected charge(amount) -> ok, err (fh_economy.charge shape: false,'fh_insufficient_funds').
---Returns ok, points paid, cost, err. Nothing is charged for a refused plan; a refused charge pays nothing.
function M.payoff(heat, perPoint, points, charge)
    local cost, paid, err = M.bountyCost(heat, perPoint, points)
    if not cost then return false, nil, nil, err end
    if type(charge) ~= 'function' then return false, nil, cost, 'fh_economy_unavailable' end
    local ok, cerr = charge(cost)
    if not ok then return false, nil, cost, cerr or 'fh_charge_failed' end
    return true, paid, cost, nil
end

---Which territory faction (if any) a position sits in, given FhRegions-shaped `regions`.
function M.factionAt(regions, x, y)
    local t = regions and regions.territoryAt(x, y)
    return t and t.faction or nil
end

if GetCurrentResourceName then
    FhHeatRules = M
else
    return M
end

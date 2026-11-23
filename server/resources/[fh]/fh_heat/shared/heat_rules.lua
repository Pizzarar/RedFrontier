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

---Region id for the bounty ledger row (fh_ledger.region_id is NOT NULL; fh_economy refuses unknown regions):
---the region of the territory the player stands in, else the faction's home region = the first region (by id)
---that lists the faction in its `factions`. nil when neither is known (the caller must not charge).
function M.chargeRegion(regions, faction, x, y)
    if type(regions) ~= 'table' then return nil end
    local t = regions.territoryAt and regions.territoryAt(x, y)
    if t and regions.isKnownRegion(t.region) then return t.region end
    local ids = {}
    for id in pairs(regions.regions or {}) do ids[#ids + 1] = id end
    table.sort(ids)
    for _, id in ipairs(ids) do
        for _, f in ipairs(regions.regions[id].factions or {}) do
            if f == faction then return id end
        end
    end
    return nil
end

---Parse the /paybounty points argument. Omitted (nil) = pay all heat. Anything else must be a finite number
---in (0, maxPoints]; junk, 0, negative, NaN/inf or more than maxPoints is refused (never silently "all").
---@return boolean ok, number|nil points, string|nil err
function M.parsePoints(arg, maxPoints)
    if arg == nil then return true, nil end
    local n = tonumber(arg)
    if not finite(n) or n <= 0 then return false, nil, 'fh_bad_points' end
    if finite(maxPoints) and n > maxPoints then return false, nil, 'fh_bad_points' end
    return true, n
end

---In-flight locks, one per key (citizenid + faction). acquire is a plain table test-and-set: Lua runs one
---coroutine at a time, so no other request can interleave between the test and the set.
function M.newLocks()
    local held = {}
    return {
        acquire = function(key)
            if held[key] then return false end
            held[key] = true
            return true
        end,
        release = function(key) held[key] = nil end,
        held = function(key) return held[key] == true end,
    }
end

function M.lockKey(citizenid, faction) return tostring(citizenid) .. '\0' .. tostring(faction) end

---Bounty payoff under the (citizenid, faction) in-flight lock. A second request while one is in flight is refused
---with fh_payoff_busy and charges nothing. The lock is ALWAYS released, and only once the whole sequence resolved:
---  plan -> charge -> commit (heat reset PERSISTED) -> success
---  charge ok, then commit fails / returns false / throws -> refund(exact charged amount), still under the lock:
---    refund ok -> fh_payoff_refunded (net nothing charged, heat unchanged, safe to retry)
---    refund fails -> fh_payoff_refund_failed (charged, heat unchanged: onError reports it, do NOT retry)
---d = { locks, key, heat = fn() -> current heat, perPoint, points,
---      charge = fn(cost) -> ok, err,  refund = fn(amount) -> ok, err,
---      commit = fn(paid) -> true only once the reset is persisted (subtracts paid from the CURRENT heat),
---      onError = fn(msg, charged:boolean, amount:number|nil)? }
---@return boolean ok, number|string paidOrErr, integer|nil cost
function M.runPayoff(d)
    if not d.locks.acquire(d.key) then return false, 'fh_payoff_busy' end
    local function report(msg, amount)
        if d.onError then pcall(d.onError, msg, amount ~= nil, amount) end
    end
    local charged -- the amount actually taken; set only once charge() reported success
    local called, ok, paid, cost, err = pcall(function()
        return M.payoff(d.heat(), d.perPoint, d.points, function(amount)
            local cok, cerr = d.charge(amount)
            if cok then charged = amount end
            return cok, cerr
        end)
    end)
    if charged == nil then -- nothing was taken: plain refusal or error, no refund needed
        d.locks.release(d.key)
        if not called then
            report(tostring(ok), nil)
            return false, 'fh_payoff_error'
        end
        if not ok then return false, err, cost end
        return false, 'fh_payoff_error' -- unreachable: success always charges
    end
    cost = cost or charged
    if called and ok then
        local cCalled, committed, cerr = pcall(d.commit, paid)
        if cCalled and committed then
            d.locks.release(d.key)
            return true, paid, cost
        end
        report('commit failed: ' .. tostring(cCalled and (cerr or 'heat reset not persisted') or committed), charged)
    else
        report('failed after charge: ' .. tostring(called and err or ok), charged)
    end
    -- post-charge failure: give the exact amount back before anyone can retry
    local rCalled, refunded, rerr = pcall(d.refund, charged)
    d.locks.release(d.key)
    if rCalled and refunded then return false, 'fh_payoff_refunded', cost end
    report('REFUND FAILED: ' .. tostring(rCalled and (rerr or 'refused') or refunded), charged)
    return false, 'fh_payoff_refund_failed', cost
end

---Event payloads (fh_core/docs/events.md: ONE table argument, src first). Returns a list of { name, payload }:
---fh:heat:changed always (when old ~= new), fh:heat:threshold when the level changes.
function M.changeEvents(src, citizenid, faction, old, new, thresholds, reason)
    if old == new then return {} end
    local lo, ln = M.level(thresholds, old), M.level(thresholds, new)
    local out = { { 'fh:heat:changed', { src = src, citizenid = citizenid, faction = faction, old = old, value = new,
        delta = new - old, level = ln, reason = reason } } }
    if lo ~= ln then
        out[2] = { 'fh:heat:threshold', { src = src, citizenid = citizenid, faction = faction, old_level = lo,
            level = ln, value = new } }
    end
    return out
end

---Run one loop tick protected: an error is reported to onError(msg) and swallowed so the loop keeps running.
---@return boolean ok
function M.safeTick(fn, onError, ...)
    local ok, err = pcall(fn, ...)
    if not ok and onError then pcall(onError, tostring(err)) end
    return ok
end

if GetCurrentResourceName then
    FhHeatRules = M
else
    return M
end

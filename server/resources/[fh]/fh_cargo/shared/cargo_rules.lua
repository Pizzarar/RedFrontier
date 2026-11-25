-- fh_cargo rules (spec L6, 4.1, 4.2). Pure Lua: no natives, specced in spec/cargo_rules_spec.lua.
-- Wagon tiers, ownership + reach + capacity checks for loading cargo, and the fast-travel veto. The server
-- (server/main.lua) only gathers facts (positions, container views) and calls this; the client is never trusted.
-- Weights are grams like the rest of fh_core.
local M = {}

-- T1 cart / T2 wagon / T3 freight. speed = unloaded cap in m/s; a full wagon is slowed by up to SPEED_LOAD_PENALTY.
M.TIERS = {
    t1 = { key = 't1', tier = 1, label = 'Cart',    slots = 15, maxWeight = 120000, speed = 8.0 },
    t2 = { key = 't2', tier = 2, label = 'Wagon',   slots = 30, maxWeight = 300000, speed = 7.0 },
    t3 = { key = 't3', tier = 3, label = 'Freight', slots = 60, maxWeight = 500000, speed = 6.0 },
}
M.ORDER = { 't1', 't2', 't3' }
M.SPEED_LOAD_PENALTY = 0.4 -- a wagon at max weight goes at (1 - 0.4) of its cap
M.DEFAULT_REACH = 5.0
M.DEFAULT_OPEN_REACH = 3.5
M.SNAP_ABOVE = 13.5 -- matches FhConfig.Access.SnapToleranceAbove (SNAP_TOLERANCE 10.0 + 3.5 m headroom)
M.SNAP_BELOW = 13.5 -- matches FhConfig.Access.SnapToleranceBelow (SNAP_TOLERANCE 10.0 + 3.5 m headroom)
M.DEFAULT_FAST_TRAVEL_REACH = 30.0
M.MAX_NEAREST_RANGE = 25.0

local ALIASES = { cart = 't1', wagon = 't2', freight = 't3', ['1'] = 't1', ['2'] = 't2', ['3'] = 't3' }

---'t2' | 'T2' | '2' | 'wagon' -> tier table, or nil, 'fh_bad_tier'.
function M.parseTier(s)
    s = tostring(s or ''):lower()
    local t = M.TIERS[ALIASES[s] or s]
    if not t then return nil, 'fh_bad_tier' end
    return t
end

---One wagon stash per character per tier: respawning a wagon keeps its cargo.
function M.wagonId(citizenid, tierKey)
    if type(citizenid) ~= 'string' or citizenid == '' or not M.TIERS[tierKey] then return nil end
    return citizenid .. ':' .. tierKey
end

function M.stashId(wagonId)
    if type(wagonId) ~= 'string' or wagonId == '' then return nil end
    return 'fh:wagon:' .. wagonId
end

---Speed cap (m/s) for a tier carrying `weight` grams. Clamped: overloaded = the full penalty.
function M.speedLimit(tierKey, weight)
    local t = M.TIERS[tierKey]
    if not t then return nil end
    local ratio = (tonumber(weight) or 0) / t.maxWeight
    if ratio < 0 then ratio = 0 elseif ratio > 1 then ratio = 1 end
    return t.speed * (1 - M.SPEED_LOAD_PENALTY * ratio)
end

local function xyz(v)
    if v == nil then return nil end
    local ok, x, y, z = pcall(function() return v.x, v.y, v.z end)
    if not ok or type(x) ~= 'number' or type(y) ~= 'number' or type(z) ~= 'number' then return nil end
    return x, y, z
end

---true/false, or nil when either position is unusable.
local function within(a, b, reach)
    local ax, ay, az = xyz(a)
    local bx, by, bz = xyz(b)
    if not ax or not bx then return nil end
    local dx, dy, dz = ax - bx, ay - by, az - bz
    return dx * dx + dy * dy + dz * dz <= reach * reach
end

---Horizontal reach + vertical snap tolerance for ground-snapped containers (e.g. chests whose server coords are a config z-hint).
local function withinSnapped(hintCoords, playerCoords, reach, above, below)
    local cx, cy, cz = xyz(hintCoords)
    local px, py, pz = xyz(playerCoords)
    if not cx or not px then return nil end
    local dx, dy = cx - px, cy - py
    if dx * dx + dy * dy > reach * reach then return false end
    local dzPlayer = pz - cz
    return dzPlayer <= above and dzPlayer >= -below
end

---Own wagon, in reach. wagon = { owner = citizenid, coords = ... }.
---@return boolean ok, string|nil reason
function M.canUseWagon(wagon, citizenid, playerCoords, reach)
    if type(wagon) ~= 'table' then return false, 'fh_no_wagon' end
    if not citizenid or wagon.owner ~= citizenid then return false, 'fh_not_owner' end
    if not xyz(wagon.coords) then return false, 'fh_no_coords' end
    local inReach = within(wagon.coords, playerCoords, reach or M.DEFAULT_REACH)
    if inReach == nil then return false, 'fh_no_player_coords' end
    if not inReach then return false, 'fh_out_of_reach' end
    return true
end

local function int(v)
    if type(v) == 'string' then v = tonumber(v) end
    if type(v) == 'number' and v == v and v == math.floor(v) and v > -math.huge and v < math.huge then
        return math.floor(v)
    end
end

---Chat args: { 'load', '3', '2' } -> { dir, slot, amount|nil } or nil, '<code>'.
function M.parseTransferArgs(args)
    local dir = args[1]
    if dir ~= 'load' and dir ~= 'unload' then return nil, 'fh_bad_dir' end
    local slot = int(args[2])
    if not slot or slot < 1 then return nil, 'fh_bad_slot' end
    local amount
    if args[3] ~= nil then
        amount = int(args[3])
        if not amount or amount < 1 then return nil, 'fh_bad_amount' end
    end
    return { dir = dir, slot = slot, amount = amount }
end

local function empty(t) return t == nil or next(t) == nil end

local function sameInfo(a, b)
    if empty(a) and empty(b) then return true end
    if type(a) ~= 'table' or type(b) ~= 'table' then return false end
    for k, v in pairs(a) do
        if type(v) == 'table' then
            if not sameInfo(v, b[k]) then return false end
        elseif b[k] ~= v then
            return false
        end
    end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end

local function weightOf(items)
    local w = 0
    for _, it in pairs(items or {}) do w = w + (tonumber(it.weight) or 0) * (tonumber(it.amount) or 0) end
    return w
end

local function stackable(it)
    if it.stackable ~= nil then return it.stackable and true or false end
    return it.unique ~= true
end

---Lowest slot first, so the pick is deterministic: a same-name, same-info stack if the item stacks, else the first free slot.
local function pickSlot(dest, item)
    local n = dest.slots
    if not n then
        n = 0
        for s in pairs(dest.items) do if type(s) == 'number' and s > n then n = s end end
    end
    if stackable(item) then
        for s = 1, n do
            local it = dest.items[s]
            if it and it.name == item.name and stackable(it) and sameInfo(it.info, item.info) then return s end
        end
    end
    for s = 1, n do
        if not dest.items[s] then return s end
    end
end

---Plan one cargo load/unload between the player's OWN wagon and the container they have open.
---p = { dir 'load'|'unload', slot, amount?, citizenid, playerCoords,
---      wagon = { id, owner, tier, coords },
---      wagonView = { items, slots?, maxWeight? } (optional; tier caps apply on top),
---      open = { type, id, coords, items, slots, maxWeight?, reach? },
---      reach?, sizeClassOf = fun(name, item) -> size_class|nil }
---Returns plan { fromRef, toRef, fromSlot, toSlot, amount, name } or nil, '<code>'. Checks only; never mutates.
---The caller then runs ONE exports.fh_core:move, which re-checks size class / weight / slot under fh_core's own veto.
function M.planTransfer(p)
    if type(p) ~= 'table' then return nil, 'fh_bad_request' end
    if p.dir ~= 'load' and p.dir ~= 'unload' then return nil, 'fh_bad_dir' end
    local ok, why = M.canUseWagon(p.wagon, p.citizenid, p.playerCoords, p.reach)
    if not ok then return nil, why end
    local tier = M.TIERS[p.wagon.tier]
    if not tier then return nil, 'fh_bad_tier' end
    local open = p.open
    if type(open) ~= 'table' or not open.type or not open.id then return nil, 'fh_nothing_open' end
    if open.type == 'wagon' then return nil, 'fh_same_container' end
    if not xyz(open.coords) then return nil, 'fh_no_coords' end
    local openReach = open.reach or M.DEFAULT_OPEN_REACH
    local openSnapped = open.snapped == true or (open.snapped == nil and open.type == 'chest')
    local openInReach
    if openSnapped then
        openInReach = withinSnapped(open.coords, p.playerCoords, openReach, M.SNAP_ABOVE, M.SNAP_BELOW)
    else
        openInReach = within(open.coords, p.playerCoords, openReach)
    end
    if not openInReach then return nil, 'fh_out_of_reach' end

    local wagonRef = { type = 'wagon', id = M.stashId(p.wagon.id) }
    local openRef = { type = open.type, id = open.id }
    local src, dst
    if p.dir == 'load' then
        src = { ref = openRef, items = open.items or {} }
        dst = { ref = wagonRef, items = (p.wagonView and p.wagonView.items) or {}, slots = tier.slots,
            maxWeight = tier.maxWeight }
        if p.wagonView and p.wagonView.slots then dst.slots = math.min(dst.slots, p.wagonView.slots) end
        if p.wagonView and p.wagonView.maxWeight then dst.maxWeight = math.min(dst.maxWeight, p.wagonView.maxWeight) end
    else
        src = { ref = wagonRef, items = (p.wagonView and p.wagonView.items) or {} }
        dst = { ref = openRef, items = open.items or {}, slots = open.slots, maxWeight = open.maxWeight }
    end

    local slot = int(p.slot)
    if not slot or slot < 1 then return nil, 'fh_bad_slot' end
    local item = src.items[slot]
    if type(item) ~= 'table' then return nil, 'fh_no_item' end
    local have = int(item.amount) or 0
    local amount = p.amount == nil and have or int(p.amount)
    if not amount or amount < 1 or amount > have then return nil, 'fh_bad_amount' end

    local class
    if type(p.sizeClassOf) == 'function' then class = p.sizeClassOf(item.name, item) else class = item.size_class end
    if class ~= 'cargo' then return nil, 'fh_not_cargo' end

    if dst.maxWeight and weightOf(dst.items) + (tonumber(item.weight) or 0) * amount > dst.maxWeight then
        return nil, 'fh_too_heavy'
    end
    local toSlot = pickSlot(dst, item)
    if not toSlot then return nil, 'fh_no_slot' end
    return { fromRef = src.ref, toRef = dst.ref, fromSlot = slot, toSlot = toSlot, amount = amount, name = item.name }
end

---Nearest wagon `citizenid` may load into (v1: owner only, canUseWagon rule), within `range` of `coords`.
---wagons = array of { id, owner, coords } for LIVE wagons only (an entry without usable coords is ignored).
---range is capped at MAX_NEAREST_RANGE. Returns wagon, distance or nil, '<code>'. Never throws.
function M.nearestWagon(citizenid, coords, range, wagons)
    range = tonumber(range)
    if not range or range ~= range or range <= 0 then return nil, 'fh_bad_range' end
    if range > M.MAX_NEAREST_RANGE then range = M.MAX_NEAREST_RANGE end
    if not citizenid then return nil, 'fh_no_character' end
    if not xyz(coords) then return nil, 'fh_no_player_coords' end
    local cx, cy, cz = xyz(coords)
    local best, bestD
    for _, w in ipairs(type(wagons) == 'table' and wagons or {}) do
        if type(w) == 'table' and M.canUseWagon(w, citizenid, coords, range) then
            local x, y, z = xyz(w.coords)
            local d = math.sqrt((x - cx) ^ 2 + (y - cy) ^ 2 + (z - cz) ^ 2)
            if not bestD or d < bestD then best, bestD = w, d end
        end
    end
    if not best then return nil, 'fh_no_wagon' end
    return best, bestD
end

---Fast-travel veto (spec 2 + 4.1: cargo never fast-travels).
---f = { unknown = reason|nil, carriedCargo = n, wagons = { { coords, cargoCount } }, playerCoords, reach }
---@return boolean ok, string|nil reason, table|nil wagon the blocking wagon
function M.fastTravelVerdict(f)
    f = f or {}
    -- Fail closed: the caller could not read a container (f.unknown = its reason), so we cannot say it is safe.
    if f.unknown then return false, 'fh_cargo_unknown' end
    if (tonumber(f.carriedCargo) or 0) > 0 then return false, 'fh_cargo_carried' end
    for _, w in ipairs(f.wagons or {}) do
        if (tonumber(w.cargoCount) or 0) > 0 and within(w.coords, f.playerCoords, f.reach or M.DEFAULT_FAST_TRAVEL_REACH) then
            return false, 'fh_cargo_wagon_near', w
        end
    end
    return true
end

-- ---------------------------------------------------------------- R8: wagon tier rep-unlock gate (roads-02)
-- t2/t3 wagons need an fh_progression unlock (wagon_t2 / wagon_t3); t1 is always allowed, so it is absent here.
-- (wagon_t3 landed in fh_progression config at G1: heartlands tier 3.) The server pcall's
-- exports.fh_progression:canUnlock and passes the result to wagonTierGate, keeping the decision pure and specced.
M.UNLOCKS = {
    t2 = 'wagon_t2',
    t3 = 'wagon_t3',
}

---Unlock id a wagon tier requires, or nil when the tier needs none (t1).
function M.unlockForTier(tierKey)
    return M.UNLOCKS[tierKey]
end

---Gate a wagon tier spawn on the fh_progression canUnlock result. Fail closed.
---callOk = the canUnlock call finished without throwing (pcall's first return); ok = its first return; reason = its second.
---A failed call (export missing / not started / threw) and any non-true ok are refused; the caller surfaces the returned
---reason when it is a non-empty string, else 'fh_locked'. A tier with no unlock (t1) is always allowed.
---@return boolean allowed, string|nil reason
function M.wagonTierGate(tierKey, callOk, ok, reason)
    if M.UNLOCKS[tierKey] == nil then return true end -- t1 / unknown tier: no gate (unknown tier is caught by parseTier)
    if callOk ~= true then return false, 'fh_locked' end -- export missing / not started / threw
    if ok == true then return true end
    if type(reason) == 'string' and reason ~= '' then return false, reason end
    return false, 'fh_locked'
end

-- ---------------------------------------------------------------- R16: owned wagons (roads-04)
-- A character owns a tier once bought (fh_wagons row, one per tier). The buy flow lives in server/wagon_buy.lua; these
-- are the pure pieces it (and the specs) use. Gate order there: unknown tier -> already owned -> canUnlock -> charge.
M.BUY_REASON = 'wagon_buy'
M.REFUND_REASON = 'wagon_buy_refund'

---Buy price (whole dollars, > 0) of a tier from the config price table, or nil (unknown tier / missing or bad price).
function M.wagonPrice(prices, tierKey)
    if not M.TIERS[tierKey] or type(prices) ~= 'table' then return nil end
    local p = prices[tierKey]
    if type(p) ~= 'number' or p ~= p or p <= 0 or p == math.huge or p ~= math.floor(p) then return nil end
    return math.floor(p)
end

---fh_wagons rows ({ tier = 't1' }, ...) -> set { t1 = true, ... }. Rows with an unknown tier are ignored.
function M.ownedSet(rows)
    local set = {}
    for _, r in ipairs(type(rows) == 'table' and rows or {}) do
        local t = type(r) == 'table' and r.tier or nil
        if type(t) == 'string' and M.TIERS[t] then set[t] = true end
    end
    return set
end

---Owned set -> tier keys in tier order ({ 't1', 't3' }).
function M.ownedList(set)
    local out = {}
    for _, k in ipairs(M.ORDER) do if type(set) == 'table' and set[k] then out[#out + 1] = k end end
    return out
end

---Same shape fh_economy accepts for a citizenid string (1-50 letters, digits, _ or -; not all digits).
function M.validCitizenid(cid)
    return type(cid) == 'string' and #cid >= 1 and #cid <= 50 and cid:match('^[%w_%-]+$') ~= nil
        and cid:match('^%d+$') == nil
end

-- ---------------------------------------------------------------- R2: wheel break + repair (spec L6)
-- The break roll runs on the server each tick from server-known state. A client hint is only ever a bool (off-road),
-- and any reported speed goes through sanitizeSpeed first.
-- TODO(R2 tune): numbers are first guesses, tune on the first drive test.
M.WHEEL = {
    minSpeed = 1.5,        -- m/s: below this a wagon never breaks a wheel
    baseChance = 0.004,    -- per tick at the tier's top speed, on road, empty
    offRoadMult = 4.0,
    loadMult = 1.0,        -- full load doubles the chance (1 + loadMult * fraction)
    speedSlack = 1.5,      -- sanitizeSpeed accepts up to tier speed * this (downhill / physics noise)
    brokenSpeedMult = 0.4, -- speed cap multiplier while a wheel is broken
    repairMs = 8000,
    repairMoveMax = 3.0,   -- m the player may drift from where they started before the repair cancels
}

---Item defs registered via fh_core.registerItems (never in fh_core's config).
M.ITEMS = {
    hammer = { label = 'Hammer', weight = 800, size_class = 'bulky', stackable = false, value_base = 4 },
    wagon_wheel = { label = 'Wagon Wheel', weight = 6000, size_class = 'bulky', stackable = true, value_base = 12 },
}

local function num(v)
    if type(v) == 'number' and v == v and v ~= math.huge and v ~= -math.huge then return v end
end

local function clamp(v, lo, hi) if v < lo then return lo elseif v > hi then return hi end return v end

---Fraction of the tier's max weight carried, 0..1.
function M.loadFraction(tierKey, weight)
    local t = M.TIERS[tierKey]
    if not t then return 0 end
    return clamp((num(weight) or 0) / t.maxWeight, 0, 1)
end

---Clamp a reported speed to [0, tier cap * slack]. nil when it is not a usable number or the tier is unknown.
function M.sanitizeSpeed(speed, tierKey)
    local t = M.TIERS[tierKey]
    local v = num(speed)
    if not t or not v then return nil end
    return clamp(v, 0, t.speed * M.WHEEL.speedSlack)
end

---Per-tick wheel-break probability 0..1. p = { tier, speed (m/s), offRoad?, loadFraction? }.
function M.breakChance(p)
    if type(p) ~= 'table' then return 0 end
    local t = M.TIERS[p.tier]
    local speed = num(p.speed)
    if not t or not speed or speed < M.WHEEL.minSpeed then return 0 end
    local w = M.WHEEL
    local frac = clamp(speed / t.speed, 0, w.speedSlack)
    local c = w.baseChance * frac * frac
    if p.offRoad == true then c = c * w.offRoadMult end
    c = c * (1 + w.loadMult * clamp(num(p.loadFraction) or 0, 0, 1))
    return clamp(c, 0, 1)
end

---Roll once. rng() returns a float in [0,1) (math.random in production, injected in specs). true = wheel breaks.
function M.rollWheelBreak(p, rng)
    if type(rng) ~= 'function' then return false end
    local c = M.breakChance(p)
    if c <= 0 then return false end
    return rng() < c
end

---Speed cap (m/s): the load-adjusted tier cap, cut further while a wheel is broken.
function M.effectiveSpeedLimit(tierKey, weight, broken)
    local lim = M.speedLimit(tierKey, weight)
    if not lim then return nil end
    if broken then lim = lim * M.WHEEL.brokenSpeedMult end
    return lim
end

---Spike gate (convar fh_spike_gated, fh_core/docs/spike-gated.md): gated = broken state + speed cap only; the native
---wheel break runs only when ungated. Anything but an explicit false counts as gated.
function M.nativeBreakAllowed(gated) return gated == false end

---Can this player start repairing? p = { citizenid, playerCoords, wagon = { id, owner, tier, coords, broken },
---hasHammer, hasWheel, reach? }. Checks only.
---@return boolean ok, string|nil reason
function M.planRepair(p)
    if type(p) ~= 'table' then return false, 'fh_bad_request' end
    local ok, why = M.canUseWagon(p.wagon, p.citizenid, p.playerCoords, p.reach)
    if not ok then return false, why end
    if p.wagon.broken ~= true then return false, 'fh_wheel_ok' end
    if not p.hasHammer then return false, 'fh_need_hammer' end
    if not p.hasWheel then return false, 'fh_not_enough' end
    return true
end

---Progress of a running repair. s = { startedAt, duration (ms), startCoords }, now in ms.
---Optional wagonCoords (+ reach): cancels when the wagon is no longer in reach of the player.
---@return string state 'continue'|'done'|'cancel', string|nil reason
function M.repairStep(s, now, playerCoords, wagonCoords, reach)
    local moved = within(s.startCoords, playerCoords, M.WHEEL.repairMoveMax)
    if moved == nil then return 'cancel', 'fh_no_player_coords' end
    if not moved then return 'cancel', 'fh_moved' end
    if wagonCoords ~= nil and not within(wagonCoords, playerCoords, reach or M.DEFAULT_REACH) then
        return 'cancel', 'fh_out_of_reach'
    end
    if now - s.startedAt >= s.duration then return 'done' end
    return 'continue'
end

---Final re-check on the repair done tick, before consuming anything. c = { broken, wagonCoords, hasHammer, hasWheel }.
---@return boolean ok, string|nil reason
function M.repairFinalCheck(c)
    if type(c) ~= 'table' then return false, 'fh_bad_request' end
    if c.wagonCoords == nil then return false, 'fh_no_wagon' end -- wagon gone/unloaded: cancel, consume nothing
    if c.broken ~= true then return false, 'fh_wheel_ok' end
    if not c.hasHammer then return false, 'fh_need_hammer' end
    if not c.hasWheel then return false, 'fh_not_enough' end
    return true
end

---What the owner's client does with a wheel_state message st = { broken, speedLimit, native }.
---native (= fh_spike_gated is false) gates every wheel native: the break and SET_VEHICLE_FIXED. The speed cap is
---not a wheel native, so it applies (and is reset on repair) in both modes.
---@return table plan { cap = number|nil, resetCap = boolean, breakNative = boolean, fixNative = boolean }
function M.clientWheelPlan(st)
    local broken = type(st) == 'table' and st.broken == true
    local native = type(st) == 'table' and st.native == true
    return {
        cap = broken and tonumber(st.speedLimit) or nil,
        resetCap = not broken,
        breakNative = broken and native,
        fixNative = (not broken) and native,
    }
end

---First of `refs` whose snapshot (snaps[i], slot -> { name, amount }) holds `amount` of `item`, else nil.
function M.findHolder(refs, snaps, item, amount)
    amount = int(amount)
    if not amount or amount < 1 then return nil end
    for i, r in ipairs(refs or {}) do
        local n = 0
        for _, it in pairs(snaps and snaps[i] or {}) do
            if it.name == item then n = n + (int(it.amount) or 0) end
        end
        if n >= amount then return r end
    end
end

if GetCurrentResourceName then
    FhCargoRules = M
else
    return M
end

-- Survival needs logic (plan survival-01, block S1). Pure Lua: no FiveM/RedM globals, no health values.
-- Needs are positive timed buffs; sluggish is derived from what is missing and is never lethal.
-- `snapshot` has the fh_buffs get() shape: { [buff_id] = { magnitude, expires_at } }. Times are seconds.
local N = {}

-- Fixed evaluation order.
N.NEEDS = { 'food', 'water', 'rest', 'clean', 'warmth' }

N.NEED_BUFF = { food = 'well_fed', water = 'hydrated', rest = 'rested', clean = 'clean', warmth = 'warm' }

-- Needs that always count; warmth only counts in cold regions.
N.CORE_NEEDS = { 'food', 'water', 'rest', 'clean' }

N.DEFAULT_DURATIONS = { well_fed = 3600, hydrated = 2700, rested = 7200, clean = 5400, warm = 1200 }

N.DEFAULT_LEVEL_MAP = { [0] = 0, 1, 2, 3 } -- missing count -> level; counts above the last entry use the last
N.DEFAULT_GRACE = 600
N.DEFAULT_MAGNITUDE_CAP = 1.20
N.DEFAULT_COMFORT_K = 0.01
N.DEFAULT_CANTEEN_MAX = 5

local function isNum(v) return type(v) == 'number' and v == v and v ~= math.huge and v ~= -math.huge end

---Duration table with defaults filled in for any missing/invalid entry.
function N.durations(cfg)
    local out = {}
    for id, d in pairs(N.DEFAULT_DURATIONS) do
        local v = type(cfg) == 'table' and cfg[id]
        out[id] = (isNum(v) and v > 0) and v or d
    end
    return out
end

---Needs that are missing at `now`. food/water/rest/clean always count; warmth only when
---`regionId` is a key (or list value) of `coldRegions`. expires_at <= now counts as missing.
---A non-number / NaN / infinite `now` cannot prove anything is active, so every counted need is missing.
---@return string[] missing need names, in N.NEEDS order
function N.missingNeeds(snapshot, now, regionId, coldRegions)
    snapshot = type(snapshot) == 'table' and snapshot or {}
    local cold = false
    if regionId ~= nil and type(coldRegions) == 'table' then
        cold = coldRegions[regionId] == true
        if not cold then
            for _, r in ipairs(coldRegions) do if r == regionId then cold = true break end end
        end
    end
    local nowOk = isNum(now)
    local out = {}
    for _, need in ipairs(N.NEEDS) do
        if need ~= 'warmth' or cold then
            local e = snapshot[N.NEED_BUFF[need]]
            local active = nowOk and type(e) == 'table' and isNum(e.expires_at) and e.expires_at > now
            if not active then out[#out + 1] = need end
        end
    end
    return out
end

---Sluggish level 0-3 from a missing count. `levelMap` is { [0]=0, 1, 2, 3 } style; counts past
---the highest key use the highest key's level. Result is always clamped to 0..3.
function N.sluggishLevel(missingCount, levelMap)
    levelMap = type(levelMap) == 'table' and levelMap or N.DEFAULT_LEVEL_MAP
    if not isNum(missingCount) or missingCount < 0 then return 0 end
    missingCount = math.floor(missingCount)
    local v = levelMap[missingCount]
    if v == nil then
        local top = -1
        for k in pairs(levelMap) do if isNum(k) and k > top and k <= missingCount then top = k end end
        v = top >= 0 and levelMap[top] or 0
    end
    if not isNum(v) then return 0 end
    return math.max(0, math.min(3, math.floor(v)))
end

---Login grace: a character with no saved needs row is exempt for `grace` seconds after login.
---Non-number / NaN / negative `grace` falls back to DEFAULT_GRACE.
function N.inGrace(hasRow, loginAt, now, grace)
    if hasRow then return false end
    if not isNum(loginAt) or not isNum(now) then return false end
    grace = (isNum(grace) and grace >= 0) and grace or N.DEFAULT_GRACE
    return now - loginAt < grace
end

---One-call evaluation.
---opts: { regionId, coldRegions, levelMap, hasRow, loginAt, grace }
---@return integer level, string[] missing
function N.evaluate(snapshot, now, opts)
    opts = opts or {}
    local missing = N.missingNeeds(snapshot, now, opts.regionId, opts.coldRegions)
    if N.inGrace(opts.hasRow, opts.loginAt, now, opts.grace) then return 0, missing end
    return N.sluggishLevel(#missing, opts.levelMap), missing
end

---Rested magnitude: 1.0 + comfort*k, clamped to `cap`. Bedroll (no comfort) = 1.0.
---Non-number / negative / NaN comfort counts as 0.
function N.restedMagnitude(comfort, k, cap)
    if not isNum(comfort) or comfort < 0 then comfort = 0 end
    k = (isNum(k) and k >= 0) and k or N.DEFAULT_COMFORT_K
    cap = (isNum(cap) and cap >= 1) and cap or N.DEFAULT_MAGNITUDE_CAP
    return math.min(1.0 + comfort * k, cap)
end

---Use one canteen charge. @return boolean ok, integer|string newCharges or error code
function N.canteenUse(charges)
    if not isNum(charges) or charges ~= math.floor(charges) or charges < 0 then return false, 'invalid_charges' end
    if charges == 0 then return false, 'empty' end
    return true, charges - 1
end

---Refill to `max`. @return boolean ok, integer|string newCharges or error code
function N.canteenRefill(charges, max)
    if max == nil then max = N.DEFAULT_CANTEEN_MAX end
    if not isNum(max) or max ~= math.floor(max) or max < 1 then return false, 'invalid_max' end
    if not isNum(charges) or charges ~= math.floor(charges) or charges < 0 or charges > max then
        return false, 'invalid_charges'
    end
    if charges == max then return false, 'full' end
    return true, max
end

---Save: remaining seconds + magnitude per need at `now` (only needs still active).
---@return table<string, {remaining:number, magnitude:number}> keyed by need name
function N.saveRemaining(snapshot, now)
    local out = {}
    if type(snapshot) ~= 'table' or not isNum(now) then return out end
    for _, need in ipairs(N.NEEDS) do
        local e = snapshot[N.NEED_BUFF[need]]
        if type(e) == 'table' and isNum(e.expires_at) and isNum(e.magnitude) and e.magnitude > 0 then
            local rem = e.expires_at - now
            if rem > 0 then out[need] = { remaining = rem, magnitude = e.magnitude } end
        end
    end
    return out
end

---Restore: list of { buff_id, magnitude, duration } to re-apply. duration = min(saved remaining,
---configured max duration); zero/negative/invalid entries are dropped. Never extends past saved.
---@param durationCfg table? per-buff max durations (defaults filled in)
function N.restore(saved, durationCfg)
    local out = {}
    if type(saved) ~= 'table' then return out end
    local max = N.durations(durationCfg)
    for _, need in ipairs(N.NEEDS) do
        local s = saved[need]
        local id = N.NEED_BUFF[need]
        if type(s) == 'table' and isNum(s.remaining) and s.remaining > 0 and isNum(s.magnitude) and s.magnitude > 0 then
            out[#out + 1] = { buff_id = id, magnitude = s.magnitude, duration = math.min(s.remaining, max[id]) }
        end
    end
    return out
end

---Has the client-visible state changed? `prev` = { level, missing } or nil; missing is compared in order.
function N.stateChanged(prev, level, missing)
    if type(prev) ~= 'table' or prev.level ~= level then return true end
    local pm = prev.missing or {}
    if #pm ~= #missing then return true end
    for i = 1, #missing do if pm[i] ~= missing[i] then return true end end
    return false
end

---Which snapshot to save on drop: the live one if it still has entries, else the last cached tick
---snapshot (fh_buffs may already have cleared its state when playerDropped reaches us). Cached
---entries are re-filtered by saveRemaining against `now`, so expired ones are never saved.
function N.pickSnapshot(live, cached)
    if type(live) == 'table' and next(live) ~= nil then return live end
    return type(cached) == 'table' and cached or {}
end

-- FXServer loads shared scripts as plain chunks; expose a global there, module under specs.
if _G.GetCurrentResourceName then _G.FhSurvivalNeeds = N end
return N

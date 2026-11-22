-- Buff stacking rules, defined ONCE (spec 4.5). Pure Lua, no natives; unit-tested.
--
-- Rules:
--   * Different buff ids stack (they coexist in the same state table).
--   * The same buff id (while still active) refreshes: expires_at = now + duration (it never
--     accumulates), and magnitude = max(old, new), both after the per-buff cap.
--   * Magnitude is capped per buff id (caps[buff_id]); unknown buff ids are refused.
--   * Expired entries are dropped by expire()/get().
-- `state` is a per-player table { [buff_id] = { magnitude, expires_at } }. Times are in seconds.
local logic = {}

---@param caps table<string, number> magnitude cap per known buff id
---@return boolean ok, string? err
function logic.validate(caps, buff_id, magnitude, duration)
    if type(buff_id) ~= 'string' or caps[buff_id] == nil then return false, 'unknown_buff' end
    if type(magnitude) ~= 'number' or magnitude ~= magnitude or magnitude <= 0 or magnitude == math.huge then
        return false, 'invalid_magnitude'
    end
    if type(duration) ~= 'number' or duration ~= duration or duration <= 0 or duration == math.huge then
        return false, 'invalid_duration'
    end
    return true
end

---Apply a buff to `state` in place.
---@return boolean ok, table|string result entry on success ({ magnitude, expires_at, refreshed }) or error code
function logic.apply(state, caps, buff_id, magnitude, duration, now)
    local ok, err = logic.validate(caps, buff_id, magnitude, duration)
    if not ok then return false, err end
    local mag = math.min(magnitude, caps[buff_id])
    local cur = state[buff_id]
    local refreshed = false
    if cur and cur.expires_at > now then
        refreshed = true
        if cur.magnitude > mag then mag = cur.magnitude end
    end
    local entry = { magnitude = mag, expires_at = now + duration }
    state[buff_id] = entry
    return true, { magnitude = entry.magnitude, expires_at = entry.expires_at, refreshed = refreshed }
end

---Remove expired entries. Returns the list of expired buff ids (sorted).
function logic.expire(state, now)
    local gone = {}
    for id, e in pairs(state) do
        if e.expires_at <= now then gone[#gone + 1] = id end
    end
    table.sort(gone)
    for _, id in ipairs(gone) do state[id] = nil end
    return gone
end

---Snapshot of active buffs: { [buff_id] = { magnitude, expires_at } } (expired entries dropped first).
function logic.snapshot(state, now)
    logic.expire(state, now)
    local out = {}
    for id, e in pairs(state) do out[id] = { magnitude = e.magnitude, expires_at = e.expires_at } end
    return out
end

if _G.GetCurrentResourceName then _G.FhBuffLogic = logic end
return logic

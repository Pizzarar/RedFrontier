-- Pure decision logic for client-side ground snapping (world-01 block D). No natives, so busted can load it.
-- The thin native probe lives in fh_core/client/ground_snap.lua; this module only decides retry / fallback /
-- once-per-id logging. A client probes the ground height at a place's (x, y, z-hint) and, once the area has
-- streamed in, snaps z to the real ground; on failure it falls back to the z-hint and logs `fh:world:unsnapped <id>`
-- exactly once per id.
local M = {}

M.PROBE_ABOVE = 20.0      -- metres above the z-hint to start the probe (places: chests/camps)
M.SPAWN_PROBE_ABOVE = 1.5 -- metres above the requested z for entity spawns: probe down only (never a roof/upper floor)
M.RETRY_MS = 50           -- ms between probe attempts
M.TIMEOUT_MS = 2000       -- ms total probe budget before falling back
M.MAX_RETRIES = 40        -- attempts before giving up (== TIMEOUT_MS / RETRY_MS)

---True when n is a finite number (not NaN, not ±math.huge).
local function finite(n)
    return type(n) == 'number' and n == n and n > -math.huge and n < math.huge
end

---True when a probe result is a usable ground height (truthy found + a finite number).
---@return boolean
function M.usable(found, groundZ)
    if not found then return false end
    return finite(groundZ)
end

---The snapped z: groundZ when usable, else the hint z (the fallback).
function M.resolve(found, groundZ, hintZ)
    if M.usable(found, groundZ) then return groundZ end
    return hintZ
end

M.SNAP_TOLERANCE = 10.0 -- metres: a probed ground z this far (or farther) from the request is rejected

---Snap requestedZ to a probed groundZ only when both are finite and within ±tolerance (protects interiors/roofs and
---other spawn-contract callers); otherwise keep requestedZ. NaN / ±math.huge / missing inputs keep the request.
function M.snapZ(requestedZ, groundZ, tolerance)
    if not finite(requestedZ) or not finite(groundZ) then return requestedZ end
    local tol = (type(tolerance) == 'number' and tolerance) or M.SNAP_TOLERANCE
    if math.abs(groundZ - requestedZ) <= tol then return groundZ end
    return requestedZ
end

---True unless the request opts out (snap == false). Absent or any non-false value snaps (default true).
---@return boolean
function M.wantsSnap(snap)
    return snap ~= false
end

---Keep probing after a failed attempt? attempt is the attempt just made (1-based). Gives up at maxRetries
---(default M.MAX_RETRIES) or at the deadline (ms, optional).
---@return boolean
function M.shouldRetry(attempt, maxRetries, now, deadline)
    if type(attempt) ~= 'number' then return false end
    local max = (type(maxRetries) == 'number' and maxRetries) or M.MAX_RETRIES
    if attempt >= max then return false end
    if deadline ~= nil and now ~= nil and now >= deadline then return false end
    return true
end

-- Once-per-id "unsnapped" logging.
M.unsnapped = {}

---Mark an id as logged. Returns true exactly once per id (until reset()), so the caller logs once.
---@return boolean
function M.markUnsnapped(id)
    if type(id) ~= 'string' or id == '' then return false end
    if M.unsnapped[id] then return false end
    M.unsnapped[id] = true
    return true
end

---Clear the once-per-id log (used by specs; production never resets).
function M.reset() M.unsnapped = {} end

-- FXServer loads shared scripts as plain chunks; expose a global there, module under busted.
if _G.GetCurrentResourceName then _G.FhGroundSnap = M end
return M

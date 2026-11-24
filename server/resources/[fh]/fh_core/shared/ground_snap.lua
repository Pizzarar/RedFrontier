-- Pure decision logic for client-side ground snapping (world-01 block D). No natives, so busted can load it.
-- The thin native probe lives in fh_core/client/ground_snap.lua; this module only decides retry / fallback /
-- once-per-id logging. A client probes the ground height at a place's (x, y, z-hint) and, once the area has
-- streamed in, snaps z to the real ground; on failure it falls back to the z-hint and logs `fh:world:unsnapped <id>`
-- exactly once per id.
local M = {}

M.PROBE_ABOVE = 20.0 -- metres above the z-hint to start the probe (an unstreamed area reads low)
M.RETRY_MS = 50      -- ms between probe attempts
M.TIMEOUT_MS = 2000  -- ms total probe budget before falling back
M.MAX_RETRIES = 40   -- attempts before giving up (== TIMEOUT_MS / RETRY_MS)

---True when a probe result is a usable ground height (truthy found + a finite number).
---@return boolean
function M.usable(found, groundZ)
    if not found then return false end
    return type(groundZ) == 'number' and groundZ == groundZ
end

---The snapped z: groundZ when usable, else the hint z (the fallback).
function M.resolve(found, groundZ, hintZ)
    if M.usable(found, groundZ) then return groundZ end
    return hintZ
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

-- Pure roadblock / ambush / chase decisions (spec L7/M5, roads R6). No natives; specced in spec/roadblock_rules_spec.lua.
-- The server file (server/roadblocks.lua) only feeds it state and acts on the answers.
-- Times are seconds (any monotonic clock the caller picks). Coordinates are { x, y, z }.
local M = {}

local function finite(n) return type(n) == 'number' and n == n and n > -math.huge and n < math.huge end

---Convar string -> boolean; unknown/empty gives the default (same rule as fh_core spawn_rules.parseFlag).
function M.parseFlag(s, default)
    s = tostring(s or ''):lower()
    if s == 'true' or s == '1' or s == 'yes' or s == 'on' then return true end
    if s == 'false' or s == '0' or s == 'no' or s == 'off' then return false end
    return default
end

---Rank of a threshold level name (1 = lowest), or 0 for nil / unknown.
function M.rank(thresholds, name)
    if name == nil then return 0 end
    for i, t in ipairs(thresholds or {}) do if t.name == name then return i end end
    return 0
end

---Did the level RISE onto or past minLevel? (old_level/level come from fh:heat:threshold.)
function M.crossedUp(thresholds, oldLevel, newLevel, minLevel)
    local min = M.rank(thresholds, minLevel)
    if min == 0 then return false end
    return M.rank(thresholds, newLevel) >= min and M.rank(thresholds, oldLevel) < min
end

---Is the level at or above minLevel right now?
function M.atLeast(thresholds, level, minLevel)
    local min = M.rank(thresholds, minLevel)
    return min > 0 and M.rank(thresholds, level) >= min
end

local function dist2(a, x, y)
    local dx, dy = a.x - x, a.y - y
    return dx * dx + dy * dy
end

---Nearest chokepoint to (x, y). Prefers ones in `region` when any exist there (the player's region), else all.
---maxDistance (optional) drops anything farther than that from the player.
---@return table|nil chokepoint, string|nil err
function M.pickChokepoint(chokepoints, region, x, y, maxDistance)
    if not finite(x) or not finite(y) then return nil, 'fh_bad_coords' end
    local function nearest(filter)
        local best, bestD
        for _, c in ipairs(chokepoints or {}) do
            if c.coords and finite(c.coords.x) and finite(c.coords.y) and filter(c) then
                local d = dist2(c.coords, x, y)
                if not bestD or d < bestD or (d == bestD and tostring(c.id) < tostring(best.id)) then best, bestD = c, d end
            end
        end
        return best, bestD
    end
    local best, d
    if region then best, d = nearest(function(c) return c.region == region end) end
    if not best then best, d = nearest(function() return true end) end
    if not best then return nil, 'fh_no_chokepoint' end
    if finite(maxDistance) and d > maxDistance * maxDistance then return nil, 'fh_chokepoint_too_far' end
    return best
end

---Key for one live roadblock per player + faction.
function M.key(citizenid, faction) return tostring(citizenid) .. '\0' .. tostring(faction) end

---May a roadblock spawn now? s = { liveKey = bool, liveCount, lastAt = seconds|nil, now, cooldown, maxConcurrent }
---@return boolean ok, string|nil reason  ('already_live' | 'cooldown' | 'max_concurrent')
function M.canSpawn(s)
    if s.liveKey then return false, 'already_live' end
    if s.lastAt and finite(s.cooldown) and s.now - s.lastAt < s.cooldown then return false, 'cooldown' end
    if finite(s.maxConcurrent) and (s.liveCount or 0) >= s.maxConcurrent then return false, 'max_concurrent' end
    return true
end

---Should a live roadblock go? rb = { expiresAt }; heatLevel = the player's CURRENT level for that faction (nil = none);
---online = player still connected. Returns a reason or nil to keep it.
function M.clearReason(rb, now, thresholds, heatLevel, minLevel, online)
    if online == false then return 'player_dropped' end
    if rb.expiresAt and now >= rb.expiresAt then return 'expired' end
    if not M.atLeast(thresholds, heatLevel, minLevel) then return 'heat_dropped' end
    return nil
end

---Peds of a roadblock: a line across the road through the chokepoint, `spacing` metres apart, centred on it.
---The line runs perpendicular to the heading (heading = direction the road runs, degrees, GTA convention).
---@return table[] list of { model, weapon, x, y, z, heading, index }
function M.pedPlan(fcfg, choke, spacing)
    if type(fcfg) ~= 'table' or not fcfg.model or not choke or not choke.coords then return {} end
    local n = math.floor(finite(fcfg.count) and fcfg.count or 0)
    if n < 1 then return {} end
    spacing = finite(spacing) and spacing or 2.5
    local h = choke.heading or 0.0
    local rad = math.rad(h)
    -- unit vector of the road direction in world coords (heading 0 = +y, increasing counter-clockwise)
    local rx, ry = -math.sin(rad), math.cos(rad)
    local px, py = ry, -rx -- perpendicular
    local out = {}
    for i = 1, n do
        local off = (i - (n + 1) / 2) * spacing
        out[i] = { model = fcfg.model, weapon = fcfg.weapon, index = i,
            x = choke.coords.x + px * off, y = choke.coords.y + py * off, z = choke.coords.z,
            heading = (h + 180.0) % 360.0 } -- face oncoming traffic
    end
    return out
end

---Night window [from, to) in game hours (0-23); wraps midnight when from > to.
function M.isNight(hour, from, to)
    if not finite(hour) or not finite(from) or not finite(to) then return false end
    if from == to then return false end
    if from < to then return hour >= from and hour < to end
    return hour >= from or hour < to
end

---Ring of points around (x, y) for an ambush, evenly spaced from startDeg, `radius` away.
function M.ringPlan(fcfg, x, y, z, radius, startDeg)
    if type(fcfg) ~= 'table' or not fcfg.model or not finite(x) or not finite(y) then return {} end
    local n = math.floor(finite(fcfg.count) and fcfg.count or 0)
    if n < 1 then return {} end
    radius = finite(radius) and radius or 60.0
    local out = {}
    for i = 1, n do
        local a = math.rad((startDeg or 0) + (i - 1) * 360.0 / n)
        local px, py = x + math.cos(a) * radius, y + math.sin(a) * radius
        -- face the centre (heading 0 = +y, counter-clockwise)
        local hd = math.deg(math.atan(-(x - px), y - py))
        out[i] = { model = fcfg.model, weapon = fcfg.weapon, index = i, x = px, y = py, z = z or 0.0,
            heading = hd % 360.0 }
    end
    return out
end

---What may the night ambush / mounted chase do? Both sit behind fh_spike_gated (S2 spk_chase).
---Gated = no-op with a log line. Ungated = the plan to run when its own conditions hold.
---@return table { run = bool, log = string|nil }
function M.gatedPlan(gated, what)
    if gated then
        return { run = false, log = ('%s skipped: fh_spike_gated=true (waiting on S2 spk_chase RESULT)'):format(what) }
    end
    return { run = true }
end

---Chase mount order, once per rider/horse pair. Call from BOTH onReady callbacks: returns true exactly once, when
---pair.rider and pair.horse are both set and the group is still live (rider-first and horse-first both work).
function M.claimMount(pair, live)
    if not live or pair.sent or not pair.rider or not pair.horse then return false end
    pair.sent = true
    return true
end

---Ambush decision (ungated only). cfg = FhHeatConfig.ambush; returns ok, reason.
---s = { gated, level, thresholds, hour, now, lastAt, liveKey }
function M.ambushDecision(cfg, s)
    local g = M.gatedPlan(s.gated, 'night ambush')
    if not g.run then return false, 'gated', g.log end
    if not cfg or cfg.enabled == false then return false, 'disabled' end
    if not M.atLeast(s.thresholds, s.level, cfg.minLevel) then return false, 'below_threshold' end
    if not M.isNight(s.hour, cfg.nightFrom, cfg.nightTo) then return false, 'not_night' end
    if s.liveKey then return false, 'already_live' end
    if s.lastAt and s.now - s.lastAt < (cfg.cooldownSeconds or 0) then return false, 'cooldown' end
    return true
end

---Chase decision (ungated only). cfg = FhHeatConfig.chase. The player must be on a wagon/horse (s.mounted).
function M.chaseDecision(cfg, s)
    local g = M.gatedPlan(s.gated, 'mounted chase')
    if not g.run then return false, 'gated', g.log end
    if not cfg or cfg.enabled == false then return false, 'disabled' end
    if not M.atLeast(s.thresholds, s.level, cfg.minLevel) then return false, 'below_threshold' end
    if not s.mounted then return false, 'not_mounted' end
    if s.liveKey then return false, 'already_live' end
    if s.lastAt and s.now - s.lastAt < (cfg.cooldownSeconds or 0) then return false, 'cooldown' end
    return true
end

if GetCurrentResourceName then
    FhRoadblockRules = M
else
    return M
end

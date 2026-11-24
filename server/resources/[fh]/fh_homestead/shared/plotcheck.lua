-- fh_homestead /fh_plotcheck (homestead-03 H16): pure math for the admin plot check. No natives, specced under busted
-- (spec/plotcheck_spec.lua). The client probe (ground z, water) and the server command live in client/main.lua and
-- server/plotcheck.lua; this module only measures, classifies and formats.
local M = {}

M.Z_OK = 2.0                 -- metres: |ground - config z| up to this is "ok"
M.Z_WARN = 10.0              -- == FhGroundSnap.SNAP_TOLERANCE: beyond it the snap is REJECTED and the chest uses the config z
M.WATER_MARGIN = 0.25        -- metres the water surface must sit above ground to count as "water at center"
M.TIMEOUT_BASE_MS = 8000     -- server waits this long for the client report, plus PER_PLOT_MS per plot
M.PER_PLOT_MS = 3000         -- the probe itself gives up after 2000 ms (FhGroundSnap.TIMEOUT_MS) plus the water read

local function finite(n) return type(n) == 'number' and n == n and n > -math.huge and n < math.huge end

local function xy(c)
    local ok, x, y = pcall(function() return c.x, c.y end)
    if ok and finite(x) and finite(y) then return x, y end
    return nil
end

---Horizontal (2D) distance between two {x,y} like positions, nil when either is unusable.
function M.dist2d(a, b)
    local ax, ay = xy(a)
    local bx, by = xy(b)
    if not ax or not bx then return nil end
    return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2)
end

---Largest radius a plot's area can reach: a claim = max(plot.radius, baseSafeRadius) plus the biggest safeRadiusBonus of
---every slot (the fence, once built); a town lot = exactly plot.radius (no base, no fence; see build_rules.safeRadiusFor).
function M.maxRadius(plot, baseSafeRadius)
    if type(plot) ~= 'table' then return 0 end
    local r = finite(plot.radius) and plot.radius or 0
    if plot.class == 'town_lot' then return r end
    local base = r
    if finite(baseSafeRadius) and baseSafeRadius > base then base = baseSafeRadius end
    local bonus = 0
    for _, slot in pairs(plot.slots or {}) do
        local best = 0
        for _, tier in pairs(type(slot) == 'table' and slot.tiers or {}) do
            local b = type(tier) == 'table' and type(tier.unlocks) == 'table' and tier.unlocks.safeRadiusBonus
            if finite(b) and b > best then best = b end
        end
        bonus = bonus + best
    end
    return base + bonus
end

local function sortedIds(plots)
    local ids = {}
    for id in pairs(plots or {}) do ids[#ids + 1] = id end
    table.sort(ids)
    return ids
end

---Every other plot/lot whose max-radius circle intersects plots[id]'s. Returns a sorted list of
---{ id, dist, limit } (dist = centre distance, limit = r1 + r2; overlap when dist < limit). Touching is not overlap.
function M.overlaps(plots, id, baseSafeRadius)
    local me = plots and plots[id]
    if type(me) ~= 'table' then return {} end
    local r1 = M.maxRadius(me, baseSafeRadius)
    local out = {}
    for _, other in ipairs(sortedIds(plots)) do
        if other ~= id and type(plots[other]) == 'table' then
            local d = M.dist2d(me.center, plots[other].center)
            local limit = r1 + M.maxRadius(plots[other], baseSafeRadius)
            if d and d < limit then out[#out + 1] = { id = other, dist = d, limit = limit } end
        end
    end
    return out
end

---Nearest town among regions (FhRegions.regions: each region has towns = { {id,label,x,y} }). Returns
---{ id, label, dist } or nil when no town has usable coordinates (the caller omits the line). There is no road data
---in the repo, so towns are the only reference.
function M.nearestTown(center, regions)
    local best
    local rids = sortedIds(regions)
    for _, rid in ipairs(rids) do
        for _, t in ipairs(type(regions[rid]) == 'table' and regions[rid].towns or {}) do
            local d = M.dist2d(center, t)
            if d and (not best or d < best.dist) then best = { id = t.id, label = t.label or t.id, dist = d } end
        end
    end
    return best
end

---Classify the ground probe vs the config z. found = the probe really hit ground (not the hint fallback).
---Returns kind, delta: 'no_ground' (probe timed out: area not streamed, stand near it), 'ok' (<= Z_OK),
---'warn' (<= Z_WARN: the snap corrects it), 'bad' (> Z_WARN: the snap is rejected, props sit at the config z).
function M.classifyZ(configZ, groundZ, found)
    if not found or not finite(groundZ) or not finite(configZ) then return 'no_ground', nil end
    local delta = groundZ - configZ
    local a = math.abs(delta)
    if a <= M.Z_OK then return 'ok', delta end
    if a <= M.Z_WARN then return 'warn', delta end
    return 'bad', delta
end

---Water at the plot centre: waterZ (surface height, nil = none/unknown native) above the ground (or the config z when
---there is no ground) by more than WATER_MARGIN.
function M.isWater(waterZ, groundZ, configZ)
    if not finite(waterZ) then return false end
    local ref = finite(groundZ) and groundZ or configZ
    if not finite(ref) then return false end
    return waterZ > ref + M.WATER_MARGIN
end

---Targets for a command argument: nil/''/'all' = every plot (sorted), a known id = that plot, else nil, 'unknown_plot'.
function M.targets(plots, arg)
    if type(arg) ~= 'string' or arg == '' or arg == 'all' then return sortedIds(plots) end
    if type(plots) == 'table' and plots[arg] then return { arg } end
    return nil, 'unknown_plot'
end

---Keep only well-formed client results: { id, groundZ?, found?, waterZ?, waterKnown? }. Unknown ids and garbage dropped.
function M.cleanResults(plots, raw)
    local out = {}
    if type(raw) ~= 'table' then return out end
    for _, r in pairs(raw) do
        if type(r) == 'table' and type(r.id) == 'string' and plots[r.id] and not out[r.id] then
            out[r.id] = {
                found = r.found == true,
                groundZ = finite(r.groundZ) and r.groundZ or nil,
                waterZ = finite(r.waterZ) and r.waterZ or nil,
                waterKnown = r.waterKnown == true,
            }
        end
    end
    return out
end

---One report per plot (severity: 'fail' = bad z / water / overlap / no report, 'warn' = z snap corrects it or ground not found, 'ok'): { id, line = {strings}, flags = n }. res = cleaned client result (may be nil = no report).
function M.report(plots, id, res, opts)
    opts = opts or {}
    local p = plots[id]
    local cz = p.center and p.center.z
    local head = ('%s [%s%s]'):format(id, p.class or 'claim', p.verified == false and ', unverified' or '')
    local lines, flags, fail = {}, 0, false
    if not res then
        lines[#lines + 1] = 'ground: no report from the client'
        flags = flags + 1
        fail = true
    else
        local kind, delta = M.classifyZ(cz, res.groundZ, res.found)
        if kind == 'no_ground' then
            lines[#lines + 1] = ('ground: NOT FOUND (area not streamed in; stand near it and re-run). config z %.1f'):format(cz or 0 / 0)
            flags = flags + 1
        else
            local tag = kind == 'ok' and 'OK' or (kind == 'warn' and 'WARN snap corrects' or 'BAD snap rejected, props sit at config z')
            lines[#lines + 1] = ('ground z %.1f vs config z %.1f (%+.1f) %s'):format(res.groundZ, cz, delta, tag)
            if kind ~= 'ok' then flags = flags + 1 end
            if kind == 'bad' then fail = true end
        end
        if not res.waterKnown then
            lines[#lines + 1] = 'water: unknown (native unavailable)'
        elseif M.isWater(res.waterZ, res.groundZ, cz) then
            lines[#lines + 1] = ('water at center: YES (surface %.1f) BAD'):format(res.waterZ)
            flags = flags + 1
            fail = true
        else
            lines[#lines + 1] = 'water at center: no'
        end
    end
    local ov = M.overlaps(plots, id, opts.baseSafeRadius)
    if #ov == 0 then
        lines[#lines + 1] = ('overlap at max radius (%.0f m): none'):format(M.maxRadius(p, opts.baseSafeRadius))
    else
        local parts = {}
        for _, o in ipairs(ov) do parts[#parts + 1] = ('%s (%.0f m apart, limit %.0f)'):format(o.id, o.dist, o.limit) end
        lines[#lines + 1] = ('overlap at max radius (%.0f m): %s BAD'):format(M.maxRadius(p, opts.baseSafeRadius), table.concat(parts, ', '))
        flags = flags + 1
        fail = true
    end
    if opts.regions then
        local t = M.nearestTown(p.center, opts.regions)
        if t then lines[#lines + 1] = ('nearest town: %s %.0f m (no road data in repo)'):format(t.label, t.dist) end
    end
    return { id = id, head = head, lines = lines, flags = flags, severity = fail and 'fail' or (flags > 0 and 'warn' or 'ok') }
end

---Worst-case wait for a run: every plot can burn the whole 2 s ground probe (an unstreamed plot always does).
function M.etaSeconds(n)
    return math.ceil((finite(n) and n or 0) * 2.0)
end

---Capped in-game summary of many reports (the full blocks go to the server console only): { counts line, problem line? }.
---Problem plots list fail before warn, sorted by id within each, at most maxList ids, then "+N more".
function M.summary(reports, maxList)
    local cap = (finite(maxList) and maxList >= 0) and maxList or 8
    local n = { ok = 0, warn = 0, fail = 0 }
    local fails, warns = {}, {}
    for _, r in ipairs(reports or {}) do
        local sev = r.severity == 'fail' and 'fail' or (r.severity == 'warn' and 'warn' or 'ok')
        n[sev] = n[sev] + 1
        if sev == 'fail' then fails[#fails + 1] = r.id elseif sev == 'warn' then warns[#warns + 1] = r.id end
    end
    table.sort(fails); table.sort(warns)
    local lines = { ('fh_plotcheck: %d plot(s): %d ok, %d warn, %d fail'):format(n.ok + n.warn + n.fail, n.ok, n.warn, n.fail) }
    local all = {}
    for _, id in ipairs(fails) do all[#all + 1] = id end
    for _, id in ipairs(warns) do all[#all + 1] = id end
    if #all > 0 then
        local shown = {}
        for i = 1, math.min(cap, #all) do shown[i] = all[i] end
        local more = #all > cap and (' +%d more'):format(#all - cap) or ''
        lines[#lines + 1] = ('problems (fail first): %s%s'):format(table.concat(shown, ', '), more)
    end
    return lines
end

if _G.GetCurrentResourceName then _G.FhPlotCheck = M end
return M

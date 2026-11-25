-- Run from repo root: `python tools/run-specs.py spec/ground_snap_spec.lua`.
-- world-01 (block D): the pure ground-snap decision logic (retry / fallback / once-per-id logging). No natives.
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local case = T.it
local G = dofile(here .. '../server/resources/[fh]/fh_core/shared/ground_snap.lua')

case('usable: truthy found + finite number only', function()
    T.eq(true, G.usable(true, 105.0))
    T.eq(true, G.usable(1, 0.0)) -- truthy found (not strictly boolean)
    T.eq(false, G.usable(false, 105.0))
    T.eq(false, G.usable(nil, 105.0))
    T.eq(false, G.usable(true, nil))
    T.eq(false, G.usable(true, 'high'))
    T.eq(false, G.usable(true, 0 / 0))       -- NaN
    T.eq(false, G.usable(true, math.huge))   -- +inf
    T.eq(false, G.usable(true, -math.huge))  -- -inf
end)

case('snapZ: uses the ground z only within tolerance, else keeps the request', function()
    T.eq(108.0, G.snapZ(105.0, 108.0, 10.0)) -- +3 within ±10
    T.eq(95.0, G.snapZ(105.0, 95.0, 10.0))   -- -10 within ±10 (edge)
    T.eq(105.0, G.snapZ(105.0, 116.0, 10.0)) -- +11 outside
    T.eq(105.0, G.snapZ(105.0, 94.0, 10.0))  -- -11 outside
    T.eq(105.0, G.snapZ(105.0, 105.0, 10.0)) -- equal
end)

case('snapZ: non-finite or missing inputs keep the requested z', function()
    T.eq(105.0, G.snapZ(105.0, 0 / 0))      -- groundZ NaN -> keep request
    T.eq(105.0, G.snapZ(105.0, math.huge))  -- groundZ +inf -> keep request
    T.eq(105.0, G.snapZ(105.0, -math.huge)) -- groundZ -inf -> keep request
    T.eq(105.0, G.snapZ(105.0, nil))        -- groundZ missing -> keep request
    T.eq(nil, G.snapZ(nil, 108.0))          -- request missing -> stays nil
    local nan = G.snapZ(0 / 0, 108.0)       -- request NaN -> stays NaN (kept unchanged)
    assert(nan ~= nan)
end)

case('snapZ: defaults to SNAP_TOLERANCE', function()
    T.eq(10.0, G.SNAP_TOLERANCE)
    T.eq(108.0, G.snapZ(105.0, 108.0)) -- within default ±10
    T.eq(105.0, G.snapZ(105.0, 116.0)) -- outside default
end)

case('wantsSnap: snap == false opts out, everything else snaps (default true)', function()
    T.eq(true, G.wantsSnap(true))
    T.eq(true, G.wantsSnap(nil))  -- absent = default
    T.eq(true, G.wantsSnap(1))
    T.eq(false, G.wantsSnap(false))
end)

case('SPAWN_PROBE_ABOVE: spawns probe down from 1.5 m above (never a roof/upper floor)', function()
    T.eq(1.5, G.SPAWN_PROBE_ABOVE)
end)

case('probeAboveFor: town lot / verified place uses the tight downward probe, else the wide probe', function()
    T.eq(G.SPAWN_PROBE_ABOVE, G.probeAboveFor({ class = 'town_lot' }))
    T.eq(G.SPAWN_PROBE_ABOVE, G.probeAboveFor({ verified = true }))
    T.eq(G.SPAWN_PROBE_ABOVE, G.probeAboveFor({ class = 'town_lot', verified = false }))
    T.eq(G.PROBE_ABOVE, G.probeAboveFor({ verified = false }))
    T.eq(G.PROBE_ABOVE, G.probeAboveFor({ class = 'claim' }))
    T.eq(G.PROBE_ABOVE, G.probeAboveFor({}))
    T.eq(G.PROBE_ABOVE, G.probeAboveFor(nil))
end)

case('resolve: groundZ on success, hint on failure', function()
    T.eq(105.0, G.resolve(true, 105.0, 118.0))
    T.eq(118.0, G.resolve(false, nil, 118.0))
    T.eq(118.0, G.resolve(true, 0 / 0, 118.0))
    T.eq(118.0, G.resolve(true, nil, 118.0))
end)

case('shouldRetry: keeps probing until max attempts or the deadline', function()
    T.eq(true, G.shouldRetry(0, 40, 0, 2000))  -- before the first probe
    T.eq(true, G.shouldRetry(1, 40, 0, 2000))
    T.eq(true, G.shouldRetry(39, 40, 0, 2000))
    T.eq(false, G.shouldRetry(40, 40, 0, 2000)) -- attempt == max
    T.eq(false, G.shouldRetry(41, 40, 0, 2000))
    T.eq(false, G.shouldRetry(1, 40, 2000, 2000)) -- now >= deadline
    T.eq(false, G.shouldRetry(nil, 40, 0, 2000))
    T.eq(true, G.shouldRetry(1, nil, 0, nil)) -- defaults to MAX_RETRIES, no deadline
    T.eq(true, G.shouldRetry(39, nil, 0, nil))
    T.eq(false, G.shouldRetry(40, nil, 0, nil))
end)

case('markUnsnapped: logs each id exactly once until reset', function()
    G.reset()
    T.eq(true, G.markUnsnapped('heartlands_01'))
    T.eq(false, G.markUnsnapped('heartlands_01'))
    T.eq(true, G.markUnsnapped('heartlands_02'))
    T.eq(false, G.markUnsnapped('heartlands_02'))
    T.eq(false, G.markUnsnapped(nil))
    T.eq(false, G.markUnsnapped(''))
    G.reset()
    T.eq(true, G.markUnsnapped('heartlands_01'))
end)

-- Static scan: every groundZAt() call in server/resources/[fh] that affects placement/reach must be clamped through
-- FhGroundSnap.snapZ(..., FhGroundSnap.SNAP_TOLERANCE). Only the definition itself and the read-only /fh_plotcheck
-- admin diagnostic (which reports raw ground delta vs config z) are exempt.
local function stripComments(src)
    local out, i, n = {}, 1, #src
    while i <= n do
        local c = src:sub(i, i)
        local cmtEq = src:match('^%-%-%[(=*)%[', i)
        if cmtEq then
            local close = ']' .. cmtEq .. ']'
            local j = src:find(close, i + 2 + #cmtEq, true)
            out[#out + 1] = ' '
            i = j and (j + #close) or (n + 1)
        elseif src:sub(i, i + 1) == '--' then
            local j = src:find('\n', i + 2, true)
            out[#out + 1] = '\n'
            i = j and (j + 1) or (n + 1)
        elseif c == '"' or c == "'" then
            local q, j = c, i + 1
            while j <= n do
                if src:sub(j, j) == '\\' then j = j + 2
                elseif src:sub(j, j) == q then j = j + 1; break
                else j = j + 1 end
            end
            out[#out + 1] = src:sub(i, j - 1)
            i = j
        else
            out[#out + 1] = c
            i = i + 1
        end
    end
    return table.concat(out)
end

local function listFhLua(root)
    local tmp = os.tmpname()
    os.execute("find '" .. root .. "' -name '*.lua' -type f 2>/dev/null > '" .. tmp .. "'")
    local files = {}
    local f = io.open(tmp, 'r')
    if f then
        for line in f:lines() do
            if line:match('%.lua$') then files[#files + 1] = line end
        end
        f:close()
    end
    os.remove(tmp)
    table.sort(files)
    return files
end

local function findMatchingParen(s, openPos)
    local depth = 0
    for i = openPos, #s do
        local ch = s:sub(i, i)
        if ch == '(' then depth = depth + 1
        elseif ch == ')' then
            depth = depth - 1
            if depth == 0 then return i end
        end
    end
    return nil
end

local function blankStrings(src)
    local out, i, n = {}, 1, #src
    while i <= n do
        local c = src:sub(i, i)
        if c == '"' or c == "'" then
            local q, j = c, i + 1
            while j <= n do
                if src:sub(j, j) == '\\' then j = j + 2
                elseif src:sub(j, j) == q then j = j + 1; break
                else j = j + 1 end
            end
            out[#out + 1] = string.rep(' ', j - i)
            i = j
        else
            out[#out + 1] = c
            i = i + 1
        end
    end
    return table.concat(out)
end

local function findLocalFunctionSpan(src, fnName)
    local clean = blankStrings(src)
    local startPos, bodyPos = clean:find('local%s+function%s+' .. fnName .. '%s*%b()%s*')
    if not startPos then return nil, nil end
    local depth = 1
    local pos = bodyPos + 1
    while pos <= #clean do
        local s, e, word = clean:find('(%f[%w_][%a_][%w_]*%f[^%w_])', pos)
        if not s then break end
        local prev = s > 1 and clean:sub(s - 1, s - 1) or ''
        if prev ~= '.' and prev ~= ':' then
            if word == 'function' or word == 'if' or word == 'do' then
                depth = depth + 1
            elseif word == 'end' then
                depth = depth - 1
                if depth == 0 then return startPos, e end
            end
        end
        pos = e + 1
    end
    return nil, nil
end

local function scanGroundZAt(path, rawSrc)
    local src = stripComments(rawSrc)
    local clampedCount, diagCount = 0, 0
    local rawViolations = {}
    local isDefFile = path:match('fh_core/client/ground_snap%.lua$') ~= nil
    local diagStart, diagEnd
    if path:match('fh_homestead/client/main%.lua$') then
        diagStart, diagEnd = findLocalFunctionSpan(src, 'runPlotcheckProbe')
    end
    local pos = 1
    while true do
        local a, b = src:find('%f[%w_]groundZAt%f[^%w_]', pos)
        if not a then break end
        local before = src:sub(math.max(1, a - 40), a - 1)
        local openParen = src:match('^%s*()%(', b + 1)
        if isDefFile and openParen and before:match('function%s+FhSnap%.%s*$') then
            -- definition in fh_core/client/ground_snap.lua
        elseif not openParen then
            -- Alias, value reference, or dynamic lookup (e.g. local g = FhSnap.groundZAt, FhSnap['groundZAt'])
            rawViolations[#rawViolations + 1] = path .. ' (non-direct reference) near: ' .. src:sub(math.max(1, a - 40), math.min(#src, b + 40)):gsub('%s+', ' ')
        else
            local callEnd = findMatchingParen(src, openParen)
            if diagStart and callEnd and a >= diagStart and callEnd <= diagEnd then
                -- read-only admin diagnostic (/fh_plotcheck, runPlotcheckProbe): reports raw ground delta, never places or gates reach
                diagCount = diagCount + 1
            else
                -- Must be wrapped in FhGroundSnap.snapZ(..., FhSnap.groundZAt(...), FhGroundSnap.SNAP_TOLERANCE)
                local snapPos
                local searchFrom = math.max(1, a - 200)
                while true do
                    local s1, s2 = src:find('FhGroundSnap%.snapZ%s*%(', searchFrom)
                    if not s1 or s1 >= a then break end
                    snapPos = s2
                    searchFrom = s2 + 1
                end
                local snapEnd = snapPos and findMatchingParen(src, snapPos)
                local insideSnap = snapEnd and callEnd and snapEnd > callEnd
                local snapArgs = insideSnap and src:sub(snapPos + 1, snapEnd - 1) or ''
                if insideSnap and snapArgs:find('FhGroundSnap%.SNAP_TOLERANCE', 1) then
                    clampedCount = clampedCount + 1
                else
                    rawViolations[#rawViolations + 1] = path .. ' near: ' .. src:sub(math.max(1, a - 40), math.min(#src, (callEnd or b) + 40)):gsub('%s+', ' ')
                end
            end
        end
        pos = b + 1
    end
    return clampedCount, diagCount, rawViolations
end

case('static scan: no raw groundZAt reaches a reach/placement decision across [fh]', function()
    local root = here .. '../server/resources/[fh]'
    local files = listFhLua(root)
    assert(#files > 0, 'no [fh] lua files found')
    local clampedCount, diagCount = 0, 0
    local rawViolations = {}
    for _, path in ipairs(files) do
        local f = assert(io.open(path, 'r'))
        local c, d, v = scanGroundZAt(path, f:read('*a'))
        f:close()
        clampedCount = clampedCount + c
        diagCount = diagCount + d
        for _, msg in ipairs(v) do rawViolations[#rawViolations + 1] = msg end
    end
    T.eq(0, #rawViolations, 'raw groundZAt caller(s) found:\n' .. table.concat(rawViolations, '\n'))
    assert(clampedCount >= 5, 'expected at least 5 clamped groundZAt callers, saw ' .. tostring(clampedCount))
    T.eq(1, diagCount, 'expected exactly 1 read-only plotcheck diagnostic caller')
end)

case('static scan self-test: rejects aliases, value references, and unexempted plotcheck calls', function()
    local _, _, vAlias = scanGroundZAt('fh_zones/client/evil.lua', 'local g = FhSnap.groundZAt\nlocal z = g("x", 1, 2, 3)\n')
    T.eq(1, #vAlias, 'aliasing FhSnap.groundZAt must fail static scan')

    local _, _, vPass = scanGroundZAt('fh_zones/client/evil.lua', 'runLater(FhSnap.groundZAt)\n')
    T.eq(1, #vPass, 'passing FhSnap.groundZAt as a value must fail static scan')

    local _, _, vIndex = scanGroundZAt('fh_zones/client/evil.lua', 'local z = FhSnap["groundZAt"]("x", 1, 2, 3)\n')
    T.eq(1, #vIndex, 'string-indexed groundZAt lookup must fail static scan')

    local _, dOutside, vOutside = scanGroundZAt('fh_homestead/client/main.lua',
        "local function otherFn()\n    local gz = FhSnap.groundZAt('plotcheck:fake', 1, 2, 3)\nend\n")
    T.eq(0, dOutside, 'plotcheck string literal outside runPlotcheckProbe must not be exempted')
    T.eq(1, #vOutside, 'raw groundZAt outside runPlotcheckProbe must fail static scan')
end)

case('mirrored server snap tolerances match fh_core config and cover SNAP_TOLERANCE + headroom', function()
    local cfg = dofile(here .. '../server/resources/[fh]/fh_core/config.lua')
    local containers = dofile(here .. '../server/resources/[fh]/fh_core/shared/containers.lua')
    local cargo = dofile(here .. '../server/resources/[fh]/fh_cargo/shared/cargo_rules.lua')
    local stations = dofile(here .. '../server/resources/[fh]/fh_homestead/shared/stations.lua')
    local gunsmith = dofile(here .. '../server/resources/[fh]/fh_gunsmith/shared/restore_flow.lua')
    local expected = G.SNAP_TOLERANCE + cfg.Access.InteractDistance -- 10.0 + 3.5 = 13.5 m
    T.eq(13.5, expected)
    T.eq(expected, cfg.Access.SnapToleranceAbove)
    T.eq(expected, cfg.Access.SnapToleranceBelow)
    T.eq(expected, containers.DEFAULT_SNAP_ABOVE)
    T.eq(expected, containers.DEFAULT_SNAP_BELOW)
    T.eq(expected, cargo.SNAP_ABOVE)
    T.eq(expected, cargo.SNAP_BELOW)
    T.eq(expected, stations.SNAP_ABOVE)
    T.eq(expected, stations.SNAP_BELOW)
    T.eq(expected, gunsmith.SNAP_ABOVE)
    T.eq(expected, gunsmith.SNAP_BELOW)
end)

T.finish()

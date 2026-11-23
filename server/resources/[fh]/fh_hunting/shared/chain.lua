-- fh_hunting legendary hunt chain (spec L8, H4). Pure Lua, no natives: the state machine that enforces clue order
-- (rumour -> track -> carcass -> spawn -> skin), no skipping, idempotent repeats, relog resume, and one spawn per
-- chain. server/main.lua injects every side effect (load/save, charge, requestSpawn, despawn, emit) as deps, so
-- spec/hunting_chain_spec.lua runs the real flow with fakes.
--
-- Persisted state (one row per character per chain, keyed (citizenid, chain_id)):
--   step          1 rumour -> 2 track -> 3 carcass -> 4 spawned -> 5 complete. It is the NEXT clue to find (1..3),
--                 then the hunt phase (4) and the done state (5).
--   spawn_request the fh_core requestSpawn id once the bear was requested; 0/nil = not yet.
--   spawned       true once the spawn was adopted (the bear exists).
--   completed     true once the pelt was skinned (the chain is done).
local M = {}

M.CHAIN_ID = 'legendary_bear'
M.EVENT_CLUE = 'fh:hunting:clue_found'
M.EVENT_SPAWNED = 'fh:hunting:legendary_spawned'
M.EVENT_COMPLETE = 'fh:hunting:chain_complete'

M.STEP_RUMOUR = 1
M.STEP_TRACK = 2
M.STEP_CARCASS = 3
M.STEP_SPAWNED = 4
M.STEP_COMPLETE = 5

-- Marker id -> the step that inspects it (clues 2 and 3).
M.MARKERS = { track = M.STEP_TRACK, carcass = M.STEP_CARCASS }

local function finite(n) return type(n) == 'number' and n == n and n > -math.huge and n < math.huge end

-- Position reader: reuse the single shared reader FhHuntingWagon.xyz (shared/wagon.lua) at runtime. It has NO type
-- gate — under CfxLua 5.4 `type(vector3)` is 'vector3', not 'table'/'userdata' — so it probes any value through a pcall
-- and accepts x/y/z (or [1]/[2]/[3]) that are finite numbers. The spec loads chain.lua alone, so a minimal no-gate
-- fallback of the same shape is kept for that case.
local function probeXyz(v)
    if v == nil then return nil end
    local ok, x, y, z = pcall(function() return v.x, v.y, v.z end)
    if not ok or not finite(x) or not finite(y) or not finite(z) then return nil end
    return x, y, z
end

local function xyz(v)
    if FhHuntingWagon and FhHuntingWagon.xyz then return FhHuntingWagon.xyz(v) end
    return probeXyz(v)
end

---Distance in metres between two {x,y,z} / vector3 positions; nil when either is unreadable.
function M.distance(a, b)
    local ax, ay, az = xyz(a)
    local bx, by, bz = xyz(b)
    if not ax or not bx then return nil end
    local dx, dy, dz = ax - bx, ay - by, az - bz
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

---Fresh state for a character who has never started the chain.
function M.defaultState()
    return { chain_id = M.CHAIN_ID, step = M.STEP_RUMOUR, spawn_request = nil, spawned = false, completed = false }
end

---Normalise a persisted row into a valid state (tolerates old/partial rows). `spawn_request` 0/nil -> nil.
function M.normalise(s)
    local out = M.defaultState()
    s = type(s) == 'table' and s or {}
    if type(s.chain_id) == 'string' then out.chain_id = s.chain_id end
    local step = s.step
    if type(step) == 'number' and step % 1 == 0 and step >= M.STEP_RUMOUR and step <= M.STEP_COMPLETE then
        out.step = step
    end
    if type(s.spawn_request) == 'number' and s.spawn_request > 0 then out.spawn_request = s.spawn_request end
    out.spawned = s.spawned == true
    out.completed = s.completed == true
    return out
end

---The marker table for a step (2 or 3) from cfg, or nil.
function M.markerFor(cfg, step)
    local lb = cfg and cfg.LegendaryBear
    return lb and lb.markers and lb.markers[step]
end

local MESSAGES = {
    fh_chain_busy = 'One hunt action at a time.',
    fh_chain_complete = 'The legendary hunt is already complete.',
    fh_chain_rumour_done = 'You already bought the rumour.',
    fh_chain_too_far = 'You are too far away for that.',
    fh_chain_pay_failed = 'You could not pay for the rumour.',
    fh_chain_spawned = 'The legendary bear has already been found.',
    fh_chain_bad_marker = 'There is nothing to inspect here.',
    fh_chain_wrong_marker = 'You have not found the trail that leads here yet.',
    fh_chain_spawn_failed = 'The legendary bear could not be found right now.',
    fh_chain_not_spawned = 'The legendary bear has not appeared.',
    fh_chain_no_spawn = 'No legendary hunt is in progress.',
    fh_chain_wrong_spawn = 'That is not the bear you were tracking.',
    fh_chain_error = 'The hunt could not be updated.',
}
function M.message(reason) return MESSAGES[reason] or ('Hunt: ' .. tostring(reason)) end

---Build a chain. opts = { cfg (FhHuntingConfig), deps = {
---  load(cid)                              -> persisted state table|nil
---  save(cid, state)                       -> ok boolean (false = DB error; the in-memory state still advances)
---  charge(src, cid, amount, reason, region) -> ok boolean (the rumour charge: DEDUCTS cash from the player)
---  spawn(cid, chainCfg)                   -> requestId|nil (fh_core requestSpawn wrapper)
---  despawn(requestId)                     -> ok (fh_core despawn; stops the post-skin re-request)
---  emit(name, payload)                    -> server-only TriggerEvent
---} }
function M.new(opts)
    local cfg, deps = opts.cfg, opts.deps
    local cache = {} -- [cid] = state (the in-memory truth; persisted on every change)
    local busy = {}  -- [cid] = true while an action is mid-flight (guards re-entrancy across the charge/save yield)

    local function get(cid)
        local s = cache[cid]
        if not s then
            s = M.normalise(deps.load(cid))
            cache[cid] = s
        end
        return s
    end

    local function save(cid, s)
        cache[cid] = s
        return deps.save(cid, s) ~= false
    end

    -- Serialise one action per cid; a re-entrant call during a yield is refused (fh_chain_busy), a throw is caught.
    local function guard(cid, fn, ...)
        if busy[cid] then return false, 'fh_chain_busy' end
        busy[cid] = true
        local ok, a, b = pcall(fn, ...)
        busy[cid] = nil
        if not ok then return false, 'fh_chain_error' end
        return a, b
    end

    local C = {}

    ---Read-only copy of the current state (for the client status push).
    function C.state(cid)
        local s = get(cid)
        return { chain_id = s.chain_id, step = s.step, spawn_request = s.spawn_request,
            spawned = s.spawned, completed = s.completed }
    end

    ---Forget the cached state and any in-flight guard (playerDropped / relog).
    function C.drop(cid)
        cache[cid] = nil
        busy[cid] = nil
    end

    ---Clue 1: buy the rumour from the trapper. coords = server-read player position.
    ---@return boolean ok, table|string resOrReason
    function C.buyRumour(src, cid, coords)
        local lb = cfg and cfg.LegendaryBear
        if not lb then return false, 'fh_chain_error' end
        local function inner()
            local s = get(cid)
            if s.completed then return false, 'fh_chain_complete' end
            if s.spawned or s.step > M.STEP_RUMOUR then return false, 'fh_chain_rumour_done' end
            local d = M.distance(coords, cfg.Trapper.coords)
            if not d or d > lb.RumourRange then return false, 'fh_chain_too_far' end
            if not deps.charge(src, cid, lb.rumourPrice, 'hunting:rumour', lb.region_id) then
                return false, 'fh_chain_pay_failed'
            end
            s.step = M.STEP_TRACK
            save(cid, s)
            deps.emit(M.EVENT_CLUE, { citizenid = cid, chain_id = M.CHAIN_ID, step = M.STEP_RUMOUR })
            return true, { step = s.step, marker = M.markerFor(cfg, M.STEP_TRACK) }
        end
        return guard(cid, inner)
    end

    ---Clues 2 and 3: inspect a track/carcass marker. marker = 'track'|'carcass'. coords = server-read position.
    ---Inspecting the carcass (clue 3) also requests the bear spawn exactly once.
    ---@return boolean ok, table|string resOrReason
    function C.inspect(cid, marker, coords)
        local lb = cfg and cfg.LegendaryBear
        if not lb then return false, 'fh_chain_error' end
        local function inner()
            local s = get(cid)
            if s.completed then return false, 'fh_chain_complete' end
            if s.spawned or s.step >= M.STEP_SPAWNED then return false, 'fh_chain_spawned' end
            if type(marker) ~= 'string' then return false, 'fh_chain_bad_marker' end
            local step = M.MARKERS[marker]
            if not step then return false, 'fh_chain_bad_marker' end
            if step ~= s.step then return false, 'fh_chain_wrong_marker' end
            local m = M.markerFor(cfg, step)
            local d = M.distance(coords, m and m.coords)
            if not d or d > (m.radius or 3.0) then return false, 'fh_chain_too_far' end

            if step == M.STEP_CARCASS then
                -- final clue: request the spawn exactly once, before any further state change.
                if s.spawn_request then return false, 'fh_chain_spawned' end
                local rid = deps.spawn(cid, lb)
                if not rid then return false, 'fh_chain_spawn_failed' end
                s.spawn_request = rid
                s.step = M.STEP_SPAWNED
            else
                s.step = M.STEP_CARCASS
            end
            save(cid, s)
            deps.emit(M.EVENT_CLUE, { citizenid = cid, chain_id = M.CHAIN_ID, step = step })
            return true, { step = s.step, marker = M.markerFor(cfg, s.step) }
        end
        return guard(cid, inner)
    end

    ---The bear was adopted (requestSpawn onReady). Marks spawned and emits legendary_spawned exactly once, even when
    ---fh_core re-requests with a new netId (the chain still has one bear).
    ---@return boolean ok, string|nil reason
    function C.onAdopted(cid)
        local s = get(cid)
        if not s.spawn_request then return false, 'fh_chain_no_spawn' end
        if s.spawned then return true end
        s.spawned = true
        save(cid, s)
        deps.emit(M.EVENT_SPAWNED, { citizenid = cid, chain_id = M.CHAIN_ID })
        return true
    end

    ---The bear spawn failed (requestSpawn onFailed after retries were exhausted). Resets the chain to the carcass clue
    ---so the character can try again, unless the bear was already adopted (spawned).
    ---@return boolean ok, string|nil reason
    function C.onSpawnFailed(cid, requestId)
        local s = get(cid)
        if s.spawned then return false, 'fh_chain_spawned' end
        if requestId ~= nil and s.spawn_request ~= requestId then return false, 'fh_chain_wrong_spawn' end
        s.spawn_request = nil
        s.step = M.STEP_CARCASS
        save(cid, s)
        return true
    end

    ---The legendary pelt was skinned. Marks the chain complete and despawns the request (no post-skin re-spawn).
    ---Idempotent: completion only fires once. Requires the bear to have been spawned.
    ---@return boolean ok, string|nil reason
    function C.onSkinned(cid)
        local s = get(cid)
        if not s.spawned then return false, 'fh_chain_not_spawned' end
        if s.completed then return true end
        s.completed = true
        s.step = M.STEP_COMPLETE
        if s.spawn_request then pcall(deps.despawn, s.spawn_request) end
        save(cid, s)
        deps.emit(M.EVENT_COMPLETE, { citizenid = cid, chain_id = M.CHAIN_ID })
        return true
    end

    return C
end

if GetCurrentResourceName then
    FhHuntingChain = M
else
    return M
end

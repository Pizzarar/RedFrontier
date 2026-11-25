-- fh_hunting legendary hunt chains (spec L8 H4; plan hunting-02 B1). Pure Lua, no natives: the state machine that
-- enforces clue order (rumour -> track -> carcass -> spawn -> skin), no skipping, idempotent repeats, relog resume, and
-- one spawn per chain. One chain per legendary (data/legendaries/<region_id>.lua, loaded by shared/legendaries.lua);
-- chain_id = the legendary id. server/main.lua injects every side effect (load/save, charge, requestSpawn, despawn,
-- emit) as deps, so spec/hunting_chain_spec.lua and spec/hunting_legendaries_spec.lua run the real flow with fakes.
--
-- Every action takes an optional trailing legendary id; nil means the Legendary Bear (M.CHAIN_ID), so the H4 call
-- shapes are unchanged. Unknown ids (and stub regions, which have no entry) are refused with fh_chain_unknown.
-- Gate: while the legendary's region is not enabled (FhRegions.isEnabled), the rumour and both markers (and with the
-- carcass, the spawn) refuse with fh_chain_region_closed. State in progress is kept as it is (frozen, not reset); the
-- system callbacks (onAdopted / onSpawnFailed / onSkinned) are not gated so an in-flight spawn stays consistent.
--
-- Persisted state (one row per character per chain, keyed (citizenid, chain_id); migration 0010, unchanged):
--   step          1 rumour -> 2 track -> 3 carcass -> 4 spawned -> 5 complete. It is the NEXT clue to find (1..3),
--                 then the hunt phase (4) and the done state (5).
--   spawn_request the fh_core requestSpawn id once the animal was requested; 0/nil = not yet.
--   spawned       true once the spawn was adopted (the animal exists).
--   completed     true once the pelt was skinned (the chain is done).
local M = {}

M.CHAIN_ID = 'legendary_bear' -- the default chain: the Legendary Bear (data/legendaries/heartlands.lua)
M.EVENT_CLUE = 'fh:hunting:clue_found'
M.EVENT_SPAWNED = 'fh:hunting:legendary_spawned'
M.EVENT_COMPLETE = 'fh:hunting:chain_complete'

M.STEP_RUMOUR = 1
M.STEP_TRACK = 2
M.STEP_CARCASS = 3
M.STEP_SPAWNED = 4
M.STEP_COMPLETE = 5

-- Default marker id -> the step that inspects it (clues 2 and 3). An entry may name its markers; see M.stepOf.
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

-- The legendary registry (shared/legendaries.lua): the FXServer global, else the spec-side singleton.
local defaultLegendaries
local function legendaries()
    if FhHuntingLegendaries then return FhHuntingLegendaries end
    if not defaultLegendaries then
        local dir = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
        defaultLegendaries = package.loaded.fh_hunting_legendaries or dofile(dir .. 'legendaries.lua')
    end
    return defaultLegendaries
end
M.legendaries = legendaries

---Fresh state for a character who has never started this chain (default: the Legendary Bear).
function M.defaultState(chainId)
    return { chain_id = chainId or M.CHAIN_ID, step = M.STEP_RUMOUR, spawn_request = nil, spawned = false,
        completed = false }
end

---Normalise a persisted row into a valid state (tolerates old/partial rows). `spawn_request` 0/nil -> nil.
---chainId (the chain being loaded) wins over the row's own chain_id.
function M.normalise(s, chainId)
    s = type(s) == 'table' and s or {}
    local out = M.defaultState(chainId or (type(s.chain_id) == 'string' and s.chain_id or nil))
    local step = s.step
    if type(step) == 'number' and step % 1 == 0 and step >= M.STEP_RUMOUR and step <= M.STEP_COMPLETE then
        out.step = step
    end
    if type(s.spawn_request) == 'number' and s.spawn_request > 0 then out.spawn_request = s.spawn_request end
    out.spawned = s.spawned == true
    out.completed = s.completed == true
    return out
end

---The marker table of a legendary entry for a step (2 or 3), or nil.
function M.markerFor(entry, step)
    return entry and entry.markers and entry.markers[step]
end

---The clue step (2 or 3) a marker id inspects for this entry, or nil.
function M.stepOf(entry, marker)
    if type(marker) ~= 'string' then return nil end
    for step = M.STEP_TRACK, M.STEP_CARCASS do
        local m = M.markerFor(entry, step)
        if m and m.id == marker then return step end
    end
    return nil
end

local MESSAGES = {
    fh_chain_busy = 'One hunt action at a time.',
    fh_chain_complete = 'The legendary hunt is already complete.',
    fh_chain_rumour_done = 'You already bought the rumour.',
    fh_chain_too_far = 'You are too far away for that.',
    fh_chain_pay_failed = 'You could not pay for the rumour.',
    fh_chain_no_funds = 'You cannot afford the rumour.',
    fh_chain_pay_busy = 'Another payment is still going through. Try again in a moment.',
    fh_chain_spawned = 'The legendary beast has already been found.',
    fh_chain_bad_marker = 'There is nothing to inspect here.',
    fh_chain_wrong_marker = 'You have not found the trail that leads here yet.',
    fh_chain_spawn_failed = 'The legendary beast could not be found right now.',
    fh_chain_not_spawned = 'The legendary beast has not appeared.',
    fh_chain_no_spawn = 'No legendary hunt is in progress.',
    fh_chain_wrong_spawn = 'That is not the beast you were tracking.',
    fh_chain_unknown = 'There is no such legendary hunt.',
    fh_chain_region_closed = 'There is no legendary hunt here.',
    fh_chain_error = 'The hunt could not be updated.',
}
function M.message(reason) return MESSAGES[reason] or ('Hunt: ' .. tostring(reason)) end

---Build the chains. opts = { cfg (FhHuntingConfig), legendaries? (registry, default shared/legendaries.lua),
---isEnabled? (region_id -> boolean, default the registry's FhRegions.isEnabled), deps = {
---  load(cid, chainId)                     -> persisted state table|nil
---  save(cid, state)                       -> ok boolean (false = DB error; the in-memory state still advances)
---                                            state.chain_id says which chain
---  charge(src, cid, amount, reason, region) -> ok, err (the rumour charge: DEDUCTS cash; err = fh_economy:charge code)
---  spawn(cid, entry)                      -> requestId|nil (fh_core requestSpawn wrapper; entry = the legendary)
---  despawn(requestId)                     -> ok (fh_core despawn; stops the post-skin re-request)
---  emit(name, payload)                    -> server-only TriggerEvent
---} }
function M.new(opts)
    local cfg, deps = opts.cfg, opts.deps
    local L = opts.legendaries or legendaries()
    local isEnabled = opts.isEnabled or L.isEnabled
    local cache = {} -- [cid][chainId] = state (the in-memory truth; persisted on every change)
    local busy = {}  -- [cid][chainId] = true while an action is mid-flight (guards re-entrancy across a yield)

    local function entryOf(id)
        if id == nil then id = M.CHAIN_ID end
        if type(id) ~= 'string' then return nil end
        return L.byId[id]
    end

    local function get(cid, id)
        local c = cache[cid]
        if not c then c = {}; cache[cid] = c end
        local s = c[id]
        if not s then
            s = M.normalise(deps.load(cid, id), id)
            c[id] = s
        end
        return s
    end

    local function save(cid, s)
        local c = cache[cid]
        if not c then c = {}; cache[cid] = c end
        c[s.chain_id] = s
        return deps.save(cid, s) ~= false
    end

    -- Serialise one action per (cid, chain); a re-entrant call on the same chain during a yield is refused
    -- (fh_chain_busy), other chains of the same character go through. A throw is caught.
    local function guard(cid, id, fn)
        local b = busy[cid]
        if b and b[id] then return false, 'fh_chain_busy' end
        if not b then b = {}; busy[cid] = b end
        b[id] = true
        local ok, x, y = pcall(fn)
        b[id] = nil
        if busy[cid] == b and next(b) == nil then busy[cid] = nil end
        if not ok then return false, 'fh_chain_error' end
        return x, y
    end

    -- Additive event payload: chain_id as before, plus region_id and legendary (the entry id).
    local function payload(cid, e, step)
        return { citizenid = cid, chain_id = e.id, region_id = e.region_id, legendary = e.id, step = step }
    end

    local C = {}

    ---Read-only copy of one chain's state (for the client status push). nil for an unknown legendary.
    function C.state(cid, id)
        local e = entryOf(id)
        if not e then return nil end
        local s = get(cid, e.id)
        return { chain_id = s.chain_id, step = s.step, spawn_request = s.spawn_request,
            spawned = s.spawned, completed = s.completed }
    end

    ---States of every legendary in an enabled region: { [id] = { step, spawned, completed } } (client push).
    function C.activeStates(cid)
        local out = {}
        for _, e in ipairs(L:active()) do
            local s = get(cid, e.id)
            out[e.id] = { step = s.step, spawned = s.spawned, completed = s.completed }
        end
        return out
    end

    ---Forget the cached states and any in-flight guards of a character (playerDropped / relog).
    function C.drop(cid)
        cache[cid] = nil
        busy[cid] = nil
    end

    ---Clue 1: buy the rumour at the legendary's rumour point. coords = server-read player position.
    ---@return boolean ok, table|string resOrReason
    function C.buyRumour(src, cid, coords, id)
        local e = entryOf(id)
        if not e then return false, 'fh_chain_unknown' end
        local function inner()
            if not isEnabled(e.region_id) then return false, 'fh_chain_region_closed' end
            local s = get(cid, e.id)
            if s.completed then return false, 'fh_chain_complete' end
            if s.spawned or s.step > M.STEP_RUMOUR then return false, 'fh_chain_rumour_done' end
            -- the region's trapper hosts the rumour (the loader sets rumour.coords = trapper.coords)
            local d = M.distance(coords, e.rumour.coords)
            if not d or d > (e.rumour.range or (cfg and cfg.LegendaryRumourRange) or 4.0) then
                return false, 'fh_chain_too_far'
            end
            local paid, cerr = deps.charge(src, cid, e.rumour.price, 'hunting:rumour', e.region_id)
            if not paid then
                if cerr == 'fh_insufficient_funds' then return false, 'fh_chain_no_funds' end
                if cerr == 'fh_charge_busy' then return false, 'fh_chain_pay_busy' end
                return false, 'fh_chain_pay_failed'
            end
            s.step = M.STEP_TRACK
            save(cid, s)
            deps.emit(M.EVENT_CLUE, payload(cid, e, M.STEP_RUMOUR))
            return true, { step = s.step, marker = M.markerFor(e, M.STEP_TRACK) }
        end
        return guard(cid, e.id, inner)
    end

    ---Clues 2 and 3: inspect a marker (its id from the entry, 'track'|'carcass' by default). coords = server-read.
    ---Inspecting the last marker (clue 3) also requests the spawn exactly once.
    ---@return boolean ok, table|string resOrReason
    function C.inspect(cid, marker, coords, id)
        local e = entryOf(id)
        if not e then return false, 'fh_chain_unknown' end
        local function inner()
            if not isEnabled(e.region_id) then return false, 'fh_chain_region_closed' end
            local s = get(cid, e.id)
            if s.completed then return false, 'fh_chain_complete' end
            if s.spawned or s.step >= M.STEP_SPAWNED then return false, 'fh_chain_spawned' end
            local step = M.stepOf(e, marker)
            if not step then return false, 'fh_chain_bad_marker' end
            if step ~= s.step then return false, 'fh_chain_wrong_marker' end
            local m = M.markerFor(e, step)
            local d = M.distance(coords, m and m.coords)
            if not d or d > (m.radius or 3.0) then return false, 'fh_chain_too_far' end

            if step == M.STEP_CARCASS then
                -- final clue: request the spawn exactly once, before any further state change.
                if s.spawn_request then return false, 'fh_chain_spawned' end
                local rid = deps.spawn(cid, e)
                if not rid then return false, 'fh_chain_spawn_failed' end
                s.spawn_request = rid
                s.step = M.STEP_SPAWNED
            else
                s.step = M.STEP_CARCASS
            end
            save(cid, s)
            deps.emit(M.EVENT_CLUE, payload(cid, e, step))
            return true, { step = s.step, marker = M.markerFor(e, s.step) }
        end
        return guard(cid, e.id, inner)
    end

    ---The spawn was adopted (requestSpawn onReady). Marks spawned and emits legendary_spawned exactly once, even when
    ---fh_core re-requests with a new netId (the chain still has one animal).
    ---@return boolean ok, string|nil reason
    function C.onAdopted(cid, id)
        local e = entryOf(id)
        if not e then return false, 'fh_chain_unknown' end
        local s = get(cid, e.id)
        if not s.spawn_request then return false, 'fh_chain_no_spawn' end
        if s.spawned then return true end
        s.spawned = true
        save(cid, s)
        deps.emit(M.EVENT_SPAWNED, payload(cid, e))
        return true
    end

    ---The spawn failed (requestSpawn onFailed after retries were exhausted). Resets the chain to the carcass clue so
    ---the character can try again, unless the animal was already adopted (spawned).
    ---@return boolean ok, string|nil reason
    function C.onSpawnFailed(cid, requestId, id)
        local e = entryOf(id)
        if not e then return false, 'fh_chain_unknown' end
        local s = get(cid, e.id)
        if s.spawned then return false, 'fh_chain_spawned' end
        if requestId ~= nil and s.spawn_request ~= requestId then return false, 'fh_chain_wrong_spawn' end
        s.spawn_request = nil
        s.step = M.STEP_CARCASS
        save(cid, s)
        return true
    end

    ---The legendary pelt was skinned. Marks the chain complete and despawns the request (no post-skin re-spawn).
    ---Idempotent: completion only fires once. Requires the animal to have been spawned.
    ---@return boolean ok, string|nil reason
    function C.onSkinned(cid, id)
        local e = entryOf(id)
        if not e then return false, 'fh_chain_unknown' end
        local s = get(cid, e.id)
        if not s.spawned then return false, 'fh_chain_not_spawned' end
        if s.completed then return true end
        s.completed = true
        s.step = M.STEP_COMPLETE
        if s.spawn_request then pcall(deps.despawn, s.spawn_request) end
        save(cid, s)
        deps.emit(M.EVENT_COMPLETE, payload(cid, e))
        return true
    end

    return C
end

-- Read-only public view for other resources (exports.fh_hunting:chainState). Pure: deps = { byId = legendary registry
-- by id, query(cid, chainId) -> rows (may throw), log(msg) }. Reads the persisted row only: it never touches the chain
-- cache (so it cannot create a default state) and emits nothing. nil = no row / unknown chain / bad args / query error
-- (the error is logged once per process).
local chainStateLogged = false
---@return nil|integer|string  nil | stored step (1..4) | 'complete'
function M.readState(deps, citizenid, chainId)
    if type(citizenid) ~= 'string' or citizenid == '' then return nil end
    if type(chainId) ~= 'string' or not (deps.byId and deps.byId[chainId]) then return nil end
    local ok, rows = pcall(deps.query, citizenid, chainId)
    if not ok then
        if not chainStateLogged then
            chainStateLogged = true
            if deps.log then pcall(deps.log, 'chainState query failed: ' .. tostring(rows)) end
        end
        return nil
    end
    local r = type(rows) == 'table' and rows[1] or nil
    if type(r) ~= 'table' then return nil end
    local st = M.normalise({ step = tonumber(r.step), completed = r.completed == 1 or r.completed == true }, chainId)
    if st.completed or st.step >= M.STEP_COMPLETE then return 'complete' end
    return st.step
end

if GetCurrentResourceName then
    FhHuntingChain = M
else
    return M
end

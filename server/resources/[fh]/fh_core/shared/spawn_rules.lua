-- Spawn-request contract, pure part (plan core-01 "Entity spawning on RedM" + Amendment 2026-11-22 autonomy).
-- Server CREATE_PED / CREATE_OBJECT_NO_OFFSET / CREATE_AUTOMOBILE / CREATE_VEHICLE_SERVER_SETTER are compiled out on
-- RDR3, so: the server owns the decision and the state, a chosen client creates the networked entity, and the server
-- adopts it by netId. This file is the state machine, spawner pick and adopt validation. No natives, no ox_lib:
-- specced under busted (spec/spawn_rules_spec.lua). The natives live in server/spawn.lua and client/spawn.lua.
--
-- States:  pending -> dispatched -> verifying -> adopted
--          pending -> pending_no_client (no player to spawn it) -> dispatched
--          dispatched | verifying -> pending (retry, next candidate) | failed (retries used up)
--          adopted -> pending (re-request: entity gone, or spawner dropped while fh_spike_gated)
--          any live state -> despawned
-- Invariant (exactly-once): a request adopts at most one live entity. Only the CURRENT token from the CURRENT spawner,
-- in state `dispatched`, can enter `verifying`; every other `created` is rejected and its entity deleted.
local M = {}

M.KINDS = { ped = true, object = true, horse = true } -- no vehicles/wagons until M4

M.TRANSITIONS = {
    pending           = { dispatched = true, pending_no_client = true, failed = true, despawned = true },
    pending_no_client = { dispatched = true, despawned = true },
    dispatched        = { verifying = true, pending = true, failed = true, despawned = true },
    verifying         = { adopted = true, pending = true, failed = true, despawned = true },
    adopted           = { pending = true, despawned = true },
    failed            = {},
    despawned         = {},
}

M.DEFAULTS = {
    Range = 300.0,           -- metres: nearest ready player within this of spec.coords is the spawner
    FallbackAnyPlayer = true, -- nobody in range: use the nearest ready player anywhere
    TimeoutMs = 10000,       -- dispatched -> retry after this
    Retries = 3,             -- extra attempts after the first
    AdoptMaxDistance = 25.0, -- entity must be this close to spec.coords when adopted
}

local function finite(n) return type(n) == 'number' and n == n and n > -math.huge and n < math.huge end

local function field(v, k)
    local ok, x = pcall(function() return v[k] end) -- vector3 errors or returns nil on .w; tables just index
    if ok then return x end
end

---Reads a table / vector3 / vector4 into a plain { x, y, z } and its w (nil when absent).
function M.readCoords(v)
    if v == nil then return nil end
    local x, y, z = field(v, 'x'), field(v, 'y'), field(v, 'z')
    if not (finite(x) and finite(y) and finite(z)) then return nil end
    local w = field(v, 'w')
    return { x = x + 0.0, y = y + 0.0, z = z + 0.0 }, finite(w) and w + 0.0 or nil
end

function M.dist(a, b)
    local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

---Jenkins one-at-a-time, lowercased: the same hash GetHashKey/joaat give, as an unsigned 32-bit integer.
function M.joaat(s)
    s = tostring(s):lower()
    local h = 0
    for i = 1, #s do
        h = (h + s:byte(i)) & 0xFFFFFFFF
        h = (h + (h << 10)) & 0xFFFFFFFF
        h = h ~ (h >> 6)
    end
    h = (h + (h << 3)) & 0xFFFFFFFF
    h = h ~ (h >> 11)
    h = (h + (h << 15)) & 0xFFFFFFFF
    return h
end

---Model name or hash -> unsigned 32-bit hash (GetEntityModel may return it signed).
function M.modelHash(model)
    if type(model) == 'string' then
        local n = tonumber(model)
        if n and n == math.floor(n) then return math.floor(n) & 0xFFFFFFFF end
        return M.joaat(model)
    end
    if math.type(model) == 'integer' then return model & 0xFFFFFFFF end
    if finite(model) and model == math.floor(model) then return math.floor(model) & 0xFFFFFFFF end
end

---Convar string -> boolean. Unknown/empty values give the default.
function M.parseFlag(s, default)
    s = tostring(s or ''):lower()
    if s == 'true' or s == '1' or s == 'yes' or s == 'on' then return true end
    if s == 'false' or s == '0' or s == 'no' or s == 'off' then return false end
    return default
end

---Validates and normalises a spawn spec. Returns spec or nil, '<code>'.
function M.validateSpec(spec)
    if type(spec) ~= 'table' then return nil, 'fh_spawn_bad_spec' end
    if spec.kind == 'vehicle' or spec.kind == 'wagon' then return nil, 'fh_spawn_kind_unsupported' end
    if not M.KINDS[spec.kind] then return nil, 'fh_spawn_bad_kind' end
    local model = spec.model
    if (type(model) ~= 'string' or model == '') and type(model) ~= 'number' then return nil, 'fh_spawn_bad_model' end
    local hash = M.modelHash(model)
    if not hash or hash == 0 then return nil, 'fh_spawn_bad_model' end
    local coords, w = M.readCoords(spec.coords)
    if not coords then return nil, 'fh_spawn_bad_coords' end
    local heading = spec.heading
    if heading == nil then heading = w or 0.0 end
    if not finite(heading) then return nil, 'fh_spawn_bad_heading' end
    local owner = spec.owner
    if owner ~= nil and (type(owner) ~= 'table' or type(owner.kind) ~= 'string' or owner.id == nil) then
        return nil, 'fh_spawn_bad_owner'
    end
    if spec.tag ~= nil and type(spec.tag) ~= 'string' then return nil, 'fh_spawn_bad_tag' end
    return {
        kind = spec.kind, model = model, modelHash = hash, coords = coords, heading = (heading % 360) + 0.0,
        owner = owner and { kind = owner.kind, id = owner.id } or { kind = 'system', id = 0 }, tag = spec.tag,
    }
end

---Normalises opts against config (FhConfig.Spawn over DEFAULTS). Returns opts or nil, '<code>'.
function M.validateOpts(opts, cfg)
    opts = opts or {}
    cfg = cfg or {}
    if type(opts) ~= 'table' then return nil, 'fh_spawn_bad_opts' end
    local function pick(k) if cfg[k] ~= nil then return cfg[k] end return M.DEFAULTS[k] end
    local timeout = opts.timeoutMs == nil and pick('TimeoutMs') or opts.timeoutMs
    local retries = opts.retries == nil and pick('Retries') or opts.retries
    if not finite(timeout) or timeout <= 0 then return nil, 'fh_spawn_bad_timeout' end
    if not finite(retries) or retries < 0 or retries ~= math.floor(retries) then return nil, 'fh_spawn_bad_retries' end
    local near
    if opts.near ~= nil then
        near = M.readCoords(opts.near)
        if not near then return nil, 'fh_spawn_bad_coords' end
    end
    return { near = near, timeoutMs = timeout, retries = math.floor(retries) }
end

function M.newRequest(id, spec, opts)
    return {
        id = id, spec = spec, near = opts.near or spec.coords, timeoutMs = opts.timeoutMs,
        maxAttempts = opts.retries + 1, attempts = 0, state = 'pending',
        tried = {},       -- [playerId] = true: spawners already asked this cycle
        staleTokens = {}, -- [token] = playerId: earlier attempts; a late `created` on one is deleted, never adopted
    }
end

---The one place a request changes state. Illegal moves return false and leave the request alone.
function M.transition(req, to)
    local allowed = M.TRANSITIONS[req.state]
    if not (allowed and allowed[to]) then return false, 'fh_spawn_bad_transition' end
    req.state = to
    return true
end

function M.isLive(req) return req.state ~= 'failed' and req.state ~= 'despawned' end

---Pick the spawner. candidates: { { id = playerId, coords = {x,y,z}|nil } } (ready players only).
---Order: in range before out of range (out of range only with fallback), not-yet-tried before tried, nearer first,
---lower id on ties. Returns id, 'in_range'|'fallback' or nil when nobody qualifies.
function M.pickSpawner(candidates, near, range, fallback, tried)
    tried = tried or {}
    local best, bestKey
    for _, c in ipairs(candidates or {}) do
        local d = (c.coords and near) and M.dist(c.coords, near) or math.huge
        local out = d > range
        if not out or fallback then
            local key = { out and 1 or 0, tried[c.id] and 1 or 0, d, c.id }
            local better = not bestKey
            if bestKey then
                for i = 1, 4 do
                    if key[i] ~= bestKey[i] then better = key[i] < bestKey[i]; break end
                end
            end
            if better then best, bestKey = c.id, key end
        end
    end
    if best then return best, bestKey[1] == 0 and 'in_range' or 'fallback' end
end

---pending | pending_no_client -> dispatched. Counts one attempt.
function M.dispatch(req, spawner, token, now)
    local ok, err = M.transition(req, 'dispatched')
    if not ok then return false, err end
    req.attempts = req.attempts + 1
    req.spawner, req.token, req.deadline = spawner, token, now + req.timeoutMs
    req.tried[spawner] = true
    return true
end

---pending -> pending_no_client (wait for a player to join or come in range; does not use an attempt).
function M.park(req) return M.transition(req, 'pending_no_client') end

local function retire(req)
    if req.token then req.staleTokens[req.token] = req.spawner end
    req.token, req.spawner, req.deadline, req.netId = nil, nil, nil, nil
end

---dispatched | verifying -> pending (attempts left) or failed. Returns 'retry' | 'failed' (or nil, err).
function M.retry(req, reason)
    if req.state ~= 'dispatched' and req.state ~= 'verifying' then return nil, 'fh_spawn_bad_transition' end
    retire(req)
    req.lastReason = reason
    if req.attempts >= req.maxAttempts then
        M.transition(req, 'failed')
        req.failReason = reason or 'fh_spawn_failed'
        return 'failed'
    end
    M.transition(req, 'pending')
    return 'retry'
end

---adopted -> pending as a fresh cycle (attempts and tried reset): the entity is gone or was despawned on purpose.
function M.rerequest(req, reason)
    if req.state ~= 'adopted' then return nil, 'fh_spawn_bad_transition' end
    retire(req)
    req.entity = nil
    req.attempts, req.tried, req.lastReason = 0, {}, reason
    M.transition(req, 'pending')
    return 'rerequest'
end

---Tick: has this dispatch timed out? Returns 'retry' | 'failed' | nil.
function M.checkTimeout(req, now)
    if req.state == 'dispatched' and req.deadline and now >= req.deadline then
        return M.retry(req, 'fh_spawn_timeout')
    end
end

---A player dropped. gated = fh_spike_gated. owner = current network owner of the adopted entity (may be nil).
---Returns 'retry' | 'failed' (mid-dispatch), 'despawn_rerequest' (adopted, gated), 'keep' (adopted, ungated) or nil.
function M.onPlayerDropped(req, src, gated, owner)
    req.tried[src] = nil
    if req.state == 'dispatched' or req.state == 'verifying' then
        if req.spawner == src then return M.retry(req, 'fh_spawn_spawner_dropped') end
        return nil
    end
    if req.state == 'adopted' and (req.spawner == src or owner == src) then
        if gated then
            M.rerequest(req, 'fh_spawn_owner_dropped')
            return 'despawn_rerequest'
        end
        if req.spawner == src then req.spawner = nil end -- migration/orphan mode keeps the entity; id is gone
        return 'keep'
    end
end

---A `fh:spawn:created` arrived. Returns a verdict:
---  'verify'       current token from the current spawner while dispatched: now `verifying`, go check the entity
---  'duplicate'    current token again (already verifying/adopted): delete the extra entity unless it is the same netId
---  'same'         repeat of the adopted netId: nothing to do
---  'stale'        token of an earlier attempt from its own spawner: delete that entity, state unchanged
---  'wrong_source' / 'wrong_token' / 'unknown': rejected, state unchanged (the client only deletes what it made)
function M.onCreated(req, src, token, netId)
    if not req or not M.isLive(req) then return 'unknown' end
    if token ~= nil and token == req.token then
        if src ~= req.spawner then return 'wrong_source' end
        if req.state == 'dispatched' then
            M.transition(req, 'verifying')
            req.netId = netId
            return 'verify'
        end
        if req.netId ~= nil and req.netId == netId then return 'same' end
        return 'duplicate'
    end
    if token ~= nil and req.staleTokens[token] ~= nil then
        if req.staleTokens[token] ~= src then return 'wrong_source' end
        return 'stale'
    end
    if src ~= req.spawner then return 'wrong_source' end
    return 'wrong_token'
end

---A `fh:spawn:failed` arrived. Only the current spawner with the current token counts.
function M.onClientFailed(req, src, token, reason)
    if not req or req.state ~= 'dispatched' then return nil, 'fh_spawn_bad_state' end
    if src ~= req.spawner then return nil, 'fh_spawn_wrong_source' end
    if token ~= req.token then return nil, 'fh_spawn_wrong_token' end
    return M.retry(req, 'fh_spawn_client:' .. tostring(reason or 'unknown'))
end

---Adopt validation on server-read facts. info = { exists, model (hash, may be signed), coords }.
function M.checkEntity(req, info, maxDist)
    if not info or not info.exists then return false, 'fh_spawn_no_entity' end
    if M.modelHash(info.model) ~= req.spec.modelHash then return false, 'fh_spawn_model_mismatch' end
    local c = M.readCoords(info.coords)
    if not c or M.dist(c, req.spec.coords) > (maxDist or M.DEFAULTS.AdoptMaxDistance) then
        return false, 'fh_spawn_out_of_range'
    end
    return true
end

---verifying -> adopted (ok) or retry/failed. token guards against a verify that finished after a retry/despawn.
---Returns 'adopted' | 'retry' | 'failed' | nil, 'fh_spawn_stale_verify'.
function M.finishVerify(req, token, ok, reason, entity)
    if not req or req.state ~= 'verifying' or req.token ~= token then return nil, 'fh_spawn_stale_verify' end
    if ok then
        M.transition(req, 'adopted')
        req.entity, req.deadline = entity, nil
        return 'adopted'
    end
    return M.retry(req, reason)
end

---Any live state -> despawned. Returns { netId, entity, token, spawner }: the entity to delete (adopted/verifying) and
---the token in flight (its spawner deletes whatever it makes for it), or nil, err.
function M.despawn(req)
    if not req or not M.isLive(req) then return nil, 'fh_spawn_not_live' end
    local out = { netId = req.netId, entity = req.entity, token = req.token, spawner = req.spawner }
    retire(req)
    req.entity = nil
    M.transition(req, 'despawned')
    return out
end

---Position `dist` metres in front of coords for heading (RDR forward = (-sin h, cos h)).
function M.offsetForward(c, heading, d)
    local r = math.rad(heading or 0)
    return { x = c.x - math.sin(r) * d, y = c.y + math.cos(r) * d, z = c.z }
end

if GetCurrentResourceName then
    FhSpawnRules = M
else
    return M
end

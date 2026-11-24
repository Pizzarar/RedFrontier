-- fh_core spawn-request contract, server side. State machine + validation: shared/spawn_rules.lua (FhSpawnRules).
-- The server owns the decision and the state; a chosen client creates the networked entity (client/spawn.lua); the
-- server adopts it by netId. Behaviour behind convar fh_spike_gated: docs/spike-gated.md.
-- Natives (docs/natives.md, all unverified in-game): GetPlayers, GetPlayerPed, GetEntityCoords,
-- NetworkGetEntityFromNetworkId, DoesEntityExist, GetEntityModel, NetworkGetEntityOwner, DeleteEntity,
-- SetEntityOrphanMode, IsPedAPlayer, GetConvar, GetGameTimer, GetInvokingResource. Not runtime-tested (no Cfx key yet).
local R = FhSpawnRules

local requests = {}  -- [requestId] = request (FhSpawnRules.newRequest + resource, onReady, onFailed)
local ready = {}     -- [playerId] = true once that client's fh_core/client/spawn.lua is up
local nextId = 0

local function cfg() return (FhConfig and FhConfig.Spawn) or {} end
local function setting(k) local v = cfg()[k]; if v == nil then v = R.DEFAULTS[k] end return v end
local function gated() return R.parseFlag(GetConvar('fh_spike_gated', 'true'), true) end

local function log(fmt, ...) print(('[fh_core:spawn] ' .. fmt):format(...)) end

local function newToken()
    return ('%08x%08x'):format(math.random(0, 0x7fffffff), math.random(0, 0x7fffffff))
end

local function call(fn, ...)
    if type(fn) ~= 'function' and type(fn) ~= 'table' then return end -- cross-resource funcrefs arrive as tables
    local ok, err = pcall(fn, ...)
    if not ok then log('callback error: %s', tostring(err)) end
end

local function candidates()
    local out = {}
    for _, s in ipairs(GetPlayers()) do
        local id = tonumber(s)
        if id and ready[id] then
            local ped = GetPlayerPed(id)
            out[#out + 1] = { id = id, coords = ped ~= 0 and R.readCoords(GetEntityCoords(ped)) or nil }
        end
    end
    return out
end

-- Delete request to the client that made it. The client deletes only the entity it made for `token`, and only if it
-- has `netId` (nil netId = whatever it made for the token; sent only when nothing under that token was adopted).
local function sendDelete(playerId, req, token, netId)
    if playerId and token then
        TriggerClientEvent('fh:spawn:delete', playerId, { requestId = req and req.id, token = token, netId = netId })
    end
end

local function deleteEntity(entity)
    if entity and entity ~= 0 and DoesEntityExist(entity) then DeleteEntity(entity) end
end

local function ownerOf(entity)
    local ok, o = pcall(NetworkGetEntityOwner, entity)
    if ok and o and o > 0 then return o end -- -1 / 0: no owner (server-owned or unknown)
end

-- A retired attempt left a reported-but-unadopted entity (verifying). Ask its spawner to delete it, and delete it
-- server-side when FhSpawnRules.canCleanup proves it is ours: a dropped spawner can't delete it, and OneSync may have
-- migrated it to another client, which would leave two live entities for one request.
local function cleanupInflight(req, inflight)
    if not inflight then return end
    sendDelete(inflight.spawner, req, inflight.token, inflight.netId)
    local entity = NetworkGetEntityFromNetworkId(inflight.netId)
    local exists = entity ~= 0 and DoesEntityExist(entity)
    local info = { exists = exists, model = exists and GetEntityModel(entity) or nil,
        owner = exists and ownerOf(entity) or nil, claimedBy = R.findClaim(requests, inflight.netId, req.id) }
    if R.canCleanup(req, inflight, info) then
        DeleteEntity(entity)
        log('request %d: deleted unadopted netId %d from the retired attempt', req.id, inflight.netId)
    end
end

local function finish(req, outcome)
    if outcome == 'failed' then
        log('request %d failed: %s', req.id, tostring(req.failReason))
        requests[req.id] = nil
        call(req.onFailed, req.failReason, req.id)
    end
end

-- cands: optional candidate list (or a function returning it) so one tick reads player positions once, not per request.
local function tryDispatch(req, cands)
    if req.state ~= 'pending' and req.state ~= 'pending_no_client' then return end
    if type(cands) == 'function' then cands = cands() end
    local id = R.pickSpawner(cands or candidates(), req.near, setting('Range'), setting('FallbackAnyPlayer'), req.tried)
    if not id then
        if req.state == 'pending' then R.park(req) end
        return
    end
    local token = newToken()
    R.dispatch(req, id, token, GetGameTimer())
    local s = req.spec
    TriggerClientEvent('fh:spawn:create', id, {
        requestId = req.id, kind = s.kind, model = s.model, modelHash = s.modelHash,
        coords = s.coords, heading = s.heading, token = token,
        tag = s.tag, owner = s.owner, snap = s.snap, -- snap: world-01 block D ground-snap opt-out
    })
end

-- Outcome of a state change: clean up the retired attempt's entity, then dispatch again or report failure.
local function after(req, outcome, inflight, cands)
    cleanupInflight(req, inflight)
    if outcome == 'retry' or outcome == 'rerequest' or outcome == 'despawn_rerequest' then tryDispatch(req, cands)
    else finish(req, outcome) end
end

local function verify(req, src, token, netId)
    local waitMs, entity = setting('AdoptWaitMs') or 3000, 0
    local t = GetGameTimer() + waitMs
    while GetGameTimer() < t do -- the entity can reach the server a few frames after the client has its netId
        if req.state ~= 'verifying' or req.token ~= token then return end
        entity = NetworkGetEntityFromNetworkId(netId)
        if entity ~= 0 and DoesEntityExist(entity) then
            R.noteOwner(req, token, ownerOf(entity))
            break
        end
        Wait(100)
    end
    if req.state ~= 'verifying' or req.token ~= token then return end -- retried/despawned meanwhile: cleaned up there
    local exists = entity ~= 0 and DoesEntityExist(entity)
    local isPlayer = false
    if exists and R.isPedKind(req.spec.kind) then -- objects and wagons are never player peds
        local ok, p = pcall(IsPedAPlayer, entity)
        isPlayer = ok and p == true or (ok and p == 1)
    end
    local ok, reason = R.checkEntity(req, {
        exists = exists, model = exists and GetEntityModel(entity) or nil,
        coords = exists and GetEntityCoords(entity) or nil, owner = exists and ownerOf(entity) or nil,
        claimedBy = R.findClaim(requests, netId, req.id), isPlayer = isPlayer,
    }, setting('AdoptMaxDistance'))
    local outcome, inflight = R.finishVerify(req, token, ok, reason, entity)
    if outcome == nil then return end
    if outcome == 'adopted' then
        if not gated() then pcall(SetEntityOrphanMode, entity, 2) end -- 2 = KeepEntity (ungated path, S1-proven)
        TriggerClientEvent('fh:spawn:release', src, { requestId = req.id, token = token, netId = netId })
        log('request %d adopted netId %d from %d', req.id, netId, src)
        call(req.onReady, netId, req.id)
        return
    end
    log('request %d: entity rejected (%s), retrying', req.id, tostring(reason))
    after(req, outcome, inflight)
end

RegisterNetEvent('fh:spawn:client_ready', function()
    ready[source] = true
end)

RegisterNetEvent('fh:spawn:created', function(data)
    local src = source
    if type(data) ~= 'table' then return end
    local req = requests[tonumber(data.requestId) or -1]
    local token = data.token
    local verifyMs = (setting('AdoptWaitMs') or 3000) + 2000 -- checkTimeout backstop if verify() never finishes
    local verdict, deleteNetId = R.onCreated(req, src, token, data.netId, GetGameTimer(), verifyMs)
    if verdict == 'verify' then
        local netId = req.netId
        return CreateThread(function()
            local ok, err = pcall(verify, req, src, token, netId)
            if ok then return end
            log('request %d: verify error: %s', req.id, tostring(err))
            local outcome, inflight = R.finishVerify(req, token, false, 'fh_spawn_verify_error')
            if outcome then after(req, outcome, inflight) end
        end)
    end
    if verdict == 'same' then return end
    -- duplicate / stale / unknown: the sender deletes that one extra entity (never the live netId: FhSpawnRules).
    if deleteNetId then sendDelete(src, req, token, deleteNetId) end
    log('created from %d for request %s rejected: %s', src, tostring(data.requestId), verdict)
end)

RegisterNetEvent('fh:spawn:failed', function(data)
    local src = source
    if type(data) ~= 'table' then return end
    local req = requests[tonumber(data.requestId) or -1]
    local outcome, inflight = R.onClientFailed(req, src, data.token,
        type(data.reason) == 'string' and data.reason:sub(1, 64))
    if outcome == 'retry' or outcome == 'failed' then after(req, outcome, inflight) end
end)

-- Callbacks (onReady/onFailed) may call requestSpawn, so never iterate `requests` itself while acting on it.
local function requestIds()
    local out = {}
    for id in pairs(requests) do out[#out + 1] = id end
    table.sort(out)
    return out
end

local function lazyCandidates()
    local cached
    return function()
        cached = cached or candidates()
        return cached
    end
end

AddEventHandler('playerDropped', function()
    local src = tonumber(source)
    ready[src] = nil
    local isGated = gated()
    local cands = lazyCandidates()
    for _, id in ipairs(requestIds()) do
        local req = requests[id]
        if req then
            local entity = req.entity
            local owner
            if req.state == 'adopted' and entity and entity ~= 0 and DoesEntityExist(entity) then owner = ownerOf(entity) end
            local outcome, inflight = R.onPlayerDropped(req, src, isGated, owner)
            if outcome == 'despawn_rerequest' then
                deleteEntity(entity) -- gated: don't trust migration/orphan mode; recreate from another client
                log('request %d: owner %d dropped, despawned and re-requested', req.id, src)
            end
            if outcome and outcome ~= 'keep' then after(req, outcome, inflight, cands) end
        end
    end
end)

-- Tick: dispatch/verify timeouts, parked requests, adopted entities that vanished.
CreateThread(function()
    while true do
        Wait(setting('TickMs') or 1000)
        local now = GetGameTimer()
        local cands = lazyCandidates()
        for _, id in ipairs(requestIds()) do
            local req = requests[id]
            if not req then
                -- removed by a callback earlier in this tick
            elseif req.state == 'dispatched' or req.state == 'verifying' then
                local spawner, token = req.spawner, req.token
                local outcome, inflight = R.checkTimeout(req, now)
                if outcome then
                    if not inflight then sendDelete(spawner, req, token) end -- nothing reported under this token
                    after(req, outcome, inflight, cands)
                end
            elseif req.state == 'pending' or req.state == 'pending_no_client' then
                tryDispatch(req, cands)
            elseif req.state == 'adopted' and not (req.entity and DoesEntityExist(req.entity)) then
                log('request %d: adopted entity is gone, re-requesting', req.id)
                after(req, R.rerequest(req, 'fh_spawn_entity_gone'), nil, cands)
            end
        end
    end
end)

local function despawn(requestId)
    local req = requests[tonumber(requestId) or -1]
    if not req then return false, 'fh_spawn_unknown_request' end
    local d, err = R.despawn(req)
    requests[req.id] = nil
    if not d then return false, err end
    deleteEntity(d.entity)
    cleanupInflight(req, d.inflight)                -- despawned mid-verify
    sendDelete(d.spawner, req, d.token)             -- still being created: the spawner drops it when it arrives
    return true
end

---exports.fh_core:requestSpawn(spec, opts) -> requestId | nil, reason. See README "Spawn contract".
local function requestSpawn(spec, opts)
    local s, err = R.validateSpec(spec)
    if not s then return nil, err end
    local o
    o, err = R.validateOpts(opts, cfg())
    if not o then return nil, err end
    nextId = nextId + 1
    local req = R.newRequest(nextId, s, o)
    req.resource = GetInvokingResource() or GetCurrentResourceName()
    req.onReady, req.onFailed = opts and opts.onReady, opts and opts.onFailed
    requests[req.id] = req
    tryDispatch(req)
    return req.id
end

---exports.fh_core:getSpawn(requestId) -> { state, netId, tag, owner, kind, attempts } | nil
local function getSpawn(requestId)
    local req = requests[tonumber(requestId) or -1]
    if not req then return nil end
    return { state = req.state, netId = req.state == 'adopted' and req.netId or nil, tag = req.spec.tag,
        owner = req.spec.owner, kind = req.spec.kind, attempts = req.attempts }
end

---exports.fh_core:requestOfNetId(netId) -> requestId | nil. Only an adopted entity's current netId maps; so
---despawn(requestOfNetId(netId)) ends that entity's lifecycle (no re-request after it is deleted).
local function requestOfNetId(netId)
    return R.requestOfNetId(requests, netId)
end

exports('requestSpawn', requestSpawn)
exports('despawn', despawn)
exports('getSpawn', getSpawn)
exports('requestOfNetId', requestOfNetId)
FhSpawn = { requestSpawn = requestSpawn, despawn = despawn, getSpawn = getSpawn, requestOfNetId = requestOfNetId } -- same-resource callers (admin.lua)

AddEventHandler('onResourceStop', function(res)
    for _, id in ipairs(requestIds()) do
        local req = requests[id]
        if req and (res == GetCurrentResourceName() or req.resource == res) then despawn(id) end
    end
end)

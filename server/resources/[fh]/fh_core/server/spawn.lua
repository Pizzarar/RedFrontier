-- fh_core spawn-request contract, server side. State machine + validation: shared/spawn_rules.lua (FhSpawnRules).
-- The server owns the decision and the state; a chosen client creates the networked entity (client/spawn.lua); the
-- server adopts it by netId. Behaviour behind convar fh_spike_gated: docs/spike-gated.md.
-- Natives (docs/natives.md, all unverified in-game): GetPlayers, GetPlayerPed, GetEntityCoords,
-- NetworkGetEntityFromNetworkId, DoesEntityExist, GetEntityModel, NetworkGetEntityOwner, DeleteEntity,
-- SetEntityOrphanMode, GetConvar, GetGameTimer, GetInvokingResource. Not runtime-tested (no Cfx key yet).
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

local function sendDelete(playerId, req, token)
    if playerId and token then
        TriggerClientEvent('fh:spawn:delete', playerId, { requestId = req and req.id, token = token })
    end
end

local function deleteEntity(entity)
    if entity and entity ~= 0 and DoesEntityExist(entity) then DeleteEntity(entity) end
end

local function finish(req, outcome)
    if outcome == 'failed' then
        log('request %d failed: %s', req.id, tostring(req.failReason))
        requests[req.id] = nil
        call(req.onFailed, req.failReason, req.id)
    end
end

local function tryDispatch(req)
    if req.state ~= 'pending' and req.state ~= 'pending_no_client' then return end
    local id = R.pickSpawner(candidates(), req.near, setting('Range'), setting('FallbackAnyPlayer'), req.tried)
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
    })
end

-- Retry/re-request outcome: dispatch again now, or report failure.
local function after(req, outcome)
    if outcome == 'retry' or outcome == 'rerequest' or outcome == 'despawn_rerequest' then tryDispatch(req)
    else finish(req, outcome) end
end

local function verify(req, src, token, netId)
    local waitMs, entity = setting('AdoptWaitMs') or 3000, 0
    local t = GetGameTimer() + waitMs
    while GetGameTimer() < t do -- the entity can reach the server a few frames after the client has its netId
        if req.state ~= 'verifying' or req.token ~= token then return end
        entity = NetworkGetEntityFromNetworkId(netId)
        if entity ~= 0 and DoesEntityExist(entity) then break end
        Wait(100)
    end
    local exists = entity ~= 0 and DoesEntityExist(entity)
    local ok, reason = R.checkEntity(req, {
        exists = exists, model = exists and GetEntityModel(entity) or nil,
        coords = exists and GetEntityCoords(entity) or nil,
    }, setting('AdoptMaxDistance'))
    local outcome = R.finishVerify(req, token, ok, reason, entity)
    if outcome == nil then return end -- retried/despawned meanwhile; that path already cleaned up
    if outcome == 'adopted' then
        if not gated() then pcall(SetEntityOrphanMode, entity, 2) end -- 2 = KeepEntity (ungated path, S1-proven)
        log('request %d adopted netId %d from %d', req.id, netId, src)
        call(req.onReady, netId, req.id)
        return
    end
    log('request %d: entity rejected (%s), retrying', req.id, tostring(reason))
    sendDelete(src, req, token)
    after(req, outcome)
end

RegisterNetEvent('fh:spawn:client_ready', function()
    ready[source] = true
end)

RegisterNetEvent('fh:spawn:created', function(data)
    local src = source
    if type(data) ~= 'table' then return end
    local req = requests[tonumber(data.requestId) or -1]
    local token, netId = data.token, tonumber(data.netId)
    local verdict = R.onCreated(req, src, token, netId)
    if verdict == 'verify' then
        if not netId then
            sendDelete(src, req, token)
            return after(req, R.finishVerify(req, token, false, 'fh_spawn_no_entity'))
        end
        return CreateThread(function() verify(req, src, token, netId) end)
    end
    if verdict == 'same' then return end
    -- duplicate / stale / wrong_* / unknown: the sender deletes the entity it made for that token (if any).
    if verdict ~= 'wrong_source' then sendDelete(src, req, token) end
    log('created from %d for request %s rejected: %s', src, tostring(data.requestId), verdict)
end)

RegisterNetEvent('fh:spawn:failed', function(data)
    local src = source
    if type(data) ~= 'table' then return end
    local req = requests[tonumber(data.requestId) or -1]
    local outcome = R.onClientFailed(req, src, data.token, type(data.reason) == 'string' and data.reason:sub(1, 64))
    if outcome then after(req, outcome) end
end)

AddEventHandler('playerDropped', function()
    local src = tonumber(source)
    ready[src] = nil
    local isGated = gated()
    for _, req in pairs(requests) do
        local entity = req.entity
        local owner
        if req.state == 'adopted' and entity and entity ~= 0 and DoesEntityExist(entity) then
            local ok, o = pcall(NetworkGetEntityOwner, entity)
            owner = ok and o or nil
        end
        local outcome = R.onPlayerDropped(req, src, isGated, owner)
        if outcome == 'despawn_rerequest' then
            deleteEntity(entity) -- gated: don't trust migration/orphan mode; recreate from another client
            log('request %d: owner %d dropped, despawned and re-requested', req.id, src)
        end
        if outcome and outcome ~= 'keep' then after(req, outcome) end
    end
end)

-- Tick: dispatch timeouts, parked requests, adopted entities that vanished.
CreateThread(function()
    while true do
        Wait(setting('TickMs') or 1000)
        local now = GetGameTimer()
        for _, req in pairs(requests) do
            if req.state == 'dispatched' then
                local spawner, token = req.spawner, req.token
                local outcome = R.checkTimeout(req, now)
                if outcome then sendDelete(spawner, req, token); after(req, outcome) end
            elseif req.state == 'pending' or req.state == 'pending_no_client' then
                tryDispatch(req)
            elseif req.state == 'adopted' and not (req.entity and DoesEntityExist(req.entity)) then
                log('request %d: adopted entity is gone, re-requesting', req.id)
                after(req, R.rerequest(req, 'fh_spawn_entity_gone'))
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
    local entity = d.entity
    if not entity and d.netId then entity = NetworkGetEntityFromNetworkId(d.netId) end -- despawned mid-verify
    deleteEntity(entity)
    sendDelete(d.spawner, req, d.token) -- in flight: the spawner drops whatever it creates for that token
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

exports('requestSpawn', requestSpawn)
exports('despawn', despawn)
exports('getSpawn', getSpawn)
FhSpawn = { requestSpawn = requestSpawn, despawn = despawn, getSpawn = getSpawn } -- same-resource callers (admin.lua)

AddEventHandler('onResourceStop', function(res)
    for id, req in pairs(requests) do
        if res == GetCurrentResourceName() or req.resource == res then despawn(id) end
    end
end)

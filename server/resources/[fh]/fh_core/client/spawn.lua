-- fh_core spawn-request contract, client side. The server picks this client to create a networked entity
-- (fh:spawn:create), this file creates it and answers fh:spawn:created { requestId, token, netId } or
-- fh:spawn:failed { requestId, token, reason }. The server validates and adopts (server/spawn.lua).
-- fh:spawn:delete { requestId, token, netId? } deletes only an entity THIS client made for that token (and that netId
-- when given), so a forged, stale or duplicate message can never delete anything else, nor the adopted entity.
-- fh:spawn:release { token, netId } after adoption: forget it (server owns its lifetime).
-- Natives (docs/natives.md, all unverified in-game): RequestModel, HasModelLoaded, IsModelInCdimage, CreatePed,
-- CreateObject, CreateVehicle (wagon, B7), SetEntityHeading, _SET_RANDOM_OUTFIT_VARIATION (0x283978A15512B2FE), NetworkGetEntityIsNetworked,
-- NetworkGetNetworkIdFromEntity, NetworkDoesNetworkIdExist, SetModelAsNoLongerNeeded, SetEntityAsMissionEntity,
-- DoesEntityExist, DeleteEntity, GetGameTimer. Not runtime-tested (no Cfx key yet).
local MODEL_TIMEOUT_MS = 5000
local NETID_TIMEOUT_MS = 3000

-- [token] = { entity, netId, cancelled }. One entry per token: a repeated fh:spawn:create for a token is ignored, so
-- this client never makes two entities for one request attempt. Entries leave on delete or release (adopted).
local made = {}

local function fail(d, reason)
    TriggerServerEvent('fh:spawn:failed', { requestId = d.requestId, token = d.token, reason = reason })
end

local function loadModel(hash)
    if not IsModelInCdimage(hash) then return false end
    RequestModel(hash)
    local t = GetGameTimer() + MODEL_TIMEOUT_MS
    while not HasModelLoaded(hash) do
        if GetGameTimer() > t then return false end
        Wait(50)
    end
    return true
end

local function destroy(e)
    if e and e ~= 0 and DoesEntityExist(e) then
        SetEntityAsMissionEntity(e, true, true)
        DeleteEntity(e)
    end
end

local function create(d, slot)
    local c, hash = d.coords, d.modelHash
    if not loadModel(hash) then made[d.token] = nil; return fail(d, 'model_timeout') end
    local how = FhSpawnRules.CREATE[d.kind]
    -- Ground-snap (world-01 block D): ped/horse/object snap down to the floor under them (probe from 1.5 m above),
    -- unless the request opts out (snap == false); the +/-10 m guard keeps an off-floor point as-is. Wagons never snap.
    local z = c.z
    if how ~= 'vehicle' and FhGroundSnap.wantsSnap(d.snap) then
        z = FhGroundSnap.snapZ(c.z, FhSnap.groundZAt(d.tag or d.token, c.x, c.y, c.z, FhGroundSnap.SPAWN_PROBE_ABOVE), FhGroundSnap.SNAP_TOLERANCE)
    end
    local e
    if how == 'ped' then
        e = CreatePed(hash, c.x, c.y, z, d.heading + 0.0, true, true, false, false)
        if e and e ~= 0 then Citizen.InvokeNative(0x283978A15512B2FE, e, true) end -- else RDR3 peds can be invisible
    elseif how == 'object' then
        e = CreateObject(hash, c.x, c.y, z, true, true, false, false, false)
        if e and e ~= 0 then SetEntityHeading(e, d.heading + 0.0) end
    elseif how == 'vehicle' then
        -- CreateVehicle(model, x, y, z, heading, isNetwork, bScriptHostVeh, bDontAutoCreateDraftAnimals, p8):
        -- networked, draft horses auto-created by the game (they are not separate spawn requests)
        e = CreateVehicle(hash, c.x, c.y, c.z, d.heading + 0.0, true, true, false, false)
    end
    SetModelAsNoLongerNeeded(hash)
    if not e or e == 0 then made[d.token] = nil; return fail(d, 'create_failed') end
    slot.entity = e
    local t, netId = GetGameTimer() + NETID_TIMEOUT_MS, nil
    while GetGameTimer() < t and not slot.cancelled do
        if NetworkGetEntityIsNetworked(e) then
            netId = NetworkGetNetworkIdFromEntity(e)
            if netId and netId ~= 0 and NetworkDoesNetworkIdExist(netId) then break end
            netId = nil
        end
        Wait(50)
    end
    if slot.cancelled or not netId then
        made[d.token] = nil
        destroy(e)
        if not slot.cancelled then fail(d, 'no_netid') end
        return
    end
    slot.netId = netId
    TriggerServerEvent('fh:spawn:created', { requestId = d.requestId, token = d.token, netId = netId })
end

FH.onNet('fh:spawn:create', function(d)
    if type(d) ~= 'table' or type(d.token) ~= 'string' or type(d.coords) ~= 'table' then return end
    if made[d.token] then return end -- already handling this attempt
    local slot = { tag = type(d.tag) == 'string' and d.tag or nil, owner = d.owner, kind = d.kind }
    made[d.token] = slot
    FH.thread(function() create(d, slot) end)
end)

-- Delete what this client made for d.token. With d.netId set, only if it is that entity (a duplicate/stale netId
-- never matches the adopted one, and a forged message can't name anything this client didn't make).
FH.onNet('fh:spawn:delete', function(d)
    if type(d) ~= 'table' or d.token == nil then return end
    local slot = made[d.token]
    if not slot then return end
    if d.netId ~= nil and slot.netId ~= d.netId then return end
    if not slot.entity then slot.cancelled = true; return end -- still creating: create() drops it
    made[d.token] = nil
    destroy(slot.entity)
end)

-- The server adopted our entity: it owns its lifetime now (despawn is server-side), so stop tracking it.
FH.onNet('fh:spawn:release', function(d)
    if type(d) ~= 'table' or d.token == nil then return end
    local slot = made[d.token]
    if slot and slot.netId ~= nil and slot.netId == d.netId then
        made[d.token] = nil
        -- Post-adopt hook: other resources set the entity up (AI, relationship group, weapon) on THIS client.
        -- Local event (never networked): { requestId, tag, owner, kind, netId, entity }. Fires again after a re-request.
        TriggerEvent('fh:spawn:adopted', { requestId = d.requestId, tag = slot.tag, owner = slot.owner, kind = slot.kind,
            netId = slot.netId, entity = slot.entity })
    end
end)

FH.on('onClientResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for _, slot in pairs(made) do destroy(slot.entity) end
end)

-- Tell the server this client can take spawn requests (it only picks ready clients).
FH.thread(function()
    TriggerServerEvent('fh:spawn:client_ready')
end)

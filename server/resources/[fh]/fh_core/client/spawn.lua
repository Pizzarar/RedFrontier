-- fh_core spawn-request contract, client side. The server picks this client to create a networked entity
-- (fh:spawn:create), this file creates it and answers fh:spawn:created { requestId, token, netId } or
-- fh:spawn:failed { requestId, token, reason }. The server validates and adopts (server/spawn.lua).
-- fh:spawn:delete { requestId, token } deletes only an entity THIS client made for that token, so a forged or
-- stale request can never delete anything else.
-- Natives (docs/natives.md, all unverified in-game): RequestModel, HasModelLoaded, IsModelInCdimage, CreatePed,
-- CreateObject, SetEntityHeading, _SET_RANDOM_OUTFIT_VARIATION (0x283978A15512B2FE), NetworkGetEntityIsNetworked,
-- NetworkGetNetworkIdFromEntity, NetworkDoesNetworkIdExist, SetModelAsNoLongerNeeded, SetEntityAsMissionEntity,
-- DoesEntityExist, DeleteEntity, GetGameTimer. Not runtime-tested (no Cfx key yet).
local MODEL_TIMEOUT_MS = 5000
local NETID_TIMEOUT_MS = 3000

local made = {} -- [token] = entity

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

local function create(d)
    local c, hash = d.coords, d.modelHash
    if not loadModel(hash) then return fail(d, 'model_timeout') end
    local e
    if d.kind == 'ped' or d.kind == 'horse' then
        e = CreatePed(hash, c.x, c.y, c.z, d.heading + 0.0, true, true, false, false)
        if e and e ~= 0 then Citizen.InvokeNative(0x283978A15512B2FE, e, true) end -- else RDR3 peds can be invisible
    elseif d.kind == 'object' then
        e = CreateObject(hash, c.x, c.y, c.z, true, true, false, false, false)
        if e and e ~= 0 then SetEntityHeading(e, d.heading + 0.0) end
    end
    SetModelAsNoLongerNeeded(hash)
    if not e or e == 0 then return fail(d, 'create_failed') end
    made[d.token] = e
    local t, netId = GetGameTimer() + NETID_TIMEOUT_MS, nil
    while GetGameTimer() < t do
        if NetworkGetEntityIsNetworked(e) then
            netId = NetworkGetNetworkIdFromEntity(e)
            if netId and netId ~= 0 and NetworkDoesNetworkIdExist(netId) then break end
            netId = nil
        end
        Wait(50)
    end
    if not netId then
        made[d.token] = nil
        SetEntityAsMissionEntity(e, true, true)
        DeleteEntity(e)
        return fail(d, 'no_netid')
    end
    TriggerServerEvent('fh:spawn:created', { requestId = d.requestId, token = d.token, netId = netId })
end

FH.onNet('fh:spawn:create', function(d)
    if type(d) ~= 'table' or type(d.token) ~= 'string' or type(d.coords) ~= 'table' then return end
    FH.thread(function() create(d) end)
end)

FH.onNet('fh:spawn:delete', function(d)
    if type(d) ~= 'table' or d.token == nil then return end
    local e = made[d.token]
    made[d.token] = nil
    if e and DoesEntityExist(e) then
        SetEntityAsMissionEntity(e, true, true)
        DeleteEntity(e)
    end
end)

FH.on('onClientResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for _, e in pairs(made) do
        if DoesEntityExist(e) then DeleteEntity(e) end
    end
end)

-- Tell the server this client can take spawn requests (it only picks ready clients).
FH.thread(function()
    TriggerServerEvent('fh:spawn:client_ready')
end)

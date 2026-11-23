-- fh_core saddlebag client (B6e): /saddlebag finds the horse you are riding, else the nearest horse within reach, and
-- sends its netId. The server re-checks everything (entity exists, is a horse, within reach of the server-side ped).
-- Natives (UNVERIFIED in-game): GetMount, IsPedOnMount, GetClosestPed-style scan via GetGamePool, IsThisModelAHorse,
-- NetworkGetNetworkIdFromEntity, NetworkGetEntityIsNetworked. NOT runtime-tested.
local SCAN = 4.0 -- metres; the server enforces the real reach

local function findHorse()
    local me = PlayerPedId()
    if IsPedOnMount(me) then
        local m = GetMount(me)
        if m and m ~= 0 then return m end
    end
    local mc, best, bestD = GetEntityCoords(me), nil, SCAN
    for _, p in ipairs(GetGamePool('CPed')) do
        if p ~= me and IsThisModelAHorse(GetEntityModel(p)) then
            local d = #(GetEntityCoords(p) - mc)
            if d <= bestD then best, bestD = p, d end
        end
    end
    return best
end

RegisterCommand('saddlebag', FH.wrap(function()
    local horse = findHorse()
    if not horse or not NetworkGetEntityIsNetworked(horse) then
        return TriggerEvent('chat:addMessage', { args = { 'fh', 'saddlebag: no horse in reach' } })
    end
    TriggerServerEvent('fh:saddlebag:open', { netId = NetworkGetNetworkIdFromEntity(horse) })
end), false)

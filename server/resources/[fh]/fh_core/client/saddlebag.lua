-- fh_core saddlebag client (B6e).
--   /saddlebag                      open the saddlebag at the horse you ride, else the nearest horse within 4 m
--   /saddlebag in <slot> [amount]   move a stack from the container you have OPEN (chest, camp stash) into the saddlebag
--   /saddlebag out <slot> [amount]  move a stack from the saddlebag into the container you have open
-- <slot> is the slot number in the SOURCE container. The server re-checks everything: the horse (entity type + model
-- allowlist), reach to the horse and to the open container, and which container is open (the client never names it).
-- Natives (UNVERIFIED in-game): GetMount, IsPedOnMount, GetGamePool, IsThisModelAHorse (client-only; a hint, the server
-- decides), NetworkGetNetworkIdFromEntity, NetworkGetEntityIsNetworked. NOT runtime-tested.
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

local function say(msg) TriggerEvent('chat:addMessage', { args = { 'fh', msg } }) end

RegisterCommand('saddlebag', FH.wrap(function(_, args)
    local horse = findHorse()
    if not horse or not NetworkGetEntityIsNetworked(horse) then return say('saddlebag: no horse in reach') end
    local netId = NetworkGetNetworkIdFromEntity(horse)
    local dir = args[1]
    if dir == nil then return TriggerServerEvent('fh:saddlebag:open', { netId = netId }) end
    if dir ~= 'in' and dir ~= 'out' then return say('usage: /saddlebag | /saddlebag in|out <slot> [amount]') end
    local slot, amount = tonumber(args[2]), args[3] and tonumber(args[3]) or nil
    if not slot or (args[3] and not amount) then return say('usage: /saddlebag in|out <slot> [amount]') end
    TriggerServerEvent('fh:saddlebag:transfer', { netId = netId, dir = dir, slot = slot, amount = amount })
end), false)

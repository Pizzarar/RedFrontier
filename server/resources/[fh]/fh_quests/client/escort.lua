-- fh_quests escort client (quests-02 C3): the escortee follows its holder. The server decides everything else
-- (spawn, arrival, lost: server/watch.lua escort section). Minimal on purpose: the holder's client asks for control
-- of the escortee and tasks it to follow the local player; it re-tasks after a control change or a respawn (new
-- netId arrives with a new fh:quests:escort_follow). Fallback "meet at the destination" is NOT here (plan Open).
-- Natives (all unverified in-game; not yet in fh_core/docs/natives.md): NetworkDoesNetworkIdExist,
-- NetworkGetEntityFromNetworkId, DoesEntityExist, IsEntityDead, NetworkHasControlOfEntity, NetworkRequestControlOfEntity, SetBlockingOfNonTemporaryEvents,
-- TaskFollowToOffsetOfEntity, ClearPedTasks, PlayerPedId.
local CHECK_MS = 2000
local MISSING_CHECKS = 30 -- netId unknown here this many checks in a row (60 s): stop following it

local following = {} -- netId -> true while the server says this escortee follows us

local function follow(netId)
    local tasked, missing = nil, 0
    while following[netId] do
        Wait(CHECK_MS)
        if not following[netId] then break end
        if not NetworkDoesNetworkIdExist(netId) then
            missing = missing + 1
            tasked = nil
            if missing >= MISSING_CHECKS then following[netId] = nil end
        else
            missing = 0
            local ped = NetworkGetEntityFromNetworkId(netId)
            if ped ~= 0 and DoesEntityExist(ped) and not IsEntityDead(ped) then
                if not NetworkHasControlOfEntity(ped) then
                    tasked = nil
                    NetworkRequestControlOfEntity(ped)
                elseif tasked ~= ped then
                    SetBlockingOfNonTemporaryEvents(ped, true)
                    -- RDR3 TASK_FOLLOW_TO_OFFSET_OF_ENTITY 0x304AE42E357B8C7E: ped, target, offset x/y/z (a little
                    -- behind), speed, timeout (-1 = none), stop range, persistFollowing, p9, walkOnly, p11..p13
                    TaskFollowToOffsetOfEntity(ped, PlayerPedId(), 0.0, -2.0, 0.0, 2.0, -1, 2.0, true, false, false,
                        false, false, false)
                    tasked = ped
                end
            end
        end
    end
end

FH.onNet('fh:quests:escort_follow', function(d)
    local netId = type(d) == 'table' and tonumber(d.netId) or nil
    if not netId or following[netId] then return end
    following[netId] = true
    FH.thread(function() follow(netId) end)
end)

FH.onNet('fh:quests:escort_stop', function(d)
    local netId = type(d) == 'table' and tonumber(d.netId) or nil
    if not netId or not following[netId] then return end
    following[netId] = nil
    if NetworkDoesNetworkIdExist(netId) then
        local ped = NetworkGetEntityFromNetworkId(netId)
        if ped ~= 0 and DoesEntityExist(ped) and NetworkHasControlOfEntity(ped) then ClearPedTasks(ped) end
    end
end)

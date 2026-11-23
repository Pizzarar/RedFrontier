-- Family giver NPCs, client side: rsg-target zones open the fh_ui `dialogue` screen (server event fh:quests:ui_talk) and
-- the giver ped setup. The giver peds are spawned server side (fh_core requestSpawn); the target zone sits at the same
-- fixed point, TODO-verify-in-game.
local G = FhQuestsGivers

CreateThread(function()
    if GetResourceState('rsg-target') ~= 'started' then return end
    for _, id in ipairs(G.ORDER) do
        local g = G[id]
        exports['rsg-target']:addSphereZone({
            coords = vector3(g.coords.x, g.coords.y, g.coords.z), radius = 1.5, debug = false,
            options = { { label = 'Talk to ' .. g.label, icon = 'fa-solid fa-comments', distance = 2.5,
                onSelect = function() TriggerServerEvent('fh:quests:ui_talk', g.npc) end } },
        })
    end
end)

-- Giver peds (spawned by the server via fh_core, tag fh_quests:giver:<npc>): stand still, cannot be hurt or scared
-- off, ignore events. Like client/bounty.lua; natives unverified in-game.
local TAG_PREFIX = 'fh_quests:giver:'
FH.on('fh:spawn:adopted', function(d)
    if type(d) ~= 'table' or d.kind ~= 'ped' or type(d.tag) ~= 'string' or d.tag:sub(1, #TAG_PREFIX) ~= TAG_PREFIX then return end
    local ped = d.entity
    if not ped or not DoesEntityExist(ped) then return end
    FreezeEntityPosition(ped, true)
    SetEntityInvincible(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedFleeAttributes(ped, 0, false)
    SetPedCanRagdoll(ped, false)
end)

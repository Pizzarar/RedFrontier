-- fh_quests bounty client (permanent): makes the wanted NPC hostile on the client that spawned it. The server decides
-- everything else (spawn, death watch, credit: server/jobtypes.lua). Not part of the jobs-menu workaround.
-- The bounty target (spawned by the server via fh_core): hostile like the fh_zones camp peds.
-- Tag format: fh_quests:bounty:<region>:<key>. Natives as in fh_zones/client/main.lua (unverified in-game).
local TAG_PREFIX = 'fh_quests:bounty:'
FH.on('fh:spawn:adopted', function(d)
    if type(d) ~= 'table' or d.kind ~= 'ped' or type(d.tag) ~= 'string' or d.tag:sub(1, #TAG_PREFIX) ~= TAG_PREFIX then return end
    local ped = d.entity
    if not ped or not DoesEntityExist(ped) then return end
    AddRelationshipGroup('FH_BOUNTY')
    local group = joaat('FH_BOUNTY')
    SetPedRelationshipGroupHash(ped, group)
    SetRelationshipBetweenGroups(5, group, joaat('PLAYER'))
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedCombatAttributes(ped, 46, true)
    TaskCombatHatedTargetsAroundPed(ped, 60.0, 0)
end)

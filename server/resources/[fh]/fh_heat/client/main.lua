-- fh_heat R6 client: hostile AI for roadblock / ambush / chase peds (from fh_core's local post-adopt event
-- fh:spawn:adopted, same pattern as fh_zones) and the chase mount order. The server decides everything.
-- Natives (fh_core/docs/natives.md, all UNVERIFIED in game): AddRelationshipGroup, SetPedRelationshipGroupHash,
-- SetRelationshipBetweenGroups, GIVE_WEAPON_TO_PED (by hash; RDR3 has no GiveWeaponToPed_2), SetCurrentPedWeapon,
-- SetPedCombatAttributes, TaskCombatHatedTargetsAroundPed, SetBlockingOfNonTemporaryEvents, TaskMountAnimal,
-- NetworkGetEntityFromNetworkId.
local GROUP = 'FH_HEAT_HOSTILE'
local cfg = FhHeatConfig
local N_GIVE_WEAPON = 0x5E3BDDBCB83F3D84 -- GIVE_WEAPON_TO_PED(ped, weaponHash, ammo, bForceInHand, bForceInHolster, attachPoint, bAllowMultiple, p7, p8, addReason, bIgnoreUnlocks, permanentDegradation, p12)

local function setupPed(ped, weapon, standGround)
    AddRelationshipGroup(GROUP)
    local group = joaat(GROUP)
    SetPedRelationshipGroupHash(ped, group)
    SetRelationshipBetweenGroups(5, group, joaat('PLAYER')) -- 5 = hate
    SetRelationshipBetweenGroups(5, joaat('PLAYER'), group)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedCombatAttributes(ped, 46, true) -- always fight
    if weapon then
        local h = joaat(weapon)
        Citizen.InvokeNative(N_GIVE_WEAPON, ped, h, 100, true, true, 0x2CD419DC, false, 0.5, 1.0, 0, false, 0, false)
        SetCurrentPedWeapon(ped, h, true)
    end
    TaskCombatHatedTargetsAroundPed(ped, standGround and 40.0 or 120.0, 0)
end

-- tag = fh_heat:<kind>:<faction>:<index>[:<role>]
local function parseTag(tag)
    if type(tag) ~= 'string' then return nil end
    local kind, faction, idx, role = tag:match('^fh_heat:(%a+):(%w+):(%d+):?(%a*)$')
    return kind, faction, tonumber(idx), role ~= '' and role or nil
end

FH.on('fh:spawn:adopted', function(d)
    if type(d) ~= 'table' or d.kind ~= 'ped' then return end
    local kind, faction, _, role = parseTag(d.tag)
    if not kind or not d.entity or not DoesEntityExist(d.entity) then return end
    local block = cfg[kind] and cfg[kind].factions and cfg[kind].factions[faction]
    setupPed(d.entity, block and block.weapon or nil, kind == 'roadblock')
end)

-- Chase: the targeted player's client seats the rider on its horse (both are adopted networked entities).
FH.onNet('fh:heat:chase', function(d)
    if type(d) ~= 'table' then return end
    local function netId(v) return type(v) == 'number' and v == v and v > 0 and v % 1 == 0 and v or nil end
    local rid, hid = netId(d.rider), netId(d.horse)
    if not rid or not hid then return end
    local ok, rider, horse = pcall(function() return NetworkGetEntityFromNetworkId(rid), NetworkGetEntityFromNetworkId(hid) end)
    if not ok or not rider or not horse or rider == 0 or horse == 0 or not DoesEntityExist(rider)
        or not DoesEntityExist(horse) then return end
    pcall(TaskMountAnimal, rider, horse, 10000, -1, 2.0, 1, 0, 0)
end)

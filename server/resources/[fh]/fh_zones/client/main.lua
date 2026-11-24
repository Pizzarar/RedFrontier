-- fh_zones client: (1) hostile AI setup for adopted camp peds (runs on the client that created them, from fh_core's local
-- post-adopt event fh:spawn:adopted), (2) death hints to the server, (3) stash open prompt. Server decides everything.
-- Natives (fh_core/docs/natives.md, all UNVERIFIED in-game): AddRelationshipGroup, SetPedRelationshipGroupHash,
-- SetRelationshipBetweenGroups, GIVE_WEAPON_TO_PED (by hash; RDR3 has no GiveWeaponToPed_2), SetCurrentPedWeapon,
-- SetPedCombatAttributes, TaskCombatHatedTargetsAroundPed, SetBlockingOfNonTemporaryEvents, IsEntityDead,
-- DoesEntityExist, IsControlJustReleased. Not runtime-tested.
local rules = FhCampRules
local camps = {}                 -- [campId] = { weapons = { [idx] = name } }
local tracked = {}               -- [netId] = { entity, tag, reported }
local INPUT_CONTEXT = 0xCEFD9220 -- E (unverified)
local GROUP = 'FH_OUTLAWS'
local N_GIVE_WEAPON = 0x5E3BDDBCB83F3D84 -- GIVE_WEAPON_TO_PED(ped, weaponHash, ammo, bForceInHand, bForceInHolster, attachPoint, bAllowMultiple, p7, p8, addReason, bIgnoreUnlocks, permanentDegradation, p12)

local function setupPed(ped, weapon)
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
    TaskCombatHatedTargetsAroundPed(ped, 60.0, 0)
end

-- Fires on the spawning client after the server adopted the entity (again after a B4c re-request, on a new client).
FH.on('fh:spawn:adopted', function(d)
    if type(d) ~= 'table' or d.kind ~= 'ped' then return end
    local campId, idx = rules.parseTag(d.tag)
    if not campId or not d.entity or not DoesEntityExist(d.entity) then return end
    local camp = camps[campId] or (FH.refreshCamps and FH.refreshCamps()) and camps[campId]
    local def = camp and camp.weapons[idx]
    setupPed(d.entity, def ~= false and def or nil)
    tracked[d.netId] = { entity = d.entity, tag = d.tag }
end)

-- Report deaths of peds this client tracks (server re-checks health itself; this just makes it prompt).
FH.thread(function()
    while true do
        Wait(1000)
        for netId, t in pairs(tracked) do
            if not DoesEntityExist(t.entity) then
                tracked[netId] = nil
            elseif IsEntityDead(t.entity) then
                TriggerServerEvent('fh:zones:ped_dead', { tag = t.tag })
                tracked[netId] = nil
            end
        end
    end
end)

local function loadCamps()
    local list = lib.callback.await('fh:zones:camps', false) or {}
    for _, c in ipairs(list) do
        local weapons = {}
        for i, p in ipairs(c.peds) do weapons[i] = p.weapon or false end
        camps[c.id] = { weapons = weapons, loot = c.loot }
    end
    return list
end
FH.refreshCamps = function() loadCamps() return true end

FH.thread(function()
    for _, c in ipairs(loadCamps()) do
        lib.points.new({
            coords = c.loot, distance = 2.0,
            onEnter = FH.wrap(function() lib.showTextUI('[E] Outlaw camp stash') end),
            onExit = FH.wrap(function() lib.hideTextUI() end),
            nearby = FH.wrap(function()
                if IsControlJustReleased(0, INPUT_CONTEXT) then TriggerServerEvent('fh:zones:open_loot', { camp_id = c.id }) end
            end),
        })
    end
end)

FH.on('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    lib.hideTextUI()
end)

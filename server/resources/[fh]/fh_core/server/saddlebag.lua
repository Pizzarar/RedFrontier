-- fh_core saddlebag (B6e): one `saddlebag` container per character, used only at a horse. Rules: shared/saddlebag_rules.lua.
-- Natives used: GetPlayerPed, GetEntityCoords, NetworkGetEntityFromNetworkId, DoesEntityExist, GetEntityType,
-- IsPedAPlayer, GetEntityModel, GetGameTimer (see docs/natives.md; ALL UNVERIFIED IN-GAME). NOT runtime-tested (no Cfx key).
-- IsThisModelAHorse is client-only: the server validates a horse by entity type + model allowlist (FhConfig.Saddlebag).
-- The container is a world container (needs coords): its coords follow the horse (use) or the player (death).
-- Contents persist like the plot chest: fh_inventory keeps the stash by id.
local registeredIds = {} -- stash id -> true once registered this fh_core run (fh_core restart clears it with the table)
local lastCall = {}      -- [event][src] = GetGameTimer() of the last accepted call (rate limit)
local horseSet

local function citizenidOf(src)
    local c = exports['rsg-core']:GetCoreObject()
    local p = c and c.Functions.GetPlayer(src)
    return p and p.PlayerData.citizenid or nil
end

local function reply(src, msg) TriggerClientEvent('chat:addMessage', src, { args = { 'fh', msg } }) end

AddEventHandler('playerDropped', function()
    local src = source
    for _, t in pairs(lastCall) do t[src] = nil end
end)

---@return boolean true when the call may proceed
local function allowed(event, src)
    local cd = (FhConfig.Saddlebag and FhConfig.Saddlebag.OpenCooldownMs) or 500
    local t = lastCall[event]
    if not t then t = {}; lastCall[event] = t end
    local now = GetGameTimer()
    if t[src] and now - t[src] < cd then return false end
    t[src] = now
    return true
end

---Register (first time) or move (afterwards) the character's saddlebag at `coords`.
---@return table|nil ref, string|nil reason
local function ensure(citizenid, coords)
    local id = FhSaddlebagRules.stashId(citizenid)
    if not id then return nil, 'fh_no_character' end
    local ref = { type = 'saddlebag', id = id }
    local ok, why
    if registeredIds[id] then
        ok, why = exports.fh_core:setContainerCoords(ref, coords)
    else
        ok, why = exports.fh_core:registerContainer(ref, { coords = coords, label = 'Saddlebag' })
        if ok then registeredIds[id] = true end
    end
    if not ok then return nil, why end
    return ref
end

---Export for fh_death: stash id of the dying player's saddlebag (registered at the player's position so it can be
---read and emptied), or nil.
local function saddlebagOf(src)
    local cid = citizenidOf(src)
    local ped = GetPlayerPed(src)
    if not cid or ped == 0 then return nil end
    local ref = ensure(cid, GetEntityCoords(ped))
    return ref and ref.id or nil
end

---Read the horse entity for a client-supplied netId with server natives only.
local function readHorse(netId)
    local ent = NetworkGetEntityFromNetworkId(netId)
    if not ent or ent == 0 or not DoesEntityExist(ent) then return { exists = false } end
    local isPlayer = IsPedAPlayer(ent)
    return {
        exists = true, entityType = GetEntityType(ent), isPlayer = isPlayer == true or isPlayer == 1,
        model = GetEntityModel(ent), coords = GetEntityCoords(ent),
    }
end

local function horses()
    if not horseSet then
        horseSet = FhSaddlebagRules.horseSet(FhConfig.Saddlebag and FhConfig.Saddlebag.HorseModels, FhSpawnRules.modelHash)
    end
    return horseSet
end

local function validNetId(n) return type(n) == 'number' and n >= 1 and n % 1 == 0 end

RegisterNetEvent('fh:saddlebag:open', function(payload)
    local src = source
    if type(payload) ~= 'table' or not validNetId(payload.netId) then return end
    if not allowed('open', src) then return end
    local cid, ped = citizenidOf(src), GetPlayerPed(src)
    if not cid or ped == 0 then return end
    local horse = readHorse(payload.netId)
    local ok, why = FhSaddlebagRules.canAccess(cid, horse, GetEntityCoords(ped),
        FhContainers.interactDistance('saddlebag'), horses())
    if not ok then return reply(src, 'saddlebag: ' .. why) end
    local ref, rwhy = ensure(cid, horse.coords)
    if not ref then return reply(src, 'saddlebag: ' .. tostring(rwhy)) end
    local oOk, oWhy = exports.fh_core:open(src, ref)
    if not oOk then reply(src, 'saddlebag: ' .. tostring(oWhy)) end
end)

-- Container-to-container transfer (bulky items cannot go through the backpack, so a chest/camp stash <-> saddlebag
-- move has no UI path otherwise). The container is NEVER client-named: it is the pane fh_inventory says this player
-- has open (FhOpenRef). One fh_core.move does the work: it re-plans under the rules veto (size class, weight, slot)
-- and fh_inventory re-checks and applies it atomically, so an item is moved exactly once or not at all.
RegisterNetEvent('fh:saddlebag:transfer', function(payload)
    local src = source
    if type(payload) ~= 'table' or not validNetId(payload.netId) then return end
    if not allowed('transfer', src) then return end
    local cid, ped = citizenidOf(src), GetPlayerPed(src)
    if not cid or ped == 0 then return end
    local pc = GetEntityCoords(ped)

    local openRef = exports.fh_core:openRef(src)
    local openView = openRef and exports.fh_core:view(openRef)
    if not openView then return reply(src, 'saddlebag: fh_nothing_open') end
    local horse = readHorse(payload.netId)
    local reach = FhContainers.interactDistance('saddlebag')
    -- gate on the horse BEFORE registering/moving the saddlebag to its coords (planTransfer re-checks everything)
    local ok, why = FhSaddlebagRules.canAccess(cid, horse, pc, reach, horses())
    if not ok then return reply(src, 'saddlebag: ' .. why) end
    local bagRef, bwhy = ensure(cid, horse.coords)
    local bagView = bagRef and exports.fh_core:view(bagRef)
    if not bagView then return reply(src, 'saddlebag: ' .. tostring(bwhy or 'fh_no_container')) end

    local plan, pwhy = FhSaddlebagRules.planTransfer({
        citizenid = cid, horse = horse, playerCoords = pc, reach = reach, horses = horses(),
        dir = payload.dir, slot = payload.slot, amount = payload.amount,
        open = { type = openRef.type, id = openRef.id, coords = openView.coords, slots = openView.slots,
            items = openView.items, reach = FhContainers.interactDistance(openRef.type) },
        bag = bagView,
    })
    if not plan then return reply(src, 'saddlebag: ' .. tostring(pwhy)) end

    local from, to = openRef, bagRef
    if plan.dir == 'out' then from, to = bagRef, openRef end
    local mok, mwhy = exports.fh_core:move(from, to, plan.fromSlot, plan.toSlot, plan.amount, src)
    reply(src, mok and ('saddlebag: moved (' .. plan.dir .. ')') or ('saddlebag: ' .. tostring(mwhy)))
end)

-- B6f: the gate for fh_inventory's saddlebag player pane (convar fh_saddlebag_pane, read by fh_inventory). Same horse
-- check as fh:saddlebag:open (server natives; the netId only locates the entity), then the bag is registered / moved
-- to the horse. fh_inventory calls this on the toggle, before every action on the pane, and once a second.
---@return boolean ok, string stash id | reason
local function saddlebagPane(src, netId)
    if not validNetId(netId) then return false, 'fh_no_horse' end
    local cid, ped = citizenidOf(src), GetPlayerPed(src)
    if not cid or ped == 0 then return false, 'fh_no_character' end
    local horse = readHorse(netId)
    local ok, why = FhSaddlebagRules.canAccess(cid, horse, GetEntityCoords(ped),
        FhContainers.interactDistance('saddlebag'), horses())
    if not ok then return false, why end
    local ref, rwhy = ensure(cid, horse.coords)
    if not ref then return false, tostring(rwhy or 'fh_no_container') end
    return true, ref.id
end

exports('saddlebagOf', saddlebagOf)
exports('saddlebagPane', saddlebagPane)

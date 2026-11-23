-- fh_core saddlebag (B6e): one `saddlebag` container per character, opened only at a horse. Rule: shared/saddlebag_rules.lua.
-- Natives used: GetPlayerPed, GetEntityCoords, NetworkGetEntityFromNetworkId, DoesEntityExist, GetEntityModel,
-- IsThisModelAHorse (see docs/natives.md; ALL UNVERIFIED IN-GAME). NOT runtime-tested (no Cfx key).
-- The container is a world container (needs coords): its coords follow the horse (set at open) or the player (death).
-- Contents persist like the plot chest: fh_inventory keeps the stash by id.
local registeredIds = {} -- stash id -> true once registered this fh_core run (fh_core restart clears it with the table)

local function citizenidOf(src)
    local c = exports['rsg-core']:GetCoreObject()
    local p = c and c.Functions.GetPlayer(src)
    return p and p.PlayerData.citizenid or nil
end

local function reply(src, msg) TriggerClientEvent('chat:addMessage', src, { args = { 'fh', msg } }) end

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

RegisterNetEvent('fh:saddlebag:open', function(payload)
    local src = source
    local netId = type(payload) == 'table' and payload.netId
    if type(netId) ~= 'number' or netId < 1 or netId % 1 ~= 0 then return end
    local cid = citizenidOf(src)
    local ped = GetPlayerPed(src)
    if not cid or ped == 0 then return end

    local horse = { exists = false }
    local ent = NetworkGetEntityFromNetworkId(netId)
    if ent and ent ~= 0 and DoesEntityExist(ent) then
        -- UNVERIFIED native: IsThisModelAHorse(model)
        local isHorse = IsThisModelAHorse(GetEntityModel(ent))
        horse = { exists = true, isHorse = isHorse == true or isHorse == 1, coords = GetEntityCoords(ent) }
    end
    local reach = FhContainers.interactDistance('saddlebag')
    local ok, why = FhSaddlebagRules.canAccess(cid, horse, GetEntityCoords(ped), reach)
    if not ok then return reply(src, 'saddlebag: ' .. why) end
    local ref, rwhy = ensure(cid, horse.coords)
    if not ref then return reply(src, 'saddlebag: ' .. tostring(rwhy)) end
    local oOk, oWhy = exports.fh_core:open(src, ref)
    if not oOk then reply(src, 'saddlebag: ' .. tostring(oWhy)) end
end)

exports('saddlebagOf', saddlebagOf)

-- fh_hunting server (spec L8). H1: item registration and the pure-rule exports. H2: the skin request
-- (fh:hunting:skin); the decision lives in shared/skin.lua, this file only wires natives and exports into it.
-- Natives (fh_core/docs/natives.md, all UNVERIFIED in-game): GetPlayerPed, GetEntityCoords, NetworkGetEntityFromNetworkId,
-- DoesEntityExist, GetEntityType, IsPedAPlayer, GetEntityModel, GetEntityHealth, DeleteEntity, GetGameTimer; state bags.
local animals, price, cfg = FhHuntingAnimals, FhHuntingPrice, FhHuntingConfig

local function registerItems()
    local ok, err, bad = exports.fh_core:registerItems(animals.itemDefs())
    if not ok then print(('^1[fh_hunting] registerItems failed: %s (%s)^7'):format(tostring(err), tostring(bad))) end
    return ok
end

-- fh_core keeps runtime definitions in memory, so a restart of fh_core loses them: register again.
AddEventHandler('onResourceStart', function(res)
    if res == GetCurrentResourceName() or res == 'fh_core' then registerItems() end
end)

exports('getAnimal', function(model, legendary) return animals.get(model, legendary) end)
exports('getPeltItem', function(model, legendary)
    local a = animals.get(model, legendary)
    return a and a.pelt or nil
end)
-- Payout for a pelt item and star rating: amount | nil, err. The base value comes from the animal table.
exports('price', function(peltItem, stars)
    local a = animals.byPelt[peltItem]
    if not a then return nil, 'fh_unknown_pelt' end
    return price.price(a.value, a.fixedStars or stars, a.legendary == true, cfg)
end)

-- ---------------------------------------------------------------- H2 skin flow

local RSGCore
local function citizenidOf(src)
    if not RSGCore and GetResourceState('rsg-core') == 'started' then RSGCore = exports['rsg-core']:GetCoreObject() end
    local p = RSGCore and RSGCore.Functions.GetPlayer(src)
    return p and p.PlayerData.citizenid or nil
end

---Adapter: the wagon container a player owns or is using, near them. fh_core has no wagon lookup yet (wagons are
---@roads / M4; fh_core only knows the `wagon` container type), so this returns nil and every cargo pelt is refused
---with "bring a wagon". Contract requested from @core/@roads: a server export returning { ref, coords } for the
---player's owned/used wagon container. Keep this the only place that changes when it ships.
---@return table|nil { ref = { type = 'wagon', id }, coords }
local function findCargoWagon(src)
    return nil
end

---H4 sets this for the legendary bear it spawned (server-side memory, never a client-writable state bag).
local legendaryEntities = {}
FhHuntingLegendary = legendaryEntities

local function readCarcass(netId)
    local ent = NetworkGetEntityFromNetworkId(netId)
    if not ent or ent == 0 or not DoesEntityExist(ent) then return nil end
    local isPlayer = IsPedAPlayer(ent)
    return {
        entity = ent, isPed = GetEntityType(ent) == 1, isPlayer = isPlayer == true or isPlayer == 1,
        model = GetEntityModel(ent), coords = GetEntityCoords(ent), dead = GetEntityHealth(ent) <= 0,
        legendary = legendaryEntities[ent] == true,
    }
end

local function playerCoords(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return nil end
    return GetEntityCoords(ped)
end

local function saddlebagOf(src)
    local ok, id = pcall(function() return exports.fh_core:saddlebagOf(src) end)
    if not ok or type(id) ~= 'string' then return nil end
    return { type = 'saddlebag', id = id }
end

local function addItem(ref, name, amount, info)
    local ok, done, err = pcall(function() return exports.fh_core:addItem(ref, name, amount, info) end)
    if not ok then return false, 'fh_core_error' end
    return done == true, err
end

local function finishCarcass(ent)
    if not DoesEntityExist(ent) then return end
    Entity(ent).state:set('fhSkinned', true, true) -- clients hide the Skin option
    if cfg.DeleteCarcass then DeleteEntity(ent) end
end

local claims = FhHuntingSkin.newClaims()
local skinner = FhHuntingSkin.new({
    cfg = cfg, animals = animals, quality = FhHuntingQuality, claims = claims,
    deps = {
        citizenid = citizenidOf, playerCoords = playerCoords, readCarcass = readCarcass, saddlebagOf = saddlebagOf,
        findCargoWagon = findCargoWagon, addItem = addItem, finishCarcass = finishCarcass,
        accepts = function(t, sc) return (FhContainers.accepts(t, sc)) end,
        emit = function(name, payload) TriggerEvent(name, payload) end, -- server-only, never to clients
        rng = math.random,
    },
})

local function notify(src, kind, msg)
    TriggerClientEvent('ox_lib:notify', src, { title = 'Hunting', description = msg, type = kind })
end

local lastSkin = {}
AddEventHandler('playerDropped', function() lastSkin[source] = nil end)

-- Client request: { netId, bone?, hits?, explosive?, nativeQuality?, cleanliness? }. Everything is re-read here.
RegisterNetEvent('fh:hunting:skin', function(payload)
    local src = source
    local now = GetGameTimer()
    if lastSkin[src] and now - lastSkin[src] < cfg.SkinCooldownMs then return end
    lastSkin[src] = now
    local ok, res = skinner.skin(src, payload)
    if ok then
        local stars = res.stars and (' (' .. res.stars .. ' star' .. (res.stars == 1 and '' or 's') .. ')') or ''
        local where = res.container == 'wagon' and 'your wagon' or 'your saddlebag'
        notify(src, 'success', ('Pelt skinned%s, stowed in %s.'):format(stars, where))
    else
        notify(src, 'error', FhHuntingSkin.message(res, cfg))
    end
end)

-- Forget skinned carcasses that are gone (their netId may be reused).
CreateThread(function()
    while true do
        Wait(cfg.ClaimPruneMs)
        claims:prune(function(netId, e)
            return DoesEntityExist(e.token) and NetworkGetEntityFromNetworkId(netId) == e.token
        end)
    end
end)

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

local function playerCoords(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return nil end
    return GetEntityCoords(ped)
end

---Adapter: the wagon container the player owns or uses, near them: exports.fh_cargo:nearestWagon(src, coords, range)
---(roads-r1) -> { type = 'wagon', id = 'fh:wagon:<id>' } | nil. nil, a throw or a missing fh_cargo all mean "no wagon":
---the skin is refused and the carcass stays claimable. The shape adaptation is the pure FhHuntingWagon.find.
---@return table|nil { ref = { type = 'wagon', id }, coords }
local function findCargoWagon(src, coords)
    coords = coords or playerCoords(src)
    return FhHuntingWagon.find(function(s, c, range)
        return exports.fh_cargo:nearestWagon(s, c, range)
    end, src, coords, cfg.WagonRange)
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

-- ---------------------------------------------------------------- H3 trapper

-- WORKAROUND until @core removeItem export: take an item out of a world container. fh_core §4 has no remove export, so this goes through the rsg-inventory
-- compat RemoveItem (fh_inventory API.RemoveItem(containerId, name, amount, slot, reason); it only removes when the
-- slot really holds `name`). UNVERIFIED in game. Request to @core: a removeItem(ref, name, n, slot) export; this is
-- the only place that changes when it ships.
local function removeItem(ref, name, amount, slot)
    local ok, done = pcall(function()
        return exports['rsg-inventory']:RemoveItem(ref.id, name, amount, slot, 'hunting:pelt')
    end)
    return ok and done == true
end

local function snapshotOf(ref)
    local ok, items = pcall(function() return exports.fh_core:snapshot(ref) end)
    if not ok or type(items) ~= 'table' then return nil end
    return items
end

local function paySrc(src, amount, reason, region)
    local ok, done = pcall(function() return exports.fh_economy:pay(src, amount, reason, region) end)
    return ok and done == true
end

local trapper = FhHuntingSell.new({
    cfg = cfg, animals = animals, price = price,
    deps = {
        citizenid = citizenidOf, playerCoords = playerCoords, snapshot = snapshotOf, removeItem = removeItem,
        addItem = addItem, pay = paySrc,
        refFor = function(kind, src, pc)
            if kind == 'saddlebag' then return saddlebagOf(src) end
            local w = findCargoWagon(src, pc)
            return w and w.ref or nil
        end,
        emit = function(name, payload) TriggerEvent(name, payload) end, -- server-only, never to clients
        log = function(msg) print('^1[fh_hunting] ' .. msg .. '^7') end,
    },
})

local lastSell = {} -- [src] = { open = ms, sell = ms }
AddEventHandler('playerDropped', function() lastSell[source] = nil; trapper.busy[source] = nil end)

-- Per player and per event: ignore a request that comes within cfg.SellCooldownMs of the previous one.
local function sellThrottled(src, kind)
    local now = GetGameTimer()
    local t = lastSell[src]
    if not t then t = {}; lastSell[src] = t end
    if t[kind] and now - t[kind] < cfg.SellCooldownMs then return true end
    t[kind] = now
    return false
end

-- Client asks to open the sell menu; the server answers with the rows it computed itself.
RegisterNetEvent('fh:hunting:sell_open', function()
    local src = source
    if sellThrottled(src, 'open') then return end
    local rows, err = trapper.list(src)
    if not rows then return notify(src, 'error', FhHuntingSell.message(err)) end
    TriggerClientEvent('fh:hunting:sell_rows', src, rows)
end)

-- Client request: { container, slot, item }. Position, container, item, quality and price are all re-read here.
RegisterNetEvent('fh:hunting:sell', function(payload)
    local src = source
    if sellThrottled(src, 'sell') then return end
    local ok, res = trapper.sell(src, payload)
    if ok then
        notify(src, 'success', ('Sold %s (%d star%s) for $%d.'):format(res.label, res.stars, res.stars == 1 and '' or 's', res.price))
    else
        notify(src, 'error', FhHuntingSell.message(res))
    end
end)

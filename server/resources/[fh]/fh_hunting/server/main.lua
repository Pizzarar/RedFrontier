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

-- H5: comfort of a trophy item id (number) or nil. Pure lookup in shared/trophies.lua; no events (Homestead owns placement).
exports('getTrophyComfort', function(itemId) return FhHuntingTrophies.getComfort(itemId) end)

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

---H4 records the citizenid that owns each spawned legendary bear (server-side memory, never a client-writable state
---bag). Ownership scopes skinning: only that character's chain may skin the bear, and it is cleared on finish.
local legendaryEntities = {}
FhHuntingLegendary = legendaryEntities

local function readCarcass(netId)
    local ent = NetworkGetEntityFromNetworkId(netId)
    if not ent or ent == 0 or not DoesEntityExist(ent) then return nil end
    local isPlayer = IsPedAPlayer(ent)
    local owner = legendaryEntities[ent]
    return {
        entity = ent, isPed = GetEntityType(ent) == 1, isPlayer = isPlayer == true or isPlayer == 1,
        model = GetEntityModel(ent), coords = GetEntityCoords(ent), dead = GetEntityHealth(ent) <= 0,
        legendary = owner ~= nil, legendaryOwner = owner,
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
    legendaryEntities[ent] = nil -- the legendary owner is only relevant while the carcass exists
    Entity(ent).state:set('fhSkinned', true, true) -- clients hide the Skin option
    if cfg.DeleteCarcass then DeleteEntity(ent) end
end

local claims = FhHuntingSkin.newClaims()
local skinner = FhHuntingSkin.new({
    cfg = cfg, animals = animals, quality = FhHuntingQuality, claims = claims,
    deps = {
        citizenid = citizenidOf, playerCoords = playerCoords, readCarcass = readCarcass, saddlebagOf = saddlebagOf,
        findCargoWagon = findCargoWagon, addItem = addItem, finishCarcass = finishCarcass,
        releaseSpawn = function(netId) -- H7: skinned adopted animals are not re-requested by fh_core
            FhHuntingSkin.releaseSpawn(netId, {
                requestOfNetId = function(n) return exports.fh_core:requestOfNetId(n) end,
                despawn = function(id) return exports.fh_core:despawn(id) end,
            }, function(m) print(('^3[fh_hunting] spawn release: %s^7'):format(m)) end)
        end,
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
        local msg = ('Pelt skinned%s, stowed in %s.'):format(stars, where)
        if res.trophy then
            if res.trophy.container then
                local tw = res.trophy.container == 'wagon' and 'your wagon' or 'your saddlebag'
                msg = msg .. (' Trophy stowed in %s.'):format(tw)
            else
                msg = msg .. ' The trophy could not be stowed.'
            end
        end
        notify(src, 'success', msg)
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

local function snapshotOf(ref)
    local ok, items = pcall(function() return exports.fh_core:snapshot(ref) end)
    if not ok or type(items) ~= 'table' then return nil end
    return items
end

-- Take one pelt out of a world container (saddlebag / wagon) with fh_core:removeItem (B7). That export removes by name,
-- all-or-nothing, with no slot, so when a container holds several pelts of this name it may take a different slot
-- than the one the player asked for. To keep the payout honest the adapter snapshots before and after, finds the slot
-- that actually lost the pelt and hands its info back; shared/sell.lua then prices that pelt, not the requested one.
local function removeItem(ref, name, amount, slot)
    local before = snapshotOf(ref)
    if type(before) ~= 'table' then return false end
    local ok, done = pcall(function() return exports.fh_core:removeItem(ref, name, amount) end)
    if not ok or done ~= true then return false end
    local after = snapshotOf(ref) -- pcall'd: a throw here must not strand a removed pelt unpaid
    if type(after) == 'table' then
        for s, it in pairs(before) do
            if type(it) == 'table' and it.name == name then
                local now = after[s]
                if not now or now.name ~= name or (tonumber(now.amount) or 0) < (tonumber(it.amount) or 0) then
                    return true, { slot = s, info = it.info }
                end
            end
        end
    end
    return true, { slot = slot } -- removed, but could not tell which slot: price the requested one
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

-- ---------------------------------------------------------------- H4 legendary bear chain

local chain

local function chainNotify(src, kind, msg)
    TriggerClientEvent('ox_lib:notify', src, { title = 'Legendary Hunt', description = msg, type = kind })
end

local function pushChainState(src, cid)
    local s = chain.state(cid)
    TriggerClientEvent('fh:hunting:chain_state', src, { step = s.step, spawned = s.spawned, completed = s.completed })
end

---Server id of the online player with this citizenid, or nil.
local function playerByCid(cid)
    if not RSGCore and GetResourceState('rsg-core') == 'started' then RSGCore = exports['rsg-core']:GetCoreObject() end
    local p = RSGCore and RSGCore.Functions.GetPlayerByCitizenId(cid)
    return p and p.PlayerData and p.PlayerData.source or nil
end

---Charge the player for the rumour through fh_economy:charge (B7): ledger row, serialized per citizenid, never negative.
---@return boolean ok, string? err
local function chargeSrc(src, amount, reason, region_id)
    local called, ok, err = pcall(function() return exports.fh_economy:charge(src, amount, reason, region_id) end)
    if not called then return false, 'fh_charge_error' end
    if ok == true then return true end
    return false, type(err) == 'string' and err or 'fh_charge_error'
end

---Adapter: fh_core requestSpawn for the legendary bear. onReady marks the adopted entity as the cid's legendary (so the
---skin flow sees legendary + owner) and advances the chain; onFailed resets the chain so the player can retry.
local function requestLegendary(cid, chainCfg)
    local c = chainCfg.spawn.coords
    local ok, id = pcall(function()
        return exports.fh_core:requestSpawn({
            kind = 'ped', model = chainCfg.model,
            coords = vector4(c.x, c.y, c.z, c.heading or 0.0),
            owner = { kind = 'legendary_bear', id = cid },
            tag = 'fh_hunting:legendary_bear:' .. cid,
        }, {
            near = { x = c.x, y = c.y, z = c.z },
            onReady = function(netId)
                local ent = NetworkGetEntityFromNetworkId(netId)
                if ent and ent ~= 0 and DoesEntityExist(ent) then legendaryEntities[ent] = cid end
                chain.onAdopted(cid)
            end,
            onFailed = function(reason, requestId)
                print(('^1[fh_hunting] legendary bear spawn for %s failed: %s^7'):format(cid, tostring(reason)))
                if chain.onSpawnFailed(cid, requestId) then
                    local src = playerByCid(cid)
                    if src then
                        pushChainState(src, cid) -- back to the carcass clue, so the player can retry without relogging
                        chainNotify(src, 'error', FhHuntingChain.message('fh_chain_spawn_failed'))
                    end
                end
            end,
        })
    end)
    if not ok or not id then return nil end
    return id
end

chain = FhHuntingChain.new({
    cfg = cfg,
    deps = {
        load = function(cid)
            local ok, rows = pcall(MySQL.query.await,
                'SELECT step, spawn_request, spawned, completed FROM fh_hunting_chains WHERE citizenid = ? AND chain_id = ? LIMIT 1',
                { cid, FhHuntingChain.CHAIN_ID })
            if not ok or type(rows) ~= 'table' or #rows == 0 then return nil end
            local r = rows[1]
            return { chain_id = FhHuntingChain.CHAIN_ID, step = tonumber(r.step),
                spawn_request = tonumber(r.spawn_request), spawned = r.spawned == 1 or r.spawned == true,
                completed = r.completed == 1 or r.completed == true }
        end,
        save = function(cid, s)
            local ok = pcall(MySQL.update.await, [[
                INSERT INTO fh_hunting_chains (citizenid, chain_id, step, spawn_request, spawned, completed)
                VALUES (?, ?, ?, ?, ?, ?)
                ON DUPLICATE KEY UPDATE step = VALUES(step), spawn_request = VALUES(spawn_request),
                    spawned = VALUES(spawned), completed = VALUES(completed)
            ]], { cid, s.chain_id, s.step, s.spawn_request or 0, s.spawned and 1 or 0, s.completed and 1 or 0 })
            return ok
        end,
        charge = function(src, cid, amount, reason, region)
            return chargeSrc(src, amount, reason, region)
        end,
        spawn = function(cid, chainCfg) return requestLegendary(cid, chainCfg) end,
        despawn = function(requestId) pcall(function() exports.fh_core:despawn(requestId) end) end,
        emit = function(name, payload) TriggerEvent(name, payload) end,
    },
})

RegisterNetEvent('fh:hunting:chain_status', function()
    local src = source
    local cid = citizenidOf(src)
    if not cid then return end
    pushChainState(src, cid)
end)

RegisterNetEvent('fh:hunting:chain_rumour', function()
    local src = source
    local cid = citizenidOf(src)
    if not cid then return end
    local ok, res = chain.buyRumour(src, cid, playerCoords(src))
    if ok then
        chainNotify(src, 'success', 'The trapper pockets your money and points you toward fresh bear tracks to the east.')
        pushChainState(src, cid)
    else
        chainNotify(src, 'error', FhHuntingChain.message(res))
    end
end)

RegisterNetEvent('fh:hunting:chain_inspect', function(payload)
    local src = source
    local cid = citizenidOf(src)
    if not cid then return end
    local marker = type(payload) == 'table' and payload.marker or nil
    local ok, res = chain.inspect(cid, marker, playerCoords(src))
    if ok then
        if res.step == FhHuntingChain.STEP_SPAWNED then
            chainNotify(src, 'success', 'The trail ends at a clearing. Something huge is watching you.')
        else
            chainNotify(src, 'success', 'The trail leads on. Follow it.')
        end
        pushChainState(src, cid)
    else
        chainNotify(src, 'error', FhHuntingChain.message(res))
    end
end)

-- A legendary skin was granted (pelt_skinned with animal == legendary_bear): mark the chain complete.
AddEventHandler('fh:hunting:pelt_skinned', function(payload)
    if type(payload) ~= 'table' or payload.animal ~= 'legendary_bear' then return end
    if type(payload.citizenid) ~= 'string' then return end
    local ok, why = chain.onSkinned(payload.citizenid)
    if ok then
        -- Push step 5 (complete) to the client so the trapper prompt flips back to "Sell pelts" immediately.
        if type(payload.src) == 'number' and payload.src > 0 then pushChainState(payload.src, payload.citizenid) end
    elseif why ~= 'fh_chain_not_spawned' then
        print(('^3[fh_hunting] chain complete refused for %s: %s^7'):format(payload.citizenid, tostring(why)))
    end
end)

AddEventHandler('playerDropped', function()
    local cid = citizenidOf(source)
    if cid then chain.drop(cid) end
end)

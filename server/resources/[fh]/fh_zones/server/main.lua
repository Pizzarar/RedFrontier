-- fh_zones server: camp state machine idle -> active -> cleared -> respawn_wait -> idle (spec L89 L3 seed, M1 L107).
-- The server owns all state. Peds go through the B4c spawn contract (exports.fh_core:requestSpawn); death is decided by
-- the server reading the adopted entity's health, a client death report is only a hint that triggers an immediate check.
-- Natives: GetPlayers, GetPlayerPed, GetEntityCoords, GetEntityHealth, NetworkGetEntityFromNetworkId, DoesEntityExist,
-- GetGameTimer (fh_core/docs/natives.md, unverified in-game). NOT runtime-tested (no Cfx key yet).
local cfg = FhZonesConfig
local rules = FhCampRules

local camps = {} -- [campId] = { cfg, state, peds = { [i] = { reqId, netId, dead, failed } }, respawnAt }

local function log(fmt, ...) print(('[fh_zones] ' .. fmt):format(...)) end
local function stashRef(camp) return { type = 'chest', id = rules.stashId(camp.cfg.id) } end

-- ---------------------------------------------------------------- a-life ownership (fh_alife)
-- Camp ownership lives in fh_alife (built separately). These lookups are guarded: only consulted when fh_alife is
-- started, and wrapped in pcall; any failure or a missing fh_alife behaves exactly as today (nil owner, not law-held).

---@return boolean|nil lawHeld  (nil = unknown: fh_alife absent or the export failed)
local function isLawHeld(campId)
    if GetResourceState('fh_alife') ~= 'started' then return nil end
    local ok, res = pcall(function() return exports.fh_alife:isLawHeld(campId) end)
    if not ok then return nil end
    return res
end

---@return string|nil owner  (faction id, e.g. 'outlaws' | 'raiders' | 'lawmen' | 'rhodes_law')
local function getOwner(campId)
    if GetResourceState('fh_alife') ~= 'started' then return nil end
    local ok, res = pcall(function() return exports.fh_alife:getOwner(campId) end)
    if not ok then return nil end
    return res
end

for id, c in pairs(cfg.camps) do
    camps[id] = { cfg = c, state = 'idle', peds = {} }
end

local function step(camp, event)
    local nxt, err = rules.transition(camp.state, event)
    if not nxt then
        log('camp %s: refused %s from %s (%s)', camp.cfg.id, event, camp.state, tostring(err))
        return false
    end
    camp.state = nxt
    return true
end

-- ---------------------------------------------------------------- items + stash registration

local function registerItems()
    local ok, err, name = exports.fh_core:registerItems(cfg.items)
    if not ok then log('item registration failed: %s (%s)', tostring(err), tostring(name)) end
    return ok
end

local function registerStash(camp)
    local ok, why = exports.fh_core:registerContainer(stashRef(camp), { coords = camp.cfg.loot.coords, label = camp.cfg.loot.label })
    if not ok then log('camp %s: stash register failed: %s', camp.cfg.id, tostring(why)) end
    return ok
end

local function setup()
    registerItems()
    for _, camp in pairs(camps) do registerStash(camp) end
end

CreateThread(function()
    while GetResourceState('fh_core') ~= 'started' do Wait(500) end
    setup()
end)

-- fh_core restarts drop its registry (and despawn our requests): register again and reset to idle.
AddEventHandler('onResourceStart', function(res)
    if res ~= 'fh_core' then return end
    for _, camp in pairs(camps) do
        camp.peds, camp.state, camp.respawnAt, camp.retryAt = {}, 'idle', nil, nil
    end
    CreateThread(setup)
end)

-- ---------------------------------------------------------------- peds

local function despawnPeds(camp)
    for _, p in pairs(camp.peds) do
        if p.reqId then pcall(function() exports.fh_core:despawn(p.reqId) end) end
    end
    camp.peds = {}
end

local function spawnPed(camp, i, def)
    local entry = { dead = false, failed = false }
    camp.peds[i] = entry
    local id, err = exports.fh_core:requestSpawn({
        kind = 'ped', model = def.model, coords = vector4(def.coords.x, def.coords.y, def.coords.z, def.heading or 0.0),
        owner = { kind = 'camp', id = camp.cfg.id }, tag = rules.tagFor(camp.cfg.id, i),
    }, {
        near = def.coords,
        -- fires again with a new netId after B4c re-requests (spawner drop while fh_spike_gated). Same requestId.
        onReady = function(netId, requestId)
            if camp.peds[i] ~= entry then return end
            if entry.dead or camp.state ~= 'active' then
                -- a corpse that was cleaned up (or a camp that already ended) must not come back to life
                pcall(function() exports.fh_core:despawn(requestId) end)
                return
            end
            entry.netId = netId
        end,
        onFailed = function(reason)
            if camp.peds[i] ~= entry then return end
            entry.failed = true
            log('camp %s ped %d spawn failed: %s', camp.cfg.id, i, tostring(reason))
        end,
    })
    if not id then
        entry.failed = true
        log('camp %s ped %d refused: %s', camp.cfg.id, i, tostring(err))
        return
    end
    entry.reqId = id
end

local function isDead(entry)
    if not entry.netId then return false end
    local e = NetworkGetEntityFromNetworkId(entry.netId)
    if e == 0 or not DoesEntityExist(e) then return false end -- gone = B4c re-requests it; onReady drops it if dead
    return GetEntityHealth(e) <= 0
end

-- ---------------------------------------------------------------- state changes

local function activate(camp)
    if not step(camp, 'activate') then return end
    log('camp %s activated', camp.cfg.id)
    for i, def in ipairs(camp.cfg.peds) do spawnPed(camp, i, def) end
    TriggerEvent('fh:zones:camp_activated', { camp_id = camp.cfg.id, region_id = camp.cfg.region })
end

local function rollIntoStash(camp)
    local ref = stashRef(camp)
    exports.fh_core:clearContainer(ref)
    local table_ = rules.pickLootTable(cfg.lootByFaction, getOwner(camp.cfg.id), camp.cfg.loot.table, camp.cfg.tier)
    local items = rules.rollLoot(table_)
    local placed = {}
    for _, it in ipairs(items) do
        local ok, why = exports.fh_core:addItem(ref, it.name, it.amount, it.info)
        if ok then placed[#placed + 1] = it else log('camp %s: loot %s not placed: %s', camp.cfg.id, it.name, tostring(why)) end
    end
    return placed
end

local function citizenidOf(src)
    local c = exports['rsg-core']:GetCoreObject()
    local p = c and c.Functions.GetPlayer(src)
    return p and p.PlayerData.citizenid or nil
end

-- Players within activationRadius of the camp centre right now (citizenids). No damage tracking: presence only.
-- The lookup is guarded (rsg-core may be restarting): on error it logs and returns {} so clear() always reaches 'wait'.
local function campParticipants(camp)
    local list, err = rules.safeParticipants(camp.cfg.center, camp.cfg.activationRadius, function()
        local entries = {}
        for _, s in ipairs(GetPlayers()) do
            local src = tonumber(s)
            local ped = GetPlayerPed(src)
            if ped ~= 0 then entries[#entries + 1] = { citizenid = citizenidOf(src), pos = GetEntityCoords(ped) } end
        end
        return entries
    end)
    if err then log('camp %s: participants lookup failed: %s', camp.cfg.id, err) end
    return list
end

local function clear(camp)
    if not step(camp, 'clear') then return end
    local loot = rollIntoStash(camp)
    log('camp %s cleared, %d loot entries', camp.cfg.id, #loot)
    -- Drop the ped requests now: a dead ped left registered would be re-requested (fh_spike_gated spawner drop / corpse
    -- cleanup) and pop in alive until the respawn timer, then be despawned by onReady.
    despawnPeds(camp)
    TriggerEvent('fh:zones:camp_cleared', { camp_id = camp.cfg.id, region_id = camp.cfg.region, loot = loot, participants = campParticipants(camp) })
    step(camp, 'wait')
    camp.respawnAt = GetGameTimer() + math.floor(camp.cfg.respawnMinutes * 60000)
end

local function respawn(camp)
    if not step(camp, 'respawn') then return end
    despawnPeds(camp) -- no-op after clear(); kept for safety
    exports.fh_core:clearContainer(stashRef(camp))
    camp.respawnAt = nil
    log('camp %s respawned (idle)', camp.cfg.id)
    TriggerEvent('fh:zones:camp_respawned', { camp_id = camp.cfg.id, region_id = camp.cfg.region })
end

-- Every ped failed to spawn (bad model, retries used up): give up and go idle after a cooldown instead of wedging.
local function abort(camp)
    if not step(camp, 'abort') then return end
    despawnPeds(camp)
    camp.retryAt = GetGameTimer() + (cfg.AbortCooldownMs or 60000)
    log('camp %s aborted: every ped failed to spawn; retry in %d ms', camp.cfg.id, cfg.AbortCooldownMs or 60000)
end

-- Re-check ped deaths from server state and clear the camp when every ped is dead.
local function evaluate(camp)
    if camp.state ~= 'active' then return end
    local list = {}
    for i = 1, #camp.cfg.peds do
        local p = camp.peds[i]
        if p and not p.dead and isDead(p) then p.dead = true end
        list[i] = p or { dead = false, failed = false }
    end
    if rules.allDead(list) then clear(camp)
    elseif rules.allFailed(list) then abort(camp) end
end

local function playerPositions()
    local out = {}
    for _, s in ipairs(GetPlayers()) do
        local ped = GetPlayerPed(tonumber(s))
        if ped ~= 0 then out[#out + 1] = GetEntityCoords(ped) end
    end
    return out
end

CreateThread(function()
    while true do
        Wait(cfg.TickMs or 1000)
        local positions
        for _, camp in pairs(camps) do
            local ok, err = pcall(function()
                if camp.state == 'idle' then
                    positions = positions or playerPositions()
                    if rules.cooldownOver(GetGameTimer(), camp.retryAt) and rules.shouldWake(camp.state, camp.cfg, positions, isLawHeld(camp.cfg.id)) then activate(camp) end
                elseif camp.state == 'active' then
                    evaluate(camp)
                elseif camp.state == 'respawn_wait' and rules.respawnDue(GetGameTimer(), camp.respawnAt) then
                    respawn(camp)
                end
            end)
            if not ok then log('camp %s tick error: %s', camp.cfg.id, tostring(err)) end
        end
    end
end)

-- Client death report: a HINT only. Believed only from a player near the camp for a ped this camp owns, and it only
-- triggers an immediate server-side health check (a lying client can't clear a camp whose peds are alive).
RegisterNetEvent('fh:zones:ped_dead', function(payload)
    local src = source
    if type(payload) ~= 'table' then return end
    local campId, idx = rules.parseTag(payload.tag)
    local camp = campId and camps[campId]
    if not camp or camp.state ~= 'active' or not camp.peds[idx] then return end
    local ped = GetPlayerPed(src)
    if ped == 0 or not rules.canReport(camp.cfg, GetEntityCoords(ped)) then return end
    evaluate(camp)
end)

-- Client prompt -> open request. fh_core.open re-checks reach from the server-side ped position; the stash only
-- holds loot once the camp has been cleared (state respawn_wait).
RegisterNetEvent('fh:zones:open_loot', function(payload)
    local src = source
    if type(payload) ~= 'table' or type(payload.camp_id) ~= 'string' then return end
    local camp = camps[payload.camp_id]
    if not camp or camp.state ~= 'respawn_wait' then return end
    local ok, why = exports.fh_core:open(src, stashRef(camp))
    if not ok then TriggerClientEvent('chat:addMessage', src, { args = { 'fh', 'stash: ' .. tostring(why) } }) end
end)

-- Client asks what to draw/set up. Weapons come from our own config, never from the client.
lib.callback.register('fh:zones:camps', function()
    local out = {}
    for id, camp in pairs(camps) do
        local peds = {}
        for i, p in ipairs(camp.cfg.peds) do peds[i] = { weapon = p.weapon } end
        out[#out + 1] = { id = id, loot = camp.cfg.loot.coords, radius = camp.cfg.activationRadius, center = camp.cfg.center, peds = peds }
    end
    return out
end)

---exports.fh_zones:getCamp(id) -> { state, respawnAt } | nil
exports('getCamp', function(id)
    local c = camps[id]
    if not c then return nil end
    return { state = c.state, respawnAt = c.respawnAt }
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for _, camp in pairs(camps) do despawnPeds(camp) end -- fh_core also despawns by invoking resource
end)

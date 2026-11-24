-- fh_alife server/squads.lua (a-life-02 B2): materialise and despawn ambush squads on foot near players, and run a
-- server-side death watch that calls FhAlifeRules.onSquadKill. Squads are server-owned through fh_core requestSpawn
-- (owner tag { kind = 'alife_squad' }), inside fh_core's zone budget, and stay invisible while travelling: a squad
-- materialises only when it holds an ambush node AND a player is within ambushRadius. Despawning keeps its surviving
-- strength (only the death watch decrements strength). No visible riding.
-- Natives: GetPlayers, GetPlayerPed, GetEntityCoords, GetEntityHealth, NetworkGetEntityFromNetworkId,
-- DoesEntityExist, GetPedSourceOfDeath; all UNVERIFIED in game (no Cfx key yet). Spawn contract: fh_core README
-- "Spawn contract". Credit (squad_wiped participants) resolves citizenids via rsg-core exactly like fh_zones camp_cleared.
local rules = FhAlifeRules
local server = FhAlifeServer
local ctx = server.ctx

local function log(fmt, ...) print(('[fh_alife] ' .. fmt):format(...)) end

-- Materialisation knobs: FhAlifeConfig.squads = { ambushRadius, pedModel } (config.lua); literals are only the fallback.
local function setting(k, d)
    local t = FhAlifeConfig and FhAlifeConfig.squads
    return (t and t[k] ~= nil) and t[k] or d
end
local AMBUSH_RADIUS = setting('ambushRadius', 45.0) -- a player this close to a held node materialises its squad
local PED_MODEL = setting('pedModel', 'g_m_m_unibanditos_01')

local squads = {} -- squadId -> { squadId, peds = { [i] = { reqId, netId, dead, failed } } }

local function dist2d(ax, ay, bx, by)
    local dx, dy = ax - bx, ay - by
    return math.sqrt(dx * dx + dy * dy)
end

local function playerPositions()
    local out = {}
    for _, s in ipairs(GetPlayers()) do
        local src = tonumber(s)
        local ped = src and GetPlayerPed(src)
        if ped and ped ~= 0 then
            local c = GetEntityCoords(ped)
            if c and c.x then out[#out + 1] = c end
        end
    end
    return out
end

local function playerNear(node, positions)
    for _, p in ipairs(positions) do
        if dist2d(node.x, node.y, p.x, p.y) <= AMBUSH_RADIUS then return true end
    end
    return false
end

local function requestPed(squadId, rec, i, node, heading)
    local entry = { reqId = nil, netId = nil, dead = false, failed = false }
    rec.peds[i] = entry
    local id, err = exports.fh_core:requestSpawn({
        kind = 'ped', model = PED_MODEL, coords = vector4(node.x, node.y, node.z, heading),
        owner = { kind = 'alife_squad', id = squadId },
        tag = ('fh_alife:%s:%d'):format(squadId, i),
    }, {
        near = vector3(node.x, node.y, node.z),
        onReady = function(netId, requestId)
            if squads[squadId] ~= rec or entry.dead then
                pcall(function() exports.fh_core:despawn(requestId) end) return
            end
            entry.netId = netId
        end,
        onFailed = function(reason)
            if squads[squadId] ~= rec then return end
            entry.failed = true
            log('squad %s ped %d spawn failed: %s', squadId, i, tostring(reason))
        end,
    })
    if not id then
        entry.failed = true
        log('squad %s ped %d refused: %s', squadId, i, tostring(err))
        return
    end
    entry.reqId = id
end

local function materialise(squadId, sq, node)
    local rec = { squadId = squadId, peds = {} }
    squads[squadId] = rec
    local n = math.max(1, math.floor(sq.strength or 0))
    for i = 1, n do
        requestPed(squadId, rec, i, node, (360 / n) * (i - 1))
    end
    log('squad %s materialised at %s (%d peds)', squadId, tostring(node.id), n)
end

local function despawnSquad(squadId, reason)
    local rec = squads[squadId]
    if not rec then return end
    squads[squadId] = nil
    for _, p in ipairs(rec.peds) do
        if p.reqId then pcall(function() exports.fh_core:despawn(p.reqId) end) end
    end
    log('squad %s despawned (%s)', squadId, reason)
end

-- Returns dead?, entity. The entity lets the caller ask who killed it.
local function isDead(entry)
    if not entry.netId then return false end
    local e = NetworkGetEntityFromNetworkId(entry.netId)
    if e == 0 or not DoesEntityExist(e) then return false end -- gone = fh_core re-requests it; not a confirmed kill
    return GetEntityHealth(e) <= 0, e
end

---Killer entity of a dead ped (GetPedSourceOfDeath), or nil. Guarded: the native may be missing or throw.
local function killerOf(e)
    if type(GetPedSourceOfDeath) ~= 'function' then return nil end
    local ok, k = pcall(GetPedSourceOfDeath, e)
    if ok and k and k ~= 0 then return k end
    return nil
end

local function citizenidOf(src)
    local ok, cid = pcall(function()
        local c = exports['rsg-core']:GetCoreObject()
        local p = c and c.Functions.GetPlayer(src)
        return p and p.PlayerData.citizenid or nil
    end)
    return ok and cid or nil
end

---Citizenids credited for a wipe: every player whose ped is within ambushRadius of the node now (presence, via
---FhCampRules.safeParticipants — the same filter fh_zones uses for camp_cleared), plus any player whose ped killed a
---squad member (GetPedSourceOfDeath) even from outside the radius. Deduped; {} on any lookup failure, never nil.
local function wipeParticipants(squadId, rec, node)
    local killers = {}
    for _, p in ipairs(rec.peds) do if p.killer then killers[p.killer] = true end end
    local extra = {}
    local gather = function()
        local entries = {}
        for _, s in ipairs(GetPlayers()) do
            local src = tonumber(s)
            local ped = src and GetPlayerPed(src)
            if ped and ped ~= 0 then
                local cid = citizenidOf(src)
                entries[#entries + 1] = { citizenid = cid, pos = GetEntityCoords(ped) }
                if cid and killers[ped] then extra[#extra + 1] = cid end
            end
        end
        return entries
    end
    local list, err
    if FhCampRules and FhCampRules.safeParticipants then
        list, err = FhCampRules.safeParticipants(vector3(node.x, node.y, node.z), AMBUSH_RADIUS, gather)
    else
        list, err = {}, 'FhCampRules missing'
    end
    if err then log('squad %s: participants lookup failed: %s', squadId, tostring(err)) end
    local out, seen = {}, {}
    for _, src in ipairs({ list or {}, extra }) do
        for _, cid in ipairs(src) do
            if not seen[cid] then seen[cid] = true out[#out + 1] = cid end
        end
    end
    return out
end

-- One pass of the death watch: each dead ped takes 1 off the squad's strength (FhAlifeRules.onSquadKill); when the
-- squad is wiped, the survivors are despawned and fh:alife:squad_wiped is emitted.
local function checkDeaths(squadId, rec)
    local state = server.getState()
    for _, entry in ipairs(rec.peds) do
        local dead, e = false, nil
        if not entry.dead and not entry.failed then dead, e = isDead(entry) end
        if dead then
            entry.dead = true
            entry.killer = killerOf(e)
            local effects, err = rules.onSquadKill(ctx, state, squadId)
            if err then return end -- squad already gone (e.g. pruned): stop
            server.save()
            for _, e in ipairs(effects) do
                if e.type == 'squad_wiped' then
                    -- Canonical payload (fh_core/docs/events.md): snake_case like fh:zones:camp_cleared.
                    local node = ctx.graph.nodes[e.node]
                    TriggerEvent('fh:alife:squad_wiped', { squad_id = e.squad_id, node_id = e.node,
                        region_id = e.region_id, faction = e.faction, goal = e.goal, camp_id = e.camp_id,
                        label = e.label,
                        participants = node and wipeParticipants(squadId, rec, node) or {} })
                    despawnSquad(squadId, 'wiped')
                    return
                end
            end
        end
    end
end

-- ---------------------------------------------------------------- sweep (materialise / despawn / death watch)

local function sweep()
    local state = server.getState()
    local positions = playerPositions()
    -- squads that left the state or left 'hold' despawn (their surviving strength stays in state)
    do
        local gone = {}
        for squadId in pairs(squads) do
            local sq = state.squads[squadId]
            if not sq or sq.goal ~= 'ambush' or sq.phase ~= 'hold' then gone[#gone + 1] = squadId end
        end
        for _, squadId in ipairs(gone) do despawnSquad(squadId, 'left_node') end
    end
    -- materialise a held squad when a player is within ambushRadius, else despawn it
    for squadId, sq in pairs(state.squads) do
        if sq.goal == 'ambush' and sq.phase == 'hold' then
            local node = ctx.graph.nodes[sq.node]
            if node and playerNear(node, positions) then
                if not squads[squadId] then materialise(squadId, sq, node) end
            elseif squads[squadId] then
                despawnSquad(squadId, 'no_player_near')
            end
        end
    end
    -- death watch (snapshot: a wipe removes its record from `squads`)
    local snapshot = {}
    for squadId in pairs(squads) do snapshot[#snapshot + 1] = squadId end
    for _, squadId in ipairs(snapshot) do
        local rec = squads[squadId]
        if rec then checkDeaths(squadId, rec) end
    end
end

CreateThread(function()
    while true do
        Wait(1000)
        local ok, err = pcall(sweep)
        if not ok then log('squad sweep error: %s', tostring(err)) end
    end
end)

-- fh_core restart drops its spawn registry (and despawns our requests): drop our records so they re-materialise.
AddEventHandler('onResourceStart', function(res)
    if res ~= 'fh_core' then return end
    for squadId in pairs(squads) do squads[squadId] = nil end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    local all = {}
    for squadId in pairs(squads) do all[#all + 1] = squadId end
    for _, squadId in ipairs(all) do despawnSquad(squadId, 'resource_stop') end
end)

-- Test surface (stubbed server / plain Lua): sweep is idempotent and safe to call directly.
FhAlifeSquads = { sweep = sweep }

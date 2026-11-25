-- fh_alife server/squads.lua (a-life-02 B2): materialise and despawn ambush squads on foot near players, and run a
-- server-side death watch that calls FhAlifeRules.onSquadKill. Squads are server-owned through fh_core requestSpawn
-- (owner tag { kind = 'alife_squad' }), inside fh_core's zone budget, and stay invisible while travelling: a squad
-- materialises only when it holds an ambush node AND a player is within ambushRadius. Despawning keeps its surviving
-- strength (only the death watch decrements strength). No visible riding.
-- Natives: GetPlayers, GetPlayerPed, GetEntityCoords, GetEntityHealth, NetworkGetEntityFromNetworkId,
-- DoesEntityExist, GetPedSourceOfDeath; all UNVERIFIED in game (no Cfx key yet). Spawn contract: fh_core README
-- "Spawn contract". Credit (squad_wiped participants) resolves citizenids via rsg-core exactly like fh_zones camp_cleared.
-- a-life-03 C2: claim-raid squads (goal 'raid') in phase 'fight' have their own spawn branch: they materialise at the
-- claim's coords (FhAlifeServer.raidCenter, server/raids.lua) with owner tag FhAlifeRaidRules.OWNER_TAG while the
-- claim owner is online, with no player-proximity check, and despawn as soon as the owner drops or the fight phase
-- ends. The death watch routes every kill through FhAlifeRaidRules.onSquadKill (it wraps FhAlifeRules.onSquadKill),
-- which adds raid_repelled when a raid squad is wiped -> fh:alife:raid_repelled.
local raidRules = FhAlifeRaidRules
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
-- raid squads: credit radius around the claim at wipe = claimRaids.raidRadius (the same "owner home" radius)
local RAID_RADIUS = (FhAlifeConfig and FhAlifeConfig.claimRaids and tonumber(FhAlifeConfig.claimRaids.raidRadius)) or 60.0

-- squadId -> { squadId, kind = 'ambush'|'raid', center = {x,y,z}, radius, peds = { [i] = { reqId, netId, dead, failed } } }
local squads = {}

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

local function requestPed(squadId, rec, i, node, heading, ownerKind)
    local entry = { reqId = nil, netId = nil, dead = false, failed = false }
    rec.peds[i] = entry
    local id, err = exports.fh_core:requestSpawn({
        kind = 'ped', model = PED_MODEL, coords = vector4(node.x, node.y, node.z, heading),
        owner = { kind = ownerKind, id = squadId },
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

-- kind 'ambush': node = the ambush node, owner tag 'alife_squad'. kind 'raid': node = the claim center {x,y,z} (no
-- id), owner tag raidRules.OWNER_TAG. Peds stand on the point, spread by heading. TODO-verify-in-game for raids: the
-- claim center may sit on the house; an offset ring needs a ground-z source first.
local function materialise(squadId, sq, node, kind)
    kind = kind or 'ambush'
    local rec = { squadId = squadId, kind = kind, center = { x = node.x, y = node.y, z = node.z },
        radius = kind == 'raid' and RAID_RADIUS or AMBUSH_RADIUS, peds = {} }
    squads[squadId] = rec
    local ownerKind = kind == 'raid' and raidRules.OWNER_TAG or 'alife_squad'
    local n = math.max(1, math.floor(sq.strength or 0))
    for i = 1, n do
        requestPed(squadId, rec, i, node, (360 / n) * (i - 1), ownerKind)
    end
    log('squad %s (%s) materialised at %s (%d peds)', squadId, kind, tostring(node.id or sq.plot), n)
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

---Citizenids credited for a wipe: every player whose ped is within rec.radius of rec.center now (ambush: ambushRadius
---of the node; raid: claimRaids.raidRadius of the claim) (presence, via FhCampRules.safeParticipants — the same filter
---fh_zones uses for camp_cleared), plus any player whose ped killed a squad member (GetPedSourceOfDeath) even from
---outside the radius. Deduped; {} on any lookup failure, never nil.
local function wipeParticipants(squadId, rec)
    local node = rec.center
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
        list, err = FhCampRules.safeParticipants(vector3(node.x, node.y, node.z), rec.radius or AMBUSH_RADIUS, gather)
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

-- One pass of the death watch: each dead ped takes 1 off the squad's strength (FhAlifeRaidRules.onSquadKill, which
-- wraps FhAlifeRules.onSquadKill for every squad); when the squad is wiped, the survivors are despawned and
-- fh:alife:squad_wiped is emitted, plus fh:alife:raid_repelled (once, same participants) for a raid squad.
local function checkDeaths(squadId, rec)
    local state = server.getState()
    for _, entry in ipairs(rec.peds) do
        local dead, e = false, nil
        if not entry.dead and not entry.failed then dead, e = isDead(entry) end
        if dead then
            entry.dead = true
            entry.killer = killerOf(e)
            local effects, err = raidRules.onSquadKill(ctx, state, squadId)
            if err then return end -- squad already gone (e.g. pruned): stop
            server.save()
            local wiped, participants = false, nil
            for _, ef in ipairs(effects) do
                if ef.type == 'squad_wiped' or ef.type == 'raid_repelled' then
                    participants = participants or wipeParticipants(squadId, rec)
                end
                if ef.type == 'squad_wiped' then
                    wiped = true
                    -- Canonical payload (fh_core/docs/events.md): snake_case like fh:zones:camp_cleared.
                    TriggerEvent('fh:alife:squad_wiped', { squad_id = ef.squad_id, node_id = ef.node,
                        region_id = ef.region_id, faction = ef.faction, goal = ef.goal, camp_id = ef.camp_id,
                        label = ef.label, participants = participants })
                elseif ef.type == 'raid_repelled' then
                    TriggerEvent('fh:alife:raid_repelled', { plot_id = ef.plot_id, region_id = ef.region_id,
                        faction = ef.faction, camp_id = ef.camp_id, squad_id = ef.squad_id,
                        participants = participants })
                    if server.raidNotify then pcall(server.raidNotify, ef) end
                end
            end
            if wiped then
                despawnSquad(squadId, 'wiped')
                return
            end
        end
    end
end

---A raid squad that should stand at its claim now: phase 'fight', not cancelled, owner online (raids.lua's cache,
---cleared on playerDropped), and claim coords known. @return table|nil center {x,y,z}
local function raidFightCenter(sq)
    if sq.goal ~= raidRules.GOAL or sq.phase ~= 'fight' or sq.cancelled then return nil end
    if not (server.raidOwnerOnline and server.raidOwnerOnline(sq.citizenid)) then return nil end
    local c = server.raidCenter and server.raidCenter(sq)
    if type(c) == 'table' and tonumber(c.x) and tonumber(c.y) and tonumber(c.z) then return c end
    return nil
end

-- ---------------------------------------------------------------- sweep (materialise / despawn / death watch)

local function sweep()
    local state = server.getState()
    local positions = playerPositions()
    -- squads that left the state, left 'hold' (ambush) or left a live fight (raid) despawn (their surviving strength
    -- stays in state). Raid fight squads have their own branch: never swept as "not ambush".
    do
        local gone = {}
        for squadId, rec in pairs(squads) do
            local sq = state.squads[squadId]
            local keep
            if rec.kind == 'raid' then keep = sq ~= nil and raidFightCenter(sq) ~= nil
            else keep = sq ~= nil and sq.goal == 'ambush' and sq.phase == 'hold' end
            if not keep then gone[#gone + 1] = squadId end
        end
        for _, squadId in ipairs(gone) do
            despawnSquad(squadId, squads[squadId].kind == 'raid' and 'raid_over' or 'left_node')
        end
    end
    -- raid fight: materialise at the claim (no player-proximity check: the owner was home when it arrived)
    for squadId, sq in pairs(state.squads) do
        if not squads[squadId] then
            local c = raidFightCenter(sq)
            if c then materialise(squadId, sq, c, 'raid') end
        end
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

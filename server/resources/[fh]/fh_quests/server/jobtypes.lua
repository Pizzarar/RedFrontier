-- fh_quests built-in job types (Q3), registered through the public registerJobType export, exactly like an
-- external lane would (shared/jobtypes.lua holds the data and every verdict, specced). This file is I/O only:
-- registration and the bounty NPC (spawn via fh_core requestSpawn, server-side death watch).
--
-- Bounty death detection: the server polls GetEntityHealth(NetworkGetEntityFromNetworkId(netId)) <= 0 on the
-- adopted ped, the same check fh_zones already uses for camp peds (unverified in-game like every RDR3 entity
-- native; fh_core/docs/natives.md). It is NOT behind fh_spike_gated: if the check proves wrong, camp_clear
-- breaks the same way. Credit goes to the acceptor whoever lands the kill (README "bounty").
local JT, Jobs = FhQuestsJobTypes, FhQuestsJobs
local Q = FhQuestsServer

local POLL_MS = 2000
local watch = {} -- tag -> { tag, src, cid, qid, key, region_id, reqId, netId }

local function despawn(w)
    watch[w.tag] = nil
    if w.reqId then pcall(function() exports.fh_core:despawn(w.reqId) end) end
end

-- Spawn the bounty ped for an owner (accept, and re-arm after a relog / restart). Returns ok, err.
local function arm(src, cid, offer)
    if type(offer.region_id) ~= 'string' or type(offer.key) ~= 'string' or type(offer.coords) ~= 'table' then
        return false, 'fh_bad_offer'
    end
    local tag = JT.bountyTag(offer.region_id, offer.key)
    if watch[tag] then return false, 'fh_bounty_taken' end -- someone is already hunting this one
    local w = { tag = tag, src = src, cid = cid, qid = Jobs.questId('bounty', offer.key), key = offer.key,
        region_id = offer.region_id }
    local c = offer.coords
    local reqId, err = exports.fh_core:requestSpawn({
        kind = 'ped', model = offer.model, coords = vector4(c.x, c.y, c.z, offer.heading or 0.0),
        owner = { kind = 'quest', id = cid }, tag = tag,
    }, {
        near = vector3(c.x, c.y, c.z),
        onReady = function(netId, requestId) -- again with a new netId after a re-request (spawner drop)
            if watch[tag] ~= w then pcall(function() exports.fh_core:despawn(requestId) end) return end
            w.netId = netId
        end,
        onFailed = function(reason)
            if watch[tag] ~= w then return end
            watch[tag] = nil
            Q.log('bounty %s spawn failed: %s (the job stays open; relog or abandon)', tag, tostring(reason))
        end,
    })
    if not reqId then return false, type(err) == 'string' and err or 'fh_bounty_spawn_failed' end
    w.reqId = reqId
    watch[tag] = w
    return true
end

local function accept(src, offer)
    local cid = Q.citizenidOf(src)
    if not cid then return false, 'fh_no_player' end
    return arm(src, cid, offer)
end

local function abandon(_, state)
    for _, w in pairs(watch) do
        if w.cid == state.citizenid and w.qid == state.quest_id then despawn(w) end
    end
end

local function isDead(w)
    if not w.netId then return false end
    local e = NetworkGetEntityFromNetworkId(w.netId)
    if e == 0 or not DoesEntityExist(e) then return false end -- gone: fh_core re-requests it (onReady, new netId)
    return GetEntityHealth(e) <= 0
end

-- Credit only goes to an online acceptor: the character behind w.src must still be w.cid.
local function ownerOnline(w)
    return Q.srcOf[w.cid] == w.src and Q.citizenidOf(w.src) == w.cid
end

CreateThread(function()
    while true do
        Wait(POLL_MS)
        -- Snapshot first: TriggerEvent below yields (listeners take the quest lock), and an accept may insert into
        -- `watch` meanwhile, which would break a live pairs() traversal.
        for _, w in ipairs(JT.collectDead(watch, isDead)) do
            if watch[w.tag] == w then
                despawn(w)
                if ownerOnline(w) then
                    local ok, err = pcall(TriggerEvent, JT.BOUNTY_EVENT,
                        { citizenid = w.cid, offer_key = w.key, region_id = w.region_id })
                    if not ok then Q.log('^1bounty event for %s failed: %s^7', w.tag, tostring(err)) end
                end
            end
        end
    end
end)

-- Owner left (drop or character unload): despawn the ped and free the offer. The job row stays active, so nothing
-- persisted changes; the bounty is re-armed (a fresh ped) when the owner's character loads again (rearm below).
local function ownerGone(src)
    for _, w in ipairs(JT.ownedBy(watch, src)) do despawn(w) end
end
AddEventHandler('playerDropped', function() ownerGone(tonumber(source)) end)
AddEventHandler('RSGCore:Server:OnPlayerUnload', function(src) ownerGone(src) end)

-- Re-arm: an active bounty job whose ped does not exist (relog, or the server restarted) gets its ped again.
local function rearm(src)
    local cid = Q.citizenidOf(src)
    if not cid then return end
    local active = exports.fh_quests:getActive(src) or {}
    if Q.srcOf[cid] ~= src or Q.citizenidOf(src) ~= cid then return end -- dropped during the yield: no leaked ped/watch
    for _, e in ipairs(active) do
        local jt, key = Jobs.parseId(e.quest_id)
        if jt == 'bounty' and e.status == 'active' and e.region_id then
            local offer = JT.bountyOffer(e.region_id, key)
            if offer then
                local ok, err = arm(src, cid, offer)
                if not ok then Q.log('bounty %s not re-armed for %s: %s', key, cid, tostring(err)) end
            end
        end
    end
end

AddEventHandler('RSGCore:Server:PlayerLoaded', function(Player)
    local d = Player and Player.PlayerData
    local src = d and d.source
    if type(src) ~= 'number' then return end
    CreateThread(function()
        Wait(3000) -- fh_quests' own PlayerLoaded handler loads the rows first
        if Q.srcOf[d.citizenid] == src then pcall(rearm, src) end
    end)
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then
        for _, w in pairs(watch) do despawn(w) end
    end
end)

-- ---------------------------------------------------------------- registration
-- TODO(quests-04 L0): exports.fh_hunting:chainState(citizenid, chain_id) does not exist yet (@hunting L0).
-- Until L0 lands, this returns nil so the offer is shown. Once L0 lands, the GetResourceState + pcall + callable
-- check picks it up automatically and returns { reason = 'legendary_done' } when chainState == 'complete'.
local function legendaryLockedFor(offer, src)
    if GetResourceState('fh_hunting') ~= 'started' then return nil end
    local h = exports.fh_hunting
    if not h then return nil end
    local okFn, fn = pcall(function() return h.chainState end)
    if not okFn or not Jobs.callable(fn) then return nil end
    return JT.legendaryLockedFor(offer, src, {
        citizenidOf = Q.citizenidOf,
        huntingStarted = function() return true end,
        chainState = function(cid, chain_id) return h:chainState(cid, chain_id) end,
    })
end

local function hooks(job_type, extra)
    local h = {
        offers = function(region_id) return JT.offers(job_type, region_id) end,
        onEvent = function(name, payload, state) return JT.verdict(job_type, name, payload, state) end,
    }
    for k, v in pairs(extra or {}) do h[k] = v end
    return h
end

CreateThread(function()
    Wait(0) -- api.lua's exports are registered by now
    local defs = {
        hunt_request = hooks('hunt_request'),
        camp_clear = hooks('camp_clear'),
        supply_run = hooks('supply_run'),
        bounty = hooks('bounty', { accept = accept, abandon = abandon, events = { JT.BOUNTY_EVENT } }),
        survey = hooks('survey', FhQuestsWatch.jobHooks('survey')), -- reach-watcher (server/watch.lua)
        escort = hooks('escort', FhQuestsWatch.escortHooks()),       -- reach-watcher escort section
        rescue = hooks('rescue', FhQuestsWatch.rescueHooks()),       -- reach-watcher rescue section
        legendary = hooks('legendary', { lockedFor = legendaryLockedFor }),
    }
    for _, name in ipairs(JT.TYPES) do
        local ok, err = exports.fh_quests:registerJobType(name, defs[name])
        if not ok then Q.log('^1built-in job type %s not registered: %s^7', name, tostring(err)) end
    end
    for _, id in ipairs(GetPlayers()) do -- resource restart with players online: re-arm their bounties
        local src = tonumber(id)
        CreateThread(function() Wait(3000); pcall(rearm, src) end)
    end
    FhQuestsWatch.rearmAll() -- ... and their watched (survey) jobs
end)

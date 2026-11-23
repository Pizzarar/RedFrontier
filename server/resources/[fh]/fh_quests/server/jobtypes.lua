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
local watch = {} -- tag -> { tag, cid, qid, key, region_id, reqId, netId }

local function despawn(w)
    watch[w.tag] = nil
    if w.reqId then pcall(function() exports.fh_core:despawn(w.reqId) end) end
end

local function accept(src, offer)
    local cid = Q.citizenidOf(src)
    if not cid then return false, 'fh_no_player' end
    if type(offer.region_id) ~= 'string' or type(offer.key) ~= 'string' or type(offer.coords) ~= 'table' then
        return false, 'fh_bad_offer'
    end
    local tag = JT.bountyTag(offer.region_id, offer.key)
    if watch[tag] then return false, 'fh_bounty_taken' end -- someone is already hunting this one
    local w = { tag = tag, cid = cid, qid = Jobs.questId('bounty', offer.key), key = offer.key,
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
            Q.log('bounty %s spawn failed: %s (the job stays open until abandoned)', tag, tostring(reason))
        end,
    })
    if not reqId then return false, type(err) == 'string' and err or 'fh_bounty_spawn_failed' end
    w.reqId = reqId
    watch[tag] = w
    return true
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

CreateThread(function()
    while true do
        Wait(POLL_MS)
        for _, w in pairs(watch) do
            if isDead(w) then
                despawn(w)
                TriggerEvent(JT.BOUNTY_EVENT, { citizenid = w.cid, offer_key = w.key, region_id = w.region_id })
            end
        end
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then
        for _, w in pairs(watch) do despawn(w) end
    end
end)

-- ---------------------------------------------------------------- registration
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
        bounty = hooks('bounty', { accept = accept, abandon = abandon, events = { JT.BOUNTY_EVENT } }),
    }
    for _, name in ipairs(JT.TYPES) do
        local ok, err = exports.fh_quests:registerJobType(name, defs[name])
        if not ok then Q.log('^1built-in job type %s not registered: %s^7', name, tostring(err)) end
    end
end)

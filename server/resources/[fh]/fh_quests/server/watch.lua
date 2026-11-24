-- fh_quests server reach-watcher (quests-02 C2). I/O only: every decision is in shared/watch_rules.lua (specced).
-- Polls ONLY players holding a watched job (survey now; escort C3 and rescue C4 register a kind in their own
-- shared/jobtypes/<type>.lua via FhQuestsWatchRules.registerKind), on a coarse tick, with server-side coords
-- (GetEntityCoords(GetPlayerPed(src)), OneSync), and emits the kind's quest-owned local event
-- (default fh:quests:point_reached { citizenid, offer_key, region_id, point }). Same shape as the bounty watcher in
-- server/jobtypes.lua: accept arms, abandon / drop disarms, PlayerLoaded re-arms from the persisted progress.
--
-- Section layout: shared core (this file) | per-kind behaviour lives in the kind def (posOf / onArm / onDisarm),
-- so C3/C4 add a kind instead of editing the loop.
local WR, JT, Jobs = FhQuestsWatchRules, FhQuestsJobTypes, FhQuestsJobs
local Q = FhQuestsServer

local W = {}
FhQuestsWatch = W

local watch = {} -- WR.key(cid, qid) -> entry (shared/watch_rules.lua M.entry)
W.entries = watch -- read-only view for kinds (e.g. an escort death watch keyed by the same entry)

-- ---------------------------------------------------------------- core: arm / disarm
local function disarm(key, why)
    local e = watch[key]
    if not e then return end
    watch[key] = nil
    local kind = WR.KINDS[e.job_type]
    if kind and kind.onDisarm then
        local ok, err = pcall(kind.onDisarm, e, why)
        if not ok then Q.log('^1watch %s onDisarm threw: %s^7', e.job_type, tostring(err)) end
    end
end

-- Watch a held job for (src, cid). done = points already credited (0 on accept, the persisted count on re-arm).
local function arm(src, cid, job_type, offer, done)
    if type(offer) ~= 'table' or type(offer.key) ~= 'string' then return false, 'fh_bad_offer' end
    local qid = Jobs.questId(job_type, offer.key)
    local e, err = WR.entry(job_type, { cid = cid, src = src, qid = qid, offer_key = offer.key,
        region_id = offer.region_id }, offer, done)
    if not e then return false, err end
    local key = WR.key(cid, qid)
    disarm(key, 'rearm') -- a stale entry (resource restart, double load) never doubles up
    local kind = WR.KINDS[job_type]
    if kind.onArm then
        local called, ok, why = pcall(kind.onArm, e, offer)
        if not called then return false, 'fh_watch_arm_failed' end
        if ok == false then return false, type(why) == 'string' and why or 'fh_watch_arm_failed' end
    end
    watch[key] = e
    return true
end

-- Credit only goes to an online holder: the character behind e.src must still be e.cid.
local function ownerOnline(e)
    return Q.srcOf[e.cid] == e.src and Q.citizenidOf(e.src) == e.cid
end

local function playerPos(e)
    local ped = GetPlayerPed(e.src)
    if not ped or ped == 0 or not DoesEntityExist(ped) then return nil end
    return GetEntityCoords(ped)
end

-- Position that counts for an entry: the kind's posOf (e.g. the escortee) or the holder's ped. Only ever called by
-- WR.tick for entries in `watch`, so players without a watched job are never polled.
local function posOf(e)
    if not ownerOnline(e) then return nil end
    local kind = WR.KINDS[e.job_type]
    if kind and kind.posOf then return kind.posOf(e) end
    return playerPos(e)
end

-- ---------------------------------------------------------------- core: the tick
CreateThread(function()
    while true do
        Wait(WR.TICK_MS)
        if next(watch) ~= nil then
            -- Reconcile with the cached rows first (no lock, no yield): drops jobs finished or failed elsewhere and
            -- rolls back points that were emitted but never credited.
            for _, key in ipairs((function()
                local ks = {}
                for k in pairs(watch) do ks[#ks + 1] = k end
                return ks
            end)()) do
                local e = watch[key]
                local rows = Q.cache[e.cid]
                local row = rows and rows[e.qid]
                if WR.heal(e, row) == 'drop' then disarm(key, row.status == 'done' and 'done' or 'gone') end
            end
            -- WR.tick snapshots hits before anything yields; TriggerEvent below takes the quest lock.
            for _, hit in ipairs(WR.tick(watch, posOf)) do
                local e = hit.entry
                if watch[hit.key] == e then
                    local ok, err = pcall(TriggerEvent, WR.eventOf(e.job_type), WR.payload(e, hit.point))
                    if not ok then Q.log('^1watch event for %s failed: %s^7', hit.key, tostring(err)) end
                    -- hit.last: the entry stays (finished, so never polled) until heal sees the row done and drops
                    -- it, or sees the last credit never landed and rolls it back so the point can be reached again.
                end
            end
        end
    end
end)

-- ---------------------------------------------------------------- core: lifecycle
local function ownerGone(src)
    for _, key in ipairs(WR.ownedBy(watch, src)) do disarm(key, 'gone') end
end
AddEventHandler('playerDropped', function() ownerGone(tonumber(source)) end)
AddEventHandler('RSGCore:Server:OnPlayerUnload', function(src) ownerGone(src) end)

-- Re-arm every active watched job of src from its template + persisted progress count (relog, resource restart).
local function rearm(src)
    local cid = Q.citizenidOf(src)
    if not cid then return end
    local active = exports.fh_quests:getActive(src) or {}
    if Q.srcOf[cid] ~= src or Q.citizenidOf(src) ~= cid then return end -- dropped during the yield
    for _, j in ipairs(active) do
        local jt, key = WR.watchedJob(j.quest_id)
        if jt and j.status == 'active' and j.region_id then
            local offer = JT.offerByKey(jt, j.region_id, key)
            if offer then
                local ok, err = arm(src, cid, jt, offer, j.count)
                if not ok then Q.log('watch %s not re-armed for %s: %s', j.quest_id, cid, tostring(err)) end
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
    if res ~= GetCurrentResourceName() then return end
    local keys = {}
    for k in pairs(watch) do keys[#keys + 1] = k end
    for _, k in ipairs(keys) do disarm(k, 'stop') end
end)

-- ---------------------------------------------------------------- public: job-type hooks
---registerJobType hooks for a watched job type: { accept, abandon, events }. Merge into the type's own hooks.
function W.jobHooks(job_type)
    return {
        accept = function(src, offer)
            local cid = Q.citizenidOf(src)
            if not cid then return false, 'fh_no_player' end
            return arm(src, cid, job_type, offer, 0)
        end,
        abandon = function(_, state)
            if type(state) == 'table' then disarm(WR.key(state.citizenid, state.quest_id), 'abandon') end
        end,
        events = { WR.eventOf(job_type) },
    }
end

---Re-arm the watched jobs of every online player (resource restart). Called once types are registered.
function W.rearmAll()
    for _, id in ipairs(GetPlayers()) do
        local src = tonumber(id)
        CreateThread(function() Wait(3000); pcall(rearm, src) end)
    end
end

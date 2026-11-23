-- fh_quests server API (Q2): exports (README "Server exports") and the whitelisted fh:* event intake.
-- Thin glue over server/main.lua (FhQuestsServer) and the pure shared/ modules.
local Q = FhQuestsServer
local E, I, R, B, Jobs = FhQuestsEngine, FhQuestsIntake, FhQuestsRewards, FhQuestsBoard, FhQuestsJobs

local function regions() return FhRegions.regions end

---Run fn(cid, states) for src's character under its lock. Returns whatever fn returns, or false, err.
local function withPlayer(src, fn)
    if not Q.ready then return false, 'fh_not_ready' end
    local cid = Q.citizenidOf(src)
    if not cid then return false, 'fh_no_player' end
    Q.srcOf[cid] = src
    return Q.locked(cid, 5000, function()
        local states, err = Q.load(cid)
        if not states then return false, err end
        local res = table.pack(fn(cid, states))
        -- The player may have disconnected while fn held the lock (forget() leaves a busy cache alone): drop the
        -- rows now, like onIntake does. No yield between here and the lock release, so nothing can re-add src.
        if not Q.srcOf[cid] then Q.cache[cid] = nil end
        return table.unpack(res, 1, res.n)
    end)
end

-- ---------------------------------------------------------------- intake
local listening = {}

local function onIntake(name, payload)
    if not Q.ready or type(payload) ~= 'table' then return end
    local src = I.srcToResolve(payload)
    local resolved = src and Q.citizenidOf(src) or nil
    local p = I.payloadFor(payload, resolved)
    for _, cid in ipairs(I.targets(payload, resolved)) do
        local ok, err = Q.locked(cid, 30000, function()
            local states = Q.load(cid)
            if not states then return false, 'fh_db' end
            local defs = Q.defsFor(states)
            local changes, errors = I.feed(defs, states, name, p, os.time(), Q.hookFor)
            for _, e in ipairs(errors) do Q.log('onEvent hook for %s threw: %s', e.quest_id, e.err) end
            for _, c in ipairs(changes) do
                -- A synchronous fh:quests:* listener of an earlier commit may have re-entered the lock and changed
                -- this quest: never write the stale pre-computed `after` (intake.fresh recomputes or drops it).
                c = I.fresh(defs, states, c, name, p, os.time(), Q.hookFor)
                if c then Q.commit(defs[c.quest_id], c.after, c.effects) end
            end
            if #changes > 0 then Q.sync(cid) end
            if not Q.srcOf[cid] then Q.cache[cid] = nil end -- offline participant: don't keep the rows
            return true
        end)
        if not ok then Q.log('^3%s for %s dropped: %s^7', name, cid, tostring(err)) end
    end
end

---Subscribe to a server event (once). Local server events only: anything that arrives with a client source is
---dropped, so a client can never feed the intake even if some resource registers the name as a net event.
local function listen(name)
    if listening[name] then return end
    listening[name] = true
    AddEventHandler(name, function(payload)
        local s = tonumber(source)
        if s and s > 0 then return end
        if not I.accepts(name, Q.jobEvents) then return end -- e.g. a job type's event after it unregistered
        onIntake(name, payload)
    end)
end

for _, name in ipairs(E.INTAKE) do
    if I.accepts(name) then listen(name) end
end

-- ---------------------------------------------------------------- registries
local function rebuildJobEvents()
    local set = {}
    for _, jt in pairs(Q.jobTypes) do
        for ev in pairs(jt.events) do set[ev] = true end
    end
    Q.jobEvents = set
    Q.resetJobDefs()
    local regionsShown = Q.boards
    Q.boards = {}
    for region_id in pairs(regionsShown) do Q.boardChanged(region_id) end
end

---registerQuest(def) -> ok, err. Replaces a def with the same id. 'job:*' ids belong to job types.
local function registerQuest(def)
    if type(def) ~= 'table' then return false, 'fh_bad_def' end
    if type(def.id) == 'string' and def.id:sub(1, #Jobs.PREFIX) == Jobs.PREFIX then return false, 'fh_reserved_id' end
    local ok, err = E.validate(def, { regions = regions() })
    if not ok then return false, err end
    def.job_type = nil -- only job defs (jobs.def) carry it
    Q.defs[def.id] = def
    return true
end

---registerJobType(name, hooks) -> ok, err. Replaces a type with the same name; dropped when its owner stops.
local function registerJobType(name, hooks)
    local ok, err = Jobs.validateType(name, hooks)
    if not ok then return false, err end
    local events = {}
    for _, ev in ipairs(hooks.events or {}) do events[ev] = true end
    Q.jobTypes[name] = { hooks = hooks, owner = GetInvokingResource() or GetCurrentResourceName(), events = events }
    rebuildJobEvents()
    for ev in pairs(events) do listen(ev) end
    return true
end

AddEventHandler('onResourceStop', function(res)
    local dropped = false
    for name, jt in pairs(Q.jobTypes) do
        if jt.owner == res and res ~= GetCurrentResourceName() then
            Q.jobTypes[name] = nil
            dropped = true
        end
    end
    if dropped then rebuildJobEvents() end
end)

-- ---------------------------------------------------------------- player exports
local function start(src, quest_id)
    return withPlayer(src, function(cid, states)
        local def = type(quest_id) == 'string' and Q.defs[quest_id] or nil
        if not def then return false, 'fh_unknown_quest' end
        if R.pending(states[def.id]) then Q.payout(cid, def) end -- settle an old reward first if we can
        local st, fx = E.start(def, states, cid, os.time())
        if not st then return false, fx end
        if not Q.commit(def, st, fx) then return false, 'fh_db' end
        Q.sync(cid)
        return true
    end)
end

local function abandon(src, quest_id)
    return withPlayer(src, function(cid, states)
        local st = type(quest_id) == 'string' and states[quest_id] or nil
        local def = st and Q.defOf(quest_id, st)
        if not def or st.status ~= 'active' then return false, 'fh_not_active' end
        local after, fx = E.abandon(def, st, os.time())
        if not Q.commit(def, after, fx) then return false, 'fh_db' end
        local jt = def.job_type and Q.jobTypes[def.job_type]
        if jt and jt.hooks.abandon then
            local ok, err = pcall(jt.hooks.abandon, src, after)
            if not ok then Q.log('job type %s abandon hook threw: %s', def.job_type, tostring(err)) end
        end
        Q.sync(cid)
        return true
    end)
end

local function getActive(src)
    local entries = nil
    local ok, err = withPlayer(src, function(_, states)
        entries = FhQuestsJournal.journal(Q.defsFor(states), states, true)
        return true
    end)
    if not ok then return {}, err end
    return entries
end

local function getBoard(src, region_id)
    if type(region_id) ~= 'string' or not regions()[region_id] then return nil, 'fh_bad_region' end
    local view = nil
    local ok, err = withPlayer(src, function(cid, states)
        Q.viewing[src] = region_id
        view = Q.boardView(region_id, states, os.time())
        Q.sync(cid)
        return true
    end)
    if not ok then return nil, err end
    return view
end

local function acceptOffer(src, offer_id)
    local region_id = type(offer_id) == 'string' and offer_id:match('^([^:]+):') or nil
    if not region_id or not regions()[region_id] then return false, 'fh_offer_gone' end
    return withPlayer(src, function(cid, states)
        local now = os.time()
        local offer = B.find(Q.boardFor(region_id, now).offers, offer_id)
        local jt = offer and Q.jobTypes[offer.job_type]
        if not jt then return false, 'fh_offer_gone' end
        local snap, err = Jobs.snapshot(offer.job_type, offer.offer, region_id, jt.hooks.onEvent ~= nil)
        if not snap then return false, err end
        local def
        def, err = Jobs.def(snap, { regions = regions(), events = Q.eventSet() })
        if not def then return false, err end
        local prev = states[def.id]
        if R.pending(prev) then
            local prevDef = Q.defOf(def.id, prev)
            if prevDef then Q.payout(cid, prevDef) end
        end
        local st, fx = E.start(def, states, cid, now)
        if not st then return false, fx end
        if jt.hooks.accept then
            local called, accepted, why = pcall(jt.hooks.accept, src, offer.offer)
            if not called then
                Q.log('job type %s accept hook threw: %s', offer.job_type, tostring(accepted))
                return false, 'fh_accept_failed'
            end
            if not accepted then return false, type(why) == 'string' and why or 'fh_accept_refused' end
        end
        st.progress.job = snap
        if not Q.commit(def, st, fx) then
            if jt.hooks.abandon then pcall(jt.hooks.abandon, src, st) end -- undo the job type's setup
            return false, 'fh_db'
        end
        Q.boardChanged(region_id)
        Q.sync(cid)
        return true, nil, def.id
    end)
end

---talk(src, npc_id) -> ok, err, dialogue. Feeds fh:quests:talked to this player's quests directly (it is not on
---the intake), then emits it for observers.
local function talk(src, npc_id)
    if type(npc_id) ~= 'string' or npc_id == '' then return false, 'fh_bad_npc' end
    local payload = nil
    local ok, err, dialogue = withPlayer(src, function(cid, states)
        local now = os.time()
        payload = { src = src, citizenid = cid, npc_id = npc_id }
        local defs = Q.defsFor(states)
        local changes, errors = I.feed(defs, states, E.TALK_EVENT, payload, now, Q.hookFor)
        for _, e in ipairs(errors) do Q.log('onEvent hook for %s threw: %s', e.quest_id, e.err) end
        local out = {}
        for _, c in ipairs(changes) do
            local def = defs[c.quest_id]
            c = I.fresh(defs, states, c, E.TALK_EVENT, payload, now, Q.hookFor) -- see onIntake
            if c and Q.commit(def, c.after, c.effects) then
                local d = I.dialogue(def, c.before, c.after)
                if d then out[#out + 1] = d end
            end
        end
        out.offers = I.offers(Q.defs, states, npc_id, now)
        Q.sync(cid)
        return true, nil, out
    end)
    if ok then TriggerEvent(E.TALK_EVENT, payload) end
    return ok, err, dialogue
end

exports('registerQuest', registerQuest)
exports('registerJobType', registerJobType)
exports('start', start)
exports('abandon', abandon)
exports('getActive', getActive)
exports('getBoard', getBoard)
exports('acceptOffer', acceptOffer)
exports('talk', talk)

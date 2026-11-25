-- fh_quests event routing (Q2). Pure Lua: which events are listened to, who an intake event credits (citizenid,
-- src resolved by the server, participants), feeding it to every active quest of those characters, the events the
-- resulting effects emit, the dialogue a talk produced, and the quests an npc offers.
local M = {}

local function engine() return FhQuestsEngine or require('engine') end

local function sortedKeys(t)
    local keys = {}
    for k in pairs(t or {}) do keys[#keys + 1] = k end
    table.sort(keys)
    return keys
end

local function validCid(v) return type(v) == 'string' and v ~= '' end

---Does fh_quests listen to this event? The engine whitelist plus `extra` ({ [name] = true }: events registered
---job types added). fh:quests:talked is excluded: the talk export processes it itself (and only emits it after),
---so a re-fired talked event can never advance a second talk step. Unknown events are ignored.
function M.accepts(name, extra)
    if type(name) ~= 'string' or name == engine().TALK_EVENT then return false end
    return engine().isIntake(name) or (type(extra) == 'table' and extra[name] == true)
end

---The player server id to resolve when the payload has no citizenid (`src`, a positive integer), else nil.
function M.srcToResolve(payload)
    if type(payload) ~= 'table' or validCid(payload.citizenid) then return nil end
    local src = payload.src
    if type(src) == 'number' and src >= 1 and src == math.floor(src) then return math.tointeger(src) end
    return nil
end

---Citizenids an event may credit: payload.citizenid (or the one resolved from payload.src), then participants.
---Unique, in that order. Empty = nobody (event ignored).
function M.targets(payload, resolvedCid)
    if type(payload) ~= 'table' then return {} end
    local out, seen = {}, {}
    local function add(cid)
        if validCid(cid) and not seen[cid] then seen[cid] = true; out[#out + 1] = cid end
    end
    add(validCid(payload.citizenid) and payload.citizenid or resolvedCid)
    if type(payload.participants) == 'table' then
        for _, cid in ipairs(payload.participants) do add(cid) end
    end
    return out
end

---The payload the engine sees: when the event carried only `src`, a shallow copy with the resolved citizenid.
function M.payloadFor(payload, resolvedCid)
    if validCid(payload.citizenid) or not validCid(resolvedCid) then return payload end
    local p = {}
    for k, v in pairs(payload) do p[k] = v end
    p.citizenid = resolvedCid
    return p
end

local function shallow(t)
    local c = {}
    for k, v in pairs(t) do c[k] = v end
    return c
end

-- idea-1017 (quests-04 L1): delivery events where ONE event is ONE delivery. fh:hunting:pelt_sold fires once per
-- pelt (fh_hunting/shared/sell.lua), so it may advance at most one job-kind quest, or a player holding N matching
-- orders would be paid N times for one pelt. Line/tutorial quests are progress, not deliveries: they still all see it.
-- Every other event keeps feeding every matching job.
M.ONE_JOB_EVENTS = { ['fh:hunting:pelt_sold'] = true }

-- Accept-order key of a state: (rank, at). progress.accepted_at is stamped by engine.start (persisted by store).
-- A row without it was saved before idea-1017, so it was accepted before any row that has one: rank 0, ordered by
-- updated_at (for an active count-1 job such as hunt_request that is still the accept write: only a progress step
-- rewrites an active row; a re-keyed idea-902 row keeps its updated_at). Ties are broken by quest id in acceptOrder.
local function acceptKey(st)
    local p = type(st) == 'table' and type(st.progress) == 'table' and st.progress or {}
    if math.type(p.accepted_at) == 'integer' then return 1, p.accepted_at end
    local u = type(st) == 'table' and st.updated_at or nil
    return 0, (type(u) == 'number' and u == u) and u or 0
end

---Quest ids of `states`, oldest accepted first; ties (and equal fallbacks) by quest id. See acceptKey.
function M.acceptOrder(states)
    local keys = sortedKeys(states)
    local rank, at = {}, {}
    for _, qid in ipairs(keys) do rank[qid], at[qid] = acceptKey(states[qid]) end
    table.sort(keys, function(a, b)
        if rank[a] ~= rank[b] then return rank[a] < rank[b] end
        if at[a] ~= at[b] then return at[a] < at[b] end
        return a < b
    end)
    return keys
end

---Feed one event to every active quest in `states` (one character). Deterministic order (quest_id).
---hookFor(def) (optional) routes job quests: nil = the engine matches the step itself, a callable = the job type's
---hooks.onEvent(name, payload, stateCopy) decides the verdict (engine.apply, so a reward still pays once),
---false = the job type is not registered right now (the job pauses).
---For M.ONE_JOB_EVENTS only the first job-kind quest in acceptOrder that reacts takes the event (later jobs, and
---their hooks, are not asked); non-job quests are fed as usual.
---@return table changes  { { quest_id, before, after, effects }... } only for quests that changed, by quest_id;
---        table errors  { { quest_id, err }... } hooks that threw
function M.feed(defs, states, eventName, payload, now, hookFor)
    local changes, errors = {}, {}
    local function feedOne(qid)
        local st, def = states[qid], defs[qid]
        local hook = nil
        if def and hookFor then hook = hookFor(def) end
        if not (def and st.status == 'active' and hook ~= false) then return nil end
        local after, effects = st, {}
        if hook then
            if engine().eligible(st, eventName, payload) then
                local ok, verdict = pcall(hook, eventName, payload, shallow(st))
                if ok then
                    after, effects = engine().apply(def, st, verdict, now)
                else
                    errors[#errors + 1] = { quest_id = qid, err = tostring(verdict) }
                end
            end
        else
            after, effects = engine().onEvent(def, st, eventName, payload, now)
        end
        if #effects == 0 then return nil end
        local c = { quest_id = qid, before = st, after = after, effects = effects }
        changes[#changes + 1] = c
        return c
    end
    local oneJob = M.ONE_JOB_EVENTS[eventName] == true
    local function isJob(qid) return defs[qid] ~= nil and defs[qid].kind == 'job' end
    if oneJob then
        for _, qid in ipairs(M.acceptOrder(states)) do
            if isJob(qid) and feedOne(qid) then break end
        end
    end
    for _, qid in ipairs(sortedKeys(states)) do
        if not (oneJob and isJob(qid)) then feedOne(qid) end
    end
    if oneJob then table.sort(changes, function(a, b) return a.quest_id < b.quest_id end) end
    return changes, errors
end

---Is a change from feed() still valid at commit time? A synchronous listener of an earlier commit can re-enter the
---character lock and change a later quest, so the pre-computed `after` would overwrite that newer state. Returns
---the change itself while states[quest_id] is still change.before, otherwise the change recomputed from the current
---state (feed on that one quest), or nil when the quest no longer reacts (or no longer exists / is not active).
---@return table|nil change
function M.fresh(defs, states, change, eventName, payload, now, hookFor)
    local qid = change.quest_id
    local cur = states[qid]
    if cur == change.before then return change end
    if cur == nil or defs[qid] == nil then return nil end
    local changes = M.feed({ [qid] = defs[qid] }, { [qid] = cur }, eventName, payload, now, hookFor)
    return changes[1]
end

M.EMIT = { started = 'fh:quests:started', step = 'fh:quests:step', completed = 'fh:quests:completed',
    failed = 'fh:quests:failed', abandoned = 'fh:quests:abandoned' }

---Engine effects -> emitted events (README "Emitted events"), in order. The 'reward' effect is not an event: it is
---the payout trigger (hasReward). Payload is exactly { citizenid, quest_id, kind, step }.
---@return table events  { { name, payload }... }, boolean hasReward
function M.emits(effects)
    local out, reward = {}, false
    for _, e in ipairs(effects or {}) do
        if e.type == 'reward' then
            reward = true
        elseif M.EMIT[e.type] then
            out[#out + 1] = { name = M.EMIT[e.type],
                payload = { citizenid = e.citizenid, quest_id = e.quest_id, kind = e.kind, step = e.step } }
        end
    end
    return out, reward
end

---Dialogue for a change caused by a talk: the talk step's lines once that step advanced (or finished the quest).
---@return table|nil { quest_id, step, lines }
function M.dialogue(def, before, after)
    local beforeIdx = engine().stepIndexOf(def, before) or before.step
    local step = engine().stepOf(def, beforeIdx)
    if not step or not step.talk then return nil end
    if after.status == 'active' and after.step == beforeIdx then return nil end -- counted, not advanced
    local lines = {}
    for i, l in ipairs(step.talk.lines or {}) do lines[i] = l end
    return { quest_id = def.id, step = beforeIdx, lines = lines }
end

---Quest ids `npc_id` gives (def.giver) that this character can start now. Sorted.
function M.offers(defs, states, npc_id, now)
    local out = {}
    for _, qid in ipairs(sortedKeys(defs)) do
        local def = defs[qid]
        if def.giver == npc_id and engine().canStart(def, states or {}, now) then out[#out + 1] = qid end
    end
    return out
end

if GetCurrentResourceName then
    FhQuestsIntake = M
else
    return M
end

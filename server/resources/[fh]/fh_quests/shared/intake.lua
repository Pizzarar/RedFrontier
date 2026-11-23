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

---Feed one event to every active quest in `states` (one character). Deterministic order (quest_id).
---hookFor(def) (optional) routes job quests: nil = the engine matches the step itself, a callable = the job type's
---hooks.onEvent(name, payload, stateCopy) decides the verdict (engine.apply, so a reward still pays once),
---false = the job type is not registered right now (the job pauses).
---@return table changes  { { quest_id, before, after, effects }... } only for quests that changed;
---        table errors  { { quest_id, err }... } hooks that threw
function M.feed(defs, states, eventName, payload, now, hookFor)
    local changes, errors = {}, {}
    for _, qid in ipairs(sortedKeys(states)) do
        local st, def = states[qid], defs[qid]
        local hook = nil
        if def and hookFor then hook = hookFor(def) end
        if def and st.status == 'active' and hook ~= false then
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
            if #effects > 0 then
                changes[#changes + 1] = { quest_id = qid, before = st, after = after, effects = effects }
            end
        end
    end
    return changes, errors
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
    local step = engine().stepOf(def, before.step)
    if not step or not step.talk then return nil end
    if after.status == 'active' and after.step == before.step then return nil end -- counted, not advanced
    local lines = {}
    for i, l in ipairs(step.talk.lines or {}) do lines[i] = l end
    return { quest_id = def.id, step = before.step, lines = lines }
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

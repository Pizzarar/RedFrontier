-- fh_quests event routing (Q2). Pure Lua: who an intake event credits, feeding it to every active quest of
-- those characters, the dialogue a talk produced, and the quests an npc offers.
local M = {}

local function engine() return FhQuestsEngine or require('engine') end

local function sortedKeys(t)
    local keys = {}
    for k in pairs(t or {}) do keys[#keys + 1] = k end
    table.sort(keys)
    return keys
end

local function validCid(v) return type(v) == 'string' and v ~= '' end

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

---Feed one event to every active quest in `states` (one character). Deterministic order (quest_id).
---@return table changes  { { quest_id, before, after, effects }... } only for quests that changed
function M.feed(defs, states, eventName, payload, now)
    local changes = {}
    for _, qid in ipairs(sortedKeys(states)) do
        local st, def = states[qid], defs[qid]
        if def and st.status == 'active' then
            local after, effects = engine().onEvent(def, st, eventName, payload, now)
            if #effects > 0 then
                changes[#changes + 1] = { quest_id = qid, before = st, after = after, effects = effects }
            end
        end
    end
    return changes
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

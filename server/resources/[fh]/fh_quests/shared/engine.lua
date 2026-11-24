-- fh_quests engine (Q1): pure quest state machine. No natives, no I/O, no clock of its own.
-- Every function takes the state it changes and returns a NEW state plus a list of effects; the caller
-- (the Q2 server) persists the state and turns effects into fh:quests:* events and fh_economy payouts.
--
-- State (one row of fh_quest_state per citizenid + quest_id):
--   { citizenid, quest_id, status = 'active'|'done'|'failed'|'abandoned', step = 1..#steps,
--     progress = { count = n, completions = n, reward_pending = bool, step_id = string|nil },
--     cooldown_until = unix seconds|nil, updated_at = unix seconds }
-- `step` is the index into the CURRENT def; `progress.step_id` is the step's optional stable id. A def may give
-- steps ids ({ id = 'claim_plot', ... }); progress is then resolved by id first, so reordering/inserting steps does
-- not move a player mid-quest. Rows written before a def had ids have no step_id and fall back to the index.
-- Effects: { type = 'started'|'step'|'completed'|'failed'|'abandoned'|'reward', citizenid, quest_id, kind, step,
--   reason? } ('reward' also carries money, rep, items, reason = 'quest:<id>').
-- `now` is injected everywhere: a number (unix seconds) or a function returning one.
local M = {}

local function match() return FhQuestsMatch or require('match') end

M.STATUS = { active = 'active', done = 'done', failed = 'failed', abandoned = 'abandoned' }
M.KINDS = { job = true, line = true, tutorial = true }
M.TALK_EVENT = 'fh:quests:talked'

-- Event intake whitelist (README "Event intake"). Server-side events only; anything else is ignored.
M.INTAKE = {
    'fh:zones:camp_cleared',
    'fh:hunting:pelt_skinned',
    'fh:hunting:pelt_sold',
    'fh:hunting:chain_complete',
    'fh:homestead:claimed',
    'fh:economy:paid',
    'fh:economy:rep_changed',
    'fh:death:dropped',
    'fh:death:recovered',
    'fh:death:expired',
    'fh:quests:talked',
}
local INTAKE_SET = {}
for _, name in ipairs(M.INTAKE) do INTAKE_SET[name] = true end

function M.isIntake(name) return INTAKE_SET[name] == true end

local ECONOMY = { ['fh:economy:paid'] = true, ['fh:economy:rep_changed'] = true }

M.LIMITS = { idLen = 64, steps = 32, count = 1000, money = 100000, repDelta = 1000, items = 16, itemAmount = 1000 }

local ID_PATTERN = '^[%w_%-%.:]+$'

local function nowOf(now)
    if type(now) == 'function' then now = now() end
    assert(math.type(now) == 'integer' or (type(now) == 'number' and now == math.floor(now)),
        'fh_quests: now must be whole unix seconds')
    return math.tointeger(now)
end

local function posInt(n, max) return math.type(n) == 'integer' and n >= 1 and (not max or n <= max) end

-- A proper sequence: keys are exactly 1..n. Counting keys matters: for a table with holes ({ [1] = a, [3] = b })
-- `#t` may legally be 3, so a bounds check alone would accept it and ipairs would then stop at the hole.
local function isList(t)
    if type(t) ~= 'table' then return false end
    local n, keys = #t, 0
    for k in pairs(t) do
        if math.type(k) ~= 'integer' or k < 1 or k > n then return false end
        keys = keys + 1
    end
    return keys == n
end

local function copy(state)
    local s = {}
    for k, v in pairs(state) do s[k] = v end
    local p = {}
    for k, v in pairs(state.progress or {}) do p[k] = v end
    s.progress = p
    return s
end

---Step i with defaults applied: count 1; a talk step listens on fh:quests:talked with npc_id = talk.npc.
---@return table|nil step  { on, where, count, text, talk }
function M.stepOf(def, i)
    local raw = def.steps and def.steps[i]
    if not raw then return nil end
    local on, where = raw.on, raw.where
    if raw.talk then
        on = on or M.TALK_EVENT
        if on == M.TALK_EVENT then
            local w = {}
            for k, v in pairs(where or {}) do w[k] = v end
            w.npc_id = raw.talk.npc
            where = w
        end
    end
    return { on = on, where = where, count = raw.count or 1, text = raw.text, talk = raw.talk }
end

---The stable id of step `i`, or nil when the def gives the step no id.
function M.stepIdOf(def, i)
    local raw = def.steps and def.steps[i]
    return raw and type(raw.id) == 'string' and raw.id or nil
end

local function indexOfId(def, id)
    if type(id) ~= 'string' then return nil end
    for i, raw in ipairs(def.steps or {}) do
        if raw.id == id then return i end
    end
    return nil
end

---The index in `def` that `state` is on: the saved step id resolved against the current def (a reorder keeps
---progress), else the saved index (defs without ids / legacy rows). nil when the saved id no longer exists.
function M.stepIndexOf(def, state)
    if type(state) ~= 'table' then return nil end
    local saved = type(state.progress) == 'table' and state.progress.step_id or nil
    if saved ~= nil then
        if type(saved) ~= 'string' then return state.step end
        return indexOfId(def, saved) -- nil = the step was removed: apply treats it as past the end
    end
    return state.step
end

local function validRegion(regions, id)
    if type(id) ~= 'string' or id == '' then return false end
    if regions == nil then return true end
    if type(regions) == 'function' then return regions(id) ~= nil end
    return regions[id] ~= nil
end

local function validateRewards(r, regions)
    if r == nil then return true end
    if type(r) ~= 'table' then return false, 'fh_bad_rewards' end
    for k in pairs(r) do
        if k ~= 'money' and k ~= 'rep' and k ~= 'items' then return false, 'fh_unknown_reward:' .. tostring(k) end
    end
    if r.money ~= nil and not (math.type(r.money) == 'integer' and r.money >= 0 and r.money <= M.LIMITS.money) then
        return false, 'fh_bad_money'
    end
    if r.rep ~= nil then
        local rep = r.rep
        if type(rep) ~= 'table' or not validRegion(regions, rep.region_id) then return false, 'fh_bad_rep_region' end
        if math.type(rep.delta) ~= 'integer' or rep.delta == 0 or math.abs(rep.delta) > M.LIMITS.repDelta then
            return false, 'fh_bad_rep_delta'
        end
    end
    if r.items ~= nil then
        if not isList(r.items) or #r.items > M.LIMITS.items then return false, 'fh_bad_items' end
        for _, it in ipairs(r.items) do
            if type(it) ~= 'table' or type(it.name) ~= 'string' or it.name == '' then return false, 'fh_bad_item' end
            if not posInt(it.amount, M.LIMITS.itemAmount) then return false, 'fh_bad_item_amount' end
            if it.info ~= nil and type(it.info) ~= 'table' then return false, 'fh_bad_item_info' end
        end
    end
    return true
end

---Validate a quest definition (README "Definition shape").
---opts = { regions = { [id] = ... } | function(id), events = { [name] = true } (default M.INTAKE) }
---@return boolean ok, string|nil err  err = code, step errors suffixed '@step<i>'
function M.validate(def, opts)
    opts = opts or {}
    if type(def) ~= 'table' then return false, 'fh_bad_def' end
    if type(def.id) ~= 'string' or #def.id > M.LIMITS.idLen or not def.id:match(ID_PATTERN) then
        return false, 'fh_bad_id'
    end
    if not M.KINDS[def.kind] then return false, 'fh_bad_kind' end
    if type(def.title) ~= 'string' or def.title == '' then return false, 'fh_bad_title' end
    if def.giver ~= nil and (type(def.giver) ~= 'string' or def.giver == '') then return false, 'fh_bad_giver' end
    if not validRegion(opts.regions, def.region_id) then return false, 'fh_bad_region' end
    if def.prereq ~= nil then
        if not isList(def.prereq) then return false, 'fh_bad_prereq' end
        for _, id in ipairs(def.prereq) do
            if type(id) ~= 'string' or id == '' then return false, 'fh_bad_prereq' end
            if id == def.id then return false, 'fh_prereq_self' end
        end
    end
    if def['repeat'] ~= nil then
        local r = def['repeat']
        if type(r) ~= 'table' or type(r.cooldown_min) ~= 'number' or r.cooldown_min ~= r.cooldown_min
            or r.cooldown_min < 0 or r.cooldown_min > 525600 then
            return false, 'fh_bad_repeat'
        end
    end
    if type(def.steps) ~= 'table' or next(def.steps) == nil then return false, 'fh_no_steps' end
    if not isList(def.steps) then return false, 'fh_bad_steps' end -- holes or non-integer keys
    if #def.steps > M.LIMITS.steps then return false, 'fh_too_many_steps' end
    local events = opts.events or INTAKE_SET
    local stepIds = {}
    for i, raw in ipairs(def.steps) do
        local at = '@step' .. i
        if type(raw) ~= 'table' then return false, 'fh_bad_step' .. at end
        if raw.id ~= nil and (type(raw.id) ~= 'string' or raw.id == '') then return false, 'fh_bad_step_id' .. at end
        if raw.id ~= nil then
            if stepIds[raw.id] then return false, 'fh_duplicate_step_id' .. at end
            stepIds[raw.id] = true
        end
        if type(raw.text) ~= 'string' or raw.text == '' then return false, 'fh_bad_step_text' .. at end
        if raw.count ~= nil and not posInt(raw.count, M.LIMITS.count) then return false, 'fh_bad_step_count' .. at end
        if raw.talk ~= nil then
            local t = raw.talk
            if type(t) ~= 'table' or type(t.npc) ~= 'string' or t.npc == '' then return false, 'fh_bad_talk' .. at end
            if t.lines ~= nil then
                if not isList(t.lines) then return false, 'fh_bad_talk_lines' .. at end
                for _, l in ipairs(t.lines) do
                    if type(l) ~= 'string' then return false, 'fh_bad_talk_lines' .. at end
                end
            end
        end
        local step = M.stepOf(def, i)
        if type(step.on) ~= 'string' or not events[step.on] then return false, 'fh_bad_step_event' .. at end
        local ok, err = match().validate(raw.where)
        if not ok then return false, err .. at end
    end
    local ok, err = validateRewards(def.rewards, opts.regions)
    if not ok then return false, err end
    return true
end

local function effect(type_, def, state, extra)
    local e = { type = type_, citizenid = state.citizenid, quest_id = def.id, kind = def.kind, step = state.step }
    for k, v in pairs(extra or {}) do e[k] = v end
    return e
end

local function hasReward(r)
    return type(r) == 'table' and ((r.money or 0) > 0 or r.rep ~= nil or (r.items ~= nil and #r.items > 0))
end

local function rewardEffect(def, state)
    local r = def.rewards or {}
    return effect('reward', def, state, {
        reason = 'quest:' .. def.id, region_id = def.region_id, money = r.money, rep = r.rep, items = r.items,
    })
end

local function everDone(state)
    return state ~= nil and (state.status == 'done' or ((state.progress or {}).completions or 0) > 0)
end

---Can this citizen start `def` now? stateByQuest = { [quest_id] = state } for this citizen.
---@return boolean ok, string|nil err  fh_quest_active | fh_reward_pending | fh_quest_done | fh_quest_cooldown | fh_quest_prereq:<id>
function M.canStart(def, stateByQuest, now)
    stateByQuest = stateByQuest or {}
    local t = nowOf(now)
    local prev = stateByQuest[def.id]
    if prev then
        if prev.status == 'active' then return false, 'fh_quest_active' end
        if (prev.progress or {}).reward_pending then return false, 'fh_reward_pending' end
        if everDone(prev) then
            if def['repeat'] == nil then return false, 'fh_quest_done' end
            if prev.cooldown_until and t < prev.cooldown_until then return false, 'fh_quest_cooldown' end
        end
    end
    for _, id in ipairs(def.prereq or {}) do
        if not everDone(stateByQuest[id]) then return false, 'fh_quest_prereq:' .. id end
    end
    return true
end

---Start (or restart, for a repeatable / abandoned / failed quest) `def` for citizenid.
---@return table|nil state, table effectsOrErr  on refusal: nil, err
function M.start(def, stateByQuest, citizenid, now)
    if type(citizenid) ~= 'string' or citizenid == '' then return nil, 'fh_bad_citizenid' end
    local ok, err = M.canStart(def, stateByQuest, now)
    if not ok then return nil, err end
    local prev = (stateByQuest or {})[def.id]
    local state = {
        citizenid = citizenid, quest_id = def.id, status = 'active', step = 1,
        progress = { count = 0, completions = prev and (prev.progress or {}).completions or 0,
            step_id = M.stepIdOf(def, 1) },
        cooldown_until = prev and prev.cooldown_until or nil, updated_at = nowOf(now),
    }
    return state, { effect('started', def, state) }
end

local function complete(def, state, t, effects)
    state.status = 'done'
    state.progress.count = 0
    state.progress.completions = (state.progress.completions or 0) + 1
    if def['repeat'] then state.cooldown_until = t + math.floor(def['repeat'].cooldown_min * 60) end
    effects[#effects + 1] = effect('completed', def, state)
    if hasReward(def.rewards) then
        state.progress.reward_pending = true
        effects[#effects + 1] = rewardEffect(def, state)
    end
end

---Apply a verdict to an active quest: 'progress' (count one toward the current step), 'complete', 'fail'.
---This is also how registerJobType hooks.onEvent results land. Anything but an active state is a no-op,
---so a re-fired event or a second 'complete' can never emit a second reward.
---@return table state, table effects  state is the same table when nothing changed (effects empty)
function M.apply(def, state, verdict, now)
    if type(state) ~= 'table' or state.status ~= 'active' then return state, {} end
    if verdict ~= 'progress' and verdict ~= 'complete' and verdict ~= 'fail' then return state, {} end
    local t = nowOf(now)
    local s, effects = copy(state), {}
    s.updated_at = t
    if verdict == 'fail' then
        s.status = 'failed'
        effects[1] = effect('failed', def, s)
        return s, effects
    end
    if verdict == 'complete' then
        complete(def, s, t, effects)
        return s, effects
    end
    local idx = M.stepIndexOf(def, s)
    local step = idx and M.stepOf(def, idx) or nil
    if not step then -- step past the end (def shrank / the saved step id is gone): finish rather than stall
        complete(def, s, t, effects)
        return s, effects
    end
    s.step = idx -- heal the index when the saved step id moved in a reordered def
    s.progress.count = (s.progress.count or 0) + 1
    if s.progress.count < step.count then
        effects[1] = effect('step', def, s, { count = s.progress.count, need = step.count })
        return s, effects
    end
    if idx >= #def.steps then
        complete(def, s, t, effects)
    else
        s.step = idx + 1
        s.progress.step_id = M.stepIdOf(def, s.step)
        s.progress.count = 0
        effects[1] = effect('step', def, s, { count = 0, need = M.stepOf(def, s.step).count })
    end
    return s, effects
end

---Feed one intake event to one quest state. Ignored (state unchanged, no effects) unless the quest is
---active, the event is the current step's `on`, the payload credits this state's citizenid, and `where` matches.
---@return table state, table effects
---Is this event about this state's holder at all? Active quest, payload credits the holder, and not a quest
---payout echo (a quest's own fh:economy:paid / rep_changed must never advance a quest). Step-independent: also
---the gate for registerJobType hooks.onEvent.
function M.eligible(state, eventName, payload)
    if type(state) ~= 'table' or state.status ~= 'active' or type(payload) ~= 'table' then return false end
    if not match().credits(payload, state.citizenid) then return false end
    if ECONOMY[eventName] and type(payload.reason) == 'string' and payload.reason:sub(1, 6) == 'quest:' then
        return false
    end
    return true
end

function M.onEvent(def, state, eventName, payload, now)
    if not M.eligible(state, eventName, payload) then return state, {} end
    local idx = M.stepIndexOf(def, state)
    local step = idx and M.stepOf(def, idx) or nil
    if not step or step.on ~= eventName then return state, {} end
    if not match().where(step.where, payload) then return state, {} end
    return M.apply(def, state, 'progress', now)
end

---Player gives up. Only an active quest can be abandoned; no reward, no cooldown.
function M.abandon(def, state, now)
    if type(state) ~= 'table' or state.status ~= 'active' then return state, {} end
    local s = copy(state)
    s.status, s.updated_at = 'abandoned', nowOf(now)
    return s, { effect('abandoned', def, s) }
end

---The server (or a job hook) fails an active quest. reason is passed through on the effect.
function M.fail(def, state, now, reason)
    if type(state) ~= 'table' or state.status ~= 'active' then return state, {} end
    local s, effects = M.apply(def, state, 'fail', now)
    effects[1].reason = reason
    return s, effects
end

---The reward a done state still owes (after a crash between persisting 'done' and paying), or nil.
function M.pendingReward(def, state)
    if type(state) ~= 'table' or state.status ~= 'done' or not (state.progress or {}).reward_pending then return nil end
    return rewardEffect(def, state)
end

---Mark the reward paid (call after fh_economy accepted every part). Idempotent.
function M.rewardPaid(state, now)
    if type(state) ~= 'table' or not (state.progress or {}).reward_pending then return state end
    local s = copy(state)
    s.progress.reward_pending = nil
    s.updated_at = nowOf(now)
    return s
end

if GetCurrentResourceName then
    FhQuestsEngine = M
else
    return M
end

-- fh_quests client sync payload (Q2). Pure Lua: builds README "Client sync: fh:quests:sync" (v1, full snapshot).
local M = {}

M.VERSION = 1

local function engine() return FhQuestsEngine or require('engine') end

local function rewardsView(r)
    if type(r) ~= 'table' then return {} end
    local out = { money = r.money }
    if r.rep then out.rep = { region_id = r.rep.region_id, delta = r.rep.delta } end
    if r.items and #r.items > 0 then
        out.items = {}
        for i, it in ipairs(r.items) do out.items[i] = { name = it.name, amount = it.amount } end
    end
    return out
end

---One journal entry. The current step is resolved by its saved id when the def has ids (a reorder keeps the
---player's place). A step index past the end of the def (def shrank) shows the last step.
function M.entry(def, state)
    local n = #def.steps
    local i = math.min(math.max(engine().stepIndexOf(def, state) or state.step or 1, 1), n)
    local step = engine().stepOf(def, i)
    local p = state.progress or {}
    return {
        quest_id = def.id, kind = def.kind, title = def.title, giver = def.giver, region_id = def.region_id,
        status = state.status, step = i, steps_total = n, step_text = step.text,
        count = state.status == 'active' and (p.count or 0) or 0, need = step.count,
        rewards = rewardsView(def.rewards), cooldown_until = state.cooldown_until, updated_at = state.updated_at,
    }
end

---Is this state shown in the journal? Active quests, plus done/failed one-time quests (history).
function M.shown(def, state)
    if state.status == 'active' then return true end
    return (state.status == 'done' or state.status == 'failed') and def['repeat'] == nil
end

---Journal entries for one character: defs = { [quest_id] = def }, states = { [quest_id] = state }.
---Rows without a registered def are skipped. Order: active first, then newest first, then quest_id.
function M.journal(defs, states, activeOnly)
    local out = {}
    for qid, st in pairs(states or {}) do
        local def = defs[qid]
        if def and (activeOnly and st.status == 'active' or (not activeOnly and M.shown(def, st))) then
            out[#out + 1] = M.entry(def, st)
        end
    end
    table.sort(out, function(a, b)
        local aa, ba = a.status == 'active', b.status == 'active'
        if aa ~= ba then return aa end
        if (a.updated_at or 0) ~= (b.updated_at or 0) then return (a.updated_at or 0) > (b.updated_at or 0) end
        return a.quest_id < b.quest_id
    end)
    return out
end

---Board object for the sync payload / getBoard (README "board"). offers = board.rotate() output;
---accepted = { [quest_id] = true } for this player's active jobs; questId(job_type, key) -> quest id;
---locked (optional, dev flag only) = { [offer_id] = min_tier | { min_tier?, reason? } } for locked offers.
function M.boardView(region_id, epoch, expires_at, offers, accepted, questId, locked)
    local out = { region_id = region_id, epoch = epoch, expires_at = expires_at, offers = {} }
    for i, o in ipairs(offers or {}) do
        local src = o.offer or {}
        local minTier = type(locked) == 'table' and locked[o.id] or nil -- number, or a lock table
        out.offers[i] = {
            id = o.id, job_type = o.job_type, title = o.title,
            text = type(src.text) == 'string' and src.text or nil,
            rewards = rewardsView(src.rewards),
            accepted = (accepted or {})[questId(o.job_type, o.key)] == true,
            locked = type(minTier) == 'table' and { min_tier = minTier.min_tier, reason = minTier.reason }
                or (minTier and { min_tier = minTier } or nil),
        }
    end
    return out
end

---The full fh:quests:sync payload. board may be nil.
function M.snapshot(defs, states, boardObj)
    return { v = M.VERSION, journal = M.journal(defs, states), board = boardObj }
end

if GetCurrentResourceName then
    FhQuestsJournal = M
else
    return M
end

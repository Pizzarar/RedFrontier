-- fh_quests persistence mapping (Q2). Pure Lua: state <-> fh_quest_state row (migration 0007_quest_state.sql).
-- progress keys kept: count, completions, reward_pending, reward_paid, reward_inflight, step_id, job (anything else
-- is dropped).
-- JSON encode/decode are injected (the server passes the CfxLua `json` global), so specs run without natives.
-- fromRow normalises what comes back (JSON numbers may decode as floats; bad JSON or an unknown status drops the
-- row's progress / the row) so the engine and the reward protocol only ever see well-formed state.
local M = {}

M.SELECT = 'SELECT citizenid, quest_id, status, step, progress, cooldown_until, updated_at '
    .. 'FROM fh_quest_state WHERE citizenid = ?'

M.UPSERT = 'INSERT INTO fh_quest_state (citizenid, quest_id, status, step, progress, cooldown_until, updated_at) '
    .. 'VALUES (?, ?, ?, ?, ?, NULLIF(?, 0), ?) ON DUPLICATE KEY UPDATE status = VALUES(status), step = VALUES(step), '
    .. 'progress = VALUES(progress), cooldown_until = VALUES(cooldown_until), updated_at = VALUES(updated_at)'

local STATUS = { active = true, done = true, failed = true, abandoned = true }

local function int(v)
    if type(v) == 'string' then v = tonumber(v) end
    if type(v) ~= 'number' or v ~= v or v == math.huge or v == -math.huge then return nil end
    return math.tointeger(math.floor(v))
end

---The progress table that is written: only known keys, JSON-friendly.
local function cleanProgress(p)
    p = type(p) == 'table' and p or {}
    local out = { count = int(p.count) or 0, completions = int(p.completions) or 0 }
    if type(p.step_id) == 'string' and p.step_id ~= '' then out.step_id = p.step_id end
    if p.reward_pending == true then out.reward_pending = true end
    if type(p.reward_paid) == 'table' then
        local paid, any = {}, false
        for k, v in pairs(p.reward_paid) do
            if type(k) == 'string' and v == true then paid[k], any = true, true end
        end
        if any then out.reward_paid = paid end
    end
    local f = p.reward_inflight
    if type(f) == 'table' and type(f.key) == 'string' and f.key ~= '' then
        out.reward_inflight = { key = f.key, at = int(f.at) or 0 }
    end
    -- Accepted job offer (jobs.snapshot): kept as-is; jobs.def re-validates it on load.
    if type(p.job) == 'table' and type(p.job.job_type) == 'string' and type(p.job.key) == 'string' then
        out.job = p.job
    end
    return out
end

---UPSERT parameters for a state, in column order. Never sparse: no cooldown is sent as 0 and NULLIF(?, 0) stores
---NULL (a nil in the middle of a Lua array would not cross to oxmysql as a positional array).
---@param encode fun(t: table): string
function M.params(state, encode)
    return { state.citizenid, state.quest_id, state.status, int(state.step) or 1, encode(cleanProgress(state.progress)),
        int(state.cooldown_until) or 0, int(state.updated_at) or 0 }
end

---A row from M.SELECT -> state, or nil for a row that cannot be used (logged by the server).
---@param decode fun(s: string): table
---@return table|nil state, string|nil err
function M.fromRow(row, decode)
    if type(row) ~= 'table' then return nil, 'fh_bad_row' end
    if type(row.citizenid) ~= 'string' or row.citizenid == '' then return nil, 'fh_bad_row_citizenid' end
    if type(row.quest_id) ~= 'string' or row.quest_id == '' then return nil, 'fh_bad_row_quest' end
    if not STATUS[row.status] then return nil, 'fh_bad_row_status' end
    local progress = {}
    if type(row.progress) == 'string' and row.progress ~= '' then
        local ok, decoded = pcall(decode, row.progress)
        if ok and type(decoded) == 'table' then progress = decoded end
    end
    local step = int(row.step)
    return {
        citizenid = row.citizenid, quest_id = row.quest_id, status = row.status,
        step = (step and step >= 1) and step or 1,
        progress = cleanProgress(progress),
        cooldown_until = int(row.cooldown_until),
        updated_at = int(row.updated_at) or 0,
    }
end

if GetCurrentResourceName then
    FhQuestsStore = M
else
    return M
end

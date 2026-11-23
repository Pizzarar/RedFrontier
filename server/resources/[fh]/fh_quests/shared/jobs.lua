-- fh_quests job types (Q2 registry; the concrete hunt_request / camp_clear / bounty types land in Q3). Pure Lua.
-- A job type (registerJobType) supplies board offers. An accepted offer becomes a one-step repeatable quest with
-- id 'job:<type>:<key>'. Its def is rebuilt from a snapshot of the offer that is stored in the row
-- (progress.job), so an active job and an unpaid job reward survive a restart even after the board rotated.
--
-- Offer fields (all but key/title optional; anything else rides along to hooks.accept):
--   key, title, text, rewards (engine reward shape), cooldown_min (default DEFAULT_COOLDOWN_MIN),
--   on + where + count: the step the engine matches itself. Required unless the job type has hooks.onEvent, which
--   then decides every verdict (on/where are display-only).
local M = {}

local function engine() return FhQuestsEngine or require('engine') end

M.NAME_PATTERN = '^[a-z0-9_]+$'
M.PREFIX = 'job:'
M.DEFAULT_COOLDOWN_MIN = 60 -- one board rotation: the same offer cannot be farmed inside its epoch
M.HOOKS = { offers = true, accept = true, onEvent = true, abandon = true }

-- Cross-resource function refs arrive as tables with __call (msgpack funcref), not as Lua functions.
local function callable(f)
    if type(f) == 'function' then return true end
    local mt = type(f) == 'table' and getmetatable(f)
    return type(mt) == 'table' and mt.__call ~= nil
end
M.callable = callable

---Validate registerJobType(name, hooks). hooks.offers is required; accept/onEvent/abandon are optional;
---hooks.events is an optional list of extra intake event names ('fh:*').
---@return boolean ok, string|nil err
function M.validateType(name, hooks)
    if type(name) ~= 'string' or #name > 32 or not name:match(M.NAME_PATTERN) then return false, 'fh_bad_job_name' end
    if type(hooks) ~= 'table' then return false, 'fh_bad_hooks' end
    if not callable(hooks.offers) then return false, 'fh_bad_hook:offers' end
    for k in pairs(M.HOOKS) do
        if hooks[k] ~= nil and not callable(hooks[k]) then return false, 'fh_bad_hook:' .. k end
    end
    if hooks.events ~= nil then
        if type(hooks.events) ~= 'table' then return false, 'fh_bad_job_events' end
        for _, ev in ipairs(hooks.events) do
            if type(ev) ~= 'string' or ev:sub(1, 3) ~= 'fh:' or ev == engine().TALK_EVENT then
                return false, 'fh_bad_job_event:' .. tostring(ev)
            end
        end
    end
    return true
end

---Is quest_id a job id? Returns job type and key.
function M.parseId(quest_id)
    if type(quest_id) ~= 'string' or quest_id:sub(1, #M.PREFIX) ~= M.PREFIX then return nil end
    local jt, key = quest_id:match('^job:([a-z0-9_]+):(.+)$')
    return jt, key
end

function M.questId(job_type, key) return M.PREFIX .. job_type .. ':' .. key end

-- JSON round trips may turn whole numbers into floats; the engine wants integers (money, count, delta, amount).
local function normalize(v, depth)
    depth = depth or 0
    if depth > 8 then return nil end
    if type(v) == 'number' then
        if math.type(v) == 'float' and v == math.floor(v) and v > -2 ^ 53 and v < 2 ^ 53 then return math.tointeger(v) end
        return v
    end
    if type(v) ~= 'table' then return v end
    local out = {}
    for k, x in pairs(v) do
        if type(k) == 'string' or math.type(k) == 'integer' then out[k] = normalize(x, depth + 1) end
    end
    return out
end
M.normalize = normalize

---The snapshot stored in progress.job when an offer is accepted (only these fields; JSON-friendly).
---@param hasHook boolean  the job type decides verdicts via hooks.onEvent
---@return table|nil snapshot, string|nil err
function M.snapshot(job_type, offer, region_id, hasHook)
    if type(offer) ~= 'table' or type(offer.key) ~= 'string' or offer.key == '' then return nil, 'fh_bad_offer' end
    if type(offer.title) ~= 'string' or offer.title == '' then return nil, 'fh_bad_offer' end
    if not hasHook and type(offer.on) ~= 'string' then return nil, 'fh_offer_no_event' end
    local cd = offer.cooldown_min
    if cd == nil then cd = M.DEFAULT_COOLDOWN_MIN end
    return normalize({
        job_type = job_type, key = offer.key, region_id = region_id, title = offer.title,
        text = type(offer.text) == 'string' and offer.text or nil,
        on = type(offer.on) == 'string' and offer.on or nil, where = offer.where, count = offer.count,
        rewards = offer.rewards, cooldown_min = cd, hook = hasHook and true or nil,
    })
end

---Rebuild the quest def of a job from its snapshot and validate it with the engine.
---opts = { regions, events = { [name] = true } } (events: intake whitelist plus this job type's events)
---@return table|nil def, string|nil err
function M.def(snap, opts)
    if type(snap) ~= 'table' or type(snap.job_type) ~= 'string' or type(snap.key) ~= 'string' then
        return nil, 'fh_bad_job_snapshot'
    end
    snap = normalize(snap)
    local on = snap.on
    -- A hook-driven job without its own `on` still needs a valid step for validate/journal: it never reaches
    -- engine.onEvent (intake routes it to hooks.onEvent), so the event name is display-only.
    if on == nil and snap.hook then on = 'fh:quests:job' end
    local events = {}
    if (opts or {}).events then
        for k, v in pairs(opts.events) do events[k] = v end
    else
        for _, name in ipairs(engine().INTAKE) do events[name] = true end
    end
    if snap.hook then events['fh:quests:job'] = true end
    local def = {
        id = M.questId(snap.job_type, snap.key), kind = 'job', title = snap.title, region_id = snap.region_id,
        job_type = snap.job_type,
        ['repeat'] = { cooldown_min = snap.cooldown_min or M.DEFAULT_COOLDOWN_MIN },
        steps = { { on = on, where = snap.where, count = snap.count, text = snap.text or snap.title } },
        rewards = snap.rewards,
    }
    local ok, err = engine().validate(def, { regions = (opts or {}).regions, events = events })
    if not ok then return nil, err end
    return def
end

if GetCurrentResourceName then
    FhQuestsJobs = M
else
    return M
end

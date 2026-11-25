-- fh_quests built-in job types (Q3): hunt_request, camp_clear, bounty; survey (quests-02 C2); escort (C3); rescue (C4). Pure Lua, no natives.
-- This is the data + the decisions. server/jobtypes.lua registers them through the same registerJobType export
-- every other lane uses, and does the bounty I/O (spawn, death watch). Region templates live in M.DATA.
--
-- Every offer carries the fields registerJobType documents (key/title/text/on/where/count/rewards); the job types
-- decide their own verdicts in M.verdict (used as hooks.onEvent), reading the accepted-offer snapshot that
-- the server stored in state.progress.job. ALL coordinates/models in data/regions are guesses: TODO-verify-in-game.
local M = {}

local function match() return FhQuestsMatch or require('match') end

M.TYPES = { 'hunt_request', 'camp_clear', 'bounty', 'supply_run', 'survey', 'escort', 'rescue' }
M.BOUNTY_EVENT = 'fh:quests:bounty_down' -- local server event fired by the bounty death watcher: { citizenid, offer_key, region_id }
M.BOUNTY_TAG_PREFIX = 'fh_quests:bounty:'

-- Region templates: data/regions/<region_id>.lua (one per FhRegions id) fill M.DATA through M.registerRegion.
-- Offer builders: shared/jobtypes/<job_type>.lua fill M.BUILDERS through M.registerBuilder. In FXServer the manifest
-- loads both right after this file; outside it (specs) this file loads them itself (bottom).
M.DATA = {}     -- region_id -> { hunt = {...}, camps = {...}, bounties = {...} }
M.BUILDERS = {} -- job_type -> function(region_id, data) -> offer list
M.VERDICTS = {} -- job_type -> function(eventName, payload, state, snap) -> verdict|nil (types with their own rule)

function M.registerRegion(region_id, data) M.DATA[region_id] = data end
function M.registerBuilder(job_type, build) M.BUILDERS[job_type] = build end
function M.registerVerdict(job_type, decide) M.VERDICTS[job_type] = decide end

---Offer rewards shape shared by the builders.
function M.rewards(region_id, money, rep)
    return { money = money, rep = { region_id = region_id, delta = rep } }
end

---Normalize an offer's minimum tier (defaults to 1 when omitted or invalid).
function M.minTier(v)
    if type(v) == 'number' and v == v and v >= 1 then return math.floor(v) end
    return 1
end

---Offer templates of one job type for a region (hooks.offers). Fresh tables every call; unknown region = {}.
function M.offers(job_type, region_id)
    local build, d = M.BUILDERS[job_type], M.DATA[region_id]
    if not build or not d then return {} end
    return build(region_id, d)
end

---Tag of a bounty's spawn request (fh_core requestSpawn spec.tag). One live bounty per region + offer key.
function M.bountyTag(region_id, key) return M.BOUNTY_TAG_PREFIX .. region_id .. ':' .. key end

---The bounty offer of a region by offer key (the spawn setup is not stored in the job snapshot, so a re-arm after a
---restart or a relog rebuilds it from the template). nil when the template is gone.
function M.offerByKey(job_type, region_id, key)
    for _, o in ipairs(M.offers(job_type, region_id)) do
        if o.key == key then return o end
    end
    return nil
end
function M.bountyOffer(region_id, key) return M.offerByKey('bounty', region_id, key) end

---Watched bounties whose ped is dead, as a sorted snapshot list. Taken before anything yields, so the caller can
---fire events and mutate `watch` afterwards without invalidating a traversal. isDead(w) -> boolean (may throw: that
---entry is skipped).
function M.collectDead(watch, isDead)
    local out = {}
    for _, w in pairs(watch) do
        local ok, dead = pcall(isDead, w)
        if ok and dead then out[#out + 1] = w end
    end
    table.sort(out, function(a, b) return a.tag < b.tag end)
    return out
end

---Watched bounties owned by player `src` (they left: despawn these, credit nobody). Snapshot list, sorted.
function M.ownedBy(watch, src)
    local out = {}
    for _, w in pairs(watch) do
        if w.src == src then out[#out + 1] = w end
    end
    table.sort(out, function(a, b) return a.tag < b.tag end)
    return out
end

-- The accepted-offer snapshot is the source of truth for what a job needs (it survives rotation and restarts).
local function snapOf(job_type, state)
    local snap = type(state) == 'table' and type(state.progress) == 'table' and state.progress.job or nil
    if type(snap) ~= 'table' or snap.job_type ~= job_type then return nil end
    return snap
end

---hooks.onEvent decision for a built-in job type. Called by intake.feed only for events that already credit
---state.citizenid (payload.citizenid or a listed participant) and are not quota echoes.
---  hunt_request / camp_clear: the offer's own event + where predicates, one progress per matching event.
---    camp_clear credit therefore comes from payload.participants (core idea-614) and from nothing else.
---  survey (and other M.VERDICTS types): their own registered rule (shared/jobtypes/<type>.lua).
---  bounty: only the bounty watcher's event, naming the acceptor as payload.citizenid and this offer's key.
---    participants are ignored: nobody but the acceptor is paid.
---@return string|nil verdict
function M.verdict(job_type, eventName, payload, state)
    local snap = snapOf(job_type, state)
    if not snap or type(payload) ~= 'table' then return nil end
    if M.VERDICTS[job_type] then return M.VERDICTS[job_type](eventName, payload, state, snap) end
    if job_type == 'bounty' then
        if eventName ~= M.BOUNTY_EVENT then return nil end
        if payload.citizenid ~= state.citizenid or payload.offer_key ~= snap.key then return nil end
        return 'complete'
    end
    if eventName ~= snap.on then return nil end
    if not match().where(snap.where, payload) then return nil end
    return 'progress'
end

if GetCurrentResourceName then
    FhQuestsJobTypes = M
else
    -- Specs: load what the manifest loads in-game. The global is set first: some files read FhQuestsJobTypes
    -- directly (supply_run, survey, escort, rescue); the rest take the chunk argument passed below, guarded by
    -- `type((...)) == 'table'` because under FXServer `...` is a number and they fall back to the global.
    FhQuestsJobTypes = M
    local dir = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
    for _, job_type in ipairs(M.TYPES) do assert(loadfile(dir .. 'jobtypes/' .. job_type .. '.lua'))(M) end
    local ids = {}
    for id in pairs((FhRegions or require('regions')).regions) do ids[#ids + 1] = id end
    table.sort(ids)
    for _, id in ipairs(ids) do
        local path = dir .. '../data/regions/' .. id .. '.lua'
        local f = io.open(path, 'r')
        if f then f:close(); assert(loadfile(path))(M) end
    end
    return M
end

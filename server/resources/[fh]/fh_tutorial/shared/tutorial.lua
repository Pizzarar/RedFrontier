-- fh_tutorial (guide-02): the intro tutorial, built on the fh_quests API (registerQuest kind='tutorial').
-- Pure data + decisions, no natives: loadable under busted (spec/tutorial_spec.lua) and FXServer.
-- The quest definition lives here so the server (registerQuest) and the spec (validate + walk) share one source.
--
-- Steps advance on the fh_quests intake whitelist plus fh:quests:talked (README "Event intake"). A step with no
-- real fh:* event advances through the `talk` export: the tutorial's own server calls talk(src, npc) when the step's
-- signal is seen (a client check, a survival buff, or a real giver conversation). Nothing else ever calls into
-- fh_quests; the engine decides whether the current step matches, so a stray signal is a no-op.
local M = {}

M.QUEST_ID = 'tutorial_intro'

-- Client-check steps: the client detects a signal and reports it (`fh:tutorial:check`); the server maps the id to a
-- synthetic talk npc and calls talk(src, npc). The npc id is free-form (fh_quests `talk` accepts any non-empty
-- string; only the giver proximity net handlers know real giver positions).
M.CHECKS = {
    greeting  = 'tutorial_greeting',
    inventory = 'tutorial_inventory',
    trade     = 'tutorial_trade',
    jobs      = 'tutorial_jobs',
}

-- The survival step advances on the server-local `fh:buffs:applied` event (see server/main.lua), not a client check.
M.SURVIVAL_NPC = 'tutorial_survival'
M.SURVIVAL_BUFFS = { well_fed = true, hydrated = true }

-- Waypoints for the steps that have a location. Coordinates are copied from the owning lanes' configs (never invented
-- here); re-sync if a lane moves one. All are approximate / unverified in game, like their sources.
M.WAYPOINTS = {
    trader     = { x = -176.0, y = 630.0, z = 114.0, label = 'Valentine Trade Post' }, -- fh_trade/config.lua:37
    homestead  = { x = -300.0, y = 790.0, z = 118.0, label = 'Homestead plot' },        -- fh_homestead/config.lua heartlands_01.center
    trapper    = { x = -299.0, y = 792.0, z = 118.2, label = 'Trapper' },                -- fh_hunting/config.lua:39
    giver_hale = { x = -296.0, y = 788.0, z = 118.2, label = 'Ruth Hale' },               -- fh_quests/shared/givers.lua:8
}

-- Step bodies, keyed by stable id. The order comes from FhTutorialConfig.order (config.lua), never from this file:
-- reordering the intro is a config edit. `id` is what fh_quests persists in the player's progress, so moving a step
-- keeps an in-flight character on the same logical step (see "progress" in fh_quests/shared/engine.lua).
-- `ack_ms` is for an informational step: the client reports its check after the prompt has been on screen that long
-- (the greeting has no player action of its own).
M.STEPS = {
    greeting = {
        talk = { npc = 'tutorial_greeting' }, check = 'greeting', ack_ms = 2500,
        text = 'Welcome to RedFrontier. This short guide covers your first day and never blocks you (skip any time with /tutorial skip).' },
    inventory = {
        talk = { npc = 'tutorial_inventory' }, check = 'inventory',
        text = 'Press I to open your inventory and see what you are carrying.' },
    eat_drink = {
        talk = { npc = 'tutorial_survival' }, check = 'survival',
        text = 'Eat and drink to keep your needs up — a hungry rider is a slow one.' },
    claim_plot = {
        on = 'fh:homestead:claimed', waypoint = 'homestead',
        text = 'Find a homestead plot and claim it with /fh_claim.' },
    trade_post = {
        talk = { npc = 'tutorial_trade' }, check = 'trade', waypoint = 'trader',
        text = 'Ride to the Valentine Trade Post and open its menu to quote or sell goods.' },
    hunt = {
        on = 'fh:hunting:pelt_sold', waypoint = 'trapper',
        text = 'Hunt an animal, skin it, then sell the pelt to the trapper — your first sale.' },
    jobs = {
        talk = { npc = 'tutorial_jobs' }, check = 'jobs',
        text = 'Open the jobs board with /jobs to take on paid work.' },
    family = {
        talk = { npc = 'npc_hale' }, waypoint = 'giver_hale',
        text = 'Meet a family quest giver — find Ruth Hale and introduce yourself.' },
}

-- Used when config.lua is absent or its order is unusable. Keep in sync with config.lua's documented default.
M.DEFAULT_ORDER = { 'greeting', 'inventory', 'eat_drink', 'claim_plot', 'trade_post', 'hunt', 'jobs', 'family' }

-- Only these must be in the order; the rest may be omitted by a config that wants a shorter intro.
M.MANDATORY = { greeting = true, inventory = true }

local function defaultWarn(fmt, ...)
    if print then print('[fh_tutorial] ' .. string.format(fmt, ...)) end
end

---Build the def's step list from an order of step ids. Unknown and duplicate ids are dropped with a warning; an
---order missing a mandatory step falls back to M.DEFAULT_ORDER. Every built step carries its id.
---@param order table|nil list of step ids
---@param warn fun(fmt: string, ...): nil|nil warning collector (default: print)
---@param fallback boolean|nil internal: do not fall back again
---@return table steps
function M.buildSteps(order, warn, fallback)
    warn = warn or defaultWarn
    if type(order) ~= 'table' then
        warn('order is not a list; using the default order')
        return fallback and {} or M.buildSteps(M.DEFAULT_ORDER, warn, true)
    end
    local steps, seen = {}, {}
    for _, id in ipairs(order) do
        local template = type(id) == 'string' and M.STEPS[id] or nil
        if not template then
            warn('unknown step id %q dropped', tostring(id))
        elseif seen[id] then
            warn('duplicate step id %q dropped', id)
        else
            seen[id] = true
            local step = {}
            for k, v in pairs(template) do step[k] = v end
            step.id = id
            steps[#steps + 1] = step
        end
    end
    for id in pairs(M.MANDATORY) do
        if not seen[id] then
            warn('mandatory step %q missing; using the default order', id)
            if not fallback then return M.buildSteps(M.DEFAULT_ORDER, warn, true) end
        end
    end
    return steps
end

-- Repeatable with a zero cooldown so `/tutorial restart` can replay a completed tutorial through the public
-- start/abandon exports (a one-time quest cannot be restarted once done). No rewards: nothing to pay twice, and the
-- zero-cooldown "can underpay" caveat only applies to rewarded quests. Never a prereq for anything: never blocking.
local config = rawget(_G, 'FhTutorialConfig')
M.def = {
    id = M.QUEST_ID,
    kind = 'tutorial',
    title = 'Welcome to RedFrontier',
    region_id = 'heartlands',
    ['repeat'] = { cooldown_min = 0 },
    steps = nil, -- built below from FhTutorialConfig.order
}
local configured = type(config) == 'table' and config.order or nil
M.def.steps = M.buildSteps(configured)
M.order = {}
for i, step in ipairs(M.def.steps) do M.order[i] = step.id end

---The step at 1-based index `i`, or nil.
function M.stepOf(def, i) return def.steps[i] end

---The waypoint (coords table) a step points at, or nil when the step has no location.
function M.waypointOf(step)
    local k = step and step.waypoint
    return k and M.WAYPOINTS[k] or nil
end

---The client-check id a step expects (one of M.CHECKS, or 'survival'), or nil.
function M.checkOf(step) return step and step.check or nil end

---How a step advances: 'event' (fh_quests intake), 'client_check' (client reports a signal),
---'buff' (survival fh:buffs:applied), or 'giver' (a real family giver talk).
function M.advancesOn(step)
    if not step then return nil end
    if step.on then return 'event' end
    if step.talk then
        if step.check == 'survival' then return 'buff' end
        if M.CHECKS[step.check] then return 'client_check' end
        return 'giver'
    end
    return nil
end

---The synthetic talk npc for a client-check id (M.CHECKS), or nil for 'survival'/unknown.
function M.checkNpc(checkId) return M.CHECKS[checkId] end

-- ------------------------------------------------------------------ persistence (skip / auto-start / restart)
-- The per-character record (fh_tutorial_state row) is nil (never started), or { skipped = false } (started before),
-- or { skipped = true } (opted out). The quest's own done/step state lives in fh_quests (fh_quest_state), keyed by
-- M.QUEST_ID. `record` and the fh_quests `status` are the two inputs to every decision below.

---Auto-start on character load only when there is no record (a never-seen character). A done, skipped, or previously
---started character is never re-nagged.
function M.shouldAutoStart(record) return record == nil end

function M.isSkipped(record) return record ~= nil and record.skipped == true end

---`/tutorial skip`: mark skipped and, when the quest is active, abandon it. Returns the new record + quest actions.
function M.skip(status)
    local actions = {}
    if status == 'active' then actions[1] = 'abandon' end
    return { skipped = true }, actions
end

---`/tutorial restart`: clear the skip flag, abandon an active run, then start again (the zero cooldown lets the
---repeatable quest restart even after done). Returns the new record + quest actions.
function M.restart(status)
    local actions = {}
    if status == 'active' then actions[1] = 'abandon' end
    actions[#actions + 1] = 'start'
    return { skipped = false }, actions
end

if GetCurrentResourceName then
    FhTutorial = M
else
    return M
end

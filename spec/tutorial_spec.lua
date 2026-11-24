-- fh_tutorial step machine spec (guide-02). Run from repo root: `lua spec/tutorial_spec.lua` (or tools/run-specs.py).
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local describe, it, eq, same = T.describe, T.it, T.eq, T.same
local fh = here .. '../server/resources/[fh]/'
package.path = fh .. 'fh_quests/shared/?.lua;' .. package.path
local E = dofile(fh .. 'fh_quests/shared/engine.lua')
local regions = require('regions') -- fh_core/shared/regions.lua via fh_prelude package.path
dofile(fh .. 'fh_tutorial/config.lua') -- FhTutorialConfig.order, the real production order
local Tut = dofile(fh .. 'fh_tutorial/shared/tutorial.lua')

T.ok = function(c, msg) if not c then error(msg or 'assertion failed', 2) end end

local T0 = 1795651200
local CID, OTHER = 'ABC123', 'XYZ999'
local def = Tut.def

-- The owner-approved order: teach needs before they bite; home and stash before shopping; jobs after the first
-- sale proves the money loop; the family giver is the graduation.
local WANT_ORDER = { 'greeting', 'inventory', 'eat_drink', 'claim_plot', 'trade_post', 'hunt', 'jobs', 'family' }

-- Payload that satisfies a step's event (mirrors spec/quests_families_spec.lua payloadFor).
local function payloadFor(step, cid)
    if step.talk then return E.TALK_EVENT, { citizenid = cid, npc_id = step.talk.npc } end
    local p = { citizenid = cid }
    if step.on == 'fh:homestead:claimed' then p.plot_id = 'p1'; p.region_id = 'heartlands'
    elseif step.on == 'fh:hunting:pelt_sold' then p.quality = 2; p.price = 12; p.region_id = 'heartlands'
    end
    return step.on, p
end

local function walk(cid, now)
    local st = E.start(def, {}, cid, now or T0)
    T.ok(st ~= nil, 'start')
    local rewards = 0
    for _, step in ipairs(def.steps) do
        local ev, p = payloadFor(step, cid)
        local fx
        st, fx = E.onEvent(def, st, ev, p, now or T0)
        for _, e in ipairs(fx) do if e.type == 'reward' then rewards = rewards + 1 end end
    end
    return st, rewards
end

local function withSteps(steps)
    local d = {}
    for k, v in pairs(def) do d[k] = v end
    d.steps = steps
    return d
end

local function currentId(d, st)
    local i = E.stepIndexOf(d, st)
    return i and d.steps[i] and d.steps[i].id or nil
end

local function feedCurrent(d, st, cid)
    local step = d.steps[E.stepIndexOf(d, st)]
    local ev, p = payloadFor(step, cid or CID)
    return (E.onEvent(d, st, ev, p, T0))
end

local function warningsOf()
    local out = {}
    return out, function(fmt, ...) out[#out + 1] = string.format(fmt, ...) end
end

describe('tutorial definition', function()
    it('passes engine validate, kind tutorial, heartlands', function()
        local ok, err = E.validate(def, { regions = regions.regions })
        eq(true, ok, tostring(err))
        eq('tutorial', def.kind)
        eq('heartlands', def.region_id)
        eq(Tut.QUEST_ID, def.id)
    end)
    it('has one step per configured id, in the configured order; zero-cooldown repeatable, no reward/prereq', function()
        eq(#FhTutorialConfig.order, #def.steps)
        same(FhTutorialConfig.order, Tut.order)
        for i, id in ipairs(FhTutorialConfig.order) do eq(id, def.steps[i].id) end
        -- the built-in fallback is the approved baseline (a config reorder updates config.lua, not this list)
        same(WANT_ORDER, Tut.DEFAULT_ORDER)
        local n = 0
        for i = 1, #def.steps do T.ok(def.steps[i] ~= nil, 'gap at ' .. i) n = n + 1 end
        eq(#def.steps, n)
        T.ok(def['repeat'] ~= nil and def['repeat'].cooldown_min == 0, 'repeat cooldown 0')
        eq(nil, def.rewards)
        eq(nil, def.prereq)
    end)
    it('uses only whitelisted events or talk steps', function()
        for i, s in ipairs(def.steps) do
            local ev = s.talk and E.TALK_EVENT or s.on
            T.ok(E.isIntake(ev), ('step %d event %s'):format(i, tostring(ev)))
        end
    end)
    it('classifies every step (client_check / event / giver / buff)', function()
        local want = {
            greeting = 'client_check', inventory = 'client_check', eat_drink = 'buff', claim_plot = 'event',
            trade_post = 'client_check', hunt = 'event', jobs = 'client_check', family = 'giver',
        }
        for i, s in ipairs(def.steps) do eq(want[s.id], Tut.advancesOn(s), s.id) end
    end)
    it('resolves waypoints only for the location steps', function()
        local want = {
            greeting = nil, inventory = nil, eat_drink = nil, claim_plot = 'Homestead plot',
            trade_post = 'Valentine Trade Post', hunt = 'Trapper', jobs = nil, family = 'Ruth Hale',
        }
        for _, s in ipairs(def.steps) do
            local wp = Tut.waypointOf(s)
            eq(want[s.id], wp and wp.label, s.id)
        end
    end)
    it('checkNpc maps client checks only, not survival', function()
        eq('tutorial_greeting', Tut.checkNpc('greeting'))
        eq('tutorial_inventory', Tut.checkNpc('inventory'))
        eq('tutorial_trade', Tut.checkNpc('trade'))
        eq('tutorial_jobs', Tut.checkNpc('jobs'))
        eq(nil, Tut.checkNpc('survival'))
        eq(nil, Tut.checkNpc('nope'))
    end)
end)

describe('tutorial step order comes from config', function()
    it('the config order names real steps and includes the mandatory ones', function()
        for _, id in ipairs(FhTutorialConfig.order) do
            T.ok(Tut.STEPS[id] ~= nil, 'unknown id in config: ' .. tostring(id))
        end
        T.ok(Tut.STEPS.greeting and Tut.STEPS.inventory, 'mandatory steps exist')
    end)
    it('builds a shorter intro from a subset order', function()
        local _, warn = warningsOf()
        local steps = Tut.buildSteps({ 'greeting', 'inventory', 'family' }, warn)
        eq(3, #steps)
        eq('greeting', steps[1].id); eq('inventory', steps[2].id); eq('family', steps[3].id)
    end)
    it('drops an unknown id with a warning', function()
        local warns, warn = warningsOf()
        local steps = Tut.buildSteps({ 'greeting', 'inventory', 'nope', 'trade_post' }, warn)
        eq(3, #steps)
        eq('trade_post', steps[3].id)
        eq(1, #warns)
        T.ok(warns[1]:find('nope', 1, true), warns[1])
    end)
    it('drops a duplicate id with a warning', function()
        local warns, warn = warningsOf()
        local steps = Tut.buildSteps({ 'greeting', 'inventory', 'inventory' }, warn)
        eq(2, #steps)
        eq(1, #warns)
        T.ok(warns[1]:find('duplicate', 1, true), warns[1])
    end)
    it('falls back to the default order when a mandatory step is missing (or the list is bad)', function()
        local warns, warn = warningsOf()
        local steps = Tut.buildSteps({ 'trade_post' }, warn)
        same(WANT_ORDER, (function()
            local ids = {}
            for i, s in ipairs(steps) do ids[i] = s.id end
            return ids
        end)())
        eq(1, #warns)
        T.ok(warns[1]:find('mandatory', 1, true), warns[1])

        local warns2, warn2 = warningsOf()
        local steps2 = Tut.buildSteps(nil, warn2)
        eq(#WANT_ORDER, #steps2)
        eq(1, #warns2)
    end)
end)

describe('tutorial step machine: advance', function()
    it('walks start -> done with no reward', function()
        local st, rewards = walk(CID)
        eq('done', st.status)
        eq(0, rewards)
    end)
    it('ignores another citizen and out-of-order events', function()
        local st = E.start(def, {}, CID, T0)
        local ev, p = payloadFor(def.steps[4], OTHER) -- claim_plot for someone else
        local after, fx = E.onEvent(def, st, ev, p, T0)
        eq(1, after.step)
        eq(0, #fx)
        local ev2, p2 = payloadFor(def.steps[6], CID) -- pelt sold while still on greeting
        local a2 = E.onEvent(def, st, ev2, p2, T0)
        eq(1, a2.step)
    end)
    it('a re-fired last event does not complete twice', function()
        local st = E.start(def, {}, CID, T0)
        for _, step in ipairs(def.steps) do
            local ev, p = payloadFor(step, CID)
            st = E.onEvent(def, st, ev, p, T0)
        end
        eq('done', st.status)
        local last = def.steps[#def.steps]
        local ev, p = payloadFor(last, CID)
        local _, fx = E.onEvent(def, st, ev, p, T0)
        eq(0, #fx)
    end)
    it('restart after done works through the engine (repeatable, zero cooldown)', function()
        local st = walk(CID)
        eq('done', st.status)
        local ok, err = E.canStart(def, { [def.id] = st }, T0 + 100)
        eq(true, ok, tostring(err))
        local st2 = E.start(def, { [def.id] = st }, CID, T0 + 100)
        eq(1, st2.step)
        eq('active', st2.status)
    end)
end)

describe('tutorial progress survives a reorder', function()
    it('resolves the current step by id, not by index', function()
        local defA = withSteps(Tut.buildSteps(WANT_ORDER))
        local defB = withSteps(Tut.buildSteps({ 'greeting', 'inventory', 'claim_plot', 'trade_post', 'hunt', 'jobs',
            'family', 'eat_drink' }))
        local st = E.start(defA, {}, CID, T0)
        while currentId(defA, st) ~= 'trade_post' do st = feedCurrent(defA, st) end
        eq(5, E.stepIndexOf(defA, st))
        eq(4, E.stepIndexOf(defB, st), 'trade_post moved to 4 in the reordered def')

        st = feedCurrent(defB, st) -- the current step's own event still advances it
        eq('hunt', currentId(defB, st))
        eq('hunt', st.progress.step_id, 'the next step id is persisted, not the index')
    end)
    it('a legacy row without a step id falls back to the saved index', function()
        local defA = withSteps(Tut.buildSteps(WANT_ORDER))
        local st = E.start(defA, {}, CID, T0)
        st.step, st.progress.step_id = 3, nil -- written by the pre-id version
        eq(3, E.stepIndexOf(defA, st))
        eq('eat_drink', currentId(defA, st))
    end)
    it('a saved step id that no longer exists completes instead of landing on a random step', function()
        local defA = withSteps(Tut.buildSteps(WANT_ORDER))
        local st = E.start(defA, {}, CID, T0)
        st.progress.step_id = 'gone'
        eq(nil, E.stepIndexOf(defA, st))
        st = E.apply(defA, st, 'progress', T0)
        eq('done', st.status)
    end)
end)

describe('tutorial skip / restart / persistence', function()
    it('auto-starts only a never-seen character (no record)', function()
        eq(true, Tut.shouldAutoStart(nil))
        eq(false, Tut.shouldAutoStart({ skipped = false }))
        eq(false, Tut.shouldAutoStart({ skipped = true }))
    end)
    it('skip marks skipped and abandons only an active run', function()
        local rec, actions = Tut.skip('active')
        eq(true, rec.skipped)
        eq(1, #actions)
        eq('abandon', actions[1])
        local rec2, a2 = Tut.skip('done')
        eq(true, rec2.skipped)
        eq(0, #a2)
    end)
    it('restart clears skip and always starts (abandoning an active run first)', function()
        local rec, actions = Tut.restart('active')
        eq(false, rec.skipped)
        eq(2, #actions)
        eq('abandon', actions[1])
        eq('start', actions[2])
        local rec2, a2 = Tut.restart('done')
        eq(false, rec2.skipped)
        eq(1, #a2)
        eq('start', a2[1])
    end)
    it('isSkipped reads the persisted flag', function()
        eq(false, Tut.isSkipped(nil))
        eq(true, Tut.isSkipped({ skipped = true }))
        eq(false, Tut.isSkipped({ skipped = false }))
    end)
end)

T.finish()

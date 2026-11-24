-- fh_tutorial step machine spec (guide-02). Run from repo root: `lua spec/tutorial_spec.lua` (or tools/run-specs.py).
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local describe, it, eq = T.describe, T.it, T.eq
local fh = here .. '../server/resources/[fh]/'
package.path = fh .. 'fh_quests/shared/?.lua;' .. package.path
local E = dofile(fh .. 'fh_quests/shared/engine.lua')
local regions = require('regions') -- fh_core/shared/regions.lua via fh_prelude package.path
local Tut = dofile(fh .. 'fh_tutorial/shared/tutorial.lua')

T.ok = function(c, msg) if not c then error(msg or 'assertion failed', 2) end end

local T0 = 1795651200
local CID, OTHER = 'ABC123', 'XYZ999'
local def = Tut.def

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

describe('tutorial definition', function()
    it('passes engine validate, kind tutorial, heartlands', function()
        local ok, err = E.validate(def, { regions = regions.regions })
        eq(true, ok, tostring(err))
        eq('tutorial', def.kind)
        eq('heartlands', def.region_id)
        eq(Tut.QUEST_ID, def.id)
    end)
    it('has 7 contiguous steps, zero-cooldown repeatable, no reward/prereq', function()
        eq(7, #def.steps)
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
        eq('client_check', Tut.advancesOn(def.steps[1]))
        eq('client_check', Tut.advancesOn(def.steps[2]))
        eq('event', Tut.advancesOn(def.steps[3]))
        eq('client_check', Tut.advancesOn(def.steps[4]))
        eq('event', Tut.advancesOn(def.steps[5]))
        eq('giver', Tut.advancesOn(def.steps[6]))
        eq('buff', Tut.advancesOn(def.steps[7]))
    end)
    it('resolves waypoints only for the location steps', function()
        eq(nil, Tut.waypointOf(def.steps[1]))
        eq('Valentine Trade Post', Tut.waypointOf(def.steps[2]).label)
        eq('Homestead plot', Tut.waypointOf(def.steps[3]).label)
        eq(nil, Tut.waypointOf(def.steps[4]))
        eq('Trapper', Tut.waypointOf(def.steps[5]).label)
        eq('Ruth Hale', Tut.waypointOf(def.steps[6]).label)
        eq(nil, Tut.waypointOf(def.steps[7]))
    end)
    it('checkNpc maps client checks only, not survival', function()
        eq('tutorial_inventory', Tut.checkNpc('inventory'))
        eq('tutorial_trade', Tut.checkNpc('trade'))
        eq('tutorial_jobs', Tut.checkNpc('jobs'))
        eq(nil, Tut.checkNpc('survival'))
        eq(nil, Tut.checkNpc('nope'))
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
        local ev, p = payloadFor(def.steps[3], OTHER) -- homestead for someone else
        local after, fx = E.onEvent(def, st, ev, p, T0)
        eq(1, after.step)
        eq(0, #fx)
        local ev2, p2 = payloadFor(def.steps[5], CID) -- pelt sold while still on step 1
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

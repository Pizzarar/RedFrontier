-- Run from repo root: `lua spec/quests_jobs_spec.lua` (or via tools/run-specs.py).
-- fh_quests jobs.lua: registerJobType validation, accepted-offer snapshot (progress.job), def rebuild after a
-- restart, default cooldown, and jobs pausing while their type is unregistered (intake.feed hookFor = false).
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local describe, it, eq, same = T.describe, T.it, T.eq, T.same
local shared = here .. '../server/resources/[fh]/fh_quests/shared/'
package.path = shared .. '?.lua;' .. package.path
local Jobs = dofile(shared .. 'jobs.lua')
local E = require('engine')
local I = require('intake')
local S = require('store')
local regions = require('regions')

local T0 = 1795651200
local CID = 'ABC123'
local OPTS = { regions = regions.regions }

local function fn() end
local callableTable = setmetatable({}, { __call = function() return {} end }) -- cross-resource funcref shape

local function offer(extra)
    local o = { key = 'c1', title = 'Clear camp one', text = 'Go clear it.', on = 'fh:zones:camp_cleared',
        where = { camp_id = 'c1' }, rewards = { money = 12 }, spawn = { x = 1.5 } }
    for k, v in pairs(extra or {}) do o[k] = v end
    return o
end

-- A JSON round trip through store.lua as the server does it (every number comes back a float).
local function floats(v)
    if type(v) == 'number' then return v + 0.0 end
    if type(v) ~= 'table' then return v end
    local out = {}
    for k, x in pairs(v) do out[k] = floats(x) end
    return out
end

local function restart(state)
    local stash
    local p = S.params(state, function(t) stash = floats(t); return 'json' end)
    local row = { citizenid = p[1], quest_id = p[2], status = p[3], step = p[4], progress = p[5],
        cooldown_until = p[6] ~= 0 and p[6] or nil, updated_at = p[7] }
    local st, err = S.fromRow(row, function() return floats(stash) end)
    assert(st, err)
    return st
end

-- acceptOffer's pure part (server/api.lua): snapshot -> def -> engine.start -> progress.job = snapshot.
local function accept(o, hasHook, states)
    local snap = assert(Jobs.snapshot('camp_clear', o or offer(), 'heartlands', hasHook))
    local def = assert(Jobs.def(snap, OPTS))
    local st = assert(E.start(def, states or {}, CID, T0))
    st.progress.job = snap
    return def, st, snap
end

describe('quests jobs: registerJobType validation', function()
    local function bad(code, name, hooks)
        local ok, err = Jobs.validateType(name, hooks)
        eq(false, ok, code); eq(code, err)
    end
    it('accepts a minimal type (offers only) and full hooks with extra events', function()
        eq(true, (Jobs.validateType('camp_clear', { offers = fn })))
        eq(true, (Jobs.validateType('freight', { offers = fn, accept = fn, onEvent = fn, abandon = fn,
            events = { 'fh:roads:delivered' } })))
    end)
    it('accepts cross-resource function refs (tables with __call)', function()
        eq(true, (Jobs.validateType('freight', { offers = callableTable, onEvent = callableTable })))
    end)
    it('name must match [a-z0-9_]+, max 32 chars', function()
        bad('fh_bad_job_name', 'Freight', { offers = fn })
        bad('fh_bad_job_name', 'free-ight', { offers = fn })
        bad('fh_bad_job_name', '', { offers = fn })
        bad('fh_bad_job_name', 12, { offers = fn })
        bad('fh_bad_job_name', string.rep('a', 33), { offers = fn })
        eq(true, (Jobs.validateType(string.rep('a', 32), { offers = fn })))
    end)
    it('hooks must be a table with a callable offers', function()
        bad('fh_bad_hooks', 'camp_clear', nil)
        bad('fh_bad_hooks', 'camp_clear', 'offers')
        bad('fh_bad_hook:offers', 'camp_clear', {})
        bad('fh_bad_hook:offers', 'camp_clear', { offers = {} })
    end)
    it('optional hooks must be callable when present', function()
        bad('fh_bad_hook:accept', 'camp_clear', { offers = fn, accept = 5 })
        bad('fh_bad_hook:onEvent', 'camp_clear', { offers = fn, onEvent = 'x' })
        bad('fh_bad_hook:abandon', 'camp_clear', { offers = fn, abandon = {} })
    end)
    it('events must be a list of fh:* names, never fh:quests:talked', function()
        bad('fh_bad_job_events', 'freight', { offers = fn, events = 'fh:roads:delivered' })
        bad('fh_bad_job_event:roads:delivered', 'freight', { offers = fn, events = { 'roads:delivered' } })
        bad('fh_bad_job_event:fh:quests:talked', 'freight', { offers = fn, events = { 'fh:quests:talked' } })
        bad('fh_bad_job_event:5', 'freight', { offers = fn, events = { 5 } })
    end)
end)

describe('quests jobs: quest ids', function()
    it('questId / parseId round trip; keys may contain colons', function()
        eq('job:camp_clear:c1', Jobs.questId('camp_clear', 'c1'))
        same({ 'camp_clear', 'c1' }, { Jobs.parseId('job:camp_clear:c1') })
        same({ 'freight', 'a:b' }, { Jobs.parseId('job:freight:a:b') })
    end)
    it('non-job ids parse to nil', function()
        eq(nil, Jobs.parseId('family_hale_1'))
        eq(nil, Jobs.parseId('job:Bad:x'))
        eq(nil, Jobs.parseId(nil))
    end)
end)

describe('quests jobs: offer snapshot (progress.job)', function()
    it('keeps only the snapshot fields; offer extras ride to accept, not to the row', function()
        local snap = Jobs.snapshot('camp_clear', offer(), 'heartlands', false)
        same({ job_type = 'camp_clear', key = 'c1', region_id = 'heartlands', title = 'Clear camp one',
            text = 'Go clear it.', on = 'fh:zones:camp_cleared', where = { camp_id = 'c1' },
            rewards = { money = 12 }, cooldown_min = 60 }, snap)
    end)
    it('is a copy: changing the offer later does not change the accepted job', function()
        local o = offer()
        local snap = Jobs.snapshot('camp_clear', o, 'heartlands', false)
        o.rewards.money, o.where.camp_id = 999, 'other'
        eq(12, snap.rewards.money); eq('c1', snap.where.camp_id)
    end)
    it('refuses offers without key / title, and engine-matched offers without on', function()
        eq('fh_bad_offer', select(2, Jobs.snapshot('camp_clear', offer({ key = '' }), 'heartlands', false)))
        eq('fh_bad_offer', select(2, Jobs.snapshot('camp_clear', offer({ title = 5 }), 'heartlands', false)))
        eq('fh_bad_offer', select(2, Jobs.snapshot('camp_clear', nil, 'heartlands', false)))
        eq('fh_offer_no_event', select(2, Jobs.snapshot('camp_clear', offer({ on = false }), 'heartlands', false)))
    end)
    it('a hook-driven offer needs no on (display-only step)', function()
        local snap = Jobs.snapshot('bounty', { key = 'b1', title = 'Wanted' }, 'heartlands', true)
        eq(true, snap.hook)
        local def = assert(Jobs.def(snap, OPTS))
        eq('fh:quests:job', def.steps[1].on)
        eq('Wanted', def.steps[1].text, 'text falls back to the title')
    end)
    it('accepted job: def id, kind, job_type, one step, repeatable', function()
        local def, st, snap = accept()
        eq('job:camp_clear:c1', def.id); eq('job', def.kind); eq('camp_clear', def.job_type)
        eq(1, #def.steps); eq(60, def['repeat'].cooldown_min)
        eq(snap, st.progress.job)
        eq('active', st.status)
    end)
    it('a def that fails engine.validate is refused with its code', function()
        local snap = Jobs.snapshot('camp_clear', offer({ rewards = { money = -1 } }), 'heartlands', false)
        eq('fh_bad_money', select(2, Jobs.def(snap, OPTS)))
        snap = Jobs.snapshot('camp_clear', offer(), 'nowhere', false)
        eq('fh_bad_region', select(2, Jobs.def(snap, OPTS)))
        eq('fh_bad_job_snapshot', select(2, Jobs.def({ key = 'c1' }, OPTS)))
    end)
    it("a job type's own event validates only while it is in the event set", function()
        local snap = Jobs.snapshot('freight', offer({ on = 'fh:roads:delivered', where = false }), 'heartlands', false)
        snap.where = nil
        eq('fh_bad_step_event@step1', select(2, Jobs.def(snap, OPTS)))
        local events = { ['fh:roads:delivered'] = true }
        for _, n in ipairs(E.INTAKE) do events[n] = true end
        assert(Jobs.def(snap, { regions = regions.regions, events = events }))
    end)
end)

describe('quests jobs: def rebuilt after a restart', function()
    it('progress.job survives the row and rebuilds the same def, integers intact', function()
        local def, st = accept(offer({ count = 2, where = { quality = { min = 2 } }, cooldown_min = 30,
            rewards = { money = 12, rep = { region_id = 'heartlands', delta = 3 } } }))
        local back = restart(st)
        assert(back.progress.job, 'snapshot kept in the row')
        local rebuilt = assert(Jobs.def(back.progress.job, OPTS))
        same(def, rebuilt)
        eq('integer', math.type(rebuilt.rewards.money))
        eq('integer', math.type(rebuilt.rewards.rep.delta))
        eq('integer', math.type(rebuilt.steps[1].count))
        eq('integer', math.type(rebuilt.steps[1].where.quality.min))
        eq('integer', math.type(rebuilt['repeat'].cooldown_min))
    end)
    it('the restored job keeps advancing and pays once', function()
        local _, st = accept(offer({ count = 2 }))
        local back = restart(st)
        local def = assert(Jobs.def(back.progress.job, OPTS))
        local p = { citizenid = CID, camp_id = 'c1' }
        local s1, fx1 = E.onEvent(def, back, 'fh:zones:camp_cleared', p, T0 + 1)
        eq('active', s1.status); eq(1, #fx1)
        local s2, fx2 = E.onEvent(def, restart(s1), 'fh:zones:camp_cleared', p, T0 + 2)
        eq('done', s2.status)
        eq('reward', fx2[#fx2].type); eq(12, fx2[#fx2].money)
        local _, fx3 = E.onEvent(def, restart(s2), 'fh:zones:camp_cleared', p, T0 + 3)
        same({}, fx3, 'no second reward after reload')
    end)
end)

describe('quests jobs: cooldown', function()
    it('default cooldown is 60 minutes (one board rotation)', function()
        eq(60, Jobs.DEFAULT_COOLDOWN_MIN)
        local def, st = accept()
        local done = E.apply(def, st, 'complete', T0)
        eq(T0 + 3600, done.cooldown_until)
        eq('fh_quest_cooldown', select(2, E.canStart(def, { [def.id] = E.rewardPaid(done, T0) }, T0 + 3599)))
        eq(true, (E.canStart(def, { [def.id] = E.rewardPaid(done, T0) }, T0 + 3600)))
    end)
    it('an old snapshot without cooldown_min rebuilds with the default', function()
        local snap = Jobs.snapshot('camp_clear', offer(), 'heartlands', false)
        snap.cooldown_min = nil
        eq(60, assert(Jobs.def(snap, OPTS))['repeat'].cooldown_min)
    end)
    it('an explicit cooldown_min = 0 is kept (not defaulted)', function()
        local def, st = accept(offer({ cooldown_min = 0 }))
        eq(0, def['repeat'].cooldown_min)
        local done = E.rewardPaid((E.apply(def, st, 'complete', T0)), T0)
        eq(true, (E.canStart(def, { [def.id] = done }, T0)))
    end)
end)

describe('quests jobs: paused while the job type is unregistered', function()
    local function world()
        local def, st = accept()
        local line = {
            id = 'family_test_1', kind = 'line', title = 'A Roof', region_id = 'heartlands',
            steps = { { on = 'fh:zones:camp_cleared', text = 'Clear any camp.' } },
        }
        local lst = assert(E.start(line, {}, CID, T0))
        return { [def.id] = def, [line.id] = line }, { [def.id] = st, [line.id] = lst }
    end
    local payload = { citizenid = CID, camp_id = 'c1' }
    local JOB = 'job:camp_clear:c1'
    local function byId(changes, qid)
        for _, c in ipairs(changes) do if c.quest_id == qid then return c end end
    end
    it('hookFor = false: the job ignores events and stays active; other quests still advance', function()
        local defs, states = world()
        local changes = I.feed(defs, states, 'fh:zones:camp_cleared', payload, T0 + 1,
            function(def) if def.job_type then return false end end)
        eq(1, #changes)
        eq('family_test_1', changes[1].quest_id)
        eq('active', states['job:camp_clear:c1'].status)
    end)
    it('registered again (no onEvent hook): the engine matches the job step', function()
        local defs, states = world()
        local changes = I.feed(defs, states, 'fh:zones:camp_cleared', payload, T0 + 1, function() return nil end)
        eq(2, #changes)
        same({ 'family_test_1', JOB }, { changes[1].quest_id, changes[2].quest_id }, 'fed in quest_id order')
        eq('done', byId(changes, JOB).after.status)
    end)
    it('registered with onEvent: the hook decides, rewards still once', function()
        local defs, states = world()
        local calls = 0
        local hook = function(name, p, st)
            calls = calls + 1
            eq('fh:zones:camp_cleared', name); eq(CID, p.citizenid); eq('active', st.status)
            return 'complete'
        end
        local changes = I.feed(defs, states, 'fh:zones:camp_cleared', payload, T0 + 1,
            function(def) if def.job_type then return hook end end)
        eq(1, calls)
        eq('done', byId(changes, JOB).after.status)
        states[JOB] = byId(changes, JOB).after
        changes = I.feed(defs, states, 'fh:zones:camp_cleared', payload, T0 + 2,
            function(def) if def.job_type then return hook end end)
        eq(1, calls, 'a done job is not fed again')
        eq(nil, byId(changes, JOB), 'no second job change')
    end)
end)

T.finish()

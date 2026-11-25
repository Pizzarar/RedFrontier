-- Run from repo root: `lua spec/quests_one_job_spec.lua` (or via tools/run-specs.py).
-- idea-1017 (quests-04 L1): one fh:hunting:pelt_sold (fired once per pelt, fh_hunting/shared/sell.lua) completes at
-- most ONE matching job-kind quest: the oldest accepted (progress.accepted_at; rows without it predate the field and
-- go first, by updated_at), ties by quest id. Line/tutorial quests listening to pelt_sold still advance alongside.
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local describe, it, eq, same = T.describe, T.it, T.eq, T.same
local shared = here .. '../server/resources/[fh]/fh_quests/shared/'
package.path = shared .. '?.lua;' .. package.path
local I = dofile(shared .. 'intake.lua')
local E = require('engine')
local Jobs = require('jobs')
local JT = dofile(shared .. 'jobtypes.lua')
local S = require('store')
local regions = require('regions')

local T0 = 1795651200
local ME = 'ABC123'
local SOLD = 'fh:hunting:pelt_sold'

local function events()
    local set = {}
    for _, name in ipairs(E.INTAKE) do set[name] = true end
    return set
end

-- One region offering two elk orders a 3-star elk pelt satisfies both (2-star-or-better and 3-star-or-better),
-- plus a deer order; scarlett_meadows offers its own elk 3-star.
local DATA = { hunt = { { 'elk', 2, 30 }, { 'elk', 3, 42 }, { 'deer', 1, 10 } } }
local function offer(region_id, animal, stars)
    for _, o in ipairs(JT.BUILDERS.hunt_request(region_id, DATA)) do
        if o.animal == animal and o.stars == stars then return o end
    end
    error('no offer ' .. animal .. stars)
end
local function qid(region_id, animal, stars) return Jobs.questId('hunt_request', JT.huntKey(region_id, animal, stars)) end
local HL2, HL3 = qid('heartlands', 'elk', 2), qid('heartlands', 'elk', 3)
local SM3, DEER = qid('scarlett_meadows', 'elk', 3), qid('heartlands', 'deer', 1)

local function accept(w, region_id, animal, stars, at)
    local snap = assert(Jobs.snapshot('hunt_request', offer(region_id, animal, stars), region_id, true))
    local def = assert(Jobs.def(snap, { regions = regions.regions, events = events() }))
    local st = assert(E.start(def, w.states, ME, at))
    st.progress.job = snap
    w.states[def.id], w.defs[def.id] = st, def
    return def.id
end

local function hook(...) return JT.verdict('hunt_request', ...) end
local function hookFor(def) if def.job_type then return hook end return nil end

local function sold(over)
    local p = { citizenid = ME, item_id = 'pelt_elk', animal = 'elk', size_class = 'bulky', quality = 3, price = 40,
        region_id = 'heartlands' }
    for k, v in pairs(over or {}) do p[k] = v end
    return p
end

-- Feed one event and commit every change (as server/api.lua onIntake does). Returns the sorted ids that completed
-- and the sorted ids that changed at all.
local function feed(w, name, payload, now)
    local changes = I.feed(w.defs, w.states, name, payload, now, hookFor)
    local done, changed = {}, {}
    for _, c in ipairs(changes) do
        w.states[c.quest_id] = c.after
        changed[#changed + 1] = c.quest_id
        if c.after.status == 'done' then done[#done + 1] = c.quest_id end
    end
    table.sort(done); table.sort(changed)
    return done, changed
end

local function world() return { states = {}, defs = {} } end

local function family()
    return { id = 'family_trapper_1', kind = 'line', title = 'Trapper', region_id = 'heartlands',
        steps = { { on = SOLD, where = { quality = { min = 2 } }, count = 2, text = 'Sell two good pelts.' },
            { on = 'fh:homestead:claimed', text = 'Claim a plot.' } } }
end

describe('quests one job: accept order is recorded', function()
    it('engine.start stamps progress.accepted_at = now; a re-accept stamps the new time', function()
        local w = world()
        accept(w, 'heartlands', 'elk', 3, T0 + 7)
        eq(T0 + 7, w.states[HL3].progress.accepted_at)
        feed(w, SOLD, sold(), T0 + 8)
        eq('done', w.states[HL3].status)
        eq(T0 + 7, w.states[HL3].progress.accepted_at, 'apply keeps it')
        w.states[HL3].progress.reward_pending = nil
        accept(w, 'heartlands', 'elk', 3, T0 + 7200)
        eq(T0 + 7200, w.states[HL3].progress.accepted_at)
    end)
    it('store keeps accepted_at across a save/load round trip (integer; junk dropped)', function()
        local w = world()
        accept(w, 'heartlands', 'elk', 3, T0 + 7)
        local blob
        local p = S.params(w.states[HL3], function(t) blob = t; return 'x' end)
        eq('x', p[5]); eq(T0 + 7, blob.accepted_at)
        local row = { citizenid = ME, quest_id = HL3, status = 'active', step = 1, progress = 'x', updated_at = T0 + 7 }
        local st = assert(S.fromRow(row, function() return { count = 0, completions = 0, accepted_at = T0 + 7.0 } end))
        eq(T0 + 7, st.progress.accepted_at); eq('integer', math.type(st.progress.accepted_at))
        st = assert(S.fromRow(row, function() return { count = 0, accepted_at = 'soon' } end))
        eq(nil, st.progress.accepted_at)
    end)
end)

describe('quests one job: one pelt_sold completes one job (idea-1017)', function()
    it('2 matching orders + 1 pelt: exactly 1 completes, the older one; a second pelt completes the other', function()
        local w = world()
        accept(w, 'heartlands', 'elk', 3, T0)      -- older, but the higher quest id
        accept(w, 'heartlands', 'elk', 2, T0 + 5)
        local done = feed(w, SOLD, sold(), T0 + 10)
        same({ HL3 }, done)
        eq('active', w.states[HL2].status); eq(0, w.states[HL2].progress.count)
        done = feed(w, SOLD, sold(), T0 + 20)
        same({ HL2 }, done)
        same({}, (feed(w, SOLD, sold(), T0 + 30)), 'nothing left to complete')
    end)
    it('exactly one reward is emitted per pelt', function()
        local w = world()
        accept(w, 'heartlands', 'elk', 2, T0); accept(w, 'heartlands', 'elk', 3, T0 + 1)
        local n = 0
        for _, c in ipairs(I.feed(w.defs, w.states, SOLD, sold(), T0 + 10, hookFor)) do
            for _, fx in ipairs(c.effects) do if fx.type == 'reward' then n = n + 1 end end
        end
        eq(1, n)
    end)
    it('equal accept time: the tie goes to the lowest quest id', function()
        local w = world()
        accept(w, 'heartlands', 'elk', 3, T0)
        accept(w, 'heartlands', 'elk', 2, T0)
        assert(HL2 < HL3)
        same({ HL2 }, (feed(w, SOLD, sold(), T0 + 10)))
        same({ HL3 }, (feed(w, SOLD, sold(), T0 + 11)))
    end)
    it('a family pelt_sold step advances alongside the one job', function()
        local w = world()
        local fam = family()
        w.defs[fam.id] = fam
        w.states[fam.id] = assert(E.start(fam, w.states, ME, T0 - 999)) -- older than both jobs: still not "the" job
        accept(w, 'heartlands', 'elk', 3, T0); accept(w, 'heartlands', 'elk', 2, T0 + 5)
        local done, changed = feed(w, SOLD, sold(), T0 + 10)
        same({ HL3 }, done)
        same({ fam.id, HL3 }, changed)
        eq(1, w.states[fam.id].progress.count)
        done, changed = feed(w, SOLD, sold(), T0 + 20)
        same({ HL2 }, done)
        same({ fam.id, HL2 }, changed)
        eq(2, w.states[fam.id].step, 'family step 1 finished on the second pelt')
    end)
    it('a tutorial step listening to pelt_sold also advances alongside', function()
        local w = world()
        local tut = { id = 'guide_sell', kind = 'tutorial', title = 'Sell', steps = { { on = SOLD, text = 'Sell a pelt.' } } }
        w.defs[tut.id] = tut
        w.states[tut.id] = assert(E.start(tut, w.states, ME, T0))
        accept(w, 'heartlands', 'elk', 2, T0 + 1); accept(w, 'heartlands', 'elk', 3, T0 + 2)
        same({ 'guide_sell', HL2 }, (feed(w, SOLD, sold(), T0 + 10)))
    end)
    it('a non-matching older job (wrong region / wrong animal) does not consume the pelt', function()
        local w = world()
        accept(w, 'scarlett_meadows', 'elk', 3, T0 - 100) -- oldest, wrong region
        accept(w, 'heartlands', 'deer', 1, T0 - 50)       -- older, wrong animal
        accept(w, 'heartlands', 'elk', 3, T0)
        local done, changed = feed(w, SOLD, sold(), T0 + 10)
        same({ HL3 }, done); same({ HL3 }, changed)
        eq('active', w.states[SM3].status); eq('active', w.states[DEER].status)
    end)
    it('a too-low quality pelt matches only the lower order, which then takes it', function()
        local w = world()
        accept(w, 'heartlands', 'elk', 3, T0); accept(w, 'heartlands', 'elk', 2, T0 + 5)
        same({ HL2 }, (feed(w, SOLD, sold({ quality = 2 }), T0 + 10)))
        eq('active', w.states[HL3].status)
    end)
    it('a paused job (job type not registered) is skipped and does not consume the pelt', function()
        local w = world()
        accept(w, 'heartlands', 'elk', 3, T0); accept(w, 'heartlands', 'elk', 2, T0 + 5)
        local changes = I.feed(w.defs, w.states, SOLD, sold(), T0 + 10, function(def)
            if def.id == HL3 then return false end
            return hook
        end)
        eq(1, #changes); eq(HL2, changes[1].quest_id)
    end)
    it('the later job hook is not even asked once a job took the pelt', function()
        local w = world()
        accept(w, 'heartlands', 'elk', 3, T0); accept(w, 'heartlands', 'elk', 2, T0 + 5)
        local asked = {}
        I.feed(w.defs, w.states, SOLD, sold(), T0 + 10, function(def)
            return function(...) asked[#asked + 1] = def.id; return hook(...) end
        end)
        same({ HL3 }, asked)
    end)
    it('engine-matched jobs (no hook) follow the same rule', function()
        local w = world()
        accept(w, 'heartlands', 'elk', 3, T0); accept(w, 'heartlands', 'elk', 2, T0 + 5)
        local done = {}
        for _, c in ipairs(I.feed(w.defs, w.states, SOLD, sold(), T0 + 10, function() return nil end)) do
            if c.after.status == 'done' then done[#done + 1] = c.quest_id end
        end
        same({ HL3 }, done)
    end)
    it('another seller\'s pelt never consumes my order', function()
        local w = world()
        accept(w, 'heartlands', 'elk', 3, T0)
        same({}, (feed(w, SOLD, sold({ citizenid = 'XYZ999' }), T0 + 10)))
    end)
end)

describe('quests one job: legacy / re-keyed rows (idea-902) without accepted_at', function()
    local function legacy(w, id, updated_at)
        w.states[id].progress.accepted_at = nil
        w.states[id].updated_at = updated_at
    end
    it('a row without accepted_at goes before any row that has one (it predates the field)', function()
        local w = world()
        accept(w, 'heartlands', 'elk', 2, T0)
        accept(w, 'heartlands', 'elk', 3, T0 + 5)
        legacy(w, HL3, T0 + 900) -- its last write is even later than HL2's accept
        same({ HL3 }, (feed(w, SOLD, sold(), T0 + 1000)))
        same({ HL2 }, (feed(w, SOLD, sold(), T0 + 1001)))
    end)
    it('two rows without accepted_at go by updated_at, then quest id', function()
        local w = world()
        accept(w, 'heartlands', 'elk', 2, T0); accept(w, 'heartlands', 'elk', 3, T0)
        legacy(w, HL2, T0 - 10); legacy(w, HL3, T0 - 20)
        same({ HL3 }, (feed(w, SOLD, sold(), T0 + 10)))
        w = world()
        accept(w, 'heartlands', 'elk', 2, T0); accept(w, 'heartlands', 'elk', 3, T0)
        legacy(w, HL2, T0 - 10); legacy(w, HL3, T0 - 10)
        same({ HL2 }, (feed(w, SOLD, sold(), T0 + 10)))
    end)
    it('a re-keyed legacy job (unscoped where) and a scoped job from another region: one pelt, one job', function()
        local w = world()
        accept(w, 'scarlett_meadows', 'elk', 3, T0 + 5)
        local old = { citizenid = ME, quest_id = 'job:hunt_request:elk_3star', status = 'active', step = 1,
            progress = { count = 0, completions = 2, job = { job_type = 'hunt_request', key = 'elk_3star',
                region_id = 'heartlands', title = 'Pelt wanted: 3-star elk', text = 'Sell a 3-star or better elk pelt.',
                on = SOLD, where = { quality = { min = 3 }, animal = { eq = 'elk' } },
                rewards = { money = 63, rep = { region_id = 'heartlands', delta = 2 } }, cooldown_min = 60, hook = true } },
            updated_at = T0 + 600 }
        local st = assert(Jobs.migrateLegacy(old, { regions = regions.regions }))
        eq(HL3, st.quest_id); eq(nil, st.progress.accepted_at)
        w.states[HL3] = st
        w.defs[HL3] = assert(Jobs.def(st.progress.job, { regions = regions.regions, events = events() }))
        -- a scarlett_meadows sale matches both (the legacy where is unscoped): the legacy row is older
        same({ HL3 }, (feed(w, SOLD, sold({ region_id = 'scarlett_meadows' }), T0 + 700)))
        eq('active', w.states[SM3].status)
        same({ SM3 }, (feed(w, SOLD, sold({ region_id = 'scarlett_meadows' }), T0 + 701)))
    end)
end)

describe('quests one job: other events are unchanged (scope = pelt_sold)', function()
    local function job(id, on)
        return { id = id, kind = 'job', title = id, region_id = 'heartlands', ['repeat'] = { cooldown_min = 30 },
            steps = { { on = on, text = 'Do it.' } }, rewards = { money = 5 } }
    end
    it('two jobs on pelt_skinned both advance on one event', function()
        local w = world()
        for i, id in ipairs({ 'job:x:a', 'job:x:b' }) do
            w.defs[id] = job(id, 'fh:hunting:pelt_skinned')
            w.states[id] = assert(E.start(w.defs[id], w.states, ME, T0 + i))
        end
        same({ 'job:x:a', 'job:x:b' }, (feed(w, 'fh:hunting:pelt_skinned', { citizenid = ME }, T0 + 10)))
    end)
    it('ONE_JOB_EVENTS lists exactly pelt_sold', function()
        local n = 0
        for name, on in pairs(I.ONE_JOB_EVENTS) do n = n + 1; eq(SOLD, name); eq(true, on) end
        eq(1, n)
    end)
end)

T.finish()

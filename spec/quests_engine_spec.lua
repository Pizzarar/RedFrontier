-- Run from repo root: `lua spec/quests_engine_spec.lua` (or via tools/run-specs.py).
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local describe, it, eq, same = T.describe, T.it, T.eq, T.same
local shared = here .. '../server/resources/[fh]/fh_quests/shared/'
package.path = shared .. '?.lua;' .. package.path
local E = dofile(shared .. 'engine.lua')
local regions = require('regions')

local T0 = 1795651200
local CID = 'ABC123'

local function line()
    return {
        id = 'family_test_1', kind = 'line', title = 'A Roof', giver = 'npc_hale', region_id = 'heartlands',
        steps = {
            { on = 'fh:homestead:claimed', text = 'Claim a plot.' },
            { on = 'fh:hunting:pelt_sold', where = { quality = { min = 2 } }, count = 2, text = 'Sell two good pelts.' },
            { talk = { npc = 'npc_hale', lines = { 'Well done.' } }, text = 'Report to Hale.' },
        },
        rewards = { money = 25, rep = { region_id = 'heartlands', delta = 5 }, items = { { name = 'bread', amount = 2 } } },
    }
end

local function job()
    return {
        id = 'job:camp_clear:t1', kind = 'job', title = 'Clear the camp', region_id = 'heartlands',
        ['repeat'] = { cooldown_min = 30 },
        steps = { { on = 'fh:zones:camp_cleared', where = { camp_id = 'heartlands_t1_camp' }, text = 'Clear it.' } },
        rewards = { money = 10 },
    }
end

local function types(effects)
    local t = {}
    for i, e in ipairs(effects) do t[i] = e.type end
    return t
end

local function count(effects, type_)
    local n = 0
    for _, e in ipairs(effects) do if e.type == type_ then n = n + 1 end end
    return n
end

local function started(def, byQuest, now)
    local s, fx = E.start(def, byQuest or {}, CID, now or T0)
    assert(s, tostring(fx))
    return s, fx
end

-- Drive the line quest to completion; returns final state and all effects in order.
local function finishLine(def)
    local s, fx = started(def)
    local all = { table.unpack(fx) }
    local function feed(name, payload)
        local e
        s, e = E.onEvent(def, s, name, payload, T0 + 10)
        for _, x in ipairs(e) do all[#all + 1] = x end
    end
    feed('fh:homestead:claimed', { src = 1, citizenid = CID, plot_id = 'p1', region_id = 'heartlands' })
    feed('fh:hunting:pelt_sold', { citizenid = CID, quality = 2 })
    feed('fh:hunting:pelt_sold', { citizenid = CID, quality = 3 })
    feed('fh:quests:talked', { src = 1, citizenid = CID, npc_id = 'npc_hale' })
    return s, all
end

describe('quests engine: validate', function()
    local opts = { regions = regions.regions }
    local function bad(mut, code)
        local d = line()
        mut(d)
        local ok, err = E.validate(d, opts)
        eq(false, ok, code)
        assert(tostring(err):find(code, 1, true), 'expected ' .. code .. ', got ' .. tostring(err))
    end
    it('accepts the documented line and job shapes', function()
        assert(E.validate(line(), opts))
        assert(E.validate(job(), opts))
    end)
    it('rejects malformed defs', function()
        eq(false, (E.validate(nil)))
        eq(false, (E.validate('x')))
        bad(function(d) d.id = nil end, 'fh_bad_id')
        bad(function(d) d.id = 'has space' end, 'fh_bad_id')
        bad(function(d) d.id = string.rep('a', 65) end, 'fh_bad_id')
        bad(function(d) d.kind = 'side' end, 'fh_bad_kind')
        bad(function(d) d.title = '' end, 'fh_bad_title')
        bad(function(d) d.giver = 5 end, 'fh_bad_giver')
        bad(function(d) d.region_id = 'mars' end, 'fh_bad_region')
        bad(function(d) d.prereq = { d.id } end, 'fh_prereq_self')
        bad(function(d) d.prereq = { x = 'a' } end, 'fh_bad_prereq')
        bad(function(d) d['repeat'] = { cooldown_min = -1 } end, 'fh_bad_repeat')
        bad(function(d) d['repeat'] = {} end, 'fh_bad_repeat')
        bad(function(d) d.steps = {} end, 'fh_no_steps')
        bad(function(d) d.steps = nil end, 'fh_no_steps')
        bad(function(d) d.steps[2].on = 'fh:nope:never' end, 'fh_bad_step_event@step2')
        bad(function(d) d.steps[1].on = nil end, 'fh_bad_step_event@step1')
        bad(function(d) d.steps[2].count = 0 end, 'fh_bad_step_count@step2')
        bad(function(d) d.steps[2].count = 1.5 end, 'fh_bad_step_count@step2')
        bad(function(d) d.steps[1].text = nil end, 'fh_bad_step_text@step1')
        bad(function(d) d.steps[2].where = { quality = { min = 'x' } } end, 'fh_bad_min@quality@step2')
        bad(function(d) d.steps[3].talk = { lines = {} } end, 'fh_bad_talk@step3')
        bad(function(d) d.steps[3].talk.lines = { 1 } end, 'fh_bad_talk_lines@step3')
        bad(function(d) d.rewards.money = -1 end, 'fh_bad_money')
        bad(function(d) d.rewards.money = 2.5 end, 'fh_bad_money')
        bad(function(d) d.rewards.rep = { region_id = 'mars', delta = 1 } end, 'fh_bad_rep_region')
        bad(function(d) d.rewards.rep.delta = 0 end, 'fh_bad_rep_delta')
        bad(function(d) d.rewards.items = { { name = 'bread', amount = 0 } } end, 'fh_bad_item_amount')
        bad(function(d) d.rewards.items = { { amount = 1 } } end, 'fh_bad_item')
        bad(function(d) d.rewards.gold = 1 end, 'fh_unknown_reward:gold')
    end)
    it('the intake whitelist holds the contract events and nothing else', function()
        for _, n in ipairs({ 'fh:zones:camp_cleared', 'fh:hunting:pelt_skinned', 'fh:hunting:pelt_sold',
            'fh:hunting:chain_complete', 'fh:homestead:claimed', 'fh:economy:paid', 'fh:economy:rep_changed',
            'fh:death:dropped', 'fh:death:recovered', 'fh:death:expired', 'fh:quests:talked' }) do
            assert(E.isIntake(n), n)
        end
        eq(false, E.isIntake('fh:inventory:moved'))
        eq(false, E.isIntake('playerDropped'))
    end)
    it('a talk step defaults to fh:quests:talked with npc_id = talk.npc', function()
        local s = E.stepOf(line(), 3)
        eq('fh:quests:talked', s.on); eq('npc_hale', s.where.npc_id); eq(1, s.count)
    end)
end)

describe('quests engine: start / advance / count / complete', function()
    it('start gives an active state at step 1 and a started effect', function()
        local s, fx = started(line())
        eq('active', s.status); eq(1, s.step); eq(CID, s.citizenid); eq('family_test_1', s.quest_id)
        eq(0, s.progress.count); eq(T0, s.updated_at)
        same({ 'started' }, types(fx))
        eq('line', fx[1].kind); eq(1, fx[1].step)
    end)
    it('start refuses a bad citizenid', function()
        local s, err = E.start(line(), {}, '', T0)
        eq(nil, s); eq('fh_bad_citizenid', err)
    end)
    it('the right event advances a step; count needs that many matches', function()
        local def = line()
        local s = started(def)
        local s2, fx = E.onEvent(def, s, 'fh:homestead:claimed', { citizenid = CID }, T0 + 1)
        eq(2, s2.step); same({ 'step' }, types(fx)); eq(2, fx[1].step); eq(2, fx[1].need)
        eq(1, s.step, 'input state is not mutated')
        local s3, fx3 = E.onEvent(def, s2, 'fh:hunting:pelt_sold', { citizenid = CID, quality = 2 }, T0 + 2)
        eq(2, s3.step); eq(1, s3.progress.count); eq(1, fx3[1].count)
        local s4 = E.onEvent(def, s3, 'fh:hunting:pelt_sold', { citizenid = CID, quality = 3 }, T0 + 3)
        eq(3, s4.step); eq(0, s4.progress.count)
    end)
    it('a non-matching where, the wrong event or an off-step event changes nothing', function()
        local def = line()
        local s = started(def)
        local s2, fx = E.onEvent(def, s, 'fh:hunting:pelt_sold', { citizenid = CID, quality = 3 }, T0)
        eq(s, s2); same({}, fx)
        s = E.onEvent(def, s, 'fh:homestead:claimed', { citizenid = CID }, T0)
        s2, fx = E.onEvent(def, s, 'fh:hunting:pelt_sold', { citizenid = CID, quality = 1 }, T0)
        eq(s, s2); same({}, fx)
        s2, fx = E.onEvent(def, s, 'fh:quests:talked', { citizenid = CID, npc_id = 'npc_hale' }, T0)
        eq(s, s2); same({}, fx)
    end)
    it('a wrong citizenid (or none) never advances', function()
        local def = line()
        local s = started(def)
        local s2, fx = E.onEvent(def, s, 'fh:homestead:claimed', { citizenid = 'OTHER' }, T0)
        eq(s, s2); same({}, fx)
        s2, fx = E.onEvent(def, s, 'fh:homestead:claimed', { src = 3 }, T0)
        eq(s, s2); same({}, fx)
        s2, fx = E.onEvent(def, s, 'fh:homestead:claimed', nil, T0)
        eq(s, s2); same({}, fx)
    end)
    it('talk to the wrong npc does not advance the talk step', function()
        local def = line()
        local s = started(def)
        s = E.onEvent(def, s, 'fh:homestead:claimed', { citizenid = CID }, T0)
        s = E.onEvent(def, s, 'fh:hunting:pelt_sold', { citizenid = CID, quality = 2 }, T0)
        s = E.onEvent(def, s, 'fh:hunting:pelt_sold', { citizenid = CID, quality = 2 }, T0)
        local s2, fx = E.onEvent(def, s, 'fh:quests:talked', { citizenid = CID, npc_id = 'npc_other' }, T0)
        eq(s, s2); same({}, fx)
    end)
    it('the last step completes and emits completed then reward once', function()
        local s, all = finishLine(line())
        eq('done', s.status); eq(1, s.progress.completions); eq(true, s.progress.reward_pending)
        same({ 'started', 'step', 'step', 'step', 'completed', 'reward' }, types(all))
        local r = all[#all]
        eq('quest:family_test_1', r.reason); eq(25, r.money); eq(5, r.rep.delta); eq('bread', r.items[1].name)
        eq(CID, r.citizenid); eq('heartlands', r.region_id)
        eq(nil, s.cooldown_until, 'one-time quests have no cooldown')
    end)
    it('participants credit (camp_cleared after Q0a)', function()
        local def = job()
        local s = started(def)
        local s2, fx = E.onEvent(def, s, 'fh:zones:camp_cleared',
            { camp_id = 'heartlands_t1_camp', region_id = 'heartlands', participants = { 'X', CID } }, T0)
        eq('done', s2.status); same({ 'completed', 'reward' }, types(fx))
    end)
    it('camp_cleared without a player (today) credits nobody', function()
        local def = job()
        local s = started(def)
        local s2, fx = E.onEvent(def, s, 'fh:zones:camp_cleared', { camp_id = 'heartlands_t1_camp', region_id = 'heartlands' }, T0)
        eq(s, s2); same({}, fx)
    end)
    it('a quest without rewards completes with no reward effect', function()
        local def = job(); def.rewards = nil
        local s, fx = E.apply(def, started(def), 'complete', T0)
        eq('done', s.status); same({ 'completed' }, types(fx)); eq(nil, s.progress.reward_pending)
    end)
end)

describe('quests engine: reward exactly once', function()
    it('re-fired events after completion produce no effects and no second reward', function()
        local def = line()
        local s = finishLine(def)
        for _, ev in ipairs({
            { 'fh:quests:talked', { citizenid = CID, npc_id = 'npc_hale' } },
            { 'fh:homestead:claimed', { citizenid = CID } },
            { 'fh:hunting:pelt_sold', { citizenid = CID, quality = 3 } },
        }) do
            local s2, fx = E.onEvent(def, s, ev[1], ev[2], T0 + 99)
            eq(s, s2); same({}, fx)
        end
    end)
    it('a duplicate complete verdict after completion is a no-op', function()
        local def = job()
        local s, fx = E.apply(def, started(def), 'complete', T0)
        eq(1, count(fx, 'reward'))
        local s2, fx2 = E.apply(def, s, 'complete', T0 + 1)
        eq(s, s2); same({}, fx2)
        s2, fx2 = E.apply(def, s, 'progress', T0 + 1)
        eq(s, s2); same({}, fx2)
    end)
    it('the same completing event fired twice on the same state copy pays once per state', function()
        -- the server feeds events sequentially and persists the returned state; the second event sees 'done'
        local def = job()
        local s = started(def)
        local p = { camp_id = 'heartlands_t1_camp', participants = { CID } }
        local s2, fx = E.onEvent(def, s, 'fh:zones:camp_cleared', p, T0)
        local _, fx2 = E.onEvent(def, s2, 'fh:zones:camp_cleared', p, T0)
        eq(1, count(fx, 'reward')); eq(0, count(fx2, 'reward'))
    end)
    it("a quest's own payout event never advances a quest", function()
        local def = job()
        def.steps = { { on = 'fh:economy:paid', text = 'Get paid.' } }
        local s = started(def)
        local s2, fx = E.onEvent(def, s, 'fh:economy:paid', { citizenid = CID, amount = 10, reason = 'quest:other' }, T0)
        eq(s, s2); same({}, fx)
        s2, fx = E.onEvent(def, s, 'fh:economy:paid', { citizenid = CID, amount = 10, reason = 'pelt:pelt_wolf' }, T0)
        eq('done', s2.status)
    end)
    it('pendingReward re-offers an unpaid reward; rewardPaid clears it and it is idempotent', function()
        local def = line()
        local s = finishLine(def)
        local r = E.pendingReward(def, s)
        eq('reward', r.type); eq('quest:family_test_1', r.reason)
        local paid = E.rewardPaid(s, T0 + 20)
        eq(nil, paid.progress.reward_pending); eq(nil, E.pendingReward(def, paid))
        eq(true, s.progress.reward_pending, 'input state is not mutated')
        eq(paid, E.rewardPaid(paid, T0 + 21))
    end)
    it('start refuses while a reward is still pending', function()
        local def = job()
        local s = E.apply(def, started(def), 'complete', T0)
        local ok, err = E.canStart(def, { [def.id] = s }, T0 + 99999)
        eq(false, ok); eq('fh_reward_pending', err)
    end)
end)

describe('quests engine: fail / abandon', function()
    it('abandon an active quest: abandoned effect, no reward, restartable', function()
        local def = line()
        local s = started(def)
        local s2, fx = E.abandon(def, s, T0 + 5)
        eq('abandoned', s2.status); same({ 'abandoned' }, types(fx)); eq(T0 + 5, s2.updated_at)
        assert(E.canStart(def, { [def.id] = s2 }, T0 + 6))
        local s3 = started(def, { [def.id] = s2 }, T0 + 6)
        eq('active', s3.status); eq(1, s3.step)
    end)
    it('fail an active quest carries the reason', function()
        local def = line()
        local s2, fx = E.fail(def, started(def), T0, 'fh_target_lost')
        eq('failed', s2.status); same({ 'failed' }, types(fx)); eq('fh_target_lost', fx[1].reason)
        local s3, fx3 = E.apply(def, started(def), 'fail', T0)
        eq('failed', s3.status); same({ 'failed' }, types(fx3))
    end)
    it('abandon/fail on a non-active state is a no-op', function()
        local def = line()
        local done = finishLine(def)
        local s, fx = E.abandon(def, done, T0)
        eq(done, s); same({}, fx)
        s, fx = E.fail(def, done, T0, 'x')
        eq(done, s); same({}, fx)
        eq(nil, (E.abandon(def, nil, T0)))
    end)
    it('events on a failed or abandoned quest do nothing', function()
        local def = line()
        local s = E.abandon(def, started(def), T0)
        local s2, fx = E.onEvent(def, s, 'fh:homestead:claimed', { citizenid = CID }, T0)
        eq(s, s2); same({}, fx)
    end)
    it('unknown verdicts (nil from a job hook) change nothing', function()
        local def = job()
        local s = started(def)
        local s2, fx = E.apply(def, s, nil, T0)
        eq(s, s2); same({}, fx)
        s2, fx = E.apply(def, s, 'explode', T0)
        eq(s, s2); same({}, fx)
    end)
end)

describe('quests engine: canStart gates', function()
    it('an active quest cannot be started again', function()
        local def = line()
        local ok, err = E.canStart(def, { [def.id] = started(def) }, T0)
        eq(false, ok); eq('fh_quest_active', err)
    end)
    it('prereq gate: blocked until the prereq is done', function()
        local pre = job()
        local def = line(); def.prereq = { pre.id }
        local ok, err = E.canStart(def, {}, T0)
        eq(false, ok); eq('fh_quest_prereq:' .. pre.id, err)
        local active = started(pre)
        ok, err = E.canStart(def, { [pre.id] = active }, T0)
        eq(false, ok); eq('fh_quest_prereq:' .. pre.id, err)
        local done = E.rewardPaid((E.apply(pre, active, 'complete', T0)), T0)
        assert(E.canStart(def, { [pre.id] = done }, T0))
    end)
    it('prereq stays satisfied while a repeatable prereq is re-running', function()
        local pre = job()
        local done = E.rewardPaid((E.apply(pre, started(pre), 'complete', T0)), T0)
        local again = started(pre, { [pre.id] = done }, T0 + 30 * 60)
        eq('active', again.status); eq(1, again.progress.completions)
        local def = line(); def.prereq = { pre.id }
        assert(E.canStart(def, { [pre.id] = again }, T0 + 30 * 60))
    end)
    it('one-time: done means never again', function()
        local def = line()
        local done = E.rewardPaid((finishLine(def)), T0)
        local ok, err = E.canStart(def, { [def.id] = done }, T0 + 10 ^ 7)
        eq(false, ok); eq('fh_quest_done', err)
    end)
    it('repeatable: blocked during cooldown, allowed from cooldown_until on', function()
        local def = job()
        local done = E.rewardPaid((E.apply(def, started(def), 'complete', T0)), T0)
        eq(T0 + 30 * 60, done.cooldown_until)
        local by = { [def.id] = done }
        local ok, err = E.canStart(def, by, T0 + 30 * 60 - 1)
        eq(false, ok); eq('fh_quest_cooldown', err)
        assert(E.canStart(def, by, T0 + 30 * 60))
        local s, fx = E.start(def, by, CID, function() return T0 + 30 * 60 end)
        eq('active', s.status); same({ 'started' }, types(fx))
        local s2, fx2 = E.apply(def, s, 'complete', T0 + 31 * 60)
        eq(2, s2.progress.completions); eq(1, count(fx2, 'reward')); eq(T0 + 61 * 60, s2.cooldown_until)
    end)
    it('repeatable with cooldown 0 restarts immediately after payment', function()
        local def = job(); def['repeat'] = { cooldown_min = 0 }
        local done = E.rewardPaid((E.apply(def, started(def), 'complete', T0)), T0)
        assert(E.canStart(def, { [def.id] = done }, T0))
    end)
end)

T.finish()

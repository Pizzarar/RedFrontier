-- Run from repo root: `lua spec/quests_journal_spec.lua` (or via tools/run-specs.py).
-- fh_quests journal.lua: the fh:quests:sync payload (README "Client sync").
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local describe, it, eq, same = T.describe, T.it, T.eq, T.same
local shared = here .. '../server/resources/[fh]/fh_quests/shared/'
package.path = shared .. '?.lua;' .. package.path
local J = dofile(shared .. 'journal.lua')
local Jobs = require('jobs')

local T0 = 1795651200
local CID = 'ABC123'

local function line(id)
    return {
        id = id or 'family_test_1', kind = 'line', title = 'A Roof', giver = 'npc_hale', region_id = 'heartlands',
        steps = {
            { on = 'fh:homestead:claimed', text = 'Claim a plot.' },
            { on = 'fh:hunting:pelt_sold', count = 3, text = 'Sell three pelts.' },
        },
        rewards = { money = 25, rep = { region_id = 'heartlands', delta = 5 },
            items = { { name = 'bread', amount = 2, info = { secret = true } } } },
    }
end

local function job(id)
    return {
        id = id or 'job:camp_clear:c1', kind = 'job', title = 'Clear the camp', region_id = 'heartlands',
        job_type = 'camp_clear', ['repeat'] = { cooldown_min = 60 },
        steps = { { on = 'fh:zones:camp_cleared', text = 'Clear it.' } },
        rewards = { money = 10 },
    }
end

local function state(qid, status, step, count, updated, extra)
    local s = { citizenid = CID, quest_id = qid, status = status, step = step or 1,
        progress = { count = count or 0, completions = 0 }, updated_at = updated or T0 }
    for k, v in pairs(extra or {}) do s[k] = v end
    return s
end

local function ids(entries)
    local t = {}
    for i, e in ipairs(entries) do t[i] = e.quest_id end
    return t
end

describe('quests journal: entry', function()
    it('has every README field for an active quest', function()
        local e = J.entry(line(), state('family_test_1', 'active', 2, 1, T0 + 5))
        same({
            quest_id = 'family_test_1', kind = 'line', title = 'A Roof', giver = 'npc_hale', region_id = 'heartlands',
            status = 'active', step = 2, steps_total = 2, step_text = 'Sell three pelts.', count = 1, need = 3,
            rewards = { money = 25, rep = { region_id = 'heartlands', delta = 5 }, items = { { name = 'bread', amount = 2 } } },
            cooldown_until = nil, updated_at = T0 + 5,
        }, e)
    end)
    it('resolves the step by id after a reorder', function()
        local d = line()
        d.steps = {
            { id = 'claim', on = 'fh:homestead:claimed', text = 'Claim a plot.' },
            { id = 'sell', on = 'fh:hunting:pelt_sold', count = 3, text = 'Sell three pelts.' },
        }
        d.steps = { d.steps[2], d.steps[1] } -- reordered: sell is now step 1
        local st = state('family_test_1', 'active', 2, 1) -- index from the old order still says 2
        st.progress.step_id = 'sell'
        local e = J.entry(d, st)
        eq(1, e.step); eq('Sell three pelts.', e.step_text); eq(3, e.need)
    end)
    it('item info never reaches the client', function()
        local e = J.entry(line(), state('family_test_1', 'active'))
        eq(nil, e.rewards.items[1].info)
    end)
    it('count is 0 unless active; need defaults to 1', function()
        local e = J.entry(line(), state('family_test_1', 'done', 2, 2))
        eq(0, e.count)
        e = J.entry(line(), state('family_test_1', 'active', 1))
        eq(1, e.need)
    end)
    it('a step past the end (def shrank) shows the last step; step < 1 shows the first', function()
        local e = J.entry(line(), state('family_test_1', 'active', 9))
        eq(2, e.step); eq('Sell three pelts.', e.step_text)
        e = J.entry(line(), state('family_test_1', 'active', 0))
        eq(1, e.step); eq('Claim a plot.', e.step_text)
    end)
    it('no rewards -> empty table; cooldown_until is passed through', function()
        local def = job()
        def.rewards = nil
        local e = J.entry(def, state(def.id, 'done', 1, 0, T0, { cooldown_until = T0 + 3600 }))
        same({}, e.rewards)
        eq(T0 + 3600, e.cooldown_until)
        eq(nil, e.giver)
    end)
end)

describe('quests journal: shown', function()
    it('active quests are always shown (one-time and repeatable)', function()
        eq(true, J.shown(line(), state('x', 'active')))
        eq(true, J.shown(job(), state('x', 'active')))
    end)
    it('done / failed one-time quests stay as history', function()
        eq(true, J.shown(line(), state('x', 'done')))
        eq(true, J.shown(line(), state('x', 'failed')))
    end)
    it('abandoned quests and finished repeatables are hidden', function()
        eq(false, J.shown(line(), state('x', 'abandoned')))
        eq(false, J.shown(job(), state('x', 'done')))
        eq(false, J.shown(job(), state('x', 'failed')))
        eq(false, J.shown(job(), state('x', 'abandoned')))
    end)
end)

describe('quests journal: journal ordering and filters', function()
    local defs = {
        a_line = line('a_line'), b_line = line('b_line'), c_line = line('c_line'), d_line = line('d_line'),
        ['job:camp_clear:c1'] = job(), e_gone = line('e_gone'),
    }
    local states = {
        a_line = state('a_line', 'done', 2, 0, T0 + 10),
        b_line = state('b_line', 'active', 1, 0, T0 + 1),
        c_line = state('c_line', 'active', 1, 0, T0 + 20),
        d_line = state('d_line', 'done', 2, 0, T0 + 10),
        ['job:camp_clear:c1'] = state('job:camp_clear:c1', 'done', 1, 0, T0 + 50),
        e_gone = state('e_gone', 'abandoned', 1, 0, T0 + 99),
        orphan = state('orphan', 'active', 1, 0, T0 + 100), -- no registered def: skipped
    }
    it('active first, then newest first, then quest_id', function()
        same({ 'c_line', 'b_line', 'a_line', 'd_line' }, ids(J.journal(defs, states)))
    end)
    it('activeOnly lists active quests only (getActive)', function()
        same({ 'c_line', 'b_line' }, ids(J.journal(defs, states, true)))
    end)
    it('activeOnly includes an active repeatable job', function()
        local s2 = {}
        for k, v in pairs(states) do s2[k] = v end
        s2['job:camp_clear:c1'] = state('job:camp_clear:c1', 'active', 1, 0, T0 + 30)
        same({ 'job:camp_clear:c1', 'c_line', 'b_line' }, ids(J.journal(defs, s2, true)))
    end)
    it('empty / nil states -> empty journal', function()
        same({}, J.journal(defs, nil))
        same({}, J.journal(defs, {}, true))
    end)
end)

describe('quests journal: boardView and snapshot', function()
    local offers = {
        { id = 'heartlands:7:camp_clear:c1', job_type = 'camp_clear', key = 'c1', title = 'Clear camp one',
            offer = { key = 'c1', title = 'Clear camp one', text = 'Go clear it.', rewards = { money = 12, junk = 1 },
                secret = 'not for clients' } },
        { id = 'heartlands:7:bounty:b2', job_type = 'bounty', key = 'b2', title = 'Wanted',
            offer = { key = 'b2', title = 'Wanted', text = 42 } },
        { id = 'heartlands:7:freight:f3', job_type = 'freight', key = 'f3', title = 'Haul' },
    }
    it('maps offers to the README shape, in order', function()
        local v = J.boardView('heartlands', 7, 3600, offers, { ['job:bounty:b2'] = true }, Jobs.questId)
        eq('heartlands', v.region_id); eq(7, v.epoch); eq(3600, v.expires_at)
        eq(3, #v.offers)
        same({ id = 'heartlands:7:camp_clear:c1', job_type = 'camp_clear', title = 'Clear camp one',
            text = 'Go clear it.', rewards = { money = 12 }, accepted = false }, v.offers[1])
        same({ id = 'heartlands:7:bounty:b2', job_type = 'bounty', title = 'Wanted', text = nil, rewards = {},
            accepted = true }, v.offers[2], 'non-string text dropped; accepted from the active job id')
        same({ id = 'heartlands:7:freight:f3', job_type = 'freight', title = 'Haul', text = nil, rewards = {},
            accepted = false }, v.offers[3], 'offer without a source table')
    end)
    it('nil offers / accepted -> empty board', function()
        local v = J.boardView('heartlands', 7, 3600, nil, nil, Jobs.questId)
        same({ region_id = 'heartlands', epoch = 7, expires_at = 3600, offers = {} }, v)
    end)
    it('snapshot is v1 with the full journal and the board (or nil)', function()
        local defs = { a = line('a') }
        local states = { a = state('a', 'active') }
        local snap = J.snapshot(defs, states, nil)
        eq(1, snap.v); eq(1, J.VERSION)
        eq(nil, snap.board)
        same({ 'a' }, ids(snap.journal))
        local b = J.boardView('heartlands', 7, 3600, offers, {}, Jobs.questId)
        eq(b, J.snapshot(defs, states, b).board)
    end)
end)

T.finish()

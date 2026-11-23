-- Run from repo root: `lua spec/quests_store_spec.lua` (or via tools/run-specs.py).
-- fh_quests store.lua: state <-> fh_quest_state row (migration 0007_quest_state.sql).
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local describe, it, eq, same = T.describe, T.it, T.eq, T.same
local shared = here .. '../server/resources/[fh]/fh_quests/shared/'
package.path = shared .. '?.lua;' .. package.path
local S = dofile(shared .. 'store.lua')
local E = require('engine')

local T0 = 1795651200
local CID = 'ABC123'

-- A lossy stand-in for the CfxLua json global as oxmysql rows see it: encode stores a deep copy, decode hands
-- back a copy in which every number is a float (what a JSON round trip may do). Unknown strings fail to decode.
local function codec()
    local store, n = {}, 0
    local function floats(v)
        if type(v) == 'number' then return v + 0.0 end
        if type(v) ~= 'table' then return v end
        local out = {}
        for k, x in pairs(v) do out[k] = floats(x) end
        return out
    end
    local c = { encoded = {} }
    c.encode = function(t)
        n = n + 1
        local key = 'json#' .. n
        store[key] = floats(t)
        c.encoded[#c.encoded + 1] = t
        return key
    end
    c.decode = function(s)
        local t = store[s]
        if t == nil then error('bad json: ' .. tostring(s)) end
        return floats(t)
    end
    return c
end

-- What MySQL hands back for a written state: params in column order, with NULLIF(?, 0) applied to cooldown_until
-- and whole numbers coming back as floats (as some drivers / JSON paths do).
local function rowOf(params)
    return {
        citizenid = params[1], quest_id = params[2], status = params[3], step = params[4] + 0.0,
        progress = params[5], cooldown_until = params[6] ~= 0 and (params[6] + 0.0) or nil,
        updated_at = params[7] + 0.0,
    }
end

local function reload(state, c)
    c = c or codec()
    return S.fromRow(rowOf(S.params(state, c.encode)), c.decode)
end

local function isInt(v, msg) eq('integer', math.type(v), msg) end

local function line()
    return {
        id = 'family_test_1', kind = 'line', title = 'A Roof', region_id = 'heartlands',
        steps = { { on = 'fh:homestead:claimed', text = 'Claim a plot.' },
            { on = 'fh:hunting:pelt_sold', count = 3, text = 'Sell three pelts.' } },
        rewards = { money = 25 },
    }
end

local function repeatable()
    return {
        id = 'job_test', kind = 'job', title = 'Clear the camp', region_id = 'heartlands',
        ['repeat'] = { cooldown_min = 30 },
        steps = { { on = 'fh:zones:camp_cleared', text = 'Clear it.' } },
        rewards = { money = 10 },
    }
end

local function active()
    return {
        citizenid = CID, quest_id = 'family_test_1', status = 'active', step = 2,
        progress = { count = 2, completions = 0 }, updated_at = T0,
    }
end

describe('quests store: UPSERT params', function()
    it('UPSERT has 7 placeholders, cooldown through NULLIF(?, 0)', function()
        local _, n = S.UPSERT:gsub('%?', '')
        eq(7, n)
        assert(S.UPSERT:find('NULLIF(?, 0)', 1, true), 'cooldown_until goes through NULLIF')
        assert(S.SELECT:find('WHERE citizenid = ?', 1, true), 'select is per character')
    end)
    it('params are 7 non-nil entries in column order, no cooldown = 0', function()
        local c = codec()
        local p = S.params(active(), c.encode)
        for i = 1, 7 do assert(p[i] ~= nil, 'param ' .. i .. ' is nil') end
        eq(7, #p)
        eq(CID, p[1]); eq('family_test_1', p[2]); eq('active', p[3]); eq(2, p[4])
        eq('string', type(p[5]))
        eq(0, p[6], 'no cooldown -> 0 (stored NULL by NULLIF)')
        eq(T0, p[7])
    end)
    it('a set cooldown_until is sent as an integer', function()
        local s = active()
        s.status, s.cooldown_until = 'done', T0 + 1800.0
        local p = S.params(s, codec().encode)
        eq(T0 + 1800, p[6]); isInt(p[6])
        for i = 1, 7 do assert(p[i] ~= nil, 'param ' .. i .. ' is nil') end
    end)
    it('missing step / updated_at fall back to 1 / 0, never nil', function()
        local p = S.params({ citizenid = CID, quest_id = 'q', status = 'active' }, codec().encode)
        eq(1, p[4]); eq(0, p[6]); eq(0, p[7])
        eq(7, #p)
    end)
end)

describe('quests store: save/load round trip', function()
    it('an active state survives, floats come back as integers', function()
        local st, err = reload(active())
        assert(st, err)
        same(active(), st)
        isInt(st.step, 'step'); isInt(st.updated_at, 'updated_at')
        isInt(st.progress.count, 'progress.count'); isInt(st.progress.completions, 'progress.completions')
        eq(nil, st.cooldown_until)
    end)
    it('string numbers from the driver are parsed too', function()
        local c = codec()
        local row = rowOf(S.params(active(), c.encode))
        row.step, row.updated_at, row.cooldown_until = '2', tostring(T0), tostring(T0 + 60)
        local st = S.fromRow(row, c.decode)
        eq(2, st.step); eq(T0, st.updated_at); eq(T0 + 60, st.cooldown_until)
        isInt(st.step); isInt(st.cooldown_until)
    end)
    it('reward bookkeeping keys survive (reward_pending, reward_paid, reward_inflight)', function()
        local s = active()
        s.status = 'done'
        s.progress = { count = 0, completions = 1, reward_pending = true, reward_paid = { money = true },
            reward_inflight = { key = 'rep', at = T0 + 5 } }
        local st = reload(s)
        same(s.progress, st.progress)
        isInt(st.progress.reward_inflight.at)
    end)
    it('unknown progress keys are dropped on save and on load', function()
        local s = active()
        s.progress = { count = 1, completions = 0, junk = 'x', nested = { a = 1 }, reward_pending = 'yes',
            reward_paid = { money = true, [1] = true, rep = 'no' }, reward_inflight = { at = 3 } }
        local c = codec()
        S.params(s, c.encode)
        same({ count = 1, completions = 0, reward_paid = { money = true } }, c.encoded[1], 'written progress')
        local st = reload(s)
        same({ count = 1, completions = 0, reward_paid = { money = true } }, st.progress)
    end)
    it('a job snapshot in progress.job is kept', function()
        local s = active()
        s.quest_id = 'job:camp_clear:c1'
        s.progress.job = { job_type = 'camp_clear', key = 'c1', title = 'Clear', region_id = 'heartlands',
            on = 'fh:zones:camp_cleared', cooldown_min = 60, rewards = { money = 12 } }
        local st = reload(s)
        eq('camp_clear', st.progress.job.job_type)
        eq('c1', st.progress.job.key)
        eq('fh:zones:camp_cleared', st.progress.job.on)
        eq(12, st.progress.job.rewards.money) -- may be a float here: jobs.def normalises (quests_jobs_spec)
        eq(60, st.progress.job.cooldown_min)
    end)
    it('a job snapshot without job_type/key strings is dropped', function()
        local s = active()
        s.progress.job = { job_type = 'camp_clear' }
        eq(nil, reload(s).progress.job)
        s.progress.job = { job_type = 3, key = 'c1' }
        eq(nil, reload(s).progress.job)
    end)
    it('done one-time status and a repeatable cooldown_until survive a reload', function()
        local def = line()
        local st = E.start(def, {}, CID, T0)
        st = E.apply(def, st, 'complete', T0 + 10)
        st = E.rewardPaid(st, T0 + 11)
        local back = reload(st)
        eq('done', back.status); eq(nil, back.cooldown_until); eq(1, back.progress.completions)
        local ok, err = E.canStart(def, { [def.id] = back }, T0 + 99999)
        eq(false, ok); eq('fh_quest_done', err)

        local rdef = repeatable()
        local rs = E.start(rdef, {}, CID, T0)
        rs = E.rewardPaid((E.apply(rdef, rs, 'complete', T0 + 10)), T0 + 11)
        eq(T0 + 10 + 1800, rs.cooldown_until)
        local rback = reload(rs)
        eq('done', rback.status); eq(T0 + 1810, rback.cooldown_until); isInt(rback.cooldown_until)
        ok, err = E.canStart(rdef, { [rdef.id] = rback }, T0 + 1809)
        eq(false, ok); eq('fh_quest_cooldown', err)
        eq(true, (E.canStart(rdef, { [rdef.id] = rback }, T0 + 1810)))
    end)
    it('a pending reward survives a reload (start refuses until paid)', function()
        local def = line()
        local st = E.apply(def, E.start(def, {}, CID, T0), 'complete', T0)
        local back = reload(st)
        eq(true, back.progress.reward_pending)
        assert(E.pendingReward(def, back), 'reward still owed after reload')
    end)
end)

describe('quests store: bad rows', function()
    local function good()
        local c = codec()
        return rowOf(S.params(active(), c.encode)), c
    end
    it('non-table row -> fh_bad_row', function()
        local st, err = S.fromRow(nil, codec().decode)
        eq(nil, st); eq('fh_bad_row', err)
    end)
    it('unknown status -> fh_bad_row_status', function()
        local row, c = good()
        row.status = 'paused'
        local st, err = S.fromRow(row, c.decode)
        eq(nil, st); eq('fh_bad_row_status', err)
    end)
    it('empty / missing citizenid -> fh_bad_row_citizenid', function()
        local row, c = good()
        row.citizenid = ''
        local st, err = S.fromRow(row, c.decode)
        eq(nil, st); eq('fh_bad_row_citizenid', err)
        row.citizenid = nil
        eq('fh_bad_row_citizenid', select(2, S.fromRow(row, c.decode)))
    end)
    it('empty / missing quest_id -> fh_bad_row_quest', function()
        local row, c = good()
        row.quest_id = ''
        local st, err = S.fromRow(row, c.decode)
        eq(nil, st); eq('fh_bad_row_quest', err)
        row.quest_id = 42
        eq('fh_bad_row_quest', select(2, S.fromRow(row, c.decode)))
    end)
    it('bad progress JSON keeps the row with empty progress; step < 1 becomes 1', function()
        local row, c = good()
        row.progress, row.step = '{not json', 0
        local st = S.fromRow(row, c.decode)
        same({ count = 0, completions = 0 }, st.progress)
        eq(1, st.step)
        row.progress, row.step = nil, 'abc'
        st = S.fromRow(row, c.decode)
        same({ count = 0, completions = 0 }, st.progress)
        eq(1, st.step)
    end)
end)

T.finish()

-- Run from repo root: `lua spec/quests_rewards_spec.lua` (or via tools/run-specs.py).
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local describe, it, eq, same = T.describe, T.it, T.eq, T.same
local shared = here .. '../server/resources/[fh]/fh_quests/shared/'
package.path = shared .. '?.lua;' .. package.path
local R = dofile(shared .. 'rewards.lua')
local E = require('engine')

local T0 = 1795651200
local CID = 'ABC123'

local function line()
    return {
        id = 'family_test_1', kind = 'line', title = 'A Roof', region_id = 'heartlands',
        steps = { { on = 'fh:homestead:claimed', text = 'Claim a plot.' } },
        rewards = { money = 25, rep = { region_id = 'heartlands', delta = 5 }, items = { { name = 'bread', amount = 2 } } },
    }
end

local function repeatable()
    return {
        id = 'job:camp_clear:t1', kind = 'job', title = 'Clear the camp', region_id = 'heartlands',
        ['repeat'] = { cooldown_min = 30 },
        steps = { { on = 'fh:zones:camp_cleared', text = 'Clear it.' } },
        rewards = { money = 10 },
    }
end

local function done(def)
    local s = E.start(def, {}, CID, T0)
    return (E.apply(def, s, 'complete', T0))
end

-- A fake server: save() records rows; pay() records delivered parts and (money/rep) writes a ledger row, like
-- fh_economy. opts.pay(part) may return { called, ok, err } to override; opts.ledger(part) overrides the lookup.
local function world(opts)
    opts = opts or {}
    local w = { saved = {}, paid = {}, ledger = {}, calls = 0 }
    w.io = {
        now = T0 + 10,
        save = function(s)
            if opts.failSaveAt and #w.saved + 1 == opts.failSaveAt then
                opts.failSaveAt = nil
                return false
            end
            w.saved[#w.saved + 1] = s
            return true
        end,
        pay = function(part)
            w.calls = w.calls + 1
            local o = opts.pay and opts.pay(part)
            if o then return table.unpack(o, 1, 3) end
            w.paid[#w.paid + 1] = part.key
            if part.kind ~= 'item' then w.ledger[part.key] = true end
            return true, true
        end,
        ledger = function(part, inflight)
            assert(inflight and inflight.key == part.key, 'ledger lookup is for the in-flight part')
            if opts.ledger then return opts.ledger(part) end
            return w.ledger[part.key] == true
        end,
    }
    return w
end

local function outcomes(log)
    local t = {}
    for i, l in ipairs(log) do t[i] = l.key .. '=' .. l.outcome end
    return t
end

describe('quests rewards: parts and ledger reason', function()
    it('ledger reason is quest:<id>, on the engine reward effect too', function()
        local def = line()
        eq('quest:family_test_1', R.reason(def))
        local _, fx = E.apply(def, E.start(def, {}, CID, T0), 'complete', T0)
        eq('quest:family_test_1', fx[2].reason)
    end)
    it('parts are money, rep, then each item, in that order', function()
        local p = R.parts(line())
        same({ 'money', 'rep', 'item:1' }, { p[1].key, p[2].key, p[3].key })
        eq('pay', p[1].kind); eq(25, p[1].amount); eq('heartlands', p[1].region_id)
        eq('rep', p[2].kind); eq(5, p[2].delta)
        eq('item', p[3].kind); eq('bread', p[3].name); eq(2, p[3].amount)
        same({}, R.parts({ id = 'x', region_id = 'heartlands', rewards = { money = 0 } }))
    end)
    it('the ledger lookup matches citizenid, kind, reason quest:<id>, amount, region, since the marker', function()
        local def = line()
        local sql, params = R.ledgerQuery(def, R.part(def, 'money'), CID, { key = 'money', at = T0 })
        assert(sql:find('fh_ledger', 1, true))
        same({ CID, 'pay', 'quest:family_test_1', 25, 'heartlands', T0 - R.LEDGER_SLACK_S }, params)
        local _, rp = R.ledgerQuery(def, R.part(def, 'rep'), CID, { key = 'rep', at = T0 })
        same({ CID, 'rep', 'quest:family_test_1', 5, 'heartlands', T0 - R.LEDGER_SLACK_S }, rp)
        eq(nil, R.ledgerQuery(def, R.part(def, 'item:1'), CID, { key = 'item:1', at = T0 }))
    end)
end)

describe('quests rewards: paid exactly once', function()
    it('pays every part once, persisting the in-flight marker before each payer call', function()
        local def, w = line(), world()
        local final, log = R.run(def, done(def), w.io)
        same({ 'money', 'rep', 'item:1' }, w.paid)
        same({ 'money=paid', 'rep=paid', 'item:1=paid' }, outcomes(log))
        eq(6, #w.saved, 'begin + settle per part')
        eq('money', w.saved[1].progress.reward_inflight.key)
        eq(true, w.saved[2].progress.reward_paid.money)
        eq(nil, final.progress.reward_pending); eq(nil, final.progress.reward_paid)
        eq(nil, final.progress.reward_inflight); eq(false, R.pending(final))
    end)
    it('a second run on the paid state pays nothing', function()
        local def, w = line(), world()
        local final = R.run(def, done(def), w.io)
        local again, log = R.run(def, final, w.io)
        eq(3, w.calls); same({}, log); eq(final, again)
    end)
    it('re-fired events after completion never produce a second reward to pay', function()
        local def = line()
        local s = E.start(def, {}, CID, T0)
        local s2, fx = E.onEvent(def, s, 'fh:homestead:claimed', { citizenid = CID }, T0)
        local rewardsSeen = 0
        for _, e in ipairs(fx) do if e.type == 'reward' then rewardsSeen = rewardsSeen + 1 end end
        local w = world()
        local final = R.run(def, s2, w.io)
        for _ = 1, 3 do
            local s3, fx3 = E.onEvent(def, final, 'fh:homestead:claimed', { citizenid = CID }, T0 + 20)
            eq(final, s3); same({}, fx3)
            for _, e in ipairs(fx3) do if e.type == 'reward' then rewardsSeen = rewardsSeen + 1 end end
            R.run(def, s3, w.io)
        end
        eq(1, rewardsSeen); eq(3, w.calls)
    end)
    it('a repeatable pays once per completion', function()
        local def, w = repeatable(), world()
        local first = R.run(def, done(def), w.io)
        local s = E.start(def, { [def.id] = first }, CID, T0 + 30 * 60)
        local second = R.run(def, (E.apply(def, s, 'complete', T0 + 30 * 60)), w.io)
        eq(2, w.calls); eq(2, second.progress.completions); eq(false, R.pending(second))
    end)
end)

describe('quests rewards: no payout without a ledger row', function()
    it('money payer threw and no ledger row: not counted as paid, owed again, paid once on the next run', function()
        local def = line()
        local w = world({ pay = function(p) if p.key == 'money' then return { false, nil, 'boom' } end end })
        local s, log = R.run(def, done(def), w.io)
        same({ 'money=refused' }, outcomes(log))
        same({}, w.paid); eq(true, R.pending(s)); eq(nil, s.progress.reward_paid.money)
        eq(nil, R.inflight(s), 'marker cleared once the ledger said "not paid"')
        local w2 = world()
        local final = R.run(def, s, w2.io)
        same({ 'money', 'rep', 'item:1' }, w2.paid); eq(false, R.pending(final))
    end)
    it('money payer threw but the ledger row exists: counted as paid, never paid twice', function()
        local def = line()
        local w = world({
            pay = function(p) if p.key == 'money' then return { false, nil, 'timeout' } end end,
            ledger = function(p) return p.key == 'money' end,
        })
        local final, log = R.run(def, done(def), w.io)
        same({ 'money=paid', 'rep=paid', 'item:1=paid' }, outcomes(log))
        same({ 'rep', 'item:1' }, w.paid); eq(false, R.pending(final))
    end)
    it('resolveUnknown: money/rep only by ledger; a failed lookup decides nothing', function()
        local def = line()
        eq('paid', R.resolveUnknown(R.part(def, 'money'), true))
        eq('refused', R.resolveUnknown(R.part(def, 'money'), false))
        eq(nil, R.resolveUnknown(R.part(def, 'rep'), nil))
        eq('assumed', R.resolveUnknown(R.part(def, 'item:1'), nil))
        eq('refused', R.resolveUnknown(nil, nil))
    end)
end)

describe('quests rewards: crash recovery from a persisted in-flight marker', function()
    local function crashed(key)
        local def = line()
        return def, assert(R.begin(def, done(def), key, T0 + 5))
    end
    it('ledger has the row: settles as paid without paying again', function()
        local def, s = crashed('money')
        local w = world({ ledger = function(p) return p.key == 'money' end })
        local final, log = R.run(def, s, w.io)
        eq(true, log[1].recovered); eq('money=paid', outcomes(log)[1])
        same({ 'rep', 'item:1' }, w.paid); eq(false, R.pending(final))
    end)
    it('ledger has no row: the part was never paid, pay it now (once)', function()
        local def, s = crashed('money')
        local w = world()
        local final = R.run(def, s, w.io)
        same({ 'money', 'rep', 'item:1' }, w.paid); eq(false, R.pending(final))
    end)
    it('ledger unavailable: keep the marker, pay nothing, try again later', function()
        local def, s = crashed('rep')
        local w = world({ ledger = function() return nil end })
        local same_s, log = R.run(def, s, w.io)
        eq(s, same_s); same({ 'rep=ledger_unavailable' }, outcomes(log)); eq(0, w.calls); same({}, w.saved)
    end)
    it('an item marker is assumed delivered (no ledger for items): never added twice', function()
        local def = line()
        local w = world({ pay = function(p) if p.kind == 'item' then return { true, false, 'fh_not_registrable' } end end })
        local s = R.run(def, done(def), w.io) -- money + rep paid, item refused
        s = assert(R.begin(def, s, 'item:1', T0 + 6))
        local w2 = world()
        local final = R.run(def, s, w2.io)
        eq(0, w2.calls); eq(false, R.pending(final))
    end)
    it('the settle write failed after paying: the next run sees the marker and the ledger row, no second pay', function()
        local def = line()
        local w = world({ failSaveAt = 2 })
        local s, log = R.run(def, done(def), w.io)
        same({ 'money=paid', 'money=save_failed' }, outcomes(log))
        eq('money', R.inflight(s).key, 'returned state is the last persisted one (marker set)')
        local w2 = world({ ledger = function(p) return p.key == 'money' end })
        R.run(def, s, w2.io)
        same({ 'money' }, w.paid); same({ 'rep', 'item:1' }, w2.paid)
    end)
    it('the marker write failed: nothing is paid', function()
        local def = line()
        local w = world({ failSaveAt = 1 })
        local input = done(def)
        local s, log = R.run(def, input, w.io)
        eq(input, s); eq(0, w.calls); same({ 'money=save_failed' }, outcomes(log))
    end)
end)

describe('quests rewards: refusals keep the reward owed', function()
    it('fh_economy refuses money: nothing paid, reward still pending, start refused until paid', function()
        local def = line()
        local w = world({ pay = function(p) if p.key == 'money' then return { true, false, 'no_player' } end end })
        local s, log = R.run(def, done(def), w.io)
        eq('no_player', log[1].err); same({}, w.paid); eq(true, R.pending(s))
        eq(false, (E.canStart(def, { [def.id] = s }, T0 + 99)))
        local _, err = E.canStart(def, { [def.id] = s }, T0 + 99)
        eq('fh_reward_pending', err)
    end)
    it('an item refusal after money and rep: the retry delivers only the item', function()
        local def = line()
        local w = world({ pay = function(p) if p.kind == 'item' then return { true, false, 'fh_inventory_full' } end end })
        local s = R.run(def, done(def), w.io)
        same({ 'money', 'rep' }, w.paid); eq(true, R.pending(s))
        same({ money = true, rep = true }, s.progress.reward_paid)
        local w2 = world()
        local final = R.run(def, s, w2.io)
        same({ 'item:1' }, w2.paid); eq(false, R.pending(final))
    end)
    it('begin/settle guard rails', function()
        local def = line()
        local s = done(def)
        local _, e1 = R.begin(def, R.finish(s, T0), 'money', T0); eq('fh_no_reward', e1)
        local f = assert(R.begin(def, s, 'money', T0))
        local _, e2 = R.begin(def, f, 'rep', T0); eq('fh_reward_inflight', e2)
        local _, e3 = R.begin(def, s, 'item:9', T0); eq('fh_reward_not_owed', e3)
        local _, e4 = R.settle(def, f, 'rep', 'paid', T0); eq('fh_reward_not_inflight', e4)
        local _, e5 = R.settle(def, f, 'money', 'maybe', T0); eq('fh_bad_outcome', e5)
        eq(true, s.progress.reward_pending, 'inputs not mutated'); eq(nil, s.progress.reward_inflight)
    end)
end)

describe('quests rewards: done status and cooldown_until', function()
    it('one-time quest: done, no cooldown, can never start again', function()
        local def = line()
        local final = R.run(def, done(def), world().io)
        eq('done', final.status); eq(nil, final.cooldown_until); eq(1, final.progress.completions)
        local ok, err = E.canStart(def, { [def.id] = final }, T0 + 10000000)
        eq(false, ok); eq('fh_quest_done', err)
    end)
    it('repeatable: done with cooldown_until = completion + cooldown_min * 60, restartable after it', function()
        local def = repeatable()
        local final = R.run(def, done(def), world().io)
        eq('done', final.status); eq(T0 + 30 * 60, final.cooldown_until)
        local ok, err = E.canStart(def, { [def.id] = final }, T0 + 60)
        eq(false, ok); eq('fh_quest_cooldown', err)
        assert(E.canStart(def, { [def.id] = final }, T0 + 30 * 60))
    end)
end)

describe('quests rewards: scaleByTier (quests-03 T2)', function()
    it('scales money and rep by default tier multipliers (t1 x1.0, t2 x1.5, t3 x2.25) and leaves items unchanged', function()
        local base = {
            money = 20,
            rep = { region_id = 'heartlands', delta = 4 },
            items = { { name = 'bread', amount = 2 } },
        }
        local t1 = R.scaleByTier(base, 1)
        eq(20, t1.money); eq('integer', math.type(t1.money))
        eq(4, t1.rep.delta); eq('integer', math.type(t1.rep.delta)); eq('heartlands', t1.rep.region_id)
        same({ { name = 'bread', amount = 2 } }, t1.items)

        local t2 = R.scaleByTier(base, 2)
        eq(30, t2.money); eq('integer', math.type(t2.money))
        eq(6, t2.rep.delta); eq('integer', math.type(t2.rep.delta)); eq('heartlands', t2.rep.region_id)
        same({ { name = 'bread', amount = 2 } }, t2.items)

        local t3 = R.scaleByTier(base, 3)
        eq(45, t3.money); eq('integer', math.type(t3.money))
        eq(9, t3.rep.delta); eq('integer', math.type(t3.rep.delta)); eq('heartlands', t3.rep.region_id)
        same({ { name = 'bread', amount = 2 } }, t3.items)

        -- Input table and nested tables are never mutated.
        eq(20, base.money); eq(4, base.rep.delta); eq(2, base.items[1].amount)
        assert(t2 ~= base and t2.rep ~= base.rep and t2.items ~= base.items and t2.items[1] ~= base.items[1])
    end)

    it('rounds money and rep half-up to whole integers (fh_quests engine integer contract)', function()
        -- 25 * 1.5 = 37.5 -> 38; 3 * 1.5 = 4.5 -> 5
        local r2 = R.scaleByTier({ money = 25, rep = { region_id = 'heartlands', delta = 3 } }, 2)
        eq(38, r2.money); eq('integer', math.type(r2.money))
        eq(5, r2.rep.delta); eq('integer', math.type(r2.rep.delta))

        -- 10 * 2.25 = 22.5 -> 23; 5 * 2.25 = 11.25 -> 11
        local r3 = R.scaleByTier({ money = 10, rep = { region_id = 'heartlands', delta = 5 } }, 3)
        eq(23, r3.money); eq('integer', math.type(r3.money))
        eq(11, r3.rep.delta); eq('integer', math.type(r3.rep.delta))
    end)

    it('falls back to x1.0 for unknown, nil, fractional, or invalid tiers', function()
        local base = { money = 20, rep = { region_id = 'heartlands', delta = 4 } }
        local outNil = R.scaleByTier(base, nil)
        eq(20, outNil.money, 'money for tier nil')
        eq(4, outNil.rep.delta, 'rep for tier nil')
        for _, badTier in ipairs({ 0, -1, 4, 99, 2.5, '2', 0 / 0, math.huge }) do
            local out = R.scaleByTier(base, badTier)
            eq(20, out.money, 'money for tier ' .. tostring(badTier))
            eq(4, out.rep.delta, 'rep for tier ' .. tostring(badTier))
        end
    end)

    it('reads FhQuestsConfig.tierRewardMultipliers when present and accepts an explicit multipliers override', function()
        local base = { money = 10, rep = { region_id = 'heartlands', delta = 2 } }
        local prev = FhQuestsConfig
        FhQuestsConfig = { tierRewardMultipliers = { [1] = 1.0, [2] = 2.0, [3] = 3.0 } }
        local ok, err = pcall(function()
            local r2 = R.scaleByTier(base, 2)
            eq(20, r2.money); eq(4, r2.rep.delta)
            -- Explicit override wins over config; negative config multiplier falls back to 1.0.
            local rOv = R.scaleByTier(base, 2, { [2] = 1.5 })
            eq(15, rOv.money); eq(3, rOv.rep.delta)
            local rNeg = R.scaleByTier(base, 2, { [2] = -2.0 })
            eq(10, rNeg.money); eq(2, rNeg.rep.delta)
        end)
        FhQuestsConfig = prev
        assert(ok, err)
    end)

    it('handles bad inputs safely and never produces negative money or rep', function()
        eq(nil, R.scaleByTier(nil, 2))
        eq(nil, R.scaleByTier('not a table', 2))
        same({}, R.scaleByTier({}, 2))

        local neg = R.scaleByTier({ money = -10, rep = { region_id = 'heartlands', delta = -5 } }, 2)
        eq(0, neg.money); eq('integer', math.type(neg.money))
        eq(0, neg.rep.delta); eq('integer', math.type(neg.rep.delta))

        local zero = R.scaleByTier({ money = 0 }, 3)
        eq(0, zero.money); eq('integer', math.type(zero.money))

        local nan = R.scaleByTier({ money = 0 / 0, rep = { region_id = 'heartlands', delta = math.huge } }, 2)
        eq(0, nan.money); eq(0, nan.rep.delta)
    end)
end)

T.finish()

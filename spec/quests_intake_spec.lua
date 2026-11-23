-- Run from repo root: `lua spec/quests_intake_spec.lua` (or via tools/run-specs.py).
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local describe, it, eq, same = T.describe, T.it, T.eq, T.same
local shared = here .. '../server/resources/[fh]/fh_quests/shared/'
package.path = shared .. '?.lua;' .. package.path
local I = dofile(shared .. 'intake.lua')
local E = require('engine')

local T0 = 1795651200
local CID, OTHER = 'ABC123', 'XYZ999'

local function line()
    return {
        id = 'family_test_1', kind = 'line', title = 'A Roof', giver = 'npc_hale', region_id = 'heartlands',
        steps = {
            { on = 'fh:homestead:claimed', text = 'Claim a plot.' },
            { talk = { npc = 'npc_hale', lines = { 'Well done.', 'Take this.' } }, text = 'Report to Hale.' },
        },
        rewards = { money = 25 },
    }
end

local function job()
    return {
        id = 'job:camp_clear:t1', kind = 'job', title = 'Clear the camp', region_id = 'heartlands',
        job_type = 'camp_clear', ['repeat'] = { cooldown_min = 30 },
        steps = { { on = 'fh:zones:camp_cleared', text = 'Clear it.' } },
        rewards = { money = 10 },
    }
end

local function started(def, cid)
    local s = E.start(def, {}, cid or CID, T0)
    assert(s)
    return s
end

local function rewards(changes)
    local n = 0
    for _, c in ipairs(changes) do
        for _, e in ipairs(c.effects) do if e.type == 'reward' then n = n + 1 end end
    end
    return n
end

describe('quests intake: whitelist', function()
    it('accepts the contract events', function()
        for _, n in ipairs({ 'fh:zones:camp_cleared', 'fh:hunting:pelt_skinned', 'fh:hunting:pelt_sold',
            'fh:hunting:chain_complete', 'fh:homestead:claimed', 'fh:economy:paid', 'fh:economy:rep_changed',
            'fh:death:dropped', 'fh:death:recovered', 'fh:death:expired' }) do
            eq(true, I.accepts(n), n)
        end
    end)
    it('ignores unknown events', function()
        eq(false, I.accepts('fh:inventory:moved'))
        eq(false, I.accepts('playerDropped'))
        eq(false, I.accepts('fh:quests:completed'))
        eq(false, I.accepts(nil))
        eq(false, I.accepts(42))
    end)
    it('fh:quests:talked is not intake (the talk export feeds it itself, so a re-fire cannot advance twice)', function()
        eq(false, I.accepts('fh:quests:talked'))
        eq(false, I.accepts('fh:quests:talked', { ['fh:quests:talked'] = true }))
    end)
    it('a registered job type adds its own events', function()
        eq(false, I.accepts('fh:roads:delivered'))
        eq(true, I.accepts('fh:roads:delivered', { ['fh:roads:delivered'] = true }))
    end)
    it('an unknown event advances nothing even if fed', function()
        local def = line()
        local changes = I.feed({ [def.id] = def }, { [def.id] = started(def) }, 'fh:inventory:moved',
            { citizenid = CID }, T0)
        same({}, changes)
    end)
end)

describe('quests intake: who is credited (src -> citizenid)', function()
    it('srcToResolve: only when there is no citizenid, and only a positive whole src', function()
        eq(7, I.srcToResolve({ src = 7 }))
        eq(7, I.srcToResolve({ src = 7.0 }))
        eq(nil, I.srcToResolve({ src = 7, citizenid = CID }))
        eq(nil, I.srcToResolve({ src = 0 }))
        eq(nil, I.srcToResolve({ src = -1 }))
        eq(nil, I.srcToResolve({ src = 1.5 }))
        eq(nil, I.srcToResolve({ src = '7' }))
        eq(nil, I.srcToResolve(nil))
    end)
    it('targets: the citizenid the server resolved from src', function()
        same({ CID }, I.targets({ src = 7 }, CID))
    end)
    it('targets: a payload citizenid wins over the resolved one', function()
        same({ CID }, I.targets({ src = 7, citizenid = CID }, OTHER))
    end)
    it('targets: participants are added once, in order, invalid ones dropped', function()
        same({ CID, OTHER }, I.targets({ citizenid = CID, participants = { OTHER, CID, '', 5 } }))
        same({ OTHER }, I.targets({ camp_id = 'c', participants = { OTHER } }))
    end)
    it('targets: nobody when nothing names a player (src unresolved, no citizenid)', function()
        same({}, I.targets({ src = 7 }, nil))
        same({}, I.targets({ camp_id = 'c' }))
        same({}, I.targets('x'))
    end)
    it('payloadFor: copies in the resolved citizenid without mutating the event payload', function()
        local p = { src = 7, plot_id = 'p1' }
        local q = I.payloadFor(p, CID)
        eq(CID, q.citizenid); eq('p1', q.plot_id); eq(nil, p.citizenid)
        eq(p, I.payloadFor(p, nil), 'unresolved: unchanged')
        local r = { citizenid = OTHER }
        eq(r, I.payloadFor(r, CID), 'own citizenid kept')
    end)
    it('a src-only event advances the resolved player (end to end through feed)', function()
        local def = line()
        local payload = { src = 7, plot_id = 'p1', region_id = 'heartlands' }
        local cid = 'ABC123' -- what the server resolved src 7 to
        local changes = I.feed({ [def.id] = def }, { [def.id] = started(def) }, 'fh:homestead:claimed',
            I.payloadFor(payload, cid), T0)
        eq(1, #changes); eq(2, changes[1].after.step)
        -- without resolution the engine sees no citizenid and credits nobody
        changes = I.feed({ [def.id] = def }, { [def.id] = started(def) }, 'fh:homestead:claimed', payload, T0)
        same({}, changes)
    end)
end)

describe('quests intake: feed', function()
    it('wrong citizen never advances', function()
        local def = line()
        local changes = I.feed({ [def.id] = def }, { [def.id] = started(def) }, 'fh:homestead:claimed',
            { citizenid = OTHER }, T0)
        same({}, changes)
    end)
    it('only active quests with a def are fed; changes are in quest_id order', function()
        local a, b = line(), line()
        b.id = 'aaa_first'
        local gone = started(line()); gone.quest_id = 'no_def'
        local states = { [a.id] = started(a), [b.id] = started(b), no_def = gone }
        states[b.id].quest_id = b.id
        local changes = I.feed({ [a.id] = a, [b.id] = b }, states, 'fh:homestead:claimed', { citizenid = CID }, T0)
        eq(2, #changes); eq('aaa_first', changes[1].quest_id); eq('family_test_1', changes[2].quest_id)
        eq(states[a.id], changes[2].before, 'before is the input state')
        eq(1, states[a.id].step, 'input not mutated')
    end)
    it('reward exactly once: the completing event re-fired against the new state pays nothing', function()
        local def = job(); def.job_type = nil
        local defs, st = { [def.id] = def }, started(def)
        local p = { camp_id = 'c1', participants = { CID } }
        local c1 = I.feed(defs, { [def.id] = st }, 'fh:zones:camp_cleared', p, T0)
        eq(1, rewards(c1)); eq('done', c1[1].after.status)
        local c2 = I.feed(defs, { [def.id] = c1[1].after }, 'fh:zones:camp_cleared', p, T0 + 1)
        same({}, c2); eq(0, rewards(c2))
    end)
end)

describe('quests intake: job type hooks', function()
    it('a hook verdict goes through engine.apply: complete pays once, a second complete is a no-op', function()
        local def = job()
        local seen = nil
        local hook = function(name, payload, state) seen = { name, payload.citizenid, state.quest_id }; return 'complete' end
        local hookFor = function() return hook end
        local c1 = I.feed({ [def.id] = def }, { [def.id] = started(def) }, 'fh:roads:delivered', { citizenid = CID }, T0, hookFor)
        eq(1, #c1); eq(1, rewards(c1)); same({ 'fh:roads:delivered', CID, def.id }, seen)
        local c2 = I.feed({ [def.id] = def }, { [def.id] = c1[1].after }, 'fh:roads:delivered', { citizenid = CID }, T0, hookFor)
        same({}, c2)
    end)
    it('the hook gets a copy: mutating it cannot change the stored state', function()
        local def = job()
        local st = started(def)
        I.feed({ [def.id] = def }, { [def.id] = st }, 'fh:roads:delivered', { citizenid = CID }, T0,
            function() return function(_, _, s) s.status = 'done'; return nil end end)
        eq('active', st.status)
    end)
    it('the hook is not asked about other players, quest payout echoes, or nil verdicts', function()
        local def, calls = job(), 0
        local hookFor = function() return function() calls = calls + 1; return nil end end
        local states = { [def.id] = started(def) }
        same({}, (I.feed({ [def.id] = def }, states, 'fh:roads:delivered', { citizenid = OTHER }, T0, hookFor)))
        eq(0, calls)
        same({}, (I.feed({ [def.id] = def }, states, 'fh:economy:paid', { citizenid = CID, reason = 'quest:x' }, T0, hookFor)))
        eq(0, calls)
        same({}, (I.feed({ [def.id] = def }, states, 'fh:economy:paid', { citizenid = CID, reason = 'pelt:x' }, T0, hookFor)))
        eq(1, calls, 'asked, answered nil: nothing changes')
    end)
    it('false = job type not registered: the job pauses (not even the engine step matches)', function()
        local def = job()
        local changes = I.feed({ [def.id] = def }, { [def.id] = started(def) }, 'fh:zones:camp_cleared',
            { citizenid = CID }, T0, function() return false end)
        same({}, changes)
    end)
    it('a hook that throws is reported and changes nothing', function()
        local def = job()
        local changes, errors = I.feed({ [def.id] = def }, { [def.id] = started(def) }, 'fh:roads:delivered',
            { citizenid = CID }, T0, function() return function() error('boom') end end)
        same({}, changes); eq(1, #errors); eq(def.id, errors[1].quest_id)
        assert(errors[1].err:find('boom', 1, true))
    end)
end)

describe('quests intake: emitted events', function()
    it('maps effects to fh:quests:* with exactly { citizenid, quest_id, kind, step }; reward is not an event', function()
        local def = job(); def.job_type = nil
        local st, fx = E.start(def, {}, CID, T0)
        local evs, reward = I.emits(fx)
        same({ { name = 'fh:quests:started', payload = { citizenid = CID, quest_id = def.id, kind = 'job', step = 1 } } }, evs)
        eq(false, reward)
        local _, fx2 = E.apply(def, st, 'complete', T0)
        evs, reward = I.emits(fx2)
        eq(1, #evs); eq('fh:quests:completed', evs[1].name); eq(true, reward)
        local _, fx3 = E.abandon(def, st, T0)
        eq('fh:quests:abandoned', I.emits(fx3)[1].name)
        local _, fx4 = E.fail(def, st, T0, 'timeout')
        evs = I.emits(fx4)
        eq('fh:quests:failed', evs[1].name); eq(nil, evs[1].payload.reason)
    end)
    it('a counted step event emits fh:quests:step', function()
        local def = line()
        local _, fx = E.onEvent(def, started(def), 'fh:homestead:claimed', { citizenid = CID }, T0)
        local evs = I.emits(fx)
        eq('fh:quests:step', evs[1].name); eq(2, evs[1].payload.step)
    end)
end)

describe('quests intake: talk dialogue and giver offers', function()
    it('dialogue: the talk step lines once that step advanced', function()
        local def = line()
        local s1 = E.onEvent(def, started(def), 'fh:homestead:claimed', { citizenid = CID }, T0)
        local changes = I.feed({ [def.id] = def }, { [def.id] = s1 }, 'fh:quests:talked',
            { citizenid = CID, npc_id = 'npc_hale' }, T0)
        eq(1, #changes); eq('done', changes[1].after.status)
        same({ quest_id = def.id, step = 2, lines = { 'Well done.', 'Take this.' } },
            I.dialogue(def, changes[1].before, changes[1].after))
    end)
    it('dialogue: nil for a non-talk step', function()
        local def = line()
        local s0 = started(def)
        local s1 = E.onEvent(def, s0, 'fh:homestead:claimed', { citizenid = CID }, T0)
        eq(nil, I.dialogue(def, s0, s1))
    end)
    it('talking to the wrong npc changes nothing', function()
        local def = line()
        local s1 = E.onEvent(def, started(def), 'fh:homestead:claimed', { citizenid = CID }, T0)
        same({}, (I.feed({ [def.id] = def }, { [def.id] = s1 }, 'fh:quests:talked', { citizenid = CID, npc_id = 'npc_x' }, T0)))
    end)
    it('offers: quests this npc gives that the player can start now', function()
        local a, b, c = line(), line(), line()
        b.id = 'family_test_2'; b.prereq = { a.id }
        c.id = 'other_giver'; c.giver = 'npc_x'
        local defs = { [a.id] = a, [b.id] = b, [c.id] = c }
        same({ a.id }, I.offers(defs, {}, 'npc_hale', T0))
        local done = E.apply(a, started(a), 'complete', T0)
        done = E.rewardPaid(done, T0)
        same({ b.id }, I.offers(defs, { [a.id] = done }, 'npc_hale', T0))
        same({}, I.offers(defs, {}, 'npc_nobody', T0))
    end)
end)

T.finish()

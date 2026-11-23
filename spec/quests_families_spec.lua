-- Run from repo root: `lua spec/quests_families_spec.lua` (or via tools/run-specs.py).
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local describe, it, eq = T.describe, T.it, T.eq
local base = here .. '../server/resources/[fh]/fh_quests/'
package.path = base .. 'shared/?.lua;' .. package.path
local E = dofile(base .. 'shared/engine.lua')
local G = dofile(base .. 'shared/givers.lua')
local regions = require('regions')

T.ok = function(c, msg) if not c then error(msg or 'assertion failed', 2) end end

local T0 = 1795651200
local CID, OTHER = 'ABC123', 'XYZ999'
local NAMES = { 'hale', 'marrow', 'whitlock' }

local defs = {}
for _, n in ipairs(NAMES) do defs[n] = dofile(base .. 'data/families/' .. n .. '.lua') end

-- Synthetic payload that satisfies each step's event (keyed by family, then step index).
local function payloadFor(def, step, cid)
    if step.talk then return E.TALK_EVENT, { citizenid = cid, npc_id = step.talk.npc } end
    local p = { citizenid = cid }
    if step.on == 'fh:homestead:claimed' then p.plot_id = 'p1'; p.region_id = 'heartlands'
    elseif step.on == 'fh:economy:paid' then p.amount = 20; p.reason = 'sale'
    elseif step.on == 'fh:hunting:pelt_sold' then p.quality = 3; p.price = 12; p.region_id = 'heartlands'
    elseif step.on == 'fh:hunting:chain_complete' then p.chain_id = 'legendary_bear'
    elseif step.on == 'fh:zones:camp_cleared' then p.camp_id = 'c1'; p.region_id = 'heartlands'; p.participants = { cid }; p.citizenid = nil
    end
    return step.on, p
end

describe('family definitions', function()
    for _, n in ipairs(NAMES) do
        local def = defs[n]
        it(n .. ' passes engine validate', function()
            local ok, err = E.validate(def, { regions = regions.regions })
            eq(true, ok, tostring(err))
            eq('line', def.kind)
            eq('heartlands', def.region_id)
        end)
        it(n .. ' has 3-5 contiguous steps', function()
            T.ok(#def.steps >= 3 and #def.steps <= 5, 'step count ' .. #def.steps)
            for i = 1, #def.steps do T.ok(def.steps[i] ~= nil, 'gap at ' .. i) end
            local n2 = 0
            for _ in pairs(def.steps) do n2 = n2 + 1 end
            eq(#def.steps, n2)
        end)
        it(n .. ' uses only whitelisted events', function()
            for i, s in ipairs(def.steps) do
                local ev = s.talk and E.TALK_EVENT or s.on
                T.ok(E.isIntake(ev), ('step %d event %s'):format(i, tostring(ev)))
            end
        end)
        it(n .. ' has a money/rep reward only, no items', function()
            T.ok(def.rewards.money and def.rewards.rep, 'money+rep')
            eq(nil, def.rewards.items)
        end)
        it(n .. ' is one-time, resolves its giver and prereqs', function()
            eq(nil, def['repeat'])
            T.ok(G[def.giver] ~= nil, 'giver ' .. tostring(def.giver))
            eq(def.id, G[def.giver].quest)
            for _, pid in ipairs(def.prereq or {}) do
                local found = false
                for _, o in pairs(defs) do if o.id == pid then found = true end end
                T.ok(found, 'prereq ' .. pid)
            end
        end)
    end
    it('ids and givers are distinct, families independent', function()
        local ids, givers = {}, {}
        for _, n in ipairs(NAMES) do
            T.ok(not ids[defs[n].id] and not givers[defs[n].giver], 'duplicate')
            ids[defs[n].id], givers[defs[n].giver] = true, true
            eq(nil, defs[n].prereq)
        end
    end)
    it('one family requires the legendary bear chain_complete', function()
        local found = false
        for _, s in ipairs(defs.whitlock.steps) do
            if s.on == 'fh:hunting:chain_complete' and s.where.chain_id == 'legendary_bear' then found = true end
        end
        T.ok(found, 'chain_complete step')
    end)
end)

describe('family walk-through', function()
    for _, n in ipairs(NAMES) do
        local def = defs[n]
        it(n .. ' walks to done with exactly one reward', function()
            local st = E.start(def, {}, CID, T0)
            T.ok(st ~= nil, 'start')
            local rewards = 0
            for i, step in ipairs(def.steps) do
                eq(i, st.step)
                local ev, p = payloadFor(def, step, CID)
                for _ = 1, step.count or 1 do
                    local fx
                    st, fx = E.onEvent(def, st, ev, p, T0)
                    for _, e in ipairs(fx) do if e.type == 'reward' then rewards = rewards + 1 end end
                end
            end
            eq('done', st.status)
            eq(1, rewards)
            -- a re-fired last event cannot pay again
            local last = def.steps[#def.steps]
            local ev, p = payloadFor(def, last, CID)
            local _, fx = E.onEvent(def, st, ev, p, T0)
            eq(0, #fx)
        end)
        it(n .. ' ignores events for a different citizen and out-of-order events', function()
            local st = E.start(def, {}, CID, T0)
            local ev, p = payloadFor(def, def.steps[1], OTHER)
            local after, fx = E.onEvent(def, st, ev, p, T0)
            eq(1, after.step)
            eq(0, #fx)
            -- a later step's event does not skip ahead
            if #def.steps >= 2 then
                local ev2, p2 = payloadFor(def, def.steps[2], CID)
                if ev2 ~= def.steps[1].on and not def.steps[1].talk then
                    local a2 = E.onEvent(def, st, ev2, p2, T0)
                    eq(1, a2.step)
                end
            end
        end)
    end
    it('a reward-origin payment (reason quest:*) never advances the hale paid step', function()
        local def = defs.hale
        local st = E.start(def, {}, CID, T0)
        st = E.onEvent(def, st, 'fh:homestead:claimed', { citizenid = CID, plot_id = 'p1', region_id = 'heartlands' }, T0)
        eq(2, st.step)
        local after = E.onEvent(def, st, 'fh:economy:paid', { citizenid = CID, amount = 99, reason = 'quest:family_hale' }, T0)
        eq(2, after.step)
    end)
    it('the bear step ignores another chain id', function()
        local def = defs.whitlock
        local st = E.start(def, {}, CID, T0)
        st = E.onEvent(def, st, 'fh:hunting:pelt_sold', { citizenid = CID, quality = 3 }, T0)
        eq(2, st.step)
        local a = E.onEvent(def, st, 'fh:hunting:chain_complete', { citizenid = CID, chain_id = 'other' }, T0)
        eq(2, a.step)
        a = E.onEvent(def, st, 'fh:hunting:chain_complete', { citizenid = CID, chain_id = 'legendary_bear' }, T0)
        eq(3, a.step)
    end)
end)

describe('giver proximity', function()
    local g = G.npc_hale
    local c = g.coords
    it('within reach passes, beyond fails', function()
        eq(true, G.within(g, { x = c.x + 3, y = c.y, z = c.z }))
        eq(true, G.within(g, { x = c.x, y = c.y, z = c.z }))
        eq(false, G.within(g, { x = c.x + 6, y = c.y, z = c.z }))
        eq(false, G.within(g, { x = c.x, y = c.y, z = c.z + 5.5 }))
        eq(false, G.within(g, { x = c.x + 500, y = c.y + 500, z = c.z }))
    end)
    it('uses 3D distance and a custom radius', function()
        eq(false, G.within(g, { x = c.x + 3.6, y = c.y + 3.6, z = c.z })) -- ~5.09 m
        eq(true, G.within(g, { x = c.x + 3.6, y = c.y + 3.6, z = c.z }, 6.0))
    end)
    it('bad input is out of reach', function()
        eq(false, G.within(g, nil))
        eq(false, G.within(g, { x = 0 / 0, y = c.y, z = c.z }))
        eq(false, G.within(g, { x = 'a', y = c.y, z = c.z }))
        eq(false, G.within(nil, { x = 0, y = 0, z = 0 }))
    end)
    it('get/byQuest resolve only real givers', function()
        eq(g, G.get('npc_hale'))
        eq(nil, G.get('within'))
        eq(nil, G.get('REACH'))
        eq(nil, G.get(42))
        eq(g, G.byQuest('family_hale'))
        eq(nil, G.byQuest('family_nope'))
    end)
end)

T.finish()

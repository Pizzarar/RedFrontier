-- Run from repo root: `lua spec/crafting_flow_spec.lua` (or via tools/run-specs.py).
-- C2 craft transaction: station check -> canCraft -> remove inputs -> add outputs, all-or-nothing with rollback.
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local describe, it, eq, same = T.describe, T.it, T.eq, T.same
local base = here .. '../server/resources/[fh]/fh_crafting/'
local R = dofile(base .. 'shared/craft_rules.lua')
local F = dofile(base .. 'shared/craft_flow.lua')

local recipe = { id = 'ammo', station_type = 'reload',
    inputs = { { item = 'powder', amount = 1 }, { item = 'lead', amount = 2 }, { item = 'casings', amount = 2 } },
    outputs = { { item = 'ammo_box', amount = 1 }, { item = 'scrap', amount = 1 } } }

-- Fake carried inventory. opts: near (bool), nearReason, failTake = { [item] = reason }, failGive = { [item] = reason },
-- failTakeAfter = n (the n+1-th take fails), throwGive = item.
local function fakeInv(start, opts)
    opts = opts or {}
    local inv, calls = {}, {}
    for k, v in pairs(start) do inv[k] = v end
    local takes = 0
    local deps = {
        canCraft = R.canCraft,
        near = function(src, t)
            calls[#calls + 1] = 'near:' .. t
            if opts.near == false then return false, opts.nearReason end
            return true
        end,
        count = function(src, item) return inv[item] or 0 end,
        take = function(src, item, n)
            calls[#calls + 1] = 'take:' .. item .. ':' .. n
            takes = takes + 1
            if opts.failTake and opts.failTake[item] then return false, opts.failTake[item] end
            if opts.failTakeAfter and takes > opts.failTakeAfter then return false, 'not_enough' end
            if (inv[item] or 0) < n then return false, 'not_enough' end
            inv[item] = inv[item] - n
            if inv[item] == 0 then inv[item] = nil end
            return true
        end,
        give = function(src, item, n)
            calls[#calls + 1] = 'give:' .. item .. ':' .. n
            if opts.throwGive == item then error('boom') end
            if opts.failGive and opts.failGive[item] then return false, opts.failGive[item] end
            inv[item] = (inv[item] or 0) + n
            return true
        end,
    }
    return deps, inv, calls
end

local full = { powder = 1, lead = 2, casings = 3 }

describe('craft flow: success', function()
    it('removes every input and adds every output', function()
        local deps, inv = fakeInv(full)
        local ok, reason, info = F.craft(1, recipe, deps)
        eq(true, ok); eq(nil, reason)
        same({ casings = 1, ammo_box = 1, scrap = 1 }, inv)
        eq('ammo', info.recipe)
    end)
    it('order: station, then removes, then adds', function()
        local deps, _, calls = fakeInv(full)
        F.craft(1, recipe, deps)
        same({ 'near:reload', 'take:powder:1', 'take:lead:2', 'take:casings:2', 'give:ammo_box:1', 'give:scrap:1' }, calls)
    end)
end)

describe('craft flow: refusals before any change', function()
    it('unknown recipe', function()
        local deps, inv, calls = fakeInv(full)
        local ok, reason = F.craft(1, nil, deps)
        eq(false, ok); eq('unknown_recipe', reason); eq(0, #calls); same(full, inv)
    end)
    it('not near the station: no_station, nothing touched', function()
        local deps, inv, calls = fakeInv(full, { near = false })
        local ok, reason = F.craft(1, recipe, deps)
        eq(false, ok); eq('no_station', reason)
        same({ 'near:reload' }, calls); same(full, inv)
    end)
    it('passes the station reason through', function()
        local deps = fakeInv(full, { near = false, nearReason = 'bad_type' })
        local _, reason = F.craft(1, recipe, deps)
        eq('bad_type', reason)
    end)
    it('missing input: missing_inputs with need/have, nothing touched', function()
        local deps, inv, calls = fakeInv({ powder = 1, lead = 1, casings = 2 })
        local ok, reason, info = F.craft(1, recipe, deps)
        eq(false, ok); eq('missing_inputs', reason)
        same({ { item = 'lead', need = 2, have = 1 } }, info.missing)
        same({ 'near:reload' }, calls); same({ powder = 1, lead = 1, casings = 2 }, inv)
    end)
    it('item listed on two input lines needs the sum', function()
        local dup = { id = 'd', station_type = 'reload', inputs = { { item = 'lead', amount = 2 }, { item = 'lead', amount = 2 } },
            outputs = { { item = 'x', amount = 1 } } }
        local deps, inv = fakeInv({ lead = 3 })
        local ok, reason, info = F.craft(1, dup, deps)
        eq(false, ok); eq('missing_inputs', reason)
        same({ { item = 'lead', need = 4, have = 3 } }, info.missing)
        same({ lead = 3 }, inv)
    end)
end)

describe('craft flow: rollback', function()
    it('remove fails midway: earlier removes are given back, no output added', function()
        local deps, inv, calls = fakeInv(full, { failTake = { casings = 'no_remove' } })
        local ok, reason, info = F.craft(1, recipe, deps)
        eq(false, ok); eq('no_remove', reason)
        eq(3, info.index); eq(0, #info.rollbackFailed)
        same(full, inv)
        same({ 'near:reload', 'take:powder:1', 'take:lead:2', 'take:casings:2', 'give:lead:2', 'give:powder:1' }, calls)
    end)
    it('first remove fails: nothing to undo', function()
        local deps, inv, calls = fakeInv(full, { failTake = { powder = 'no_remove' } })
        local ok, reason = F.craft(1, recipe, deps)
        eq(false, ok); eq('no_remove', reason)
        same(full, inv); same({ 'near:reload', 'take:powder:1' }, calls)
    end)
    it('add fails: added outputs are taken back, then every input is given back', function()
        local deps, inv, calls = fakeInv(full, { failGive = { scrap = 'no_room' } })
        local ok, reason, info = F.craft(1, recipe, deps)
        eq(false, ok); eq('no_room', reason)
        eq(5, info.index); eq(0, #info.rollbackFailed)
        same(full, inv)
        same({ 'near:reload', 'take:powder:1', 'take:lead:2', 'take:casings:2', 'give:ammo_box:1', 'give:scrap:1',
            'take:ammo_box:1', 'give:casings:2', 'give:lead:2', 'give:powder:1' }, calls)
    end)
    it('a throwing step counts as failed and still rolls back', function()
        local deps, inv = fakeInv(full, { throwGive = 'ammo_box' })
        local ok, reason, info = F.craft(1, recipe, deps)
        eq(false, ok); eq('step_error', reason); eq(4, info.index)
        same(full, inv)
    end)
    it('an undo that fails is reported, the rest still rolls back', function()
        -- casings take fails; giving lead back also fails -> reported; powder still given back
        local deps, inv = fakeInv(full, { failTake = { casings = 'not_enough' }, failGive = { lead = 'no_room' } })
        local ok, reason, info = F.craft(1, recipe, deps)
        eq(false, ok); eq('not_enough', reason)
        eq(1, #info.rollbackFailed)
        same({ op = 'remove', item = 'lead', amount = 2 }, info.rollbackFailed[1].step)
        eq('no_room', info.rollbackFailed[1].reason)
        same({ powder = 1, casings = 3 }, inv)
    end)
    it('never mutates the recipe', function()
        local deps = fakeInv(full, { failGive = { scrap = 'no_room' } })
        F.craft(1, recipe, deps)
        eq(3, #recipe.inputs); eq(2, recipe.inputs[2].amount); eq(2, #recipe.outputs)
    end)
end)

describe('craft flow: transact', function()
    it('empty steps succeed', function()
        local ok, _, info = F.transact({}, function() return true end, function() return true end)
        eq(true, ok); eq(0, info.applied)
    end)
    it('a nil result counts as failure with a default reason', function()
        local undone = {}
        local ok, reason, info = F.transact({ { n = 1 }, { n = 2 } },
            function(s) if s.n == 2 then return nil end return true end,
            function(s) undone[#undone + 1] = s.n; return true end)
        eq(false, ok); eq('step_failed', reason); eq(2, info.index); same({ 1 }, undone)
    end)
    it('a throwing undo is reported as undo_error', function()
        local ok, _, info = F.transact({ { n = 1 }, { n = 2 } },
            function(s) return s.n == 1 end, function() error('x') end)
        eq(false, ok); eq('undo_error', info.rollbackFailed[1].reason)
    end)
end)

describe('craft flow: planTake over carried sections', function()
    local A, B = { type = 'equipped', id = 1 }, { type = 'backpack', id = 1 }
    it('takes from the first section first, then the next', function()
        local steps = F.planTake({ { ref = A, have = 1 }, { ref = B, have = 5 } }, 'lead', 3)
        same({ { op = 'remove', ref = A, item = 'lead', amount = 1 }, { op = 'remove', ref = B, item = 'lead', amount = 2 } }, steps)
    end)
    it('skips empty sections and stops once covered', function()
        local steps = F.planTake({ { ref = A, have = 0 }, { ref = B, have = 5 } }, 'lead', 2)
        same({ { op = 'remove', ref = B, item = 'lead', amount = 2 } }, steps)
    end)
    it('short total: not_enough, no steps', function()
        local steps, why = F.planTake({ { ref = A, have = 1 }, { ref = B, have = 1 } }, 'lead', 3)
        eq(nil, steps); eq('not_enough', why)
    end)
    it('bad amounts refused', function()
        for _, n in ipairs({ 0, -1, 1.5, 'x' }) do
            local steps, why = F.planTake({ { ref = A, have = 9 } }, 'lead', n)
            eq(nil, steps); eq('bad_amount', why)
        end
    end)
    it('inverse flips remove/add and keeps the rest', function()
        local s = { op = 'remove', ref = A, item = 'lead', amount = 2 }
        same({ op = 'add', ref = A, item = 'lead', amount = 2 }, F.inverse(s))
        eq('remove', s.op)
        eq('remove', F.inverse(F.inverse(s)).op)
    end)
end)

describe('craft flow: dev station fallback', function()
    local dev = { reload = { x = 0, y = 0, z = 0 }, apothecary = { x = 10, y = 0, z = 0 } }
    it('in range of the right type', function()
        eq('reload', (F.nearestDev(dev, { x = 1, y = 1, z = 0 }, 3, 'reload')))
    end)
    it('out of range or wrong type: nil', function()
        eq(nil, F.nearestDev(dev, { x = 5, y = 0, z = 0 }, 3, 'reload'))
        eq(nil, F.nearestDev(dev, { x = 0, y = 0, z = 0 }, 3, 'gunsmith'))
    end)
    it('any type picks the nearest', function()
        eq('apothecary', (F.nearestDev(dev, { x = 9, y = 0, z = 0 }, 3)))
    end)
    it('bad coords, NaN or missing table: nil', function()
        eq(nil, F.nearestDev(dev, { x = 0 / 0, y = 0, z = 0 }, 3, 'reload'))
        eq(nil, F.nearestDev(dev, nil, 3, 'reload'))
        eq(nil, F.nearestDev(nil, { x = 0, y = 0, z = 0 }, 3, 'reload'))
        eq(nil, F.nearestDev(dev, { x = 0, y = 0, z = 0 }, 0 / 0, 'reload'))
    end)
end)

T.finish()

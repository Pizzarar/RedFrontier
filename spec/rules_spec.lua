local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local describe, it, eq, same = T.describe, T.it, T.eq, T.same

local config = require('config')
local Rules = require('rules')

config.Items = {}
config.ItemOverrides = {
    saddle = { size_class = 'bulky' },
    gold_bar = { size_class = 'cargo' },
}

-- rsg runtime item: per-unit weight, unique = not stackable
local function I(name, amount, weight, extra)
    local it = { name = name, amount = amount or 1, weight = weight or 100, unique = false, info = {} }
    for k, v in pairs(extra or {}) do it[k] = v end
    return it
end
local function bread(n) return I('bread', n, 100) end
local function saddle() return I('saddle', 1, 5000, { unique = true }) end
local function gold(n) return I('gold_bar', n, 12000) end
local function pistol() return I('pistol', 1, 1000, { unique = true }) end

local function V(ctype, items, slots, maxWeight, extra)
    local v = { type = ctype, items = items or {}, slots = slots or 10, maxWeight = maxWeight or 100000 }
    for k, x in pairs(extra or {}) do v[k] = x end
    return v
end

describe('fh_core shared/rules', function()
    describe('getWeight', function()
        it('sums unit weight x amount', function()
            eq(1500, Rules.getWeight(V('chest', { [1] = bread(5), [4] = I('rope', 1, 1000) })))
        end)
        it('counts only slots inside slotRange', function()
            local v = V('backpack', { [1] = bread(5), [6] = bread(2) }, 20, 100000, { slotRange = { 6, 25 } })
            eq(200, Rules.getWeight(v))
        end)
    end)

    describe('canFit', function()
        it('runs the size-class rule', function()
            local ok, reason = Rules.canFit(V('backpack'), saddle(), 1)
            eq(false, ok); eq('fh_size_class', reason)
            assert(Rules.canFit(V('saddlebag'), saddle(), 1))
            eq('fh_size_class', select(2, Rules.canFit(V('saddlebag'), gold(1), 1)))
            assert(Rules.canFit(V('wagon'), gold(1), 1))
        end)
        it('refuses unknown containers and items', function()
            eq('fh_unknown_container', select(2, Rules.canFit(V('moon'), bread(1), 1)))
            eq('fh_unknown_item', select(2, Rules.canFit(V('chest'), 'no_such_item', 1)))
        end)
        it('refuses a non-positive or fractional amount', function()
            eq('fh_bad_amount', select(2, Rules.canFit(V('chest'), bread(1), 0)))
            eq('fh_bad_amount', select(2, Rules.canFit(V('chest'), bread(1), 1.5)))
        end)
        it('enforces maxWeight to the gram', function()
            local v = V('chest', { [1] = bread(9) }, 10, 1000)
            assert(Rules.canFit(v, bread(1), 1))
            local ok, reason = Rules.canFit(v, bread(2), 2)
            eq(false, ok); eq('fh_too_heavy', reason)
        end)
        it('defaults amount to item.amount', function()
            eq('fh_too_heavy', select(2, Rules.canFit(V('chest', {}, 10, 1000), bread(11))))
        end)
        it('stacks onto a matching stack even with no free slot', function()
            local v = V('chest', { [1] = bread(1), [2] = I('rope') }, 2)
            local ok, _, slot = Rules.canFit(v, bread(3), 3)
            eq(true, ok); eq(1, slot)
            eq('fh_no_slot', select(2, Rules.canFit(v, I('cloth'), 1)))
        end)
        it('does not stack across differing info (condition)', function()
            local v = V('chest', { [1] = I('knife', 1, 500, { info = { condition = 90 } }) }, 1)
            eq('fh_no_slot', select(2, Rules.canFit(v, I('knife', 1, 500, { info = { condition = 40 } }), 1)))
        end)
        it('never stacks unique items and needs one free slot per unit', function()
            local v = V('chest', { [1] = pistol() }, 2)
            local ok, _, slot = Rules.canFit(v, pistol(), 1)
            eq(true, ok); eq(2, slot)
            eq('fh_no_slot', select(2, Rules.canFit(v, I('pistol', 2, 1000, { unique = true }), 2)))
        end)
        it('checks a named slot', function()
            local v = V('chest', { [1] = bread(1), [2] = I('rope') }, 3)
            assert(Rules.canFit(v, bread(1), 1, { slot = 1 }))
            eq('fh_slot_taken', select(2, Rules.canFit(v, bread(1), 1, { slot = 2 })))
            assert(Rules.canFit(v, bread(1), 1, { slot = 3 }))
            eq('fh_bad_slot', select(2, Rules.canFit(v, bread(1), 1, { slot = 4 })))
        end)
        it('treats `replacing` as gone (slot and weight)', function()
            local rope = I('rope', 1, 1000)
            local v = V('chest', { [1] = rope }, 1, 1000)
            eq('fh_too_heavy', select(2, Rules.canFit(v, I('lamp', 1, 1000), 1, { slot = 1 }))) -- weight first
            eq('fh_slot_taken', select(2, Rules.canFit(v, I('lamp', 1, 0), 1, { slot = 1 })))
            assert(Rules.canFit(v, I('lamp', 1, 1000), 1, { slot = 1, replacing = rope }))
        end)
        it('respects slotRange', function()
            local v = V('equipped', {}, 5, 8000, { slotRange = { 1, 5 } })
            eq('fh_bad_slot', select(2, Rules.canFit(v, bread(1), 1, { slot = 6 })))
        end)
    end)

    describe('playerViews', function()
        local function player()
            return { [1] = I('knife', 1, 1000), [7] = bread(5), [30] = I('ghost', 1, 99999) }
        end
        it('splits equipped (hotbar) and backpack with section caps', function()
            local eqv, bp = Rules.playerViews(player(), 10000, 25)
            eq('equipped', eqv.type); eq('backpack', bp.type)
            same({ 1, 5 }, eqv.slotRange); same({ 6, 25 }, bp.slotRange)
            eq(5, eqv.slots); eq(20, bp.slots)
            eq(8000, eqv.ownMaxWeight); eq(10000, bp.ownMaxWeight)
            eq(8000, eqv.maxWeight)          -- min(8000, 10000 - 500)
            eq(9000, bp.maxWeight)           -- min(10000, 10000 - 1000)
            assert(eqv.items[1] and not eqv.items[7] and bp.items[7] and not bp.items[1])
            eq(nil, bp.items[30])            -- beyond totalSlots: ignored
            assert(rawequal(eqv.group, bp.group))
        end)
        it('shrinks equipped when the backpack is heavy', function()
            local eqv = Rules.playerViews({ [6] = I('ore', 1, 9500) }, 10000, 25)
            eq(500, eqv.maxWeight)
        end)
        it('honours a capacity bonus in totalSlots', function()
            local _, bp = Rules.playerViews({}, 10000, 30)
            same({ 6, 30 }, bp.slotRange); eq(25, bp.slots)
        end)
        it('defaults totalCap / totalSlots from FhConfig.Player', function()
            local _, bp = Rules.playerViews({})
            same({ 6, config.Player.Slots }, bp.slotRange); eq(config.Player.MaxWeight, bp.maxWeight)
        end)
    end)

    describe('planMove', function()
        it('moves part of a stack into an empty slot', function()
            local eqv, bp = Rules.playerViews({ [7] = bread(5) }, 10000, 25)
            local plan = Rules.planMove(bp, eqv, 7, 2, 3)
            same({ kind = 'move', name = 'bread', fromSlot = 7, toSlot = 2, amount = 3,
                fromType = 'backpack', toType = 'equipped' }, plan)
        end)
        it('stacks onto a matching stack', function()
            local chest = V('chest', { [1] = bread(5) })
            local bp = V('backpack', { [6] = bread(2) }, 20, 100000, { slotRange = { 6, 25 } })
            eq('stack', Rules.planMove(chest, bp, 1, 6, 5).kind)
        end)
        it('refuses a bulky item into equipped / backpack', function()
            local wagon = V('wagon', { [1] = saddle() })
            local eqv, bp = Rules.playerViews({}, 10000, 25)
            eq('fh_size_class', select(2, Rules.planMove(wagon, eqv, 1, 1)))
            eq('fh_size_class', select(2, Rules.planMove(wagon, bp, 1, 6)))
        end)
        it('swaps whole stacks and refuses a partial swap', function()
            local eqv, bp = Rules.playerViews({ [1] = I('knife', 1, 1000), [7] = bread(5) }, 10000, 25)
            local plan = Rules.planMove(bp, eqv, 7, 1, 5)
            eq('swap', plan.kind); eq('knife', plan.swapName); eq(1, plan.swapAmount)
            eq('fh_slot_taken', select(2, Rules.planMove(bp, eqv, 7, 1, 2)))
        end)
        it('checks the return leg of a swap', function()
            local wagon = V('wagon', { [1] = saddle() })
            local bp = V('backpack', { [6] = bread(1) }, 20, 100000, { slotRange = { 6, 25 } })
            eq('fh_size_class', select(2, Rules.planMove(bp, wagon, 6, 1, 1))) -- saddle would land in backpack
        end)
        it('credits weight leaving the sibling section, capped by the own cap', function()
            -- total 10000; equipped holds 1000, backpack 9000 -> equipped.maxWeight 1000
            local eqv, bp = Rules.playerViews({ [1] = I('knife', 1, 1000), [6] = I('ore', 3, 3000) }, 10000, 25)
            eq(1000, eqv.maxWeight)
            assert(Rules.planMove(bp, eqv, 6, 2, 1))
            assert(Rules.planMove(bp, eqv, 6, 2, 2))
            eq('fh_too_heavy', select(2, Rules.planMove(bp, eqv, 6, 2, 3))) -- 10000 > own cap 8000
        end)
        it('does not double count weight inside one view', function()
            local chest = V('chest', { [1] = bread(10) }, 10, 1000)
            eq('move', Rules.planMove(chest, chest, 1, 2).kind)
            eq('move', Rules.planMove(chest, chest, 1, 2, 4).kind)
        end)
        it('refuses same slot, empty slot, bad amount and bad slot', function()
            local chest = V('chest', { [1] = bread(3) }, 5)
            eq('fh_same_slot', select(2, Rules.planMove(chest, chest, 1, 1)))
            eq('fh_no_item', select(2, Rules.planMove(chest, chest, 2, 3)))
            eq('fh_bad_amount', select(2, Rules.planMove(chest, chest, 1, 2, 4)))
            eq('fh_bad_slot', select(2, Rules.planMove(chest, chest, 1, 9)))
        end)
    end)

    describe('planTransferAll', function()
        it('moves what fits, partially for stacks, and reports leftovers', function()
            local chest = V('chest', { [1] = bread(10), [2] = saddle(), [3] = gold(1) })
            local bag = V('saddlebag', { [1] = bread(2) }, 20, 1000)
            local plan, left = Rules.planTransferAll(chest, bag)
            same({ { kind = 'stack', name = 'bread', fromSlot = 1, toSlot = 1, amount = 8,
                fromType = 'chest', toType = 'saddlebag' } }, plan)
            same({
                { slot = 1, name = 'bread', amount = 2, reason = 'fh_too_heavy' },
                { slot = 2, name = 'saddle', amount = 1, reason = 'fh_too_heavy' },
                { slot = 3, name = 'gold_bar', amount = 1, reason = 'fh_size_class' },
            }, left)
        end)
        it('fills free slots in order and reports fh_no_slot', function()
            local chest = V('chest', { [1] = bread(5), [2] = saddle(), [3] = pistol() })
            local bag = V('saddlebag', { [1] = I('rope') }, 2, 100000)
            local plan, left = Rules.planTransferAll(chest, bag)
            eq(1, #plan); eq('move', plan[1].kind); eq(2, plan[1].toSlot); eq(5, plan[1].amount)
            same({
                { slot = 2, name = 'saddle', amount = 1, reason = 'fh_no_slot' },
                { slot = 3, name = 'pistol', amount = 1, reason = 'fh_no_slot' },
            }, left)
        end)
        it('stacks later items onto stacks the plan itself created', function()
            local chest = V('chest', { [1] = bread(2), [2] = bread(3) })
            local plan = Rules.planTransferAll(chest, V('drop_bag', {}, 5))
            eq(2, #plan); eq('move', plan[1].kind); eq('stack', plan[2].kind); eq(plan[1].toSlot, plan[2].toSlot)
        end)
        it('does not mutate either view', function()
            local chest = V('chest', { [1] = bread(5) })
            local bag = V('saddlebag', { [1] = bread(1) })
            Rules.planTransferAll(chest, bag)
            eq(5, chest.items[1].amount); eq(1, bag.items[1].amount); eq(nil, bag.items[2])
        end)
        it('returns an empty plan for the same view', function()
            local chest = V('chest', { [1] = bread(5) })
            local plan, left = Rules.planTransferAll(chest, chest)
            eq(0, #plan); eq(0, #left)
        end)
    end)
end)

T.finish()

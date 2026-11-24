-- H13 (plan homestead-03, "no inherited stashes"): fh_homestead server/main.lua unclaim vs the plot's chest stashes, in
-- the stubbed world of spec/support/homestead_world.lua (fake fh_core snapshot/clearContainer over W.stash).
-- Unclaim is refused 'fh_chests_not_empty' while chest 1 or a built chest_2/chest_3 holds an item; admin `force` logs
-- every item, fires fh:homestead:spilled and empties them all. The check runs under the per-plot lock; anything that
-- lands during the DELETE is swept (ITEM LOST) before the lock is released, so the next owner opens empty chests.
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local case = T.it

local function V(x, y, z) return { x = x, y = y, z = z } end
local CHEST = { kind = 'chest', maxTier = 1 }
local function plot(id, x, class, slots, extra)
    local p = { id = id, region = 'heartlands', center = V(x, 0, 0), radius = 14.0, class = class, slots = slots,
        chest = { coords = V(x + 2, 0, 0), heading = 0.0, model = 'p_chest01x' } }
    for k, v in pairs(extra or {}) do p[k] = v end
    return p
end
local cfg = { baseSafeRadius = 25.0, townLot = { price = 300, rep = 25 }, plots = {
    claim_a = plot('claim_a', 0, 'claim', { chest_2 = CHEST, chest_3 = CHEST, cabin = { kind = 'cabin', maxTier = 3 } }),
    lot_a = plot('lot_a', 2000, 'town_lot', { chest_2 = CHEST }, { claimable = true }),
} }
local newWorld = dofile(here .. 'support/homestead_world.lua')(T, cfg)

local function sid(plotId, n) return ('fh:chest:%s:%d'):format(plotId, n) end

---World with A holding claim_a (and lot_a when withLot), every chest built + registered, all stashes empty.
---tiers[plotId][slotId] is what the FhHomesteadSlots stub reports; W.slotsReady toggles isReady.
local function world(withLot)
    local tiers = { claim_a = { chest_2 = 1, chest_3 = 1 }, lot_a = { chest_2 = 1 } }
    local S = { ready = true }
    local slots = { isReady = function() return S.ready end, getTiers = function(pid) return tiers[pid] or {} end }
    local rows = { { plot_id = 'claim_a', citizenid = 'A', class = 'claim' } }
    if withLot then rows[2] = { plot_id = 'lot_a', citizenid = 'A', class = 'town_lot' } end
    local W = newWorld(rows, { slots = slots })
    W.tiers, W.slotsState = tiers, S
    for _, id in ipairs({ sid('claim_a', 2), sid('claim_a', 3), sid('lot_a', 2) }) do W.registered[id] = true end
    W.players[3] = 'ADM'; W.admins[3] = true
    return W
end

local function put(W, id, slot, name, amount)
    W.stash[id] = W.stash[id] or {}
    W.stash[id][slot] = { name = name, amount = amount }
end

local function empty(W, id)
    return next(W.stash[id] or {}) == nil
end

local function lastEvent(W, name)
    for i = #W.events, 1, -1 do if W.events[i].name == name then return W.events[i].data end end
end

local function held(W, plotId, cid, class)
    T.same({ citizenid = cid, class = class }, W.db.plots[plotId], plotId .. ' row kept')
    T.eq(cid, W.C.ownerOf(plotId), plotId .. ' still owned in memory')
end

T.describe('fh_homestead unclaim vs plot stashes (H13)', function()
    case('an item in any claim chest refuses the owner unclaim: fh_chests_not_empty, nothing deleted or cleared', function()
        for n = 1, 3 do
            local W = world()
            put(W, sid('claim_a', n), 4, 'wood', 2)
            T.same({ false, 'fh_chests_not_empty' }, { W.ex.unclaim(1) }, 'chest ' .. n)
            held(W, 'claim_a', 'A', 'claim')
            T.eq(0, #W.clears, 'no clear'); T.eq(0, W.named('fh:homestead:unclaimed')); T.eq(0, W.named('fh:homestead:spilled'))
            T.eq(2, W.stash[sid('claim_a', n)][4].amount, 'items untouched')
            -- the lock was released: emptied by the owner, the same unclaim now goes through
            W.stash[sid('claim_a', n)] = {}
            T.same({ true, 'claim_a' }, { W.ex.unclaim(1) }, 'retry after emptying chest ' .. n)
            W.consistent()
        end
    end)

    case('empty chests: released, every chest of the class read, nothing cleared, no spilled event', function()
        local W = world()
        T.same({ true, 'claim_a' }, { W.ex.unclaim(1) })
        T.eq(nil, W.db.plots.claim_a); T.eq(nil, W.C.ownerOf('claim_a'))
        for n = 1, 3 do
            local seen = false
            for _, id in ipairs(W.snapshots) do if id == sid('claim_a', n) then seen = true end end
            assert(seen, 'chest ' .. n .. ' read')
        end
        T.eq(0, #W.clears); T.eq(0, W.named('fh:homestead:spilled')); T.eq(1, W.named('fh:homestead:unclaimed'))
        W.consistent()
    end)

    case('admin force: every item logged, one spilled event, every stash cleared, then released', function()
        local W = world()
        put(W, sid('claim_a', 1), 1, 'wood', 5)
        put(W, sid('claim_a', 1), 7, 'stone', 1)
        put(W, sid('claim_a', 3), 2, 'pelt_deer', 3)
        W.commands.fh_unclaim(0, {}, 'fh_unclaim claim_a force')
        T.eq('[fh_homestead] fh_unclaim: released plot claim_a', W.logs[#W.logs])
        for n = 1, 3 do assert(empty(W, sid('claim_a', n)), 'chest ' .. n .. ' empty') end
        T.same({ sid('claim_a', 1), sid('claim_a', 3) }, W.clears, 'only the non-empty stashes are cleared')
        assert(W.logged('force unclaim: plot=claim_a owner=A stash=fh:chest:claim_a:1 slot=1 item=wood count=5 cleared'))
        assert(W.logged('stash=fh:chest:claim_a:1 slot=7 item=stone count=1 cleared'))
        assert(W.logged('stash=fh:chest:claim_a:3 slot=2 item=pelt_deer count=3 cleared'))
        T.same({ src = 0, citizenid = 'A', plot_id = 'claim_a', reason = 'force unclaim', stashes = {
            { stash_id = sid('claim_a', 1), items = { { item = 'wood', count = 5 }, { item = 'stone', count = 1 } } },
            { stash_id = sid('claim_a', 3), items = { { item = 'pelt_deer', count = 3 } } },
        } }, lastEvent(W, 'fh:homestead:spilled'))
        T.eq(1, W.named('fh:homestead:spilled'))
        T.eq(nil, W.db.plots.claim_a); T.eq(1, W.named('fh:homestead:unclaimed'))
        W.consistent()
    end)

    case('the next owner opens empty chests', function()
        local W = world()
        put(W, sid('claim_a', 1), 1, 'gold_bar', 2)
        put(W, sid('claim_a', 2), 1, 'rifle', 1)
        T.same({ true, 'claim_a' }, { W.ex.unclaim(0, 'claim_a', true) })
        T.same({ true, 'claim_a' }, { W.claimAt(2, 'claim_a') })
        T.eq('B', W.C.ownerOf('claim_a'))
        for n = 1, 3 do assert(empty(W, sid('claim_a', n)), 'B inherits nothing in chest ' .. n) end
        -- and B's own unclaim sees them empty
        T.same({ true, 'claim_a' }, { W.ex.unclaim(2) })
    end)

    case('town lot: chest_2 counts, lot chest_3 does not exist; force keeps the rep-back', function()
        local W = world(true)
        put(W, sid('lot_a', 2), 3, 'wood', 9)
        T.same({ false, 'fh_chests_not_empty' }, { W.ex.unclaim(1, 'lot_a') })
        held(W, 'lot_a', 'A', 'town_lot')
        T.eq(0, #W.reps, 'no rep taken back on a refusal')
        for _, id in ipairs(W.snapshots) do assert(id ~= sid('lot_a', 3), 'a lot has no chest 3') end
        T.same({ false, 'fh_not_admin' }, { W.ex.unclaim(1, 'lot_a', true) })
        T.same({ true, 'lot_a' }, { W.ex.unclaim(3, 'lot_a', true) }, 'an ace admin player may force')
        assert(empty(W, sid('lot_a', 2)))
        T.eq('lot_a', lastEvent(W, 'fh:homestead:spilled').plot_id)
        T.same({ { citizenid = 'A', region = 'heartlands', delta = -25, reason = 'town_lot_abandon', byCid = true } }, W.reps)
        T.eq('claim_a', W.ex.getPlot('A'), 'the claim is untouched')
        W.consistent()
    end)

    case('an item added during the DELETE is swept (ITEM LOST) before the lock is released', function()
        local W = world()
        W.hold.delete_plot = true
        local h = W.start(function() return W.ex.unclaim(1) end)
        assert(not h.done, 'held at the DELETE')
        -- a pane opened before the lock is still open: the player drops an item in now
        put(W, sid('claim_a', 2), 5, 'moonshine', 4)
        T.same({ false, 'fh_claim_busy' }, { W.C.beginChestWrite('claim_a') }, 'no build/trophy during the unclaim')
        T.same({ true, 'claim_a' }, { W.finish(h) })
        assert(empty(W, sid('claim_a', 2)), 'swept')
        assert(W.logged('ITEM LOST: added during unclaim: plot=claim_a owner=A stash=fh:chest:claim_a:2 slot=5 item=moonshine count=4'))
        T.eq('ITEM LOST: added during unclaim', lastEvent(W, 'fh:homestead:spilled').reason)
        T.same({ true }, { W.C.beginChestWrite('claim_a') }, 'lock released after the sweep')
        W.C.endChestWrite('claim_a')
    end)

    case('a sweep that cannot clear still releases (the row is gone) and logs a by-hand wipe', function()
        local W = world()
        W.hold.delete_plot = true
        local h = W.start(function() return W.ex.unclaim(1) end)
        put(W, sid('claim_a', 1), 1, 'wood', 1)
        W.fail.clear = 'noop'
        T.same({ true, 'claim_a' }, { W.finish(h) })
        assert(W.logged('could not be emptied'))
        assert(W.logged('was released but its chests may still hold items %(fh_chest_clear_failed%)'))
        T.same({ true }, { W.C.beginChestWrite('claim_a') }, 'lock released')
        W.C.endChestWrite('claim_a')
    end)

    case('read failures refuse fail-closed: fh_chest_check_failed, nothing deleted, lock released', function()
        for _, mode in ipairs({ 'fh_inventory_down', 'throw' }) do
            local W = world()
            W.fail.snapshot = mode
            T.same({ false, 'fh_chest_check_failed' }, { W.ex.unclaim(1) }, mode)
            T.same({ false, 'fh_chest_check_failed' }, { W.ex.unclaim(0, 'claim_a', true) }, mode .. ' force')
            held(W, 'claim_a', 'A', 'claim')
            T.eq(0, #W.clears)
            W.fail.snapshot = nil
            T.same({ true, 'claim_a' }, { W.ex.unclaim(1) }, mode .. ': not stuck busy')
        end
    end)

    case('unknown containers: chest 1 is re-registered and read; an unbuilt extra chest is skipped, a built one fails closed', function()
        local W = world()
        W.registered[sid('claim_a', 1)] = nil
        put(W, sid('claim_a', 1), 1, 'wood', 1) -- DB stash from an earlier boot
        W.registered[sid('claim_a', 3)], W.tiers.claim_a.chest_3 = nil, 0
        T.same({ false, 'fh_chests_not_empty' }, { W.ex.unclaim(1) }, 'chest 1 re-registered and its items seen')
        assert(W.registered[sid('claim_a', 1)])
        W.stash[sid('claim_a', 1)] = {}
        T.same({ true, 'claim_a' }, { W.ex.unclaim(1) }, 'unbuilt chest_3 skipped')

        W = world()
        W.registered[sid('claim_a', 2)] = nil -- built, but fh_core does not know it
        T.same({ false, 'fh_chest_check_failed' }, { W.ex.unclaim(1) })
        held(W, 'claim_a', 'A', 'claim')

        W = world()
        W.registered[sid('claim_a', 2)] = nil
        W.slotsState.ready = false
        T.same({ false, 'fh_not_ready' }, { W.ex.unclaim(1) }, 'cannot tell built from unbuilt before the slot load')
        held(W, 'claim_a', 'A', 'claim')
    end)

    case('clear failures refuse the force: fh_chest_clear_failed, row kept, lock released; event lists only verified clears', function()
        for _, mode in ipairs({ 'nope', 'throw', 'noop' }) do
            local W = world()
            put(W, sid('claim_a', 1), 1, 'wood', 2)
            W.fail.clear = mode
            T.same({ false, 'fh_chest_clear_failed' }, { W.ex.unclaim(0, 'claim_a', true) }, mode)
            held(W, 'claim_a', 'A', 'claim')
            T.eq(0, W.named('fh:homestead:unclaimed'))
            assert(W.logged('stash=fh:chest:claim_a:1 could not be emptied'), mode)
            T.eq(0, W.named('fh:homestead:spilled'), mode .. ': spilled only after a verified clear (review low 1)')
            W.fail.clear = nil
            T.same({ true, 'claim_a' }, { W.ex.unclaim(0, 'claim_a', true) }, mode .. ': retry')
        end
        -- chest 1 clears, chest 2 does not: the event names chest 1 only, the retry names chest 2 only
        local W = world()
        put(W, sid('claim_a', 1), 1, 'wood', 2)
        put(W, sid('claim_a', 2), 1, 'stone', 3)
        local clear = W.env.exports.fh_core.clearContainer
        W.env.exports.fh_core.clearContainer = function(self, ref)
            if ref.id == sid('claim_a', 2) and not W.allowChest2 then return false, 'nope' end
            return clear(self, ref)
        end
        T.same({ false, 'fh_chest_clear_failed' }, { W.ex.unclaim(0, 'claim_a', true) })
        T.same({ sid('claim_a', 1) }, { lastEvent(W, 'fh:homestead:spilled').stashes[1].stash_id })
        T.eq(1, #lastEvent(W, 'fh:homestead:spilled').stashes)
        W.allowChest2 = true
        T.same({ true, 'claim_a' }, { W.ex.unclaim(0, 'claim_a', true) })
        T.same({ { stash_id = sid('claim_a', 2), items = { { item = 'stone', count = 3 } } } },
            lastEvent(W, 'fh:homestead:spilled').stashes)
    end)

    case('force clears right before the DELETE: a refused own-lot rep-back destroys nothing; a failed clear gives the rep back', function()
        -- an admin abandoning their OWN lot with force: the rep-back is refusable, so it must come before the clear
        local W = world(true)
        W.admins[1] = true
        put(W, sid('lot_a', 1), 1, 'wood', 6)
        W.fail.rep = true
        T.same({ false, 'fh_rep_failed' }, { W.ex.unclaim(1, 'lot_a', true) })
        T.eq(6, W.stash[sid('lot_a', 1)][1].amount, 'nothing cleared')
        T.eq(0, #W.clears); T.eq(0, W.named('fh:homestead:spilled'))
        held(W, 'lot_a', 'A', 'town_lot')
        -- rep-back taken, then the clear fails: the rep is given back, the lot stays
        W.fail.rep, W.fail.clear = nil, 'nope'
        T.same({ false, 'fh_chest_clear_failed' }, { W.ex.unclaim(0, 'lot_a', true) })
        T.same({ -25, 25 }, { W.reps[1].delta, W.reps[2].delta })
        T.eq('town_lot_abandon_undo', W.reps[2].reason)
        T.eq(0, W.repOf('A', 'heartlands'))
        held(W, 'lot_a', 'A', 'town_lot')
        -- the clear runs after the rep-back
        W.fail.clear = nil
        local repsBefore = #W.reps
        T.same({ true, 'lot_a' }, { W.ex.unclaim(0, 'lot_a', true) })
        T.eq(repsBefore + 1, #W.reps)
        assert(empty(W, sid('lot_a', 1)))
    end)

    case('open_chest: owner opens; refused fh_claim_busy while the plot is mid-unclaim or mid-claim; unbuilt extra chest refused', function()
        local W = world()
        W.netEvent('fh:homestead:open_chest', 1, { plot_id = 'claim_a' })
        T.same({ { src = 1, id = sid('claim_a', 1) } }, W.opens)
        W.netEvent('fh:homestead:open_chest', 1, { plot_id = 'claim_a', chest = 3 })
        T.eq(sid('claim_a', 3), W.opens[2].id)
        W.netEvent('fh:homestead:open_chest', 2, { plot_id = 'claim_a' })
        T.eq(2, #W.opens, 'not the owner: no open')
        -- mid-unclaim (held at the DELETE): no chest opens until the lock is gone
        W.hold.delete_plot = true
        local h = W.start(function() return W.ex.unclaim(1) end)
        W.netEvent('fh:homestead:open_chest', 1, { plot_id = 'claim_a' })
        T.eq('chest: fh_claim_busy', W.client[#W.client].msg)
        T.eq(2, #W.opens)
        T.same({ true, 'claim_a' }, { W.finish(h) })
        -- mid-claim (held at the row insert): the new owner cannot open before the claim has landed
        W.hold.insert_plot = true
        W.at(2, 'claim_a')
        h = W.start(function() return W.ex.claim(2) end)
        W.netEvent('fh:homestead:open_chest', 2, { plot_id = 'claim_a' })
        T.eq('chest: fh_claim_busy', W.client[#W.client].msg)
        T.same({ true, 'claim_a' }, { W.finish(h) })
        W.netEvent('fh:homestead:open_chest', 2, { plot_id = 'claim_a' })
        T.same({ src = 2, id = sid('claim_a', 1) }, W.opens[3])
        W.tiers.claim_a.chest_2 = 0
        W.netEvent('fh:homestead:open_chest', 2, { plot_id = 'claim_a', chest = 2 })
        T.eq('chest: fh_chest_not_built', W.client[#W.client].msg)
        T.eq(3, #W.opens)
    end)

    case('H13b hired hand: the owner unclaim is refused fh_hand_active (getHands by src), nothing read or deleted', function()
        local W = world()
        W.hands[1] = { ranch_hand = { unpaid = 0, status = 'working' } }
        T.same({ false, 'fh_hand_active' }, { W.ex.unclaim(1) })
        T.same({ 1 }, W.handCalls, 'getHands gets the player src, not a citizenid')
        held(W, 'claim_a', 'A', 'claim')
        T.eq(0, #W.snapshots, 'refused before the stash read'); T.eq(0, W.named('fh:homestead:unclaimed'))
        W.commands.fh_unclaim(1, {}, 'fh_unclaim')
        T.eq('fh_unclaim: fh_hand_active', W.client[#W.client].msg)
        -- lock released: once the hand is fired the same unclaim goes through
        W.hands[1] = nil
        T.same({ true, 'claim_a' }, { W.ex.unclaim(1) })
        W.consistent()
    end)

    case('H13b no hand: released; fh_hands missing or erroring = allowed (pcall)', function()
        local W = world()
        T.same({ true, 'claim_a' }, { W.ex.unclaim(1) })
        T.same({ 1 }, W.handCalls)
        W = world()
        W.X.fh_hands = nil -- resource not started: no such export
        T.same({ true, 'claim_a' }, { W.ex.unclaim(1) })
        assert(W.logged('getHands unavailable'))
        W = world()
        W.fail.hands = 'throw'
        T.same({ true, 'claim_a' }, { W.ex.unclaim(1) })
        assert(W.logged('hired%-hand check skipped'))
    end)

    case('H13b skips: admin force (also by the owner), console release, and a town lot abandon', function()
        local W = world()
        W.hands[1] = { ranch_hand = {} }
        T.same({ true, 'claim_a' }, { W.ex.unclaim(0, 'claim_a', true) }, 'console force')
        T.eq(0, #W.handCalls)
        W = world()
        W.hands[1], W.admins[1] = { ranch_hand = {} }, true
        T.same({ false, 'fh_hand_active' }, { W.ex.unclaim(1) }, 'an admin owner without force is checked')
        T.same({ true, 'claim_a' }, { W.ex.unclaim(1, 'claim_a', true) }, 'an admin owner with force is not')
        W = world()
        W.hands[1] = { ranch_hand = {} }
        T.same({ true, 'claim_a' }, { W.ex.unclaim(0, 'claim_a') }, 'console release of the owner\'s claim: not checked')
        W = world(true)
        W.hands[1] = { ranch_hand = {} }
        T.same({ true, 'lot_a' }, { W.ex.unclaim(1, 'lot_a') }, 'hands work the claim chest, not the lot')
        T.eq(0, #W.handCalls)
        T.same({ false, 'fh_hand_active' }, { W.ex.unclaim(1) }, 'the claim is still guarded')
    end)

    case('force is admin-only: a non-admin owner gets fh_not_admin, command and export alike', function()
        local W = world()
        put(W, sid('claim_a', 1), 1, 'wood', 1)
        T.same({ false, 'fh_not_admin' }, { W.ex.unclaim(1, 'claim_a', true) })
        W.commands.fh_unclaim(1, {}, 'fh_unclaim claim_a force')
        T.eq('fh_unclaim: fh_not_admin', W.client[#W.client].msg)
        held(W, 'claim_a', 'A', 'claim')
        T.eq(0, #W.clears); assert(not empty(W, sid('claim_a', 1)))
    end)

    case('chest-writer interlock: a held write refuses the unclaim (fh_chest_busy); a write during the check is refused', function()
        local W = world()
        T.same({ true }, { W.C.beginChestWrite('claim_a') })
        T.same({ true }, { W.C.beginChestWrite('claim_a') }, 'writers count')
        T.same({ false, 'fh_chest_busy' }, { W.ex.unclaim(1) })
        T.same({ false, 'fh_chest_busy' }, { W.ex.unclaim(0, 'claim_a', true) }, 'force waits too')
        W.C.endChestWrite('claim_a')
        T.same({ false, 'fh_chest_busy' }, { W.ex.unclaim(1) }, 'one writer still in')
        W.C.endChestWrite('claim_a')
        local during
        W.onSnapshot = function() during = during or table.pack(W.C.beginChestWrite('claim_a')) end
        T.same({ true, 'claim_a' }, { W.ex.unclaim(1) })
        T.same({ false, 'fh_claim_busy', n = 2 }, during, 'refused while the stashes are being read')
    end)
end)

T.finish()

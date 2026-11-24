-- H7 (plan homestead-02): per-class claims in fh_homestead server/main.lua, loaded in the stubbed FXServer world of
-- spec/support/homestead_world.lua (in-memory fh_plots with PRIMARY KEY(plot_id) + UNIQUE(citizenid, class) like 0018).
-- byOwner is byOwner[class][citizenid]; getPlot(cid) / plotOf(cid) default to the 'claim' class, so every existing
-- caller (fh_hands, slots/build/comfort) keeps getting the homestead claim and never a town lot.
-- Awaits can be HELD (W.hold[tag]) so a spec can run another call meanwhile; see the harness.
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local case = T.it

local function V(x, y, z) return { x = x, y = y, z = z } end
local function plot(id, x, class, claimable)
    return { id = id, region = 'heartlands', center = V(x, 0, 0), radius = 20.0, class = class, claimable = claimable,
        chest = { coords = V(x + 2, 0, 0), heading = 0.0, model = 'p_chest01x' } }
end
-- town lots are claimable here so the class check, not the claimable flag, is what refuses /fh_claim on them
local cfg = { baseSafeRadius = 25.0, plots = {
    claim_a = plot('claim_a', 0), claim_b = plot('claim_b', 1000, 'claim'),
    lot_a = plot('lot_a', 2000, 'town_lot', true), lot_b = plot('lot_b', 3000, 'town_lot', true),
} }
local newWorld = dofile(here .. 'support/homestead_world.lua')(T, cfg)

T.describe('fh_homestead claims per class (H7)', function()
    case('getPlot(cid) returns the claim even when the cid also owns a town lot', function()
        local W = newWorld()
        T.same({ true, 'lot_a' }, { W.claimAt(1, 'lot_a', 'town_lot') })
        T.same({ true, 'claim_a' }, { W.claimAt(1, 'claim_a') })
        T.eq('claim_a', W.ex.getPlot('A'))
        T.eq('claim_a', W.ex.getPlot('A', 'claim'))
        T.eq('lot_a', W.ex.getPlot('A', 'town_lot'))
        T.eq('claim_a', W.C.plotOf('A'))
        T.eq('lot_a', W.C.plotOf('A', 'town_lot'))
        T.same({ citizenid = 'A', class = 'town_lot' }, W.db.plots.lot_a)
        T.same({ citizenid = 'A', class = 'claim' }, W.db.plots.claim_a)
        local l = W.ex.claimedPlots(); table.sort(l)
        T.same({ 'claim_a', 'lot_a' }, l)
        W.consistent()
    end)

    case('lot-only owner: getPlot(cid) nil, getPlot(cid, town_lot) = the lot', function()
        local W = newWorld()
        T.same({ true, 'lot_a' }, { W.claimAt(2, 'lot_a', 'town_lot') })
        T.eq(nil, W.ex.getPlot('B'))
        T.eq(nil, W.C.plotOf('B'))
        T.eq('lot_a', W.ex.getPlot('B', 'town_lot'))
        T.eq('B', W.C.ownerOf('lot_a'))
        -- /fh_unclaim with no id releases the claim only: a lot-only owner has none
        T.same({ false, 'fh_no_plot' }, { W.ex.unclaim(2) })
        T.eq('lot_a', W.ex.getPlot('B', 'town_lot'))
        W.consistent()
    end)

    case('unclaim of the lot leaves the claim (memory + DB), and no-arg unclaim releases the claim, not the lot', function()
        local W = newWorld()
        W.claimAt(1, 'claim_a'); W.claimAt(1, 'lot_a', 'town_lot')
        T.same({ true, 'lot_a' }, { W.ex.unclaim(1, 'lot_a') })
        T.eq('claim_a', W.ex.getPlot('A'))
        T.eq(nil, W.ex.getPlot('A', 'town_lot'))
        T.eq(nil, W.db.plots.lot_a)
        T.same({ citizenid = 'A', class = 'claim' }, W.db.plots.claim_a)
        T.eq(1, W.named('fh:homestead:unclaimed'))
        W.consistent()
        -- the lot again, then a no-arg unclaim: the claim goes, the lot stays
        T.same({ true, 'lot_b' }, { W.claimAt(1, 'lot_b', 'town_lot') })
        T.same({ true, 'claim_a' }, { W.ex.unclaim(1) })
        T.eq(nil, W.ex.getPlot('A'))
        T.eq('lot_b', W.ex.getPlot('A', 'town_lot'))
        W.consistent()
    end)

    case('one plot per class: a second claim or a second lot is refused, one of each is fine', function()
        local W = newWorld()
        W.claimAt(1, 'claim_a'); W.claimAt(1, 'lot_a', 'town_lot')
        T.same({ false, 'fh_already_has_plot' }, { W.claimAt(1, 'claim_b') })
        T.same({ false, 'fh_already_has_lot' }, { W.claimAt(1, 'lot_b', 'town_lot') })
        T.same({ false, 'fh_plot_taken' }, { W.claimAt(2, 'lot_a', 'town_lot') })
        W.consistent()
    end)

    case('/fh_claim on a town lot is refused (lots are bought, not claimed); claim(src, town_lot) on a claim too', function()
        local W = newWorld()
        W.at(1, 'lot_a')
        W.commands.fh_claim(1)
        T.eq('fh_claim: fh_wrong_plot_class', W.client[#W.client].msg)
        T.eq(nil, W.db.plots.lot_a)
        T.eq(nil, W.C.ownerOf('lot_a'))
        T.same({ false, 'fh_wrong_plot_class' }, { W.claimAt(1, 'claim_a', 'town_lot') })
        T.eq(nil, W.db.plots.claim_a)
        -- /fh_claim on a claim still works
        W.at(1, 'claim_a')
        W.commands.fh_claim(1)
        T.eq('fh_claim: claimed plot claim_a', W.client[#W.client].msg)
        T.eq('claim', W.events[#W.events].data.class, 'claimed payload carries class (H8)')
        W.consistent()
    end)

    case('DB insert failure keeps both maps consistent and leaves the other class untouched', function()
        local W = newWorld()
        W.claimAt(1, 'claim_a')
        W.fail.insert_plot = true
        T.same({ false, 'fh_claim_failed' }, { W.claimAt(1, 'lot_a', 'town_lot') })
        T.eq(nil, W.ex.getPlot('A', 'town_lot')); T.eq(nil, W.C.ownerOf('lot_a'))
        T.eq('claim_a', W.ex.getPlot('A'))
        W.consistent()
        W.fail.insert_plot = nil
        -- second stage (chest row) fails: our fh_plots row is rolled back, maps cleared
        W.fail.insert_chest = true
        T.same({ false, 'fh_claim_failed' }, { W.claimAt(1, 'lot_a', 'town_lot') })
        T.eq(nil, W.db.plots.lot_a); T.eq(nil, W.ex.getPlot('A', 'town_lot'))
        W.fail.insert_chest = nil
        -- chest register fails: same rollback
        W.fail.register = true
        T.same({ false, 'fh_claim_failed' }, { W.claimAt(1, 'lot_a', 'town_lot') })
        T.eq(nil, W.db.plots.lot_a); T.eq(nil, W.ex.getPlot('A', 'town_lot'))
        W.fail.register = nil
        -- chest register throws (fh_core gone): same rollback, the plot is not left reserved or busy
        W.fail.registerThrows = true
        T.same({ false, 'fh_claim_failed' }, { W.claimAt(1, 'lot_a', 'town_lot') })
        T.eq(nil, W.db.plots.lot_a); T.eq(nil, W.ex.getPlot('A', 'town_lot')); T.eq(nil, W.C.ownerOf('lot_a'))
        W.fail.registerThrows = nil
        T.eq(1, W.named("fh:homestead:claimed")) -- only the first claim fired
        W.consistent()
        -- and the lot is claimable afterwards
        T.same({ true, 'lot_a' }, { W.claimAt(1, 'lot_a', 'town_lot') })
        W.consistent()
    end)

    case('UNIQUE(citizenid, class) backstop: a DB row memory does not know about refuses the insert, maps stay clean', function()
        local W = newWorld()
        -- another server wrote A's lot after our load: memory thinks A has no lot
        W.db.plots.lot_b = { citizenid = 'A', class = 'town_lot' }
        T.same({ false, 'fh_claim_failed' }, { W.claimAt(1, 'lot_a', 'town_lot') })
        T.eq(nil, W.C.ownerOf('lot_a'))
        T.eq(nil, W.ex.getPlot('A', 'town_lot'))
        T.same({ citizenid = 'A', class = 'town_lot' }, W.db.plots.lot_b) -- the other row is not deleted
        -- a claim for A is still fine: different class
        T.same({ true, 'claim_a' }, { W.claimAt(1, 'claim_a') })
    end)

    case('unclaim while the claim is still writing: refused fh_claim_busy, the claim lands, memory = DB', function()
        local W = newWorld()
        W.hold.insert_chest = true
        W.at(1, 'lot_a')
        local h = W.start(function() return W.ex.claim(1, 'town_lot') end)
        T.eq('A', W.C.ownerOf('lot_a')) -- reserved
        T.same({ false, 'fh_claim_busy' }, { W.ex.unclaim(0, 'lot_a') })
        T.same({ true, 'lot_a' }, { W.finish(h) })
        W.consistent()
        T.same({ true, 'lot_a' }, { W.ex.unclaim(0, 'lot_a') })
        W.consistent()
    end)

    case('two claims in the same tick for one class: the reservation refuses the second', function()
        local W = newWorld()
        W.hold.insert_plot = true
        W.at(1, 'lot_a')
        local h = W.start(function() return W.ex.claim(1, 'town_lot') end)
        T.same({ false, 'fh_already_has_lot' }, { W.claimAt(1, 'lot_b', 'town_lot') })
        T.same({ true, 'claim_a' }, { W.claimAt(1, 'claim_a') }) -- the other class is not blocked
        T.same({ true, 'lot_a' }, { W.finish(h) })
        W.consistent()
    end)

    case('load: rows without class (no column, or NULL) load as claims; class rows load into their class', function()
        local rows = {
            { plot_id = 'claim_a', citizenid = 'A' },
            { plot_id = 'lot_a', citizenid = 'B', class = 'town_lot' },
            { plot_id = 'claim_b', citizenid = 'B', class = 'claim' },
        }
        local W = newWorld(rows)
        T.eq('claim_a', W.ex.getPlot('A'))
        T.eq('claim_b', W.ex.getPlot('B'))
        T.eq('lot_a', W.ex.getPlot('B', 'town_lot'))
        T.eq(nil, W.ex.getPlot('A', 'town_lot'))
        -- class persisted on load shows in the per-class refusal
        T.same({ false, 'fh_already_has_lot' }, { W.claimAt(2, 'lot_b', 'town_lot') })
        -- DB from before migration 0018: no class key on any row; all load as claims
        local W2 = newWorld({ { plot_id = 'claim_a', citizenid = 'A' }, { plot_id = 'claim_b', citizenid = 'B' } },
            { noClassColumn = true })
        T.eq('claim_a', W2.ex.getPlot('A')); T.eq('claim_b', W2.ex.getPlot('B'))
        T.eq(nil, W2.ex.getPlot('A', 'town_lot'))
        -- unclaim of a loaded lot clears its class bucket, the claim stays
        T.same({ true, 'lot_a' }, { W.ex.unclaim(0, 'lot_a') })
        T.eq(nil, W.ex.getPlot('B', 'town_lot')); T.eq('claim_b', W.ex.getPlot('B'))
        W.consistent()
    end)

    case('unclaim + unclaim + re-claim interleaved: one per-plot lock, the stale unclaim never wipes the new claim', function()
        local W = newWorld()
        W.claimAt(1, 'lot_a', 'town_lot')
        W.hold.delete_plot = 2 -- both unclaims would park at their DELETE
        local h1 = W.start(function() return W.ex.unclaim(0, 'lot_a') end)
        T.eq(false, h1.done)
        local h2 = W.start(function() return W.ex.unclaim(1, 'lot_a') end)
        -- the second unclaim never reaches the DB: refused at once, retryable
        T.eq(true, h2.done, 'second unclaim must not be in flight')
        T.same({ false, 'fh_claim_busy' }, { W.finish(h2) })
        T.same({ false, 'fh_plot_taken' }, { W.claimAt(2, 'lot_a', 'town_lot') }) -- still A's until the DELETE lands
        T.same({ true, 'lot_a' }, { W.finish(h1) })
        W.hold.delete_plot = nil
        W.consistent()
        -- A re-claims; while that claim is mid-write any unclaim of the plot is refused
        W.hold.insert_chest = true
        W.at(1, 'lot_a')
        local h3 = W.start(function() return W.ex.claim(1, 'town_lot') end)
        T.same({ false, 'fh_claim_busy' }, { W.ex.unclaim(0, 'lot_a') })
        T.same({ false, 'fh_claim_busy' }, { W.ex.unclaim(1, 'lot_a') })
        T.same({ true, 'lot_a' }, { W.finish(h3) })
        T.eq('lot_a', W.ex.getPlot('A', 'town_lot'))
        T.eq(1, W.named('fh:homestead:unclaimed'))
        W.consistent()
        -- the reservation is intact: no second lot for A
        T.same({ false, 'fh_already_has_lot' }, { W.claimAt(1, 'lot_b', 'town_lot') })
    end)

    case('rollback DELETE fails after a chest failure: row stays, claim stays in memory, lock released, unclaim retries', function()
        for _, mode in ipairs({ 'throw', 'nil' }) do
            local W = newWorld()
            W.fail.insert_chest, W.fail.delete_plot = true, mode
            T.same({ false, 'fh_claim_failed' }, { W.claimAt(1, 'lot_a', 'town_lot') })
            T.same({ citizenid = 'A', class = 'town_lot' }, W.db.plots.lot_a, mode .. ': row left behind')
            T.eq('lot_a', W.ex.getPlot('A', 'town_lot'), mode .. ': memory keeps the claim')
            T.eq(0, W.named('fh:homestead:claimed'))
            local logged = false
            for _, m in ipairs(W.logs) do if m:find('^%^1') and m:find('rolled back') then logged = true end end
            assert(logged, mode .. ': ^1 rollback error logged')
            W.consistent()
            W.fail.insert_chest, W.fail.delete_plot = nil, nil
            T.same({ true, 'lot_a' }, { W.ex.unclaim(0, 'lot_a') }) -- not stuck busy
            W.consistent()
            T.same({ true, 'lot_a' }, { W.claimAt(1, 'lot_a', 'town_lot') })
            W.consistent()
        end
        -- rollback DELETE works: the reservation is cleared (covered above too, asserted against the DB here)
        local W = newWorld()
        W.fail.insert_chest = true
        T.same({ false, 'fh_claim_failed' }, { W.claimAt(1, 'lot_a', 'town_lot') })
        T.eq(nil, W.db.plots.lot_a); T.eq(nil, W.C.ownerOf('lot_a'))
        W.consistent()
    end)

    case('unclaim DELETE fails: memory kept, lock released; 0 rows (row gone outside) drops the stale memory', function()
        for _, mode in ipairs({ 'throw', 'nil' }) do
            local W = newWorld()
            W.claimAt(1, 'lot_a', 'town_lot')
            W.fail.delete_plot = mode
            T.same({ false, 'fh_unclaim_failed' }, { W.ex.unclaim(0, 'lot_a') })
            T.eq('lot_a', W.ex.getPlot('A', 'town_lot'), mode)
            W.consistent()
            W.fail.delete_plot = nil
            T.same({ true, 'lot_a' }, { W.ex.unclaim(0, 'lot_a') }, mode .. ': retry works')
            W.consistent()
        end
        local W = newWorld()
        W.claimAt(1, 'lot_a', 'town_lot')
        W.db.plots.lot_a = nil -- deleted by hand in the DB
        T.same({ false, 'fh_unclaim_failed' }, { W.ex.unclaim(0, 'lot_a') })
        T.eq(nil, W.ex.getPlot('A', 'town_lot')); T.eq(nil, W.C.ownerOf('lot_a'))
        T.eq(0, W.named('fh:homestead:unclaimed'))
        W.consistent()
    end)
end)

T.finish()

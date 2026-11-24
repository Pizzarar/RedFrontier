-- H8 (plan homestead-02): town-lot purchase (/fh_buylot, export buyLot) and lot abandon in fh_homestead server/main.lua,
-- in the stubbed world of spec/support/homestead_world.lua (fake DB with 0018's keys + fake fh_economy charge/credit/rep).
-- Money: reserve + lock BEFORE charge; any failure after a charge = exactly one credit of the same amount. Rep: +townLot.rep
-- on purchase, -townLot.rep on abandon (owner online), so buy/abandon/rebuy nets one bump. Offline owner + admin abandon:
-- released anyway, the skipped rep-back is logged (fh_economy has no citizenid rep path).
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local case = T.it

local function V(x, y, z) return { x = x, y = y, z = z } end
local function plot(id, x, class, extra)
    local p = { id = id, region = 'heartlands', center = V(x, 0, 0), radius = 14.0, class = class,
        chest = { coords = V(x + 2, 0, 0), heading = 0.0, model = 'p_chest01x' } }
    for k, v in pairs(extra or {}) do p[k] = v end
    return p
end
local cfg = { baseSafeRadius = 25.0, townLot = { price = 300, rep = 25 }, plots = {
    claim_a = plot('claim_a', 0, 'claim'),
    lot_a = plot('lot_a', 2000, 'town_lot', { claimable = true }),
    lot_b = plot('lot_b', 3000, 'town_lot', { claimable = true, price = 450, region = 'scarlett_meadows' }),
    lot_closed = plot('lot_closed', 4000, 'town_lot', { claimable = false }),
    lot_c = plot('lot_c', 5000, 'town_lot'), -- no claimable key: claimable (only false refuses)
    lot_zero = plot('lot_zero', 6000, 'town_lot', { price = 0 }),
    lot_frac = plot('lot_frac', 7000, 'town_lot', { price = 12.5 }),
} }
local newWorld = dofile(here .. 'support/homestead_world.lua')(T, cfg)

local function event(W, name)
    for i = #W.events, 1, -1 do if W.events[i].name == name then return W.events[i].data end end
end

T.describe('fh_homestead town lots (H8)', function()
    case('success: 1 charge, 1 rep, 1 row + chest; claimed (class) + lot_bought events', function()
        local W = newWorld()
        W.at(1, 'lot_a')
        W.commands.fh_buylot(1)
        T.eq('fh_buylot: bought lot lot_a', W.client[#W.client].msg)
        T.same({ { citizenid = 'A', amount = 300, reason = 'town_lot:lot_a', region = 'heartlands' } }, W.charges)
        T.same({ { citizenid = 'A', region = 'heartlands', delta = 25, reason = 'town_lot' } }, W.reps)
        T.same({ citizenid = 'A', class = 'town_lot' }, W.db.plots.lot_a)
        T.eq('fh:chest:lot_a:1', W.db.chests.lot_a)
        T.eq(700, W.cash.A); T.eq(25, W.repOf('A', 'heartlands'))
        T.eq(0, #W.credits)
        T.eq('lot_a', W.ex.getPlot('A', 'town_lot')); T.eq(nil, W.ex.getPlot('A'))
        T.same({ src = 1, citizenid = 'A', plot_id = 'lot_a', region_id = 'heartlands', class = 'town_lot' },
            event(W, 'fh:homestead:claimed'))
        T.same({ src = 1, citizenid = 'A', plot_id = 'lot_a', region_id = 'heartlands', price = 300 },
            event(W, 'fh:homestead:lot_bought'))
        T.eq('fh:homestead:lot_bought', W.events[#W.events].name, 'lot_bought comes after claimed')
        W.consistent()
    end)

    case('per-plot price overrides townLot.price; rep goes to the lot region', function()
        local W = newWorld()
        T.same({ true, 'lot_b' }, { W.buyAt(1, 'lot_b') })
        T.eq(450, W.charges[1].amount); T.eq('scarlett_meadows', W.charges[1].region)
        T.eq(550, W.cash.A); T.eq(25, W.repOf('A', 'scarlett_meadows')); T.eq(0, W.repOf('A', 'heartlands'))
    end)

    case('refused before any charge: not claimable, not a lot, not in a plot; a lot with no claimable key is buyable', function()
        local W = newWorld()
        T.same({ false, 'fh_not_claimable' }, { W.buyAt(1, 'lot_closed') })
        T.same({ false, 'fh_wrong_plot_class' }, { W.buyAt(1, 'claim_a') })
        W.peds[1] = V(9999, 9999, 0)
        T.same({ false, 'fh_not_in_plot' }, { W.ex.buyLot(1) })
        T.eq(0, #W.charges); T.eq(0, #W.reps); T.eq(nil, W.db.plots.lot_closed)
        T.same({ true, 'lot_c' }, { W.buyAt(1, 'lot_c') })
        W.consistent()
    end)

    case('fh_insufficient_funds: no row, no rep, no credit, reservation released', function()
        local W = newWorld()
        W.cash.A = 100
        T.same({ false, 'fh_insufficient_funds' }, { W.buyAt(1, 'lot_a') })
        T.eq(nil, W.db.plots.lot_a); T.eq(nil, W.C.ownerOf('lot_a')); T.eq(nil, W.ex.getPlot('A', 'town_lot'))
        T.eq(0, #W.reps); T.eq(0, #W.credits); T.eq(100, W.cash.A)
        T.eq(0, W.named('fh:homestead:claimed'))
        -- not stuck busy / reserved: B can buy it
        T.same({ true, 'lot_a' }, { W.buyAt(2, 'lot_a') })
        W.consistent()
    end)

    case('fh_charge_busy (another payment in flight) = no row, retry works; a throwing charge = fh_charge_unavailable', function()
        local W = newWorld()
        W.chargeBusy.A = true
        T.same({ false, 'fh_charge_busy' }, { W.buyAt(1, 'lot_a') })
        T.eq(nil, W.db.plots.lot_a); T.eq(nil, W.C.ownerOf('lot_a')); T.eq(0, #W.charges); T.eq(0, #W.reps)
        W.chargeBusy.A = nil
        W.fail.chargeThrows = true
        T.same({ false, 'fh_charge_unavailable' }, { W.buyAt(1, 'lot_a') })
        T.eq(nil, W.C.ownerOf('lot_a')); T.eq(0, #W.credits)
        W.fail.chargeThrows = nil
        T.same({ true, 'lot_a' }, { W.buyAt(1, 'lot_a') })
        T.eq(1, #W.charges)
        W.consistent()
    end)

    case('DB write fails after the charge: exactly 1 credit of the same amount, no rep, no row, no events', function()
        for _, stage in ipairs({ 'insert_plot', 'insert_chest', 'register', 'registerThrows' }) do
            local W = newWorld()
            W.fail[stage] = true
            T.same({ false, 'fh_claim_failed' }, { W.buyAt(1, 'lot_b') }, stage)
            T.eq(1, #W.charges, stage .. ' charged once')
            T.same({ { citizenid = 'A', amount = 450, reason = 'town_lot_refund:lot_b', region = 'scarlett_meadows' } },
                W.credits, stage .. ' one refund')
            T.eq(1000, W.cash.A, stage .. ' money back')
            T.eq(0, #W.reps, stage .. ' no rep')
            T.eq(nil, W.db.plots.lot_b, stage); T.eq(nil, W.C.ownerOf('lot_b'), stage)
            T.eq(0, W.named('fh:homestead:claimed')); T.eq(0, W.named('fh:homestead:lot_bought'))
            T.eq(false, W.logged('MONEY LOST'), stage .. ': refund worked, no MONEY LOST')
            W.consistent()
            W.fail[stage] = nil
            T.same({ true, 'lot_b' }, { W.buyAt(1, 'lot_b') }, stage .. ': buyable after')
            T.eq(1, #W.credits, stage .. ': no second refund')
        end
    end)

    case('refund credit itself fails: MONEY LOST logged once with amount + citizenid', function()
        local W = newWorld()
        W.fail.insert_plot, W.fail.credit = true, true
        T.same({ false, 'fh_claim_failed' }, { W.buyAt(1, 'lot_a') })
        T.eq(1, #W.credits)
        local n = 0
        for _, m in ipairs(W.logs) do if m:find('MONEY LOST') and m:find('%$300') and m:find('citizenid=A') then n = n + 1 end end
        T.eq(1, n)
    end)

    case('rollback DELETE also fails: refunded once, row kept and flagged for an admin unclaim', function()
        local W = newWorld()
        W.fail.insert_chest, W.fail.delete_plot = true, 'throw'
        T.same({ false, 'fh_claim_failed' }, { W.buyAt(1, 'lot_a') })
        T.eq(1, #W.credits); T.eq(300, W.credits[1].amount); T.eq(0, #W.reps)
        assert(W.logged('still held'), 'admin unclaim hint logged')
        W.consistent()
    end)

    case('second lot refused BEFORE any charge (fh_already_has_lot), cash untouched', function()
        local W = newWorld()
        T.same({ true, 'lot_a' }, { W.buyAt(1, 'lot_a') })
        T.same({ false, 'fh_already_has_lot' }, { W.buyAt(1, 'lot_b') })
        T.eq(1, #W.charges); T.eq(700, W.cash.A); T.eq(1, #W.reps)
        -- someone else's lot: taken, also before the charge
        T.same({ false, 'fh_plot_taken' }, { W.buyAt(2, 'lot_a') })
        T.eq(1000, W.cash.B); T.eq(1, #W.charges)
        W.consistent()
    end)

    case('two buys in the same tick: one charge (reservation is taken before the charge yields)', function()
        local W = newWorld()
        W.hold.charge = true
        W.at(1, 'lot_a')
        local h = W.start(function() return W.ex.buyLot(1) end)
        T.eq(false, h.done)
        T.same({ false, 'fh_already_has_lot' }, { W.buyAt(1, 'lot_b') }) -- same character, other lot
        T.same({ false, 'fh_plot_taken' }, { W.buyAt(2, 'lot_a') })      -- other character, same lot
        T.same({ false, 'fh_claim_busy' }, { W.ex.unclaim(0, 'lot_a') })  -- admin cannot clear it mid-buy
        T.same({ true, 'lot_a' }, { W.finish(h) })
        T.eq(1, #W.charges); T.eq(700, W.cash.A); T.eq(1000, W.cash.B)
        W.consistent()
        -- same tick, held at the DB write instead (after the charge)
        local W2 = newWorld()
        W2.hold.insert_plot = true
        W2.at(1, 'lot_a')
        local h2 = W2.start(function() return W2.ex.buyLot(1) end)
        T.same({ false, 'fh_already_has_lot' }, { W2.buyAt(1, 'lot_b') })
        T.same({ true, 'lot_a' }, { W2.finish(h2) })
        T.eq(1, #W2.charges)
    end)

    case('a claim owner can still buy a lot; getPlot(cid) stays the claim; the claim path charges nothing', function()
        local W = newWorld()
        T.same({ true, 'claim_a' }, { W.claimAt(1, 'claim_a') })
        T.eq(0, #W.charges); T.eq(0, #W.reps)
        T.same({ true, 'lot_a' }, { W.buyAt(1, 'lot_a') })
        T.eq('claim_a', W.ex.getPlot('A')); T.eq('lot_a', W.ex.getPlot('A', 'town_lot'))
        T.eq(1, #W.charges)
        -- releasing the claim does not touch rep or money
        T.same({ true, 'claim_a' }, { W.ex.unclaim(1) })
        T.eq(1, #W.reps); T.eq(700, W.cash.A); T.eq(0, #W.credits)
        W.consistent()
    end)

    case('rep loop: buy, abandon, buy = net +25 rep; abandon gives no money back', function()
        local W = newWorld()
        T.same({ true, 'lot_a' }, { W.buyAt(1, 'lot_a') })
        T.eq(25, W.repOf('A', 'heartlands')); T.eq(700, W.cash.A)
        T.same({ true, 'lot_a' }, { W.ex.unclaim(1, 'lot_a') }) -- owner abandons their lot
        T.eq(0, W.repOf('A', 'heartlands'))
        T.eq(700, W.cash.A, 'abandon: no money back'); T.eq(0, #W.credits)
        T.same({ citizenid = 'A', region = 'heartlands', delta = -25, reason = 'town_lot_abandon' }, W.reps[2])
        T.eq(nil, W.db.plots.lot_a); T.eq(nil, W.ex.getPlot('A', 'town_lot'))
        T.same({ true, 'lot_a' }, { W.buyAt(1, 'lot_a') })
        T.eq(25, W.repOf('A', 'heartlands'), 'net one bump')
        T.eq(400, W.cash.A); T.eq(2, #W.charges); T.eq(0, #W.credits)
        W.consistent()
    end)

    case('owner abandon refused (fh_rep_failed) when the rep-back fails: lot, row, rep all unchanged', function()
        local W = newWorld()
        W.buyAt(1, 'lot_a')
        W.fail.rep = true
        T.same({ false, 'fh_rep_failed' }, { W.ex.unclaim(1, 'lot_a') })
        T.same({ citizenid = 'A', class = 'town_lot' }, W.db.plots.lot_a); T.eq('lot_a', W.ex.getPlot('A', 'town_lot'))
        T.eq(25, W.repOf('A', 'heartlands'))
        W.fail.rep = nil
        T.same({ true, 'lot_a' }, { W.ex.unclaim(1, 'lot_a') }, 'not stuck busy')
        T.eq(0, W.repOf('A', 'heartlands'))
        W.consistent()
    end)

    case('admin abandon, owner online: rep taken back from the owner (by their src)', function()
        local W = newWorld()
        W.buyAt(1, 'lot_a')
        T.same({ true, 'lot_a' }, { W.ex.unclaim(0, 'lot_a') })
        T.eq(0, W.repOf('A', 'heartlands')); T.eq(700, W.cash.A)
        -- another player who is an admin clears B's lot: B's rep, not the admin's
        W.admins[1] = true
        W.buyAt(2, 'lot_b')
        T.same({ true, 'lot_b' }, { W.ex.unclaim(1, 'lot_b') })
        T.eq(0, W.repOf('B', 'scarlett_meadows')); T.eq(0, W.repOf('A', 'scarlett_meadows'))
        W.consistent()
    end)

    case('admin abandon, owner offline: released anyway, skipped rep-back logged (cid, region, amount, lot)', function()
        local W = newWorld()
        W.buyAt(1, 'lot_a')
        W.offline[1] = true
        T.same({ true, 'lot_a' }, { W.ex.unclaim(0, 'lot_a') })
        T.eq(nil, W.db.plots.lot_a); T.eq(nil, W.C.ownerOf('lot_a'))
        T.eq(1, W.named('fh:homestead:unclaimed'))
        T.eq(25, W.repOf('A', 'heartlands'), 'no citizenid rep path: rep not taken back')
        local found = false
        for _, m in ipairs(W.logs) do
            if m:find('without rep%-back') and m:find('lot_a') and m:find('citizenid=A') and m:find('region=heartlands')
                and m:find('amount=%-25') and m:find('owner_offline') then found = true end
        end
        assert(found, 'skipped rep-back logged: ' .. table.concat(W.logs, ' | '))
        -- admin with the owner online but the rep call failing: still released, also logged
        W.offline[1] = nil
        W.buyAt(2, 'lot_b')
        W.fail.rep = true
        T.same({ true, 'lot_b' }, { W.ex.unclaim(0, 'lot_b') })
        assert(W.logged('lot_b released by admin without rep%-back'))
        W.consistent()
    end)

    case('abandon DELETE fails after the rep-back: rep given back, lot kept; 0 rows = lot gone, rep stays taken', function()
        local W = newWorld()
        W.buyAt(1, 'lot_a')
        W.fail.delete_plot = 'throw'
        T.same({ false, 'fh_unclaim_failed' }, { W.ex.unclaim(1, 'lot_a') })
        T.eq(25, W.repOf('A', 'heartlands')); T.eq('lot_a', W.ex.getPlot('A', 'town_lot'))
        W.fail.delete_plot = nil
        W.consistent()
        W.db.plots.lot_a = nil -- row removed by hand outside the server
        T.same({ false, 'fh_unclaim_failed' }, { W.ex.unclaim(1, 'lot_a') })
        T.eq(0, W.repOf('A', 'heartlands')); T.eq(nil, W.ex.getPlot('A', 'town_lot'))
        W.consistent()
    end)

    case('rep failing on purchase does not undo the buy (logged, no refund)', function()
        local W = newWorld()
        W.fail.rep = true
        T.same({ true, 'lot_a' }, { W.buyAt(1, 'lot_a') })
        T.eq(0, #W.credits); T.eq(700, W.cash.A); T.eq(0, W.repOf('A', 'heartlands'))
        assert(W.logged('rep %+25 in heartlands failed'))
        W.consistent()
    end)

    case('fh_lot_unpriced: price 0 / non-integer / no price anywhere -> refused before any charge, nothing reserved', function()
        local W = newWorld()
        T.same({ false, 'fh_lot_unpriced' }, { W.buyAt(1, 'lot_zero') })
        T.same({ false, 'fh_lot_unpriced' }, { W.buyAt(1, 'lot_frac') })
        local saved = cfg.townLot
        cfg.townLot = nil -- no default price and the plot has none
        local ok, a, b = pcall(function() return W.buyAt(1, 'lot_a') end)
        cfg.townLot = saved
        assert(ok, tostring(a))
        T.same({ false, 'fh_lot_unpriced' }, { a, b })
        T.eq(0, #W.charges); T.eq(0, #W.reps); T.eq(1000, W.cash.A)
        T.eq(nil, W.C.ownerOf('lot_zero')); T.eq(nil, W.C.ownerOf('lot_a')); T.eq(nil, W.ex.getPlot('A', 'town_lot'))
        T.same({ true, 'lot_a' }, { W.buyAt(1, 'lot_a') }, 'nothing left reserved or busy')
        W.consistent()
    end)

    case('lock held through rep + events: unclaim while buyLot awaits rep = fh_claim_busy; claimed/lot_bought before unclaimed', function()
        local W = newWorld()
        W.hold.rep = true
        W.at(1, 'lot_a')
        local h = W.start(function() return W.ex.buyLot(1) end)
        T.eq(false, h.done, 'held in rep')
        T.same({ citizenid = 'A', class = 'town_lot' }, W.db.plots.lot_a) -- written already
        T.same({ false, 'fh_claim_busy' }, { W.ex.unclaim(0, 'lot_a') })  -- admin
        T.same({ false, 'fh_claim_busy' }, { W.ex.unclaim(1, 'lot_a') })  -- owner
        T.same({ false, 'fh_plot_taken' }, { W.buyAt(2, 'lot_a') })
        T.eq(0, W.named('fh:homestead:unclaimed')); T.eq(0, W.named('fh:homestead:claimed'))
        T.same({ true, 'lot_a' }, { W.finish(h) })
        T.same({ true, 'lot_a' }, { W.ex.unclaim(1, 'lot_a') }, 'lock released after the events')
        local order = {}
        for _, e in ipairs(W.events) do order[#order + 1] = e.name end
        T.same({ 'fh:homestead:claimed', 'fh:homestead:lot_bought', 'fh:homestead:unclaimed' }, order)
        T.eq(0, W.repOf('A', 'heartlands')); T.eq(1, #W.charges); T.eq(0, #W.credits)
        W.consistent()
    end)

    case('a throw after the lot is written (event handler) keeps the buy, logs, and releases the lock', function()
        local W = newWorld()
        W.fail.eventThrows = 'fh:homestead:lot_bought'
        T.same({ true, 'lot_a' }, { W.buyAt(1, 'lot_a') })
        W.fail.eventThrows = nil
        assert(W.logged('rep/events after the purchase errored'))
        T.eq(0, #W.credits); T.eq(25, W.repOf('A', 'heartlands'))
        T.same({ true, 'lot_a' }, { W.ex.unclaim(1, 'lot_a') }, 'not stuck busy')
        W.consistent()
    end)

    case('rsg-core throws during the abandon rep-back: owner treated offline, admin release goes through, lock released', function()
        local W = newWorld()
        W.buyAt(1, 'lot_a')
        W.fail.getPlayerThrows = true
        T.same({ true, 'lot_a' }, { W.ex.unclaim(0, 'lot_a') })
        W.fail.getPlayerThrows = nil
        assert(W.logged('lot_a released by admin without rep%-back.*owner_offline'))
        T.eq(25, W.repOf('A', 'heartlands'))
        T.eq(nil, W.db.plots.lot_a)
        T.same({ true, 'lot_a' }, { W.buyAt(2, 'lot_a') }, 'lock released')
        -- a throw while buying (rep guard): rep skipped and logged, buy stands, lock released
        local W2 = newWorld()
        W2.hold.insert_chest = true
        W2.at(1, 'lot_a')
        local h = W2.start(function() return W2.ex.buyLot(1) end)
        W2.fail.getPlayerThrows = true
        T.same({ true, 'lot_a' }, { W2.finish(h) })
        W2.fail.getPlayerThrows = nil
        T.eq(0, W2.repOf('A', 'heartlands'))
        assert(W2.logged('rep %+25 in heartlands failed %(character_changed%)'))
        T.same({ true, 'lot_a' }, { W2.ex.unclaim(0, 'lot_a') }, 'lock released')
    end)
end)

T.finish()

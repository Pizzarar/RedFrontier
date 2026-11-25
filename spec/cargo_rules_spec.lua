-- Run from repo root: `lua spec/cargo_rules_spec.lua` (or via tools/run-specs.py).
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local case = T.it
local R = dofile(here .. '../server/resources/[fh]/fh_cargo/shared/cargo_rules.lua')
local cfg = dofile(here .. '../server/resources/[fh]/fh_core/config.lua')
local C = require('containers')

local me = { x = 0, y = 0, z = 0 }
local crate = { name = 'test_cargo_crate', amount = 2, weight = 20000, unique = true, size_class = 'cargo' }
local bread = { name = 'bread', amount = 3, weight = 100, size_class = 'pocket' }
local function sizeClassOf(name, item) return item and item.size_class end

local function plan(over)
    local p = {
        dir = 'load', slot = 1, citizenid = 'C1', playerCoords = me, sizeClassOf = sizeClassOf,
        wagon = { id = 'C1:t2', owner = 'C1', tier = 't2', coords = { x = 2, y = 0, z = 0 } },
        open = { type = 'chest', id = 'fh:chest:p:1', coords = { x = 1, y = 0, z = 0 }, slots = 50,
            items = { [1] = crate } },
    }
    for k, v in pairs(over or {}) do p[k] = v end
    return p
end
local function why(p) local pl, r = R.planTransfer(p); return pl and 'ok' or r end

case('tiers: slots, weight and speed strictly rise by tier; T3 stays within fh_core wagon capacity', function()
    local prev
    for _, k in ipairs(R.ORDER) do
        local t = R.TIERS[k]
        assert(t.slots > 0 and t.maxWeight > 0 and t.speed > 0)
        if prev then assert(t.slots > prev.slots and t.maxWeight > prev.maxWeight, 'capacity rises') end
        if prev then assert(t.speed < prev.speed, 'bigger wagon is slower') end
        prev = t
    end
    assert(R.TIERS.t3.slots <= cfg.Containers.wagon.slots and R.TIERS.t3.maxWeight <= cfg.Containers.wagon.maxWeight)
    assert(C.interactDistance('wagon') == R.DEFAULT_REACH, 'wagon reach matches fh_core')
end)
case('parseTier: key, number, name; junk refused', function()
    assert(R.parseTier('t2').key == 't2' and R.parseTier('T3').key == 't3' and R.parseTier('1').key == 't1')
    assert(R.parseTier('cart').key == 't1' and R.parseTier('freight').key == 't3')
    local t, e = R.parseTier('t9')
    assert(t == nil and e == 'fh_bad_tier')
    assert(select(2, R.parseTier(nil)) == 'fh_bad_tier')
end)
case('wagonId / stashId', function()
    assert(R.wagonId('C1', 't2') == 'C1:t2' and R.wagonId('', 't2') == nil and R.wagonId('C1', 'x') == nil)
    assert(R.stashId('C1:t2') == 'fh:wagon:C1:t2' and R.stashId('') == nil and R.stashId(nil) == nil)
end)
case('speedLimit: full speed empty, slowed linearly, clamped when overloaded', function()
    assert(R.speedLimit('t1', 0) == 8.0)
    local half = R.speedLimit('t1', 60000)
    assert(math.abs(half - 8.0 * 0.8) < 1e-9)
    assert(math.abs(R.speedLimit('t1', 9e9) - 8.0 * 0.6) < 1e-9)
    assert(R.speedLimit('t1', -5) == 8.0 and R.speedLimit('nope', 0) == nil)
end)
case('canUseWagon: owner and reach', function()
    local w = { owner = 'C1', coords = { x = 3, y = 0, z = 0 } }
    assert(R.canUseWagon(w, 'C1', me))
    local ok, r = R.canUseWagon(w, 'C2', me)
    assert(not ok and r == 'fh_not_owner')
    ok, r = R.canUseWagon(w, 'C1', { x = 50, y = 0, z = 0 })
    assert(not ok and r == 'fh_out_of_reach')
    ok, r = R.canUseWagon(w, 'C1', nil)
    assert(not ok and r == 'fh_no_player_coords')
    ok, r = R.canUseWagon({ owner = 'C1' }, 'C1', me)
    assert(not ok and r == 'fh_no_coords')
    ok, r = R.canUseWagon(nil, 'C1', me)
    assert(not ok and r == 'fh_no_wagon')
    assert(not R.canUseWagon(w, nil, me), 'no character never owns')
end)
case('parseTransferArgs', function()
    T.same({ dir = 'load', slot = 3, amount = 2 }, R.parseTransferArgs({ 'load', '3', '2' }))
    T.same({ dir = 'unload', slot = 1 }, R.parseTransferArgs({ 'unload', '1' }))
    assert(select(2, R.parseTransferArgs({ 'drop', '1' })) == 'fh_bad_dir')
    assert(select(2, R.parseTransferArgs({ 'load', '0' })) == 'fh_bad_slot')
    assert(select(2, R.parseTransferArgs({ 'load', 'x' })) == 'fh_bad_slot')
    assert(select(2, R.parseTransferArgs({ 'load', '1', '-2' })) == 'fh_bad_amount')
    assert(select(2, R.parseTransferArgs({ 'load', '1', '1.5' })) == 'fh_bad_amount')
end)
case('planTransfer load: chest -> own wagon, whole stack by default', function()
    local pl = R.planTransfer(plan())
    T.same({ fromRef = { type = 'chest', id = 'fh:chest:p:1' }, toRef = { type = 'wagon', id = 'fh:wagon:C1:t2' },
        fromSlot = 1, toSlot = 1, amount = 2, name = 'test_cargo_crate' }, pl)
    assert(R.planTransfer(plan({ amount = 1 })).amount == 1)
end)
case('planTransfer unload: wagon -> open chest', function()
    local pl = R.planTransfer(plan({ dir = 'unload', wagonView = { items = { [4] = crate } }, slot = 4,
        open = { type = 'chest', id = 'c', coords = { x = 1, y = 0, z = 0 }, slots = 3, items = {} } }))
    assert(pl and pl.fromRef.type == 'wagon' and pl.toRef.type == 'chest' and pl.fromSlot == 4 and pl.toSlot == 1)
end)
case('planTransfer: only cargo-class items', function()
    local p = plan({ slot = 2 })
    p.open.items[2] = bread
    assert(why(p) == 'fh_not_cargo')
    p.open.items[2] = { name = 'small_safe', amount = 1, weight = 25000, size_class = 'bulky' }
    assert(why(p) == 'fh_not_cargo')
    assert(why(plan({ sizeClassOf = function() return nil end })) == 'fh_not_cargo', 'unknown class is refused')
end)
case('planTransfer: own wagon only, never the client claim', function()
    assert(why(plan({ citizenid = 'C2' })) == 'fh_not_owner')
    assert(why(plan({ wagon = false })) == 'fh_no_wagon')
    assert(why(plan({ citizenid = false })) == 'fh_not_owner')
end)
case('planTransfer: reach to the wagon and to the source container', function()
    local far = { id = 'C1:t2', owner = 'C1', tier = 't2', coords = { x = 40, y = 0, z = 0 } }
    assert(why(plan({ wagon = far })) == 'fh_out_of_reach')
    local p = plan()
    p.open.coords = { x = 30, y = 0, z = 0 }
    assert(why(p) == 'fh_out_of_reach')
    p.open.coords = nil
    assert(why(p) == 'fh_no_coords')
    assert(why(plan({ open = false })) == 'fh_nothing_open')
    assert(why(plan({ playerCoords = false })) == 'fh_no_player_coords')
end)
case('planTransfer: ground-snapped chest uses horizontal reach + vertical snap tolerance; non-snapped stays 3D', function()
    local hint = { x = -496, y = 750, z = 105 }
    local player = { x = -494, y = 750, z = 93 } -- 12 m below hint (within ±13.5 m), 2 m horizontal
    local w = { id = 'C1:t2', owner = 'C1', tier = 't2', coords = { x = -493, y = 750, z = 93 } }
    local p = plan({ playerCoords = player, wagon = w })
    p.open.coords = hint
    assert(why(p) == 'ok')
    -- +12.5 m above hint (e.g. chest snapped +10 m, player on wagon +2.5 m) -> ok
    p.playerCoords = { x = -494, y = 750, z = 117.5 }
    p.wagon = { id = 'C1:t2', owner = 'C1', tier = 't2', coords = { x = -493, y = 750, z = 117.5 } }
    assert(why(p) == 'ok')
    p.playerCoords = { x = -492, y = 750, z = 93 } -- 4 m horizontal
    p.wagon = w
    assert(why(p) == 'fh_out_of_reach')
    p.playerCoords = { x = -494, y = 750, z = 91.4 } -- 13.6 m below hint (beyond ±13.5 m tolerance)
    p.wagon = { id = 'C1:t2', owner = 'C1', tier = 't2', coords = { x = -493, y = 750, z = 91.4 } }
    assert(why(p) == 'fh_out_of_reach')
    p.playerCoords = { x = -494, y = 750, z = 118.6 } -- 13.6 m above hint (beyond ±13.5 m tolerance)
    p.wagon = { id = 'C1:t2', owner = 'C1', tier = 't2', coords = { x = -493, y = 750, z = 118.6 } }
    assert(why(p) == 'fh_out_of_reach')
    -- non-snapped open container (drop_bag) keeps strict 3D
    local p2 = plan({ playerCoords = player, wagon = w })
    p2.open.type = 'drop_bag'
    p2.open.coords = hint
    assert(why(p2) == 'fh_out_of_reach')
end)
case('planTransfer: wagon cannot be the other side; bad inputs', function()
    local p = plan()
    p.open.type = 'wagon'
    assert(why(p) == 'fh_same_container')
    assert(why(plan({ dir = 'x' })) == 'fh_bad_dir')
    assert(why(plan({ slot = 9 })) == 'fh_no_item')
    assert(why(plan({ slot = 0 })) == 'fh_bad_slot')
    assert(why(plan({ amount = 3 })) == 'fh_bad_amount')
    assert(why(plan({ amount = 0 })) == 'fh_bad_amount')
    assert(why(plan({ amount = 1.5 })) == 'fh_bad_amount')
    assert(why(plan({ wagon = { id = 'x', owner = 'C1', tier = 't9', coords = me } })) == 'fh_bad_tier')
end)
case('planTransfer capacity: weight by tier, slots by tier', function()
    -- T1 holds 120 000 g: 7 crates of 20 000 is over.
    local heavy = { name = 'test_cargo_crate', amount = 7, weight = 20000, unique = true, size_class = 'cargo' }
    local t1 = { id = 'C1:t1', owner = 'C1', tier = 't1', coords = { x = 2, y = 0, z = 0 } }
    local p = plan({ wagon = t1 })
    p.open.items[1] = heavy
    assert(why(p) == 'fh_too_heavy')
    p.open.items[1] = { name = 'test_cargo_crate', amount = 6, weight = 20000, unique = true, size_class = 'cargo' }
    assert(why(p) == 'ok', 'exactly at the cap fits')
    -- existing wagon load counts
    p.wagonView = { items = { [1] = { name = 'gold_bar', amount = 1, weight = 12000, size_class = 'cargo' } } }
    assert(why(p) == 'fh_too_heavy')
    -- slots: a full T1 (15 slots) refuses a non-stackable
    local full = {}
    for s = 1, 15 do full[s] = { name = 'barrel_' .. s, amount = 1, weight = 1, unique = true, size_class = 'cargo' } end
    assert(why(plan({ wagon = t1, wagonView = { items = full } })) == 'fh_no_slot')
end)
case('planTransfer: stackable merges onto the same stack, different info does not', function()
    local bar = { name = 'gold_bar', amount = 2, weight = 1000, size_class = 'cargo', info = { stars = 2 } }
    local p = plan({ wagonView = { items = { [3] = { name = 'gold_bar', amount = 5, weight = 1000, size_class = 'cargo',
        info = { stars = 2 } } } } })
    p.open.items[1] = bar
    assert(R.planTransfer(p).toSlot == 3)
    p.wagonView.items[3].info = { stars = 1 }
    assert(R.planTransfer(p).toSlot == 1, 'first free slot instead')
    p.wagonView.items[3].info = nil
    p.open.items[1] = { name = 'gold_bar', amount = 2, weight = 1000, size_class = 'cargo' }
    assert(R.planTransfer(p).toSlot == 3, 'nil info equals empty info')
end)
case('planTransfer: destination container weight cap on unload', function()
    local p = plan({ dir = 'unload', wagonView = { items = { [1] = crate } },
        open = { type = 'chest', id = 'c', coords = { x = 1, y = 0, z = 0 }, slots = 5, maxWeight = 30000, items = {} } })
    assert(why(p) == 'fh_too_heavy')
    p.amount = 1
    assert(why(p) == 'ok')
end)
case('fastTravelVerdict: carrying cargo, wagon with cargo in reach, otherwise fine', function()
    assert(R.fastTravelVerdict({ playerCoords = me, wagons = {} }))
    local ok, r = R.fastTravelVerdict({ carriedCargo = 1, playerCoords = me, wagons = {} })
    assert(not ok and r == 'fh_cargo_carried')
    local near = { id = 'w', coords = { x = 10, y = 0, z = 0 }, cargoCount = 2 }
    local blocked, reason, w = R.fastTravelVerdict({ playerCoords = me, wagons = { near } })
    assert(not blocked and reason == 'fh_cargo_wagon_near' and w == near)
    assert(R.fastTravelVerdict({ playerCoords = me, wagons = { { coords = { x = 10, y = 0, z = 0 }, cargoCount = 0 } } }),
        'empty wagon does not block')
    assert(R.fastTravelVerdict({ playerCoords = me, wagons = { { coords = { x = 500, y = 0, z = 0 }, cargoCount = 3 } } }),
        'loaded wagon far away does not block')
    assert(R.fastTravelVerdict({ playerCoords = me, reach = 5, wagons = { { coords = { x = 10, y = 0, z = 0 }, cargoCount = 1 } } }),
        'custom reach shrinks the zone')
end)

case('planTransfer: stackable flag wins over unique; lowest matching stack; non-stackable takes a free slot', function()
    local function stack(slot) return { name = 'gold_bar', amount = 1, weight = 1000, size_class = 'cargo', stackable = true } end
    local p = plan({ wagonView = { items = { [5] = stack(), [2] = stack() } } })
    p.open.items[1] = { name = 'gold_bar', amount = 1, weight = 1000, size_class = 'cargo', stackable = true }
    assert(R.planTransfer(p).toSlot == 2, 'deterministic: lowest slot, not pairs() order')
    -- same name present, but the incoming item is non-stackable: never merges, first free slot
    p.open.items[1] = { name = 'gold_bar', amount = 1, weight = 1000, size_class = 'cargo', stackable = false }
    assert(R.planTransfer(p).toSlot == 1)
    -- stackable = false with no unique flag still counts as non-stackable
    p.wagonView.items[1] = { name = 'x', amount = 1, weight = 1, size_class = 'cargo' }
    assert(R.planTransfer(p).toSlot == 3)
end)
case('fastTravelVerdict fails closed when a container could not be read', function()
    local ok, r = R.fastTravelVerdict({ unknown = 'fh_inventory_down', carriedCargo = 0, playerCoords = me, wagons = {} })
    assert(not ok and r == 'fh_cargo_unknown')
end)

case('nearestWagon: owner only, in range, nearest of several, dead ignored, range capped', function()
    local function w(id, owner, x) return { id = id, owner = owner, coords = x and { x = x, y = 0, z = 0 } or nil } end
    local list = { w('far', 'C1', 20), w('near', 'C1', 4), w('theirs', 'C2', 1), w('dead', 'C1', nil) }
    local best, d = R.nearestWagon('C1', me, 10, list)
    assert(best.id == 'near' and d == 4, 'nearest own wagon; the closer foreign one is skipped')
    assert(R.nearestWagon('C1', me, 30, list).id == 'near')
    assert(select(2, R.nearestWagon('C1', me, 3, list)) == 'fh_no_wagon', 'out of range')
    assert(R.nearestWagon('C1', me, 100, { w('far', 'C1', 20) }), 'within the 25 m cap')
    assert(select(2, R.nearestWagon('C1', me, 100, { w('far', 'C1', 40) })) == 'fh_no_wagon', 'range capped at 25')
    assert(select(2, R.nearestWagon('C2', me, 10, { w('a', 'C1', 1) })) == 'fh_no_wagon', 'owner only')
    assert(select(2, R.nearestWagon('C1', me, 10, { w('dead', 'C1', nil) })) == 'fh_no_wagon', 'dead ignored')
    assert(select(2, R.nearestWagon('C1', me, 0, list)) == 'fh_bad_range')
    assert(select(2, R.nearestWagon('C1', me, -1, list)) == 'fh_bad_range')
    assert(select(2, R.nearestWagon('C1', me, 'x', list)) == 'fh_bad_range')
    assert(select(2, R.nearestWagon('C1', me, 0 / 0, list)) == 'fh_bad_range')
    assert(select(2, R.nearestWagon('C1', nil, 10, list)) == 'fh_no_player_coords')
    assert(select(2, R.nearestWagon(nil, me, 10, list)) == 'fh_no_character')
    assert(select(2, R.nearestWagon('C1', me, 10, nil)) == 'fh_no_wagon', 'junk list does not throw')
end)

T.finish()

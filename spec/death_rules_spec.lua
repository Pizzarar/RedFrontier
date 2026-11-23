-- Run from repo root: `lua spec/death_rules_spec.lua` (or via tools/run-specs.py).
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local case = T.it
local R = dofile(here .. '../server/resources/[fh]/fh_death/shared/death_rules.lua')

local function why(ok, r) return not ok and r or nil end

case('onDeath: alive -> dead once, returns the life number', function()
    local s = R.newState()
    local ok, life = R.onDeath(s, 'C1', 0, 100)
    assert(ok and life == 1)
    assert(R.isDead(s, 'C1'))
end)
case('onDeath: repeated / duplicated events for one life are refused (one death = one drop)', function()
    local s = R.newState()
    assert(R.onDeath(s, 'C1', 0, 100))
    assert(why(R.onDeath(s, 'C1', 0, 100)) == 'fh_already_dead')  -- same tick (concurrent handler)
    assert(why(R.onDeath(s, 'C1', 0, 109)) == 'fh_already_dead')  -- RSG re-report after MinSecondsBetween
    assert(why(R.onDeath(s, 'C1', -5, 500)) == 'fh_already_dead') -- still lying dead minutes later
end)
case('onDeath: server-read health must say dead (client report alone is not enough)', function()
    local s = R.newState()
    assert(why(R.onDeath(s, 'C1', 150, 100)) == 'fh_not_dead')
    assert(why(R.onDeath(s, 'C1', nil, 100)) == 'fh_not_dead')
    assert(why(R.onDeath(s, 'C1', 0 / 0, 100)) == 'fh_not_dead')
    assert(not R.isDead(s, 'C1'))
    assert(why(R.onDeath(s, '', 0, 100)) == 'fh_no_character')
    assert(why(R.onDeath(s, nil, 0, 100)) == 'fh_no_character')
end)
case('onAlive: needs health > 0 and the minimum dead time; then a new life may drop again', function()
    local s = R.newState()
    assert(R.onDeath(s, 'C1', 0, 100))
    assert(not R.onAlive(s, 'C1', 0, 200, 5))    -- still dead
    assert(not R.onAlive(s, 'C1', 200, 102, 5))  -- too soon (sync lag flapping)
    assert(R.onAlive(s, 'C1', 200, 106, 5))
    assert(not R.isDead(s, 'C1'))
    assert(not R.onAlive(s, 'C1', 200, 107, 5))  -- already alive: no second flip
    local ok, life = R.onDeath(s, 'C1', 0, 300)
    assert(ok and life == 2)
end)
case('characters are independent; forget resets', function()
    local s = R.newState()
    assert(R.onDeath(s, 'C1', 0, 1))
    assert(R.onDeath(s, 'C2', 0, 1))
    R.forget(s, 'C1')
    assert(not R.isDead(s, 'C1') and R.isDead(s, 'C2'))
    assert(not R.onAlive(s, 'C9', 100, 50, 0))
end)
case('sources: backpack (+ saddlebag when known), never equipped', function()
    local a = R.sources(7, nil)
    assert(#a == 1 and a[1].type == 'backpack' and a[1].id == 7)
    local b = R.sources(7, 'fh:saddle:h1')
    assert(#b == 2 and b[2].type == 'saddlebag' and b[2].id == 'fh:saddle:h1')
    assert(#R.sources(7, '') == 1)
    for _, ref in ipairs(b) do assert(ref.type ~= 'equipped') end
    assert(#R.sources(nil, nil) == 0)
end)
case('isEmpty / contentsOf over snapshots', function()
    assert(R.isEmpty({}))
    assert(R.isEmpty({ {}, {} }))
    assert(R.isEmpty(nil))
    local snaps = { { [6] = { name = 'bread', amount = 3, weight = 100 } }, { [2] = { name = 'saddle', amount = 1, weight = 5000 } } }
    assert(not R.isEmpty(snaps))
    local slots, grams = R.contentsOf(snaps)
    assert(slots == 2 and grams == 5300)
    assert(R.isEmpty({ { [1] = { name = 'x', amount = 0 } } }))
end)
case('bagSize: at least the defaults, grown to fit the contents', function()
    local d = { slots = 30, maxWeight = 1000000 }
    local small = R.bagSize(d, { { [6] = { amount = 1, weight = 10 } } })
    assert(small.slots == 30 and small.maxWeight == 1000000)
    local snap = {}
    for i = 1, 40 do snap[i] = { amount = 1, weight = 50000 } end
    local big = R.bagSize(d, { snap })
    assert(big.slots == 40 and big.maxWeight == 2000000)
end)
case('bagId / expiry', function()
    assert(R.bagId(1700000000, 3) == 'fh:dropbag:1700000000-3')
    assert(R.bagId(1, 1) ~= R.bagId(1, 2))
    assert(#R.bagId(2 ^ 40, 2 ^ 30) <= 100) -- fh_inventory stash ids are capped at 100 chars
    local bag = { expiresAt = R.expiresAt(1000, 30) }
    assert(bag.expiresAt == 2800)
    assert(not R.isExpired(bag, 2799))
    assert(R.isExpired(bag, 2800))
    assert(not R.isExpired({}, 5000))
    assert(not R.isExpired(nil, 5000))
end)
case('canOpen: owner only, within reach', function()
    local bag = { owner = 'C1', coords = { x = 0, y = 0, z = 0 } }
    assert(R.canOpen(bag, 'C1', { x = 1, y = 1, z = 0 }, 3.5))
    assert(why(R.canOpen(bag, 'C2', { x = 1, y = 1, z = 0 }, 3.5)) == 'fh_not_owner')
    assert(why(R.canOpen(bag, 'C1', { x = 3, y = 3, z = 0 }, 3.5)) == 'fh_out_of_reach')
    assert(why(R.canOpen(bag, nil, { x = 0, y = 0, z = 0 }, 3.5)) == 'fh_no_character')
    assert(why(R.canOpen(bag, 'C1', nil, 3.5)) == 'fh_no_player_coords')
    assert(why(R.canOpen(nil, 'C1', { x = 0, y = 0, z = 0 }, 3.5)) == 'fh_no_bag')
end)
case('isLive: busy (mid-drop / mid-delete) and expired bags are not live', function()
    local bag = { owner = 'C1', coords = { x = 0, y = 0, z = 0 }, expiresAt = 100 }
    assert(R.isLive(bag, 99))
    assert(not R.isLive(bag, 100))
    bag.busy = true
    assert(not R.isLive(bag, 50))
    assert(not R.isLive(nil, 50))
    assert(R.isLive({ coords = bag.coords }, 50)) -- no expiresAt: never expires by itself
end)
case('canOpen: refuses an expired bag (e.g. loaded after restart, before the first sweep) and a busy one', function()
    local bag = { owner = 'C1', coords = { x = 0, y = 0, z = 0 }, expiresAt = 100 }
    local at = { x = 1, y = 0, z = 0 }
    assert(R.canOpen(bag, 'C1', at, 3.5, 99))
    assert(why(R.canOpen(bag, 'C1', at, 3.5, 100)) == 'fh_bag_expired')
    assert(why(R.canOpen(bag, 'C1', at, 3.5, 5000)) == 'fh_bag_expired')
    bag.busy = true
    assert(why(R.canOpen(bag, 'C1', at, 3.5, 50)) == 'fh_bag_busy')
end)

T.finish()

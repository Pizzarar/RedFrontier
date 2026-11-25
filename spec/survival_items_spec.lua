-- Run from repo root: `lua spec/survival_items_spec.lua` (or via tools/run-specs.py).
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
package.path = here .. '../server/resources/[fh]/fh_survival/shared/?.lua;' .. package.path
local case = T.it
local I = require('items')
local N = require('needs')

case('item -> buff mapping', function()
    local d = N.DEFAULT_DURATIONS
    local e = I.effectOf('fh_stew', d)
    assert(e.kind == 'food' and e.buff_id == 'well_fed' and e.magnitude == 1.15 and e.duration == d.well_fed)
    e = I.effectOf('fh_jerky', d)
    assert(e.buff_id == 'well_fed' and e.duration == d.well_fed * 0.5)
    e = I.effectOf('fh_canteen', d)
    assert(e.kind == 'canteen' and e.buff_id == 'hydrated' and e.duration == d.hydrated)
    assert(I.effectOf('nope', d) == nil and I.effectOf(nil, d) == nil)
    assert(I.effectOf('fh_stew', { well_fed = -1 }).duration == 3600, 'bad config falls back')
    assert(I.effectOf('fh_stew', { well_fed = 100 }).duration == 100)
end)

case('every usable item maps to a known need buff on the fraction scale', function()
    local known = {}
    for _, id in pairs(N.NEED_BUFF) do known[id] = true end
    for name, u in pairs(I.USE) do
        assert(I.ITEMS[name] or I.isForeign(name), name .. ' neither fh-defined nor foreign')
        assert(known[u.buff], name .. ' unknown buff')
        assert(u.magnitude > 0, name .. ' magnitude')
        assert(u.scale > 0 and u.scale <= 1, name .. ' scale must be a fraction')
    end
    assert(I.ITEMS.fh_canteen.stackable == false, 'canteen carries per-item charges')
end)

case('food/drink map: rows are valid or skipped by registry existence', function()
    local names = {
        bread = true, canned_beans = true, canned_apricots = true, canned_salmon = true,
        cooked_meat = true, stew = true, stew_veg = true, jerky_meat = true, coffee = true, water = true,
    }
    for name in pairs(names) do assert(I.isForeign(name), name .. ' should be foreign') end
    assert(I.isForeign('fh_jerky') == false and I.isForeign('fh_canteen') == false, 'fh items are ours')
    -- all 10 foreign items exist -> nothing skipped; 4 fh + 10 foreign = 14 rows register
    local register, skipped = I.usableRows(function(n) return names[n] == true end)
    assert(#skipped == 0, 'known rsg items must not be skipped')
    assert(#register == 14, '#register = ' .. #register)
    -- a future @crafting/@hunting item that does not exist yet is skipped; our fh items still register
    local r2, s2 = I.usableRows(function() return false end)
    assert(#r2 == 4 and #s2 == 10, 'foreign rows skipped, fh rows kept: ' .. #r2 .. '/' .. #s2)
end)

case('food/drink fractions match the jerky/biscuit/stew scale', function()
    local function scale(name) local u = I.USE[name]; return u and u.scale end
    -- existing fh foods keep their shipped values
    assert(scale('fh_jerky') == 0.5 and scale('fh_biscuit') == 0.35 and scale('fh_stew') == 1.0)
    -- rsg-core food: bread/jerky_meat/cooked_meat sit at hardtack/jerky; stew is a full meal
    assert(scale('bread') == 0.35 and scale('jerky_meat') == 0.5 and scale('cooked_meat') == 0.5)
    assert(scale('canned_beans') == 0.6 and scale('canned_salmon') == 0.6 and scale('canned_apricots') == 0.4)
    assert(scale('stew') == 1.0 and scale('stew_veg') == 0.85)
    -- drinks: water equals a canteen charge; coffee is a smaller cup
    assert(scale('water') == 1.0 and scale('coffee') == 0.6)
    -- target buffs: food -> well_fed, drinks -> hydrated, all consumed (remove 1)
    local d = N.DEFAULT_DURATIONS
    for _, name in ipairs({ 'bread', 'canned_beans', 'canned_apricots', 'canned_salmon', 'cooked_meat', 'stew', 'stew_veg', 'jerky_meat' }) do
        local e = I.effectOf(name, d)
        assert(e.kind == 'food' and e.buff_id == 'well_fed', name)
    end
    for _, name in ipairs({ 'coffee', 'water' }) do
        local e = I.effectOf(name, d)
        assert(e.kind == 'food' and e.buff_id == 'hydrated', name)
    end
end)

case('consume outcome: a failed remove grants no buff, a refused buff refunds', function()
    assert(I.consumeOutcome(false, nil) == 'blocked')
    assert(I.consumeOutcome(nil, true) == 'blocked')
    assert(I.consumeOutcome(true, false) == 'refund')
    assert(I.consumeOutcome(true, nil) == 'refund')
    assert(I.consumeOutcome(true, true) == 'granted')
end)

case('refusal message follows the buff: drinks say drink, food says eat', function()
    assert(I.refuseMessage('hydrated') == 'You cannot drink right now.')
    assert(I.refuseMessage('well_fed') == 'You cannot eat right now.')
    assert(I.refuseMessage(nil) == 'You cannot eat right now.', 'unknown buff defaults to eat')
end)

case('canteen charges: use', function()
    assert(I.charges(nil, 5) == 5 and I.charges({}, 5) == 5, 'fresh canteen is full')
    local ok, info = I.useCanteen({ charges = 3, note = 'x' }, 5)
    assert(ok and info.charges == 2 and info.note == 'x')
    ok, info = I.useCanteen(nil, 5)
    assert(ok and info.charges == 4, 'fresh canteen')
    local a, err = I.useCanteen({ charges = 0 }, 5)
    assert(a == false and err == 'empty')
    a, err = I.useCanteen({ charges = -1 }, 5)
    assert(a == false and err == 'invalid_charges')
    a, err = I.useCanteen({ charges = 9 }, 5)
    assert(a == false and err == 'invalid_charges')
    a, err = I.useCanteen({ charges = 1.5 }, 5)
    assert(a == false and err == 'invalid_charges')
    local src = { charges = 2 }
    I.useCanteen(src, 5)
    assert(src.charges == 2, 'input not mutated')
end)

case('canteen charges: refill', function()
    local ok, info = I.refillCanteen({ charges = 1, k = 'v' }, 5)
    assert(ok and info.charges == 5 and info.k == 'v')
    local a, err = I.refillCanteen({ charges = 5 }, 5)
    assert(a == false and err == 'full')
    a, err = I.refillCanteen(nil, 5)
    assert(a == false and err == 'full', 'fresh canteen is already full')
    a, err = I.refillCanteen({ charges = 'x' }, 5)
    assert(a == false and err == 'invalid_charges')
    a, err = I.refillCanteen({ charges = 1 }, 0)
    assert(a == false and err == 'invalid_max', 'bad max')
    ok, info = I.refillCanteen({ charges = 0 })
    assert(ok and info.charges == N.DEFAULT_CANTEEN_MAX, 'default max')
end)

case('wash cooldown', function()
    assert(I.washReady(nil, 100, 300) == true, 'never washed')
    local ok, rem = I.washReady(100, 200, 300)
    assert(ok == false and rem == 200)
    assert(I.washReady(100, 400, 300) == true, 'exactly at cooldown end')
    ok, rem = I.washReady(100, 399, 300)
    assert(ok == false and rem == 1)
    ok = I.washReady(500, 100, 300)
    assert(ok == false, 'clock backwards still cooling down')
    assert(I.washReady(100, 0 / 0, 300) == false)
    ok, rem = I.washReady(100, 150, 'x')
    assert(ok == false and rem == 250, 'bad cooldown uses default')
    assert(I.washReady(100, 100, 0) == true, 'zero cooldown')
end)

case('water mode flag defaults to the safe path', function()
    assert(I.waterMode(nil) == 'zones' and I.waterMode('zones') == 'zones' and I.waterMode('garbage') == 'zones')
    assert(I.waterMode('native') == 'native')
end)

case('water zones and heat sources', function()
    local zones = { { x = 0, y = 0, radius = 5 }, { x = 100, y = 100, z = 10 } }
    assert(I.inWaterZone({ x = 3, y = 4 }, zones) == true, 'edge, 2D')
    assert(I.inWaterZone({ x = 3.1, y = 4 }, zones) == false)
    assert(I.inWaterZone({ x = 103, y = 100, z = 10 }, zones) == true, 'default radius 6')
    assert(I.inWaterZone({ x = 103, y = 100, z = 30 }, zones) == false, '3D when both have z')
    assert(I.inWaterZone({ x = 0, y = 0 }, {}) == false and I.inWaterZone(nil, zones) == false)
    assert(I.inWaterZone({ x = 0, y = 0 }, { 'bad', { x = 'a', y = 0 } }) == false, 'malformed skipped')
    local fires = { { x = 10, y = 10 } }
    assert(I.nearHeat({ x = 12, y = 10 }, fires) == true, 'default radius 4')
    assert(I.nearHeat({ x = 15, y = 10 }, fires) == false)
    assert(I.nearHeat({ x = 15, y = 10 }, fires, 6) == true, 'passed default radius')
    assert(I.nearHeat({ x = 15, y = 10 }, { { x = 10, y = 10, radius = 6 } }) == true, 'per-source radius')
    assert(I.nearHeat({ x = 10, y = 10 }, nil) == false)
end)

case('ITEMS pass fh_core registerItems validation (B7)', function()
    local saved = _G.FhConfig
    _G.FhConfig = { Items = {} }
    local Core = dofile(here .. '../server/resources/[fh]/fh_core/shared/items.lua')
    Core._reset()
    local ok, err, bad = Core.checkRegister(I.ITEMS, 'fh_survival', function() return false end)
    assert(ok, tostring(err) .. ' / ' .. tostring(bad))
    for name, def in pairs(I.ITEMS) do
        assert(Core.validName(name), name)
        assert(def.illicit == false, name .. ' full 4.1 def has explicit illicit')
    end
    local b = I.ITEMS[I.BEDROLL]
    assert(I.BEDROLL == 'bedroll' and b and b.useable == true and b.illicit == false and b.stackable == false)
    assert(I.USE[I.BEDROLL] == nil, 'bedroll has no buff-on-use entry: server/rest.lua owns it')
    assert(Core.checkRegister({ [I.BEDROLL] = b }, 'fh_survival', function() return false end), 'bedroll passes the validator alone')
    ok, err, bad = Core.register(I.ITEMS, 'fh_survival', nil)
    assert(ok, tostring(err))
    ok = Core.register(I.ITEMS, 'fh_survival', nil) -- re-register after a restart is fine
    assert(ok, 'same owner may re-register')
    ok, err = Core.checkRegister(I.ITEMS, 'someone_else', nil)
    assert(not ok and err == 'fh_duplicate_item')
    Core._reset()
    _G.FhConfig = saved
end)

T.finish()

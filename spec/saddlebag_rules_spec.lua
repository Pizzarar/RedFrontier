-- Run from repo root: `lua spec/saddlebag_rules_spec.lua` (or via tools/run-specs.py).
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local case = T.it
local R = dofile(here .. '../server/resources/[fh]/fh_core/shared/saddlebag_rules.lua')
local S = dofile(here .. '../server/resources/[fh]/fh_core/shared/spawn_rules.lua')
local cfg = dofile(here .. '../server/resources/[fh]/fh_core/config.lua')
local A = dofile(here .. '../server/resources/[fh]/fh_core/shared/admin_args.lua')
-- What fh_core/server/inventory.lua wires at runtime: base RSG items (bread, ...) resolve through
-- RSGCore.Shared.Items, which is where their `unique` (stackable) flag comes from. Without a definition an item
-- cannot resolve as stackable, so rules.canStack would refuse every merge.
local Items = require('items')
Items.sharedLookup = function(name) return name == 'bread' and { label = 'Bread', weight = 100 } or nil end

local horses = R.horseSet(cfg.Saddlebag.HorseModels, S.modelHash)
local me = { x = 0, y = 0, z = 0 }
local function horse(over)
    local h = { exists = true, entityType = 1, isPlayer = false, model = S.modelHash('a_c_horse_morgan_bay'),
        coords = { x = 2, y = 0, z = 0 } }
    for k, v in pairs(over or {}) do h[k] = v end
    return h
end
local function why(ok, r) return not ok and r or nil end
local function access(h, c) return R.canAccess('C1', h, c or me, 3.5, horses) end

case('stashId: per character, nil without one', function()
    assert(R.stashId('ABC123') == 'fh:saddle:ABC123')
    assert(R.stashId('') == nil and R.stashId(nil) == nil and R.stashId(5) == nil)
end)
case('config: the fh_spawn_horse default model is on the allowlist', function()
    assert(horses[S.modelHash(A.DEFAULT_MODELS.horse)], 'fh_spawn_horse default must pass the horse check')
end)
case('u32: signed model normalizes, junk is nil', function()
    assert(R.u32(-1) == 4294967295 and R.u32(5) == 5)
    assert(R.u32(1.5) == nil and R.u32('x') == nil and R.u32(2 ^ 40) == nil and R.u32(0 / 0) == nil)
end)
case('canAccess: horse within reach, signed model hash accepted', function()
    assert(access(horse()))
    assert(access(horse({ coords = { x = 3.5, y = 0, z = 0 } }))) -- edge
    assert(access(horse({ coords = me }))) -- mounted
    local h = S.modelHash('a_c_horse_morgan_bay')
    assert(access(horse({ model = h >= 2147483648 and h - 4294967296 or h })))
end)
case('canAccess: too far', function()
    assert(why(access(horse({ coords = { x = 3.6, y = 0, z = 0 } }))) == 'fh_out_of_reach')
    assert(why(access(horse({ coords = { x = 0, y = 0, z = 9 } }))) == 'fh_out_of_reach')
end)
case('canAccess: not a horse (type, player, model) fails', function()
    assert(why(access(horse({ entityType = 2 }))) == 'fh_not_a_horse')   -- vehicle
    assert(why(access(horse({ entityType = 3 }))) == 'fh_not_a_horse')   -- object
    assert(why(access(horse({ isPlayer = true }))) == 'fh_not_a_horse')
    assert(why(access(horse({ model = S.modelHash('g_m_m_unibanditos_01') }))) == 'fh_not_a_horse')
    assert(why(access(horse({ model = 'x' }))) == 'fh_not_a_horse')
    assert(why(R.canAccess('C1', horse(), me, 3.5, nil)) == 'fh_not_a_horse') -- no allowlist: fail closed
end)
case('canAccess: no entity, no character, bad coords/reach fail closed', function()
    assert(why(R.canAccess('C1', nil, me, 3.5, horses)) == 'fh_no_horse')
    assert(why(access({ exists = false })) == 'fh_no_horse')
    assert(why(R.canAccess(nil, horse(), me, 3.5, horses)) == 'fh_no_character')
    assert(why(access(horse({ coords = { x = 0 / 0, y = 0, z = 0 } }))) == 'fh_no_player_coords')
    assert(why(R.canAccess('C1', horse(), nil, 3.5, horses)) == 'fh_no_player_coords')
    assert(why(R.canAccess('C1', horse(), me, nil, horses)) == 'fh_out_of_reach')
end)

-- ---- planTransfer
local function plan(over)
    local a = {
        citizenid = 'C1', horse = horse(), playerCoords = me, reach = 3.5, horses = horses, dir = 'in', slot = 2,
        open = { type = 'chest', id = 'fh:chest:p:1', coords = { x = 1, y = 0, z = 0 }, slots = 50, reach = 3.5,
            items = { [2] = { name = 'small_safe', amount = 1 }, [3] = { name = 'bread', amount = 4 } } },
        bag = { slots = 20, items = { [1] = { name = 'bread', amount = 2 } } },
    }
    for k, v in pairs(over or {}) do a[k] = v end
    return R.planTransfer(a)
end
case('planTransfer in: first free slot; stackables go to the existing stack', function()
    local p = plan()
    assert(p.dir == 'in' and p.fromSlot == 2 and p.toSlot == 2 and p.amount == nil)
    p = plan({ slot = 3, amount = 2 })
    assert(p.toSlot == 1 and p.amount == 2, 'bread joins the bread stack in slot 1')
end)
case('planTransfer out: from the saddlebag into the open container', function()
    local p = plan({ dir = 'out', slot = 1 })
    assert(p.dir == 'out' and p.fromSlot == 1 and p.toSlot == 3, 'bread joins the chest bread stack')
end)
case('planTransfer: unique items never merge, a full destination has no slot', function()
    local full = { slots = 1, items = { [1] = { name = 'worn_rifle', unique = true, amount = 1 } } }
    local o = { type = 'chest', id = 'x', coords = me, slots = 5, reach = 3.5,
        items = { [1] = { name = 'worn_rifle', unique = true, amount = 1 } } }
    assert(why(plan({ open = o, bag = full, slot = 1 })) == 'fh_no_slot')
end)
case('planTransfer: reach to BOTH containers is enforced', function()
    assert(why(plan({ horse = horse({ coords = { x = 9, y = 0, z = 0 } }) })) == 'fh_out_of_reach')
    local o = { type = 'chest', id = 'x', coords = { x = 9, y = 0, z = 0 }, slots = 5, reach = 3.5, items = { [2] = { name = 'a' } } }
    assert(why(plan({ open = o })) == 'fh_out_of_reach')
    o.coords = nil
    assert(why(plan({ open = o })) == 'fh_no_coords')
end)
case('planTransfer: horse rule applies, container must be the open one and not the bag itself', function()
    assert(why(plan({ horse = horse({ entityType = 2 }) })) == 'fh_not_a_horse')
    assert(why(plan({ open = false })) == 'fh_nothing_open')
    assert(why(plan({ open = { type = 'saddlebag', id = 'fh:saddle:C1', coords = me, reach = 3.5 } })) == 'fh_same_container')
end)
case('planTransfer: bad direction, slot, amount, empty source slot', function()
    assert(why(plan({ dir = 'sideways' })) == 'fh_bad_dir')
    assert(why(plan({ slot = 0 })) == 'fh_bad_slot')
    assert(why(plan({ slot = 1.5 })) == 'fh_bad_slot')
    assert(why(plan({ slot = 'a' })) == 'fh_bad_slot')
    assert(why(plan({ amount = 0 })) == 'fh_bad_amount')
    assert(why(plan({ amount = -3 })) == 'fh_bad_amount')
    assert(why(plan({ slot = 40 })) == 'fh_no_item')
end)
case('pickSlot: same name but different info is not a merge target (first free slot instead)', function()
    local bag = { slots = 4, items = {
        [1] = { name = 'bread', amount = 2, info = { condition = 90 } },
        [2] = { name = 'bread', amount = 2, info = { condition = 50 } } } }
    assert(R.pickSlot(bag, { name = 'bread', amount = 1, info = { condition = 10 } }) == 3)
end)
case('pickSlot: same name and equal info, stackable -> that stack', function()
    local bag = { slots = 3, items = {
        [1] = { name = 'bread', amount = 2 },
        [2] = { name = 'bread', amount = 2, info = { condition = 50 } } } }
    assert(R.pickSlot(bag, { name = 'bread', amount = 1 }) == 1)
    assert(R.pickSlot(bag, { name = 'bread', amount = 1, info = { condition = 50 } }) == 2)
end)
case('pickSlot: non-stackable item never merges', function()
    Items.define('fh_spec_unique', { label = 'Spec Unique', weight = 100, size_class = 'pocket', stackable = false })
    local bag = { slots = 3, items = { [1] = { name = 'fh_spec_unique', amount = 1 } } }
    assert(R.pickSlot(bag, { name = 'fh_spec_unique', amount = 1 }) == 2)
end)
case('planTransfer: a same-name stack with different info does not absorb the transfer', function()
    local o = { type = 'chest', id = 'x', coords = me, slots = 5, reach = 3.5,
        items = { [1] = { name = 'bread', amount = 4, info = { condition = 90 } } } }
    local p = plan({ open = o, slot = 1, bag = { slots = 4,
        items = { [1] = { name = 'bread', amount = 2, info = { condition = 10 } } } } })
    assert(p.toSlot == 2, 'first free bag slot, not the occupied cond-10 stack at 1')
end)

T.finish()

-- Run from repo root: `lua spec/crafting_inv_spec.lua` (or via tools/run-specs.py).
-- fh_crafting/server/inv.lua against a fake fh_core (core-03 carried refs, setItemInfo expectName).
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local describe, it, eq = T.describe, T.it, T.eq
local base = here .. '../server/resources/[fh]/fh_crafting/'
FhCraftFlow = dofile(base .. 'shared/craft_flow.lua')

local calls, core
GetResourceState = function() return 'started' end
exports = setmetatable({}, { __index = function(_, res)
    return setmetatable({}, { __index = function(_, fn)
        local f = core[fn]
        if not f then error('No such export ' .. fn) end
        return function(_, ...) calls[#calls + 1] = { fn = fn, args = table.pack(...) }; return f(...) end
    end })
end })
dofile(base .. 'server/inv.lua')
local I = FhCraftInv

local function fresh(c) calls = {}; core = c end

describe('carried refs use `type`', function()
    it('count / take / give address { type, id = src } (never kind)', function()
        fresh({
            snapshot = function(ref) if ref.type == 'backpack' then return { [20] = { name = 'lead', amount = 5 } } end return {} end,
            removeItem = function() return true end,
            addItem = function() return true end,
        })
        eq(5, I.count(9, 'lead'))
        eq(true, I.take(9, 'lead', 2))
        eq(true, I.give(9, 'gun_parts', 1))
        for _, c in ipairs(calls) do
            local ref = c.args[1]
            eq(true, ref.type == 'equipped' or ref.type == 'backpack'); eq(9, ref.id); eq(nil, ref.kind)
        end
    end)
    it('offline src and bulky veto pass fh_core reasons through', function()
        fresh({ removeItem = function() return false, 'fh_player_offline' end,
                addItem = function() return false, 'fh_size_class' end })
        local ok, why = I.removeItem({ type = 'backpack', id = 9 }, 'lead', 1)
        eq(false, ok); eq('fh_player_offline', why)
        ok, why = I.addItem({ type = 'backpack', id = 9 }, 'worn_rifle', 1)
        eq(false, ok); eq('fh_size_class', why)
    end)
end)

describe('setInfo -> fh_core setItemInfo', function()
    it('passes ref, slot, info and expectName', function()
        fresh({ setItemInfo = function() return true end })
        eq(true, I.setInfo(9, 4, { condition = 60 }, 'worn_rifle'))
        eq('setItemInfo', calls[1].args and calls[1].fn)
        eq('equipped', calls[1].args[1].type); eq(9, calls[1].args[1].id)
        eq(4, calls[1].args[2]); eq(60, calls[1].args[3].condition); eq('worn_rifle', calls[1].args[4])
    end)
    it('slot outside the first section: tries the backpack', function()
        fresh({ setItemInfo = function(ref) if ref.type == 'equipped' then return false, 'fh_bad_slot' end return true end })
        eq(true, I.setInfo(9, 20, {}, 'worn_rifle'))
        eq('backpack', calls[2].args[1].type)
    end)
    it('fh_wrong_item / offline stop at once; export missing is no_set_info', function()
        fresh({ setItemInfo = function() return false, 'fh_wrong_item' end })
        eq('fh_wrong_item', select(2, I.setInfo(9, 4, {}, 'x'))); eq(1, #calls)
        fresh({})
        eq('no_set_info', select(2, I.setInfo(9, 4, {}, 'x')))
    end)
end)

T.finish()

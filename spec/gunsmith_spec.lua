-- Run from repo root: `lua spec/gunsmith_spec.lua` (or via tools/run-specs.py).
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local describe, it, eq = T.describe, T.it, T.eq
local R = dofile(here .. '../server/resources/[fh]/fh_crafting/shared/craft_rules.lua')
local F = dofile(here .. '../server/resources/[fh]/fh_gunsmith/shared/restore_flow.lua')

local function w(cond, stars) return { name = 'worn_rifle', info = { condition = cond, stars = stars } } end

describe('gunsmith plan', function()
    it('fewest parts to reach the cap', function()
        local p = F.plan(w(45, 1), 10, R)
        eq(60, p.to); eq(1, p.parts)
        p = F.plan(w(10, 3), 10, R)
        eq(100, p.to); eq(5, p.parts)
    end)
    it('uses all parts when short of the cap', function()
        local p = F.plan(w(10, 3), 2, R)
        eq(50, p.to); eq(2, p.parts)
    end)
    it('no stars = 1 star cap 60', function()
        local p = F.plan(w(20, nil), 10, R)
        eq(60, p.to); eq(2, p.parts)
    end)
    it('already at cap refuses', function()
        local p, why = F.plan(w(60, 1), 5, R)
        eq(nil, p); eq('at_cap', why)
    end)
    it('no parts refuses', function()
        local p, why = F.plan(w(10, 2), 0, R)
        eq(nil, p); eq('no_parts', why)
    end)
    it('missing item / condition', function()
        eq('no_weapon', select(2, F.plan(nil, 5, R)))
        eq('no_condition', select(2, F.plan({ info = {} }, 5, R)))
    end)
end)

local function mkDeps(o)
    o = o or {}
    local d = { log = {}, item = o.item or w(30, 2), parts = o.parts or 10 }
    d.rules = R
    d.near = function() if o.far then return false, 'no_station' end return true end
    d.slot = function() return d.item end
    d.count = function() return d.parts end
    d.setInfo = function(_, _, info)
        if o.setFails then return false, 'write_failed' end
        d.log[#d.log + 1] = 'set' .. info.condition; return true
    end
    d.take = function(_, _, n)
        if o.takeWhy then return false, o.takeWhy end
        d.log[#d.log + 1] = 'take' .. n; return true
    end
    return d
end

describe('gunsmith flow', function()
    it('writes condition then consumes parts', function()
        local d = mkDeps()
        local ok, res = F.run(d, 1, 1)
        eq(true, ok); eq(80, res.to); eq(3, res.parts)
        eq('set80,take3', table.concat(d.log, ','))
    end)
    it('refuses away from a station without touching anything', function()
        local d = mkDeps({ far = true })
        local ok, why = F.run(d, 1, 1)
        eq(false, ok); eq('no_station', why); eq(0, #d.log)
    end)
    it('failed write consumes nothing', function()
        local d = mkDeps({ setFails = true })
        local ok = F.run(d, 1, 1)
        eq(false, ok); eq(0, #d.log)
    end)
    it('failed take rolls the write back; not_implemented maps to no_remove', function()
        local d = mkDeps({ takeWhy = 'not_implemented' })
        local ok, why = F.run(d, 1, 1)
        eq(false, ok); eq('no_remove', why)
        eq('set80,set30', table.concat(d.log, ','))
    end)
    it('bad slot', function()
        eq('bad_slot', select(2, F.run(mkDeps(), 1, 'x')))
    end)
end)

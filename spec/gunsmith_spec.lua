-- Run from repo root: `lua spec/gunsmith_spec.lua` (or via tools/run-specs.py).
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local describe, it, eq = T.describe, T.it, T.eq
local R = dofile(here .. '../server/resources/[fh]/fh_crafting/shared/craft_rules.lua')
local F = dofile(here .. '../server/resources/[fh]/fh_gunsmith/shared/restore_flow.lua')
local Containers = dofile(here .. '../server/resources/[fh]/fh_core/shared/containers.lua')

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
    d.containers = Containers
    d.playerCoords = function() return o.playerCoords or { x = 0, y = 0, z = 0 } end
    d.open = function()
        if o.nothingOpen then return nil, nil, 'fh_nothing_open' end
        local ref = { type = o.type or 'chest', id = o.id or 'fh:chest:test:1' }
        local coords = o.coords or { x = 0, y = 0, z = 0 }
        if o.noCoords then coords = nil end
        local view = { coords = coords, slots = o.slots or 20, items = {} }
        view.items[o.slot or 1] = d.item
        return ref, view
    end
    d.nearSrc = nil
    d.nearStation = function(src, coords)
        d.nearSrc, d.nearCoords = src, coords
        if o.tooFar then return false, 'no_station' end
        return true
    end
    d.count = function() return d.parts end
    d.setCalls = {}
    d.setInfo = function(ref, slot, info, expectName)
        d.setCalls[#d.setCalls + 1] = { ref = ref, slot = slot, expectName = expectName }
        if o.setWhy then return false, o.setWhy end
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
    it('success on a chest: writes condition then consumes parts', function()
        local d = mkDeps()
        local ok, res = F.run(d, 1, 1)
        eq(true, ok); eq(80, res.to); eq(3, res.parts)
        eq('set80,take3', table.concat(d.log, ','))
    end)
    it('refuses with nothing open without touching anything', function()
        local d = mkDeps({ nothingOpen = true })
        local ok, why = F.run(d, 1, 1)
        eq(false, ok); eq('fh_nothing_open', why); eq(0, #d.log)
    end)
    it('refuses a non-bulky container type without touching anything', function()
        local d = mkDeps({ type = 'backpack' })
        local ok, why = F.run(d, 1, 1)
        eq(false, ok); eq('fh_size_class', why); eq(0, #d.log)
    end)
    it('refuses when the player is out of reach of the container', function()
        local d = mkDeps({ coords = { x = 10, y = 0, z = 0 } })
        local ok, why = F.run(d, 1, 1)
        eq(false, ok); eq('fh_out_of_reach', why); eq(0, #d.log)
    end)
    it('refuses a container with no coords', function()
        local d = mkDeps({ noCoords = true })
        local ok, why = F.run(d, 1, 1)
        eq(false, ok); eq('fh_no_coords', why); eq(0, #d.log)
    end)
    it('refuses a container too far from the bench without touching anything', function()
        local d = mkDeps({ tooFar = true })
        local ok, why = F.run(d, 1, 1)
        eq(false, ok); eq('no_station', why); eq(0, #d.log)
    end)
    it('refuses when the setInfo contract is missing, before taking any parts', function()
        local d = mkDeps({ setWhy = 'no_set_info' })
        local ok, why = F.run(d, 1, 1)
        eq(false, ok); eq('no_set_info', why); eq(0, #d.log)
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
        for _, v in ipairs({ 'x', 0, -1, 1.5, 'inf', '-inf', 'nan', 1e999 }) do
            eq('bad_slot', select(2, F.run(mkDeps(), 1, v)), tostring(v))
        end
        eq('bad_slot', select(2, F.run(mkDeps(), 1, nil)))
    end)
    it('passes a take refusal through and rolls back', function()
        local d = mkDeps({ takeWhy = 'fh_not_registrable' })
        local ok, why = F.run(d, 1, 1)
        eq(false, ok); eq('fh_not_registrable', why)
        eq('set80,set30', table.concat(d.log, ','))
    end)
    it('reports a failed rollback', function()
        local d = mkDeps({ takeWhy = 'fh_not_registrable' })
        local n = 0
        local set = d.setInfo
        d.setInfo = function(...) n = n + 1; if n == 2 then return false, 'gone' end return set(...) end
        local ok, why, meta = F.run(d, 1, 1)
        eq(false, ok); eq('fh_not_registrable', why); eq(true, meta.rollbackFailed); eq('gone', meta.reason)
    end)
end)

describe('gunsmith setInfo + station wiring', function()
    it('passes the weapon item name as expectName on write and rollback', function()
        local d = mkDeps({ takeWhy = 'no_remove' })
        F.run(d, 7, 1)
        eq(2, #d.setCalls)
        eq('worn_rifle', d.setCalls[1].expectName); eq('worn_rifle', d.setCalls[2].expectName)
        eq(1, d.setCalls[1].slot); eq('chest', d.setCalls[1].ref.type)
    end)
    it('nearStation gets the src and the container coords', function()
        local d = mkDeps({ coords = { x = 0.5, y = 0.5, z = 0.5 } })
        F.run(d, 7, 1)
        eq(7, d.nearSrc); eq(0.5, d.nearCoords.z)
    end)
end)

describe('gunsmith restore reach via getStations', function()
    local bench = { plot_id = 1, slot_id = 2, station_type = 'workbench', coords = { x = 10.0, y = 20.0, z = 5.0 } }
    local camp = { plot_id = 1, slot_id = 3, station_type = 'campfire', coords = { x = 10.0, y = 20.0, z = 5.0 } }
    it('container in reach of the own workbench', function()
        eq(true, F.stationInReach({ bench }, { x = 11.0, y = 20.0, z = 5.0 }))
        eq(true, F.stationInReach({ bench }, { x = 13.0, y = 20.0, z = 5.0 })) -- exactly 3.0
    end)
    it('out of reach', function()
        local ok, why = F.stationInReach({ bench }, { x = 14.0, y = 20.0, z = 5.0 })
        eq(false, ok); eq('no_station', why)
    end)
    it('ground-snapped workbench allows vertical snap offset within tolerance', function()
        -- 12 m below bench hint z, 2 m horizontal -> ok
        eq(true, F.stationInReach({ bench }, { x = 12.0, y = 20.0, z = -7.0 }))
        -- 4 m horizontal -> no_station
        eq('no_station', select(2, F.stationInReach({ bench }, { x = 14.0, y = 20.0, z = -7.0 })))
        -- >20 m below bench hint z -> no_station
        eq('no_station', select(2, F.stationInReach({ bench }, { x = 12.0, y = 20.0, z = -15.5 })))
    end)
    it("other player's plot (getStations of the asker has none) / not ready ({}) / nil", function()
        eq('no_station', select(2, F.stationInReach({}, { x = 10.0, y = 20.0, z = 5.0 })))
        eq('no_station', select(2, F.stationInReach(nil, { x = 10.0, y = 20.0, z = 5.0 })))
    end)
    it('only workbenches count (not campfire / tanning_rack)', function()
        eq('no_station', select(2, F.stationInReach({ camp }, { x = 10.0, y = 20.0, z = 5.0 })))
    end)
    it('dev gunsmith station counts, dev reload does not; bad coords refuse', function()
        local dev = { station_type = 'gunsmith', dev = true, coords = { x = 0.0, y = 0.0, z = 0.0 } }
        eq(true, F.stationInReach({ dev }, { x = 1.0, y = 0.0, z = 0.0 }))
        dev.station_type = 'reload'
        eq('no_station', select(2, F.stationInReach({ dev }, { x = 1.0, y = 0.0, z = 0.0 })))
        eq('no_station', select(2, F.stationInReach({ bench }, nil)))
    end)
end)

describe('stationInReach with vector3-like coords', function()
    -- stand-in for cfx vector3: not a table, fields via __index
    local function vec(x, y, z)
        local u = newproxy and newproxy(true)
        if u then
            getmetatable(u).__index = function(_, k) return ({ x = x, y = y, z = z })[k] end
            return u
        end
        return setmetatable({}, { __index = { x = x, y = y, z = z } })
    end
    it('container coords as vector3', function()
        local bench = { station_type = 'workbench', coords = { x = 10.0, y = 20.0, z = 5.0 } }
        eq(true, F.stationInReach({ bench }, vec(11.0, 20.0, 5.0)))
        eq('no_station', select(2, F.stationInReach({ bench }, vec(20.0, 20.0, 5.0))))
    end)
    it('station coords as vector3', function()
        local bench = { station_type = 'workbench', coords = vec(10.0, 20.0, 5.0) }
        eq(true, F.stationInReach({ bench }, { x = 11.0, y = 20.0, z = 5.0 }))
        eq(true, F.stationInReach({ bench }, vec(11.0, 20.0, 5.0)))
    end)
    it('non-finite / missing fields refuse', function()
        local bench = { station_type = 'workbench', coords = { x = 0, y = 0, z = 0 } }
        eq('no_station', select(2, F.stationInReach({ bench }, vec(0/0, 0, 0))))
        eq('no_station', select(2, F.stationInReach({ bench }, 5)))
    end)
end)

T.finish()

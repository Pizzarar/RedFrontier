-- Run from repo root: `lua spec/crafting_stations_spec.lua` (or via tools/run-specs.py).
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local describe, it, eq = T.describe, T.it, T.eq
local base = here .. '../server/resources/[fh]/fh_crafting/'
FhCraftingConfig = dofile(base .. 'config.lua')
FhCraftRules = dofile(base .. 'shared/craft_rules.lua')
FhCraftFlow = dofile(base .. 'shared/craft_flow.lua')
dofile(base .. 'server/stations.lua')
local S = FhCraftStations
local cfg = FhCraftingConfig
local dev = cfg.devStations.gunsmith
local atDev = { x = dev.x, y = dev.y, z = dev.z }
local far = { x = 0.0, y = 0.0, z = 0.0 }

-- o: state ('started'|'missing'), dev, near (H3 result), throws, noExport, coords
local function mk(o)
    local calls, logs = {}, {}
    local env = {
        resourceState = function() return o.state or 'started' end,
        callExport = function(res, fn, ...)
            calls[#calls + 1] = { res = res, fn = fn, args = table.pack(...) }
            if o.noExport then error('No such export ' .. fn .. ' in resource ' .. res) end
            if o.throws then error('boom') end
            if fn == 'isNearStation' then return o.near end
            if fn == 'getStations' then return o.list or {} end
            if fn == 'stationAt' then return o.at end
        end,
        devOn = function() return o.dev == true end,
        pedCoords = function() return o.coords or far end,
        log = function(m) logs[#logs + 1] = m end,
    }
    return S.new(env), calls, logs
end

describe('station adapter', function()
    it('homestead started: uses H3 and passes maxDist', function()
        local a, calls = mk({ near = true })
        eq(true, a.isNearStation(1, 'gunsmith', 5.0))
        eq('isNearStation', calls[1].fn); eq(5.0, calls[1].args[3])
        local a2, c2 = mk({ near = true })
        a2.isNearStation(1, 'gunsmith')
        eq(cfg.stationMaxDist, c2[1].args[3])
    end)
    it('homestead started, no station, dev off: no_station (no dev fallback)', function()
        local a = mk({ near = false, coords = atDev })
        local ok, why = a.isNearStation(1, 'gunsmith')
        eq(false, ok); eq('no_station', why)
    end)
    it('homestead missing + fh_dev on: dev stations', function()
        local a, calls = mk({ state = 'missing', dev = true, coords = atDev })
        eq(true, a.isNearStation(1, 'gunsmith'))
        eq(0, #calls)
        local ok, why = mk({ state = 'missing', dev = true, coords = far }).isNearStation(1, 'gunsmith')
        eq(false, ok); eq('no_homestead', why)
    end)
    it('homestead missing + fh_dev off: refuse no_homestead even at a dev spot', function()
        local ok, why = mk({ state = 'missing', dev = false, coords = atDev }).isNearStation(1, 'gunsmith')
        eq(false, ok); eq('no_homestead', why)
    end)
    it('export missing: refuse, no log noise', function()
        local a, _, logs = mk({ noExport = true })
        local ok, why = a.isNearStation(1, 'gunsmith')
        eq(false, ok); eq('no_homestead', why); eq(0, #logs)
    end)
    it('H3 export throwing: refuse and log', function()
        local a, _, logs = mk({ throws = true })
        local ok, why = a.isNearStation(1, 'gunsmith')
        eq(false, ok); eq('homestead_error', why); eq(1, #logs)
        eq(true, logs[1]:find('isNearStation', 1, true) ~= nil)
    end)
    it('bad station type', function()
        local ok, why = mk({ near = true }).isNearStation(1, 'forge')
        eq(false, ok); eq('bad_type', why)
    end)
    it('getStations / stationAt follow the same gating', function()
        local a = mk({ list = { { station_type = 'reload' } }, at = { station_type = 'gunsmith', plot_id = 1, slot_id = 2 } })
        eq(1, #a.getStations('cid')); eq(2, a.stationAt(atDev, 3.0).slot_id)
        local b = mk({ state = 'missing' })
        eq(0, #b.getStations('cid')); eq(nil, b.stationAt(atDev, 3.0))
        local c = mk({ state = 'missing', dev = true })
        eq(3, #c.getStations('cid')); eq(true, c.stationAt(atDev, 3.0).dev)
        eq(nil, mk({ throws = true }).stationAt(atDev, 3.0))
    end)
end)

T.finish()

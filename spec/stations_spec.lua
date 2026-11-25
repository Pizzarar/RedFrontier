local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local case = T.it
local dir = here .. '../server/resources/[fh]/fh_homestead/'
local S = dofile(dir .. 'shared/stations.lua')
dofile(dir .. 'config.lua')
local plots = FhHomesteadConfig.plots
local p1 = plots.heartlands_01
-- offsets from plot center: workbench (6,4), campfire (6,-4), tanning_rack (10,0)
local function at(plot, dx, dy) return { x = plot.center.x + dx, y = plot.center.y + dy, z = plot.center.z } end

case('unbuilt stations are not listed; non-station slots never are', function()
    T.eq(0, #S.builtStations(p1, {}))
    T.eq(0, #S.builtStations(p1, { cabin = 2, fence = 1, trophy_wall = 1, chest_2 = 1 }))
    T.eq(0, #S.builtStations(p1, { station_1 = 0 }))
end)
case('built stations listed with type and coords', function()
    local l = S.builtStations(p1, { station_1 = 1, station_2 = 1 })
    T.eq(2, #l)
    T.eq('station_1', l[1].slot_id); T.eq('workbench', l[1].station_type); T.eq('heartlands_01', l[1].plot_id)
    T.eq(p1.center.x + 6.0, l[1].coords.x); T.eq(p1.center.y + 4.0, l[1].coords.y)
end)
case('nearest within radius (inclusive); outside refused', function()
    local l = S.builtStations(p1, { station_1 = 1, station_3 = 1 })
    local s, d = S.nearest(l, at(p1, 6.0, 5.0), 3.0)
    T.eq('station_1', s.slot_id); T.eq(1.0, d)
    assert(S.nearest(l, at(p1, 6.0, 7.0), 3.0) ~= nil, 'exactly at maxDist counts')
    assert(S.nearest(l, at(p1, 6.0, 7.5), 3.0) == nil)
    -- ground-snapped station: 12 m below hint z within 2 m horizontally -> found; 4 m horizontally or >20 m dz -> nil
    local below = { x = p1.center.x + 8.0, y = p1.center.y + 4.0, z = p1.center.z - 12.0 }
    T.eq('station_1', S.nearest(l, below, 3.0).slot_id)
    assert(S.nearest(l, { x = p1.center.x + 10.0, y = p1.center.y + 4.0, z = p1.center.z - 12.0 }, 3.0) == nil)
    assert(S.nearest(l, { x = p1.center.x + 8.0, y = p1.center.y + 4.0, z = p1.center.z - 21.0 }, 3.0) == nil)
end)
case('nearest picks the closest of several', function()
    local l = S.builtStations(p1, { station_1 = 1, station_2 = 1, station_3 = 1 })
    T.eq('station_3', S.nearest(l, at(p1, 9.0, 0.5), 20).slot_id)
end)
case('type match filters', function()
    local l = S.builtStations(p1, { station_1 = 1, station_2 = 1 })
    local c = at(p1, 6.0, 4.0) -- on the workbench
    T.eq('station_2', S.nearest(l, c, 10, 'campfire').slot_id)
    assert(S.nearest(l, c, 10, 'tanning_rack') == nil)
end)
case('multiple plots: allStations covers all, onlyPlot restricts', function()
    local t = { heartlands_01 = { station_1 = 1 }, heartlands_02 = { station_1 = 1, station_2 = 1 } }
    T.eq(3, #S.allStations(plots, t))
    T.eq(2, #S.allStations(plots, t, nil, 'heartlands_02'))
    T.eq(0, #S.allStations(plots, t, nil, 'heartlands_03'))
    local s = S.nearest(S.allStations(plots, t), at(plots.heartlands_02, 6.0, 4.0), 1.0)
    T.eq('heartlands_02', s.plot_id)
end)
case('unknown station type / bad slots ignored', function()
    local plot = { id = 'x', center = { x = 0, y = 0, z = 0 }, slots = {
        a = { kind = 'station', stationType = 'workbench', prop = { offset = { x = 1, y = 0, z = 0 } } },
        b = { kind = 'station', prop = { offset = { x = 1, y = 0, z = 0 } } },
        c = { kind = 'station', stationType = 'forge', prop = { offset = { x = 'bad', y = 0, z = 0 } } },
        d = 'junk' } }
    local l = S.builtStations(plot, { a = 1, b = 1, c = 1, d = 1 })
    T.eq(1, #l)
    assert(S.nearest(l, { x = 0, y = 0, z = 0 }, 5, 'nonexistent') == nil)
end)
case('nil / garbage safety', function()
    T.eq(0, #S.builtStations(nil, nil))
    T.eq(0, #S.allStations(nil, nil))
    assert(S.nearest(nil, { x = 0, y = 0, z = 0 }) == nil)
    assert(S.nearest({}, nil) == nil)
    assert(S.nearest({}, { x = 0 / 0, y = 0, z = 0 }) == nil)
    assert(S.slotCoords(nil, nil) == nil)
    assert(S.isStationBuilt(nil, 0, 1) == false)
end)
case('station_built only on 0 -> >=1 of a station slot', function()
    local st, ch = p1.slots.station_1, p1.slots.cabin
    assert(S.isStationBuilt(st, 0, 1)); assert(S.isStationBuilt(st, nil, 1))
    assert(not S.isStationBuilt(st, 1, 1)); assert(not S.isStationBuilt(st, 1, 0))
    assert(not S.isStationBuilt(ch, 0, 1))
end)

-- ---------------------------------------------------------------------------------------------------------------
-- server/slots.lua (+ server/main.lua claims) in a stubbed FXServer world. MySQL is a fake in-memory DB; every
-- *.await called from a coroutine started with W.start YIELDS, so a spec can interleave an unclaim / a second
-- setTier while a write is "in flight". By default the query runs at call time and its reply is held (the race
-- the review describes); W.execOnResume = true runs it only when resumed instead.
-- ---------------------------------------------------------------------------------------------------------------
local PR = dofile(dir .. 'shared/plot_rules.lua')
local BR = dofile(dir .. 'shared/build_rules.lua')
local function readSrc(p) local fh = assert(io.open(p, 'rb')); local s = fh:read('a'); fh:close(); return s end
local MAIN_SRC, SLOTS_SRC = readSrc(dir .. 'server/main.lua'), readSrc(dir .. 'server/slots.lua')

local function newWorld(config)
    local W = { db = { plots = {}, slots = {} }, events = {}, handlers = {}, threads = {}, ex = {}, sql = {},
        players = {}, peds = {}, async = {}, failNext = false, execOnResume = false }
    local function fire(name, ...)
        W.events[#W.events + 1] = { name = name, args = table.pack(...) }
        for _, h in ipairs(W.handlers[name] or {}) do h(...) end
    end
    local function key(p, s) return p .. '|' .. s end
    local function exec(sql, p)
        p = p or {}
        if sql:find('^SELECT %* FROM fh_plots') then -- rows carry no class: loaded as claims (H7 fallback)
            local rows = {}
            for pid, cid in pairs(W.db.plots) do rows[#rows + 1] = { plot_id = pid, citizenid = cid } end
            return rows
        elseif sql:find('^SELECT plot_id, slot_id, tier FROM fh_plot_slots') then
            local rows = {}
            for k, t in pairs(W.db.slots) do
                local pid, sid = k:match('^(.-)|(.*)$')
                rows[#rows + 1] = { plot_id = pid, slot_id = sid, tier = t }
            end
            return rows
        elseif sql:find('^INSERT INTO fh_plot_slots') then -- INSERT ... SELECT ... WHERE plot_id = ? AND citizenid = ?
            local pid, sid, t, pid2, cid = p[1], p[2], p[3], p[4], p[5]
            if W.db.plots[pid2] ~= cid then return 0 end
            W.db.slots[key(pid, sid)] = t
            return 1
        elseif sql:find('^DELETE s FROM fh_plot_slots s JOIN fh_plots') then
            local k = key(p[1], p[2])
            if W.db.plots[p[1]] ~= p[3] or W.db.slots[k] == nil then return 0 end
            W.db.slots[k] = nil
            return 1
        elseif sql:find('^DELETE FROM fh_plot_slots') then
            local k = key(p[1], p[2])
            if W.db.slots[k] ~= p[3] then return 0 end
            W.db.slots[k] = nil
            return 1
        elseif sql:find('^DELETE FROM fh_plots') then
            if W.db.plots[p[1]] ~= p[2] then return 0 end
            W.db.plots[p[1]] = nil
            for k in pairs(W.db.slots) do if k:sub(1, #p[1] + 1) == p[1] .. '|' then W.db.slots[k] = nil end end
            return 1
        elseif sql:find('^INSERT INTO fh_plots ') then
            for _, c in pairs(W.db.plots) do if c == p[2] then error('dup citizenid') end end
            if W.db.plots[p[1]] then error('dup plot') end
            W.db.plots[p[1]] = p[2]
            return 1
        elseif sql:find('^INSERT INTO fh_plot_chests') then
            return 1
        end
        error('unmocked sql: ' .. sql)
    end
    local function await(sql, p)
        if W.failNext then W.failNext = false; error('db down') end
        W.sql[#W.sql + 1] = sql
        local yields = W.async[coroutine.running()]
        if yields and W.execOnResume then coroutine.yield('db') end
        local r = exec(sql, p)
        if yields and not W.execOnResume then coroutine.yield('db') end
        return r
    end
    local core = { Functions = { GetPlayer = function(src)
        local cid = W.players[src]
        return cid and { PlayerData = { citizenid = cid } } or nil
    end } }
    local exportsT = setmetatable({}, {
        __call = function(_, name, fn) W.ex[name] = fn end,
        __index = function(_, res) return setmetatable({}, { __index = function(_, fn) return function()
            if fn == 'GetCoreObject' then return core end
            if fn == 'registerContainer' then return true end
            if fn == 'snapshot' then return {} end -- H13: unclaim reads every plot stash (empty here)
            if fn == 'clearContainer' then return true end
        end end }) end })
    W.env = setmetatable({
        FhHomesteadConfig = config or FhHomesteadConfig, FhPlotRules = PR, FhStations = S, FhBuildRules = BR,
        MySQL = { query = { await = await }, update = { await = await }, insert = { await = await } },
        CreateThread = function(fn) W.threads[#W.threads + 1] = fn end, Wait = function() end,
        AddEventHandler = function(name, fn) W.handlers[name] = W.handlers[name] or {}; table.insert(W.handlers[name], fn) end,
        RegisterNetEvent = function() end, TriggerEvent = fire, TriggerClientEvent = function() end,
        exports = exportsT, IsPlayerAceAllowed = function() return false end,
        lib = { callback = { register = function() end }, addCommand = function() end },
        GetPlayerPed = function(src) return W.peds[src] and src or 0 end,
        GetEntityCoords = function(ped) return W.peds[ped] end,
        print = function() end,
    }, { __index = _G })
    assert(load(MAIN_SRC, '@main.lua', 't', W.env))()
    assert(load(SLOTS_SRC, '@slots.lua', 't', W.env))()
    W.slots = W.env.FhHomesteadSlots
    -- threads[1] = main.lua loadClaims, threads[2] = slots.lua boot load; specs drive them by hand
    W.loadClaims = function() W.threads[1]() end
    W.boot = function() W.loadClaims(); assert(W.slots.load()) end
    W.start = function(fn, ...)
        local h = { co = coroutine.create(fn) }
        W.async[h.co] = true
        W.step(h, ...)
        return h
    end
    W.step = function(h, ...)
        local r = table.pack(coroutine.resume(h.co, ...))
        if not r[1] then error(r[2], 0) end
        if coroutine.status(h.co) == 'dead' then h.done, h.res = true, table.pack(table.unpack(r, 2, r.n)) end
    end
    W.finish = function(h) while not h.done do W.step(h) end return table.unpack(h.res, 1, h.res.n) end
    W.named = function(name)
        local out = {}
        for _, e in ipairs(W.events) do if e.name == name then out[#out + 1] = e.args end end
        return out
    end
    W.unclaim = function(plotId) return W.ex.unclaim(0, plotId) end
    W.claim = function(src, cid, plot) W.players[src], W.peds[src] = cid, at(plot, 0, 0); return W.ex.claim(src) end
    return W
end

T.describe('server/slots.lua', function()
    local P1, P2 = 'heartlands_01', 'heartlands_02'
    local BUILT = 'fh:homestead:station_built'

    case('ready gate: reads/writes refused before the slot load; the load keeps DB rows and never clobbers', function()
        local W = newWorld()
        W.db.plots[P1] = 'C1'
        W.db.slots[P1 .. '|station_1'] = 1
        W.loadClaims()
        local Sl = W.slots
        assert(not Sl.isReady())
        local ok, why = Sl.setTier(P1, 'station_2', 1)
        T.eq(false, ok); T.eq('fh_not_ready', why)
        local t, w = Sl.getTiers(P1)
        T.same({}, t); T.eq('fh_not_ready', w)
        T.same({}, W.ex.getStations('C1'))
        T.eq(nil, W.ex.stationAt(at(p1, 6.0, 4.0), 3.0))
        local h = W.start(Sl.load) -- SELECT ran, reply in flight
        ok, why = Sl.setTier(P1, 'station_2', 1)
        T.eq(false, ok); T.eq('fh_not_ready', why)
        T.eq(nil, W.db.slots[P1 .. '|station_2'], 'refused write reached the DB')
        T.eq(false, (Sl.load()), 'second load while loading')
        T.eq(true, (W.finish(h)))
        T.eq(0, #W.named(BUILT), 'no station_built from refused writes')
        T.same({ station_1 = 1 }, (Sl.getTiers(P1)))
        T.eq(1, #W.ex.getStations('C1'))
        T.eq(true, (Sl.setTier(P1, 'station_2', 1)))
        T.same({ station_1 = 1, station_2 = 1 }, (Sl.getTiers(P1)))
        T.eq(1, #W.named(BUILT))
    end)

    case('stationAt: optional type filter, coords in result, offline owner still found (H17)', function()
        local W = newWorld()
        W.db.plots[P1] = 'C1' -- C1 is not online: no player exists in the world
        W.db.slots[P1 .. '|station_1'] = 1 -- workbench (6,4)
        W.db.slots[P1 .. '|station_2'] = 1 -- campfire (6,-4)
        W.boot()
        local atFire = at(p1, 6.0, -3.5)
        T.eq('campfire', W.ex.stationAt(atFire, 3.0).station_type, 'no type = nearest of any type')
        local hit = W.ex.stationAt(atFire, 3.0, 'campfire')
        T.eq('station_2', hit.slot_id); T.eq(P1, hit.plot_id)
        T.eq(p1.center.x + 6.0, hit.coords.x); T.eq(p1.center.y - 4.0, hit.coords.y)
        T.eq(nil, W.ex.stationAt(atFire, 3.0, 'workbench'), 'type miss')
        T.eq('workbench', W.ex.stationAt(at(p1, 6.0, 4.0), 3.0, 'workbench').station_type)
        T.eq(nil, W.ex.stationAt(atFire, 3.0, 'tanning_rack'))
    end)

    case('ready gate: claims not loaded yet -> writes refused; failed load stays not ready and can retry', function()
        local W = newWorld()
        W.db.plots[P1] = 'C1'
        T.eq(true, (W.slots.load()))
        local ok, why = W.slots.setTier(P1, 'station_1', 1)
        T.eq(false, ok); T.eq('fh_not_ready', why)
        local W2 = newWorld()
        W2.loadClaims()
        W2.failNext = true
        T.eq(false, (W2.slots.load()))
        T.eq('fh_not_ready', select(2, W2.slots.setTier(P1, 'station_1', 1)))
        T.eq(true, (W2.slots.load()), 'retry after failure')
    end)

    case('load does not resurrect a plot unclaimed while the boot SELECT was in flight', function()
        local W = newWorld()
        W.db.plots[P1] = 'C1'
        W.db.slots[P1 .. '|station_1'] = 1
        W.loadClaims()
        local h = W.start(W.slots.load)
        T.eq(true, (W.unclaim(P1)))
        T.eq(true, (W.finish(h)))
        T.same({}, (W.slots.getTiers(P1)))
        T.eq(nil, W.ex.stationAt(at(p1, 6.0, 4.0), 3.0))
    end)

    case('unclaim while setTier awaits: fails, nothing cached, no events, no orphan row', function()
        local W = newWorld()
        W.db.plots[P1] = 'C1'
        W.boot()
        local h = W.start(W.slots.setTier, P1, 'station_1', 1) -- INSERT ran, reply in flight
        T.eq(true, (W.unclaim(P1)))
        local ok, why = W.finish(h)
        T.eq(false, ok); T.eq('fh_plot_free', why)
        T.same({}, (W.slots.getTiers(P1)))
        T.eq(0, #W.named(BUILT)); T.eq(0, #W.named('fh:homestead:slot_changed'))
        T.eq(nil, W.db.slots[P1 .. '|station_1'])
        T.eq(nil, W.ex.stationAt(at(p1, 6.0, 4.0), 3.0))
    end)

    case('unclaim + re-claim by the SAME owner while setTier awaits: stale row undone, nothing cached', function()
        local W = newWorld()
        W.db.plots[P1] = 'C1'
        W.boot()
        W.execOnResume = true -- the INSERT only reaches the DB after the re-claim
        local h = W.start(W.slots.setTier, P1, 'station_1', 1)
        T.eq(true, (W.unclaim(P1)))
        T.eq(true, (W.claim(1, 'C1', p1)))
        local ok, why = W.finish(h)
        T.eq(false, ok); T.eq('fh_plot_free', why)
        T.eq(nil, W.db.slots[P1 .. '|station_1'], 'stale write left on the new claim')
        T.same({}, (W.slots.getTiers(P1)))
        T.same({}, W.ex.getStations('C1'))
        T.eq(0, #W.named(BUILT))
    end)

    case('unclaim + re-claim by ANOTHER owner while setTier awaits: no row, no station for the new owner', function()
        local W = newWorld()
        W.db.plots[P1] = 'C1'
        W.boot()
        W.execOnResume = true
        local h = W.start(W.slots.setTier, P1, 'station_1', 1)
        T.eq(true, (W.unclaim(P1)))
        T.eq(true, (W.claim(2, 'C2', p1)))
        local ok, why = W.finish(h)
        T.eq(false, ok); T.eq('fh_plot_free', why)
        T.eq(nil, W.db.slots[P1 .. '|station_1'])
        T.same({}, W.ex.getStations('C2'))
        T.eq(0, #W.named(BUILT))
    end)

    case('concurrent setTier on one plot: second refused while the first awaits; lock always released', function()
        local W = newWorld()
        W.db.plots[P1], W.db.plots[P2] = 'C1', 'C2'
        W.boot()
        local Sl = W.slots
        local h = W.start(Sl.setTier, P1, 'station_1', 1)
        local ok, why = Sl.setTier(P1, 'station_1', 1)
        T.eq(false, ok); T.eq('fh_slot_busy', why)
        T.eq('fh_slot_busy', select(2, Sl.setTier(P1, 'station_2', 1)))
        T.eq(true, (Sl.setTier(P2, 'station_1', 1)), 'other plots are not blocked')
        T.eq(true, (W.finish(h)))
        local built = W.named(BUILT)
        T.eq(2, #built)
        T.same({ 'C2', P2, 'station_1', 'workbench' }, { built[1][1], built[1][2], built[1][3], built[1][4] })
        T.same({ 'C1', P1, 'station_1', 'workbench' }, { built[2][1], built[2][2], built[2][3], built[2][4] })
        T.eq(true, (Sl.setTier(P1, 'station_1', 1)), 'same tier again is a no-op')
        T.eq(2, #W.named(BUILT), 'no duplicate station_built')
        W.failNext = true
        T.eq('fh_slot_save_failed', select(2, Sl.setTier(P1, 'station_3', 1)))
        T.eq(true, (Sl.setTier(P1, 'station_3', 1)), 'lock released after a DB error')
        T.same({ station_1 = 1, station_3 = 1 }, (Sl.getTiers(P1)))
    end)

    case('0 affected rows (fh_plots disagrees with the claim cache): not cached, no events', function()
        local W = newWorld()
        W.db.plots[P1] = 'C1'
        W.boot()
        W.db.plots[P1] = 'CX'
        local ok, why = W.slots.setTier(P1, 'station_1', 1)
        T.eq(false, ok); T.eq('fh_slot_save_failed', why)
        T.same({}, (W.slots.getTiers(P1)))
        T.eq(0, #W.named(BUILT))
    end)

    case('tier bounds: checked against maxTier and slot.tiers; tier 0 deletes the row', function()
        local W = newWorld()
        W.db.plots[P1] = 'C1'
        W.boot()
        local Sl = W.slots
        for _, bad in ipairs({ 2, -1, 1.5, '1', 0 / 0, math.huge, true }) do
            T.eq('fh_bad_tier', select(2, Sl.setTier(P1, 'station_1', bad)), 'tier ' .. tostring(bad))
        end
        T.eq('fh_bad_tier', select(2, Sl.setTier(P1, 'station_1', nil)))
        T.eq('fh_no_slot', select(2, Sl.setTier(P1, 'nope', 1)))
        T.eq('fh_no_slot', select(2, Sl.setTier('nope', 'station_1', 1)))
        T.eq('fh_bad_tier', select(2, Sl.setTier(P1, 'cabin', 3)))
        T.eq(true, (Sl.setTier(P1, 'cabin', 2)))
        T.eq(true, (Sl.setTier(P1, 'station_1', 1)))
        T.eq(1, W.db.slots[P1 .. '|station_1'])
        T.eq(true, (Sl.setTier(P1, 'station_1', 0)))
        T.eq(nil, W.db.slots[P1 .. '|station_1'], 'tier 0 = no row')
        T.same({ cabin = 2 }, (Sl.getTiers(P1)))
        T.same({}, W.ex.getStations('C1'))
        local changed = W.named('fh:homestead:slot_changed')
        T.same({ P1, 'station_1', 0 }, { changed[#changed][1], changed[#changed][2], changed[#changed][3] })
        T.eq(1, #W.named(BUILT))
        local n = #W.sql
        T.eq(true, (Sl.setTier(P1, 'station_1', 0)), 'already 0: no-op')
        T.eq(n, #W.sql, 'no-op issued SQL')
        T.eq('fh_plot_free', select(2, Sl.setTier(P2, 'station_1', 1)))
    end)

    case('tier bounds: a tier with no slot.tiers entry is refused; load drops 0-tier and out-of-range rows', function()
        local cfgX = { verifiedProps = false, plots = { odd = {
            id = 'odd', region = 'heartlands', center = { x = 0, y = 0, z = 0 }, radius = 25.0,
            chest = { coords = { x = 0, y = 0, z = 0 } },
            slots = { forge = { kind = 'station', stationType = 'forge', maxTier = 2,
                tiers = { [1] = { cost = {}, comfort = 1, unlocks = {} } } } } } } }
        local W = newWorld(cfgX)
        W.db.plots.odd = 'C9'
        W.db.slots['odd|forge'] = 2 -- tier 2 has no tiers[2]: ignored on load
        W.boot()
        T.same({}, (W.slots.getTiers('odd')))
        T.eq('fh_bad_tier', select(2, W.slots.setTier('odd', 'forge', 2)))
        T.eq(true, (W.slots.setTier('odd', 'forge', 1)))
        local W2 = newWorld()
        W2.db.plots[P1] = 'C1'
        W2.db.slots[P1 .. '|station_1'] = 0
        W2.db.slots[P1 .. '|station_2'] = 5
        W2.db.slots[P1 .. '|nope'] = 1
        W2.db.slots['ghost|station_1'] = 1
        W2.db.slots[P1 .. '|cabin'] = 2
        W2.boot()
        T.same({ cabin = 2 }, (W2.slots.getTiers(P1)))
        T.same({}, (W2.slots.getTiers('ghost')))
    end)

    case('FhHomesteadClaims is a read-only view (no mutable claim tables exposed)', function()
        local W = newWorld()
        W.db.plots[P1] = 'C1'
        W.loadClaims()
        local C = W.env.FhHomesteadClaims
        T.eq(nil, rawget(C, 'byPlot')); T.eq(nil, C.byPlot); T.eq(nil, C.byOwner)
        T.eq('C1', C.ownerOf(P1)); T.eq(P1, C.plotOf('C1')); T.eq(true, C.isReady())
        assert(not pcall(function() C.byPlot = {} end), 'write to the view must fail')
        assert(not pcall(function() C.ownerOf = function() return 'evil' end end), 'override must fail')
        T.eq('C1', C.ownerOf(P1))
        T.eq(false, (pcall(setmetatable, C, nil)), 'metatable is locked')
    end)
end)
T.finish()

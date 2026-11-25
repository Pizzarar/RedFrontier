-- H19 (plan homestead-04): fh_homestead server/garden.lua with server/main.lua, slots.lua and build.lua in a stubbed
-- FXServer world: in-memory MySQL (fh_plots, fh_plot_slots, fh_plot_beds with PRIMARY KEY(plot_id, bed) and the FK
-- cascade), fh_core (removeItem/addItem/snapshot/clearContainer), rsg-core players, os.time = W.now. An await can be
-- HELD (W.hold[tag] = true): the call yields there, so a spec can run a second call meanwhile, as FXServer would.
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local case = T.it
local dir = here .. '../server/resources/[fh]/fh_homestead/'
local R = dofile(dir .. 'shared/build_rules.lua')
local PR = dofile(dir .. 'shared/plot_rules.lua')
local ST = dofile(dir .. 'shared/stations.lua')
dofile(dir .. 'config.lua')
local cfg = FhHomesteadConfig
local GR = dofile(dir .. 'shared/garden.lua')
local P1, P2 = 'heartlands_01', 'heartlands_02'
local p1 = cfg.plots[P1]
local T0 = 1700000000
local GROW = cfg.garden.growthSeconds

local function readSrc(p) local fh = assert(io.open(p, 'rb')); local s = fh:read('a'); fh:close(); return s end
local SRC = {}
for _, f in ipairs({ 'main', 'slots', 'build', 'garden' }) do SRC[f] = readSrc(dir .. 'server/' .. f .. '.lua') end

local function at(plot, dx, dy) return { x = plot.center.x + (dx or 0), y = plot.center.y + (dy or 0), z = plot.center.z } end
-- the garden prop: plot center + the slot's prop offset
local function gardenSpot(plot) local o = plot.slots.garden.prop.offset; return at(plot, o.x, o.y) end

-- review L: the server never asks FhGarden.ready/remaining about a nil crop
local strictGarden = setmetatable({
    ready = function(pa, now, crop, c) assert(crop ~= nil, 'FhGarden.ready called with a nil crop'); return GR.ready(pa, now, crop, c) end,
    remaining = function(pa, now, crop, c) assert(crop ~= nil, 'FhGarden.remaining called with a nil crop'); return GR.remaining(pa, now, crop, c) end,
}, { __index = GR })

---db (optional) = a DB table from an earlier world: a "restart" keeps every row.
local function newWorld(db)
    local W = { db = db or { plots = {}, slots = {}, beds = {} }, events = {}, handlers = {}, threads = {}, ex = {},
        logs = {}, commands = {}, players = { [1] = 'A', [2] = 'B' }, peds = {}, hold = {}, chest = {}, containers = {},
        now = T0, calls = { removeItem = 0, addItem = 0 }, fail = {} }
    local function await(tag)
        if W.hold[tag] and coroutine.isyieldable() then W.hold[tag] = nil; coroutine.yield(tag) end
    end
    local function fire(name, ...)
        W.events[#W.events + 1] = { name = name, args = table.pack(...) }
        for _, h in ipairs(W.handlers[name] or {}) do h(...) end
    end
    local function bedKey(p, b) return p .. '|' .. tostring(b) end
    local function exec(sql, p)
        p = p or {}
        if sql:find('^SELECT %* FROM fh_plots') then
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
        elseif sql:find('^CREATE TABLE IF NOT EXISTS `fh_plot_beds`') then
            return {}
        elseif sql:find('^SELECT bed, crop, planted_at FROM fh_plot_beds WHERE plot_id = %?') then
            if W.fail.bedRead then error('db down') end
            local rows = {}
            for k, r in pairs(W.db.beds) do
                if k:sub(1, #p[1] + 1) == p[1] .. '|' then rows[#rows + 1] = { bed = r.bed, crop = r.crop, planted_at = r.planted_at } end
            end
            await('bed_read')
            return rows
        elseif sql:find('^INSERT INTO fh_plot_beds %(plot_id, bed, crop, planted_at%) SELECT %?, %?, %?, %? FROM fh_plots'
            .. ' WHERE plot_id = %? AND citizenid = %?$') then
            await('bed_write')
            if W.fail.bedWrite then error('db down') end
            if W.db.plots[p[5]] ~= p[6] then return 0 end
            local k = bedKey(p[1], p[2])
            if W.db.beds[k] then error("Duplicate entry for key 'PRIMARY'") end
            W.db.beds[k] = { bed = p[2], crop = p[3], planted_at = p[4] }
            return 1
        elseif sql:find('^DELETE b FROM fh_plot_beds b JOIN fh_plots p ON p.plot_id = b.plot_id'
            .. ' WHERE b.plot_id = %? AND b.bed = %? AND b.crop = %? AND b.planted_at = %? AND p.citizenid = %?$') then
            await('bed_delete')
            if W.fail.bedDelete then error('db down') end
            local k = bedKey(p[1], p[2])
            local r = W.db.beds[k]
            if not r or r.crop ~= p[3] or r.planted_at ~= p[4] or W.db.plots[p[1]] ~= p[5] then return 0 end
            W.db.beds[k] = nil
            return 1
        elseif sql:find('^DELETE FROM fh_plot_beds WHERE plot_id = %?$') then
            local n = 0
            for k in pairs(W.db.beds) do if k:sub(1, #p[1] + 1) == p[1] .. '|' then W.db.beds[k] = nil; n = n + 1 end end
            return n
        elseif sql:find('^DELETE FROM fh_plots') then
            if W.db.plots[p[1]] ~= p[2] then return 0 end
            W.db.plots[p[1]] = nil
            for k in pairs(W.db.slots) do if k:sub(1, #p[1] + 1) == p[1] .. '|' then W.db.slots[k] = nil end end
            if not W.fail.noCascade then -- FK ON DELETE CASCADE (0021)
                for k in pairs(W.db.beds) do if k:sub(1, #p[1] + 1) == p[1] .. '|' then W.db.beds[k] = nil end end
            end
            return 1
        end
        error('unmocked sql: ' .. sql)
    end
    local core = { Functions = { GetPlayer = function(src)
        local cid = W.players[src]
        return cid and { PlayerData = { citizenid = cid } } or nil
    end } }
    local function stash(ref) return ref.type == 'backpack' and ('bag:' .. tostring(ref.id)) or ref.id end
    local X = {
        ['rsg-core'] = { GetCoreObject = function() return core end },
        fh_core = {
            registerContainer = function(_, ref, opts) W.containers[ref.id] = opts; return true end,
            registerItems = function() return true end,
            snapshot = function(_, ref)
                local out, slot = {}, 0
                for item, n in pairs(W.chest[stash(ref)] or {}) do
                    if n > 0 then slot = slot + 1; out[slot] = { name = item, amount = n } end
                end
                return out
            end,
            clearContainer = function(_, ref) W.chest[stash(ref)] = {}; return true end,
            removeItem = function(_, ref, item, n)
                W.calls.removeItem = W.calls.removeItem + 1
                if W.fail.removeThrows then error('fh_core gone') end
                if ref.type == 'backpack' and not W.players[ref.id] then return false, 'fh_player_offline' end
                local s = stash(ref)
                W.chest[s] = W.chest[s] or {}
                if (W.chest[s][item] or 0) < n then return false, 'fh_not_enough' end
                W.chest[s][item] = W.chest[s][item] - n
                await('removeItem')
                return true
            end,
            addItem = function(_, ref, item, n)
                W.calls.addItem = W.calls.addItem + 1
                await('addItem')
                if W.fail.addThrows then error('fh_core gone') end
                if ref.type == 'backpack' and W.fail.bagAdd then return false, W.fail.bagAdd end
                if ref.type ~= 'backpack' and W.fail.chestAdd then return false, W.fail.chestAdd end
                if ref.type == 'backpack' and not W.players[ref.id] then return false, 'fh_player_offline' end
                local s = stash(ref)
                W.chest[s] = W.chest[s] or {}
                W.chest[s][item] = (W.chest[s][item] or 0) + n
                return true
            end,
        },
        fh_economy = {},
        fh_hands = { getHands = function() return {} end },
    }
    local db = function(sql, p) return exec(sql, p) end
    W.env = setmetatable({
        FhHomesteadConfig = cfg, FhPlotRules = PR, FhStations = ST, FhBuildRules = R, FhGarden = strictGarden,
        MySQL = { query = { await = db }, update = { await = db }, insert = { await = db }, scalar = { await = db } },
        CreateThread = function(fn) W.threads[#W.threads + 1] = fn end, Wait = function() end,
        AddEventHandler = function(name, fn) W.handlers[name] = W.handlers[name] or {}; table.insert(W.handlers[name], fn) end,
        RegisterNetEvent = function() end, TriggerEvent = fire, TriggerClientEvent = function() end,
        exports = setmetatable({}, { __call = function(_, name, fn) W.ex[name] = fn end,
            __index = function(_, res) return X[res] or {} end }),
        IsPlayerAceAllowed = function() return false end,
        GetResourceState = function() return 'started' end, GetCurrentResourceName = function() return 'fh_homestead' end,
        lib = { callback = { register = function() end }, addCommand = function(name, _, fn) W.commands[name] = fn end },
        GetPlayerPed = function(src) return W.peds[src] and src or 0 end,
        GetEntityCoords = function(ped) return W.peds[ped] end,
        os = setmetatable({ time = function()
            if W.fail.timeThrows then error('clock gone') end
            return W.now
        end }, { __index = os }),
        print = function(m) W.logs[#W.logs + 1] = tostring(m) end,
    }, { __index = _G })
    for _, f in ipairs({ 'main', 'slots', 'build', 'garden' }) do assert(load(SRC[f], '@' .. f .. '.lua', 't', W.env))() end
    W.G, W.slots = W.env.FhHomesteadGarden, W.env.FhHomesteadSlots
    W.threads[1](); assert(W.slots.load())
    W.start = function(fn)
        local h = { co = coroutine.create(fn) }
        W.step(h)
        return h
    end
    W.step = function(h)
        local r = table.pack(coroutine.resume(h.co))
        if not r[1] then error(r[2], 0) end
        if coroutine.status(h.co) == 'dead' then h.done, h.res = true, table.pack(table.unpack(r, 2, r.n)) end
    end
    W.finish = function(h) while not h.done do W.step(h) end return table.unpack(h.res, 1, h.res.n) end
    W.logged = function(pat) for _, m in ipairs(W.logs) do if m:find(pat) then return true end end return false end
    W.bag = function(src) local s = 'bag:' .. (src or 1); W.chest[s] = W.chest[s] or {}; return W.chest[s] end
    W.chest1 = function(plotId) local s = PR.chestStashId(plotId or P1, 1); W.chest[s] = W.chest[s] or {}; return W.chest[s] end
    W.bedRow = function(b, plotId) return W.db.beds[(plotId or P1) .. '|' .. b] end
    W.bedCount = function(plotId)
        local n = 0
        for k in pairs(W.db.beds) do if k:sub(1, #(plotId or P1) + 1) == (plotId or P1) .. '|' then n = n + 1 end end
        return n
    end
    W.plant = function(src, seed) return W.G.plant(src, seed) end
    W.harvest = function(src, bed) return W.G.harvest(src, bed) end
    return W
end

-- A owns heartlands_01 with the garden built, stands at it, carries `seeds` (default 5 seedcarrot).
local function world(seeds, db)
    local fresh = db == nil
    db = db or { plots = { [P1] = 'A' }, slots = { [P1 .. '|garden'] = 1 }, beds = {} }
    local W = newWorld(db)
    W.peds[1] = gardenSpot(p1)
    if fresh then for k, v in pairs(seeds or { seedcarrot = 5 }) do W.bag(1)[k] = v end end
    return W
end

local function r(...) return table.pack(...) end

T.describe('config + comfort (H19)', function()
    case('claim template has a garden station slot with comfort; tier-1 garden = FhGarden.beds beds', function()
        local g = p1.slots.garden
        T.eq('station', g.kind); T.eq('garden', g.stationType); T.eq(1, g.maxTier)
        T.eq(3, GR.beds(cfg))
        T.same({}, R.validatePlot(p1))
        T.eq(g.tiers[1].comfort, R.totalComfort(p1, { garden = 1 }))
        assert(g.tiers[1].comfort > 0, 'garden gives comfort')
        T.same({ 'garden' }, R.unlockedState(p1, { garden = 1 }).stations)
    end)
end)

T.describe('/fh_plant', function()
    case('takes 1 seed from the backpack, then writes bed 1 with server time; next plant uses bed 2', function()
        local W = world()
        local res = r(W.plant(1, 'seedcarrot'))
        T.same({ true, 1, T0, n = 3 }, res)
        T.eq(4, W.bag(1).seedcarrot)
        T.same({ bed = 1, crop = 'seedcarrot', planted_at = T0 }, W.bedRow(1))
        W.now = T0 + 5
        T.same({ true, 2, T0 + 5, n = 3 }, r(W.plant(1, 'seedcarrot')))
        T.eq(3, W.bag(1).seedcarrot)
    end)
    case('all beds planted: fh_garden_full, no seed taken', function()
        local W = world()
        for _ = 1, 3 do assert(W.plant(1, 'seedcarrot')) end
        T.eq(2, W.bag(1).seedcarrot)
        local calls = W.calls.removeItem
        T.same({ false, 'fh_garden_full', n = 2 }, r(W.plant(1, 'seedcarrot')))
        T.eq(2, W.bag(1).seedcarrot); T.eq(calls, W.calls.removeItem); T.eq(3, W.bedCount())
    end)
    case('refusals before any take: unknown seed, no seed, not at the garden, no garden, no plot, not the owner', function()
        local W = world({ seedpotato = 0 })
        T.same({ false, 'fh_unknown_seed', n = 2 }, r(W.plant(1, 'seedmystery')))
        T.same({ false, 'fh_unknown_seed', n = 2 }, r(W.plant(1, nil)))
        T.same({ false, 'fh_no_seed', 'seedcarrot', n = 3 }, r(W.plant(1, 'seedcarrot')))
        T.eq(0, W.bedCount())
        W.bag(1).seedcarrot = 1
        W.peds[1] = at(p1) -- inside the plot, 10 m from the garden
        T.same({ false, 'fh_not_near_garden', n = 2 }, r(W.plant(1, 'seedcarrot')))
        -- B owns no plot; then B owns heartlands_02 (no garden), then stands at A's garden
        W.bag(2).seedcarrot = 1
        W.peds[2] = gardenSpot(p1)
        T.same({ false, 'fh_no_plot', n = 2 }, r(W.plant(2, 'seedcarrot')))
        local W2 = world(nil, { plots = { [P1] = 'A', [P2] = 'B' }, slots = { [P1 .. '|garden'] = 1 }, beds = {} })
        W2.bag(2).seedcarrot = 1
        W2.peds[2] = gardenSpot(cfg.plots[P2])
        T.same({ false, 'fh_no_garden', n = 2 }, r(W2.plant(2, 'seedcarrot')))
        local W3 = world(nil, { plots = { [P1] = 'A', [P2] = 'B' }, slots = { [P1 .. '|garden'] = 1, [P2 .. '|garden'] = 1 }, beds = {} })
        W3.bag(2).seedcarrot = 1
        W3.peds[2] = gardenSpot(p1)
        T.same({ false, 'fh_not_owner', n = 2 }, r(W3.plant(2, 'seedcarrot')))
        T.eq(1, W3.bag(2).seedcarrot); T.eq(0, W3.bedCount(P1)); T.eq(0, W3.calls.removeItem)
    end)
    case('bed write fails: the seed goes back to the backpack, no row (all-or-nothing)', function()
        local W = world({ seedcorn = 1 })
        W.fail.bedWrite = true
        T.same({ false, 'fh_garden_save_failed', n = 2 }, r(W.plant(1, 'seedcorn')))
        T.eq(1, W.bag(1).seedcorn); T.eq(0, W.bedCount())
    end)
    case('bed write lands 0 rows (fh_plots changed outside the server): refund, no row', function()
        local W = world({ seedcorn = 1 })
        W.hold.bed_write = true
        local h = W.start(function() return W.plant(1, 'seedcorn') end)
        T.eq(0, W.bag(1).seedcorn) -- taken, write suspended
        W.db.plots[P1] = 'Z'
        T.same({ false, 'fh_garden_save_failed' }, { W.finish(h) })
        T.eq(1, W.bag(1).seedcorn); T.eq(0, W.bedCount())
    end)
    case('refund: backpack refuses with an unchanged reason -> plot chest 1 (warn); unknown outcome -> ITEM LOST, not rerouted', function()
        local W = world({ seedcorn = 1 })
        W.fail.bedWrite, W.fail.bagAdd = true, 'no_space'
        T.same({ false, 'fh_garden_save_failed', n = 2 }, r(W.plant(1, 'seedcorn')))
        T.eq(0, W.bag(1).seedcorn); T.eq(1, W.chest1().seedcorn)
        assert(W.logged('garden refund: backpack refused 1 seedcorn %(no_space%); put into plot chest'))
        local W2 = world({ seedcorn = 1 })
        W2.fail.bedWrite, W2.fail.bagAdd = true, 'fh_inventory_error'
        T.same({ false, 'fh_garden_refund_failed', n = 2 }, r(W2.plant(1, 'seedcorn')))
        T.eq(nil, W2.chest1().seedcorn)
        assert(W2.logged('ITEM LOST: garden seed refund failed: citizenid=A plot=heartlands_01 item=seedcorn amount=1'))
    end)
    case('character switched on src before the take: player_changed, nothing taken', function()
        local W = world()
        W.players[1] = 'C' -- C has no plot: refused before the lock
        T.same({ false, 'fh_no_plot', n = 2 }, r(W.plant(1, 'seedcarrot')))
        W.players[1] = 'A'
        W.hold.bed_read = true
        local h = W.start(function() return W.plant(1, 'seedcarrot') end)
        W.players[1] = 'C' -- switched while the bed read was in flight
        T.same({ false, 'player_changed' }, { W.finish(h) })
        T.eq(5, W.bag(1).seedcarrot); T.eq(0, W.calls.removeItem); T.eq(0, W.bedCount())
    end)
    case('a Lua error after the take refunds the seed and releases every lock', function()
        local W = world({ seedcorn = 1 })
        W.fail.timeThrows = true
        T.same({ false, 'fh_garden_failed', n = 2 }, r(W.plant(1, 'seedcorn')))
        T.eq(1, W.bag(1).seedcorn); T.eq(0, W.bedCount())
        W.fail.timeThrows = false
        assert(W.plant(1, 'seedcorn')) -- plot + character locks released
        T.same({ true, P1, n = 2 }, r(W.ex.unclaim(0, P1, true))) -- chest hold released (no fh_chest_busy)
    end)
    case('removeItem throws: fh_removeitem_unavailable, nothing written', function()
        local W = world()
        W.fail.removeThrows = true
        T.same({ false, 'fh_removeitem_unavailable', n = 2 }, r(W.plant(1, 'seedcarrot')))
        T.eq(0, W.bedCount())
    end)
end)

T.describe('/fh_harvest', function()
    case('timer: refused before planted_at + growth (fh_not_ripe, seconds left), ready exactly at it', function()
        local W = world()
        assert(W.plant(1, 'seedcarrot'))
        W.now = T0 + GROW - 1
        T.same({ false, 'fh_not_ripe', 1, n = 3 }, r(W.harvest(1)))
        T.same({ false, 'fh_not_ripe', 1, n = 3 }, r(W.harvest(1, 1)))
        T.eq(nil, W.bag(1).carrot); T.eq(1, W.bedCount()); T.eq(0, W.calls.addItem)
        W.now = T0 + GROW
        T.same({ true, { bed = 1, item = 'carrot', amount = 3, to = 'bag' }, n = 2 }, r(W.harvest(1)))
        T.eq(3, W.bag(1).carrot); T.eq(0, W.bedCount())
    end)
    case('the bed is empty again: a second harvest gives nothing (fh_garden_empty / fh_bed_empty)', function()
        local W = world()
        assert(W.plant(1, 'seedcarrot'))
        W.now = T0 + GROW
        assert(W.harvest(1))
        T.same({ false, 'fh_garden_empty', n = 2 }, r(W.harvest(1)))
        T.same({ false, 'fh_bed_empty', n = 2 }, r(W.harvest(1, 1)))
        T.same({ false, 'fh_bad_bed', n = 2 }, r(W.harvest(1, 4)))
        T.same({ false, 'fh_bad_bed', n = 2 }, r(W.harvest(1, 1.5)))
        T.eq(3, W.bag(1).carrot)
        assert(W.plant(1, 'seedcarrot')) -- replantable
    end)
    case('first ready bed only; others keep growing', function()
        local W = world({ seedcarrot = 1, seedpotato = 1 })
        assert(W.plant(1, 'seedcarrot'))
        W.now = T0 + 100
        assert(W.plant(1, 'seedpotato'))
        W.now = T0 + GROW + 50 -- carrot ready, potato 50 s short
        T.same({ true, { bed = 1, item = 'carrot', amount = 3, to = 'bag' }, n = 2 }, r(W.harvest(1)))
        T.same({ false, 'fh_not_ripe', 50, n = 3 }, r(W.harvest(1)))
        T.same({ bed = 2, crop = 'seedpotato', planted_at = T0 + 100 }, W.bedRow(2))
    end)
    case('restart keeps the timer and the crop grows while the owner is offline', function()
        local W = world()
        assert(W.plant(1, 'seedcarrot'))
        local db = W.db
        -- owner logs off; server restarts twice; owner comes back after the growth time
        local W2 = world(nil, db)
        W2.players[1] = nil
        W2.now = T0 + GROW / 2
        local W3 = world(nil, db)
        W3.now = T0 + GROW - 1
        T.same({ false, 'fh_not_ripe', 1, n = 3 }, r(W3.harvest(1)))
        W3.now = T0 + GROW + 3600
        T.same({ true, { bed = 1, item = 'carrot', amount = 3, to = 'bag' }, n = 2 }, r(W3.harvest(1)))
        T.eq(3, W3.bag(1).carrot); T.eq(0, W3.bedCount())
    end)
    case('double harvest: a concurrent second call is refused (lock) and a stale bed (0 rows) gives nothing', function()
        local W = world()
        assert(W.plant(1, 'seedcarrot'))
        W.now = T0 + GROW
        W.hold.bed_delete = true
        local h = W.start(function() return W.harvest(1) end)
        T.same({ false, 'fh_garden_busy', n = 2 }, r(W.harvest(1)))
        T.same({ true, { bed = 1, item = 'carrot', amount = 3, to = 'bag' } }, { W.finish(h) })
        T.eq(3, W.bag(1).carrot)
        -- the row disappears between the read and the conditional DELETE (another server / admin): nothing given
        local W2 = world()
        assert(W2.plant(1, 'seedcarrot'))
        W2.now = T0 + GROW
        W2.hold.bed_read = true
        local h2 = W2.start(function() return W2.harvest(1) end)
        W2.db.beds[P1 .. '|1'] = nil
        T.same({ false, 'fh_bed_changed' }, { W2.finish(h2) })
        T.eq(nil, W2.bag(1).carrot); T.eq(0, W2.calls.addItem)
        -- re-planted in between (same bed, new planted_at): the DELETE does not match the new planting
        local W3 = world()
        assert(W3.plant(1, 'seedcarrot'))
        W3.now = T0 + GROW
        W3.hold.bed_read = true
        local h3 = W3.start(function() return W3.harvest(1) end)
        W3.db.beds[P1 .. '|1'].planted_at = T0 + GROW
        T.same({ false, 'fh_bed_changed' }, { W3.finish(h3) })
        T.eq(nil, W3.bag(1).carrot); T.eq(1, W3.bedCount())
    end)
    case('bed clear errors: nothing given', function()
        local W = world()
        assert(W.plant(1, 'seedcarrot'))
        W.now = T0 + GROW
        W.fail.bedDelete = true
        T.same({ false, 'fh_garden_save_failed', n = 2 }, r(W.harvest(1)))
        T.eq(nil, W.bag(1).carrot); T.eq(0, W.calls.addItem)
    end)
    case('backpack refuses with an unchanged reason: the yield goes to plot chest 1 (warn)', function()
        local W = world()
        assert(W.plant(1, 'seedcarrot'))
        W.now = T0 + GROW
        W.fail.bagAdd = 'fh_too_heavy'
        T.same({ true, { bed = 1, item = 'carrot', amount = 3, to = 'chest' }, n = 2 }, r(W.harvest(1)))
        T.eq(3, W.chest1().carrot); T.eq(nil, W.bag(1).carrot); T.eq(0, W.bedCount())
        assert(W.logged('garden harvest: backpack refused 3 carrot %(fh_too_heavy%); put into plot chest fh:chest:heartlands_01:1'))
    end)
    case('character left src after planting: the yield goes to plot chest 1, never another character', function()
        local W = world()
        assert(W.plant(1, 'seedcarrot'))
        W.now = T0 + GROW
        W.hold.bed_delete = true
        local h = W.start(function() return W.harvest(1) end)
        W.players[1] = 'C'
        T.same({ true, { bed = 1, item = 'carrot', amount = 3, to = 'chest' } }, { W.finish(h) })
        T.eq(3, W.chest1().carrot); T.eq(nil, W.bag(1).carrot)
    end)
    case('backpack and chest both refuse (unchanged): the bed is put back as it was, fh_no_room', function()
        local W = world()
        assert(W.plant(1, 'seedcarrot'))
        W.now = T0 + GROW
        W.fail.bagAdd, W.fail.chestAdd = 'no_space', 'fh_no_slot'
        T.same({ false, 'fh_no_room', n = 2 }, r(W.harvest(1)))
        T.same({ bed = 1, crop = 'seedcarrot', planted_at = T0 }, W.bedRow(1))
        T.eq(nil, W.bag(1).carrot); T.eq(nil, W.chest1().carrot)
        W.fail.bagAdd, W.fail.chestAdd = nil, nil
        assert(W.harvest(1)) -- room made: harvest once, exactly
        T.eq(3, W.bag(1).carrot); T.eq(0, W.bedCount())
    end)
    case('unknown outcome fails closed: ITEM LOST, not rerouted, bed not restored', function()
        local W = world()
        assert(W.plant(1, 'seedcarrot'))
        W.now = T0 + GROW
        W.fail.bagAdd = 'fh_inventory_error'
        T.same({ false, 'fh_harvest_lost', n = 2 }, r(W.harvest(1)))
        T.eq(nil, W.chest1().carrot); T.eq(0, W.bedCount())
        assert(W.logged('ITEM LOST: garden harvest give failed: citizenid=A plot=heartlands_01 bed=1 item=carrot amount=3'))
        -- chest refusal with an unknown reason after an unchanged backpack refusal: ITEM LOST too, no restore
        local W2 = world()
        assert(W2.plant(1, 'seedcarrot'))
        W2.now = T0 + GROW
        W2.fail.bagAdd, W2.fail.chestAdd = 'no_space', 'fh_inventory_error'
        T.same({ false, 'fh_harvest_lost', n = 2 }, r(W2.harvest(1)))
        T.eq(0, W2.bedCount())
        -- addItem throws
        local W3 = world()
        assert(W3.plant(1, 'seedcarrot'))
        W3.now = T0 + GROW
        W3.fail.addThrows = true
        T.same({ false, 'fh_harvest_lost', n = 2 }, r(W3.harvest(1)))
        T.eq(0, W3.bedCount()); T.eq(1, W3.calls.addItem)
    end)
    case('review L: a stored row with an unknown / empty crop is never ready and FhGarden never sees a nil crop', function()
        local W = world()
        W.db.beds[P1 .. '|1'] = { bed = 1, crop = 'seedmystery', planted_at = T0 - 10 * GROW }
        W.db.beds[P1 .. '|2'] = { bed = 2, crop = '', planted_at = T0 - 10 * GROW }
        T.same({ false, 'fh_garden_empty', n = 2 }, r(W.harvest(1)))
        T.same({ false, 'fh_unknown_crop', 'seedmystery', n = 3 }, r(W.harvest(1, 1)))
        T.eq(2, W.bedCount())
        local st = W.G.status(1)
        T.eq(false, st[1].ready); T.eq(nil, st[1].remaining); T.eq(nil, st[3].crop)
        T.same({ true, 3, T0, n = 3 }, r(W.plant(1, 'seedcarrot'))) -- the odd rows still hold their beds
    end)
    case('commands: /fh_plant, /fh_harvest and /fh_garden reply with the outcome', function()
        local W = world()
        local said = {}
        W.env.TriggerClientEvent = function(ev, _, payload) if ev == 'chat:addMessage' then said[#said + 1] = payload.args[2] end end
        W.commands.fh_plant(1, { seed = 'seedcarrot' })
        T.eq('fh_plant: planted seedcarrot in bed 1 (ready in 2h 00m)', said[1])
        W.commands.fh_garden(1, {})
        T.eq('fh_garden: plot heartlands_01: bed 1 carrot 2h 00m; bed 2 empty; bed 3 empty', said[2])
        W.commands.fh_harvest(1, {})
        T.eq('fh_harvest: fh_not_ripe (ready in 2h 00m)', said[3])
        W.now = T0 + GROW
        W.commands.fh_harvest(1, {})
        T.eq('fh_harvest: bed 1 gave 3 carrot (backpack)', said[4])
    end)
end)

T.describe('unclaim vs the garden (H19)', function()
    case('a planted bed blocks the owner and a plain admin release: fh_garden_not_empty, nothing changed', function()
        local W = world()
        assert(W.plant(1, 'seedcarrot'))
        T.same({ false, 'fh_garden_not_empty', n = 2 }, r(W.ex.unclaim(1)))
        T.same({ false, 'fh_garden_not_empty', n = 2 }, r(W.ex.unclaim(0, P1)))
        T.eq('A', W.db.plots[P1]); T.eq(1, W.bedCount())
        W.now = T0 + GROW
        assert(W.harvest(1))
        W.bag(1).carrot = nil
        T.same({ true, P1, n = 2 }, r(W.ex.unclaim(1)))
    end)
    case('admin force clears the beds and logs each one', function()
        local W = world()
        assert(W.plant(1, 'seedcarrot'))
        W.now = T0 + 1
        assert(W.plant(1, 'seedcarrot'))
        W.fail.noCascade = true -- the explicit DELETE is the backstop
        T.same({ true, P1, n = 2 }, r(W.ex.unclaim(0, P1, true)))
        T.eq(nil, W.db.plots[P1]); T.eq(0, W.bedCount())
        assert(W.logged('force unclaim: plot=heartlands_01 owner=A bed=1 crop=seedcarrot planted_at=' .. T0 .. ' cleared'))
        assert(W.logged('force unclaim: plot=heartlands_01 owner=A bed=2 crop=seedcarrot planted_at=' .. (T0 + 1) .. ' cleared'))
    end)
    case('garden read fails: unclaim refused fh_garden_check_failed (fails closed), even forced', function()
        local W = world()
        W.fail.bedRead = true
        T.same({ false, 'fh_garden_check_failed', n = 2 }, r(W.ex.unclaim(1)))
        T.same({ false, 'fh_garden_check_failed', n = 2 }, r(W.ex.unclaim(0, P1, true)))
        T.eq('A', W.db.plots[P1])
        W.fail.bedRead = false
        T.same({ true, P1, n = 2 }, r(W.ex.unclaim(1))) -- lock released
    end)
    case('no unclaim while a plant or harvest is in flight (fh_chest_busy); none starts while an unclaim holds the plot', function()
        local W = world()
        W.hold.removeItem = true
        local h = W.start(function() return W.plant(1, 'seedcarrot') end)
        T.same({ false, 'fh_chest_busy', n = 2 }, r(W.ex.unclaim(0, P1, true)))
        T.same({ true, 1, T0 }, { W.finish(h) })
        W.now = T0 + GROW
        W.hold.addItem = true
        local h2 = W.start(function() return W.harvest(1) end)
        T.same({ false, 'fh_chest_busy', n = 2 }, r(W.ex.unclaim(0, P1, true)))
        assert((W.finish(h2)))
        -- unclaim suspended in its garden read: plant refused fh_claim_busy
        W.bag(1).carrot = nil
        W.hold.bed_read = true
        local h3 = W.start(function() return W.ex.unclaim(1) end)
        T.same({ false, 'fh_claim_busy', n = 2 }, r(W.plant(1, 'seedcarrot')))
        T.same({ true, P1 }, { W.finish(h3) })
    end)
end)

T.finish()

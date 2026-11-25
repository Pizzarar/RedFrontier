-- H20b (plan homestead-04): fh_homestead server/trough.lua with server/main.lua, slots.lua, build.lua and garden.lua in a
-- stubbed FXServer world (in-memory MySQL incl. fh_plot_trough + FK cascade, fh_core containers, rsg-core players,
-- os.time = W.now). Same harness idea as garden_server_spec.lua.
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
local TR = dofile(dir .. 'shared/trough.lua')
local P1, P2 = 'heartlands_01', 'heartlands_02'
local p1 = cfg.plots[P1]
local T0 = 1700000000
local CD = cfg.trough.cooldownSeconds
local TID = 'fh:trough:' .. P1

local function readSrc(p) local fh = assert(io.open(p, 'rb')); local s = fh:read('a'); fh:close(); return s end
local SRC = {}
for _, f in ipairs({ 'main', 'slots', 'build', 'garden', 'trough' }) do SRC[f] = readSrc(dir .. 'server/' .. f .. '.lua') end

local function at(plot, dx, dy) return { x = plot.center.x + (dx or 0), y = plot.center.y + (dy or 0), z = plot.center.z } end
local function troughSpot(plot) local o = plot.slots.trough.prop.offset; return at(plot, o.x, o.y) end

local function newWorld(db, refillOn)
    local W = { db = db or { plots = {}, slots = {}, refill = {} }, events = {}, client = {}, handlers = {}, net = {}, threads = {},
        ex = {}, logs = {}, players = { [1] = 'A', [2] = 'B' }, peds = {}, chest = {}, containers = {}, use = {},
        now = T0, calls = { removeItem = 0, addItem = 0 }, fail = {} }
    cfg.trough.troughRefill = refillOn == true
    local function fire(name, ...)
        W.events[#W.events + 1] = { name = name, args = table.pack(...) }
        for _, h in ipairs(W.handlers[name] or {}) do h(...) end
    end
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
        elseif sql:find('^CREATE TABLE IF NOT EXISTS') then
            return {}
        elseif sql:find('^SELECT bed, crop, planted_at FROM fh_plot_beds') then
            return {}
        elseif sql:find('^DELETE FROM fh_plot_beds') then
            return 0
        elseif sql:find('^SELECT last_refill_at FROM fh_plot_trough WHERE plot_id = %?') then
            if W.fail.refillRead then error('db down') end
            local v = W.db.refill[p[1]]
            return v and { { last_refill_at = v } } or {}
        elseif sql:find('^INSERT INTO fh_plot_trough') then
            if W.fail.refillWrite then error('db down') end
            if W.db.plots[p[3]] ~= p[4] then return 0 end
            W.db.refill[p[1]] = p[2]
            return 1
        elseif sql:find('^DELETE FROM fh_plot_trough') then
            W.db.refill[p[1]] = nil
            return 1
        elseif sql:find('^DELETE FROM fh_plots') then
            if W.db.plots[p[1]] ~= p[2] then return 0 end
            W.db.plots[p[1]] = nil
            for k in pairs(W.db.slots) do if k:sub(1, #p[1] + 1) == p[1] .. '|' then W.db.slots[k] = nil end end
            W.db.refill[p[1]] = nil -- FK cascade
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
        ['rsg-core'] = { GetCoreObject = function() return core end,
            CreateUseableItem = function(_, name, fn) W.use[name] = fn end },
        fh_core = {
            registerContainer = function(_, ref, opts) W.containers[ref.id] = opts; return true end,
            registerItems = function() return true end,
            snapshot = function(_, ref)
                if W.fail.snapshot and ref.id == TID then return false, W.fail.snapshot end
                if ref.type ~= 'backpack' and ref.id:find('^fh:trough:') and not W.containers[ref.id] then return false, 'fh_unknown_container' end
                local out, slot = {}, 0
                for item, n in pairs(W.chest[stash(ref)] or {}) do
                    if n > 0 then slot = slot + 1; out[slot] = { name = item, amount = n } end
                end
                return out
            end,
            clearContainer = function(_, ref) W.chest[stash(ref)] = {}; return true end,
            removeItem = function(_, ref, item, n)
                W.calls.removeItem = W.calls.removeItem + 1
                if ref.type == 'backpack' and not W.players[ref.id] then return false, 'fh_player_offline' end
                local s = stash(ref)
                W.chest[s] = W.chest[s] or {}
                if (W.chest[s][item] or 0) < n then return false, 'fh_not_enough' end
                W.chest[s][item] = W.chest[s][item] - n
                return true
            end,
            addItem = function(_, ref, item, n)
                W.calls.addItem = W.calls.addItem + 1
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
        FhHomesteadConfig = cfg, FhPlotRules = PR, FhStations = ST, FhBuildRules = R, FhGarden = GR, FhTrough = TR,
        MySQL = { query = { await = db }, update = { await = db }, insert = { await = db }, scalar = { await = db } },
        CreateThread = function(fn) W.threads[#W.threads + 1] = fn end, Wait = function() end,
        AddEventHandler = function(name, fn) W.handlers[name] = W.handlers[name] or {}; table.insert(W.handlers[name], fn) end,
        RegisterNetEvent = function(name, fn) W.net[name] = fn end, TriggerEvent = fire,
        TriggerClientEvent = function(name, src) W.client[#W.client + 1] = { name = name, src = src } end,
        exports = setmetatable({}, { __call = function(_, name, fn) W.ex[name] = fn end,
            __index = function(_, res) return X[res] or {} end }),
        IsPlayerAceAllowed = function() return false end,
        GetResourceState = function() return 'started' end, GetCurrentResourceName = function() return 'fh_homestead' end,
        lib = { callback = { register = function() end }, addCommand = function() end },
        GetPlayerPed = function(src) return W.peds[src] and src or 0 end,
        GetEntityCoords = function(ped) return W.peds[ped] end,
        os = setmetatable({ time = function() return W.now end }, { __index = os }),
        print = function(m) W.logs[#W.logs + 1] = tostring(m) end,
    }, { __index = _G })
    local before
    for _, f in ipairs({ 'main', 'slots', 'build', 'garden', 'trough' }) do
        if f == 'trough' then before = #W.threads end
        assert(load(SRC[f], '@' .. f .. '.lua', 't', W.env))()
    end
    W.TR = W.env.FhHomesteadTrough
    W.slots = W.env.FhHomesteadSlots
    W.threads[1](); assert(W.slots.load())
    for i = before + 1, #W.threads do W.threads[i]() end -- trough boot: DDL + register containers, then the use handler
    W.logged = function(pat) for _, m in ipairs(W.logs) do if m:find(pat) then return true end end return false end
    W.bag = function(src) local s = 'bag:' .. (src or 1); W.chest[s] = W.chest[s] or {}; return W.chest[s] end
    W.trough = function(plotId) local s = 'fh:trough:' .. (plotId or P1); W.chest[s] = W.chest[s] or {}; return W.chest[s] end
    W.refill = function(src) W.env.source = src; local n = #W.client; W.net['fh:homestead:trough_refill'](); return #W.client > n end
    return W
end

-- A owns heartlands_01 with the trough built (and the trough container registered), stands at it.
local function world(refillOn, db)
    db = db or { plots = { [P1] = 'A' }, slots = { [P1 .. '|trough'] = 1 }, refill = {} }
    local W = newWorld(db, refillOn)
    W.peds[1] = troughSpot(p1)
    return W
end
local function r(...) return table.pack(...) end

T.describe('config + container (H20b)', function()
    case('claim template has a trough station slot with comfort; town lots have none', function()
        local s = p1.slots.trough
        T.eq('station', s.kind); T.eq('trough', s.stationType); T.eq(1, s.maxTier)
        T.same({}, R.validatePlot(p1))
        assert(s.tiers[1].comfort > 0)
        T.same({ 'trough' }, R.unlockedState(p1, { trough = 1 }).stations)
        T.eq(nil, cfg.slotTemplates.town_lot().trough)
    end)
    case('boot registers fh:trough:<plot> at the slot prop with the configured size; unbuilt plots get none', function()
        local W = world()
        local c = W.containers[TID]
        assert(c, 'trough container registered')
        T.eq(cfg.trough.slots, c.slots); T.eq(cfg.trough.maxWeight, c.maxWeight)
        local spot = troughSpot(p1)
        T.eq(spot.x, c.coords.x); T.eq(spot.y, c.coords.y)
        local W2 = world(false, { plots = { [P1] = 'A' }, slots = {}, refill = {} })
        T.eq(nil, W2.containers[TID])
    end)
end)

T.describe('loading the trough (feedbag use handler)', function()
    case('using a feedbag at your trough moves exactly 1 from the backpack into the container', function()
        local W = world(); W.bag(1).feedbag = 3
        assert(W.use.feedbag, 'feedbag has a use handler')
        W.use.feedbag(1, { name = 'feedbag' })
        T.eq(2, W.bag(1).feedbag); T.eq(1, W.trough().feedbag)
    end)
    case('a non-feedbag is refused: nothing taken, nothing added', function()
        local W = world(); W.bag(1).carrot = 2
        T.same({ false, 'fh_trough_wrong_item', n = 2 }, r(W.TR.load(1, 'carrot')))
        T.eq(2, W.bag(1).carrot); T.eq(nil, W.trough().carrot); T.eq(0, W.calls.removeItem); T.eq(0, W.calls.addItem)
        assert(not TR.accepts('carrot') and TR.accepts('feedbag'))
    end)
    case('refusals: no bag in the backpack, away from the trough, not the owner, no trough built', function()
        local W = world()
        T.same({ false, 'fh_no_feedbag', n = 2 }, r(W.TR.load(1, 'feedbag')))
        W.bag(1).feedbag = 1
        W.peds[1] = at(p1)
        T.same({ false, 'fh_not_near_trough', n = 2 }, r(W.TR.load(1, 'feedbag')))
        T.eq(1, W.bag(1).feedbag)
        W.bag(2).feedbag = 1; W.peds[2] = troughSpot(p1)
        T.same({ false, 'fh_no_plot', n = 2 }, r(W.TR.load(2, 'feedbag'))) -- B owns nothing
        local W2 = world(false, { plots = { [P1] = 'A' }, slots = {}, refill = {} })
        W2.bag(1).feedbag = 1
        T.same({ false, 'fh_no_trough', n = 2 }, r(W2.TR.load(1, 'feedbag')))
        T.eq(1, W2.bag(1).feedbag)
    end)
    case('the trough refuses the add: the feedbag goes back to the backpack', function()
        local W = world(); W.bag(1).feedbag = 1
        W.fail.chestAdd = 'fh_inventory_full'
        T.same({ false, 'fh_trough_full', n = 2 }, r(W.TR.load(1, 'feedbag')))
        T.eq(1, W.bag(1).feedbag); T.eq(nil, W.trough().feedbag)
    end)
end)

T.describe('refill on mount', function()
    case('refill consumes exactly 1 feedbag, records the time, and tells the client', function()
        local W = world(true); W.trough().feedbag = 3
        W.peds[1] = at(p1)
        assert(W.refill(1))
        T.eq(2, W.trough().feedbag); T.eq(T0, W.db.refill[P1])
        T.eq('fh:homestead:trough_refilled', W.client[#W.client].name); T.eq(1, W.client[#W.client].src)
    end)
    case('cooldown respected: refused until last + cooldown, feedbag kept; allowed exactly at it', function()
        local W = world(true); W.trough().feedbag = 3; W.peds[1] = at(p1)
        assert(W.refill(1))
        W.now = T0 + CD - 1
        T.same({ false, 'fh_cooldown', n = 2 }, r(W.TR.refill(1)))
        assert(not W.refill(1)); T.eq(2, W.trough().feedbag)
        W.now = T0 + CD
        assert(W.refill(1)); T.eq(1, W.trough().feedbag)
    end)
    case('cooldown survives a restart (persisted per plot)', function()
        local W = world(true); W.trough().feedbag = 3; W.peds[1] = at(p1)
        assert(W.refill(1))
        local W2 = world(true, W.db); W2.trough().feedbag = 2; W2.peds[1] = at(p1)
        W2.now = T0 + 10
        T.same({ false, 'fh_cooldown', n = 2 }, r(W2.TR.refill(1)))
    end)
    case('empty trough = no refill (and no cooldown recorded)', function()
        local W = world(true); W.peds[1] = at(p1)
        T.same({ false, 'fh_trough_empty', n = 2 }, r(W.TR.refill(1)))
        assert(not W.refill(1)); T.eq(nil, W.db.refill[P1]); T.eq(0, W.calls.removeItem)
    end)
    case('a non-feedbag item in the trough does not count as a refill (carrots only = empty)', function()
        local W = world(true); W.trough().carrot = 5; W.peds[1] = at(p1)
        T.same({ false, 'fh_trough_empty', n = 2 }, r(W.TR.refill(1)))
    end)
    case('non-owner = no refill (no plot, or standing on A\'s plot with B\'s own claim)', function()
        local W = world(true); W.trough().feedbag = 2; W.peds[2] = at(p1)
        T.same({ false, 'fh_no_plot', n = 2 }, r(W.TR.refill(2)))
        local W2 = newWorld({ plots = { [P1] = 'A', [P2] = 'B' }, slots = { [P1 .. '|trough'] = 1, [P2 .. '|trough'] = 1 }, refill = {} }, true)
        W2.trough().feedbag = 2; W2.peds[2] = at(p1) -- B stands on A's plot
        T.same({ false, 'fh_out_of_range', n = 2 }, r(W2.TR.refill(2)))
        T.eq(2, W2.trough().feedbag); T.eq(nil, W2.db.refill[P1]); T.eq(nil, W2.db.refill[P2])
    end)
    case('out of range = no refill: the SERVER ped position outside the plot radius', function()
        local W = world(true); W.trough().feedbag = 2
        W.peds[1] = at(p1, p1.radius + 50.0, 0)
        T.same({ false, 'fh_out_of_range', n = 2 }, r(W.TR.refill(1)))
        T.eq(2, W.trough().feedbag); T.eq(nil, W.db.refill[P1])
    end)
    case('troughRefill = false: the server never consumes and never answers the client', function()
        local W = world(false); W.trough().feedbag = 2; W.peds[1] = at(p1)
        T.same({ false, 'fh_refill_disabled', n = 2 }, r(W.TR.refill(1)))
        assert(not W.refill(1)); T.eq(2, W.trough().feedbag); T.eq(0, W.calls.removeItem)
        T.eq(false, cfg.trough.troughRefill)
    end)
    case('recording the refill fails: the feedbag goes back into the trough, no client refill', function()
        local W = world(true); W.trough().feedbag = 2; W.peds[1] = at(p1)
        W.fail.refillWrite = true
        T.same({ false, 'fh_trough_save_failed', n = 2 }, r(W.TR.refill(1)))
        T.eq(2, W.trough().feedbag); T.eq(nil, W.db.refill[P1])
        assert(not W.refill(1))
    end)
    case('cooldown read fails: fails closed, nothing consumed', function()
        local W = world(true); W.trough().feedbag = 2; W.peds[1] = at(p1)
        W.fail.refillRead = true
        T.same({ false, 'fh_trough_check_failed', n = 2 }, r(W.TR.refill(1)))
        T.eq(2, W.trough().feedbag)
    end)
    case('locks released after every path (a second refill is not fh_trough_busy; unclaim not fh_chest_busy)', function()
        local W = world(true); W.trough().feedbag = 1; W.peds[1] = at(p1)
        assert(W.refill(1)); T.same({ false, 'fh_trough_empty', n = 2 }, r(W.TR.refill(1)))
        T.same({ true, P1, n = 2 }, r(W.ex.unclaim(0, P1)))
    end)
end)

T.describe('getTrough export', function()
    case('returns the container ref of the character\'s claim trough, else nil', function()
        local W = world()
        T.same({ type = 'chest', id = TID }, W.ex.getTrough('A'))
        T.eq(nil, W.ex.getTrough('B')); T.eq(nil, W.ex.getTrough(nil)); T.eq(nil, W.ex.getTrough(7)); T.eq(nil, W.ex.getTrough(''))
        local W2 = world(false, { plots = { [P1] = 'A' }, slots = {}, refill = {} })
        T.eq(nil, W2.ex.getTrough('A'))
    end)
end)

T.describe('unclaim vs the trough (H20b)', function()
    case('items in the trough block unclaim: fh_trough_not_empty (owner and admin); nothing deleted', function()
        local W = world(); W.trough().feedbag = 1
        T.same({ false, 'fh_trough_not_empty', n = 2 }, r(W.ex.unclaim(1)))
        T.same({ false, 'fh_trough_not_empty', n = 2 }, r(W.ex.unclaim(0, P1)))
        T.eq('A', W.db.plots[P1]); T.eq(1, W.trough().feedbag)
    end)
    case('empty trough: unclaim goes through and the cooldown row goes with the plot', function()
        local W = world(); W.db.refill[P1] = T0
        T.same({ true, P1, n = 2 }, r(W.ex.unclaim(1)))
        T.eq(nil, W.db.plots[P1]); T.eq(nil, W.db.refill[P1])
    end)
    case('admin force: logs the feedbags, empties the trough, releases the plot', function()
        local W = world(); W.trough().feedbag = 2
        T.same({ true, P1, n = 2 }, r(W.ex.unclaim(0, P1, true)))
        T.eq(nil, W.db.plots[P1])
        assert(W.logged('force unclaim: plot=heartlands_01 owner=A stash=' .. TID .. ' slot=%d+ item=feedbag count=2 cleared'))
        T.eq(nil, W.trough().feedbag)
        T.same({ false, 'fh_not_admin', n = 2 }, r(world().ex.unclaim(1, P1, true)))
    end)
    case('trough read fails: refused fh_trough_check_failed (fails closed), even forced', function()
        local W = world(); W.fail.snapshot = 'boom'
        T.same({ false, 'fh_trough_check_failed', n = 2 }, r(W.ex.unclaim(1)))
        T.same({ false, 'fh_trough_check_failed', n = 2 }, r(W.ex.unclaim(0, P1, true)))
        T.eq('A', W.db.plots[P1])
    end)
    case('no trough built: unclaim is not blocked by it', function()
        local W = world(false, { plots = { [P1] = 'A' }, slots = {}, refill = {} })
        T.same({ true, P1, n = 2 }, r(W.ex.unclaim(1)))
    end)
end)

T.finish()

-- H2 build flow: shared/build_rules.lua H2 helpers (pure) + server/build.lua with server/main.lua and server/slots.lua
-- in a stubbed FXServer world: in-memory MySQL, fh_core (removeItem/addItem/registerContainer/registerItems),
-- fh_economy (charge/pay), rsg-core players. An await can be HELD (W.hold[tag] = true): the call yields there, so a
-- spec can run a second call / an unclaim while the first is suspended, as FXServer would between coroutines.
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local case = T.it
local dir = here .. '../server/resources/[fh]/fh_homestead/'
local R = dofile(dir .. 'shared/build_rules.lua')
local PR = dofile(dir .. 'shared/plot_rules.lua')
local ST = dofile(dir .. 'shared/stations.lua')
dofile(dir .. 'config.lua')
local cfg = FhHomesteadConfig
local P1, P2 = 'heartlands_01', 'heartlands_02'
local p1 = cfg.plots[P1]
local function at(plot, dx, dy) return { x = plot.center.x + (dx or 0), y = plot.center.y + (dy or 0), z = plot.center.z } end

-- ------------------------------------------------------------------------------------------- pure helpers
T.describe('build_rules H2 helpers', function()
    case('costList: sorted items, whole amounts, money >= 0; bad costs refused', function()
        local c = R.costList({ money = 400, items = { nails = 20, lumber = 40 } })
        T.same({ money = 400, items = { { item = 'lumber', amount = 40 }, { item = 'nails', amount = 20 } } }, c)
        T.same({ money = 0, items = {} }, R.costList({}))
        T.eq(nil, (R.costList(nil)))
        T.eq(nil, (R.costList({ money = -1 })))
        T.eq(nil, (R.costList({ money = 1.5 })))
        T.eq(nil, (R.costList({ money = 5, items = { lumber = 0 } })))
        T.eq(nil, (R.costList({ money = 5, items = { lumber = 2.5 } })))
        T.eq(nil, (R.costList({ money = 5, items = { lumber = '3' } })))
        for id, slot in pairs(p1.slots) do
            for tier = 1, slot.maxTier do assert(R.costList(R.costFor(slot, tier)), id .. ' tier ' .. tier .. ' cost') end
        end
    end)
    case('safeRadius: base, plus the fence bonus once built', function()
        T.eq(25.0, R.safeRadius(p1, {}, cfg.baseSafeRadius))
        T.eq(35.0, R.safeRadius(p1, { fence = 1 }, cfg.baseSafeRadius))
        T.eq(25.0, R.safeRadius(p1, { fence = 0, cabin = 2 }, cfg.baseSafeRadius))
        T.eq(p1.radius, R.safeRadius(p1, nil, nil)) -- no base configured: the plot radius
        T.eq(0, R.safeRadius(nil, nil, 10))
    end)
    case('chestNumber: chest-kind slots only', function()
        T.eq(2, R.chestNumber('chest_2', p1.slots.chest_2))
        T.eq(3, R.chestNumber('chest_3', p1.slots.chest_3))
        T.eq(nil, R.chestNumber('cabin', p1.slots.cabin))
        T.eq(nil, R.chestNumber('chest_1', { kind = 'chest' }))
        T.eq(nil, R.chestNumber('chest_x', { kind = 'chest' }))
        T.eq(nil, R.chestNumber('station_2', { kind = 'chest' }))
    end)
    case('slotProps: built slots only, fallback vs verified props per the flag', function()
        T.eq(0, #R.slotProps(p1, {}, false))
        local l = R.slotProps(p1, { cabin = 1, chest_2 = 1 }, false)
        T.eq(2, #l)
        T.eq('cabin', l[1].slot_id); T.eq(1, l[1].tier); T.eq('p_chest01x', l[1].model); T.eq(nil, l[1].chest)
        T.eq(p1.center.x - 8.0, l[1].coords.x)
        T.eq('chest_2', l[2].slot_id); T.eq(2, l[2].chest)
        local plot = { id = 'x', center = { x = 0, y = 0, z = 0 }, slots = {
            a = { kind = 'cabin', maxTier = 1, prop = { model = 'fallback', offset = { x = 1, y = 0, z = 0 } },
                propVerified = { model = 'real', offset = { x = 2, y = 0, z = 0 }, heading = 90.0 } } } }
        T.eq('fallback', R.slotProps(plot, { a = 1 }, false)[1].model)
        local v = R.slotProps(plot, { a = 1 }, true)[1]
        T.eq('real', v.model); T.eq(2, v.coords.x); T.eq(90.0, v.heading)
        T.eq(0, #R.slotProps(nil, nil, false))
    end)
end)

-- ------------------------------------------------------------------------------------------- server world
local function readSrc(p) local fh = assert(io.open(p, 'rb')); local s = fh:read('a'); fh:close(); return s end
local MAIN_SRC, SLOTS_SRC, BUILD_SRC = readSrc(dir .. 'server/main.lua'), readSrc(dir .. 'server/slots.lua'),
    readSrc(dir .. 'server/build.lua')

local function newWorld(wcfg)
    local cfg = wcfg or cfg -- H9: a world may run on a config with extra (town lot) plots
    local W = { db = { plots = {}, slots = {}, class = {} }, events = {}, handlers = {}, threads = {}, ex = {}, logs = {}, client = {},
        commands = {}, callbacks = {}, players = { [1] = 'A', [2] = 'B' }, peds = {}, hold = {}, order = {},
        chest = {}, cash = { A = 1000, B = 1000 }, containers = {}, opened = {}, registeredItems = {},
        pending = {}, known = { A = true, B = true },
        calls = { removeItem = 0, addItem = 0, charge = 0, pay = 0, credit = 0, registerItems = 0 } }
    W.peds[1], W.peds[2] = at(p1), at(cfg.plots[P2])
    local function await(tag)
        W.order[#W.order + 1] = tag
        if W.hold[tag] and coroutine.isyieldable() then W.hold[tag] = nil; coroutine.yield(tag) end
    end
    local function fire(name, ...)
        W.events[#W.events + 1] = { name = name, args = table.pack(...) }
        for _, h in ipairs(W.handlers[name] or {}) do h(...) end
    end
    local function key(p, s) return p .. '|' .. s end
    local function exec(sql, p)
        p = p or {}
        if sql:find('^SELECT %* FROM fh_plots') then -- rows carry no class unless W.db.class says: claims (H7 fallback)
            local rows = {}
            for pid, cid in pairs(W.db.plots) do rows[#rows + 1] = { plot_id = pid, citizenid = cid, class = W.db.class[pid] } end
            return rows
        elseif sql:find('^SELECT plot_id, slot_id, tier FROM fh_plot_slots') then
            local rows = {}
            for k, t in pairs(W.db.slots) do
                local pid, sid = k:match('^(.-)|(.*)$')
                rows[#rows + 1] = { plot_id = pid, slot_id = sid, tier = t }
            end
            return rows
        elseif sql:find('^INSERT INTO fh_plot_slots') then
            await('slot_write')
            if W.failSlotWrite then error('db down') end
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
            await('delete_plot')
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
    local function db(sql, p) return exec(sql, p) end
    local core = { Functions = { GetPlayer = function(src)
        local cid = W.players[src]
        return cid and { PlayerData = { citizenid = cid } } or nil
    end } }
    -- carried ref { type = 'backpack', id = src } (C3a): W.chest['bag:<src>']; refused fh_player_offline while nobody is
    -- loaded on src or W.bagOffline; W.bagThrows makes every backpack call throw, W.bagNoSnapshot the snapshot export
    -- missing for it; W.bagAddRefuses refuses backpack adds (nothing added)
    local function stash(ref) return ref.type == 'backpack' and ('bag:' .. tostring(ref.id)) or ref.id end
    local function bagDown(ref)
        if ref.type ~= 'backpack' then return nil end
        if W.bagThrows then error('fh_core backpack gone') end
        if type(ref.id) ~= 'number' then return 'fh_bad_ref' end
        if W.bagOffline or not W.players[ref.id] then return 'fh_player_offline' end
        return nil
    end
    local X = {
        ['rsg-core'] = { GetCoreObject = function() return core end },
        fh_core = {
            registerContainer = function(_, ref, opts) W.containers[ref.id] = opts; return true end,
            open = function(_, src, ref) W.opened[#W.opened + 1] = { src = src, ref = ref }; return true end,
            registerItems = function(_, defs)
                W.calls.registerItems = W.calls.registerItems + 1
                for n in pairs(defs) do W.registeredItems[n] = true end
                return true
            end,
            -- H13: unclaim reads (and on force empties) the plot stashes; W.chest[id] = { item = count }
            snapshot = function(_, ref)
                if ref.type == 'backpack' and W.bagNoSnapshot then error('No such export snapshot in resource fh_core') end
                local down = bagDown(ref)
                if down then return nil, down end
                local s = stash(ref)
                if ref.type ~= 'backpack' and not (W.containers[s] or W.chest[s]) then return nil, 'fh_unknown_container' end
                local out, slot = {}, 0
                for item, n in pairs(W.chest[s] or {}) do
                    if n > 0 then slot = slot + 1; out[slot] = { name = item, amount = n } end
                end
                return out
            end,
            clearContainer = function(_, ref)
                W.chest[stash(ref)] = {}
                return true
            end,
            removeItem = function(_, ref, item, n)
                W.calls.removeItem = W.calls.removeItem + 1
                if W.removeThrows then error('fh_core gone') end
                local down = bagDown(ref)
                if down then return false, down end
                if ref.type == 'backpack' and W.bagRemoveOffline then return false, 'fh_player_offline' end
                local s = stash(ref)
                W.chest[s] = W.chest[s] or {}
                if (W.chest[s][item] or 0) < n then return false, 'fh_not_enough' end
                W.chest[s][item] = W.chest[s][item] - n
                await('removeItem') -- removed; the caller resumes later
                return true
            end,
            addItem = function(_, ref, item, n)
                W.calls.addItem = W.calls.addItem + 1
                await('addItem')
                if W.addRefuses then return false, W.addRefuses end
                local down = bagDown(ref)
                if down then return false, down end
                if ref.type == 'backpack' and W.bagAddRefuses then return false, W.bagAddRefuses end
                local s = stash(ref)
                W.chest[s] = W.chest[s] or {}
                W.chest[s][item] = (W.chest[s][item] or 0) + n
                return true
            end,
        },
        fh_economy = {
            charge = function(_, src, amount, reason, region)
                W.calls.charge = W.calls.charge + 1
                W.lastCharge = { src = src, amount = amount, reason = reason, region = region }
                if W.chargeThrows then error('fh_economy gone') end
                if W.chargeFails then return false, W.chargeFails end
                local cid = W.players[src]
                if not cid then return false, 'no_player' end
                if (W.cash[cid] or 0) < amount then return false, 'fh_insufficient_funds' end
                await('charge')
                W.cash[cid] = W.cash[cid] - amount
                await('charged')
                if W.chargeFailsLate then -- refused after a hold (the stub keeps the debit out: nothing was taken)
                    W.cash[cid] = W.cash[cid] + amount
                    return false, W.chargeFailsLate
                end
                return true, nil, 1
            end,
            pay = function(_, src, amount, reason, region)
                W.calls.pay = W.calls.pay + 1
                W.lastPay = { src = src, amount = amount, reason = reason, region = region }
                await('pay')
                if W.payFails then return false, W.payFails end
                local cid = W.players[src]
                if not cid then return false, 'no_player' end
                W.cash[cid] = (W.cash[cid] or 0) + amount
                return true, nil, 2
            end,
            -- core-04 E2 contract: by citizenid; online -> 'paid', offline -> queued 'pending'
            credit = function(_, cid, amount, reason, region)
                W.calls.credit = W.calls.credit + 1
                W.lastCredit = { cid = cid, amount = amount, reason = reason, region = region }
                await('credit')
                if W.creditThrows then error('fh_economy gone') end
                if W.creditFails then return false, W.creditFails end
                if not W.known[cid] then return false, 'unknown_citizenid' end
                local online = false
                for _, c in pairs(W.players) do if c == cid then online = true end end
                if online then
                    W.cash[cid] = (W.cash[cid] or 0) + amount
                    W.lastCredit.mode = 'paid'
                else
                    W.pending[cid] = (W.pending[cid] or 0) + amount
                    W.lastCredit.mode = 'pending'
                end
                return true, nil, W.lastCredit.mode
            end,
        },
    }
    local exportsT = setmetatable({}, {
        __call = function(_, name, fn) W.ex[name] = fn end,
        __index = function(_, res)
            if res == 'fh_homestead' then -- own exports, as the in-resource commands call them
                return setmetatable({}, { __index = function(_, k) return function(_, ...) return W.ex[k](...) end end })
            end
            return X[res] or {}
        end,
    })
    W.env = setmetatable({
        FhHomesteadConfig = cfg, FhPlotRules = PR, FhStations = ST, FhBuildRules = R,
        MySQL = { query = { await = db }, update = { await = db }, insert = { await = db }, scalar = { await = db } },
        CreateThread = function(fn) W.threads[#W.threads + 1] = fn end, Wait = function() end,
        AddEventHandler = function(name, fn) W.handlers[name] = W.handlers[name] or {}; table.insert(W.handlers[name], fn) end,
        RegisterNetEvent = function(name, fn) W.net = W.net or {}; W.net[name] = fn end,
        TriggerEvent = fire,
        TriggerClientEvent = function(name, target, ...) W.client[#W.client + 1] = { name = name, target = target, args = table.pack(...) } end,
        exports = exportsT, IsPlayerAceAllowed = function() return false end,
        GetResourceState = function() return 'started' end, GetCurrentResourceName = function() return 'fh_homestead' end,
        lib = { callback = { register = function(name, fn) W.callbacks[name] = fn end },
            addCommand = function(name, _, fn) W.commands[name] = fn end },
        GetPlayerPed = function(src) return W.peds[src] and src or 0 end,
        GetEntityCoords = function(ped) return W.peds[ped] end,
        print = function(m) W.logs[#W.logs + 1] = tostring(m) end,
    }, { __index = _G })
    assert(load(MAIN_SRC, '@main.lua', 't', W.env))()
    assert(load(SLOTS_SRC, '@slots.lua', 't', W.env))()
    assert(load(BUILD_SRC, '@build.lua', 't', W.env))()
    W.slots, W.B = W.env.FhHomesteadSlots, W.env.FhHomesteadBuild
    -- threads: [1] main.lua loadClaims, [2] slots.lua boot load, [3] build.lua items + chests (run after the boot)
    W.boot = function() W.threads[1](); assert(W.slots.load()); W.threads[3]() end
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
    W.build = function(src, slot) return W.B.build(src, slot) end
    -- admin force (H13): these specs leave build materials in the chests; force logs + empties them, then releases
    W.unclaim = function(plotId) return W.ex.unclaim(0, plotId, true) end
    W.named = function(name)
        local out = {}
        for _, e in ipairs(W.events) do if e.name == name then out[#out + 1] = e.args end end
        return out
    end
    W.logged = function(pat) for _, m in ipairs(W.logs) do if m:find(pat) then return true end end return false end
    W.bag = function(src) local s = 'bag:' .. (src or 1); W.chest[s] = W.chest[s] or {}; return W.chest[s] end
    W.chest1 = function(plotId) local s = PR.chestStashId(plotId or P1, 1); W.chest[s] = W.chest[s] or {}; return W.chest[s] end
    return W
end

-- A world where A owns heartlands_01 with a stocked chest; `tiers` pre-built in the DB.
local function world(tiers, stock)
    local W = newWorld()
    W.db.plots[P1] = 'A'
    for sid, t in pairs(tiers or {}) do W.db.slots[P1 .. '|' .. sid] = t end
    W.boot()
    local c = W.chest1()
    for k, v in pairs(stock or { lumber = 100, nails = 50 }) do c[k] = v end
    return W
end

local function snapshot(W) return { lumber = W.chest1().lumber, nails = W.chest1().nails, cash = W.cash.A } end

T.describe('server/build.lua', function()
    case('happy path: materials then money then tier; event, client push, nothing refunded', function()
        local W = world()
        local ok, tier, cost = W.build(1, 'cabin')
        assert(ok == true and tier == 1, tostring(tier))
        T.eq(150, cost.money)
        T.eq(80, W.chest1().lumber); T.eq(850, W.cash.A)
        T.eq(1, W.db.slots[P1 .. '|cabin']); T.eq(1, W.slots.getTiers(P1).cabin)
        T.eq(0, W.calls.addItem); T.eq(0, W.calls.pay)
        T.eq('homestead build', W.lastCharge.reason); T.eq('heartlands', W.lastCharge.region); T.eq(150, W.lastCharge.amount)
        -- order: removeItem before charge before the slot write
        local seen = {}
        for i, tag in ipairs(W.order) do seen[tag] = seen[tag] or i end
        assert(seen.removeItem < seen.charge and seen.charge < seen.slot_write, 'order removeItem -> charge -> setTier')
        T.eq(1, #W.named('fh:homestead:slot_changed'))
        local push = W.client[#W.client]
        T.eq('fh:homestead:slot_props', push.name); T.eq(-1, push.target); T.eq(P1, push.args[1])
        T.eq('cabin', push.args[2][1].slot_id)
        -- tier 2 next: two materials, sorted
        local ok2, t2 = W.build(1, 'cabin')
        assert(ok2 and t2 == 2)
        T.eq(40, W.chest1().lumber); T.eq(30, W.chest1().nails); T.eq(450, W.cash.A)
        T.eq('fh_max_tier', select(2, W.build(1, 'cabin')))
    end)

    for _, code in ipairs({ 'fh_insufficient_funds', 'ledger_failed', 'removemoney_refused', 'no_player', 'player_changed', 'fh_charge_busy' }) do
        case('charge error ' .. code .. ': no build, each material refunded exactly once, no pay', function()
            local W = world({ cabin = 1 })
            local before = snapshot(W)
            W.chargeFails = code
            local ok, why = W.build(1, 'cabin') -- tier 2: lumber 40 + nails 20
            assert(ok == false and why == code, tostring(why))
            T.same(before, snapshot(W))
            T.eq(2, W.calls.removeItem); T.eq(2, W.calls.addItem); T.eq(0, W.calls.pay); T.eq(0, W.calls.credit)
            T.eq(1, W.slots.getTiers(P1).cabin)
            T.eq(0, #W.named('fh:homestead:slot_changed'))
        end)
    end
    case('real shortfall of cash (no stub) is fh_insufficient_funds with the items back', function()
        local W = world()
        W.cash.A = 10
        local ok, why = W.build(1, 'cabin')
        assert(not ok and why == 'fh_insufficient_funds')
        T.eq(100, W.chest1().lumber); T.eq(10, W.cash.A); T.eq(1, W.calls.addItem)
    end)
    case('charge export throws: fh_charge_unavailable, items back', function()
        local W = world()
        W.chargeThrows = true
        local ok, why = W.build(1, 'fence')
        assert(not ok and why == 'fh_charge_unavailable', tostring(why))
        T.eq(100, W.chest1().lumber); T.eq(1000, W.cash.A); T.eq(0, W.calls.pay)
    end)
    case('removeItem fh_not_enough: no charge; items taken before the short one go back', function()
        local W = world({ cabin = 1 }, { lumber = 100, nails = 5 })
        local ok, why, item = W.build(1, 'cabin')
        assert(ok == false and why == 'fh_not_enough' and item == 'nails', tostring(why))
        T.eq(0, W.calls.charge)
        T.eq(100, W.chest1().lumber); T.eq(5, W.chest1().nails); T.eq(1000, W.cash.A)
        T.eq(1, W.calls.addItem) -- only the lumber that was taken
        -- first material short: nothing taken, nothing refunded
        local W2 = world({}, { lumber = 3 })
        assert(select(2, W2.build(1, 'cabin')) == 'fh_not_enough')
        T.eq(0, W2.calls.charge); T.eq(0, W2.calls.addItem); T.eq(3, W2.chest1().lumber)
    end)
    case('removeItem throws: fh_removeitem_unavailable, no charge', function()
        local W = world()
        W.removeThrows = true
        assert(select(2, W.build(1, 'cabin')) == 'fh_removeitem_unavailable')
        T.eq(0, W.calls.charge); T.eq(0, W.calls.addItem)
    end)
    case('setTier failure after a successful charge: money and items refunded, logged', function()
        local W = world({ cabin = 1 })
        local before = snapshot(W)
        W.failSlotWrite = true
        local ok, why = W.build(1, 'cabin')
        assert(ok == false and why == 'fh_slot_save_failed', tostring(why))
        T.same(before, snapshot(W))
        T.eq(1, W.calls.charge); T.eq(1, W.calls.credit); T.eq(0, W.calls.pay); T.eq(2, W.calls.addItem)
        T.eq('A', W.lastCredit.cid); T.eq(400, W.lastCredit.amount); T.eq('homestead build refund', W.lastCredit.reason)
        T.eq('heartlands', W.lastCredit.region); T.eq('paid', W.lastCredit.mode)
        T.eq(nil, W.pending.A)
        assert(W.logged('setTier heartlands_01/cabin %-> 2 failed'), 'setTier failure logged')
        assert(not W.logged('MONEY LOST') and not W.logged('pending credit'), 'paid online: no loss, no queue log')
        T.eq(1, W.slots.getTiers(P1).cabin)
    end)
    case('Lua error inside the flow (setTier throws): refunds, lock released', function()
        local W = world()
        local real = W.slots.setTier
        W.slots.setTier = function() error('boom') end
        local ok, why = W.build(1, 'cabin')
        assert(ok == false and why == 'fh_build_failed', tostring(why))
        T.eq(100, W.chest1().lumber); T.eq(1000, W.cash.A); T.eq(1, W.calls.credit); T.eq(0, W.calls.pay)
        assert(W.logged('errored'))
        W.slots.setTier = real
        assert(W.build(1, 'cabin'), 'lock released after the error')
    end)
    case('Lua error after the tier was written: still a success with tier + cost, nothing refunded, command replies', function()
        local W = world()
        local realChest = R.chestNumber
        R.chestNumber = function() error('chest boom') end -- registerSlotChest runs after setTier
        local ok, tier, cost = W.build(1, 'cabin')
        R.chestNumber = realChest
        assert(ok == true and tier == 1 and cost and cost.money == 150, tostring(tier))
        T.eq(80, W.chest1().lumber); T.eq(850, W.cash.A); T.eq(0, W.calls.pay); T.eq(0, W.calls.addItem)
        T.eq(1, W.slots.getTiers(P1).cabin)
        assert(W.logged('tier 1 was saved before the error; kept'), 'the throw came out of setTier (slot_changed push)')
        R.chestNumber = function() error('chest boom') end
        W.commands.fh_build(1, { slot = 'fence' }) -- must not crash on the success message
        R.chestNumber = realChest
        T.eq('fh_build: built fence tier 1 ($100, 15 lumber)', W.client[#W.client].args[1].args[2])
        -- only the chest registration after setTier throws (st.done path): the 1st chestNumber call is the prop push
        -- inside setTier (one built slot -> one call), the 2nd is registerSlotChest
        local W2 = world()
        local n = 0
        R.chestNumber = function(...) n = n + 1; if n == 2 then error('register boom') end return realChest(...) end
        local ok2, tier2, cost2 = W2.build(1, 'cabin')
        R.chestNumber = realChest
        T.eq(2, n)
        assert(ok2 == true and tier2 == 1 and cost2.money == 150, tostring(tier2))
        assert(not W2.logged('was saved before the error'), 'st.done path, not the cache check')
        T.eq(0, W2.calls.pay); T.eq(0, W2.calls.addItem); T.eq(850, W2.cash.A)
    end)
    case('error inside the error path (log throws): lock still released, reported as a failed refund', function()
        local W = world()
        local real, realPrint = W.slots.setTier, W.env.print
        W.slots.setTier = function() error('boom') end
        W.env.print = function() error('console gone') end
        local ok, why = W.build(1, 'cabin')
        W.slots.setTier, W.env.print = real, realPrint
        assert(ok == false and why == 'fh_build_refund_failed', tostring(why))
        local ok2, tier2 = W.build(1, 'cabin')
        assert(ok2 == true and tier2 == 1, 'lock released: ' .. tostring(tier2))
    end)
    case('double-fire: the second /fh_build while the first is suspended is refused; one build, one charge', function()
        local W = world()
        W.hold.charge = true
        local h = W.start(function() return W.build(1, 'cabin') end)
        assert(not h.done, 'first build suspended in charge')
        local ok2, why2 = W.build(1, 'cabin')
        assert(ok2 == false and why2 == 'fh_build_busy', tostring(why2))
        assert(select(2, W.build(1, 'fence')) == 'fh_build_busy', 'per-plot/char lock covers other slots too')
        local ok, tier = W.finish(h)
        assert(ok and tier == 1)
        T.eq(1, W.calls.charge); T.eq(850, W.cash.A); T.eq(80, W.chest1().lumber)
        T.eq(1, #W.named('fh:homestead:slot_changed'))
        -- through the command too
        W.hold.charge = true
        local h2 = W.start(function() return W.build(1, 'fence') end)
        W.commands.fh_build(1, { slot = 'fence' })
        local last = W.client[#W.client]
        T.eq('chat:addMessage', last.name)
        assert(last.args[1].args[2]:find('fh_build_busy'), last.args[1].args[2])
        assert(W.finish(h2))
        T.eq(1, W.slots.getTiers(P1).fence)
    end)
    -- H13: a build holds the plot's chests (FhHomesteadClaims.beginChestWrite) from before its first removeItem until its
    -- lock is released, so an unclaim (owner or admin force) can never run mid-build and let a refund land in the next
    -- owner's chest. Replaces the H2 "unclaim mid-build -> refund into the released chest" cases.
    case('unclaim (even admin force) mid-build is refused fh_chest_busy in every phase; the build completes', function()
        for _, tag in ipairs({ 'removeItem', 'charged', 'slot_write' }) do
            local W = world()
            W.hold[tag] = true
            local h = W.start(function() return W.build(1, 'cabin') end)
            assert(not h.done, tag .. ': build suspended')
            T.same({ false, 'fh_chest_busy' }, { W.unclaim(P1) }, tag .. ': admin force refused')
            T.same({ false, 'fh_chest_busy' }, { W.ex.unclaim(0, P1) }, tag .. ': admin refused')
            T.eq('A', W.db.plots[P1], tag .. ': row kept')
            local ok, tier = W.finish(h)
            assert(ok == true and tier == 1, tag .. ': ' .. tostring(tier))
            T.eq(850, W.cash.A); T.eq(80, W.chest1().lumber); T.eq(0, W.calls.addItem, tag .. ': nothing refunded')
            -- hold released with the build lock: the leftovers now block a plain unclaim, force clears them
            T.same({ false, 'fh_chests_not_empty' }, { W.ex.unclaim(0, P1) }, tag)
            T.same({ true, P1 }, { W.unclaim(P1) }, tag)
            T.eq(nil, next(W.chest1()), tag .. ': chest emptied')
        end
    end)
    case('a build is refused fh_claim_busy while an unclaim of the plot is in flight; nothing taken', function()
        local W = world()
        W.chest1().lumber, W.chest1().nails = nil, nil -- empty chests: the owner's own unclaim goes through
        W.hold.delete_plot = true
        local h = W.start(function() return W.ex.unclaim(1, P1) end)
        assert(not h.done, 'unclaim suspended in its DELETE')
        T.same({ false, 'fh_claim_busy' }, { W.build(1, 'cabin') })
        T.eq(0, W.calls.removeItem); T.eq(0, W.calls.charge)
        T.same({ true, P1 }, { W.finish(h) })
        T.eq('fh_no_plot', select(2, W.build(1, 'cabin')))
    end)
    case('not ready: refused fh_not_ready, nothing taken', function()
        local W = newWorld()
        W.db.plots[P1] = 'A'
        W.threads[1]() -- claims loaded, slot cache not
        W.chest1().lumber = 100
        T.eq('fh_not_ready', select(2, W.build(1, 'cabin')))
        T.eq(0, W.calls.removeItem); T.eq(0, W.calls.charge)
        T.eq(nil, W.callbacks['fh:homestead:slot_props']()) -- client asked to retry
    end)
    case('rules first: no plot, outside the plot, unknown slot, prerequisite, max tier; nothing taken', function()
        local W = world()
        T.eq('fh_no_plot', select(2, W.build(2, 'cabin')))
        W.peds[1] = at(p1, 40, 0)
        T.eq('fh_not_in_plot', select(2, W.build(1, 'cabin')))
        W.peds[1] = at(p1, 5, 5)
        T.eq('fh_unknown_slot', select(2, W.build(1, 'castle')))
        T.eq('fh_unknown_slot', select(2, W.build(1, nil)))
        T.eq('fh_prereq_missing', select(2, W.build(1, 'chest_2')))
        T.eq('fh_no_character', select(2, W.build(7, 'cabin')))
        T.eq(0, W.calls.removeItem); T.eq(0, W.calls.charge)
    end)
    case('refund failures are logged loudly with citizenid/item/amount and reported', function()
        local W = world({ cabin = 1 })
        W.chargeFails = 'ledger_failed'
        W.addRefuses = 'fh_too_heavy'
        local ok, why = W.build(1, 'cabin')
        assert(ok == false and why == 'fh_build_refund_failed', tostring(why))
        assert(W.logged('ITEM LOST: build refund failed: citizenid=A plot=heartlands_01 slot=cabin item=nails amount=20'))
        assert(W.logged('ITEM LOST: build refund failed: citizenid=A plot=heartlands_01 slot=cabin item=lumber amount=40'))
        T.eq(2, W.calls.addItem) -- tried once each, never retried
        -- credit refused (c): MONEY LOST with citizenid / amount / err / plot / slot / build_error
        local W3 = world()
        W3.failSlotWrite, W3.creditFails = true, 'ledger_failed'
        assert(select(2, W3.build(1, 'cabin')) == 'fh_build_refund_failed')
        assert(W3.logged('MONEY LOST: build refund of %$150 to citizenid=A failed: ledger_failed; plot=heartlands_01 slot=cabin build_error=fh_slot_save_failed'))
        T.eq(1, W3.calls.credit); T.eq(0, W3.calls.pay); T.eq(850, W3.cash.A)
        T.eq(100, W3.chest1().lumber) -- the items still went back
        -- unknown citizenid (contract refusal) is a failed refund too
        local W4 = world()
        W4.failSlotWrite, W4.known.A = true, nil
        assert(select(2, W4.build(1, 'cabin')) == 'fh_build_refund_failed')
        assert(W4.logged('MONEY LOST: build refund of %$150 to citizenid=A failed: unknown_citizenid'))
        -- credit export throws: failed refund, logged with the error
        local W5 = world()
        W5.failSlotWrite, W5.creditThrows = true, true
        assert(select(2, W5.build(1, 'cabin')) == 'fh_build_refund_failed')
        assert(W5.logged('MONEY LOST: build refund of %$150 to citizenid=A failed: .*fh_economy gone'))
        T.eq(1, W5.calls.credit)
    end)
    for _, swap in ipairs({ { 'switched to another character', 'B' }, { 'logged out', nil } }) do
        case('player ' .. swap[1] .. ' before the refund (b): credited to the original citizenid as pending, not lost', function()
            local W = world()
            W.failSlotWrite = true
            W.hold.slot_write = true
            local h = W.start(function() return W.build(1, 'cabin') end)
            T.eq(850, W.cash.A)
            W.players[1] = swap[2]
            local ok, why = W.finish(h)
            assert(ok == false and why == 'fh_slot_save_failed', tostring(why))
            T.eq(1, W.calls.credit); T.eq(0, W.calls.pay)
            T.eq('A', W.lastCredit.cid); T.eq(150, W.lastCredit.amount); T.eq('pending', W.lastCredit.mode)
            T.eq(150, W.pending.A); T.eq(nil, W.pending.B)
            T.eq(1000, W.cash.B) -- never paid to whoever is on src now
            assert(not W.logged('MONEY LOST'), 'a queued credit is not a loss')
            assert(W.logged('build refund of %$150 to citizenid=A queued as a pending credit'), 'pending logged at info')
            T.eq(100, W.chest1().lumber)
        end)
    end
    case('refund-once (d): the error path after an in-flow refund does not credit again', function()
        -- the in-flow abort credits (pending), then its info log throws -> buildLocked errors -> the error path aborts
        -- again with st.charged already 0: no second credit, no second item refund
        local W = world({ cabin = 1 })
        W.failSlotWrite = true
        W.hold.slot_write = true
        local h = W.start(function() return W.build(1, 'cabin') end)
        W.players[1] = nil
        local realPrint = W.env.print
        W.env.print = function(m)
            if tostring(m):find('queued as a pending credit') then error('console gone') end
            return realPrint(m)
        end
        local ok, why = W.finish(h)
        W.env.print = realPrint
        assert(ok == false and why == 'fh_build_failed', tostring(why))
        assert(W.logged('errored'), 'went through the error path')
        T.eq(1, W.calls.credit); T.eq(400, W.pending.A); T.eq(2, W.calls.addItem)
        T.eq(100, W.chest1().lumber); T.eq(50, W.chest1().nails)
        W.players[1] = 'A'
        W.failSlotWrite = false
        local ok2, tier2 = W.build(1, 'cabin')
        assert(ok2 == true and tier2 == 2, 'lock released: ' .. tostring(tier2))
        T.eq(1, W.calls.credit)
    end)
    case('character switched before the charge: not charged to the new character', function()
        local W = world()
        W.hold.removeItem = true
        local h = W.start(function() return W.build(1, 'cabin') end)
        W.players[1] = 'B'
        local ok, why = W.finish(h)
        assert(ok == false and why == 'player_changed', tostring(why))
        T.eq(0, W.calls.charge); T.eq(1000, W.cash.B); T.eq(100, W.chest1().lumber)
    end)
    case('registerItems: build materials registered from fh_homestead at start and on fh_core restart', function()
        local W = world()
        T.eq(1, W.calls.registerItems)
        assert(W.registeredItems.lumber and W.registeredItems.nails)
        for _, h in ipairs(W.handlers.onResourceStart) do h('fh_core') end
        T.eq(2, W.calls.registerItems)
        for _, def in pairs(cfg.buildItems) do
            assert(type(def.label) == 'string' and type(def.weight) == 'number' and def.size_class == 'pocket')
        end
        -- every material a cost names is a registered build item
        for _, slot in pairs(p1.slots) do
            for _, t in pairs(slot.tiers) do
                for item in pairs(t.cost.items or {}) do assert(cfg.buildItems[item], item .. ' not in buildItems') end
            end
        end
    end)
    case('extra chests: registered as fh_core chest when built and on load; opening needs the slot built', function()
        local W = world({ cabin = 1 })
        T.eq(nil, W.containers['fh:chest:heartlands_01:2'])
        W.players[1] = 'A'
        W.env.source = 1
        local function lastMsg() local c = W.client[#W.client]; return c and c.args[1].args[2] end
        W.net['fh:homestead:open_chest']({ plot_id = P1, chest = 2 })
        T.eq('chest: fh_chest_not_built', lastMsg())
        T.eq(0, #W.opened)
        assert(W.build(1, 'chest_2'))
        W.net['fh:homestead:open_chest']({ plot_id = P1, chest = 2 })
        T.eq(1, #W.opened)
        T.eq('fh:chest:heartlands_01:2', W.opened[1].ref.id)
        local c = W.containers['fh:chest:heartlands_01:2']
        assert(c, 'chest_2 registered on build')
        T.eq(p1.center.x - 4.0, c.coords.x)
        -- reboot from the DB: built chest slots register again
        local W2 = newWorld()
        W2.db.plots[P1] = 'A'
        W2.db.slots[P1 .. '|cabin'] = 2
        W2.db.slots[P1 .. '|chest_2'] = 1
        W2.db.slots[P1 .. '|chest_3'] = 1
        W2.boot()
        assert(W2.containers['fh:chest:heartlands_01:2'] and W2.containers['fh:chest:heartlands_01:3'])
        -- unclaimed plots' chest slots are not registered on load
        local W3 = newWorld()
        W3.db.slots[P2 .. '|chest_2'] = 1
        W3.boot()
        T.eq(nil, W3.containers['fh:chest:heartlands_02:2'])
    end)
    case('isInSafeZone: claimed plots only; the fence widens the radius', function()
        local W = newWorld()
        T.eq(false, W.ex.isInSafeZone(at(p1)), 'before the claim load')
        W.db.plots[P1] = 'A'
        W.boot()
        W.chest1().lumber = 100
        T.eq(true, W.ex.isInSafeZone(at(p1, 20, 0)))
        T.eq(false, W.ex.isInSafeZone(at(p1, 30, 0)), 'base 25 m')
        T.eq(false, W.ex.isInSafeZone(at(cfg.plots[P2])), 'unclaimed plot is not safe')
        assert(W.build(1, 'fence'))
        T.eq(true, W.ex.isInSafeZone(at(p1, 30, 0)), 'fence: 25 + 10 m')
        T.eq(true, W.ex.isInSafeZone(at(p1, 0, 35)))
        T.eq(false, W.ex.isInSafeZone(at(p1, 36, 0)))
        T.eq(false, W.ex.isInSafeZone(nil))
        assert(W.unclaim(P1))
        T.eq(false, W.ex.isInSafeZone(at(p1)), 'unclaimed again')
    end)
    case('props feed: join snapshot of claimed plots, unclaim pushes an empty set', function()
        local W = world({ cabin = 1, station_1 = 1 })
        local all = W.callbacks['fh:homestead:slot_props']()
        T.eq(2, #all[P1]); T.eq(nil, all[P2])
        T.eq('cabin', all[P1][1].slot_id); T.eq('station_1', all[P1][2].slot_id)
        assert(W.unclaim(P1))
        local push = W.client[#W.client]
        T.eq('fh:homestead:slot_props', push.name); T.eq(P1, push.args[1]); T.eq(0, #push.args[2])
        T.same({}, W.callbacks['fh:homestead:slot_props']())
    end)
    case('/fh_build without a slot lists tiers and next costs', function()
        local W = world({ cabin = 1 })
        W.commands.fh_build(1, {})
        local msg = W.client[#W.client].args[1].args[2]
        assert(msg:find('plot heartlands_01') and msg:find('cabin 1/2 next: %$400, 40 lumber, 20 nails'), msg)
        assert(msg:find('fence 0/1 next: %$100, 15 lumber'), msg)
    end)
    case('/fh_station: owner-only reach check on a built station (isNearStation)', function()
        local W = world()
        local function say(src, t) W.commands.fh_station(src, { type = t }); return W.client[#W.client].args[1].args[2] end
        T.eq('fh_station: workbench near=false', say(1, 'workbench'), 'not built yet')
        assert(W.build(1, 'station_1'))
        W.peds[1] = at(p1, 6, 4) -- the workbench prop offset
        T.eq('fh_station: workbench near=true', say(1, 'workbench'))
        T.eq('fh_station: campfire near=false', say(1, 'campfire'))
        W.peds[2] = at(p1, 6, 4) -- B stands at A's workbench: not their plot
        T.eq('fh_station: workbench near=false', say(2, 'workbench'))
        W.peds[1] = at(p1, 6, 10)
        T.eq('fh_station: workbench near=false', say(1, 'workbench'), 'walked away (> 3 m)')
    end)
end)
-- ------------------------------------------------------------------------------------------- H9 town lots
-- Real lot entries come from @world block B; here a config copy with two test lots (radius 14) next to the claims.
local LOT, LOT2 = 'lot_t1', 'lot_t2'
local lotCfg = setmetatable({ plots = {} }, { __index = cfg })
for id, p in pairs(cfg.plots) do lotCfg.plots[id] = p end
local function lotPlot(id, x)
    return { id = id, class = 'town_lot', region = 'heartlands', center = { x = x, y = 0.0, z = 0.0 }, radius = 14.0,
        chest = { coords = { x = x + 4, y = 0.0, z = 0.0 }, heading = 0.0, model = 'p_chest01x' },
        slots = cfg.slotTemplates.town_lot() }
end
lotCfg.plots[LOT], lotCfg.plots[LOT2] = lotPlot(LOT, 5000.0), lotPlot(LOT2, 6000.0)
local lot = lotCfg.plots[LOT]

-- A owns claim P1 and lot LOT (B owns nothing); both chests stocked.
local function lotWorld(tiers)
    local W = newWorld(lotCfg)
    W.db.plots[P1], W.db.plots[LOT], W.db.class[LOT] = 'A', 'A', 'town_lot'
    for sid, t in pairs(tiers or {}) do W.db.slots[LOT .. '|' .. sid] = t end
    W.boot()
    for _, pid in ipairs({ P1, LOT }) do local c = W.chest1(pid); c.lumber, c.nails = 100, 50 end
    W.peds[1] = at(lot)
    return W
end

T.describe('H9 town lots: slots, stations, safety, plotInfo', function()
    case('/fh_build on a lot: cabin/fence/trophy_wall unknown, nothing taken', function()
        local W = lotWorld()
        for _, sid in ipairs({ 'cabin', 'fence', 'trophy_wall', 'station_2', 'chest_3' }) do
            T.eq('fh_unknown_slot', select(2, W.build(1, sid)), sid)
        end
        W.commands.fh_build(1, { slot = 'cabin' })
        T.eq('fh_build: fh_unknown_slot', W.client[#W.client].args[1].args[2])
        T.eq(0, W.calls.removeItem); T.eq(0, W.calls.charge); T.eq(1000, W.cash.A)
    end)
    case('station_1 on the lot: built from the lot chest, listed by getStations/stationAt/isNearStation', function()
        local W = lotWorld()
        T.eq(1, select(2, W.build(1, 'station_1')))
        T.eq('fh_max_tier', select(2, W.build(1, 'station_1')))
        T.eq(90, W.chest1(LOT).lumber, 'materials from the lot chest'); T.eq(100, W.chest1(P1).lumber)
        T.eq(1, W.db.slots[LOT .. '|station_1']); T.eq(nil, W.db.slots[P1 .. '|station_1'])
        local st = W.ex.getStations('A')
        T.eq(1, #st); T.eq(LOT, st[1].plot_id); T.eq('workbench', st[1].station_type)
        local wb = { x = lot.center.x + 6.0, y = lot.center.y + 4.0, z = lot.center.z }
        T.same({ plot_id = LOT, slot_id = 'station_1', station_type = 'workbench', coords = wb }, W.ex.stationAt(wb, 1.0))
        W.peds[1] = wb
        T.eq(true, W.ex.isNearStation(1, 'workbench'))
        W.peds[2] = wb
        T.eq(false, W.ex.isNearStation(2, 'workbench'), 'owner-only')
        T.eq(0, #W.ex.getStations('B'))
        -- claim workbench too: both listed, claim first
        W.peds[1] = at(p1)
        assert(W.build(1, 'station_1'))
        st = W.ex.getStations('A')
        T.eq(2, #st); T.eq(P1, st[1].plot_id); T.eq(LOT, st[2].plot_id)
        W.commands.fh_station(1, { type = 'workbench' })
        T.eq('fh_station: workbench near=false', W.client[#W.client].args[1].args[2], 'at the claim center, > 3 m')
    end)
    case('chest_2 on a lot needs no cabin and registers its container', function()
        local W = lotWorld()
        T.eq(1, select(2, W.build(1, 'chest_2')))
        assert(W.containers['fh:chest:' .. LOT .. ':2'], 'lot chest_2 registered')
    end)
    case('the build goes to the owned plot you stand in; claim behaviour unchanged', function()
        local W = lotWorld()
        W.peds[1] = at(p1)
        T.eq(1, select(2, W.build(1, 'cabin')), 'claim still has its cabin')
        T.eq(1, W.db.slots[P1 .. '|cabin']); T.eq(nil, W.db.slots[LOT .. '|cabin'])
        W.peds[1] = at(lotCfg.plots[LOT2])
        T.eq('fh_not_in_plot', select(2, W.build(1, 'station_1')), 'someone else\'s (free) lot')
        W.peds[1] = { x = 9000.0, y = 0.0, z = 0.0 }
        T.eq('fh_not_in_plot', select(2, W.build(1, 'station_1')))
        T.eq('fh_no_plot', select(2, W.build(2, 'station_1')), 'B owns nothing')
        -- status lists the plot you stand in
        W.peds[1] = at(lot)
        W.commands.fh_build(1, {})
        local msg = W.client[#W.client].args[1].args[2]
        assert(msg:find('plot ' .. LOT) and msg:find('station_1 0/1') and not msg:find('cabin'), msg)
    end)
    case('lot-only owner: builds on the lot; unclaim of the lot drops its slots and stations', function()
        local W = newWorld(lotCfg)
        W.db.plots[LOT2], W.db.class[LOT2] = 'B', 'town_lot'
        W.boot()
        W.chest1(LOT2).lumber = 100
        W.peds[2] = at(lotCfg.plots[LOT2])
        assert(W.build(2, 'station_1'))
        T.eq(1, #W.ex.getStations('B'))
        assert(W.unclaim(LOT2))
        T.eq(0, #W.ex.getStations('B'))
        T.eq('fh_no_plot', select(2, W.build(2, 'chest_2')))
    end)
    case('isInSafeZone: an owned lot counts out to its radius (no fence bonus); unowned lots do not', function()
        local W = lotWorld()
        T.eq(true, W.ex.isInSafeZone(at(lot, 14.0, 0)), 'lot edge')
        T.eq(true, W.ex.isInSafeZone(at(lot, 0, -14.0)))
        T.eq(false, W.ex.isInSafeZone(at(lot, 14.5, 0)), 'just outside: lot radius, not baseSafeRadius 25')
        T.eq(false, W.ex.isInSafeZone(at(lot, 24.0, 0)))
        local l2 = lotCfg.plots[LOT2]
        T.eq(false, W.ex.isInSafeZone(at(l2)), 'unowned lot')
        T.eq(true, W.ex.isInSafeZone(at(p1, 24.0, 0)), 'claim keeps its 25 m base')
        assert(W.unclaim(LOT))
        T.eq(false, W.ex.isInSafeZone(at(lot)), 'abandoned lot')
    end)
    case('lawSafeAt (idea-803): the owner gets their lot id within plot.radius; non-owners, claims, unowned lots, outside, bad coords = nil', function()
        local W = newWorld(lotCfg)
        local function L(c, cid) if cid == nil then cid = 'A' end return W.ex.lawSafeAt(c, cid) end
        T.eq(nil, L(at(lot)), 'before the claim load')
        W.db.plots[P1], W.db.plots[LOT], W.db.class[LOT] = 'A', 'A', 'town_lot'
        W.boot()
        T.eq(LOT, L(at(lot)), 'inside the owned lot')
        T.eq(LOT, L(at(lot, 14.0, 0)), 'edge: inclusive, same rule as isInSafeZone')
        T.eq(nil, L(at(lot, 14.5, 0)), 'just outside')
        T.eq(nil, L(at(lot, 24.0, 0)), 'inside 25 m base radius but not the lot radius')
        T.eq(true, W.ex.isInSafeZone(at(p1)))
        T.eq(nil, L(at(p1)), 'owned wilderness claim')
        T.eq(nil, L(at(lotCfg.plots[LOT2])), 'unowned lot')
        T.eq(nil, L(nil))
        T.eq(nil, W.ex.lawSafeAt(at(lot)), 'no citizenid: safe default nil')
        T.eq(nil, W.ex.lawSafeAt(at(lot), ''), 'empty citizenid')
        T.eq(nil, W.ex.lawSafeAt(at(lot), 5), 'non-string citizenid')
        T.eq(nil, L('x'))
        T.eq(nil, L({ x = 0 / 0, y = 0, z = 0 }))
        T.eq(nil, L(setmetatable({}, { __index = function() error('boom') end })))
        T.eq(nil, L(at(lot), 'B'), 'non-owner standing in an owned lot')
        assert(W.unclaim(LOT))
        T.eq(nil, L(at(lot)), 'abandoned lot')
    end)
    case('plotInfo: claim = raidable, lot = lawSafe and not raidable; owner or nil; unknown id = nil', function()
        local W = lotWorld()
        local function xyz(pl) return { x = pl.center.x, y = pl.center.y, z = pl.center.z } end
        T.same({ class = 'claim', raidable = true, lawSafe = false, owner = 'A', coords = xyz(p1), region = p1.region,
            fenceBuilt = false }, W.ex.plotInfo(P1))
        T.same({ class = 'town_lot', raidable = false, lawSafe = true, owner = 'A', coords = xyz(lot), region = 'heartlands',
            fenceBuilt = false }, W.ex.plotInfo(LOT))
        T.same({ class = 'town_lot', raidable = false, lawSafe = true, coords = xyz(lotCfg.plots[LOT2]), region = 'heartlands',
            fenceBuilt = false }, W.ex.plotInfo(LOT2), 'unowned lot: owner nil')
        T.same({ class = 'claim', raidable = true, lawSafe = false, coords = xyz(cfg.plots[P2]), region = cfg.plots[P2].region,
            fenceBuilt = false }, W.ex.plotInfo(P2))
        T.eq(nil, W.ex.plotInfo('nope')); T.eq(nil, W.ex.plotInfo(nil)); T.eq(nil, W.ex.plotInfo(5))
    end)
    case('plotInfo fenceBuilt: true once the fence tier is built (same slot state as isInSafeZone), claim only', function()
        local W = world({ fence = 1 })
        T.eq(true, W.ex.plotInfo(P1).fenceBuilt)
        T.eq(false, W.ex.plotInfo(P2).fenceBuilt, 'other plot')
        local W2 = world()
        T.eq(false, W2.ex.plotInfo(P1).fenceBuilt, 'no fence yet')
        assert(W2.build(1, 'fence'))
        T.eq(true, W2.ex.plotInfo(P1).fenceBuilt, 'after building')
        T.eq(true, W2.ex.plotInfo(P1).coords.x == p1.center.x)
    end)
    case('plotInfo before the slot cache loads: fenceBuilt false, no error', function()
        local W = newWorld()
        W.db.plots[P1] = 'A'; W.db.slots[P1 .. '|fence'] = 1
        W.threads[1]() -- claims load only; slots.load() not run yet
        local info = W.ex.plotInfo(P1)
        T.eq(false, info.fenceBuilt); T.eq(P1 and p1.region, info.region); T.eq(p1.center.x, info.coords.x)
    end)
end)
-- ------------------------------------------------------------------------------------------- H14b build from pockets
-- cabin tier 2 costs $400 + 40 lumber + 20 nails. Per item: backpack (W.bag) first, the rest from plot chest 1.
T.describe('H14b build from pockets (backpack first, then plot chest 1)', function()
    local function counts(W)
        return { bag_lumber = W.bag().lumber or 0, bag_nails = W.bag().nails or 0,
            chest_lumber = W.chest1().lumber or 0, chest_nails = W.chest1().nails or 0, cash = W.cash.A }
    end
    local function stocked(bag, chest)
        local W = world({ cabin = 1 }, chest)
        for k, v in pairs(bag or {}) do W.bag()[k] = v end
        return W
    end

    case('split take: backpack first, the rest from the chest', function()
        local W = stocked({ lumber = 30, nails = 5 }, { lumber = 100, nails = 50 })
        local ok, tier = W.build(1, 'cabin')
        assert(ok == true and tier == 2, tostring(tier))
        T.same({ bag_lumber = 0, bag_nails = 0, chest_lumber = 90, chest_nails = 35, cash = 600 }, counts(W))
        T.eq(4, W.calls.removeItem); T.eq(0, W.calls.addItem)
    end)
    case('backpack only: the chest is not touched', function()
        local W = stocked({ lumber = 50, nails = 25 }, { lumber = 100, nails = 50 })
        assert(W.build(1, 'cabin'))
        T.same({ bag_lumber = 10, bag_nails = 5, chest_lumber = 100, chest_nails = 50, cash = 600 }, counts(W))
        T.eq(2, W.calls.removeItem); T.eq(0, W.calls.addItem)
    end)
    case('chest only (empty backpack): as before H14b, no backpack take', function()
        local W = stocked({ water = 3 }, { lumber = 60, nails = 30 })
        assert(W.build(1, 'cabin'))
        T.same({ bag_lumber = 0, bag_nails = 0, chest_lumber = 20, chest_nails = 10, cash = 600 }, counts(W))
        T.eq(3, W.bag().water); T.eq(2, W.calls.removeItem)
    end)
    case('a later take fails: everything taken goes back to its own source, refused with that reason, no charge', function()
        -- second item short in both containers: lumber (bag 30 + chest 10) goes back, nails never taken
        local W = stocked({ lumber = 30, nails = 2 }, { lumber = 100, nails = 3 })
        local before = counts(W)
        local ok, why, item = W.build(1, 'cabin')
        assert(ok == false and why == 'fh_not_enough' and item == 'nails', tostring(why))
        T.same(before, counts(W))
        T.eq(0, W.calls.charge)
        T.eq(4, W.calls.removeItem) -- lumber bag + chest, nails bag (2) ok, nails chest (18 of 3) refused
        T.eq(3, W.calls.addItem)    -- nails bag 2, lumber chest 10, lumber bag 30: once each
        -- chest part of the FIRST item short: its backpack part goes back to the backpack
        local W2 = stocked({ lumber = 30 }, { lumber = 5, nails = 50 })
        local before2 = counts(W2)
        local ok2, why2, item2 = W2.build(1, 'cabin')
        assert(ok2 == false and why2 == 'fh_not_enough' and item2 == 'lumber', tostring(why2))
        T.same(before2, counts(W2))
        T.eq(1, W2.calls.addItem); T.eq(0, W2.calls.charge)
    end)
    case('charge fails: each stack refunded once to its source, no credit; nothing lost or doubled', function()
        local W = stocked({ lumber = 30, nails = 5 }, { lumber = 100, nails = 50 })
        local before = counts(W)
        W.chargeFails = 'ledger_failed'
        local ok, why = W.build(1, 'cabin')
        assert(ok == false and why == 'ledger_failed', tostring(why))
        T.same(before, counts(W))
        T.eq(4, W.calls.removeItem); T.eq(4, W.calls.addItem); T.eq(0, W.calls.credit); T.eq(1, W.slots.getTiers(P1).cabin)
    end)
    case('backpack refund refused (no room / player offline): those stacks land in plot chest 1, logged', function()
        -- online, no room in the backpack
        local W = stocked({ lumber = 30, nails = 5 }, { lumber = 100, nails = 50 })
        W.chargeFails, W.bagAddRefuses = 'ledger_failed', 'fh_too_heavy'
        local ok, why = W.build(1, 'cabin')
        assert(ok == false and why == 'ledger_failed', tostring(why))
        T.same({ bag_lumber = 0, bag_nails = 0, chest_lumber = 130, chest_nails = 55, cash = 1000 }, counts(W))
        T.eq(6, W.calls.addItem) -- 2 chest stacks + 2 refused backpack stacks + 2 into the chest
        assert(W.logged('backpack refused 30 lumber %(fh_too_heavy%); put into plot chest fh:chest:heartlands_01:1'))
        assert(not W.logged('ITEM LOST'))
        -- the player goes offline while the charge is in flight, the charge then fails
        local W2 = stocked({ lumber = 30, nails = 5 }, { lumber = 100, nails = 50 })
        W2.hold.charge, W2.chargeFailsLate = true, 'no_player'
        local h = W2.start(function() return W2.build(1, 'cabin') end)
        assert(not h.done)
        W2.players[1] = nil
        local ok2, why2 = W2.finish(h)
        assert(ok2 == false and why2 == 'no_player', tostring(why2))
        T.same({ bag_lumber = 0, bag_nails = 0, chest_lumber = 130, chest_nails = 55, cash = 1000 }, counts(W2))
        assert(W2.logged('backpack refused 5 nails %(character not on src%)'))
        assert(not W2.logged('ITEM LOST'))
    end)
    case('refund-once: the error path after an in-flow item refund puts nothing back a second time', function()
        -- in-flow abort refunds every stack (backpack ones rerouted to the chest), then the reroute log throws ->
        -- buildLocked errors -> the error path aborts again with st.taken already empty: no second addItem
        local W = stocked({ lumber = 30, nails = 5 }, { lumber = 100, nails = 50 })
        W.hold.charge, W.chargeFailsLate = true, 'no_player'
        local h = W.start(function() return W.build(1, 'cabin') end)
        W.players[1] = nil
        local realPrint = W.env.print
        W.env.print = function(m)
            if tostring(m):find('backpack refused') then error('console gone') end
            return realPrint(m)
        end
        local ok, why = W.finish(h)
        W.env.print = realPrint
        assert(ok == false and why == 'fh_build_failed', tostring(why))
        assert(W.logged('errored'), 'went through the error path')
        T.eq(4, W.calls.addItem) -- 2 chest + 2 rerouted (nobody on src: no backpack add tried); the second abort added none
        T.same({ bag_lumber = 0, bag_nails = 0, chest_lumber = 130, chest_nails = 55, cash = 1000 }, counts(W))
        T.eq(0, W.calls.credit)
    end)
    for _, down in ipairs({ { 'fh_player_offline', 'bagOffline' }, { 'snapshot throws', 'bagThrows' },
        { 'snapshot export missing', 'bagNoSnapshot' } }) do
        case('backpack unusable at the count step (' .. down[1] .. '): chest-only path exactly as before', function()
            local W = stocked({ lumber = 50, nails = 25 }, { lumber = 100, nails = 50 })
            W[down[2]] = true
            local ok, tier = W.build(1, 'cabin')
            assert(ok == true and tier == 2, tostring(tier))
            T.same({ bag_lumber = 50, bag_nails = 25, chest_lumber = 60, chest_nails = 30, cash = 600 }, counts(W))
            T.eq(2, W.calls.removeItem); T.eq(0, W.calls.addItem)
            assert(W.logged('backpack unavailable'))
        end)
    end
    case('backpack fh_player_offline at a later take step: what was taken goes back, then chest-only', function()
        -- lumber: bag 30 + chest 10 taken; nails: bag take refused fh_player_offline -> put back (the bag refund is
        -- refused too, so the 30 lumber lands in the chest), then the chest-only take: 40 lumber + 20 nails
        local W = stocked({ lumber = 30, nails = 5 }, { lumber = 100, nails = 50 })
        W.hold.removeItem = true
        local h = W.start(function() return W.build(1, 'cabin') end)
        assert(not h.done, 'suspended after the first backpack take')
        W.bagRemoveOffline, W.bagAddRefuses = true, 'fh_player_offline'
        local ok, tier = W.finish(h)
        assert(ok == true and tier == 2, tostring(tier))
        T.same({ bag_lumber = 0, bag_nails = 5, chest_lumber = 90, chest_nails = 30, cash = 600 }, counts(W))
        -- conserved: 30 + 100 lumber before = 90 left + 40 used; 5 + 50 nails = 5 + 30 left + 20 used
        assert(W.logged('backpack unavailable %(fh_player_offline%)'))
        assert(not W.logged('ITEM LOST'))
    end)
    case('another character loaded on src mid-build: no backpack take or refund on them, player_changed', function()
        local W = stocked({ lumber = 30, nails = 5 }, { lumber = 100, nails = 50 })
        W.hold.removeItem = true
        local h = W.start(function() return W.build(1, 'cabin') end)
        W.players[1] = 'B' -- same src, other character: their backpack is bag:1 in this stub
        local ok, why = W.finish(h)
        assert(ok == false and why == 'player_changed', tostring(why))
        T.eq(0, W.bag().lumber); T.eq(5, W.bag().nails) -- B's backpack: nothing taken, A's lumber not given to B
        T.eq(130, W.chest1().lumber); T.eq(50, W.chest1().nails)
        T.eq(0, W.calls.charge); T.eq(1000, W.cash.A); T.eq(1000, W.cash.B)
        assert(W.logged('backpack refused 30 lumber %(character not on src%)'))
    end)
end)

T.finish()

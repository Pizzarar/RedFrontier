-- Shared harness for the fh_homestead server specs (claims H7, town lots H8): loads fh_homestead server/main.lua in a
-- stubbed FXServer world with an in-memory fh_plots table that enforces PRIMARY KEY(plot_id) + UNIQUE(citizenid, class)
-- like migration 0018, plus a fake fh_economy (charge / credit / rep / repByCitizenid with per-character charge lock,
-- cash and rep).
-- An await can be HELD (W.hold[tag] = true, or a count n = the next n calls): the call yields there so a spec can run
-- another call meanwhile. Tags: insert_plot, insert_chest, delete_plot, charge, rep. W.fail.getPlayerThrows makes
-- rsg-core GetPlayer throw; W.fail.eventThrows = <event name> makes TriggerEvent of that name throw.
-- Usage: local newWorld = dofile(here .. 'support/homestead_world.lua')(T, cfg); local W = newWorld(rows, opts)
return function(T, cfg)
    local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
    local dir = here .. '../../server/resources/[fh]/fh_homestead/'
    local PR = dofile(dir .. 'shared/plot_rules.lua')
    local BR = dofile(dir .. 'shared/build_rules.lua')
    local fh = assert(io.open(dir .. 'server/main.lua', 'rb'))
    local MAIN_SRC = fh:read('a')
    fh:close()

    return function(rows, opts)
        opts = opts or {}
        local W = { db = { plots = {}, chests = {} }, events = {}, threads = {}, ex = {}, client = {}, commands = {},
            players = { [1] = 'A', [2] = 'B' }, offline = {}, admins = {}, peds = {}, hold = {}, fail = {}, logs = {},
            cash = { A = 1000, B = 1000 }, rep = {}, unknown = {}, charges = {}, credits = {}, reps = {}, chargeBusy = {},
            stash = {}, registered = {}, snapshots = {}, clears = {}, net = {}, opens = {}, hands = {}, handCalls = {} }
        for _, r in ipairs(rows or {}) do W.db.plots[r.plot_id] = { citizenid = r.citizenid, class = r.class } end
        local function await(tag)
            local h = W.hold[tag]
            if h and coroutine.isyieldable() then
                W.hold[tag] = (type(h) == 'number' and h > 1) and h - 1 or nil
                coroutine.yield(tag)
            end
        end
        local function db(sql, p)
            p = p or {}
            if sql:find('^SELECT %* FROM fh_plots') then
                if W.fail.select_plots then error('db down') end
                local out = {}
                for pid, r in pairs(W.db.plots) do
                    -- opts.noClassColumn: a DB from before migration 0018 has no class key at all
                    out[#out + 1] = { plot_id = pid, citizenid = r.citizenid, class = (not opts.noClassColumn) and r.class or nil }
                end
                table.sort(out, function(a, b) return a.plot_id < b.plot_id end)
                return out
            elseif sql:find('^INSERT INTO fh_plots ') then
                await('insert_plot')
                if W.fail.insert_plot then error('db down') end
                local pid, cid, class = p[1], p[2], p[3] or 'claim'
                if W.db.plots[pid] then error('Duplicate entry for key PRIMARY') end
                for _, r in pairs(W.db.plots) do
                    if r.citizenid == cid and (r.class or 'claim') == class then error('Duplicate entry for key citizenid_class') end
                end
                W.db.plots[pid] = { citizenid = cid, class = class }
                return 1
            elseif sql:find('^INSERT INTO fh_plot_chests') then
                await('insert_chest')
                if W.fail.insert_chest then error('db down') end
                W.db.chests[p[1]] = p[2]
                return 1
            elseif sql:find('^DELETE FROM fh_plots') then
                await('delete_plot')
                if W.fail.delete_plot == 'throw' then error('db down') end
                if W.fail.delete_plot == 'nil' then return nil end -- error logged by the driver, no row count
                local r = W.db.plots[p[1]]
                if not r or r.citizenid ~= p[2] then return 0 end
                W.db.plots[p[1]], W.db.chests[p[1]] = nil, nil
                return 1
            end
            error('unmocked sql: ' .. sql)
        end
        local function online(src)
            local cid = W.players[src]
            if cid and not W.offline[src] then return cid end
            return nil
        end
        local core = { Functions = {
            GetPlayer = function(src)
                if W.fail.getPlayerThrows then error('rsg-core GetPlayer failed') end
                local cid = online(src)
                return cid and { PlayerData = { citizenid = cid, source = src } } or nil
            end,
            GetPlayerByCitizenId = function(cid)
                for src, c in pairs(W.players) do
                    if c == cid and not W.offline[src] then return { PlayerData = { citizenid = cid, source = src } } end
                end
                return nil
            end,
        } }
        -- fake fh_economy, following its README contract (charge: one at a time per character, never below 0). First arg =
        -- the exports proxy (callers use exports.fh_economy:fn(...)).
        local economy = {
            charge = function(_, src, amount, reason, region)
                if W.fail.chargeThrows then error('fh_economy stopped') end
                local cid = online(src)
                if not cid then return false, 'no_player' end
                if W.chargeBusy[cid] then return false, 'fh_charge_busy' end
                if (W.cash[cid] or 0) < amount then return false, 'fh_insufficient_funds' end
                W.chargeBusy[cid] = true
                await('charge')
                W.chargeBusy[cid] = nil
                if W.fail.charge then return false, W.fail.charge end
                if (W.cash[cid] or 0) < amount then return false, 'fh_insufficient_funds' end
                W.cash[cid] = W.cash[cid] - amount
                W.charges[#W.charges + 1] = { citizenid = cid, amount = amount, reason = reason, region = region }
                return true, nil, #W.charges
            end,
            credit = function(_, cid, amount, reason, region)
                W.credits[#W.credits + 1] = { citizenid = cid, amount = amount, reason = reason, region = region }
                if W.fail.credit then return false, 'ledger_failed' end
                W.cash[cid] = (W.cash[cid] or 0) + amount
                return true, nil, 'paid'
            end,
            rep = function(_, src, region, delta, reason)
                local cid = online(src)
                if not cid then return false, 'no_player' end
                await('rep')
                if W.fail.rep then return false, 'ledger_failed' end
                W.rep[cid] = W.rep[cid] or {}
                W.rep[cid][region] = (W.rep[cid][region] or 0) + delta
                W.reps[#W.reps + 1] = { citizenid = cid, region = region, delta = delta, reason = reason }
                return true
            end,
            -- idea-804: by citizenid, online or offline. W.unknown[cid] = no players row; W.fail.repByCidThrows = throws.
            repByCitizenid = function(_, cid, region, delta, reason)
                if W.fail.repByCidThrows then error('fh_economy stopped') end
                if type(cid) ~= 'string' or cid == '' then return false, 'invalid_citizenid' end
                if W.unknown[cid] then return false, 'unknown_citizenid' end
                await('rep')
                if W.fail.rep then return false, 'ledger_failed' end
                W.rep[cid] = W.rep[cid] or {}
                W.rep[cid][region] = (W.rep[cid][region] or 0) + delta
                W.reps[#W.reps + 1] = { citizenid = cid, region = region, delta = delta, reason = reason, byCid = true }
                return true
            end,
        }
        local X = {
            ['rsg-core'] = { GetCoreObject = function() return core end },
            -- H13 stashes: W.stash[id] = { [slot] = { name, amount } }; W.registered[id] = registered with fh_core.
            -- snapshot of an id fh_inventory never saw = fh_unknown_container. W.fail.snapshot = <reason> (or 'throw'),
            -- W.fail.clear = <reason> (or 'throw', or 'noop': reports ok but leaves the items), W.onSnapshot(id) runs
            -- before each read (a spec can add items there, as a pane open before the lock would).
            fh_core = {
                registerContainer = function(_, ref)
                    if W.fail.registerThrows then error('fh_core gone') end
                    if W.fail.register then return false, 'nope' end
                    W.registered[ref.id] = true
                    return true
                end,
                snapshot = function(_, ref)
                    W.snapshots[#W.snapshots + 1] = ref.id
                    if W.onSnapshot then W.onSnapshot(ref.id) end
                    if W.fail.snapshot == 'throw' then error('fh_inventory gone') end
                    if W.fail.snapshot then return nil, W.fail.snapshot end
                    if not W.registered[ref.id] then return nil, 'fh_unknown_container' end
                    local out = {}
                    for slot, it in pairs(W.stash[ref.id] or {}) do out[slot] = { name = it.name, amount = it.amount } end
                    return out
                end,
                open = function(_, src, ref) -- records the open; reach is fh_core's job, not tested here
                    W.opens[#W.opens + 1] = { src = src, id = ref.id }
                    return true
                end,
                clearContainer = function(_, ref)
                    W.clears[#W.clears + 1] = ref.id
                    if W.fail.clear == 'throw' then error('fh_inventory gone') end
                    if W.fail.clear == 'noop' then return true end
                    if W.fail.clear then return false, W.fail.clear end
                    if not W.registered[ref.id] then return false, 'fh_unknown_container' end
                    W.stash[ref.id] = {}
                    return true
                end,
            },
            fh_economy = economy,
            -- H13b: getHands(src) -> W.hands[src] or {}; W.fail.hands = 'throw'; W.X.fh_hands = nil = resource missing
            fh_hands = { getHands = function(_, src)
                W.handCalls[#W.handCalls + 1] = src
                if W.fail.hands == 'throw' then error('fh_hands errored') end
                return W.hands[src] or {}
            end },
        }
        W.X = X
        W.env = setmetatable({
            FhHomesteadConfig = cfg, FhPlotRules = PR, FhBuildRules = setmetatable({ safeRadius = function(p) return p.radius end,
                safeRadiusFor = function(p) return p.radius end }, { __index = BR }),
            FhRegions = opts.isEnabled and { isEnabled = opts.isEnabled } or nil,
            FhHomesteadSlots = opts.slots, -- H13: { isReady, getTiers } stub (extra chests' built tiers)
            -- H19: unclaim asks server/garden.lua for planted beds (none here; spec/garden_server_spec.lua runs the real one)
            FhHomesteadGarden = opts.garden or { plantedBeds = function() return {} end, clearPlot = function() return true end },
            MySQL = { query = { await = db }, update = { await = db }, insert = { await = db } },
            CreateThread = function(fn) W.threads[#W.threads + 1] = fn end, Wait = function() end,
            AddEventHandler = function() end, RegisterNetEvent = function(name, fn) W.net[name] = fn end,
            TriggerEvent = function(name, data)
                if W.fail.eventThrows == name then error('handler of ' .. name .. ' errored') end
                W.events[#W.events + 1] = { name = name, data = data }
            end,
            TriggerClientEvent = function(ev, target, payload) if ev == 'chat:addMessage' then W.client[#W.client + 1] = { target = target, msg = payload.args[2] } end end,
            exports = setmetatable({}, { __call = function(_, name, fn) W.ex[name] = fn end,
                __index = function(_, res) return X[res] or {} end }),
            IsPlayerAceAllowed = function(src) return W.admins[src] == true end,
            lib = { callback = { register = function() end }, addCommand = function(name, _, fn) W.commands[name] = fn end },
            GetPlayerPed = function(src) return W.peds[src] and src or 0 end,
            GetEntityCoords = function(ped) return W.peds[ped] end,
            print = function(m) W.logs[#W.logs + 1] = tostring(m) end,
        }, { __index = _G })
        assert(load(MAIN_SRC, '@main.lua', 't', W.env))()
        -- loadClaims; opts.deferLoad leaves it to the spec (W.load()) to observe the state before the boot load
        W.load = function() W.threads[1]() end
        if not opts.deferLoad then W.load() end
        W.C = W.env.FhHomesteadClaims
        W.at = function(src, plotId) W.peds[src] = cfg.plots[plotId].center end
        W.claimAt = function(src, plotId, class) W.at(src, plotId); return W.ex.claim(src, class) end
        W.buyAt = function(src, plotId) W.at(src, plotId); return W.ex.buyLot(src) end
        -- client -> server net event as player src (handlers read the `source` global)
        W.netEvent = function(name, src, payload)
            W.env.source = src
            local r = table.pack(W.net[name](payload))
            W.env.source = nil
            return table.unpack(r, 1, r.n)
        end
        W.repOf = function(cid, region) return (W.rep[cid] or {})[region] or 0 end
        W.start = function(fn)
            local h = { co = coroutine.create(fn) }
            local r = table.pack(coroutine.resume(h.co))
            if not r[1] then error(r[2], 0) end
            h.res = r
            h.done = coroutine.status(h.co) == 'dead'
            return h
        end
        W.finish = function(h)
            while coroutine.status(h.co) ~= 'dead' do
                local r = table.pack(coroutine.resume(h.co))
                if not r[1] then error(r[2], 0) end
                h.res = r
            end
            return table.unpack(h.res, 2, h.res.n)
        end
        W.named = function(name)
            local n = 0
            for _, e in ipairs(W.events) do if e.name == name then n = n + 1 end end
            return n
        end
        W.logged = function(pattern)
            for _, m in ipairs(W.logs) do if m:find(pattern) then return true end end
            return false
        end
        -- every claim in memory has its DB row with the same owner + class, and vice versa
        W.consistent = function()
            local mem = {}
            for _, class in ipairs({ 'claim', 'town_lot' }) do
                for cid in pairs(W.players) do
                    local c = W.players[cid]
                    local pid = W.ex.getPlot(c, class)
                    if pid then mem[pid] = { citizenid = c, class = class } end
                end
            end
            for pid, r in pairs(W.db.plots) do
                local m = mem[pid]
                assert(m, 'db row ' .. pid .. ' missing in memory')
                T.eq(r.citizenid, m.citizenid, pid .. ' owner'); T.eq(r.class or 'claim', m.class, pid .. ' class')
                T.eq(r.citizenid, W.C.ownerOf(pid), pid .. ' byPlot')
            end
            for pid in pairs(mem) do assert(W.db.plots[pid], 'memory claim ' .. pid .. ' has no db row') end
            local listed = W.ex.claimedPlots()
            local n = 0
            for _ in pairs(W.db.plots) do n = n + 1 end
            T.eq(n, #listed, 'claimedPlots count')
        end
        return W
    end
end

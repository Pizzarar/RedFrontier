-- Shared harness for the fh_homestead server specs (claims H7, town lots H8): loads fh_homestead server/main.lua in a
-- stubbed FXServer world with an in-memory fh_plots table that enforces PRIMARY KEY(plot_id) + UNIQUE(citizenid, class)
-- like migration 0018, plus a fake fh_economy (charge / credit / rep with per-character charge lock, cash and rep).
-- An await can be HELD (W.hold[tag] = true, or a count n = the next n calls): the call yields there so a spec can run
-- another call meanwhile. Tags: insert_plot, insert_chest, delete_plot, charge, rep. W.fail.getPlayerThrows makes
-- rsg-core GetPlayer throw; W.fail.eventThrows = <event name> makes TriggerEvent of that name throw.
-- Usage: local newWorld = dofile(here .. 'support/homestead_world.lua')(T, cfg); local W = newWorld(rows, opts)
return function(T, cfg)
    local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
    local dir = here .. '../../server/resources/[fh]/fh_homestead/'
    local PR = dofile(dir .. 'shared/plot_rules.lua')
    local fh = assert(io.open(dir .. 'server/main.lua', 'rb'))
    local MAIN_SRC = fh:read('a')
    fh:close()

    return function(rows, opts)
        opts = opts or {}
        local W = { db = { plots = {}, chests = {} }, events = {}, threads = {}, ex = {}, client = {}, commands = {},
            players = { [1] = 'A', [2] = 'B' }, offline = {}, admins = {}, peds = {}, hold = {}, fail = {}, logs = {},
            cash = { A = 1000, B = 1000 }, rep = {}, charges = {}, credits = {}, reps = {}, chargeBusy = {} }
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
        }
        local X = {
            ['rsg-core'] = { GetCoreObject = function() return core end },
            fh_core = { registerContainer = function()
                if W.fail.registerThrows then error('fh_core gone') end
                if W.fail.register then return false, 'nope' end
                return true
            end },
            fh_economy = economy,
        }
        W.env = setmetatable({
            FhHomesteadConfig = cfg, FhPlotRules = PR, FhBuildRules = { safeRadius = function(p) return p.radius end, safeRadiusFor = function(p) return p.radius end },
            MySQL = { query = { await = db }, update = { await = db }, insert = { await = db } },
            CreateThread = function(fn) W.threads[#W.threads + 1] = fn end, Wait = function() end,
            AddEventHandler = function() end, RegisterNetEvent = function() end,
            TriggerEvent = function(name, data)
                if W.fail.eventThrows == name then error('handler of ' .. name .. ' errored') end
                W.events[#W.events + 1] = { name = name, data = data }
            end,
            TriggerClientEvent = function(_, target, payload) W.client[#W.client + 1] = { target = target, msg = payload.args[2] } end,
            exports = setmetatable({}, { __call = function(_, name, fn) W.ex[name] = fn end,
                __index = function(_, res) return X[res] or {} end }),
            IsPlayerAceAllowed = function(src) return W.admins[src] == true end,
            lib = { callback = { register = function() end }, addCommand = function(name, _, fn) W.commands[name] = fn end },
            GetPlayerPed = function(src) return W.peds[src] and src or 0 end,
            GetEntityCoords = function(ped) return W.peds[ped] end,
            print = function(m) W.logs[#W.logs + 1] = tostring(m) end,
        }, { __index = _G })
        assert(load(MAIN_SRC, '@main.lua', 't', W.env))()
        W.threads[1]() -- loadClaims
        W.C = W.env.FhHomesteadClaims
        W.at = function(src, plotId) W.peds[src] = cfg.plots[plotId].center end
        W.claimAt = function(src, plotId, class) W.at(src, plotId); return W.ex.claim(src, class) end
        W.buyAt = function(src, plotId) W.at(src, plotId); return W.ex.buyLot(src) end
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

-- H7 (plan homestead-02): per-class claims in fh_homestead server/main.lua, loaded in a stubbed FXServer world with an
-- in-memory fh_plots table that enforces PRIMARY KEY(plot_id) + UNIQUE(citizenid, class) like migration 0018.
-- byOwner is byOwner[class][citizenid]; getPlot(cid) / plotOf(cid) default to the 'claim' class, so every existing
-- caller (fh_hands, slots/build/comfort) keeps getting the homestead claim and never a town lot.
-- An await can be HELD (W.hold[tag] = true): the call yields there so a spec can run another call meanwhile.
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local case = T.it
local dir = here .. '../server/resources/[fh]/fh_homestead/'
local PR = dofile(dir .. 'shared/plot_rules.lua')

local function V(x, y, z) return { x = x, y = y, z = z } end
local function plot(id, x, class, claimable)
    return { id = id, region = 'heartlands', center = V(x, 0, 0), radius = 20.0, class = class, claimable = claimable,
        chest = { coords = V(x + 2, 0, 0), heading = 0.0, model = 'p_chest01x' } }
end
-- town lots are claimable here so the class check, not the claimable flag, is what refuses /fh_claim on them
local cfg = { baseSafeRadius = 25.0, plots = {
    claim_a = plot('claim_a', 0), claim_b = plot('claim_b', 1000, 'claim'),
    lot_a = plot('lot_a', 2000, 'town_lot', true), lot_b = plot('lot_b', 3000, 'town_lot', true),
} }
local MAIN_SRC = (function() local fh = assert(io.open(dir .. 'server/main.lua', 'rb')); local s = fh:read('a'); fh:close(); return s end)()

local function newWorld(rows, opts)
    opts = opts or {}
    local W = { db = { plots = {}, chests = {} }, events = {}, threads = {}, ex = {}, client = {}, commands = {},
        players = { [1] = 'A', [2] = 'B' }, peds = {}, hold = {}, fail = {}, logs = {} }
    for _, r in ipairs(rows or {}) do W.db.plots[r.plot_id] = { citizenid = r.citizenid, class = r.class } end
    local function await(tag)
        if W.hold[tag] and coroutine.isyieldable() then W.hold[tag] = nil; coroutine.yield(tag) end
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
            local r = W.db.plots[p[1]]
            if not r or r.citizenid ~= p[2] then return 0 end
            W.db.plots[p[1]], W.db.chests[p[1]] = nil, nil
            return 1
        end
        error('unmocked sql: ' .. sql)
    end
    local core = { Functions = { GetPlayer = function(src)
        local cid = W.players[src]
        return cid and { PlayerData = { citizenid = cid } } or nil
    end } }
    local X = {
        ['rsg-core'] = { GetCoreObject = function() return core end },
        fh_core = { registerContainer = function()
            if W.fail.registerThrows then error('fh_core gone') end
            if W.fail.register then return false, 'nope' end
            return true
        end },
    }
    W.env = setmetatable({
        FhHomesteadConfig = cfg, FhPlotRules = PR, FhBuildRules = { safeRadius = function(p) return p.radius end },
        MySQL = { query = { await = db }, update = { await = db }, insert = { await = db } },
        CreateThread = function(fn) W.threads[#W.threads + 1] = fn end, Wait = function() end,
        AddEventHandler = function() end, RegisterNetEvent = function() end,
        TriggerEvent = function(name, data) W.events[#W.events + 1] = { name = name, data = data } end,
        TriggerClientEvent = function(_, target, payload) W.client[#W.client + 1] = { target = target, msg = payload.args[2] } end,
        exports = setmetatable({}, { __call = function(_, name, fn) W.ex[name] = fn end,
            __index = function(_, res) return X[res] or {} end }),
        IsPlayerAceAllowed = function() return false end,
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
    W.start = function(fn)
        local h = { co = coroutine.create(fn) }
        local r = table.pack(coroutine.resume(h.co))
        if not r[1] then error(r[2], 0) end
        h.res = r
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

T.describe('fh_homestead claims per class (H7)', function()
    case('getPlot(cid) returns the claim even when the cid also owns a town lot', function()
        local W = newWorld()
        T.same({ true, 'lot_a' }, { W.claimAt(1, 'lot_a', 'town_lot') })
        T.same({ true, 'claim_a' }, { W.claimAt(1, 'claim_a') })
        T.eq('claim_a', W.ex.getPlot('A'))
        T.eq('claim_a', W.ex.getPlot('A', 'claim'))
        T.eq('lot_a', W.ex.getPlot('A', 'town_lot'))
        T.eq('claim_a', W.C.plotOf('A'))
        T.eq('lot_a', W.C.plotOf('A', 'town_lot'))
        T.same({ citizenid = 'A', class = 'town_lot' }, W.db.plots.lot_a)
        T.same({ citizenid = 'A', class = 'claim' }, W.db.plots.claim_a)
        local l = W.ex.claimedPlots(); table.sort(l)
        T.same({ 'claim_a', 'lot_a' }, l)
        W.consistent()
    end)

    case('lot-only owner: getPlot(cid) nil, getPlot(cid, town_lot) = the lot', function()
        local W = newWorld()
        T.same({ true, 'lot_a' }, { W.claimAt(2, 'lot_a', 'town_lot') })
        T.eq(nil, W.ex.getPlot('B'))
        T.eq(nil, W.C.plotOf('B'))
        T.eq('lot_a', W.ex.getPlot('B', 'town_lot'))
        T.eq('B', W.C.ownerOf('lot_a'))
        -- /fh_unclaim with no id releases the claim only: a lot-only owner has none
        T.same({ false, 'fh_no_plot' }, { W.ex.unclaim(2) })
        T.eq('lot_a', W.ex.getPlot('B', 'town_lot'))
        W.consistent()
    end)

    case('unclaim of the lot leaves the claim (memory + DB), and no-arg unclaim releases the claim, not the lot', function()
        local W = newWorld()
        W.claimAt(1, 'claim_a'); W.claimAt(1, 'lot_a', 'town_lot')
        T.same({ true, 'lot_a' }, { W.ex.unclaim(1, 'lot_a') })
        T.eq('claim_a', W.ex.getPlot('A'))
        T.eq(nil, W.ex.getPlot('A', 'town_lot'))
        T.eq(nil, W.db.plots.lot_a)
        T.same({ citizenid = 'A', class = 'claim' }, W.db.plots.claim_a)
        T.eq(1, W.named('fh:homestead:unclaimed'))
        W.consistent()
        -- the lot again, then a no-arg unclaim: the claim goes, the lot stays
        T.same({ true, 'lot_b' }, { W.claimAt(1, 'lot_b', 'town_lot') })
        T.same({ true, 'claim_a' }, { W.ex.unclaim(1) })
        T.eq(nil, W.ex.getPlot('A'))
        T.eq('lot_b', W.ex.getPlot('A', 'town_lot'))
        W.consistent()
    end)

    case('one plot per class: a second claim or a second lot is refused, one of each is fine', function()
        local W = newWorld()
        W.claimAt(1, 'claim_a'); W.claimAt(1, 'lot_a', 'town_lot')
        T.same({ false, 'fh_already_has_plot' }, { W.claimAt(1, 'claim_b') })
        T.same({ false, 'fh_already_has_lot' }, { W.claimAt(1, 'lot_b', 'town_lot') })
        T.same({ false, 'fh_plot_taken' }, { W.claimAt(2, 'lot_a', 'town_lot') })
        W.consistent()
    end)

    case('/fh_claim on a town lot is refused (lots are bought, not claimed); claim(src, town_lot) on a claim too', function()
        local W = newWorld()
        W.at(1, 'lot_a')
        W.commands.fh_claim(1)
        T.eq('fh_claim: fh_wrong_plot_class', W.client[#W.client].msg)
        T.eq(nil, W.db.plots.lot_a)
        T.eq(nil, W.C.ownerOf('lot_a'))
        T.same({ false, 'fh_wrong_plot_class' }, { W.claimAt(1, 'claim_a', 'town_lot') })
        T.eq(nil, W.db.plots.claim_a)
        -- /fh_claim on a claim still works
        W.at(1, 'claim_a')
        W.commands.fh_claim(1)
        T.eq('fh_claim: claimed plot claim_a', W.client[#W.client].msg)
        W.consistent()
    end)

    case('DB insert failure keeps both maps consistent and leaves the other class untouched', function()
        local W = newWorld()
        W.claimAt(1, 'claim_a')
        W.fail.insert_plot = true
        T.same({ false, 'fh_claim_failed' }, { W.claimAt(1, 'lot_a', 'town_lot') })
        T.eq(nil, W.ex.getPlot('A', 'town_lot')); T.eq(nil, W.C.ownerOf('lot_a'))
        T.eq('claim_a', W.ex.getPlot('A'))
        W.consistent()
        W.fail.insert_plot = nil
        -- second stage (chest row) fails: our fh_plots row is rolled back, maps cleared
        W.fail.insert_chest = true
        T.same({ false, 'fh_claim_failed' }, { W.claimAt(1, 'lot_a', 'town_lot') })
        T.eq(nil, W.db.plots.lot_a); T.eq(nil, W.ex.getPlot('A', 'town_lot'))
        W.fail.insert_chest = nil
        -- chest register fails: same rollback
        W.fail.register = true
        T.same({ false, 'fh_claim_failed' }, { W.claimAt(1, 'lot_a', 'town_lot') })
        T.eq(nil, W.db.plots.lot_a); T.eq(nil, W.ex.getPlot('A', 'town_lot'))
        W.fail.register = nil
        -- chest register throws (fh_core gone): same rollback, the plot is not left reserved or busy
        W.fail.registerThrows = true
        T.same({ false, 'fh_claim_failed' }, { W.claimAt(1, 'lot_a', 'town_lot') })
        T.eq(nil, W.db.plots.lot_a); T.eq(nil, W.ex.getPlot('A', 'town_lot')); T.eq(nil, W.C.ownerOf('lot_a'))
        W.fail.registerThrows = nil
        T.eq(1, W.named("fh:homestead:claimed")) -- only the first claim fired
        W.consistent()
        -- and the lot is claimable afterwards
        T.same({ true, 'lot_a' }, { W.claimAt(1, 'lot_a', 'town_lot') })
        W.consistent()
    end)

    case('UNIQUE(citizenid, class) backstop: a DB row memory does not know about refuses the insert, maps stay clean', function()
        local W = newWorld()
        -- another server wrote A's lot after our load: memory thinks A has no lot
        W.db.plots.lot_b = { citizenid = 'A', class = 'town_lot' }
        T.same({ false, 'fh_claim_failed' }, { W.claimAt(1, 'lot_a', 'town_lot') })
        T.eq(nil, W.C.ownerOf('lot_a'))
        T.eq(nil, W.ex.getPlot('A', 'town_lot'))
        T.same({ citizenid = 'A', class = 'town_lot' }, W.db.plots.lot_b) -- the other row is not deleted
        -- a claim for A is still fine: different class
        T.same({ true, 'claim_a' }, { W.claimAt(1, 'claim_a') })
    end)

    case('unclaim while the claim is still writing: refused fh_claim_busy, the claim lands, memory = DB', function()
        local W = newWorld()
        W.hold.insert_chest = true
        W.at(1, 'lot_a')
        local h = W.start(function() return W.ex.claim(1, 'town_lot') end)
        T.eq('A', W.C.ownerOf('lot_a')) -- reserved
        T.same({ false, 'fh_claim_busy' }, { W.ex.unclaim(0, 'lot_a') })
        T.same({ true, 'lot_a' }, { W.finish(h) })
        W.consistent()
        T.same({ true, 'lot_a' }, { W.ex.unclaim(0, 'lot_a') })
        W.consistent()
    end)

    case('two claims in the same tick for one class: the reservation refuses the second', function()
        local W = newWorld()
        W.hold.insert_plot = true
        W.at(1, 'lot_a')
        local h = W.start(function() return W.ex.claim(1, 'town_lot') end)
        T.same({ false, 'fh_already_has_lot' }, { W.claimAt(1, 'lot_b', 'town_lot') })
        T.same({ true, 'claim_a' }, { W.claimAt(1, 'claim_a') }) -- the other class is not blocked
        T.same({ true, 'lot_a' }, { W.finish(h) })
        W.consistent()
    end)

    case('load: rows without class (no column, or NULL) load as claims; class rows load into their class', function()
        local rows = {
            { plot_id = 'claim_a', citizenid = 'A' },
            { plot_id = 'lot_a', citizenid = 'B', class = 'town_lot' },
            { plot_id = 'claim_b', citizenid = 'B', class = 'claim' },
        }
        local W = newWorld(rows)
        T.eq('claim_a', W.ex.getPlot('A'))
        T.eq('claim_b', W.ex.getPlot('B'))
        T.eq('lot_a', W.ex.getPlot('B', 'town_lot'))
        T.eq(nil, W.ex.getPlot('A', 'town_lot'))
        -- class persisted on load shows in the per-class refusal
        T.same({ false, 'fh_already_has_lot' }, { W.claimAt(2, 'lot_b', 'town_lot') })
        -- DB from before migration 0018: no class key on any row; all load as claims
        local W2 = newWorld({ { plot_id = 'claim_a', citizenid = 'A' }, { plot_id = 'claim_b', citizenid = 'B' } },
            { noClassColumn = true })
        T.eq('claim_a', W2.ex.getPlot('A')); T.eq('claim_b', W2.ex.getPlot('B'))
        T.eq(nil, W2.ex.getPlot('A', 'town_lot'))
        -- unclaim of a loaded lot clears its class bucket, the claim stays
        T.same({ true, 'lot_a' }, { W.ex.unclaim(0, 'lot_a') })
        T.eq(nil, W.ex.getPlot('B', 'town_lot')); T.eq('claim_b', W.ex.getPlot('B'))
        W.consistent()
    end)
end)

T.finish()

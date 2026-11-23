-- Run from repo root: `lua spec/freight_server_spec.lua` (or via tools/run-specs.py).
-- Loads fh_trade/server/freight.lua under stubbed natives/exports (fh_core incl. B7 removeItem, fh_cargo, rsg-core,
-- fh_quests). Covers: cargo removal via removeItem (all-or-nothing, pcall), restart safety, abandon races/idempotence,
-- accept lock, ref guards. The check loop is one coroutine: each resume = one tick (Wait yields 'wait').
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local case = T.it
local F = dofile(here .. '../server/resources/[fh]/fh_trade/shared/freight.lua')
local SERVER = here .. '../server/resources/[fh]/fh_trade/server/freight.lua'

local clock = 1000000
os.time = function() return clock end

local function newEnv(opts)
    opts = opts or {}
    local E = { events = {}, removeCalls = {}, addCalls = {}, rows = opts.rows or {}, deleted = {}, wagons = {}, items = {}, online = { [7] = 'CID1' } }
    E.removeResult = { true }
    E.removeYield = false
    E.addYield = false
    FhFreight = F
    FhTradeConfig = {
        goods = { trade_salt = { base = 10, label = 'Salt' }, trade_cloth = { base = 20, label = 'Cloth' } },
        freight = {
            minQty = 1, maxQty = 20, deadlineSeconds = 1800, maxActivePerPlayer = opts.max or 2, graceChecks = 3, checkMs = 5000, acceptReach = 8,
            destinations = { dunes = { x = 500, y = 0, z = 0, radius = 40 } },
        },
    }
    FhRegions = { regions = { heartlands = {}, dunes = {} }, isKnownRegion = function(id) return id == 'heartlands' or id == 'dunes' end }
    local registered = {}
    local exp = setmetatable({}, { __call = function(_, name, fn) registered[name] = fn end })
    exp['rsg-core'] = { GetCoreObject = function() return { Functions = {
        GetPlayer = function(_, src) local c = E.online[src] return c and { PlayerData = { citizenid = c, source = src } } or nil end,
        GetPlayerByCitizenId = function(_, cid) for s, c in pairs(E.online) do if c == cid then return { PlayerData = { citizenid = c, source = s } } end end end,
    } } end }
    exp.fh_trade = { getShortages = function() return {} end }
    exp.fh_cargo = {
        nearestWagon = function() return E.nearest end,
        getWagon = function(_, id) if E.getWagonThrows then error('getWagon boom') end return E.wagons[id] end,
    }
    exp.fh_core = {
        canFit = function() return true end,
        addItem = function(_, ref, name, n, info)
            if E.addYield then coroutine.yield('io') end
            E.addCalls[#E.addCalls + 1] = { ref = ref, name = name, n = n, info = info }
            E.items[ref.id] = (E.items[ref.id] or 0) + n
            return true
        end,
        snapshot = function(_, ref) local n = E.items[ref.id] if n == nil then return nil, 'x' end return { [1] = { name = 'trade_salt', amount = n } } end,
        removeItem = function(_, ref, name, n)
            E.removeCalls[#E.removeCalls + 1] = { ref = ref, name = name, n = n }
            if E.removeYield then coroutine.yield('io') end
            if E.removeThrows then error('removeItem boom') end
            local r = table.remove(E.removeSeq or {}, 1) or E.removeResult
            local ok, why = r[1], r[2]
            if ok then E.items[ref.id] = (E.items[ref.id] or 0) - n end
            return ok, why
        end,
        -- the old sink API must not be used any more
        createDropBag = function() error('createDropBag is gone') end,
        move = function() error('move is gone') end,
        deleteContainer = function() error('deleteContainer is gone') end,
        transferAll = function() error('transferAll is gone') end,
    }
    exp.fh_quests = { registerJobType = function(_, name, hooks) E.hooks = hooks E.jobName = name return true end }
    exports = exp
    MySQL = { query = { await = function(sql)
        if sql:find('^SELECT') then return E.rows end
        if sql:find('^DELETE') then E.deleted[#E.deleted + 1] = true end
        return {}
    end } }
    local thread
    CreateThread = function(fn) thread = fn end
    Wait = function() coroutine.yield('wait') end
    TriggerEvent = function(name, payload) E.events[#E.events + 1] = { name = name, payload = payload } end
    AddEventHandler = function(n, fn) if n == 'onResourceStart' then E.onStart = fn end end
    GetResourceState = function() return 'started' end
    GetCurrentResourceName = function() return 'fh_trade' end
    dofile(SERVER)
    E.onStart('fh_quests') -- as the engine would: register the job type
    E.registered = registered
    E.co = coroutine.create(thread)
    function E.step() local ok, r = coroutine.resume(E.co) assert(ok, tostring(r)) return r end
    function E.tick() local r repeat r = E.step() until r == 'wait' end -- drain 'io' yields
    E.tick() -- load(), then parks at the first Wait
    return E
end

local function offer(over)
    local o = { key = 'heartlands.dunes.trade_salt', title = 't', from_region = 'heartlands', to_region = 'dunes', item = 'trade_salt',
                qty = 5, reward = 80, deadline_s = 1800 }
    for k, v in pairs(over or {}) do o[k] = v end
    return o
end
local function state(key) return { citizenid = 'CID1', quest_id = 'job:freight:' .. key, progress = { job = { key = key } } } end
local function accept(E, o)
    E.nearest = { type = 'wagon', id = 'fh:wagon:CID1:t2' }
    E.wagons['CID1:t2'] = E.wagons['CID1:t2'] or { id = 'CID1:t2', owner = 'CID1', coords = { x = 0, y = 0, z = 0 } }
    return E.hooks.accept(7, o or offer())
end
local function atDest(E) E.wagons['CID1:t2'].coords = { x = 500, y = 0, z = 0 } end
local function delivered(E) local n = 0 for _, e in ipairs(E.events) do if e.name == F.EVENT_DELIVERED then n = n + 1 end end return n end
local function failedReasons(E) local r = {} for _, e in ipairs(E.events) do if e.name == F.EVENT_FAILED then r[#r + 1] = e.payload.reason end end return r end

case('registers the freight job type (on fh_quests / self start only) with the four hooks + events', function()
    local E = newEnv()
    T.eq('freight', E.jobName)
    for _, h in ipairs({ 'offers', 'accept', 'onEvent', 'abandon' }) do T.eq('function', type(E.hooks[h])) end
    T.same({ 'fh:trade:contract_delivered', 'fh:trade:contract_failed' }, E.hooks.events)
    E.jobName = nil; E.onStart('fh_inventory'); T.eq(nil, E.jobName)
    E.onStart('fh_trade'); T.eq('freight', E.jobName)
end)

case('accept: cargo goes into the wagon via addItem with the contract tag; contract is listed', function()
    local E = newEnv()
    local ok = accept(E)
    T.eq(true, ok); T.eq(1, #E.addCalls)
    T.same({ type = 'wagon', id = 'fh:wagon:CID1:t2' }, E.addCalls[1].ref); T.eq(5, E.addCalls[1].n)
    T.same({ freight = 'heartlands.dunes.trade_salt' }, E.addCalls[1].info)
    T.eq(1, #E.registered.getContracts(7))
end)

case('L9: wagon ref guards: nil, non-table, wrong prefix, empty id -> no wagon, nothing added', function()
    local E = newEnv()
    for _, bad in ipairs({ 'str', { id = 5 }, { id = 'other:CID1' }, { id = 'fh:wagon:' }, {} }) do
        E.nearest = bad
        local ok, err = E.hooks.accept(7, offer())
        assert(ok == false and err == 'fh_freight_no_wagon', tostring(err))
    end
    E.nearest = nil
    local ok, err = E.hooks.accept(7, offer()); assert(ok == false and err == 'fh_freight_no_wagon')
    T.eq(0, #E.addCalls)
end)

case('delivery: removeItem(ref,item,qty), ONE delivered event, contract gone; ticking again emits nothing', function()
    local E = newEnv()
    assert(accept(E)); atDest(E)
    E.tick()
    T.eq(1, #E.removeCalls); T.same({ type = 'wagon', id = 'fh:wagon:CID1:t2' }, E.removeCalls[1].ref)
    T.eq('trade_salt', E.removeCalls[1].name); T.eq(5, E.removeCalls[1].n)
    T.eq(1, delivered(E)); T.eq(0, #E.registered.getContracts(7))
    T.eq('job:freight:heartlands.dunes.trade_salt', E.events[1].payload.quest_id)
    E.tick(); T.eq(1, delivered(E)); T.eq(1, #E.removeCalls)
end)

case('A: removeItem false (fh_not_enough) or a throw -> no delivered event, contract kept', function()
    local E = newEnv()
    assert(accept(E)); atDest(E)
    E.removeResult = { false, 'fh_not_enough' }
    E.tick(); T.eq(0, delivered(E)); T.eq(1, #E.registered.getContracts(7))
    E.removeThrows = true
    E.tick(); T.eq(0, delivered(E)); T.eq(1, #E.registered.getContracts(7))
    E.removeThrows = false; E.removeResult = { true }
    E.tick(); T.eq(1, delivered(E))
end)

case('A: the old drop-bag sink is never touched (stub raises if it is)', function()
    local E = newEnv()
    assert(accept(E)); atDest(E); E.tick(); T.eq(1, delivered(E))
end)

case('B: vector3-like wagon coords still deliver', function()
    local E = newEnv()
    assert(accept(E))
    E.wagons['CID1:t2'].coords = setmetatable({}, { __index = function(_, k) return ({ x = 500, y = 0, z = 0 })[k] end })
    E.tick(); T.eq(1, delivered(E))
end)

case('getWagon throwing is contained (pcall), not a delivery, not a loss on the first tick', function()
    local E = newEnv()
    assert(accept(E)); E.getWagonThrows = true
    E.tick(); T.eq(0, delivered(E)); T.eq(0, #failedReasons(E))
end)

case('timeout: past the deadline emits failed(timeout) once, even with the player offline', function()
    local E = newEnv()
    assert(accept(E))
    E.online = {}; clock = clock + 1801
    E.tick(); T.same({ 'timeout' }, failedReasons(E)); T.eq(0, #E.registered.getContracts(7))
    E.tick(); T.eq(1, #failedReasons(E))
end)

local function restartEnv(rowOver)
    local E0 = newEnv(); assert(accept(E0))
    local row = { citizenid = 'CID1', ckey = 'heartlands.dunes.trade_salt', wagon = 'CID1:t2', from_region = 'heartlands', to_region = 'dunes',
        item = 'trade_salt', qty = 5, reward = 80, accepted_at = clock, deadline = clock + 1800 }
    for k, v in pairs(rowOver or {}) do row[k] = v end
    local E = newEnv({ rows = { row } })
    return E
end

case('C: after a restart a not-yet-spawned wagon (player online) never fails the contract; only the deadline does', function()
    local E = restartEnv()
    for _ = 1, 8 do E.tick() end
    T.eq(0, #failedReasons(E)); T.eq(1, #E.registered.getContracts(7))
    clock = clock + 1801; E.tick(); T.same({ 'timeout' }, failedReasons(E))
end)

case('C: offline player: no loss, no delivery; back online it needs to see the wagon, then gets the grace window', function()
    local E = restartEnv()
    E.online = {}
    for _ = 1, 8 do E.tick() end
    T.eq(0, #failedReasons(E)); E.online = { [7] = 'CID1' }
    E.wagons['CID1:t2'] = { id = 'CID1:t2', owner = 'CID1', coords = { x = 0, y = 0, z = 0 } }; E.items['fh:wagon:CID1:t2'] = 5
    E.tick(); T.eq(0, #failedReasons(E))
    E.wagons['CID1:t2'] = nil -- seen, then gone: 3 consecutive misses
    E.tick(); E.tick(); T.eq(0, #failedReasons(E)); E.tick(); T.same({ 'wagon_lost' }, failedReasons(E))
end)

case('D: abandon undoes accept: cargo out via removeItem, row dropped, idempotent, no failed/delivered event', function()
    local E = newEnv(); assert(accept(E))
    E.hooks.abandon(7, state('heartlands.dunes.trade_salt'))
    T.eq(1, #E.removeCalls); T.eq(5, E.removeCalls[1].n); T.eq(0, #E.registered.getContracts(7)); assert(#E.deleted >= 1)
    E.hooks.abandon(7, state('heartlands.dunes.trade_salt'))
    T.eq(1, #E.removeCalls, 'second abandon is a no-op')
    atDest(E); E.tick(); T.eq(0, delivered(E)); T.eq(0, #failedReasons(E))
end)

case('D: abandon while a delivery check is mid-removeItem: no delivered event, cargo removed exactly once', function()
    local E = newEnv(); assert(accept(E)); atDest(E)
    E.removeYield = true
    T.eq('io', E.step())                     -- check is inside removeItem
    E.hooks.abandon(7, state('heartlands.dunes.trade_salt'))
    T.eq(1, #E.removeCalls, 'abandon did not remove a second time')
    T.eq('wait', E.step())                   -- check resumes, sees c.abandoned
    T.eq(0, delivered(E)); T.eq(0, #E.registered.getContracts(7)); T.eq(1, #E.removeCalls)
end)

case('D: abandon mid-check while that check\'s removeItem fails: the check retries the undo (cargo out), no event', function()
    local E = newEnv(); assert(accept(E)); atDest(E)
    E.removeYield = true
    E.removeSeq = { { false, 'fh_inventory_down' }, { true } }
    T.eq('io', E.step())
    E.removeYield = false -- the retry must not park again
    E.hooks.abandon(7, state('heartlands.dunes.trade_salt'))
    T.eq('wait', E.step())
    T.eq(2, #E.removeCalls); T.eq(0, delivered(E)); T.eq(0, E.items['fh:wagon:CID1:t2'])
end)

case('E: accept lock per player: a second accept during the first is refused, cap holds', function()
    local E = newEnv(); E.addYield = true
    E.nearest = { type = 'wagon', id = 'fh:wagon:CID1:t2' }
    E.wagons['CID1:t2'] = { id = 'CID1:t2', owner = 'CID1', coords = { x = 0, y = 0, z = 0 } }
    local r1, r2
    local co1 = coroutine.create(function() r1 = { E.hooks.accept(7, offer({ key = 'heartlands.dunes.trade_salt' })) } end)
    assert(coroutine.resume(co1))                           -- parked inside addItem
    local ok2, a, b = coroutine.resume(coroutine.create(function() r2 = { E.hooks.accept(7, offer()) } end))
    assert(ok2); T.eq(false, r2[1]); T.eq('fh_busy', r2[2])
    E.addYield = false; assert(coroutine.resume(co1)); T.eq(true, r1[1])
    T.eq(1, #E.registered.getContracts(7))
end)

case('E: duplicate key and maxActivePerPlayer are refused', function()
    local E = newEnv({ max = 1 }); assert(accept(E))
    local ok, err = E.hooks.accept(7, offer()); T.eq(false, ok); T.eq('fh_freight_active', err)
    ok, err = E.hooks.accept(7, offer({ key = 'heartlands.dunes.trade_cloth', item = 'trade_cloth', reward = 100 }))
    T.eq(false, ok); T.eq('fh_freight_too_many', err); T.eq(1, #E.addCalls)
end)

case('accept rejects tampered offers before touching the wagon', function()
    local E = newEnv(); E.nearest = { type = 'wagon', id = 'fh:wagon:CID1:t2' }
    local ok, err = E.hooks.accept(7, offer({ qty = 999 })); T.eq(false, ok); T.eq('fh_freight_bad_qty', err); T.eq(0, #E.addCalls)
end)

case('onEvent hook maps through state.quest_id', function()
    local E = newEnv()
    T.eq('complete', E.hooks.onEvent(F.EVENT_DELIVERED, { key = 'k' }, { quest_id = 'job:freight:k' }))
    T.eq(nil, E.hooks.onEvent(F.EVENT_DELIVERED, { key = 'k' }, { quest_id = 'job:freight:j' }))
end)

T.finish()

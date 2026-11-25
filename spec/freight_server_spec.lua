-- Run from repo root: `lua spec/freight_server_spec.lua` (or via tools/run-specs.py).
-- Loads fh_trade/server/freight.lua under stubbed natives/exports (fh_core incl. B7 removeItem, fh_cargo, rsg-core,
-- fh_quests). Covers: cargo removal via removeItem (all-or-nothing, pcall), restart safety, abandon races/idempotence,
-- accept lock, ref guards. The check loop is one coroutine: each resume = one tick (Wait yields 'wait').
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local case = T.it
local F = dofile(here .. '../server/resources/[fh]/fh_trade/shared/freight.lua')
local SERVER = here .. '../server/resources/[fh]/fh_trade/server/freight.lua'
local CARGO = dofile(here .. '../server/resources/[fh]/fh_cargo/shared/cargo_rules.lua')

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
    FhCargoRules = CARGO
    if opts.t2 then -- roads-02 R9: T2 contracts on a 500 m route; salt gets a weight so wagon fit is real
        FhTradeConfig.freight.t2 = { minWagonTier = 2, minDistance = 400, deadlineBase = 900,
            deadlinePerMeter = 1.0, minQty = 10, maxQty = 30, qtyPerLevel = 30, maxLoad = 300000, payMultiple = 3, payCapMultiple = 4,
            repDelta = 4, maxOffers = 2 }
        FhTradeConfig.freight.destinations.heartlands = { x = 0, y = 0, z = 0, radius = 40 }
        FhTradeConfig.goods.trade_salt.weight, FhTradeConfig.goods.trade_salt.stackable = 1500, true
    end
    E.states, E.unlockCalls, E.shortages, E.tierCalls = {}, {}, {}, {}
    E.tiers = {} -- R13: region_id -> fh_progression getTier result (default 2 = T2 open everywhere)
    local registered = {}
    local exp = setmetatable({}, { __call = function(_, name, fn) registered[name] = fn end })
    exp['rsg-core'] = { GetCoreObject = function() return { Functions = {
        GetPlayer = function(src) local c = E.online[src] return c and { PlayerData = { citizenid = c, source = src } } or nil end,
        GetPlayerByCitizenId = function(cid) for s, c in pairs(E.online) do if c == cid then return { PlayerData = { citizenid = c, source = s } } end end end,
    } } end }
    exp.fh_trade = { getShortages = function(_, id) return E.shortages[id] or {} end }
    if not opts.noProgression then
        -- canUnlock stays stubbed only so specs can prove freight never calls it (R13: regional getTier alone)
        exp.fh_progression = { canUnlock = function(_, src, id)
            E.unlockCalls[#E.unlockCalls + 1] = { src = src, id = id }
            if E.unlockFn then return E.unlockFn(src, id) end
            return true
        end }
        if not opts.noGetTier then
            exp.fh_progression.getTier = function(_, src, region)
                E.tierCalls[#E.tierCalls + 1] = { src = src, region = region }
                if E.tierFn then return E.tierFn(src, region) end
                local t = E.tiers[region]
                if t == nil then return 2 end
                return t
            end
        end
    end
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
        snapshot = function(_, ref) if E.snapshotYield then coroutine.yield('io') end local n = E.items[ref.id] if n == nil then return nil, 'x' end return { [1] = { name = 'trade_salt', amount = n } } end,
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
        if sql:find('^DELETE') then E.deleted[#E.deleted + 1] = true if E.deleteYield then coroutine.yield('io') end end
        return {}
    end } }
    local thread
    CreateThread = function(fn) thread = fn end
    Wait = function() coroutine.yield('wait') end
    TriggerEvent = function(name, payload) E.events[#E.events + 1] = { name = name, payload = payload } end
    AddEventHandler = function(n, fn) if n == 'onResourceStart' then E.onStart = fn end end
    GetResourceState = function(name) return E.states[name] or 'started' end
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

case('idea-676: abandon yielding in drop() while the check finishes its undo: cargo removed exactly once', function()
    -- check parks in snapshot (busy held); abandon marks the contract and parks in drop()'s DELETE before reading busy.
    -- The check then sees c.abandoned and runs the undo takeCargo, parking in removeItem. busy must still be held
    -- there, so the resumed abandon skips its own takeCargo instead of removing the qty a second time.
    local E = newEnv(); assert(accept(E)); T.eq(5, E.items['fh:wagon:CID1:t2'])
    E.snapshotYield = true
    T.eq('io', E.step())                     -- check is inside snapshot
    E.snapshotYield, E.deleteYield = false, true
    local A = coroutine.create(function() E.hooks.abandon(7, state('heartlands.dunes.trade_salt')) end)
    local okA, r = coroutine.resume(A); assert(okA, tostring(r)); T.eq('io', r) -- abandon parked in drop()
    E.deleteYield, E.removeYield = false, true
    T.eq('io', E.step())                     -- check: abandoned -> undo takeCargo, parked in removeItem
    T.eq(1, #E.removeCalls)
    okA, r = coroutine.resume(A); assert(okA, tostring(r))
    T.eq(1, #E.removeCalls, 'resumed abandon must not start a second removeItem')
    T.eq('wait', E.step())                   -- check's removeItem completes
    if coroutine.status(A) ~= 'dead' then assert(coroutine.resume(A)) end
    T.eq(1, #E.removeCalls); T.eq(0, E.items['fh:wagon:CID1:t2'], 'qty removed once, not twice')
    T.eq(0, delivered(E)); T.eq(0, #failedReasons(E)); T.eq(0, #E.registered.getContracts(7))
    E.removeYield = false; E.tick(); T.eq(1, #E.removeCalls, 'later ticks touch nothing')
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

-- ---------------------------------------------------------------- T2 contracts (roads-02 R9)

local function t2Offer(E, level)
    E.shortages.dunes = { { item = 'trade_salt', level = level or 0.5, price = 10 } }
    for _, o in ipairs(E.hooks.offers('heartlands')) do if o.tier == 2 then return o end end
end
-- Put the player's `tierKey` wagon next to them (getWagon reports its fh_cargo tier key) and accept `o`.
local function acceptWith(E, o, tierKey)
    local id = 'CID1:' .. tierKey
    E.nearest = { type = 'wagon', id = 'fh:wagon:' .. id }
    E.wagons[id] = { id = id, owner = 'CID1', tier = tierKey, coords = { x = 0, y = 0, z = 0 } }
    return E.hooks.accept(7, o)
end
local function t1Offer(E)
    E.shortages.dunes = { { item = 'trade_salt', level = 0.5, price = 10 } }
    for _, o in ipairs(E.hooks.offers('heartlands')) do if o.tier == 1 then return o end end
end

case('T2 offers: the board hook lists T2 with locked = true (no player is known there) next to T1', function()
    local E = newEnv({ t2 = true })
    E.shortages.dunes = { { item = 'trade_salt', level = 0.5, price = 10 } }
    local list = E.hooks.offers('heartlands')
    T.eq(2, #list)
    T.eq(1, list[1].tier); T.eq(nil, list[1].locked)
    T.eq(2, list[2].tier); T.eq(true, list[2].locked); T.eq(nil, list[2].unlock); T.eq(2, list[2].min_region_tier)
    T.eq(0, #E.unlockCalls, 'offers must not call canUnlock'); T.eq(0, #E.tierCalls, 'offers must not call getTier')
end)

case('T2 accept allowed: getTier(src, heartlands) 2 + t2 wagon -> cargo added, contract listed; canUnlock never called', function()
    local E = newEnv({ t2 = true })
    local o = t2Offer(E)
    local ok, err = acceptWith(E, o, 't2')
    assert(ok == true, tostring(err))
    T.same({ { src = 7, region = 'heartlands' } }, E.tierCalls); T.eq(0, #E.unlockCalls)
    T.eq(1, #E.addCalls); T.eq(15, E.addCalls[1].n); T.same({ freight = 'heartlands.dunes.trade_salt.t2' }, E.addCalls[1].info)
    T.eq(1, #E.registered.getContracts(7))
end)

case('T2 accept refused fh_locked: tier 1 / not started / getTier throws / export missing / non-number; nothing added, lock released', function()
    local setups = {
        tier_too_low = function(E) E.tiers.heartlands = 1 end,
        not_started = function(E) E.states.fh_progression = 'stopped' end,
        throws = function(E) E.tierFn = function() error('progression cache boom') end end,
        string = function(E) E.tierFn = function() return '2' end end,
    }
    for name, setup in pairs(setups) do
        local E = newEnv({ t2 = true })
        local o = t2Offer(E)
        setup(E)
        local ok, err = acceptWith(E, o, 't2')
        assert(ok == false and err == 'fh_locked', name .. ' -> ' .. tostring(err))
        T.eq(0, #E.addCalls, name .. ': cargo added'); T.eq(0, #E.registered.getContracts(7), name .. ': contract kept')
        if name == 'not_started' then T.eq(0, #E.tierCalls, 'getTier called while fh_progression is stopped') end
        E.tierFn, E.states.fh_progression, E.tiers.heartlands = nil, nil, nil -- gate opens: the accept lock must have been released
        assert(acceptWith(E, o, 't2') == true, name .. ': accept lock not released')
    end
    local E = newEnv({ t2 = true, noProgression = true }) -- fh_progression exports absent entirely
    local ok, err = acceptWith(E, t2Offer(E), 't2')
    assert(ok == false and err == 'fh_locked', 'missing export -> ' .. tostring(err))
end)

case('T1 is never gated: accepted with fh_progression stopped / throwing / absent, no progression export called', function()
    for _, mode in ipairs({ 'stopped', 'throws', 'absent' }) do
        local E = newEnv({ t2 = true, noProgression = mode == 'absent' })
        if mode == 'stopped' then E.states.fh_progression = 'stopped' end
        if mode == 'throws' then E.tierFn = function() error('x') end E.unlockFn = E.tierFn end
        local ok, err = acceptWith(E, t1Offer(E), 't1')
        assert(ok == true, mode .. ' -> ' .. tostring(err))
        T.eq(0, #E.unlockCalls, mode .. ': canUnlock called for T1'); T.eq(0, #E.tierCalls, mode .. ': getTier called for T1')
    end
end)

case('T2 wagon fit: t1 cart too small, unknown tier fails closed, t3 fits; refusal adds nothing', function()
    local E = newEnv({ t2 = true })
    local o = t2Offer(E, 1) -- 30 salt = 45 kg
    local ok, err = acceptWith(E, o, 't1')
    assert(ok == false and err == 'fh_freight_wagon_too_small', tostring(err))
    E.nearest = { type = 'wagon', id = 'fh:wagon:CID1:tx' }
    E.wagons['CID1:tx'] = { id = 'CID1:tx', owner = 'CID1', tier = 'tx', coords = { x = 0, y = 0, z = 0 } }
    ok, err = E.hooks.accept(7, o)
    assert(ok == false and err == 'fh_freight_wagon_unknown', tostring(err))
    E.getWagonThrows = true
    ok, err = acceptWith(E, o, 't2')
    assert(ok == false and err == 'fh_freight_wagon_unknown', 'getWagon throws -> ' .. tostring(err))
    E.getWagonThrows = false
    T.eq(0, #E.addCalls, 'cargo added on a refused fit')
    assert(acceptWith(E, o, 't3') == true, 't3 freight wagon fits')
end)

case('T2 accept: the character changed while getTier ran -> fh_no_player, nothing added', function()
    local E = newEnv({ t2 = true })
    local o = t2Offer(E)
    E.tierFn = function() E.online[7] = 'CID2' return 3 end -- getTier yields in game (rep cache load)
    local ok, err = acceptWith(E, o, 't2')
    assert(ok == false and err == 'fh_no_player', tostring(err))
    T.eq(0, #E.addCalls)
end)

case('R12: post-derived destinations deliver at resolved post coords and skip disabled regions', function()
    local E = newEnv({ t2 = true })
    FhTradeConfig.freight.destinations = nil
    FhTradeConfig.posts = {
        { id = 'val_post', radius = 6 },
        { id = 'dunes_post', radius = 6 },
        { id = 'off_post', radius = 6 },
    }
    FhRegions = {
        regions = { heartlands = {}, dunes = {}, offworld = {} },
        posts = {
            val_post   = { id = 'val_post',   region = 'heartlands', x = 0,    y = 0, z = 0 },
            dunes_post = { id = 'dunes_post', region = 'dunes',      x = 500,  y = 0, z = 0 },
            off_post   = { id = 'off_post',   region = 'offworld',   x = 2000, y = 0, z = 0 },
        },
        isKnownRegion = function(id) return id == 'heartlands' or id == 'dunes' or id == 'offworld' end,
        isEnabled = function(id) return id ~= 'offworld' end,
    }
    E.shortages.dunes = { { item = 'trade_salt', level = 0.5, price = 10 } }
    E.shortages.offworld = { { item = 'trade_salt', level = 0.9, price = 10 } }
    local list = E.hooks.offers('heartlands')
    T.eq(2, #list, 'disabled region offworld is excluded from offers')
    for _, o in ipairs(list) do assert(o.to_region == 'dunes') end
    T.eq(0, #E.hooks.offers('offworld'), 'disabled board returns no offers')
    assert(acceptWith(E, list[1], 't1') == true)
    E.wagons['CID1:t1'].coords = { x = 500, y = 0, z = 0 }
    E.tick()
    T.eq(1, delivered(E), 'delivered using post-derived destination')
end)

case('R12: accept rejects disabled origin or destination (before unlock/addItem, lock free); in-flight contract still delivers if region is later disabled', function()
    local E = newEnv({ t2 = true })
    FhTradeConfig.freight.destinations = nil
    FhTradeConfig.posts = {
        { id = 'val_post', radius = 6 },
        { id = 'dunes_post', radius = 6 },
        { id = 'off_post', radius = 6 },
    }
    local disabled = { offworld = true }
    FhRegions = {
        regions = { heartlands = {}, dunes = {}, offworld = {} },
        posts = {
            val_post   = { id = 'val_post',   region = 'heartlands', x = 0,    y = 0, z = 0 },
            dunes_post = { id = 'dunes_post', region = 'dunes',      x = 500,  y = 0, z = 0 },
            off_post   = { id = 'off_post',   region = 'offworld',   x = 2000, y = 0, z = 0 },
        },
        isKnownRegion = function(id) return id == 'heartlands' or id == 'dunes' or id == 'offworld' end,
        isEnabled = function(id) return not disabled[id] end,
    }
    -- Build stale/hand-crafted T2 offers with disabled origin or destination.
    local staleTo = F.generate(FhTradeConfig, 'heartlands', { offworld = { { item = 'trade_salt', level = 0.5, price = 10 } } }, FhRegions)[2]
    local staleFrom = F.generate(FhTradeConfig, 'offworld', { heartlands = { { item = 'trade_salt', level = 0.5, price = 10 } } }, FhRegions)[2]
    assert(staleTo and staleTo.tier == 2 and staleFrom and staleFrom.tier == 2)

    local ok, err = acceptWith(E, staleTo, 't2')
    T.eq(false, ok); T.eq('fh_freight_region_disabled', err)
    ok, err = acceptWith(E, staleFrom, 't2')
    T.eq(false, ok); T.eq('fh_freight_region_disabled', err)
    T.eq(0, #E.tierCalls, 'rejected before the progression tier gate'); T.eq(0, #E.unlockCalls)
    T.eq(0, #E.addCalls, 'rejected before adding cargo')

    -- Accept lock was never stuck: a valid enabled-region offer still accepts, and completes even if its destination is disabled mid-run.
    E.shortages.dunes = { { item = 'trade_salt', level = 0.5, price = 10 } }
    local validOffer = E.hooks.offers('heartlands')[1]
    assert(acceptWith(E, validOffer, 't1') == true)
    disabled.dunes = true
    E.wagons['CID1:t1'].coords = { x = 500, y = 0, z = 0 }
    E.tick()
    T.eq(1, delivered(E), 'already-accepted contract still delivers when destination is later disabled')
end)

-- ---------------------------------------------------------------- regional tier gate (roads-03 R13)

-- Three post regions on a line: heartlands (0) - dunes (500) - bayou_nwa (1000); every pair is >= 400 m (T2 route).
local function regionalEnv(opts)
    local E = newEnv(opts or { t2 = true })
    FhTradeConfig.freight.destinations.bayou_nwa = { x = 1000, y = 0, z = 0, radius = 40 }
    FhRegions = { regions = { heartlands = {}, dunes = {}, bayou_nwa = {} },
        isKnownRegion = function(id) return id == 'heartlands' or id == 'dunes' or id == 'bayou_nwa' end }
    E.shortages.dunes = { { item = 'trade_salt', level = 0.5, price = 10 } }
    return E
end
local function t2From(E, region)
    for _, o in ipairs(E.hooks.offers(region)) do if o.tier == 2 and o.to_region == 'dunes' then return o end end
end

case('R13 offers: region_id = origin board, tier and min_region_tier ride along; offers() reads no tiers', function()
    local E = regionalEnv()
    local o = t2From(E, 'bayou_nwa')
    T.eq('bayou_nwa', o.region_id); T.eq('bayou_nwa', o.from_region); T.eq(2, o.tier); T.eq(2, o.min_region_tier)
    T.eq(0, #E.tierCalls, 'offers must not call getTier'); T.eq(0, #E.unlockCalls)
end)

case('R13 regional: bayou_nwa tier 2 opens bayou-origin T2 while heartlands tier 1 refuses heartlands-origin T2', function()
    local E = regionalEnv()
    E.tiers = { heartlands = 1, bayou_nwa = 2 }
    local ok, err = acceptWith(E, t2From(E, 'heartlands'), 't2')
    assert(ok == false and err == 'fh_locked', 'heartlands tier 1 -> ' .. tostring(err))
    T.same({ { src = 7, region = 'heartlands' } }, E.tierCalls)
    T.eq(0, #E.addCalls)
    ok, err = acceptWith(E, t2From(E, 'bayou_nwa'), 't2')
    assert(ok == true, 'bayou tier 2 -> ' .. tostring(err))
    T.same({ src = 7, region = 'bayou_nwa' }, E.tierCalls[2], 'gate reads the ORIGIN region, not the destination')
    T.eq(0, #E.unlockCalls, 'no global canUnlock: regional rep alone opens the board')
    T.eq(1, #E.addCalls); T.eq(1, #E.registered.getContracts(7))
end)

case('R13 regional tier 1 / 2 / 3 per region: T2 needs >= 2; T1 accepted at tier 1 without reading the tier', function()
    for _, t in ipairs({ 1, 2, 3 }) do
        local E = regionalEnv()
        E.tiers = { heartlands = t }
        local ok, err = acceptWith(E, t2From(E, 'heartlands'), 't2')
        T.eq(t >= 2, ok == true, 'tier ' .. t .. ' -> ' .. tostring(err))
        if t < 2 then T.eq('fh_locked', err) end
    end
    local E = regionalEnv()
    E.tiers = { heartlands = 1 }
    assert(acceptWith(E, t1Offer(E), 't1') == true)
    T.eq(0, #E.tierCalls, 'T1 never reads getTier'); T.eq(0, #E.unlockCalls)
end)

case('R13 kill switch: freight.t2.enabled false hides T2 and refuses a listed T2 at any region tier (lock free, no gate call); on again works', function()
    local E = regionalEnv()
    E.tiers = { bayou_nwa = 3 }
    local o = t2From(E, 'bayou_nwa') -- listed while on
    FhTradeConfig.freight.t2.enabled = false
    T.eq(nil, t2From(E, 'bayou_nwa'), 'T2 hidden while off')
    local t1n = 0 for _, x in ipairs(E.hooks.offers('bayou_nwa')) do if x.tier == 1 then t1n = t1n + 1 end end
    assert(t1n > 0, 'T1 still listed while T2 is off')
    local ok, err = acceptWith(E, o, 't2')
    assert(ok == false and err == 'fh_freight_tier_disabled', 'off -> ' .. tostring(err))
    T.eq(0, #E.tierCalls); T.eq(0, #E.addCalls)
    FhTradeConfig.freight.t2.enabled = 'yes' -- non-true is off (fail closed)
    ok, err = acceptWith(E, o, 't2')
    assert(ok == false and err == 'fh_freight_tier_disabled', 'non-true -> ' .. tostring(err))
    FhTradeConfig.freight.t2.enabled = true
    assert(t2From(E, 'bayou_nwa'), 'T2 listed again')
    ok, err = acceptWith(E, o, 't2')
    assert(ok == true, 'on -> ' .. tostring(err))
    T.eq(0, #E.unlockCalls)
end)

case('R13 fail closed: progression down / getTier throws / non-number / getTier export missing -> fh_locked, lock released', function()
    local setups = {
        stopped = function(E) E.states.fh_progression = 'stopped' end,
        starting = function(E) E.states.fh_progression = 'starting' end,
        throws = function(E) E.tierFn = function() error('progression cache boom') end end,
        string = function(E) E.tierFn = function() return '3' end end,
        ['nil'] = function(E) E.tierFn = function() return nil end end,
        nan = function(E) E.tierFn = function() return 0 / 0 end end,
        bool = function(E) E.tierFn = function() return true end end,
    }
    for name, setup in pairs(setups) do
        local E = regionalEnv()
        local o = t2From(E, 'bayou_nwa')
        setup(E)
        local ok, err = acceptWith(E, o, 't2')
        assert(ok == false and err == 'fh_locked', name .. ' -> ' .. tostring(err))
        T.eq(0, #E.addCalls, name .. ': cargo added'); T.eq(0, #E.unlockCalls, name .. ': canUnlock called')
        T.eq(0, #E.registered.getContracts(7), name .. ': contract kept')
        if name == 'stopped' or name == 'starting' then T.eq(0, #E.tierCalls, name .. ': getTier called while not started') end
        E.tierFn, E.states.fh_progression = nil, nil
        assert(acceptWith(E, o, 't2') == true, name .. ': accept lock not released')
    end
    local E = regionalEnv({ t2 = true, noGetTier = true }) -- only canUnlock exported, getTier missing
    local ok, err = acceptWith(E, t2From(E, 'bayou_nwa'), 't2')
    assert(ok == false and err == 'fh_locked', 'missing getTier -> ' .. tostring(err))
    T.eq(0, #E.unlockCalls); T.eq(0, #E.addCalls)
end)

case('R13 forged region_id: claiming another origin is rejected before any gate call; moved origin breaks the key', function()
    local E = regionalEnv()
    E.tiers = { heartlands = 1, bayou_nwa = 3 }
    local o = t2From(E, 'heartlands')
    local forged = {} for k, v in pairs(o) do forged[k] = v end
    forged.region_id = 'bayou_nwa'
    local ok, err = acceptWith(E, forged, 't2')
    assert(ok == false and err == 'fh_freight_bad_region', 'forged region_id -> ' .. tostring(err))
    forged.from_region = 'bayou_nwa' -- region_id now matches, but the key still names heartlands
    ok, err = acceptWith(E, forged, 't2')
    assert(ok == false and err == 'fh_freight_bad_key', 'forged from_region -> ' .. tostring(err))
    forged.from_region, forged.region_id = 'heartlands', nil
    ok, err = acceptWith(E, forged, 't2')
    assert(ok == false and err == 'fh_freight_bad_region', 'T2 without region_id -> ' .. tostring(err))
    T.eq(0, #E.tierCalls); T.eq(0, #E.unlockCalls); T.eq(0, #E.addCalls)
    assert(acceptWith(E, t2From(E, 'heartlands'), 't2') == false, 'genuine heartlands offer still refused at tier 1')
end)

case('R13 character swap while getTier yields -> fh_no_player; nothing added', function()
    local E = regionalEnv()
    local o = t2From(E, 'bayou_nwa')
    E.tierFn = function() E.online[7] = 'CID2' return 3 end -- getTier yields in game (rep cache load)
    local ok, err = acceptWith(E, o, 't2')
    assert(ok == false and err == 'fh_no_player', tostring(err))
    T.eq(0, #E.unlockCalls); T.eq(0, #E.addCalls)
    E.online[7], E.tierFn = 'CID1', nil
    assert(acceptWith(E, o, 't2') == true, 'accept lock released after a swap refusal')
end)

T.finish()

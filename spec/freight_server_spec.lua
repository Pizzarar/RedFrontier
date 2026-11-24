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
        FhTradeConfig.freight.t2 = { unlock = 'contracts_t2', minWagonTier = 2, minDistance = 400, deadlineBase = 900,
            deadlinePerMeter = 1.0, premium = 1.5, repDelta = 4, maxOffers = 2, qty = { trade_salt = { min = 90, max = 190 } } }
        FhTradeConfig.freight.destinations.heartlands = { x = 0, y = 0, z = 0, radius = 40 }
        FhTradeConfig.goods.trade_salt.weight, FhTradeConfig.goods.trade_salt.stackable = 1500, true
    end
    E.states, E.unlockCalls, E.shortages = {}, {}, {}
    local registered = {}
    local exp = setmetatable({}, { __call = function(_, name, fn) registered[name] = fn end })
    exp['rsg-core'] = { GetCoreObject = function() return { Functions = {
        GetPlayer = function(src) local c = E.online[src] return c and { PlayerData = { citizenid = c, source = src } } or nil end,
        GetPlayerByCitizenId = function(cid) for s, c in pairs(E.online) do if c == cid then return { PlayerData = { citizenid = c, source = s } } end end end,
    } } end }
    exp.fh_trade = { getShortages = function(_, id) return E.shortages[id] or {} end }
    if not opts.noProgression then
        exp.fh_progression = { canUnlock = function(_, src, id)
            E.unlockCalls[#E.unlockCalls + 1] = { src = src, id = id }
            if E.unlockFn then return E.unlockFn(src, id) end
            return true
        end }
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
    T.eq(2, list[2].tier); T.eq(true, list[2].locked); T.eq('contracts_t2', list[2].unlock)
    T.eq(0, #E.unlockCalls, 'offers must not call canUnlock')
end)

case('T2 accept allowed: canUnlock(src, contracts_t2) true + t2 wagon -> cargo added, contract listed', function()
    local E = newEnv({ t2 = true })
    local o = t2Offer(E)
    local ok, err = acceptWith(E, o, 't2')
    assert(ok == true, tostring(err))
    T.same({ { src = 7, id = 'contracts_t2' } }, E.unlockCalls)
    T.eq(1, #E.addCalls); T.eq(140, E.addCalls[1].n); T.same({ freight = 'heartlands.dunes.trade_salt.t2' }, E.addCalls[1].info)
    T.eq(1, #E.registered.getContracts(7))
end)

case('T2 accept refused fh_locked: tier_too_low / not started / throws / export missing / non-true; nothing added, lock released', function()
    local setups = {
        tier_too_low = function(E) E.unlockFn = function() return false, 'tier_too_low' end end,
        not_started = function(E) E.states.fh_progression = 'stopped' end,
        throws = function(E) E.unlockFn = function() error('progression cache boom') end end,
        truthy = function(E) E.unlockFn = function() return 1 end end,
    }
    for name, setup in pairs(setups) do
        local E = newEnv({ t2 = true })
        local o = t2Offer(E)
        setup(E)
        local ok, err = acceptWith(E, o, 't2')
        assert(ok == false and err == 'fh_locked', name .. ' -> ' .. tostring(err))
        T.eq(0, #E.addCalls, name .. ': cargo added'); T.eq(0, #E.registered.getContracts(7), name .. ': contract kept')
        if name == 'not_started' then T.eq(0, #E.unlockCalls, 'canUnlock called while fh_progression is stopped') end
        E.unlockFn, E.states.fh_progression = nil, nil -- gate opens: the accept lock must have been released
        assert(acceptWith(E, o, 't2') == true, name .. ': accept lock not released')
    end
    local E = newEnv({ t2 = true, noProgression = true }) -- fh_progression exports absent entirely
    local ok, err = acceptWith(E, t2Offer(E), 't2')
    assert(ok == false and err == 'fh_locked', 'missing export -> ' .. tostring(err))
end)

case('T1 is never gated: accepted with fh_progression stopped / throwing / absent, canUnlock not called', function()
    for _, mode in ipairs({ 'stopped', 'throws', 'absent' }) do
        local E = newEnv({ t2 = true, noProgression = mode == 'absent' })
        if mode == 'stopped' then E.states.fh_progression = 'stopped' end
        if mode == 'throws' then E.unlockFn = function() error('x') end end
        local ok, err = acceptWith(E, t1Offer(E), 't1')
        assert(ok == true, mode .. ' -> ' .. tostring(err))
        T.eq(0, #E.unlockCalls, mode .. ': canUnlock called for T1')
    end
end)

case('T2 wagon fit: t1 cart too small, unknown tier fails closed, t3 fits; refusal adds nothing', function()
    local E = newEnv({ t2 = true })
    local o = t2Offer(E, 1) -- 190 salt = 285 kg
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

case('T2 accept: the character changed while canUnlock ran -> fh_no_player, nothing added', function()
    local E = newEnv({ t2 = true })
    local o = t2Offer(E)
    E.unlockFn = function() E.online[7] = 'CID2' return true end -- canUnlock yields in game (rep read)
    local ok, err = acceptWith(E, o, 't2')
    assert(ok == false and err == 'fh_no_player', tostring(err))
    T.eq(0, #E.addCalls)
end)

T.finish()

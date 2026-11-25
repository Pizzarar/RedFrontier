-- Run from repo root: `lua spec/tailor_spec.lua` (Lua 5.4: pcall must be yieldable).
-- Drives the real fh_tailor/server/tailor.lua (FhTailorCore) and shared/tailor_logic.lua with a fake DB / rsg-core /
-- fh_progression / fh_economy. Every fake dep yields first (inside a coroutine), like an export awaiting MySQL, so
-- `interleave` can run two operations round-robin (a cooperative scheduler, like FXServer threads).
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local res = here .. '../server/resources/[fh]/fh_tailor/'
package.path = res .. 'shared/?.lua;' .. res .. 'server/?.lua;' .. package.path
local case, eq, same = T.it, T.eq, T.same
local logic = require('tailor_logic')
local core = require('tailor')
local regions = require('regions') -- fh_core/shared via the prelude's package.path

assert(loadfile(res .. 'config.lua'))()
local realCfg = FhTailorConfig

-- ---------------------------------------------------------------- fixture catalog

local function fixture()
    return {
        FittedOutfits = false, maxItems = 2, maxSavedOutfits = 3, chargeRetries = 2, chargeRetryMs = 10, lockWaitMs = 1000,
        shops = {
            small = { id = 'small', label = 'Small Store', region_id = 'heartlands', size = 1,
                coords = { x = 0, y = 0, z = 0 }, radius = 10 },
            city = { id = 'city', label = 'City Tailor', region_id = 'heartlands', size = 3,
                coords = { x = 100, y = 0, z = 0 }, radius = 10 },
        },
        catalog = {
            starter_m = { id = 'starter_m', label = 'Work M', sex = 'male', kind = 'outfit', preset = 1, min_tier = 1, earned_only = true },
            starter_f = { id = 'starter_f', label = 'Work F', sex = 'female', kind = 'outfit', preset = 2, min_tier = 1, earned_only = true },
            ranch_m = { id = 'ranch_m', label = 'Ranch M', sex = 'male', kind = 'outfit', preset = 3, price = 12.5, min_tier = 1 },
            suit_m = { id = 'suit_m', label = 'Suit M', sex = 'male', kind = 'outfit', preset = 4, price = 80, min_tier = 2, size = 3 },
            gala_m = { id = 'gala_m', label = 'Gala M', sex = 'male', kind = 'outfit', preset = 5, price = 200, min_tier = 3, shops = { 'city' } },
            dress_f = { id = 'dress_f', label = 'Dress F', sex = 'female', kind = 'outfit', preset = 6, price = 30, min_tier = 1 },
            hat = { id = 'hat', label = 'Hat', sex = 'any', kind = 'item', component = 1234, price = 4, min_tier = 1 },
            gloves = { id = 'gloves', label = 'Gloves', sex = 'any', kind = 'item', component = 'gloves_hash', price = 3, min_tier = 1 },
            bandana = { id = 'bandana', label = 'Bandana', sex = 'any', kind = 'item', component = 99, price = 2, min_tier = 1 },
            pelt_coat = { id = 'pelt_coat', label = 'Legendary Coat', sex = 'male', kind = 'item', component = 7, min_tier = 1, earned_only = true },
        },
        starter = { male = { 'starter_m', 'bandana' }, female = { 'starter_f' } },
    }
end

-- ---------------------------------------------------------------- fake world

---src 1 = C1 (male), src 2 = C2 (female), src 3 = C1 reconnected. Players stand at the small shop by default.
local function world(cfg, o)
    o = o or {}
    local W = {
        cfg = cfg,
        srcs = { [1] = 'C1', [2] = 'C2', [3] = 'C1' },
        sex = { C1 = 'male', C2 = 'female', C3 = 'male' },
        known = { C1 = true, C2 = true, C3 = true },
        money = { C1 = 1000, C2 = 1000, C3 = 1000 },
        pos = { [1] = 'small', [2] = 'small', [3] = 'small' },
        tier = { heartlands = 1 },
        owned = {}, state = {}, saved = {},
        charges = {}, inflight = {}, chargeScript = {}, fail = {}, hooks = {}, calls = {}, logs = {}, events = {},
        clock = 0, isReady = true,
    }
    for k, v in pairs(o) do W[k] = v end
    local function step(name, ...)
        if coroutine.isyieldable() then coroutine.yield(name) end
        W.calls[name] = (W.calls[name] or 0) + 1
        local h = W.hooks[name]
        if h then h(...) end
    end
    local function rowsOf(cid) W.owned[cid] = W.owned[cid] or {}; return W.owned[cid] end
    W.deps = {
        ready = function() return W.isReady end,
        citizenOf = function(src) return W.srcs[src] end,
        sexOf = function(src) return W.sex[W.srcs[src]] end,
        onlineSrc = function(cid) -- lowest src for the citizenid (deterministic; pairs order is not)
            local best
            for s, c in pairs(W.srcs) do if c == cid and (best == nil or s < best) then best = s end end
            return best
        end,
        inRange = function(src, shop) return W.pos[src] == shop.id end,
        tierOf = function(src, region)
            step('tierOf', src, region)
            if W.fail.tierOf then return nil end
            return W.tier[region]
        end,
        -- fh_economy B7 model: per-character in-flight lock (fh_charge_busy), balance check, debit. Scripted results first.
        charge = function(src, amount, reason, region)
            local cid = W.srcs[src]
            if W.inflight[cid] then return false, 'fh_charge_busy' end
            W.inflight[cid] = true
            local function done(...) W.inflight[cid] = nil; return ... end
            step('charge', src, amount, reason, region)
            local scripted = table.remove(W.chargeScript, 1)
            if scripted then
                if scripted == 'throw' then return done(false, 'charge_unavailable') end -- the wrapper's pcall result
                return done(false, scripted)
            end
            cid = W.srcs[src]
            if not cid then return done(false, 'no_player') end
            if W.money[cid] < amount then return done(false, 'fh_insufficient_funds') end
            W.money[cid] = W.money[cid] - amount
            W.charges[#W.charges + 1] = { cid = cid, amount = amount, reason = reason, region = region }
            return done(true)
        end,
        wait = function(ms)
            if coroutine.isyieldable() then coroutine.yield('wait') end
            W.clock = W.clock + math.max(ms, 1)
        end,
        clock = function() return W.clock end,
        now = function() return 1700000000 end,
        emit = function(name, p) W.events[#W.events + 1] = { name = name, p = p } end,
        log = function(m) W.logs[#W.logs + 1] = m end,
        db = {
            loadOwned = function(cid)
                step('loadOwned', cid)
                if W.fail.loadOwned then return nil end
                local out = {}
                for id, r in pairs(rowsOf(cid)) do out[#out + 1] = { entry_id = id, source = r.source } end
                return out
            end,
            loadState = function(cid)
                step('loadState', cid)
                if W.fail.loadState then return nil end
                local s = W.state[cid]
                if not s then return false end
                return { starter_at = s.starter_at, worn_outfit = s.worn_outfit, worn_items = s.worn_items or '' }
            end,
            loadSaved = function(cid)
                step('loadSaved', cid)
                local out = {}
                for slot, r in pairs(W.saved[cid] or {}) do
                    out[#out + 1] = { slot = slot, label = r.label, outfit_id = r.outfit_id, items = r.items }
                end
                return out
            end,
            insertOwned = function(cid, id, source, now)
                step('insertOwned', cid, id, source)
                if W.fail.insertOwned then return nil end
                local rows = rowsOf(cid)
                if rows[id] then return 0 end
                rows[id] = { source = source, at = now }
                return 1
            end,
            deleteOwned = function(cid, id, source)
                step('deleteOwned', cid, id, source)
                if W.fail.deleteOwned then return nil end
                local rows = rowsOf(cid)
                if rows[id] and rows[id].source == source then rows[id] = nil; return 1 end
                return 0
            end,
            grantStarter = function(cid, ids, worn, now)
                step('grantStarter', cid)
                if W.fail.grantStarter then return false end
                local rows = rowsOf(cid)
                for _, id in ipairs(ids) do if not rows[id] then rows[id] = { source = 'starter', at = now } end end
                local s = W.state[cid] or { worn_items = '' }
                W.state[cid] = s
                s.starter_at = s.starter_at or now
                if s.worn_outfit == nil then s.worn_outfit, s.worn_items = worn, '' end
                return true
            end,
            saveWorn = function(cid, outfit, items)
                step('saveWorn', cid)
                if W.fail.saveWorn then return false end
                local s = W.state[cid] or {}
                W.state[cid] = s
                s.worn_outfit, s.worn_items = outfit, items
                return true
            end,
            saveSlot = function(cid, slot, label, outfit, items)
                step('saveSlot', cid)
                W.saved[cid] = W.saved[cid] or {}
                W.saved[cid][slot] = { label = label, outfit_id = outfit, items = items }
                return true
            end,
            citizenSex = function(cid)
                step('citizenSex', cid)
                if W.fail.citizenSex then return nil end
                if not W.known[cid] then return false end
                return true, W.sex[cid]
            end,
        },
    }
    W.C = core.new(cfg, logic, W.deps)
    return W
end

---Run fn(...) to completion (yields are stepped through).
local function run(fn, ...)
    local co = coroutine.create(fn)
    local out = table.pack(coroutine.resume(co, ...))
    while coroutine.status(co) ~= 'dead' do out = table.pack(coroutine.resume(co)) end
    assert(out[1], tostring(out[2]))
    return table.unpack(out, 2, out.n)
end

---Cooperative scheduler, like the FXServer one: start a and run it until it yields at `at` (a dep name), then start b
---and resume a and b round-robin (one yield each) until both are dead. A waiter (Wait(0) -> yield) lets the lock
---holder run and release, exactly as on the server. @return table a results, table b results
local function interleave(a, at, b)
    local cos, outs = { coroutine.create(a) }, {}
    local ok, y = coroutine.resume(cos[1])
    assert(ok, tostring(y))
    outs[1] = table.pack(ok, y)
    while coroutine.status(cos[1]) ~= 'dead' and y ~= at do
        outs[1] = table.pack(coroutine.resume(cos[1])); ok, y = outs[1][1], outs[1][2]; assert(ok, tostring(y))
    end
    assert(y == at or coroutine.status(cos[1]) ~= 'dead', 'a finished before yielding at ' .. tostring(at))
    cos[2] = coroutine.create(b)
    local steps = 0
    while coroutine.status(cos[1]) ~= 'dead' or coroutine.status(cos[2]) ~= 'dead' do
        for k = 2, 1, -1 do -- b first: it starts while a is parked at `at`
            if coroutine.status(cos[k]) ~= 'dead' then
                local r = table.pack(coroutine.resume(cos[k]))
                assert(r[1], tostring(r[2]))
                outs[k] = r
            end
        end
        steps = steps + 1
        assert(steps < 100000, 'interleave: no progress')
    end
    return table.pack(table.unpack(outs[1], 2, outs[1].n)), table.pack(table.unpack(outs[2], 2, outs[2].n))
end

local function owns(W, cid, id) return W.owned[cid] and W.owned[cid][id] ~= nil end
local function eventsNamed(W, name)
    local n = 0
    for _, e in ipairs(W.events) do if e.name == name then n = n + 1 end end
    return n
end
local function hasLog(W, pat)
    for _, l in ipairs(W.logs) do if l:find(pat) then return true end end
    return false
end

-- ---------------------------------------------------------------- config

case('real config validates (with FhRegions)', function()
    eq(true, (logic.validateConfig(realCfg, regions.isKnownRegion)))
    eq(false, realCfg.FittedOutfits, 'FittedOutfits ships off until @spikes S1 PASS')
end)

case('fixture validates; bad configs are refused', function()
    eq(true, (logic.validateConfig(fixture(), regions.isKnownRegion)))
    local function bad(mut, want)
        local c = fixture(); mut(c)
        local ok, why = logic.validateConfig(c, regions.isKnownRegion)
        eq(false, ok, want); eq(want, why)
    end
    bad(function(c) c.FittedOutfits = 'no' end, 'bad_FittedOutfits')
    bad(function(c) c.maxItems = 40 end, 'bad_maxItems')
    bad(function(c) c.maxSavedOutfits = 0 end, 'bad_maxSavedOutfits')
    bad(function(c) c.shops.small.region_id = 'atlantis' end, 'bad_shop_small')
    bad(function(c) c.shops.small.radius = 0 end, 'bad_shop_small')
    bad(function(c) c.catalog.ranch_m.price = nil end, 'bad_entry_ranch_m')
    bad(function(c) c.catalog.ranch_m.price = 1.005 end, 'bad_entry_ranch_m')
    bad(function(c) c.catalog.ranch_m.min_tier = 4 end, 'bad_entry_ranch_m')
    bad(function(c) c.catalog.ranch_m.kind = 'hat' end, 'bad_entry_ranch_m')
    bad(function(c) c.catalog.ranch_m.preset = nil end, 'bad_entry_ranch_m')
    bad(function(c) c.catalog.hat.component = nil end, 'bad_entry_hat')
    bad(function(c) c.catalog.ranch_m.id = 'other' end, 'bad_entry_ranch_m')
    bad(function(c) c.catalog.gala_m.shops = { 'nowhere' } end, 'bad_entry_gala_m')
    bad(function(c) c.catalog.gala_m.size = 2 end, 'bad_entry_gala_m')
    bad(function(c) c.catalog['a,b'] = { id = 'a,b', label = 'x', sex = 'any', kind = 'item', component = 1, price = 1, min_tier = 1 } end, 'bad_entry_a,b')
    bad(function(c) c.starter.male = { 'hat' } end, 'bad_starter_male')       -- first starter id must be an outfit
    bad(function(c) c.starter.female = { 'starter_m' } end, 'bad_starter_female') -- wrong sex
    bad(function(c) c.starter.male = {} end, 'bad_starter_male')
end)

-- ---------------------------------------------------------------- stock filter + tier gating

local function ids(rows) local o = {}; for i, r in ipairs(rows) do o[i] = r.id end; return o end

case('stock: size-gated, shop lists, sex, tier; earned_only never listed', function()
    local c = fixture()
    same({ 'bandana', 'gloves', 'hat', 'ranch_m' }, ids(logic.stockFor(c, c.shops.small, 3, 'male')))
    -- city (size 3): size-3 suit and city-only gala appear as the tier allows
    same({ 'bandana', 'gloves', 'hat', 'ranch_m' }, ids(logic.stockFor(c, c.shops.city, 1, 'male')))
    same({ 'bandana', 'gloves', 'hat', 'ranch_m', 'suit_m' }, ids(logic.stockFor(c, c.shops.city, 2, 'male')))
    same({ 'bandana', 'gloves', 'hat', 'ranch_m', 'suit_m', 'gala_m' }, ids(logic.stockFor(c, c.shops.city, 3, 'male')))
    same({ 'bandana', 'gloves', 'hat', 'dress_f' }, ids(logic.stockFor(c, c.shops.city, 3, 'female')))
    same({}, ids(logic.stockFor(c, c.shops.city, nil, 'male')), 'no tier = no stock')
    for _, r in ipairs(logic.stockFor(c, c.shops.city, 3, 'male')) do
        assert(r.id ~= 'pelt_coat' and r.id ~= 'starter_m', 'earned_only listed: ' .. r.id)
    end
    eq(false, logic.stocked(c.catalog.pelt_coat, c.shops.city))
    eq(false, logic.stocked(c.catalog.gala_m, c.shops.small))
    local rows = logic.stockFor(c, c.shops.small, 1, 'male', { hat = 'buy' })
    for _, r in ipairs(rows) do eq(r.id == 'hat', r.owned, 'owned flag ' .. r.id) end
end)

case('checkBuy: order and codes', function()
    local c = fixture()
    same({ false, 'earned_only' }, { logic.checkBuy(c.catalog.pelt_coat, c.shops.city, 'male', 3, {}) })
    same({ false, 'not_stocked' }, { logic.checkBuy(c.catalog.suit_m, c.shops.small, 'male', 3, {}) })
    same({ false, 'wrong_sex' }, { logic.checkBuy(c.catalog.dress_f, c.shops.small, 'male', 3, {}) })
    same({ false, 'tier_too_low' }, { logic.checkBuy(c.catalog.suit_m, c.shops.city, 'male', 1, {}) })
    same({ false, 'already_owned' }, { logic.checkBuy(c.catalog.suit_m, c.shops.city, 'male', 2, { suit_m = 'buy' }) })
    same({ true }, { logic.checkBuy(c.catalog.suit_m, c.shops.city, 'male', 2, {}) })
end)

case('buy: tier gating uses the shop region tier from fh_progression', function()
    local W = world(fixture(), { pos = { [1] = 'city' } })
    same({ false, 'tier_too_low' }, { run(W.C.buy, 1, 'city', 'suit_m') })
    eq(0, #W.charges); eq(false, owns(W, 'C1', 'suit_m'))
    W.tier.heartlands = 2
    local ok, r = run(W.C.buy, 1, 'city', 'suit_m')
    eq(true, ok); eq('suit_m', r.entry_id); eq(80, r.price)
    eq(1, #W.charges); eq(920, W.money.C1)
    W.fail.tierOf = true
    same({ false, 'tier_unavailable' }, { run(W.C.buy, 1, 'city', 'gala_m') })
end)

-- ---------------------------------------------------------------- buy

case('buy: charges once, writes ownership, emits fh:tailor:owned', function()
    local W = world(fixture())
    local ok, r = run(W.C.buy, 1, 'small', 'ranch_m')
    eq(true, ok); eq(12.5, r.price); eq(nil, r.unverified)
    same({ { cid = 'C1', amount = 12.5, reason = 'tailor_buy:ranch_m', region = 'heartlands' } }, W.charges)
    eq('buy', W.owned.C1.ranch_m.source)
    eq(1, eventsNamed(W, 'fh:tailor:owned'))
    local ev = W.events[#W.events].p
    eq('C1', ev.citizenid); eq('ranch_m', ev.entry_id); eq('buy', ev.source); eq(1, ev.src); eq('small', ev.shop_id)
    -- retry after success: already owned, never charged again
    same({ false, 'already_owned' }, { run(W.C.buy, 1, 'small', 'ranch_m') })
    eq(1, #W.charges)
end)

case('buy: refusals before any money moves', function()
    local W = world(fixture())
    same({ false, 'unknown_shop' }, { run(W.C.buy, 1, 'nope', 'ranch_m') })
    same({ false, 'unknown_entry' }, { run(W.C.buy, 1, 'small', 'nope') })
    same({ false, 'unknown_entry' }, { run(W.C.buy, 1, 'small', nil) })
    same({ false, 'earned_only' }, { run(W.C.buy, 1, 'small', 'pelt_coat') })
    same({ false, 'not_stocked' }, { run(W.C.buy, 1, 'small', 'suit_m') })
    same({ false, 'wrong_sex' }, { run(W.C.buy, 1, 'small', 'dress_f') })
    same({ false, 'out_of_range' }, { run(W.C.buy, 1, 'city', 'ranch_m') })
    same({ false, 'no_player' }, { run(W.C.buy, 9, 'small', 'ranch_m') })
    same({ false, 'no_player' }, { run(W.C.buy, '1', 'small', 'ranch_m') })
    W.money.C1 = 5
    same({ false, 'fh_insufficient_funds' }, { run(W.C.buy, 1, 'small', 'ranch_m') })
    eq(false, owns(W, 'C1', 'ranch_m'), 'claim removed after a refusal')
    W.isReady = false
    same({ false, 'not_ready' }, { run(W.C.buy, 1, 'small', 'hat') })
    eq(0, #W.charges); eq(5, W.money.C1)
    eq(0, eventsNamed(W, 'fh:tailor:owned'))
end)

case('buy: full B7 error map passes through, nothing taken, claim removed; every code has text', function()
    local B7 = { 'fh_insufficient_funds', 'fh_charge_busy', 'ledger_failed', 'removemoney_refused', 'no_player',
        'player_changed', 'invalid_amount', 'amount_too_large', 'invalid_reason', 'unknown_region', 'charge_refused' }
    for _, code in ipairs(B7) do
        local W = world(fixture())
        -- busy is retried chargeRetries times: script every attempt
        for _ = 1, (code == 'fh_charge_busy') and 3 or 1 do W.chargeScript[#W.chargeScript + 1] = code end
        same({ false, code }, { run(W.C.buy, 1, 'small', 'ranch_m') }, code)
        eq(0, #W.charges, code); eq(1000, W.money.C1, code)
        eq(false, owns(W, 'C1', 'ranch_m'), code .. ': claim must be handed back')
        eq(nil, W.C.entries.C1.owned.ranch_m, code)
        assert(logic.messages[code], 'no message for B7 code ' .. code)
        -- the player can buy it after the refusal: a clean new attempt, charged once
        local ok = run(W.C.buy, 1, 'small', 'ranch_m')
        eq(true, ok, code .. ' retry'); eq(1, #W.charges, code)
    end
    local codes = { 'charge_unavailable', 'not_ready', 'tailor_busy', 'tailor_error', 'db_failed', 'unknown_shop',
        'unknown_entry', 'out_of_range', 'earned_only', 'not_stocked', 'wrong_sex', 'tier_too_low', 'tier_unavailable',
        'already_owned', 'not_owned', 'not_outfit', 'not_item', 'too_many_items', 'duplicate_item', 'bad_slot',
        'empty_slot', 'bad_label', 'invalid_citizenid', 'unknown_citizenid', 'invalid_source' }
    for _, code in ipairs(codes) do assert(logic.messages[code], 'no message for ' .. code) end
    eq('Refused: weird', logic.message('weird'))
end)

case('buy: fh_charge_busy is retried (bounded) and charged exactly once', function()
    local W = world(fixture())
    W.chargeScript = { 'fh_charge_busy', 'fh_charge_busy' } -- two busy, third attempt goes through
    local ok = run(W.C.buy, 1, 'small', 'ranch_m')
    eq(true, ok); eq(1, #W.charges); eq(987.5, W.money.C1)
    eq(3, W.calls.charge)
    -- real in-flight charge for the same character (another resource) -> busy, retried after it finishes
    local W2 = world(fixture())
    W2.inflight.C1 = true
    W2.hooks.tierOf = function() end
    local waits = 0
    local origWait = W2.deps.wait
    W2.deps.wait = function(ms) waits = waits + 1; W2.inflight.C1 = nil; return origWait(ms) end
    W2.C = core.new(W2.cfg, logic, W2.deps)
    eq(true, (run(W2.C.buy, 1, 'small', 'ranch_m')))
    eq(1, waits); eq(1, #W2.charges)
end)

case('buy: busy retry stops (no charge) when the character switched between attempts', function()
    local W = world(fixture())
    W.chargeScript = { 'fh_charge_busy' }
    W.deps.wait = function() W.srcs[1] = 'C3' end -- src 1 is now another character
    W.C = core.new(W.cfg, logic, W.deps)
    same({ false, 'player_changed' }, { run(W.C.buy, 1, 'small', 'ranch_m') })
    eq(0, #W.charges); eq(1000, W.money.C3); eq(1000, W.money.C1)
    eq(false, owns(W, 'C1', 'ranch_m'), 'claim handed back')
    eq(1, W.calls.charge, 'no second attempt for the new character')
end)

case('buy: character dropped during the tier read -> no claim, no charge', function()
    local W = world(fixture())
    W.hooks.tierOf = function() W.srcs[1] = nil end
    same({ false, 'no_player' }, { run(W.C.buy, 1, 'small', 'ranch_m') })
    eq(nil, W.calls.insertOwned); eq(0, #W.charges)
end)

case('buy: concurrent buys for one character -> tailor_busy, charged once', function()
    local W = world(fixture())
    local a, b = interleave(function() return W.C.buy(1, 'small', 'ranch_m') end, 'charge',
        function() return W.C.buy(3, 'small', 'ranch_m') end) -- src 3 = same citizenid (reconnect / second client)
    eq(true, a[1]); same({ false, 'tailor_busy' }, { b[1], b[2] })
    eq(1, #W.charges)
    -- different item, same character, still busy (one op per character): never interleaves two charges
    local W2 = world(fixture())
    local a2, b2 = interleave(function() return W2.C.buy(1, 'small', 'ranch_m') end, 'insertOwned',
        function() return W2.C.buy(1, 'small', 'hat') end)
    eq(true, a2[1]); eq('tailor_busy', b2[2]); eq(1, #W2.charges)
    -- other characters are not blocked
    local W3 = world(fixture())
    local a3, b3 = interleave(function() return W3.C.buy(1, 'small', 'ranch_m') end, 'charge',
        function() return W3.C.buy(2, 'small', 'dress_f') end)
    eq(true, a3[1]); eq(true, b3[1]); eq(2, #W3.charges)
end)

case('buy: DB already owns it (stale cache / restart lost the lock) -> no charge', function()
    local W = world(fixture())
    run(W.C.load, 1)
    W.owned.C1.ranch_m = { source = 'buy', at = 1 } -- written behind the cache (e.g. an fh_tailor restart mid-buy)
    same({ false, 'already_owned' }, { run(W.C.buy, 1, 'small', 'ranch_m') })
    eq(0, #W.charges); eq(nil, W.calls.charge)
    eq('buy', W.owned.C1.ranch_m.source, 'existing row untouched')
end)

case('buy: claim write failing -> db_failed, no charge', function()
    local W = world(fixture())
    W.fail.insertOwned = true
    same({ false, 'db_failed' }, { run(W.C.buy, 1, 'small', 'ranch_m') })
    eq(nil, W.calls.charge)
end)

case('buy: charge_unavailable (export threw) keeps the claim: never charged twice', function()
    local W = world(fixture())
    W.chargeScript = { 'throw' }
    local ok, r = run(W.C.buy, 1, 'small', 'ranch_m')
    eq(true, ok); eq(true, r.unverified)
    eq(true, owns(W, 'C1', 'ranch_m')); eq(true, hasLog(W, '^ALERT charge threw'))
    same({ false, 'already_owned' }, { run(W.C.buy, 1, 'small', 'ranch_m') })
    eq(1, W.calls.charge)
end)

case('buy: refusal whose claim delete fails -> owned unpaid (logged), no money, no retry charge', function()
    local W = world(fixture())
    W.money.C1 = 1
    W.fail.deleteOwned = true
    same({ false, 'fh_insufficient_funds' }, { run(W.C.buy, 1, 'small', 'ranch_m') })
    eq(true, owns(W, 'C1', 'ranch_m')); eq('buy', W.C.entries.C1.owned.ranch_m)
    eq(true, hasLog(W, 'claim was not removed'))
    W.money.C1 = 100
    same({ false, 'already_owned' }, { run(W.C.buy, 1, 'small', 'ranch_m') })
    eq(0, #W.charges)
end)

case('buy: a throw inside a dep -> tailor_error, lock released', function()
    local W = world(fixture())
    W.hooks.tierOf = function() error('boom') end
    same({ false, 'tailor_error' }, { run(W.C.buy, 1, 'small', 'ranch_m') })
    eq(nil, W.C.locks.C1); eq(true, hasLog(W, 'ERROR buy'))
    W.hooks.tierOf = nil
    eq(true, (run(W.C.buy, 1, 'small', 'ranch_m')))
end)

-- ---------------------------------------------------------------- grant

case('grant: idempotent, emits once, works offline', function()
    local W = world(fixture())
    same({ true, 'granted' }, { run(W.C.grant, 'C1', 'pelt_coat', 'hunting:legendary_bear') })
    same({ true, 'already_owned' }, { run(W.C.grant, 'C1', 'pelt_coat', 'hunting:legendary_bear') })
    same({ true, 'already_owned' }, { run(W.C.grant, 'C1', 'pelt_coat', 'quests:other') })
    eq('hunting:legendary_bear', W.owned.C1.pelt_coat.source)
    eq(1, eventsNamed(W, 'fh:tailor:owned')); eq(1, W.events[1].p.src)
    -- offline character (no src): still granted, event src nil
    same({ true, 'granted' }, { run(W.C.grant, 'C3', 'hat', 'quests:q1') })
    eq(nil, W.events[2].p.src)
    eq(0, #W.charges)
end)

case('grant: refusals', function()
    local W = world(fixture())
    same({ false, 'invalid_citizenid' }, { run(W.C.grant, 12, 'hat', 'x') })
    same({ false, 'invalid_citizenid' }, { run(W.C.grant, '123', 'hat', 'x') })
    same({ false, 'unknown_entry' }, { run(W.C.grant, 'C1', 'nope', 'x') })
    same({ false, 'invalid_source' }, { run(W.C.grant, 'C1', 'hat', '') })
    same({ false, 'invalid_source' }, { run(W.C.grant, 'C1', 'hat', ('x'):rep(33)) })
    same({ false, 'unknown_citizenid' }, { run(W.C.grant, 'ZZ9', 'hat', 'x') })
    same({ false, 'wrong_sex' }, { run(W.C.grant, 'C2', 'pelt_coat', 'hunting:x') })
    W.fail.citizenSex = true
    same({ false, 'db_failed' }, { run(W.C.grant, 'C1', 'hat', 'x') })
    W.fail.citizenSex, W.fail.insertOwned = nil, true
    same({ false, 'db_failed' }, { run(W.C.grant, 'C1', 'hat', 'x') })
    W.isReady = false
    same({ false, 'not_ready' }, { run(W.C.grant, 'C1', 'hat', 'x') })
end)

case('grant during a buy waits for the lock; the buy refusal cannot remove the granted row', function()
    local W = world(fixture())
    W.money.C1 = 1 -- the buy will be refused
    local a, b = interleave(function() return W.C.buy(1, 'small', 'hat') end, 'charge',
        function() return W.C.grant('C1', 'hat', 'quests:q1') end)
    -- the grant ran after the buy released the lock (it waited), so the buy's claim was handed back first
    same({ false, 'fh_insufficient_funds' }, { a[1], a[2] })
    same({ true, 'granted' }, { b[1], b[2] })
    eq('quests:q1', W.owned.C1.hat.source)
    eq('quests:q1', W.C.entries.C1.owned.hat)
end)

-- ---------------------------------------------------------------- starter

case('starter: granted once on first load, worn; never re-granted', function()
    local W = world(fixture())
    eq(true, (run(W.C.load, 1)))
    eq('starter', W.owned.C1.starter_m.source); eq('starter', W.owned.C1.bandana.source)
    eq(1700000000, W.state.C1.starter_at); eq('starter_m', W.state.C1.worn_outfit)
    same({ outfit = 'starter_m', items = {} }, W.C.entries.C1.worn)
    eq(1, W.calls.grantStarter)
    W.C.forget(1)
    eq(true, (run(W.C.load, 1)))
    eq(1, W.calls.grantStarter, 'second load must not grant again')
    -- starter_at set but rows gone (e.g. admin cleanup): not re-granted
    W.owned.C1 = {}
    W.C.forget(1)
    run(W.C.load, 1)
    eq(1, W.calls.grantStarter); eq(false, owns(W, 'C1', 'starter_m'))
    eq(nil, W.C.entries.C1.worn, 'worn look dropped: not owned any more')
    eq(0, eventsNamed(W, 'fh:tailor:owned')); eq(0, #W.charges)
end)

case('starter: an existing worn look is kept; female gets the female set', function()
    local W = world(fixture())
    W.owned.C1 = { ranch_m = { source = 'buy', at = 1 } }
    W.state.C1 = { worn_outfit = 'ranch_m', worn_items = '' } -- chosen before the starter ran (starter_at nil)
    run(W.C.load, 1)
    eq('ranch_m', W.state.C1.worn_outfit); eq('ranch_m', W.C.entries.C1.worn.outfit)
    eq(true, owns(W, 'C1', 'starter_m'))
    run(W.C.load, 2)
    eq(true, owns(W, 'C2', 'starter_f')); eq(false, owns(W, 'C2', 'bandana'))
end)

case('starter: unknown sex or a failed grant is retried on the next load', function()
    local W = world(fixture())
    W.sex.C1 = nil
    run(W.C.load, 1)
    eq(nil, W.calls.grantStarter); eq(true, hasLog(W, 'sex unknown'))
    W.sex.C1 = 'male'
    W.fail.grantStarter = true
    W.C.forget(1)
    run(W.C.load, 1)
    eq(false, owns(W, 'C1', 'starter_m')); eq(true, hasLog(W, 'starter grant failed'))
    W.fail.grantStarter = nil
    W.C.forget(1)
    run(W.C.load, 1)
    eq(true, owns(W, 'C1', 'starter_m')); eq(2, W.calls.grantStarter)
end)

case('starter: two concurrent loads grant once', function()
    local W = world(fixture())
    local a, b = interleave(function() return W.C.load(1) end, 'loadOwned', function() return W.C.load(1) end)
    eq(true, a[1]); eq(true, b[1])
    eq(1, W.calls.grantStarter)
end)

case('load: DB read failure -> db_failed, nothing cached', function()
    local W = world(fixture())
    W.fail.loadState = true
    same({ false, 'db_failed' }, { run(W.C.load, 1) })
    eq(nil, W.C.entries.C1)
end)

-- ---------------------------------------------------------------- equip + wardrobe

case('equip: validates ownership, sex, kinds and counts; persists and emits', function()
    local W = world(fixture())
    run(W.C.load, 1)
    same({ false, 'not_owned' }, { run(W.C.equip, 1, 'ranch_m') })
    same({ false, 'unknown_entry' }, { run(W.C.equip, 1, 'nope') })
    same({ false, 'not_outfit' }, { run(W.C.equip, 1, 'bandana') })
    same({ false, 'wrong_sex' }, { run(W.C.equip, 1, 'dress_f') })
    same({ false, 'not_owned' }, { run(W.C.equip, 1, 'starter_m', { 'hat' }) })
    same({ false, 'not_item' }, { run(W.C.equip, 1, 'starter_m', { 'starter_m' }) })
    same({ false, 'not_item' }, { run(W.C.equip, 1, 'starter_m', 'bandana') })
    same({ false, 'duplicate_item' }, { run(W.C.equip, 1, 'starter_m', { 'bandana', 'bandana' }) })
    run(W.C.grant, 'C1', 'hat', 'quests:q1')
    run(W.C.grant, 'C1', 'gloves', 'quests:q2')
    same({ false, 'too_many_items' }, { run(W.C.equip, 1, 'starter_m', { 'hat', 'gloves', 'bandana' }) })
    eq(0, eventsNamed(W, 'fh:tailor:equipped'))
    local ok, r = run(W.C.equip, 1, 'starter_m', { 'hat', 'gloves' })
    eq(true, ok); same({ outfit = 'starter_m', items = { 'hat', 'gloves' }, fitted = false }, r)
    eq('starter_m', W.state.C1.worn_outfit); eq('hat,gloves', W.state.C1.worn_items)
    eq(1, eventsNamed(W, 'fh:tailor:equipped'))
    -- relog keeps it
    W.C.forget(1)
    run(W.C.load, 1)
    same({ outfit = 'starter_m', items = { 'hat', 'gloves' } }, W.C.entries.C1.worn)
    W.fail.saveWorn = true
    same({ false, 'db_failed' }, { run(W.C.equip, 1, 'starter_m') })
    same({ outfit = 'starter_m', items = { 'hat', 'gloves' } }, W.C.entries.C1.worn, 'cache unchanged on failure')
end)

case('saved outfits: save, wear (re-checked), slot bounds, wardrobe view', function()
    local W = world(fixture())
    run(W.C.load, 1)
    same({ false, 'bad_slot' }, { run(W.C.saveOutfit, 1, 0, 'x', 'starter_m') })
    same({ false, 'bad_slot' }, { run(W.C.saveOutfit, 1, 4, 'x', 'starter_m') })
    same({ false, 'bad_label' }, { run(W.C.saveOutfit, 1, 1, ('x'):rep(33), 'starter_m') })
    same({ false, 'not_owned' }, { run(W.C.saveOutfit, 1, 1, 'Sunday', 'ranch_m') })
    same({ true }, { run(W.C.saveOutfit, 1, 1, 'Work', 'starter_m', { 'bandana' }) })
    same({ false, 'empty_slot' }, { run(W.C.wearSaved, 1, 2) })
    local ok, r = run(W.C.wearSaved, 1, 1)
    eq(true, ok); same({ 'bandana' }, r.items)
    local okW, view = run(W.C.getWardrobe, 1)
    eq(true, okW); eq(false, view.fitted); eq(2, view.maxItems); eq(3, view.maxSaved)
    same({ 'bandana', 'starter_m' }, ids(view.owned))
    same({ label = 'Work', outfit = 'starter_m', items = { 'bandana' }, valid = true }, view.saved[1])
    -- a saved look whose piece is no longer owned is shown invalid and refused when worn
    W.owned.C1.bandana = nil
    W.C.forget(1)
    run(W.C.load, 1)
    eq(false, select(2, run(W.C.getWardrobe, 1)).saved[1].valid)
    same({ false, 'not_owned' }, { run(W.C.wearSaved, 1, 1) })
end)

case('getStock: per-character rows with owned flags; tier read failure', function()
    local W = world(fixture())
    W.tier.heartlands = 2
    run(W.C.buy, 1, 'small', 'hat')
    local ok, s = run(W.C.getStock, 1, 'city')
    eq(true, ok); eq(2, s.tier); eq('city', s.shop.id)
    same({ 'bandana', 'gloves', 'hat', 'ranch_m', 'suit_m' }, ids(s.rows))
    for _, r in ipairs(s.rows) do eq(r.id == 'hat' or r.id == 'bandana', r.owned, r.id) end -- bandana = starter
    same({ false, 'unknown_shop' }, { run(W.C.getStock, 1, 'nope') })
    W.fail.tierOf = true
    same({ false, 'tier_unavailable' }, { run(W.C.getStock, 1, 'city') })
end)

case('item list encoding round-trips', function()
    same({ 'a', 'b_c' }, logic.decodeItems(logic.encodeItems({ 'a', 'b_c' })))
    same({}, logic.decodeItems(''))
    same({}, logic.decodeItems(nil))
    eq('male', logic.sexOf(0)); eq('female', logic.sexOf(1)); eq(nil, logic.sexOf(nil)); eq(nil, logic.sexOf(2))
end)

T.finish()

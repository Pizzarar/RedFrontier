-- Run from repo root: `lua spec/freight_spec.lua` (or via tools/run-specs.py). Pure freight rules + soft-dep registration.
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local case = T.it
local F = dofile(here .. '../server/resources/[fh]/fh_trade/shared/freight.lua')

local function cfgNew(over)
    local c = {
        goods = { trade_salt = { base = 10, label = 'Salt' }, trade_cloth = { base = 20, label = 'Cloth' } },
        freight = {
            minQty = 1, maxQty = 20, qtyPerLevel = 20, premium = 1.25, repDelta = 2, deadlineSeconds = 1800, maxOffers = 3,
            rewardCapMultiple = 4, destinations = { heartlands = { x = 0, y = 0, z = 0, radius = 40 }, dunes = { x = 500, y = 0, z = 0, radius = 40 } },
        },
    }
    for k, v in pairs(over or {}) do c.freight[k] = v end
    return c
end
local known = function(id) return id == 'heartlands' or id == 'dunes' end

-- ---------------------------------------------------------------- generation

case('generate: one offer per shortage in OTHER regions, stable key, title, reward and rep', function()
    local c = cfgNew()
    local offers = F.generate(c, 'heartlands', {
        heartlands = { { item = 'trade_salt', level = 0.9, price = 12 } }, -- own region: skipped
        dunes = { { item = 'trade_cloth', level = 0.5, price = 30 }, { item = 'trade_salt', level = 0.2, price = 11 } },
    })
    T.eq(2, #offers)
    local o = offers[1]
    T.eq('heartlands.dunes.trade_cloth', o.key)
    T.eq(10, o.qty) -- ceil(0.5*20)
    T.eq(375, o.reward) -- floor(10*30*1.25)
    T.eq('dunes', o.to_region); T.eq('heartlands', o.from_region)
    assert(o.title:find('Cloth') and o.title:find('dunes'))
    T.same({ money = 375, rep = { region_id = 'dunes', delta = 2 } }, o.rewards)
    T.eq(1800, o.deadline_s)
    T.eq(4, offers[2].qty) -- ceil(0.2*20)
end)

case('generate: same inputs give same keys; qty clamped; offers capped; no destination / same region excluded', function()
    local c = cfgNew({ maxOffers = 1 })
    local sh = { dunes = { { item = 'trade_salt', level = 1, price = 10 }, { item = 'trade_cloth', level = 0.3, price = 20 } },
                 nowhere = { { item = 'trade_salt', level = 1, price = 10 } } }
    local a, b = F.generate(c, 'heartlands', sh), F.generate(c, 'heartlands', sh)
    T.eq(1, #a); T.eq(a[1].key, b[1].key); T.eq(20, a[1].qty)
    T.eq(0, #F.generate(cfgNew(), 'dunes', { dunes = { { item = 'trade_salt', level = 1, price = 10 } } }), 'same region off by default')
    T.eq(1, #F.generate(cfgNew({ allowSameRegion = true }), 'dunes', { dunes = { { item = 'trade_salt', level = 1, price = 10 } } }))
    T.eq(0, #F.generate(c, 'heartlands', { dunes = { { item = 'gone_item', level = 1, price = 10 } } }), 'unknown good')
    T.eq(0, #F.generate(c, '', sh)); T.eq(0, #F.generate(c, 'heartlands', nil))
end)

case('quest id <-> key round trip, key fits the 64 char quest id limit', function()
    local k = F.offerKey('heartlands', 'dunes', 'trade_salt')
    T.eq('job:freight:' .. k, F.questId(k)); T.eq(k, F.keyOf(F.questId(k)))
    T.eq(nil, F.keyOf('job:hunt:x')); T.eq(nil, F.keyOf('job:freight:')); T.eq(nil, F.keyOf(5))
    assert(#F.questId(k) <= 64)
end)

case('validateOffer: accepts generated offers, refuses tampering', function()
    local c = cfgNew()
    local o = F.generate(c, 'heartlands', { dunes = { { item = 'trade_salt', level = 0.5, price = 10 } } })[1]
    assert(F.validateOffer(c, o, known))
    local function bad(field, v, code)
        local x = {} for k, val in pairs(o) do x[k] = val end
        x[field] = v
        local ok, err = F.validateOffer(c, x, known)
        assert(not ok and err == code, field .. ' -> ' .. tostring(err))
    end
    bad('item', 'gold_bar', 'unknown_item'); bad('qty', 0, 'bad_qty'); bad('qty', 21, 'bad_qty'); bad('qty', 2.5, 'bad_qty')
    bad('reward', 100000, 'bad_reward'); bad('reward', 0, 'bad_reward'); bad('key', 'x', 'bad_key')
    bad('to_region', 'atlantis', 'bad_region'); bad('deadline_s', 5, 'bad_deadline'); bad('to_region', 'heartlands', 'same_region')
    local ok, err = F.validateOffer(c, nil, known); assert(not ok and err == 'bad_offer')
end)

-- ---------------------------------------------------------------- delivery / loss / timeout

local function contract(over)
    local c = F.newContract({ key = 'k', from_region = 'heartlands', to_region = 'dunes', item = 'trade_salt', qty = 5, reward = 80, deadline_s = 100 }, 'CID1', 'CID1:t2', 1000)
    for k, v in pairs(over or {}) do c[k] = v end
    return c
end
local wagon = { owner = 'CID1', coords = { x = 1, y = 1, z = 1 } }

case('newContract: deadline = accept + duration', function()
    local c = contract()
    T.eq(1100, c.deadline); T.eq(0, c.miss); T.eq('CID1:t2', c.wagon)
end)

case('evaluate: at target with the cargo = delivered; not at target = nothing', function()
    local v = F.evaluate(contract(), { online = true, wagon = wagon, cargoCount = 5, atTarget = true }, 1050)
    T.eq('delivered', v)
    v = F.evaluate(contract(), { online = true, wagon = wagon, cargoCount = 9, atTarget = true }, 1050); T.eq('delivered', v)
    v = F.evaluate(contract(), { online = true, wagon = wagon, cargoCount = 5, atTarget = false }, 1050); T.eq(nil, v)
end)

case('evaluate: timeout wins over delivery at/after the deadline', function()
    T.eq('timeout', (F.evaluate(contract(), { online = true, wagon = wagon, cargoCount = 5, atTarget = true }, 1100)))
    T.eq('timeout', (F.evaluate(contract(), { online = true, wagon = nil }, 5000)))
end)

case('evaluate: wagon gone / wrong owner is lost only after the grace checks', function()
    local c = contract()
    local v, m = F.evaluate(c, { online = true, wagon = nil }, 1010, 3); T.eq(nil, v); T.eq(1, m)
    c.miss = m
    v, m = F.evaluate(c, { online = true, wagon = nil }, 1020, 3); T.eq(nil, v); c.miss = m
    v, m = F.evaluate(c, { online = true, wagon = nil }, 1030, 3); T.eq('wagon_lost', v)
    v = F.evaluate(contract({ miss = 2 }), { online = true, wagon = wagon, owner_ok = false }, 1030, 3); T.eq('wagon_lost', v)
end)

case('evaluate: cargo short = cargo_missing after grace; recovery resets the counter', function()
    local c = contract({ miss = 2 })
    T.eq('cargo_missing', (F.evaluate(c, { online = true, wagon = wagon, cargoCount = 4, atTarget = false }, 1010, 3)))
    local v, m = F.evaluate(c, { online = true, wagon = wagon, cargoCount = 5, atTarget = false }, 1010, 3); T.eq(nil, v); T.eq(0, m)
end)

case('evaluate: unreadable cargo fails closed (no delivery, no loss) and keeps the counter', function()
    local v, m = F.evaluate(contract({ miss = 1 }), { online = true, wagon = wagon, cargoCount = nil, atTarget = true }, 1010, 3)
    T.eq(nil, v); T.eq(1, m)
    T.eq(nil, (F.evaluate(nil, {}, 1))); T.eq(nil, (F.evaluate(contract(), {}, 0 / 0)))
end)

case('atTarget: radius, missing coords', function()
    local d = { x = 0, y = 0, z = 0, radius = 10 }
    assert(F.atTarget(d, { x = 6, y = 8, z = 0 })); assert(not F.atTarget(d, { x = 6, y = 8.1, z = 0 }))
    assert(not F.atTarget(d, nil)); assert(not F.atTarget(nil, { x = 0, y = 0 })); assert(not F.atTarget(d, { x = 0 / 0, y = 0 }))
end)

-- ---------------------------------------------------------------- onEvent mapping

case('eventVerdict: delivered -> complete, failed -> fail, for the matching quest only', function()
    local st = { quest_id = 'job:freight:k', progress = { job = { key = 'k' } } }
    T.eq('complete', F.eventVerdict(F.EVENT_DELIVERED, { key = 'k', citizenid = 'CID1' }, st))
    T.eq('fail', F.eventVerdict(F.EVENT_FAILED, { key = 'k' }, st))
    T.eq(nil, F.eventVerdict(F.EVENT_DELIVERED, { key = 'other' }, st), 'another contract')
    T.eq(nil, F.eventVerdict(F.EVENT_DELIVERED, { key = 'k' }, {}), 'state without quest_id: nothing')
    T.eq(nil, F.eventVerdict(F.EVENT_DELIVERED, { key = 'k' }, { id = 'job:freight:k' }), 'state.id does not exist in fh_quests')
    T.eq(nil, F.eventVerdict(F.EVENT_DELIVERED, { key = 'k' }, nil))
    T.eq(nil, F.eventVerdict('fh:hunting:pelt_sold', { key = 'k' }, st))
    T.eq(nil, F.eventVerdict(F.EVENT_DELIVERED, nil, st)); T.eq(nil, F.eventVerdict(F.EVENT_DELIVERED, { key = 5 }, st))
end)

-- ---------------------------------------------------------------- soft-dep registration

local function stubQuests(ret)
    local q = { calls = {} }
    function q:registerJobType(name, hooks) self.calls[#self.calls + 1] = { name = name, hooks = hooks } return table.unpack(ret or { true }) end
    return q
end
local hooks = { offers = function() end, accept = function() end, onEvent = function() end, abandon = function() end, extra = 1 }

case('register: skipped (no call) while fh_quests is not started', function()
    local q = stubQuests()
    local ok, err = F.register(function() return 'stopped' end, q, hooks)
    assert(ok == false and err == 'quests_not_started'); T.eq(0, #q.calls)
    ok, err = F.register(function() return 'missing' end, q, hooks); assert(not ok); T.eq(0, #q.calls)
end)

case('register: started -> registerJobType(freight, hooks + events), only the four hooks forwarded', function()
    local q = stubQuests()
    local asked
    local ok = F.register(function(n) asked = n return 'started' end, q, hooks)
    assert(ok); T.eq('fh_quests', asked); T.eq(1, #q.calls)
    local call = q.calls[1]
    T.eq('freight', call.name)
    T.eq(hooks.offers, call.hooks.offers); T.eq(hooks.accept, call.hooks.accept)
    T.eq(hooks.onEvent, call.hooks.onEvent); T.eq(hooks.abandon, call.hooks.abandon); T.eq(nil, call.hooks.extra)
    T.same({ 'fh:trade:contract_delivered', 'fh:trade:contract_failed' }, call.hooks.events)
end)

case('register: refusal and thrown errors come back as err, never throw', function()
    local ok, err = F.register(function() return 'started' end, stubQuests({ false, 'fh_bad_job' }), hooks)
    assert(ok == false and err == 'fh_bad_job')
    local boom = { registerJobType = function() error('export missing') end }
    ok, err = F.register(function() return 'started' end, boom, hooks); assert(ok == false and err:find('export missing'))
    ok, err = F.register(function() return 'started' end, nil, hooks); assert(ok == false and err == 'no_exports')
end)


-- ---------------------------------------------------------------- restart / presence (H5)

case('evaluate: offline player -> only the deadline applies, loss counter restarts', function()
    local c = contract({ miss = 2 })
    local v, m, seen = F.evaluate(c, { online = false, wagon = nil }, 1010, 3)
    T.eq(nil, v); T.eq(0, m); T.eq(false, seen)
    T.eq('timeout', (F.evaluate(c, { online = false }, 1100, 3)))
end)

case('evaluate: wagon not seen since restart/login is not lost; seen wagon is graced then lost', function()
    local c = contract({ seen = false })
    for _ = 1, 10 do
        local v, m, seen = F.evaluate(c, { online = true, wagon = nil }, 1010, 3)
        T.eq(nil, v); T.eq(0, m); T.eq(false, seen)
    end
    local v, m, seen = F.evaluate(c, { online = true, wagon = wagon, cargoCount = 5, atTarget = false }, 1010, 3)
    T.eq(nil, v); T.eq(true, seen); c.seen = seen
    local miss = 0
    for i = 1, 3 do
        v, m = F.evaluate(c, { online = true, wagon = nil }, 1010 + i, 3); c.miss = m; miss = i
    end
    T.eq('wagon_lost', v)
end)

case('evaluate: facts.online missing is treated as offline (fail closed)', function()
    T.eq(nil, (F.evaluate(contract(), { wagon = wagon, cargoCount = 5, atTarget = true }, 1010, 3)))
end)

-- ---------------------------------------------------------------- vector3 (H4), state keys, cooldown

case('atTarget: accepts vector3-like values read through fields (non-table userdata stand-in)', function()
    local v3 = setmetatable({}, { __index = function(_, k) return ({ x = 3, y = 4, z = 0 })[k] end })
    assert(F.atTarget({ x = 0, y = 0, z = 0, radius = 5 }, v3))
    assert(not F.atTarget({ x = 0, y = 0, z = 0, radius = 4.9 }, v3))
    assert(F.atTarget(v3, { x = 3, y = 4, z = 0 }))
    local bad = setmetatable({}, { __index = function() error('boom') end })
    assert(not F.atTarget({ x = 0, y = 0 }, bad)); assert(not F.atTarget(bad, { x = 0, y = 0 }))
    assert(not F.atTarget({ x = 0, y = 0 }, 'str')); assert(F.atTarget({ x = 0, y = 0 }, { x = 1, y = 1 }), 'z optional, default radius 30')
end)

case('keyOfState: progress.job.key first, quest_id fallback, never state.id', function()
    T.eq('k', F.keyOfState({ quest_id = 'job:freight:zzz', progress = { job = { key = 'k' } } }))
    T.eq('k2', F.keyOfState({ quest_id = 'job:freight:k2' }))
    T.eq(nil, F.keyOfState({ id = 'job:freight:k' })); T.eq(nil, F.keyOfState(nil)); T.eq(nil, F.keyOfState({ quest_id = 'job:hunt:k' }))
end)

case('generate: offers carry an explicit cooldown_min (config, default 30); only money + rep rewards', function()
    local o = F.generate(cfgNew(), 'heartlands', { dunes = { { item = 'trade_salt', level = 0.5, price = 10 } } })[1]
    T.eq(30, o.cooldown_min); T.eq(nil, o.rewards.items)
    o = F.generate(cfgNew({ cooldownMin = 0 }), 'heartlands', { dunes = { { item = 'trade_salt', level = 0.5, price = 10 } } })[1]
    T.eq(0, o.cooldown_min, '0 is allowed by fh_quests and kept')
end)

-- ---------------------------------------------------------------- T2 contracts (roads-02 R9)

local CARGO = dofile(here .. '../server/resources/[fh]/fh_cargo/shared/cargo_rules.lua')
local T2 = { unlock = 'contracts_t2', minWagonTier = 2, minDistance = 400, deadlineBase = 900, deadlinePerMeter = 1.0,
    premium = 1.5, repDelta = 4, maxOffers = 2, cooldownMin = 30, qty = { trade_salt = { min = 90, max = 190 } } }
local function t2With(over) local t = {} for k, v in pairs(T2) do t[k] = v end for k, v in pairs(over or {}) do t[k] = v end return t end
local function cfgT2(over)
    local c = cfgNew({ t2 = T2 })
    c.goods.trade_salt.weight, c.goods.trade_salt.stackable = 1500, true
    for k, v in pairs(over or {}) do c.freight[k] = v end
    return c
end
local SH = { dunes = { { item = 'trade_salt', level = 0.5, price = 10 }, { item = 'trade_cloth', level = 0.3, price = 20 } } }
local function t2of(offers) for _, o in ipairs(offers) do if o.tier == 2 then return o end end end
local function copy(o) local x = {} for k, v in pairs(o) do x[k] = v end return x end

case('T2 generate: T1 offers first (tier 1, unchanged keys), then T2 locked offers with the T2 template', function()
    local offers = F.generate(cfgT2(), 'heartlands', SH)
    T.eq(3, #offers) -- salt + cloth T1, salt T2 (cloth has no T2 qty template)
    T.eq(1, offers[1].tier); T.eq('heartlands.dunes.trade_salt', offers[1].key); T.eq(nil, offers[1].locked)
    T.eq(1, offers[2].tier)
    local o = offers[3]
    T.eq(2, o.tier); T.eq('heartlands.dunes.trade_salt.t2', o.key); assert(#F.questId(o.key) <= 64)
    T.eq(true, o.locked, 'T2 is always listed locked (board is shared; gate is per player at accept)')
    T.eq('contracts_t2', o.unlock); T.eq(2, o.min_wagon_tier)
    T.eq(140, o.qty)            -- 90 + ceil(0.5 * 100)
    T.eq(2100, o.reward)        -- floor(140 * 10 * 1.5)
    T.eq(1400, o.deadline_s)    -- 900 + 500 m * 1.0
    T.eq(30, o.cooldown_min)    -- max(cooldownMin 30, ceil(1400 / 60) = 24)
    T.same({ money = 2100, rep = { region_id = 'dunes', delta = 4 } }, o.rewards)
    assert(o.title:find('[T2]', 1, true), 'board title marks T2')
end)

case('T2 generate: deadline scales with distance; cooldown follows a long deadline; qty clamps to the template', function()
    local c = cfgT2()
    c.freight.destinations.dunes = { x = 3000, y = 0, z = 0, radius = 40 }
    local o = t2of(F.generate(c, 'heartlands', { dunes = { { item = 'trade_salt', level = 1, price = 10 } } }))
    T.eq(3900, o.deadline_s)    -- 900 + 3000
    T.eq(65, o.cooldown_min)    -- ceil(3900 / 60)
    T.eq(190, o.qty, 'level 1 = template max')
    o = t2of(F.generate(c, 'heartlands', { dunes = { { item = 'trade_salt', level = 0, price = 10 } } }))
    T.eq(90, o.qty, 'level 0 = template min')
end)

case('T2 generate: none on short routes, without t2 config, without a from-region destination; own cap', function()
    T.eq(nil, t2of(F.generate(cfgT2({ t2 = t2With({ minDistance = 600 }) }), 'heartlands', SH)), 'route 500 m < 600')
    local plain = F.generate(cfgNew(), 'heartlands', SH)
    T.eq(nil, t2of(plain), 'no t2 config'); T.eq(1, plain[1].tier)
    local c = cfgT2(); c.freight.destinations.heartlands = nil
    T.eq(nil, t2of(F.generate(c, 'heartlands', SH)), 'distance unknown')
    local list = F.generate(cfgT2({ maxOffers = 1 }), 'heartlands', SH)
    T.eq(2, #list, 'T1 capped at 1, T2 listed on its own cap'); T.eq(1, list[1].tier); T.eq(2, list[2].tier)
    T.eq(nil, t2of(F.generate(cfgT2({ t2 = t2With({ maxOffers = 0 }) }), 'heartlands', SH)), 'T2 cap 0 lists none')
end)

case('T2 validateOffer: accepts generated; refuses bad tier, key, qty, deadline, short route, missing t2 config', function()
    local c = cfgT2()
    local o = t2of(F.generate(c, 'heartlands', SH))
    assert(F.validateOffer(c, o, known))
    local function bad(field, v, code, cc)
        local x = copy(o); x[field] = v
        local ok, err = F.validateOffer(cc or c, x, known)
        assert(not ok and err == code, field .. '=' .. tostring(v) .. ' -> ' .. tostring(err))
    end
    bad('tier', 3, 'bad_tier'); bad('tier', '2', 'bad_tier'); bad('tier', 2, 'bad_tier', cfgNew())
    bad('key', 'heartlands.dunes.trade_salt', 'bad_key') -- T2 offer posing with a T1 key
    bad('qty', 89, 'bad_qty'); bad('qty', 191, 'bad_qty'); bad('item', 'trade_cloth', 'bad_key')
    bad('deadline_s', 1800, 'bad_deadline') -- must equal the distance formula
    bad('qty', 140, 'bad_route', cfgT2({ t2 = t2With({ minDistance = 600 }) }))
    -- an untiered (pre-T2) offer still validates as T1; a T1 offer relabelled tier 2 fails on its key
    local x = copy(F.generate(c, 'heartlands', SH)[1])
    x.tier = nil; assert(F.validateOffer(c, x, known), 'untiered offer = T1')
    x.tier = 2; T.eq('bad_key', select(2, F.validateOffer(c, x, known)))
end)

case('T2 wagonFits: fh_cargo tier rows; t1 cart too small, t2/t3 fit, weight and slots, unreadable tier', function()
    local c = cfgT2()
    local o = t2of(F.generate(c, 'heartlands', { dunes = { { item = 'trade_salt', level = 1, price = 10 } } })) -- 190 x 1.5 kg = 285 kg
    T.eq('fh_freight_wagon_too_small', select(2, F.wagonFits(c, o, CARGO.TIERS.t1)), 't1 cart')
    assert(F.wagonFits(c, o, CARGO.TIERS.t2), 't2 wagon (300 kg) fits 285 kg')
    assert(F.wagonFits(c, o, CARGO.TIERS.t3))
    local heavy = copy(o); heavy.qty = 201 -- 301.5 kg > t2 300 kg
    T.eq('fh_freight_wagon_too_small', select(2, F.wagonFits(c, heavy, CARGO.TIERS.t2)), 'over the t2 weight cap')
    c.goods.trade_salt.stackable = false -- one slot per unit: 190 > 60 slots even on a t3
    T.eq('fh_freight_wagon_too_small', select(2, F.wagonFits(c, o, CARGO.TIERS.t3)), 'slots')
    c.goods.trade_salt.stackable = true
    T.eq('fh_freight_wagon_unknown', select(2, F.wagonFits(c, o, nil)), 'T2 fails closed on an unreadable tier')
    T.eq('fh_freight_wagon_unknown', select(2, F.wagonFits(c, o, { tier = 't2' })))
    local t1 = F.generate(c, 'heartlands', SH)[1]
    assert(F.wagonFits(c, t1, nil), 'T1 with unreadable tier passes (canFit still applies)')
    assert(F.wagonFits(c, t1, CARGO.TIERS.t1), 'T1 on a cart')
end)

case('T2 checkUnlock: allowed / tier_too_low / not started / getState throws / canUnlock throws / truthy non-true', function()
    local started = function() return 'started' end
    assert(F.checkUnlock(started, function() return true end))
    T.eq('tier_too_low', select(2, F.checkUnlock(started, function() return false, 'tier_too_low' end)))
    local called = false
    T.eq('not_started', select(2, F.checkUnlock(function() return 'stopped' end, function() called = true return true end)))
    T.eq(false, called, 'canUnlock must not be called while fh_progression is not started')
    T.eq('not_started', select(2, F.checkUnlock(function() error('native gone') end, function() return true end)))
    T.eq('not_started', select(2, F.checkUnlock(nil, function() return true end)))
    T.eq('threw', select(2, F.checkUnlock(started, function() error('No such export canUnlock') end)))
    T.eq('denied', select(2, F.checkUnlock(started, function() return 'yes' end)), 'only true unlocks')
    T.eq('denied', select(2, F.checkUnlock(started, function() return nil end)))
    T.eq('contracts_t2', F.unlockFor(cfgT2(), 2)); T.eq(nil, F.unlockFor(cfgT2(), 1)); T.eq(1, F.minWagonTier(cfgT2(), 1))
end)

case('T2 real config: qty ranges need more than a t1 cart and fit an empty t2 wagon; pay stays under the reward cap', function()
    local saved = FhTradeConfig
    dofile(here .. '../server/resources/[fh]/fh_trade/config.lua')
    local c = FhTradeConfig
    FhTradeConfig = saved
    local t = assert(c.freight.t2, 'freight.t2 missing')
    T.eq('contracts_t2', t.unlock); T.eq(2, t.minWagonTier)
    for item, r in pairs(t.qty) do
        local g = assert(c.goods[item], item .. ' is not a trade good')
        assert(r.min * g.weight > CARGO.TIERS.t1.maxWeight, item .. ': T2 minimum fits a t1 cart')
        assert(r.max * g.weight <= CARGO.TIERS.t2.maxWeight, item .. ': T2 maximum does not fit an empty t2 wagon')
        -- worst-case unit price: base x regionFactor x (1 + gain x max shortage) x (1 + wobble)
        local rf = 1
        for _, f in pairs(c.regionFactor or {}) do if f[item] and f[item] > rf then rf = f[item] end end
        local maxUnit = g.base * rf * (1 + c.shortage.gain * c.shortage.max) * (1 + c.wobble.amplitude)
        assert(maxUnit * t.premium <= g.base * c.freight.rewardCapMultiple, item .. ': T2 reward can exceed the cap')
    end
    local dist = F.routeDistance(c, 'heartlands', 'scarlett_meadows')
    assert(dist and dist >= t.minDistance, 'heartlands <-> scarlett_meadows is not a T2 route')
end)

T.finish()

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
    minQty = 10, maxQty = 30, qtyPerLevel = 30, maxLoad = 300000, payMultiple = 3, payCapMultiple = 4,
    repDelta = 4, maxOffers = 2, cooldownMin = 30 }
local function t2With(over) local t = {} for k, v in pairs(T2) do t[k] = v end for k, v in pairs(over or {}) do t[k] = v end return t end
local function cfgT2(over)
    local c = cfgNew({ t2 = T2 })
    c.goods.trade_salt.weight, c.goods.trade_salt.stackable = 1500, true
    c.goods.trade_cloth.weight, c.goods.trade_cloth.stackable = 2500, true
    for k, v in pairs(over or {}) do c.freight[k] = v end
    return c
end
local SH = { dunes = { { item = 'trade_salt', level = 0.5, price = 10 }, { item = 'trade_cloth', level = 0.3, price = 20 } } }
local function t2of(offers) for _, o in ipairs(offers) do if o.tier == 2 then return o end end end
local function copy(o) local x = {} for k, v in pairs(o) do x[k] = v end return x end

case('T2 generate: T1 offers first (tier 1, unchanged keys), then T2 locked offers (pay = 3x the matching T1)', function()
    local offers = F.generate(cfgT2(), 'heartlands', SH)
    T.eq(4, #offers) -- salt + cloth T1, salt + cloth T2
    T.eq(1, offers[1].tier); T.eq('heartlands.dunes.trade_salt', offers[1].key); T.eq(nil, offers[1].locked)
    T.eq(1, offers[2].tier); T.eq('heartlands.dunes.trade_cloth', offers[2].key)
    local o = offers[3]
    T.eq(2, o.tier); T.eq('heartlands.dunes.trade_salt.t2', o.key); assert(#F.questId(o.key) <= 64)
    T.eq(true, o.locked, 'T2 is always listed locked (board is shared; gate is per player at accept)')
    T.eq('contracts_t2', o.unlock); T.eq(2, o.min_wagon_tier)
    T.eq(15, o.qty)             -- clamp(ceil(0.5 * 30), 10, 30)
    T.eq(375, o.reward)         -- floor(floor(10 * 10 * 1.25) * 3) = floor(125 * 3)
    T.eq(1400, o.deadline_s)    -- 900 + 500 m * 1.0
    T.eq(30, o.cooldown_min)    -- max(cooldownMin 30, ceil(1400 / 60) = 24)
    T.same({ money = 375, rep = { region_id = 'dunes', delta = 4 } }, o.rewards)
    assert(o.title:find('[T2]', 1, true), 'board title marks T2')
    -- pay follows goods value: cloth (base 20) pays more than salt (base 10) even at a lower shortage
    local o2 = offers[4]
    T.eq(2, o2.tier); T.eq('trade_cloth', o2.item); T.eq(10, o2.qty) -- ceil(0.3 * 30) = 9 -> clamped to 10
    T.eq(450, o2.reward)        -- floor(floor(6 * 20 * 1.25) * 3) = floor(150 * 3)
    assert(o2.reward > o.reward, 'cloth T2 pays more than salt T2 (goods value order)')
end)

case('T2 generate: deadline scales with distance; cooldown follows a long deadline; qty clamps to the slot range', function()
    local c = cfgT2()
    c.freight.destinations.dunes = { x = 3000, y = 0, z = 0, radius = 40 }
    local o = t2of(F.generate(c, 'heartlands', { dunes = { { item = 'trade_salt', level = 1, price = 10 } } }))
    T.eq(3900, o.deadline_s)    -- 900 + 3000
    T.eq(65, o.cooldown_min)    -- ceil(3900 / 60)
    T.eq(30, o.qty, 'level 1 = maxQty (t2 slots)')
    o = t2of(F.generate(c, 'heartlands', { dunes = { { item = 'trade_salt', level = 0, price = 10 } } }))
    T.eq(10, o.qty, 'level 0 = minQty')
end)

case('T2 generate: none on short routes, without t2 config, without a from-region destination; own cap', function()
    T.eq(nil, t2of(F.generate(cfgT2({ t2 = t2With({ minDistance = 600 }) }), 'heartlands', SH)), 'route 500 m < 600')
    local plain = F.generate(cfgNew(), 'heartlands', SH)
    T.eq(nil, t2of(plain), 'no t2 config'); T.eq(1, plain[1].tier)
    local c = cfgT2(); c.freight.destinations.heartlands = nil
    T.eq(nil, t2of(F.generate(c, 'heartlands', SH)), 'distance unknown')
    local list = F.generate(cfgT2({ maxOffers = 1 }), 'heartlands', SH)
    T.eq(3, #list, 'T1 capped at 1, T2 listed on its own cap'); T.eq(1, list[1].tier); T.eq(2, list[2].tier)
    T.eq(nil, t2of(F.generate(cfgT2({ t2 = t2With({ maxOffers = 0 }) }), 'heartlands', SH)), 'T2 cap 0 lists none')
end)

case('T2 validateOffer: accepts generated; refuses bad tier, key, level, qty, reward, deadline, short route', function()
    local c = cfgT2()
    local o = t2of(F.generate(c, 'heartlands', SH))
    assert(F.validateOffer(c, o, known))
    local function bad(field, v, code, cc)
        local x = copy(o); x[field] = v
        local ok, err = F.validateOffer(cc or c, x, known)
        assert(not ok and err == code, field .. '=' .. tostring(v) .. ' -> ' .. tostring(err))
    end
    bad('tier', 3, 'bad_tier'); bad('tier', '2', 'bad_tier'); bad('tier', false, 'bad_tier'); bad('tier', 2, 'bad_tier', cfgNew())
    bad('key', 'heartlands.dunes.trade_salt', 'bad_key') -- T2 offer posing with a T1 key
    bad('qty', 14, 'bad_qty'); bad('qty', 16, 'bad_qty'); bad('item', 'trade_cloth', 'bad_key')
    bad('level', 0, 'bad_level'); bad('level', 1.5, 'bad_level'); bad('level', nil, 'bad_level'); bad('level', '0.5', 'bad_level')
    bad('reward', 0, 'bad_reward'); bad('reward', 1601, 'bad_reward') -- cap = floor(4 * 10 * 10 * 4) = 1600
    bad('deadline_s', 1800, 'bad_deadline') -- must equal the distance formula
    local shortCfg = cfgT2({ t2 = t2With({ minDistance = 600 }) })
    local ok, err = F.validateOffer(shortCfg, o, known)
    assert(not ok and err == 'bad_route', 'short route -> ' .. tostring(err))
    -- an untiered (pre-T2) offer still validates as T1; a T1 offer relabelled tier 2 fails on its key
    local x = copy(F.generate(c, 'heartlands', SH)[1])
    x.tier = nil; assert(F.validateOffer(c, x, known), 'untiered offer = T1')
    x.tier = 2; T.eq('bad_key', select(2, F.validateOffer(c, x, known)))
end)

case('tierOf: absent tier = 1; false (and any other non-number) passes through so validateOffer rejects it', function()
    T.eq(1, F.tierOf({})); T.eq(1, F.tierOf({ tier = nil })); T.eq(1, F.tierOf(nil))
    T.eq(false, F.tierOf({ tier = false })); T.eq('2', F.tierOf({ tier = '2' })); T.eq(3, F.tierOf({ tier = 3 }))
    local c = cfgT2()
    local t1 = F.generate(c, 'heartlands', SH)[1]
    local x = copy(t1); x.tier = false
    T.eq('bad_tier', select(2, F.validateOffer(c, x, known)))
end)

case('T2 wagonFits: fh_cargo tier rows; t1 cart too small (tier), t2/t3 fit, weight and slots, unreadable tier', function()
    local c = cfgT2()
    local o = t2of(F.generate(c, 'heartlands', { dunes = { { item = 'trade_salt', level = 1, price = 10 } } })) -- 30 x 1.5 kg = 45 kg
    T.eq('fh_freight_wagon_too_small', select(2, F.wagonFits(c, o, CARGO.TIERS.t1)), 't1 cart refused by tier (1 < 2)')
    assert(F.wagonFits(c, o, CARGO.TIERS.t2), 't2 wagon fits 45 kg / 1 slot')
    assert(F.wagonFits(c, o, CARGO.TIERS.t3))
    local heavy = copy(o); heavy.qty = 201 -- 301.5 kg > t2 300 kg (tampered qty, still caught)
    T.eq('fh_freight_wagon_too_small', select(2, F.wagonFits(c, heavy, CARGO.TIERS.t2)), 'over the t2 weight cap')
    c.goods.trade_salt.stackable = false -- one slot per unit: a tampered qty over the slot count fails
    local many = copy(o); many.qty = 61 -- 61 > t3's 60 slots
    T.eq('fh_freight_wagon_too_small', select(2, F.wagonFits(c, many, CARGO.TIERS.t3)), 'slots')
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

local function loadRealTradeConfig()
    local Regions = dofile(here .. 'support/world_config.lua')
    local saved = FhTradeConfig
    dofile(here .. '../server/resources/[fh]/fh_trade/config.lua')
    local c = FhTradeConfig
    FhTradeConfig = saved
    return c, Regions
end

case('T2 real config: every T2 pay <= 4x matching T1 (about 3x at half); qty fits t2 slots/weight; t1 refused, t2 fits', function()
    local P = dofile(here .. '../server/resources/[fh]/fh_trade/shared/trade_prices.lua')
    local c = loadRealTradeConfig()
    local t = assert(c.freight.t2, 'freight.t2 missing')
    T.eq('contracts_t2', t.unlock); T.eq(2, t.minWagonTier)
    T.eq(true, t.maxQty <= CARGO.TIERS.t2.slots, 't2.maxQty must not exceed the t2 wagon slots')
    T.eq(true, t.maxLoad <= CARGO.TIERS.t2.maxWeight, 't2.maxLoad must not exceed the t2 wagon max weight')
    for item, g in pairs(c.goods) do
        local cap = math.floor(t.maxLoad / g.weight)
        assert(cap >= t.minQty, item .. ': too heavy to even carry t2.minQty')
    end
    local dist = F.routeDistance(c, 'heartlands', 'scarlett_meadows')
    assert(dist and dist >= t.minDistance, 'heartlands <-> scarlett_meadows is not a T2 route')

    -- Real quotes: setShortage across the shortage range, a few wobble phases, every good, both directions.
    local state, now, regions = P.newState(), 1700000000, { 'heartlands', 'scarlett_meadows' }
    c.freight.maxOffers, c.freight.t2.maxOffers = 99, 99 -- let every good's offer through
    local halfT1, halfT2 = {}, {}
    for _, level in ipairs({ 0.15, 0.25, 0.5, 0.75, 1.0 }) do
        for _, wob in ipairs({ 0, 900, 1800, 3600 }) do
            local tt = now + wob
            for item in pairs(c.goods) do for _, r in ipairs(regions) do P.setShortage(c, state, r, item, level, tt) end end
            local byRegion = {}
            for _, r in ipairs(regions) do byRegion[r] = P.shortages(c, state, r, tt) end
            for _, from in ipairs(regions) do
                local offers = F.generate(c, from, byRegion)
                for _, o in ipairs(offers) do
                    if o.tier == 2 then
                        local t1
                        for _, x in ipairs(offers) do
                            if x.tier == 1 and x.item == o.item and x.to_region == o.to_region then t1 = x end
                        end
                        assert(t1, ('%s: no matching T1 offer'):format(o.item))
                        assert(o.reward <= 4 * t1.reward, ('%s lvl %s: T2 %d > 4x T1 %d'):format(o.item, level, o.reward, t1.reward))
                        if level == 0.5 and wob == 0 then halfT1[o.item], halfT2[o.item] = t1.reward, o.reward end
                    end
                end
            end
        end
    end
    for item in pairs(c.goods) do
        local t1, t2 = halfT1[item], halfT2[item]
        assert(t1 and t2, item .. ': no half-shortage offers')
        local ratio = t2 / t1
        assert(ratio >= 2.9 and ratio <= 3.1, ('%s: T2/T1 at half shortage = %.3f, want ~3.0'):format(item, ratio))
    end

    -- A real T2 offer is refused on a t1 cart (tier gate) and accepted on a t2 wagon (45..300 kg always fits).
    local one
    for _, o in ipairs(F.generate(c, 'heartlands', { heartlands = P.shortages(c, state, 'heartlands', now), scarlett_meadows = P.shortages(c, state, 'scarlett_meadows', now) })) do
        if o.tier == 2 then one = o break end
    end
    assert(one, 'no real T2 offer to fit-check')
    T.eq('fh_freight_wagon_too_small', select(2, F.wagonFits(c, one, CARGO.TIERS.t1)), 't1 cart refused')
    assert(F.wagonFits(c, one, CARGO.TIERS.t2), 't2 wagon accepted')
end)

-- ---------------------------------------------------------------- R12: destinations from FhRegions + posts

local function postCfg(over)
    local c = {
        goods = {
            trade_salt  = { base = 10, label = 'Salt',  weight = 1500, stackable = true },
            trade_cloth = { base = 20, label = 'Cloth', weight = 2500, stackable = true },
        },
        posts = {
            { id = 'a_post',  region = 'reg_a', x = 0,    y = 0, z = 10, radius = 6 },
            { id = 'b_post',  region = 'reg_b', x = 800,  y = 0, z = 10, radius = 6 },
            { id = 'c_post',  region = 'reg_c', x = 2000, y = 0, z = 10, radius = 6 },
            { id = 'c_post2', region = 'reg_c', x = 2500, y = 0, z = 10, radius = 6 },
            { id = 'd_post',  region = 'reg_d', x = 4000, y = 0, z = 10, radius = 6 },
        },
        freight = {
            minQty = 1, maxQty = 20, qtyPerLevel = 20, premium = 1.25, repDelta = 2, deadlineSeconds = 1800,
            maxOffers = 3, rewardCapMultiple = 4, cooldownMin = 30, destinationRadius = 40, minDistance = 0,
            t2 = t2With({ minDistance = 1500 }),
            overrides = {}, exclude = {},
        },
    }
    for k, v in pairs(over or {}) do c.freight[k] = v end
    return c
end

case('R12 pairs generated: posts resolve to destinations, only post regions get offers, board caps hold', function()
    local c = postCfg({ maxOffers = 20, t2 = t2With({ minDistance = 1500, maxOffers = 20 }) })
    local sh = {
        reg_a = { { item = 'trade_salt', level = 0.5, price = 10 } },
        reg_b = { { item = 'trade_salt', level = 0.6, price = 10 } },
        reg_c = { { item = 'trade_salt', level = 0.7, price = 10 } },
        reg_d = { { item = 'trade_salt', level = 0.8, price = 10 } },
        no_post_region = { { item = 'trade_salt', level = 1.0, price = 10 } },
    }
    local offers = F.generate(c, 'reg_a', sh)
    local t1To, t2To = {}, {}
    for _, o in ipairs(offers) do
        if o.tier == 1 then t1To[o.to_region] = true else t2To[o.to_region] = true end
        assert(o.to_region ~= 'no_post_region', 'region without a post must not get offers')
    end
    T.eq(true, t1To.reg_b); T.eq(true, t1To.reg_c); T.eq(true, t1To.reg_d)
    T.eq(nil, t2To.reg_b, 'reg_a -> reg_b is 800 m < T2 minDistance 1500')
    T.eq(true, t2To.reg_c, 'reg_a -> reg_c is 2000 m >= 1500')
    T.eq(true, t2To.reg_d, 'reg_a -> reg_d is 4000 m >= 1500')
    T.eq(0, #F.generate(c, 'no_post_region', sh), 'origin without a post produces no offers')

    -- First post in list wins by default; overrides can tweak radius, coords, or select another post.
    T.eq(2000, F.destinationFor(c, 'reg_c').x)
    c.freight.overrides = {
        reg_b = { radius = 55 },
        reg_c = { post = 'c_post2' },
        no_post_region = { x = 5000, y = 0, z = 0, radius = 40 }, -- no post -> ignored
    }
    local dests = F.resolveDestinations(c)
    T.eq(800, dests.reg_b.x); T.eq(55, dests.reg_b.radius)
    T.eq(2500, dests.reg_c.x); T.eq('c_post2', dests.reg_c.post)
    T.eq(nil, dests.no_post_region, 'override must not invent a destination for a region with 0 posts')

    -- Default board caps keep offers bounded even with many regions and shortages.
    local capped = postCfg()
    local list = F.generate(capped, 'reg_a', sh)
    local n1, n2 = 0, 0
    for _, o in ipairs(list) do if o.tier == 1 then n1 = n1 + 1 else n2 = n2 + 1 end end
    T.eq(3, n1, 'T1 capped at maxOffers'); T.eq(2, n2, 'T2 capped at t2.maxOffers')
end)

case('R12 exclusion: array and map forms exclude region from destinations, offers, and validateOffer', function()
    local sh = {
        reg_a = { { item = 'trade_salt', level = 0.5, price = 10 } },
        reg_b = { { item = 'trade_salt', level = 0.6, price = 10 } },
        reg_c = { { item = 'trade_salt', level = 0.7, price = 10 } },
    }
    for _, ex in ipairs({ { 'reg_c' }, { reg_c = true } }) do
        local c = postCfg({ exclude = ex, overrides = { reg_c = { x = 2000, y = 0, z = 10, radius = 40 } } })
        T.eq(nil, F.destinationFor(c, 'reg_c'), 'excluded region has no destination even with override')
        T.eq(0, #F.generate(c, 'reg_c', sh), 'excluded origin generates 0 offers')
        for _, o in ipairs(F.generate(c, 'reg_a', sh)) do
            assert(o.to_region ~= 'reg_c', 'excluded region must not appear as destination')
        end
        -- Offer generated before exclusion is rejected by validateOffer once excluded.
        local rawOffer = F.generate(postCfg(), 'reg_a', sh)[1]
        assert(rawOffer.to_region == 'reg_c')
        T.eq('no_destination', select(2, F.validateOffer(c, rawOffer)))
        local fromExcluded = F.generate(postCfg(), 'reg_c', sh)[1]
        T.eq('no_destination', select(2, F.validateOffer(c, fromExcluded)))
    end
end)

case('R12 distance filter: T1 and T2 each filter by their own minDistance in generate and validateOffer', function()
    local c = postCfg({ minDistance = 1000, t2 = t2With({ minDistance = 2500 }) })
    local sh = {
        reg_b = { { item = 'trade_salt', level = 0.5, price = 10 } }, -- 800 m from reg_a (< T1 1000)
        reg_c = { { item = 'trade_salt', level = 0.5, price = 10 } }, -- 2000 m from reg_a (>= T1 1000, < T2 2500)
        reg_d = { { item = 'trade_salt', level = 0.5, price = 10 } }, -- 4000 m from reg_a (>= T2 2500)
    }
    local offers = F.generate(c, 'reg_a', sh)
    local seen = {}
    for _, o in ipairs(offers) do seen[o.to_region .. ':t' .. o.tier] = o end
    T.eq(nil, seen['reg_b:t1'], '800 m < T1 minDistance 1000')
    T.eq(nil, seen['reg_b:t2'])
    assert(seen['reg_c:t1'], '2000 m >= T1 minDistance 1000')
    T.eq(nil, seen['reg_c:t2'], '2000 m < T2 minDistance 2500')
    assert(seen['reg_d:t1'] and seen['reg_d:t2'], '4000 m >= both')
    assert(F.validateOffer(c, seen['reg_c:t1']))
    -- A short T1 offer built under minDistance=0 is rejected when minDistance=1000.
    local shortT1 = F.generate(postCfg({ minDistance = 0 }), 'reg_a', { reg_b = sh.reg_b })[1]
    T.eq('bad_route', select(2, F.validateOffer(c, shortT1)))
end)

case('R12 missing coords skipped (no throw), fallback to second post in same region, regions table fallback', function()
    local c = postCfg()
    c.posts = {
        { id = 'a_post', region = 'reg_a', x = 0, y = 0, z = 10 },
        { id = 'broken_only', region = 'reg_missing' },                         -- missing x, y
        { id = 'nan_post', region = 'reg_nan', x = 0 / 0, y = 100, z = 0 },     -- NaN x
        { id = 'bad_first', region = 'reg_fallback', x = nil, y = 500 },        -- missing x
        { id = 'good_second', region = 'reg_fallback', x = 2000, y = 0, z = 5 }, -- valid second post
        { id = 'unres_post' },                                                  -- resolved via regions arg
    }
    local fakeRegions = { posts = { unres_post = { id = 'unres_post', region = 'reg_r', x = 3000, y = 0, z = 5 } } }
    local dests = F.resolveDestinations(c, fakeRegions)
    T.eq(nil, dests.reg_missing); T.eq(nil, dests.reg_nan)
    T.eq(2000, dests.reg_fallback.x); T.eq('good_second', dests.reg_fallback.post)
    T.eq(3000, dests.reg_r.x)
    T.eq(nil, F.routeDistance(c, 'reg_a', 'reg_missing', fakeRegions))
    local sh = {
        reg_missing  = { { item = 'trade_salt', level = 0.9, price = 10 } },
        reg_nan      = { { item = 'trade_salt', level = 0.9, price = 10 } },
        reg_fallback = { { item = 'trade_salt', level = 0.5, price = 10 } },
        reg_r        = { { item = 'trade_salt', level = 0.5, price = 10 } },
    }
    T.eq(0, #F.generate(c, 'reg_missing', sh, fakeRegions), 'missing-coord origin skipped without throw')
    local offers = F.generate(c, 'reg_a', sh, fakeRegions)
    assert(#offers >= 2)
    for _, o in ipairs(offers) do
        assert(o.to_region ~= 'reg_missing' and o.to_region ~= 'reg_nan')
    end
end)

case('R12 real config: resolves destinations from FhRegions posts, >= 3 region pairs incl. bayou_nwa and great_plains', function()
    local P = dofile(here .. '../server/resources/[fh]/fh_trade/shared/trade_prices.lua')
    local c, Regions = loadRealTradeConfig()
    T.eq(nil, c.freight.destinations, 'hardcoded freight.destinations list is removed')
    local dests = F.resolveDestinations(c, Regions)
    local destCount = 0
    for r, d in pairs(dests) do
        destCount = destCount + 1
        local rp = assert(Regions.posts[d.post], r .. ': resolved post missing in FhRegions.posts')
        T.eq(rp.x, d.x); T.eq(rp.y, d.y); T.eq(rp.z, d.z)
    end
    assert(destCount >= 15, 'all 15 post regions resolve, got ' .. destCount)

    -- Enabled regions: heartlands, scarlett_meadows, bayou_nwa, great_plains.
    local enabled = {}
    for id in pairs(Regions.regions) do
        if Regions.isEnabled(id) then enabled[#enabled + 1] = id end
    end
    table.sort(enabled)
    local state, now = P.newState(), 1700000000
    for _, r in ipairs(enabled) do
        P.setShortage(c, state, r, 'trade_salt', 0.6, now)
    end
    local byRegion = {}
    for _, r in ipairs(enabled) do byRegion[r] = P.shortages(c, state, r, now) end

    -- Inspect all pairs with high caps first.
    local wide = copy(c); wide.freight = copy(c.freight); wide.freight.t2 = copy(c.freight.t2)
    wide.freight.maxOffers, wide.freight.t2.maxOffers = 99, 99
    local pairsSeen, t2Pairs = {}, {}
    local hasBayou, hasPlains = false, false
    for _, from in ipairs(enabled) do
        local offers = F.generate(wide, from, byRegion, Regions)
        for _, o in ipairs(offers) do
            assert(F.validateOffer(wide, o, Regions.isKnownRegion, Regions), 'invalid real offer ' .. o.key)
            assert(#F.questId(o.key) <= 64, 'quest id > 64: ' .. o.key)
            local a, b = o.from_region < o.to_region and o.from_region or o.to_region,
                         o.from_region < o.to_region and o.to_region or o.from_region
            local pair = a .. '<->' .. b
            pairsSeen[pair] = true
            if o.tier == 2 then t2Pairs[pair] = true end
            if o.from_region == 'bayou_nwa' or o.to_region == 'bayou_nwa' then hasBayou = true end
            if o.from_region == 'great_plains' or o.to_region == 'great_plains' then hasPlains = true end
        end
    end
    local nPairs = 0
    for _ in pairs(pairsSeen) do nPairs = nPairs + 1 end
    assert(nPairs >= 3, 'expected >= 3 region pairs, got ' .. nPairs)
    assert(hasBayou, 'expected offers involving bayou_nwa')
    assert(hasPlains, 'expected offers involving great_plains')
    -- scarlett_meadows <-> bayou_nwa (~1420 m) is T1 only; bayou_nwa <-> great_plains (~3566 m) has T2.
    T.eq(true, pairsSeen['bayou_nwa<->scarlett_meadows'])
    T.eq(nil, t2Pairs['bayou_nwa<->scarlett_meadows'], 'Rhodes <-> Saint Denis (~1420 m) is under T2 minDistance 1500')
    T.eq(true, t2Pairs['bayou_nwa<->great_plains'], 'Saint Denis <-> Blackwater (~3566 m) has T2')

    -- Real config board caps hold even when every post region has shortages on every good.
    local allByRegion = {}
    for r in pairs(dests) do
        for item in pairs(c.goods) do P.setShortage(c, state, r, item, 0.7, now) end
        allByRegion[r] = P.shortages(c, state, r, now)
    end
    local board = F.generate(c, 'heartlands', allByRegion, Regions)
    local n1, n2 = 0, 0
    for _, o in ipairs(board) do
        assert(#F.questId(o.key) <= 64, 'quest id > 64: ' .. o.key)
        if o.tier == 1 then n1 = n1 + 1 else n2 = n2 + 1 end
    end
    T.eq(c.freight.maxOffers, n1, 'T1 board cap holds with all 15 regions')
    T.eq(c.freight.t2.maxOffers, n2, 'T2 board cap holds with all 15 regions')
end)

T.finish()

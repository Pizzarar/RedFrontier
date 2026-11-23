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

T.finish()

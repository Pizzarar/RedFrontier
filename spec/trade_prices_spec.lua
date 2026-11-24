-- Run from repo root: `lua spec/trade_prices_spec.lua` (or via tools/run-specs.py).
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local case = T.it
local regions = require('regions')
local P = dofile(here .. '../server/resources/[fh]/fh_trade/shared/trade_prices.lua')
P.isKnownRegion = regions.isKnownRegion

local function cfgNew(over)
    local c = {
        seed = 7, maxSellPerTx = 100, minMultiplier = 0.1,
        wobble = { amplitude = 0.08, periodSeconds = 3600 },
        shortage = { gain = 1.0, max = 1.0, halfLifeSeconds = 7200, threshold = 0.15, reliefPerUnit = 0.02 },
        saturation = { capacityUnits = 40, maxDrop = 0.5, halfLifeSeconds = 3600 },
        goods = { trade_salt = { base = 10 }, trade_cloth = { base = 20 } },
        regionFactor = { heartlands = { trade_cloth = 1.5 } },
    }
    for k, v in pairs(over or {}) do c[k] = v end
    return c
end
local NOWOB = { amplitude = 0 }
local H, T0 = 'heartlands', 1000000

case('quote: unknown region / item / bad clock are refused', function()
    local c, s = cfgNew(), P.newState()
    local p, e = P.quote(c, s, 'atlantis', 'trade_salt', T0)
    assert(p == nil and e == 'unknown_region')
    p, e = P.quote(c, s, H, 'nope', T0)
    assert(p == nil and e == 'unknown_item')
    p, e = P.quote(c, s, H, 'trade_salt', 0 / 0)
    assert(p == nil and e == 'invalid_time')
end)

case('quote: baseline = base x regional factor when there is no wobble, shortage or sale', function()
    local c, s = cfgNew({ wobble = NOWOB }), P.newState()
    T.eq(10, (P.quote(c, s, H, 'trade_salt', T0)))
    T.eq(30, (P.quote(c, s, H, 'trade_cloth', T0)))
end)

case('wobble: deterministic, bounded, seed-dependent, drifts over time', function()
    local c = cfgNew()
    T.eq(P.wobble(c, H, 'trade_salt', T0), P.wobble(c, H, 'trade_salt', T0))
    local seen, differs = {}, false
    for i = 0, 200 do
        local w = P.wobble(c, H, 'trade_salt', T0 + i * 977)
        assert(math.abs(w) <= 0.08 + 1e-9, 'bounded')
        seen[#seen + 1] = w
        if w ~= seen[1] then differs = true end
    end
    assert(differs, 'moves over time')
    assert(P.wobble(cfgNew({ seed = 8 }), H, 'trade_salt', T0) ~= P.wobble(c, H, 'trade_salt', T0), 'seedable')
    -- continuous: a 1 s step moves it by far less than the amplitude
    assert(math.abs(P.wobble(c, H, 'trade_salt', T0 + 1) - P.wobble(c, H, 'trade_salt', T0)) < 0.001)
end)

case('shortage: raises the price, setShortage clamps, then decays back toward baseline', function()
    local c, s = cfgNew({ wobble = NOWOB }), P.newState()
    assert(P.setShortage(c, s, H, 'trade_salt', 0.5, T0))
    T.eq(15, (P.quote(c, s, H, 'trade_salt', T0)))
    assert(P.setShortage(c, s, H, 'trade_salt', 5, T0))
    T.eq(20, (P.quote(c, s, H, 'trade_salt', T0)), 'clamped to max 1.0')
    T.eq(15, (P.quote(c, s, H, 'trade_salt', T0 + 7200)), 'one half-life halves the premium')
    local late = P.quote(c, s, H, 'trade_salt', T0 + 7200 * 5)
    assert(late > 10 and late < 10.4, 'nearly back to baseline: ' .. late)
    T.eq(10, (P.quote(c, s, H, 'trade_salt', T0 + 7200 * 30)), 'fully back')
    local ok, err = P.setShortage(c, s, 'atlantis', 'trade_salt', 0.5, T0)
    assert(ok == false and err == 'unknown_region')
end)

case('quote never mutates state (same answer asked twice, earlier-than-entry clock is safe)', function()
    local c, s = cfgNew({ wobble = NOWOB }), P.newState()
    P.setShortage(c, s, H, 'trade_salt', 0.5, T0)
    local a = P.quote(c, s, H, 'trade_salt', T0 + 3600)
    T.eq(a, (P.quote(c, s, H, 'trade_salt', T0 + 3600)))
    T.eq(15, (P.quote(c, s, H, 'trade_salt', T0 - 100)), 'clock going back does not inflate it')
end)

case('sell: pays whole dollars, price falls per unit, saturation depresses the next sale', function()
    local c, s = cfgNew({ wobble = NOWOB }), P.newState()
    local first = P.sell(c, s, H, 'trade_salt', 10, T0)
    assert(first and first < 100 and first > 70, 'below 10 x $10 because each unit saturates: ' .. tostring(first))
    assert(first % 1 == 0)
    local q = P.quote(c, s, H, 'trade_salt', T0)
    assert(q < 10, 'quote now depressed: ' .. q)
    local second = P.sell(c, s, H, 'trade_salt', 10, T0)
    assert(second < first, 'second batch pays less')
end)

case('sell: saturation recovers over time; other regions/items unaffected', function()
    local c, s = cfgNew({ wobble = NOWOB }), P.newState()
    P.sell(c, s, H, 'trade_salt', 40, T0)
    local depressed = P.quote(c, s, H, 'trade_salt', T0)
    local later = P.quote(c, s, H, 'trade_salt', T0 + 3600 * 3)
    assert(depressed < 6.5 and later > depressed and later > 9, depressed .. ' -> ' .. later)
    T.eq(30, (P.quote(c, s, H, 'trade_cloth', T0)))
end)

case('sell: selling into a shortage eases it', function()
    local c, s = cfgNew({ wobble = NOWOB }), P.newState()
    P.setShortage(c, s, H, 'trade_salt', 0.6, T0)
    P.sell(c, s, H, 'trade_salt', 10, T0)
    local _, d = P.quote(c, s, H, 'trade_salt', T0)
    assert(math.abs(d.shortage - 0.4) < 1e-9, d.shortage)
end)

case('sell: validation (amount, item, region), preview matches commit and does not mutate', function()
    local c, s = cfgNew({ wobble = NOWOB }), P.newState()
    for _, a in ipairs({ 0, -1, 1.5, 101, '5' }) do
        local t, e = P.sell(c, s, H, 'trade_salt', a, T0)
        assert(t == nil and e == 'invalid_amount', tostring(a))
    end
    local t, e = P.sell(c, s, H, 'nope', 1, T0)
    assert(t == nil and e == 'unknown_item')
    t, e = P.sell(c, s, 'atlantis', 'trade_salt', 1, T0)
    assert(t == nil and e == 'unknown_region')
    T.eq(0, #P.toRows(s), 'failed sales leave no state')
    local prev = P.previewSell(c, s, H, 'trade_salt', 7, T0)
    T.eq(0, #P.toRows(s), 'preview leaves no state')
    T.eq(prev, (P.sell(c, s, H, 'trade_salt', 7, T0)))
end)

case('sell: a worthless sale is refused without touching state', function()
    local c, s = cfgNew({ wobble = NOWOB, goods = { trade_salt = { base = 0.5 } } }), P.newState()
    local t, e = P.sell(c, s, H, 'trade_salt', 1, T0)
    assert(t == nil and e == 'worthless')
    T.eq(0, #P.toRows(s))
end)

case('shortages: lists items over the threshold worst-first, hides decayed ones', function()
    local c, s = cfgNew({ wobble = NOWOB }), P.newState()
    P.setShortage(c, s, H, 'trade_salt', 0.3, T0)
    P.setShortage(c, s, H, 'trade_cloth', 0.9, T0)
    local l = P.shortages(c, s, H, T0)
    T.eq(2, #l)
    T.eq('trade_cloth', l[1].item)
    T.eq('trade_salt', l[2].item)
    assert(math.abs(l[2].multiplier - 1.3) < 1e-9 and l[2].price == 13)
    T.eq(0, #P.shortages(c, s, H, T0 + 7200 * 10), 'decayed below threshold')
    T.eq(0, #P.shortages(c, s, 'atlantis', T0))
end)

-- idea-762: initialShortages seed only regions/items with no persisted row (no state entry right after loadRow).
local SEEDS = { { region = H, item = 'trade_salt', level = 0.5 }, { region = H, item = 'trade_cloth', level = 0.6 } }

case('seedShortages: a fresh state seeds every entry and reports it', function()
    local c, s = cfgNew({ initialShortages = SEEDS }), P.newState()
    local seeded = P.seedShortages(c, s, T0)
    assert(#seeded == 2, 'seeded ' .. #seeded)
    T.same({ region = H, item = 'trade_salt' }, seeded[1])
    assert(select(2, P.quote(c, s, H, 'trade_salt', T0)).shortage == 0.5, 'salt not seeded')
    assert(select(2, P.quote(c, s, H, 'trade_cloth', T0)).shortage == 0.6, 'cloth not seeded')
    assert(#P.seedShortages(c, s, T0 + 10) == 0, 'second call re-seeded (its entries now exist)')
end)

case('seedShortages: a persisted row with shortage 0 (cleared) is NOT re-seeded', function()
    local c, s = cfgNew({ initialShortages = SEEDS }), P.newState()
    assert(P.loadRow(c, s, { region_id = H, item = 'trade_salt', shortage = 0, saturation = 0, updated_at = T0 - 100 }))
    local seeded = P.seedShortages(c, s, T0)
    assert(#seeded == 1 and seeded[1].item == 'trade_cloth', 'expected only the row-less cloth to seed')
    assert(select(2, P.quote(c, s, H, 'trade_salt', T0)).shortage == 0, 'cleared shortage was re-seeded')
end)

case('seedShortages: a persisted row with shortage > 0 is left alone (level and saturation)', function()
    local c, s = cfgNew({ initialShortages = SEEDS }), P.newState()
    for _, it in ipairs({ 'trade_salt', 'trade_cloth' }) do
        assert(P.loadRow(c, s, { region_id = H, item = it, shortage = 0.2, saturation = 0.3, updated_at = T0 }))
    end
    assert(#P.seedShortages(c, s, T0) == 0, 'seeded over persisted rows')
    local d = select(2, P.quote(c, s, H, 'trade_salt', T0))
    assert(d.shortage == 0.2 and d.saturation == 0.3, 'persisted row changed')
end)

case('seedShortages: unknown goods/regions, bad levels and junk entries are skipped', function()
    local c = cfgNew({ initialShortages = {
        { region = 'atlantis', item = 'trade_salt', level = 0.5 }, { region = H, item = 'gone', level = 0.5 },
        { region = H, item = 'trade_salt', level = 'x' }, 'junk', { region = H, item = 'trade_cloth', level = 0.4 },
    } })
    local s = P.newState()
    local seeded = P.seedShortages(c, s, T0)
    assert(#seeded == 1 and seeded[1].item == 'trade_cloth', 'expected only the valid cloth entry')
    assert(s.entries[H .. '|trade_salt'] == nil, 'bad level created an entry')
    assert(#P.seedShortages(cfgNew(), P.newState(), T0) == 0, 'no initialShortages must seed nothing')
end)

case('persistence: toRows / loadRow round-trips and rejects bad rows', function()
    local c, s = cfgNew({ wobble = NOWOB }), P.newState()
    P.setShortage(c, s, H, 'trade_salt', 0.5, T0)
    P.sell(c, s, H, 'trade_cloth', 5, T0)
    local rows = P.toRows(s)
    T.eq(2, #rows)
    local s2 = P.newState()
    for _, r in ipairs(rows) do assert(P.loadRow(c, s2, r)) end
    T.same(rows, P.toRows(s2))
    T.eq(P.quote(c, s, H, 'trade_salt', T0 + 500), (P.quote(c, s2, H, 'trade_salt', T0 + 500)))
    assert(P.loadRow(c, s2, { region_id = 'atlantis', item = 'trade_salt', shortage = 0, saturation = 0, updated_at = 1 }) == false)
    assert(P.loadRow(c, s2, { region_id = H, item = 'gone', shortage = 0, saturation = 0, updated_at = 1 }) == false)
    assert(P.loadRow(c, s2, { region_id = H, item = 'trade_salt', shortage = 'x', saturation = 0, updated_at = 1 }) == false)
    assert(P.loadRow(c, s2, 'junk') == false)
end)

case('shipped config is consistent with fh_core regions', function()
    local env = setmetatable({}, { __index = _G })
    local chunk = assert(loadfile(here .. '../server/resources/[fh]/fh_trade/config.lua', 't', env))
    chunk()
    local c = env.FhTradeConfig
    for r, f in pairs(c.regionFactor) do
        assert(regions.isKnownRegion(r), r)
        for item in pairs(f) do assert(c.goods[item], item) end
    end
    for _, post in ipairs(c.posts) do assert(regions.isKnownRegion(post.region) and post.radius > 0) end
    local s = P.newState()
    for item in pairs(c.goods) do assert(P.quote(c, s, 'heartlands', item, T0) > 0) end
end)

T.finish()

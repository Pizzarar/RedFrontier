-- Stubbed-server spec (idea-792): loads fh_trade's real server/main.lua with a fake MySQL / exports and runs its
-- startup thread: registerGoods -> seedShortages(load()) -> ready -> Wait(saveMs) -> flush(). Covers the wiring of the
-- idea-762 seed fix: what gets seeded, what is marked dirty (= UPSERTed by the first flush) and that persisted rows are
-- never clobbered. The seed decision itself is specced purely in spec/trade_prices_spec.lua (P.seedShortages).
-- Not a substitute for a live boot: exports are captured in-process, MySQL is a fake, freight.lua is not loaded.
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local R = here .. '../server/resources/[fh]/'
local CLOCK = 2000000000

---Boot a fresh copy of server/main.lua. `rows` = the persisted fh_trade_prices rows, or 'fail' (the SELECT throws).
---Returns { upserts = { ['region|item'] = { shortage, saturation, updated_at } }, nUpserts, quote, cfg, selects }.
local function boot(rows)
    local B = { upserts = {}, nUpserts = 0, selects = 0, exported = {} }
    local MySQL = { query = { await = function(q, v)
        if q:find('^SELECT') then
            B.selects = B.selects + 1
            if rows == 'fail' then error("Table 'fh_trade_prices' doesn't exist") end
            return rows
        end
        assert(q:find('^INSERT INTO fh_trade_prices'), 'unexpected query: ' .. q)
        B.nUpserts = B.nUpserts + 1
        B.upserts[v[1] .. '|' .. v[2]] = { shortage = v[3], saturation = v[4], updated_at = v[5] }
        return { affectedRows = 1 }
    end } }
    local exportsT = setmetatable({
        fh_core = { registerItems = function() return true end },
    }, { __call = function(_, name, fn) B.exported[name] = fn end })
    local thread
    local env = setmetatable({
        exports = exportsT, MySQL = MySQL, GetCurrentResourceName = function() return 'fh_trade' end,
        os = setmetatable({ time = function() return CLOCK end }, { __index = os }),
        GetGameTimer = function() return 0 end, GetPlayerPed = function() return 0 end,
        CreateThread = function(fn) thread = fn end, Wait = function() coroutine.yield('wait') end,
        RegisterNetEvent = function() end, RegisterCommand = function() end, AddEventHandler = function() end,
        TriggerEvent = function() end, TriggerClientEvent = function() end, print = function() end,
    }, { __index = _G })
    env._G = env
    for _, p in ipairs({ R .. 'fh_core/shared/regions.lua', R .. 'fh_core/shared/place_resolver.lua', R .. 'fh_trade/config.lua',
        R .. 'fh_trade/shared/trade_prices.lua', R .. 'fh_trade/shared/supplies.lua', R .. 'fh_trade/shared/posts.lua',
        R .. 'fh_trade/server/main.lua' }) do
        local fh = assert(io.open(p, 'rb')); local src = fh:read('a'); fh:close()
        assert(load(src, '@' .. p, 't', env))()
    end
    assert(thread, 'main.lua did not start its thread')
    local co = coroutine.create(thread)
    local ok, why = coroutine.resume(co)              -- startup: registerGoods, load, seed, ready, first Wait
    assert(ok and why == 'wait', 'startup did not reach Wait: ' .. tostring(why))
    T.eq(1, B.selects, 'prices SELECTed once')
    T.eq(0, B.nUpserts, 'nothing written before the first flush')
    ok, why = coroutine.resume(co)                    -- one save tick: flush() writes exactly the dirty rows
    assert(ok and why == 'wait', 'flush tick failed: ' .. tostring(why))
    -- Strict: quote returns `price, detail` or `nil, 'unknown_region'|...`; only a real quote passes.
    B.quote = function(region, item)
        local price, detail = B.exported.quote(region, item)
        assert(type(price) == 'number' and type(detail) == 'table',
            ('%s|%s does not quote: %s, %s'):format(tostring(region), tostring(item), tostring(price), tostring(detail)))
        return detail
    end
    B.cfg = env.FhTradeConfig
    return B
end

local function seedKeys(cfg)
    local keys = {}
    for _, e in ipairs(cfg.initialShortages) do keys[#keys + 1] = { key = e.region .. '|' .. e.item, e = e } end
    return keys
end

T.describe('fh_trade startup seeding (stubbed server, idea-792)', function()
    T.it('fixture: config has >= 2 initialShortages, all on known goods/regions', function()
        local B = boot({})
        assert(#B.cfg.initialShortages >= 2, 'need at least 2 initialShortages for these cases')
        for _, k in ipairs(seedKeys(B.cfg)) do
            assert(type(B.quote(k.e.region, k.e.item).shortage) == 'number', k.key .. ' quote has no shortage')
        end
    end)

    T.it('load fails -> nothing seeded, nothing marked dirty, nothing written over the persisted rows', function()
        local B = boot('fail')
        T.eq(0, B.nUpserts, 'flush wrote rows after a failed load (would clobber persisted state)')
        for _, k in ipairs(seedKeys(B.cfg)) do
            T.eq(0, B.quote(k.e.region, k.e.item).shortage, k.key .. ' seeded in memory after a failed load')
        end
    end)

    T.it('fresh empty load -> every initialShortages key seeded and marked dirty (and only those)', function()
        local B = boot({})
        local keys = seedKeys(B.cfg)
        T.eq(#keys, B.nUpserts, 'one UPSERT per seed, nothing else dirty')
        for _, k in ipairs(keys) do
            local u = B.upserts[k.key]
            assert(u, k.key .. ' not marked dirty / not saved')
            T.eq(k.e.level, u.shortage, k.key .. ' saved shortage'); T.eq(0, u.saturation); T.eq(CLOCK, u.updated_at)
            T.eq(k.e.level, B.quote(k.e.region, k.e.item).shortage, k.key .. ' in-memory shortage')
        end
    end)

    T.it('rows already persisted (cleared to 0 and > 0) -> untouched; only never-persisted keys seeded + dirty', function()
        local probe = seedKeys(boot({}).cfg)
        local cleared, held, fresh = probe[1].e, probe[2].e, {}
        for i = 3, #probe do fresh[#fresh + 1] = probe[i].e end
        local rows = {
            { region_id = cleared.region, item = cleared.item, shortage = 0, saturation = 0, updated_at = CLOCK },
            { region_id = held.region, item = held.item, shortage = 0.2, saturation = 0.3, updated_at = CLOCK },
            -- a persisted row for a key that is not a seed must also stay untouched
            { region_id = 'heartlands', item = 'trade_cloth', shortage = 0.1, saturation = 0, updated_at = CLOCK },
        }
        local B = boot(rows)
        T.eq(#fresh, B.nUpserts, 'only never-persisted seed keys may be dirty')
        assert(not B.upserts[cleared.region .. '|' .. cleared.item], 'cleared row was re-seeded/rewritten')
        assert(not B.upserts[held.region .. '|' .. held.item], 'persisted row was rewritten')
        assert(not B.upserts['heartlands|trade_cloth'], 'unrelated persisted row was rewritten')
        T.eq(0, B.quote(cleared.region, cleared.item).shortage, 'cleared shortage came back')
        local h = B.quote(held.region, held.item)
        T.eq(0.2, h.shortage, 'persisted shortage changed'); T.eq(0.3, h.saturation, 'persisted saturation changed')
        T.eq(0.1, B.quote('heartlands', 'trade_cloth').shortage)
        for _, e in ipairs(fresh) do
            local u = B.upserts[e.region .. '|' .. e.item]
            assert(u and u.shortage == e.level, e.region .. '|' .. e.item .. ' not seeded + dirty')
        end
    end)

    T.it('only one seed key persisted -> the other is seeded + dirty, the persisted one is not', function()
        local probe = seedKeys(boot({}).cfg)
        local persisted, other = probe[1].e, probe[2].e
        local B = boot({ { region_id = persisted.region, item = persisted.item, shortage = 0, saturation = 0.4, updated_at = CLOCK } })
        T.eq(#probe - 1, B.nUpserts)
        assert(not B.upserts[persisted.region .. '|' .. persisted.item], 'persisted seed key rewritten')
        T.eq(0.4, B.quote(persisted.region, persisted.item).saturation)
        T.eq(other.level, B.upserts[other.region .. '|' .. other.item].shortage, 'row-less seed key not seeded')
    end)
end)

T.finish()

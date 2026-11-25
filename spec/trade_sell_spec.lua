-- fh_trade sell money path (idea-865): the payout goes through fh_economy:credit(citizenid) with the citizenid captured
-- BEFORE the goods are removed, so a drop / character switch after removal still pays the owning character, and a
-- failed credit is never silent (ALERT log + fh:trade:owed event). Loads the real server/main.lua with stubbed exports.
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local R = here .. '../server/resources/[fh]/'

---opts: credit(fn), removeItem(fn), player(fn(src)->citizenid|nil, called per lookup)
local function boot(opts)
    local B = { logs = {}, events = {}, credits = {}, removed = {}, handlers = {} }
    local MySQL = { query = { await = function(q) if q:find('^SELECT') then return {} end return { affectedRows = 1 } end } }
    local exportsT = setmetatable({
        fh_core = { registerItems = function() return true end,
            removeItem = function(_, ref, item, n) B.removed[#B.removed + 1] = { ref = ref, item = item, n = n }
                return opts.removeItem and opts.removeItem() or true end },
        fh_economy = { credit = function(_, cid, amount, why, region)
            B.credits[#B.credits + 1] = { cid = cid, amount = amount, why = why, region = region }
            return opts.credit(cid, amount) end,
            pay = function() error('sell must not use pay') end },
        ['rsg-core'] = { GetCoreObject = function() return { Functions = { GetPlayer = function(src)
            local cid = opts.player(src)
            return cid and { PlayerData = { citizenid = cid } } or nil end } } end },
    }, { __call = function() end })
    local post
    local thread
    local env = setmetatable({
        exports = exportsT, MySQL = MySQL, GetCurrentResourceName = function() return 'fh_trade' end,
        os = setmetatable({ time = function() return 2000000000 end }, { __index = os }),
        GetGameTimer = function() return 1000000 end, GetPlayerPed = function() return 1 end,
        GetEntityCoords = function() return post end,
        CreateThread = function(fn) thread = fn end, Wait = function() coroutine.yield('wait') end,
        RegisterNetEvent = function() end, RegisterCommand = function() end,
        AddEventHandler = function(n, fn) B.handlers[n] = fn end,
        TriggerEvent = function(n, p) B.events[#B.events + 1] = { n, p } end, TriggerClientEvent = function() end,
        print = function(s) B.logs[#B.logs + 1] = s end,
    }, { __index = _G })
    env._G = env
    for _, p in ipairs({ R .. 'fh_core/shared/regions.lua', R .. 'fh_core/shared/place_resolver.lua', R .. 'fh_trade/config.lua',
        R .. 'fh_trade/shared/trade_prices.lua', R .. 'fh_trade/shared/supplies.lua', R .. 'fh_trade/shared/posts.lua',
        R .. 'fh_trade/shared/screen.lua', R .. 'fh_trade/server/main.lua' }) do
        local fh = io.open(p, 'rb')
        if fh then local src = fh:read('a'); fh:close(); assert(load(src, '@' .. p, 't', env))() end
    end
    local co = coroutine.create(thread)
    assert(coroutine.resume(co))
    local p1 = env.FhTradeConfig.posts[1]
    assert(p1 and p1.x, 'no resolved post')
    post = { x = p1.x, y = p1.y, z = p1.z }
    local nextSrc = 100
    B.sell = function(src)
        B.lastSrc = src
        B.handlers['fh:trade:ui_sell']({ src = src, screen = 'tradepost', action = 'sell', payload = { item = 'trade_salt', amount = 3 } })
    end
    B.owed = function() for _, e in ipairs(B.events) do if e[1] == 'fh:trade:owed' then return e[2] end end end
    B.sold = function() for _, e in ipairs(B.events) do if e[1] == 'fh:trade:sold' then return e[2] end end end
    B.alert = function() for _, l in ipairs(B.logs) do if l:find('ALERT credit failed', 1, true) then return l end end end
    return B
end

T.describe('fh_trade sell pays by captured citizenid (idea-865)', function()
    T.it('credit ok: one credit to the seller, sold event, no alert', function()
        local B = boot({ player = function() return 'CID1' end, credit = function() return true, nil, 'paid' end })
        B.sell(7)
        T.eq(1, #B.removed); T.eq(1, #B.credits)
        T.eq('CID1', B.credits[1].cid)
        T.eq('trade_sell:trade_salt', B.credits[1].why)
        assert(B.credits[1].amount > 0)
        assert(B.sold() and B.sold().total == B.credits[1].amount, 'sold event with the credited total')
        T.eq(nil, B.alert()); T.eq(nil, B.owed())
    end)
    T.it('credit throws: owed event + ALERT log carry citizenid and amount', function()
        local B = boot({ player = function() return 'CID1' end, credit = function() error('db down') end })
        B.sell(7)
        T.eq(1, #B.removed)
        local o = B.owed(); assert(o, 'owed event fired')
        T.eq('CID1', o.citizenid); T.eq(B.credits[1].amount, o.owed)
        assert(B.alert() and B.alert():find('CID1', 1, true), 'ALERT names the character')
        T.eq(nil, B.sold())
    end)
    T.it('credit refused: also alerts and emits owed', function()
        local B = boot({ player = function() return 'CID1' end, credit = function() return false, 'bad_amount' end })
        B.sell(7)
        assert(B.owed() and B.alert())
        T.eq(nil, B.sold())
    end)
    T.it('player dropped after removal: credit still goes to the original citizenid', function()
        local lookups = 0
        local B
        B = boot({ player = function() lookups = lookups + 1; return lookups == 1 and 'CID1' or nil end,
            credit = function() return true, nil, 'pending' end })
        B.sell(7)
        T.eq('CID1', B.credits[1].cid)
        assert(B.sold(), 'queued credit counts as paid')
    end)
    T.it('character switched after removal: credit goes to the character that owned the goods', function()
        local lookups = 0
        local B = boot({ player = function() lookups = lookups + 1; return lookups == 1 and 'CID1' or 'CID2' end,
            credit = function() return true, nil, 'paid' end })
        B.sell(7)
        T.eq('CID1', B.credits[1].cid)
    end)
    T.it('no character loaded: refused before removal, nothing taken', function()
        local B = boot({ player = function() return nil end, credit = function() return true end })
        B.sell(7)
        T.eq(0, #B.removed); T.eq(0, #B.credits)
    end)
end)
T.finish()

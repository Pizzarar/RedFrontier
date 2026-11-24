-- Core M3: fh_inventory shops move money through fh_economy (charge on buy, pay on sell, credit as the offline-safe
-- fallback), in whole cents, one trade per player at a time. Loads the real server/shops.lua into a stubbed world:
-- a fake InvCore (player inventories), a fake rsg-core and a fake fh_economy whose charge / pay can yield the calling
-- coroutine the way the real ledger insert does, so a spec can send a second event while the first is suspended.
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local SHOPS = here .. '../server/resources/[fh]/fh_inventory/server/shops.lua'
local REGIONS = here .. '../server/resources/[fh]/fh_core/shared/regions.lua'

-- world state, reset per test by fresh()
local W

local Vec = {}
Vec.__index = Vec
local function vec(x, y, z) return setmetatable({ x = x, y = y, z = z }, Vec) end
Vec.__sub = function(a, b) return vec(a.x - b.x, a.y - b.y, a.z - b.z) end
Vec.__len = function(a) return math.sqrt(a.x * a.x + a.y * a.y + a.z * a.z) end

local shared = {
    bread = { name = 'bread', weight = 100 },
    pelt = { name = 'pelt', weight = 500 },
    lamp = { name = 'lamp', weight = 1000 },
}

local function deepClone(t)
    if type(t) ~= 'table' then return t end
    local o = {}
    for k, v in pairs(t) do o[k] = deepClone(v) end
    return o
end

local function cents(x) return math.floor(x * 100 + 0.5) end

local function invItems(src) return W.inv[src] end

local API = {}
function API.CanCarry(src, name, amount) return W.inv[src] ~= nil and not W.cantCarry end
function API.GetItemBySlot(src, slot) return W.inv[src] and W.inv[src][slot] or nil end
function API.AddItem(src, name, amount, info, slot, reason)
    W.adds[#W.adds + 1] = { src = src, name = name, amount = amount, slot = slot, reason = reason }
    local items = W.inv[src]
    if not items or W.failAdd then return false end
    if slot ~= nil then
        if items[slot] then return false end
    else
        slot = 1
        while items[slot] do slot = slot + 1 end
    end
    items[slot] = { name = name, amount = amount, info = info or {}, slot = slot }
    return true
end
function API.RemoveItem(src, name, amount, slot, reason)
    local items = W.inv[src]
    local it = items and items[slot]
    if not it or it.name ~= name or it.amount < amount then return false end
    it.amount = it.amount - amount
    if it.amount == 0 then items[slot] = nil end
    return true
end

local function count(src, name)
    local n = 0
    for _, it in pairs(W.inv[src] or {}) do if it.name == name then n = n + it.amount end end
    return n
end

-- fake fh_economy: same refusals the real one returns for these paths; whole cents enforced (sub-cent = refused)
local function wholeCents(a) return type(a) == 'number' and math.abs(a * 100 - cents(a)) < 1e-6 and cents(a) >= 1 end
local Econ = {}
function Econ.charge(_, src, amount, reason, region)
    W.calls[#W.calls + 1] = { fn = 'charge', src = src, amount = amount, reason = reason, region = region }
    if W.chargeThrows then error('fh_economy stopped') end
    if not wholeCents(amount) then return false, 'invalid_amount' end
    local P = W.players[src]
    if not P then return false, 'no_player' end
    if W.pauseCharge and coroutine.isyieldable() then coroutine.yield('charge') end
    local cid = P.PlayerData.citizenid
    if cents(W.cash[cid]) < cents(amount) then return false, 'fh_insufficient_funds' end
    W.cash[cid] = (cents(W.cash[cid]) - cents(amount)) / 100
    W.ledger[#W.ledger + 1] = { kind = 'charge', cid = cid, amount = amount, reason = reason, region = region }
    return true, nil, #W.ledger
end
function Econ.pay(_, src, amount, reason, region)
    W.calls[#W.calls + 1] = { fn = 'pay', src = src, amount = amount, reason = reason, region = region }
    if W.payThrows then error('fh_economy stopped') end
    if not wholeCents(amount) then return false, 'invalid_amount' end
    local P = W.players[src]
    if not P then return false, 'no_player' end
    if W.pausePay and coroutine.isyieldable() then coroutine.yield('pay') end
    if W.payFail then return false, W.payFail end
    local cid = P.PlayerData.citizenid
    W.cash[cid] = (cents(W.cash[cid]) + cents(amount)) / 100
    W.ledger[#W.ledger + 1] = { kind = 'pay', cid = cid, amount = amount, reason = reason, region = region }
    return true, nil, #W.ledger
end
function Econ.credit(_, cid, amount, reason, region)
    W.calls[#W.calls + 1] = { fn = 'credit', cid = cid, amount = amount, reason = reason, region = region }
    if type(amount) ~= 'number' or amount % 1 ~= 0 or amount < 1 then return false, 'invalid_amount' end
    W.ledger[#W.ledger + 1] = { kind = 'credit', cid = cid, amount = amount, reason = reason, region = region }
    return true, nil, 'pending'
end

local Core = { Shared = { Items = shared }, Functions = {} }
Core.Functions.GetPlayer = function(src) return W.players[src] end

local printed = {}
local env = setmetatable({
    exports = setmetatable({}, { __index = function(_, res)
        if res == 'fh_economy' then return Econ end
        if res == 'rsg-core' then return { GetCoreObject = function() return Core end } end
        error('unexpected export resource ' .. tostring(res))
    end, __call = function() end }),
    AddEventHandler = function() end, CreateThread = function() end,
    MySQL = { ready = function() end, prepare = function() end, query = { await = function() return {} end } },
    GetGameTimer = function() return W.now end,
    GetPlayerPed = function(src) return src end,
    GetEntityCoords = function(ped) return W.pos[ped] or vec(0, 0, 0) end,
    vector3 = vec,
    Config = { Debug = false, ShopDistance = 10.0, ShopRestockMinutes = 60 },
    print = function(s) printed[#printed + 1] = tostring(s) end,
    GetCurrentResourceName = function() return 'fh_inventory' end,
}, { __index = _G })
env._G = env
env.InvCore = {
    Inventories = {}, OpenInv = {},
    Notify = function(src, key) W.notes[#W.notes + 1] = key end,
    DeepClone = deepClone,
    BuildItem = function(name, amount, info, slot) return { name = name, amount = amount, info = deepClone(info or {}), slot = slot } end,
    Refresh = function() end, WaitForDatabase = function() return true end,
    API = API,
}
local function load_into(path)
    local fh = assert(io.open(path, 'rb')); local code = fh:read('a'); fh:close()
    assert(load(code, '@' .. path, 't', env))()
end
load_into(REGIONS)  -- the manifest loads @fh_core/shared/regions.lua before shops.lua: sets env.FhRegions
assert(type(env.FhRegions) == 'table', 'FhRegions loaded')
load_into(SHOPS)
local Shops = env.Shops

local VALENTINE = { x = -169.47, y = 629.38, z = 113.03 }

local clock = 100000
local function fresh()
    clock = clock + 10000 -- shops.lua keeps its per-player cooldown across tests: always start past it
    W = { now = clock, inv = {}, players = {}, cash = {}, pos = {}, notes = {}, adds = {}, calls = {}, ledger = {} }
    env.InvCore.Inventories, env.InvCore.OpenInv = {}, {}
    printed = {}
end

local function player(src, cash, items)
    local cid = 'CID' .. src
    W.players[src] = { PlayerData = { citizenid = cid, source = src } }
    W.cash[cid] = cash
    W.inv[src] = items or {}
    W.pos[src] = vec(VALENTINE.x + 1, VALENTINE.y, VALENTINE.z)
    return cid
end

local function shop(items, extra)
    local data = { name = 'general', label = 'General', coords = VALENTINE, items = items }
    for k, v in pairs(extra or {}) do data[k] = v end
    local s = Shops.CreateShop(data)
    return s
end

local function open(src, s) env.InvCore.OpenInv[src] = s.id end

-- run fn in a coroutine (as an FXServer event handler); returns the coroutine (suspended if fn yielded)
local function go(fn, ...)
    local co = coroutine.create(fn)
    local ok, err = coroutine.resume(co, ...)
    assert(ok, err)
    return co
end
local function resume(co) local ok, err = coroutine.resume(co); assert(ok, err); T.eq('dead', coroutine.status(co)) end
local function tick() W.now = W.now + 1000; clock = W.now end

local function callsOf(fn)
    local out = {}
    for _, c in ipairs(W.calls) do if c.fn == fn then out[#out + 1] = c end end
    return out
end

T.describe('fh_inventory shops through the fh_economy ledger (core M3)', function()
    T.it('buy ok: one charge for the whole-cent total, shop_buy:<shop> reason, region from the nearest town', function()
        fresh()
        local cid = player(1, 10)
        local s = shop({ { name = 'bread', price = 1.25, amount = 5 } })
        T.eq('heartlands', s.region)
        open(1, s)
        go(Shops.Buy, 1, s, 1, 2)
        local ch = callsOf('charge')
        T.eq(1, #ch)
        T.eq(2.5, ch[1].amount)
        T.eq('shop_buy:general', ch[1].reason)
        T.eq('heartlands', ch[1].region)
        T.eq(7.5, W.cash[cid])
        T.eq(2, count(1, 'bread'))
        T.eq(3, s.items[1].amount)
        T.eq(0, #callsOf('pay'))
    end)

    T.it('buy with too little money: charge refused, no item, stock untouched, no_money', function()
        fresh()
        local cid = player(1, 1)
        local s = shop({ { name = 'bread', price = 1.25, amount = 5 } })
        open(1, s)
        go(Shops.Buy, 1, s, 1, 2)
        T.eq(1, W.cash[cid])
        T.eq(0, count(1, 'bread'))
        T.eq(5, s.items[1].amount)
        T.eq(0, #W.ledger)
        T.eq('no_money', W.notes[#W.notes])
    end)

    T.it('buy where the item add fails after the charge: refunded through pay, stock restored', function()
        fresh()
        local cid = player(1, 10)
        local s = shop({ { name = 'bread', price = 1.25, amount = 5 } })
        open(1, s)
        W.failAdd = true
        go(Shops.Buy, 1, s, 1, 2, 4)
        T.eq(10, W.cash[cid])
        T.eq(0, count(1, 'bread'))
        T.eq(5, s.items[1].amount)
        T.eq(2, #W.ledger)
        T.eq('charge', W.ledger[1].kind)
        T.eq('pay', W.ledger[2].kind)
        T.eq(2.5, W.ledger[2].amount)
        T.eq('shop_buy_refund:general', W.ledger[2].reason)
        T.eq(2, #W.adds, 'tried the client slot, then any slot')
        T.eq('too_heavy', W.notes[#W.notes])
    end)

    T.it('buy where the add fails and the refund pay is refused: credited to the citizenid instead', function()
        fresh()
        local cid = player(1, 10)
        local s = shop({ { name = 'lamp', price = 3, amount = 5 } })
        open(1, s)
        W.failAdd, W.payFail = true, 'addmoney_refused'
        go(Shops.Buy, 1, s, 1, 2)
        T.eq(4, W.cash[cid])
        local cr = callsOf('credit')
        T.eq(1, #cr)
        T.eq(cid, cr[1].cid)
        T.eq(6, cr[1].amount)
        T.eq('shop_buy_refund:general', cr[1].reason)
        T.eq(5, s.items[1].amount)
    end)

    T.it('buy where charge throws: no item, stock restored, ALERT logged', function()
        fresh()
        player(1, 10)
        local s = shop({ { name = 'bread', price = 1, amount = 5 } })
        open(1, s)
        W.chargeThrows = true
        go(Shops.Buy, 1, s, 1, 1)
        T.eq(0, count(1, 'bread'))
        T.eq(5, s.items[1].amount)
        T.eq(0, #callsOf('pay') + #callsOf('credit'))
        assert(printed[#printed]:find('ALERT charge threw', 1, true), printed[#printed])
    end)

    T.it('sell ok: item removed first, then one pay of the quality-scaled whole-cent payout', function()
        fresh()
        local cid = player(1, 0, { [3] = { name = 'pelt', amount = 4, info = { quality = 50 }, slot = 3 } })
        local s = shop({ { name = 'pelt', buyPrice = 0.75, amount = 0, maxStock = 10 } })
        open(1, s)
        go(Shops.Sell, 1, s, 3, 3)
        local p = callsOf('pay')
        T.eq(1, #p)
        T.eq(1.13, p[1].amount) -- 75c * 3 * 50% = 112.5c -> 113c
        T.eq('shop_sell:general', p[1].reason)
        T.eq('heartlands', p[1].region)
        T.eq(1.13, W.cash[cid])
        T.eq(1, count(1, 'pelt'))
        T.eq(3, s.items[1].amount)
    end)

    T.it('sell where pay is refused: the item goes back to its slot, no money, stock unchanged', function()
        fresh()
        local cid = player(1, 0, { [3] = { name = 'pelt', amount = 4, info = { quality = 100 }, slot = 3 } })
        local s = shop({ { name = 'pelt', buyPrice = 2, amount = 0, maxStock = 10 } })
        open(1, s)
        W.payFail = 'addmoney_refused'
        go(Shops.Sell, 1, s, 3, 4)
        T.eq(0, W.cash[cid])
        T.eq(4, count(1, 'pelt'))
        T.eq(3, W.inv[1][3] and W.inv[1][3].slot)
        T.eq(100, W.inv[1][3].info.quality)
        T.eq(0, s.items[1].amount)
        T.eq(0, #callsOf('credit'))
        T.eq(0, #W.ledger)
    end)

    T.it('sell where pay says no_player (logging out): no item restore, payout credited to the citizenid', function()
        fresh()
        local cid = player(1, 0, { [3] = { name = 'pelt', amount = 2, info = {}, slot = 3 } })
        local s = shop({ { name = 'pelt', buyPrice = 2, amount = 0, maxStock = 10 } })
        open(1, s)
        W.payFail = 'no_player'
        go(Shops.Sell, 1, s, 3, 2)
        T.eq(0, count(1, 'pelt'))
        local cr = callsOf('credit')
        T.eq(1, #cr)
        T.eq(cid, cr[1].cid)
        T.eq(4, cr[1].amount)
        T.eq('shop_sell:general', cr[1].reason)
        T.eq(2, s.items[1].amount, 'the shop has the goods')
    end)

    T.it('sell where pay throws: item not handed back too (no dup), ALERT logged', function()
        fresh()
        player(1, 0, { [3] = { name = 'pelt', amount = 2, info = {}, slot = 3 } })
        local s = shop({ { name = 'pelt', buyPrice = 2 } })
        open(1, s)
        W.payThrows = true
        go(Shops.Sell, 1, s, 3, 2)
        T.eq(0, count(1, 'pelt'))
        T.eq(0, #callsOf('credit'))
        assert(printed[#printed]:find('ALERT pay threw', 1, true), printed[#printed])
    end)

    T.it('fractional config price: rounded to whole cents at load, totals in integer cents; bad prices refused', function()
        fresh()
        local cid = player(1, 10)
        local s = shop({
            { name = 'bread', price = 0.333, amount = 10 },
            { name = 'pelt', price = -1, buyPrice = 0 / 0 },
            { name = 'lamp', price = 0.004, buyPrice = 1e9 },
        })
        T.eq(0.33, s.items[1].price)
        T.eq(nil, s.items[2].price)
        T.eq(nil, s.items[2].buyPrice)
        T.eq(nil, s.items[3].price)
        T.eq(nil, s.items[3].buyPrice)
        open(1, s)
        go(Shops.Buy, 1, s, 1, 3)
        T.eq(0.99, callsOf('charge')[1].amount)
        T.eq(9.01, W.cash[cid])
        T.eq(3, count(1, 'bread'))
        tick()
        go(Shops.Buy, 1, s, 2, 1)
        T.eq(1, #callsOf('charge'), 'unpriced item never charged')
        T.eq('not_for_sale', W.notes[#W.notes])
    end)

    T.it('double submit buy: a second event while the first charge is in flight is ignored', function()
        fresh()
        local cid = player(1, 10)
        local s = shop({ { name = 'bread', price = 2, amount = 5 } })
        open(1, s)
        W.pauseCharge = true
        local co = go(Shops.Buy, 1, s, 1, 1)
        T.eq('suspended', coroutine.status(co))
        tick() -- past the 300 ms cooldown: only the lock stops the second one
        local co2 = go(Shops.Buy, 1, s, 1, 1)
        T.eq('dead', coroutine.status(co2))
        T.eq(1, #callsOf('charge'))
        resume(co)
        T.eq(8, W.cash[cid])
        T.eq(1, count(1, 'bread'))
        T.eq(4, s.items[1].amount)
        tick()
        W.pauseCharge = false
        go(Shops.Buy, 1, s, 1, 1) -- lock released afterwards
        T.eq(2, count(1, 'bread'))
    end)

    T.it('double submit sell: a second event while pay is in flight is ignored', function()
        fresh()
        local cid = player(1, 0, { [3] = { name = 'pelt', amount = 4, info = {}, slot = 3 } })
        local s = shop({ { name = 'pelt', buyPrice = 1 } })
        open(1, s)
        W.pausePay = true
        local co = go(Shops.Sell, 1, s, 3, 2)
        T.eq('suspended', coroutine.status(co))
        tick()
        go(Shops.Sell, 1, s, 3, 2)
        T.eq(1, #callsOf('pay'))
        T.eq(2, count(1, 'pelt'))
        resume(co)
        T.eq(2, W.cash[cid])
        T.eq(2, count(1, 'pelt'))
    end)

    T.it('two players racing for the last unit: stock is reserved before the charge yields', function()
        fresh()
        local a = player(1, 10)
        local b = player(2, 10)
        local s = shop({ { name = 'lamp', price = 5, amount = 1 } })
        open(1, s); open(2, s)
        W.pauseCharge = true
        local co = go(Shops.Buy, 1, s, 1, 1)
        go(Shops.Buy, 2, s, 1, 1)
        T.eq('out_of_stock', W.notes[#W.notes])
        resume(co)
        T.eq(5, W.cash[a]); T.eq(10, W.cash[b])
        T.eq(1, count(1, 'lamp')); T.eq(0, count(2, 'lamp'))
        T.eq(0, s.items[1].amount)
    end)

    T.it('a non-cash shop or one with no region never trades', function()
        fresh()
        player(1, 10, { [1] = { name = 'pelt', amount = 1, info = {}, slot = 1 } })
        local s = shop({ { name = 'bread', price = 1 }, { name = 'pelt', buyPrice = 1 } }, { currency = 'bloodmoney' })
        open(1, s)
        go(Shops.Buy, 1, s, 1, 1); tick()
        go(Shops.Sell, 1, s, 1, 1)
        T.eq(0, #W.calls)
        T.eq(1, count(1, 'pelt'))
        fresh()
        player(1, 10)
        local s2 = Shops.CreateShop({ name = 'nowhere', coords = { x = 0, y = 0, z = 0 }, region = nil,
            items = { { name = 'bread', price = 1 } } })
        T.eq('string', type(s2.region), 'coords alone still find the nearest town')
        local s3 = Shops.CreateShop({ name = 'ghost', items = { { name = 'bread', price = 1 } } })
        T.eq(nil, s3.region)
        assert(printed[#printed]:find('no region', 1, true), printed[#printed])
    end)
end)

T.finish()

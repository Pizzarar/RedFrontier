local RSGCore = exports['rsg-core']:GetCoreObject()
AddEventHandler('RSGCore:Server:UpdateObject', function() RSGCore = exports['rsg-core']:GetCoreObject() end) -- FH: keep items fresh

-- Shops are containers of type 'shop' stored in InvCore.Inventories as 'shop-<name>'.
-- Drag from shop -> player buys, drag player -> shop sells (if the item has a buyPrice).

Shops = {}
local StockCache = {}   -- [shop] = { [item] = stock }
local Cooldown = {}
local notify = InvCore.Notify

local function Debug(src, msg, ...)
    if Config.Debug then print(('[rsg-inventory:shops] %s: ' .. msg):format(src, ...)) end
end

local function OnCooldown(src)
    local now = GetGameTimer()
    if Cooldown[src] and now - Cooldown[src] < 300 then return true end
    Cooldown[src] = now
    return false
end

local function ShopId(name) return 'shop-' .. name end

local function Clone(t) return InvCore.DeepClone(t or {}) end

-- FH (core M3): shop money goes through fh_economy (charge on buy, pay on sell), which writes the fh_ledger row and
-- moves its configured account only (cash). Amounts are whole cents, rounded the way fh_economy and rsg-core's money
-- items round (math.floor(x * 100 + 0.5)); totals are worked out in integer cents, never as float dollars.
local MONEY_TYPE = 'cash'
local MAX_UNIT_CENTS = 10000000 -- $100,000 a unit (fh_economy's maxPay / maxCharge cap the total)

local function ToCents(x)
    if type(x) ~= 'number' or x ~= x or x == math.huge or x == -math.huge then return nil end
    return math.floor(x * 100 + 0.5)
end

local function FromCents(c) if c % 100 == 0 then return c // 100 end return c / 100 end

---A config price (price / buyPrice) as whole dollars-and-cents, or nil (not for sale / not bought) with a warning.
local function ConfigPrice(shop, item, field, v)
    if v == nil then return nil end
    local c = ToCents(v)
    if not c or c < 1 or c > MAX_UNIT_CENTS then
        print(('^3[fh_inventory:shops] shop %s item %s: %s %s is not a price between $0.01 and $%d; ignored^7')
            :format(shop, item, field, tostring(v), MAX_UNIT_CENTS // 100))
        return nil
    end
    local price = FromCents(c)
    if price ~= v then
        print(('^3[fh_inventory:shops] shop %s item %s: %s %s rounded to whole cents (%s)^7'):format(shop, item, field, tostring(v), price))
    end
    return price
end

---Ledger region for a shop: data.region when given, else the region of the nearest town to its coords
---(FhRegions, loaded from fh_core in the manifest). nil = fh_economy refuses (unknown_region) and the shop can't trade.
local function ShopRegion(region, coords)
    if type(region) == 'string' then return region end
    local R = FhRegions
    if not coords or type(R) ~= 'table' or type(R.regions) ~= 'table' then return nil end
    local best, bestD2
    for id, r in pairs(R.regions) do
        for _, t in ipairs(type(r) == 'table' and type(r.towns) == 'table' and r.towns or {}) do
            if type(t.x) == 'number' and type(t.y) == 'number' then
                local dx, dy = coords.x - t.x, coords.y - t.y
                local d2 = dx * dx + dy * dy
                if not bestD2 or d2 < bestD2 then best, bestD2 = id, d2 end
            end
        end
    end
    return best
end

local function SetupItems(name, list, persistent)
    local items, slot = {}, 1
    for _, it in pairs(list or {}) do
        local s = it.name and RSGCore.Shared.Items[it.name:lower()]
        if s then
            local amount = it.amount
            if persistent and amount and StockCache[name] and StockCache[name][s.name] then
                amount = StockCache[name][s.name]
            end
            local built = InvCore.BuildItem(s.name, amount or 1, it.info, slot)
            built.amount       = amount          -- nil = unlimited
            built.price        = ConfigPrice(name, s.name, 'price', it.price)
            built.buyPrice     = ConfigPrice(name, s.name, 'buyPrice', it.buyPrice)
            built.defaultstock = it.amount
            built.maxStock     = it.maxStock
            built.restock      = it.restock
            built.minQuality   = it.minQuality
            items[slot] = built
            slot = slot + 1
        end
    end
    return items, slot - 1
end

local function KnownRegion(id)
    local R = FhRegions
    return type(R) == 'table' and type(R.isKnownRegion) == 'function' and R.isKnownRegion(id) == true
end

---Only a cash shop in a known fh_core region can trade: fh_economy moves cash only and refuses any other region
---(unknown_region). Checked before any stock or inventory change, so a misconfigured shop never takes an item first.
local function Tradeable(shop) return shop.currency == MONEY_TYPE and KnownRegion(shop.region) end

local function Checked(shop)
    if shop.currency ~= MONEY_TYPE then
        print(('^3[fh_inventory:shops] shop %s: currency %s is not %s (fh_economy); it will not trade^7')
            :format(shop.name, tostring(shop.currency), MONEY_TYPE))
    end
    if not shop.region then
        print(('^3[fh_inventory:shops] shop %s: no region (give region = <fh_core region id> or coords); it will not trade^7')
            :format(shop.name))
    elseif not KnownRegion(shop.region) then
        print(('^3[fh_inventory:shops] shop %s: region %s is not a known fh_core region; it will not trade^7')
            :format(shop.name, tostring(shop.region)))
    end
end

---A client amount: nil -> default; otherwise a whole number (1, 2.0), else nil (refused). Never coerced.
local function ParseAmount(v, default)
    if v == nil then return default end
    return type(v) == 'number' and math.tointeger(v) or nil
end

local function Register(name, data)
    local id = ShopId(name)
    local items, count = SetupItems(name, data.items, data.persistentStock)
    local shop = InvCore.Inventories[id]
    if shop then
        shop.items, shop.slots = items, math.max(count, 1)
        if data.label then shop.label = data.label end
        if data.persistentStock ~= nil then shop.persistentStock = data.persistentStock end
        if data.currency then shop.currency = data.currency end
        if data.coords then shop.shopCoords = vector3(data.coords.x, data.coords.y, data.coords.z) end
        if data.region or data.coords then shop.region = ShopRegion(data.region, data.coords) or shop.region end
        Checked(shop)
        return shop
    end
    shop = {
        id = id, name = name, type = 'shop', label = data.label or name,
        slots = math.max(count, 1), maxWeight = 1e12, items = items,
        shopCoords = data.coords and vector3(data.coords.x, data.coords.y, data.coords.z) or nil,
        persistentStock = data.persistentStock, currency = data.currency or 'cash',
        region = ShopRegion(data.region, data.coords),
    }
    InvCore.Inventories[id] = shop
    Checked(shop)
    return shop
end

--- CreateShop({ name, label, items = {{ name, price, amount?, buyPrice?, ... }}, coords?, persistentStock? })
--- or CreateShop({ shopA = {...}, shopB = {...} })
function Shops.CreateShop(data)
    if type(data) ~= 'table' then return end
    if data.name then return Register(data.name, data) end
    for key, v in pairs(data) do
        if type(v) == 'table' and v.items then
            Register(type(key) == 'number' and v.name or key, v)
        end
    end
end

function Shops.OpenShop(src, name)
    local shop = name and InvCore.Inventories[ShopId(name)]
    if not shop then return false end
    -- FH: a shop with no coords is refused (was: open from anywhere)
    if not shop.shopCoords or #(GetEntityCoords(GetPlayerPed(src)) - shop.shopCoords) > Config.ShopDistance then return false end
    return InvCore.OpenFor(src, shop.id)
end

function Shops.DoesShopExist(name)
    return type(name) == 'string' and InvCore.Inventories[ShopId(name)] ~= nil
end

function Shops.RestockShop(name, percentage)
    local shop = InvCore.Inventories[ShopId(name)]
    if not shop then return false end
    local mult = (percentage or 100) / 100
    for _, it in pairs(shop.items) do
        if it.amount and it.defaultstock then
            it.amount = math.min(it.defaultstock, it.amount + math.floor(it.defaultstock * mult + 0.5))
        end
    end
    shop.stockDirty = true
    InvCore.Refresh(shop.id)
    return true
end

local function InRange(src, shop)
    if InvCore.OpenInv[src] ~= shop.id then return false end
    -- FH: no coords = out of range (was: always in range)
    return shop.shopCoords ~= nil and #(GetEntityCoords(GetPlayerPed(src)) - shop.shopCoords) <= Config.ShopDistance
end

local function Alert(fmt, ...)
    print(('^1[fh_inventory:shops] ALERT ' .. fmt .. '^7'):format(...))
end

-- FH (core M3): one shop trade per player at a time. charge / pay yield on fh_economy's ledger insert, so without
-- this a double-click could start a second buy or sell before the first one has settled.
local Busy = {}

local function Locked(src, fn, ...)
    if Busy[src] then return Debug(src, 'ignored: previous shop trade still running') end
    Busy[src] = true
    local ok, err = pcall(fn, src, ...)
    Busy[src] = nil
    if not ok then Alert('shop trade error for src %s: %s', tostring(src), tostring(err)) end
end

local function Reason(kind, shop) return (kind .. ':' .. tostring(shop.name)):sub(1, 128) end

local function Citizenid(src)
    local Player = RSGCore.Functions.GetPlayer(src)
    local cid = Player and Player.PlayerData and Player.PlayerData.citizenid
    return type(cid) == 'string' and cid ~= '' and cid or nil
end

---Run one fh_economy export call -> called, ok, err. called = false when the export itself threw: then it is unknown
---whether money moved, so callers never compensate on a throw (no dup); they log an ALERT for an admin instead.
local function Econ(call)
    local r = table.pack(pcall(call))
    if not r[1] then return false, nil, tostring(r[2]) end
    return true, r[2], r[3]
end
local function Charge(src, amount, reason, region)
    return Econ(function() return exports.fh_economy:charge(src, amount, reason, region) end)
end
local function Pay(src, amount, reason, region)
    return Econ(function() return exports.fh_economy:pay(src, amount, reason, region) end)
end
local function Credit(cid, amount, reason, region)
    return Econ(function() return exports.fh_economy:credit(cid, amount, reason, region) end)
end

---Give money back to a character after its money was taken (buy: item add failed) or its item was taken (sell:
---pay failed and the item can't go back). pay(src) while the same character is online and loaded, else
---credit(citizenid) (offline-safe, queues; whole cents since core M3). Returns true once the money is back or queued.
local function Compensate(src, cid, cents, reason, region, tryPay)
    local amount = FromCents(cents)
    if tryPay and Citizenid(src) == cid then
        local called, ok = Pay(src, amount, reason, region)
        if not called then return false, 'pay_threw' end
        if ok == true then return true end
    end
    local called, ok, err = Credit(cid, amount, reason, region)
    if not called then return false, 'credit_threw' end
    if ok == true then return true end
    return false, tostring(err)
end

local function Buy(src, shop, slot, amount, toSlot)
    if OnCooldown(src) then return Debug(src, 'buy ignored: cooldown') end
    if not InRange(src, shop) then
        Debug(src, 'buy denied: shop %s not open for player (open=%s)', shop.id, tostring(InvCore.OpenInv[src]))
        return notify(src, 'too_far')
    end

    local it = shop.items[slot]
    amount = ParseAmount(amount, 1)
    if not it or not amount or amount < 1 or amount > 1000 then
        return Debug(src, 'buy denied: slot %s item %s amount %s', tostring(slot), tostring(it and it.name), tostring(amount))
    end
    local unit = ToCents(it.price)
    if not unit or unit < 1 then return notify(src, 'not_for_sale') end
    if not Tradeable(shop) then return notify(src, 'not_for_sale') end -- cash + known region, before any change
    if it.unique then amount = 1 end
    if it.amount and amount > it.amount then return notify(src, 'out_of_stock') end
    if not InvCore.API.CanCarry(src, it.name, amount) then return notify(src, 'too_heavy') end
    local cid = Citizenid(src)
    if not cid then return end

    local cents = unit * amount
    -- Reserve the stock before charge yields, so two buyers can't both pay for the last units.
    if it.amount then it.amount = it.amount - amount shop.stockDirty = true end
    local function unreserve() if it.amount then it.amount = it.amount + amount shop.stockDirty = true end end

    local called, ok, err = Charge(src, FromCents(cents), Reason('shop_buy', shop), shop.region)
    if not called then
        -- fh_economy voids its own row when it fails; a throw here means the export never completed. No item.
        unreserve()
        Alert('charge threw for %s (src %s) buying %sx %s at %s for $%s: no item given (%s)', cid, src, amount, it.name, shop.name, FromCents(cents), err)
        return notify(src, 'not_for_sale')
    end
    if ok ~= true then
        unreserve()
        Debug(src, 'buy denied: charge %s', tostring(err))
        return notify(src, err == 'fh_insufficient_funds' and 'no_money' or 'not_for_sale')
    end

    -- Charged. No yield from here to the add, and the same character is loaded (charge checks it after its insert).
    local name, info = it.name, Clone(it.info)
    local added = InvCore.API.AddItem(src, name, amount, info, toSlot, 'shop-purchase ' .. shop.name)
    if not added and toSlot ~= nil then
        added = InvCore.API.AddItem(src, name, amount, Clone(it.info), nil, 'shop-purchase ' .. shop.name)
    end
    if added then return Debug(src, 'bought %sx %s for %s', amount, name, FromCents(cents)) end

    unreserve()
    local back, why = Compensate(src, cid, cents, Reason('shop_buy_refund', shop), shop.region, true)
    if not back then
        Alert('refund FAILED for %s (src %s): charged $%s for %sx %s at %s, item add failed, refund failed (%s): owed $%s',
            cid, src, FromCents(cents), amount, name, shop.name, why, FromCents(cents))
    end
    return notify(src, 'too_heavy')
end

local function Sell(src, shop, playerSlot, amount)
    if OnCooldown(src) or not InRange(src, shop) then return end
    local item = InvCore.API.GetItemBySlot(src, playerSlot)
    if not item then return end
    amount = ParseAmount(amount, item.amount)
    if not amount or amount < 1 or amount > item.amount then return end

    local entry
    for _, it in pairs(shop.items) do
        if it.name == item.name and it.buyPrice then entry = it break end
    end
    if not entry then return notify(src, 'shop_wont_buy') end
    if not Tradeable(shop) then return notify(src, 'shop_wont_buy') end -- cash + known region, before any change
    local quality = (item.info and tonumber(item.info.quality)) or 100
    if quality ~= quality then quality = 0 end
    quality = math.max(0, math.min(100, quality))
    if quality < (entry.minQuality or 1) then return notify(src, 'quality_too_low') end
    if entry.amount and entry.maxStock and entry.amount + amount > entry.maxStock then
        return notify(src, 'shop_full')
    end
    local unit = ToCents(entry.buyPrice)
    if not unit or unit < 1 then return notify(src, 'shop_wont_buy') end
    local cents = math.floor(unit * amount * quality / 100 + 0.5) -- whole cents, rounded once on the total
    if cents < 1 then return notify(src, 'shop_wont_buy') end
    local cid = Citizenid(src)
    if not cid then return end

    -- Take the item first (no yield between the checks above and this), then pay.
    local name, info = item.name, Clone(item.info)
    if not InvCore.API.RemoveItem(src, name, amount, playerSlot, 'shop-sell ' .. shop.name) then return end
    if entry.amount then entry.amount = entry.amount + amount shop.stockDirty = true end

    local called, ok, err = Pay(src, FromCents(cents), Reason('shop_sell', shop), shop.region)
    if called and ok == true then return Debug(src, 'sold %sx %s for %s', amount, name, FromCents(cents)) end
    if not called then
        -- Unknown whether the money moved: never hand the item back too (no dup). Admin settles from this line.
        return Alert('pay threw for %s (src %s) selling %sx %s at %s for $%s: item kept by shop, check fh_ledger (%s)',
            cid, src, amount, name, shop.name, FromCents(cents), err)
    end

    -- pay refused: no money moved. Give the item back to the same, still loaded character; if that character is
    -- gone, changed, or logging out (pay's no_player / player_changed), credit the payout instead.
    Debug(src, 'sell: pay refused (%s)', tostring(err))
    if err ~= 'no_player' and err ~= 'player_changed' and Citizenid(src) == cid then
        if InvCore.API.AddItem(src, name, amount, info, playerSlot, 'shop-sell-undo ' .. shop.name)
            or InvCore.API.AddItem(src, name, amount, Clone(info), nil, 'shop-sell-undo ' .. shop.name) then
            if entry.amount then entry.amount = entry.amount - amount shop.stockDirty = true end
            return notify(src, 'shop_wont_buy')
        end
    end
    local back, why = Compensate(src, cid, cents, Reason('shop_sell', shop), shop.region, false)
    if not back then
        Alert('sell FAILED for %s (src %s): took %sx %s at %s, pay refused (%s), item restore and credit failed (%s): owed $%s',
            cid, src, amount, name, shop.name, tostring(err), why, FromCents(cents))
    end
end

function Shops.Buy(src, shop, slot, amount, toSlot) return Locked(src, Buy, shop, slot, amount, toSlot) end
function Shops.Sell(src, shop, playerSlot, amount) return Locked(src, Sell, shop, playerSlot, amount) end

--------------------------------------------------------------------------------
-- Stock persistence + restock
--------------------------------------------------------------------------------
local function SaveStock()
    local rows = {}
    for _, inv in pairs(InvCore.Inventories) do
        if inv.type == 'shop' and inv.persistentStock and inv.stockDirty then
            inv.stockDirty = false
            for _, it in pairs(inv.items) do
                if it.amount then rows[#rows + 1] = { inv.name, it.name, it.amount } end
            end
        end
    end
    for _, r in ipairs(rows) do
        MySQL.prepare('REPLACE INTO shop_stock (shop_name, item_name, stock) VALUES (?, ?, ?)', r)
    end
end

MySQL.ready(function()
    if not InvCore.WaitForDatabase() then return end -- tables are created in server/main.lua
    for _, row in ipairs(MySQL.query.await('SELECT shop_name, item_name, stock FROM shop_stock') or {}) do
        StockCache[row.shop_name] = StockCache[row.shop_name] or {}
        StockCache[row.shop_name][row.item_name] = tonumber(row.stock)
        local shop = InvCore.Inventories[ShopId(row.shop_name)]
        if shop and shop.persistentStock then
            for _, it in pairs(shop.items) do
                if it.name == row.item_name and it.amount then it.amount = tonumber(row.stock) end
            end
        end
    end
end)

CreateThread(function()
    local interval = math.max(1, tonumber(Config.ShopRestockMinutes) or 60) * 60000
    while true do
        Wait(interval)
        for _, inv in pairs(InvCore.Inventories) do
            if inv.type == 'shop' then
                for _, it in pairs(inv.items) do
                    if it.restock and it.amount and it.defaultstock and it.amount < it.defaultstock then
                        it.amount = math.min(it.defaultstock, it.amount + it.restock)
                        inv.stockDirty = true
                    end
                end
                InvCore.Refresh(inv.id)
            end
        end
        SaveStock()
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then SaveStock() end
end)
AddEventHandler('txAdmin:events:serverShuttingDown', SaveStock)
AddEventHandler('playerDropped', function() Cooldown[source] = nil end)

exports('CreateShop', Shops.CreateShop)
exports('OpenShop', Shops.OpenShop)
exports('DoesShopExist', Shops.DoesShopExist)
exports('RestockShop', Shops.RestockShop)

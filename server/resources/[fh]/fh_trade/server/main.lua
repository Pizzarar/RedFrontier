-- fh_trade server (spec L6). The server owns all price state; the pure model is shared/trade_prices.lua.
-- Selling: validate -> quote (dry run) -> fh_core.removeItem (all-or-nothing) -> commit the sale into the price
-- state -> fh_economy:pay. Natives: GetPlayerPed, GetEntityCoords, GetGameTimer. NOT runtime-tested (no Cfx key).
local cfg = FhTradeConfig
local P = FhTradePrices
P.isKnownRegion = FhRegions.isKnownRegion

local state = P.newState()
local dirty = {}      -- "region|item" -> { region, item } rows to flush
local busy = {}       -- src -> true while a sale is in flight (removeItem/pay may yield)
local lastReq = {}    -- src -> GetGameTimer() of the last menu/sell request
local ready = false

local function log(fmt, ...) print(('[fh_trade] ' .. fmt):format(...)) end
local function now() return os.time() end

local function reply(src, msg)
    if src and src > 0 then TriggerClientEvent('chat:addMessage', src, { args = { 'fh', msg } }) else print('[fh_trade] ' .. msg) end
end

-- ---------------------------------------------------------------- items (B7 @core)

-- TODO(B7 @core): fh_core.registerItems ships with @core block B7. Until then this logs and trade goods are not
-- defined in rsg-core (selling still works for any item the player already has under that name).
local function registerGoods()
    local items = {}
    for name, g in pairs(cfg.goods) do
        items[name] = { label = g.label, weight = g.weight, size_class = g.size_class, stackable = g.stackable, value_base = g.value_base }
    end
    local ok, a, b = pcall(function() return exports.fh_core:registerItems(items) end)
    if not ok then
        log('fh_core:registerItems is not available yet (B7 @core): trade goods NOT registered (%s)', tostring(a))
    elseif a == false then
        log('registerItems refused: %s', tostring(b))
    else
        log('registered %d trade goods', (function() local n = 0 for _ in pairs(items) do n = n + 1 end return n end)())
    end
end

-- ---------------------------------------------------------------- persistence

local function markDirty(region, item) dirty[region .. '|' .. item] = { region, item } end

local UPSERT = 'INSERT INTO fh_trade_prices (region_id, item, shortage, saturation, updated_at) VALUES (?, ?, ?, ?, ?) '
    .. 'ON DUPLICATE KEY UPDATE shortage = VALUES(shortage), saturation = VALUES(saturation), updated_at = VALUES(updated_at)'

local function byKey()
    local m = {}
    for _, r in ipairs(P.toRows(state)) do m[r.region_id .. '|' .. r.item] = r end
    return m
end

local function flush()
    if next(dirty) == nil then return end
    local rows, batch = byKey(), dirty
    dirty = {}
    for k in pairs(batch) do
        local r = rows[k]
        if r then
            local ok, err = pcall(MySQL.query.await, UPSERT, { r.region_id, r.item, r.shortage, r.saturation, math.floor(r.updated_at) })
            if not ok then
                log('save failed for %s (%s); will retry', k, tostring(err))
                dirty[k] = batch[k]
            end
        end
    end
end

local function load()
    local ok, rows = pcall(MySQL.query.await, 'SELECT region_id, item, shortage, saturation, updated_at FROM fh_trade_prices')
    if not ok then
        log('could not load prices (%s): did migration 0013_fh_trade.sql run? Starting from baseline.', tostring(rows))
        return
    end
    local n = 0
    for _, r in ipairs(rows or {}) do if P.loadRow(cfg, state, r) then n = n + 1 end end
    log('loaded %d price rows', n)
end

-- ---------------------------------------------------------------- posts

local function nearestPost(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return nil end
    local c = GetEntityCoords(ped)
    for _, p in ipairs(cfg.posts) do
        local dx, dy, dz = c.x - p.x, c.y - p.y, c.z - p.z
        if dx * dx + dy * dy + dz * dz <= p.radius * p.radius then return p end
    end
end

local function throttled(src)
    local t = GetGameTimer()
    if lastReq[src] and t - lastReq[src] < 500 then return true end
    lastReq[src] = t
    return false
end

-- ---------------------------------------------------------------- sell

local function removeFromPlayer(src, item, amount)
    -- TODO(B7 @core): fh_core.removeItem(ref, item, amount) -> true | false, 'fh_not_enough' (all-or-nothing per ref).
    -- Takes from the backpack only for now; equipped-slot goods are not sold (trade goods are not hotbar items).
    local ok, a, b = pcall(function() return exports.fh_core:removeItem({ type = 'backpack', id = src }, item, amount) end)
    if not ok then return false, 'fh_removeitem_missing' end
    if a == true then return true end
    return false, b or 'remove_failed'
end

---Sell `amount` of `item` at the trade post `post` for player `src`. @return boolean ok, integer|string totalOrErr
local function sell(src, post, item, amount)
    if not ready then return false, 'not_ready' end
    if type(src) ~= 'number' or src <= 0 then return false, 'no_player' end
    if busy[src] then return false, 'busy' end
    busy[src] = true
    local ok, res, extra = pcall(function()
        local t = now()
        local preview, err = P.previewSell(cfg, state, post.region, item, amount, t) -- validates item/amount/region
        if not preview then return false, err end
        local removed, why = removeFromPlayer(src, item, amount)
        if not removed then return false, why end
        local total = P.sell(cfg, state, post.region, item, amount, t) or preview -- items are gone: pay what was quoted
        markDirty(post.region, item)
        local paid, perr = exports.fh_economy:pay(src, total, 'trade_sell:' .. item, post.region)
        if not paid then
            -- Items are already gone and fh_core has no player-refund export (addItem is world containers only).
            log('ALERT pay failed after removing %dx%s from src %d (%s): owed $%d', amount, item, src, tostring(perr), total)
            return false, 'pay_failed'
        end
        TriggerEvent('fh:trade:sold', { src = src, region = post.region, post = post.id, item = item, amount = amount, total = total })
        return true, total
    end)
    busy[src] = nil
    if not ok then
        log('sell error: %s', tostring(res))
        return false, 'internal_error'
    end
    return res, extra
end

local function reason(code)
    local m = {
        fh_not_enough = 'You do not have that many.', unknown_item = 'The post does not buy that.',
        invalid_amount = ('Amount must be a whole number from 1 to %d.'):format(cfg.maxSellPerTx),
        worthless = 'That is not worth anything at the moment.', busy = 'One sale at a time.',
        pay_failed = 'The trade post could not pay you; an admin has been told (logged).',
        fh_removeitem_missing = 'Trading is not available yet.', not_ready = 'Trading is starting up.',
    }
    return m[code] or ('Sale refused (' .. tostring(code) .. ').')
end

local function doSell(src, item, amount)
    if throttled(src) then return end
    local post = nearestPost(src)
    if not post then return reply(src, 'You are not at a trade post.') end
    amount = tonumber(amount)
    local ok, res = sell(src, post, tostring(item), amount)
    if ok then
        reply(src, ('Sold %dx %s for $%d at %s.'):format(amount, (cfg.goods[item] or {}).label or item, res, post.label))
        TriggerClientEvent('fh:trade:sold', src, { item = item, amount = amount, total = res })
    else
        reply(src, reason(res))
    end
end

-- ---------------------------------------------------------------- exports

---Unit price now. @return number|nil price, table|string detail
local function quote(region, item) return P.quote(cfg, state, region, item, now()) end

---Items in shortage at a region (R4 freight contracts generate from this). Entries: { item, level, multiplier, price }.
local function getShortages(region) return P.shortages(cfg, state, region, now()) end

---Set a shortage level (0..1) from another resource/event/admin. @return boolean ok, string? err
local function setShortage(region, item, level)
    local ok, err = P.setShortage(cfg, state, region, item, tonumber(level), now())
    if ok then markDirty(region, item) end
    return ok, err
end

local function listGoods()
    local out = {}
    for name, g in pairs(cfg.goods) do out[name] = { label = g.label, base = g.base } end
    return out
end

local function previewSell(region, item, amount) return P.previewSell(cfg, state, region, item, amount, now()) end

exports('quote', quote)
exports('getShortages', getShortages)
exports('setShortage', setShortage)
exports('listGoods', listGoods)
exports('previewSell', previewSell)

-- ---------------------------------------------------------------- client menu + chat fallback

local function menuData(src)
    local post = nearestPost(src)
    if not post then return nil end
    local t, goods = now(), {}
    for name, g in pairs(cfg.goods) do
        local price, d = P.quote(cfg, state, post.region, name, t)
        goods[#goods + 1] = { item = name, label = g.label, price = price, shortage = d.shortage, saturation = d.saturation }
    end
    table.sort(goods, function(a, b) return a.item < b.item end)
    return { post = post.id, label = post.label, region = post.region, goods = goods, maxAmount = cfg.maxSellPerTx }
end

RegisterNetEvent('fh:trade:menu', function()
    local src = source
    if throttled(src) then return end
    local data = menuData(src)
    if not data then return reply(src, 'You are not at a trade post.') end
    TriggerClientEvent('fh:trade:menu', src, data)
end)

RegisterNetEvent('fh:trade:sell', function(item, amount)
    local src = source
    if type(item) ~= 'string' or #item > 64 then return end
    doSell(src, item, amount)
end)

-- Chat fallback: /tradequote  and  /tradesell <item> <amount>
RegisterCommand('tradequote', function(src)
    if src == 0 then return print(json.encode(P.toRows(state))) end
    local data = menuData(src)
    if not data then return reply(src, 'You are not at a trade post.') end
    for _, g in ipairs(data.goods) do reply(src, ('%s: $%.2f each%s'):format(g.label, g.price, g.shortage >= cfg.shortage.threshold and ' (in demand)' or '')) end
end, false)

RegisterCommand('tradesell', function(src, args)
    if src == 0 then return print('[fh_trade] tradesell is a player command') end
    doSell(src, args[1] or '', args[2])
end, false)

-- Server-console helper: fh_trade_shortage <region> <item> <level 0..1>
RegisterCommand('fh_trade_shortage', function(src, args)
    if src ~= 0 then return end
    print(json.encode({ setShortage(args[1], args[2], args[3]) }))
end, true)

-- ---------------------------------------------------------------- lifecycle

AddEventHandler('playerDropped', function() local s = source busy[s] = nil lastReq[s] = nil end)

AddEventHandler('onResourceStart', function(res)
    if res == 'fh_core' and ready then registerGoods() end -- fh_core restarted: re-push the items
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then flush() end
end)

CreateThread(function()
    registerGoods()
    load()
    ready = true
    while true do
        Wait(cfg.saveMs)
        flush()
    end
end)

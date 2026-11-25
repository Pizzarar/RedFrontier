-- fh_tailor <-> fh_ui screens `tailor` and `wardrobe` (ui-tailor-catalog T4a).
-- AUTHORITY: fh_ui is dumb. The relay re-emits fh:tailor:ui_<action> as ONE table { src, screen, action, payload } where
-- src is the net source (never the payload). This file calls ONLY the guarded, debounced exports (actBuy, actStock,
-- actWardrobe, actEquip, actSave, actWear: range guard + debounce live there), never the raw buy/equip/getStock.
-- The shop id for a buy comes from server state set by openShop (per src), never from the client. The client sends only
-- an entry id / outfit ids / slot; price, tier and owned are re-derived by the server. Every refusal is shown as
-- message(code). Pure factory (specced in spec/tailor_ui_spec.lua); the FiveM wiring is at the bottom.
local M = {}

local MAX_ID, MAX_ITEMS_IN = 64, 16

local function isId(v) return type(v) == 'string' and #v >= 1 and #v <= MAX_ID end

---@param d table { exp = { actBuy, actStock, actWardrobe, actEquip, actSave, actWear, message }, open(src, screen, data), update(src, screen, data), notify(src, text) }
function M.new(d)
    local exp = d.exp
    local U = { shopOf = {} } -- src -> last shop opened by the server (never from the client)

    local function stockData(src, shopId)
        local ok, res = exp.actStock(src, shopId)
        if ok and type(res) == 'table' then return res end
        return nil, res
    end

    local function wardrobeData(src)
        local ok, res = exp.actWardrobe(src)
        if ok and type(res) == 'table' then return res end
        return nil, res
    end

    -- Send fresh data with a notice; if the refresh itself is refused, send the notice alone (screen keeps its rows).
    local function push(src, screen, data, text, kind)
        local out = data or {}
        out.notice, out.notice_kind = text, kind
        d.update(src, screen, out)
    end

    function U.openShop(src, shopId)
        if type(src) ~= 'number' or not isId(shopId) then return false end
        local data, code = stockData(src, shopId)
        if not data then d.notify(src, exp.message(code)) return false end
        U.shopOf[src] = shopId
        d.open(src, 'tailor', data)
        return true
    end

    function U.openWardrobe(src)
        if type(src) ~= 'number' then return false end
        local data, code = wardrobeData(src)
        if not data then d.notify(src, exp.message(code)) return false end
        d.open(src, 'wardrobe', data)
        return true
    end

    local function itemList(v)
        if v == nil then return {} end
        if type(v) ~= 'table' or #v > MAX_ITEMS_IN then return nil end
        local out = {}
        for i = 1, #v do
            if not isId(v[i]) then return nil end
            out[i] = v[i]
        end
        for k in pairs(v) do if type(k) ~= 'number' or k < 1 or k > #v then return nil end end
        return out
    end

    local function valid(ev, screen)
        return type(ev) == 'table' and ev.screen == screen and type(ev.src) == 'number' and type(ev.payload) == 'table'
    end

    function U.onBuy(ev)
        if not valid(ev, 'tailor') then return end
        local src, entry = ev.src, ev.payload.entry_id
        if not isId(entry) then return end
        local shop = U.shopOf[src] -- server state only
        if not shop then return push(src, 'tailor', nil, 'Visit a tailor to shop.', 'err') end
        local ok, res = exp.actBuy(src, shop, entry)
        if not ok then return push(src, 'tailor', nil, exp.message(res), 'err') end
        local data = stockData(src, shop)
        local label = entry
        for _, r in ipairs(data and data.rows or {}) do if r.id == entry then label = r.label end end
        push(src, 'tailor', data, 'Bought ' .. tostring(label) .. '.', 'ok')
    end

    function U.onClose(ev)
        if valid(ev, 'tailor') then U.shopOf[ev.src] = nil end
    end

    local function wardrobeAction(run, okText)
        return function(ev)
            if not valid(ev, 'wardrobe') then return end
            local src = ev.src
            local ok, res = run(src, ev.payload)
            if ok == nil then return end -- malformed payload: ignore
            if not ok then return push(src, 'wardrobe', nil, exp.message(res), 'err') end
            push(src, 'wardrobe', wardrobeData(src), okText(ev.payload), 'ok')
        end
    end

    U.onEquip = wardrobeAction(function(src, p)
        local items = itemList(p.item_ids)
        if not isId(p.outfit_id) or not items then return nil end
        return exp.actEquip(src, p.outfit_id, items)
    end, function() return 'Outfit changed.' end)

    U.onSave = wardrobeAction(function(src, p)
        local items = itemList(p.item_ids)
        local label = p.label
        if not isId(p.outfit_id) or not items or math.type(p.slot) ~= 'integer' then return nil end
        if label ~= nil and (type(label) ~= 'string' or #label > 64) then return nil end
        return exp.actSave(src, p.slot, label, p.outfit_id, items)
    end, function(p) return 'Saved to slot ' .. tostring(p.slot) .. '.' end)

    U.onWear = wardrobeAction(function(src, p)
        if math.type(p.slot) ~= 'integer' then return nil end
        return exp.actWear(src, p.slot)
    end, function(p) return 'Wearing slot ' .. tostring(p.slot) .. '.' end)

    function U.forget(src) U.shopOf[src] = nil end

    return U
end

if _G.GetCurrentResourceName then
    local function call(name)
        return function(...)
            local args = { ... }
            local okC, a, b = pcall(function() return exports.fh_tailor[name](exports.fh_tailor, table.unpack(args)) end)
            if not okC then return false, 'tailor_error' end
            return a, b
        end
    end
    local U = M.new({
        exp = {
            actBuy = call('actBuy'), actStock = call('actStock'), actWardrobe = call('actWardrobe'),
            actEquip = call('actEquip'), actSave = call('actSave'), actWear = call('actWear'),
            message = function(code) return FhTailorLogic.message(code) end,
        },
        open = function(src, screen, data) TriggerClientEvent('fh:ui:open', src, { screen = screen, data = data }) end,
        update = function(src, screen, data) TriggerClientEvent('fh:ui:update', src, { screen = screen, data = data }) end,
        notify = function(src, text) TriggerClientEvent('chat:addMessage', src, { args = { 'Tailor', text } }) end,
    })
    AddEventHandler('fh:tailor:ui_buy', U.onBuy)
    AddEventHandler('fh:tailor:ui_close', U.onClose)
    AddEventHandler('fh:tailor:ui_equip', U.onEquip)
    AddEventHandler('fh:tailor:ui_save', U.onSave)
    AddEventHandler('fh:tailor:ui_wear', U.onWear)
    AddEventHandler('playerDropped', function() U.forget(tonumber(source)) end)
    exports('openShop', U.openShop)
    exports('openWardrobe', U.openWardrobe)
end
return M

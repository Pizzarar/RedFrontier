-- fh_tailor/server/ui.lua: relayed ui_* handlers with stubbed guarded exports (actBuy etc. from T2b).
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local case, eq = T.it, T.eq
local UI = dofile(here .. '../server/resources/[fh]/fh_tailor/server/ui.lua')

local function rig()
    local r = { calls = {}, sent = {}, notes = {}, refuse = nil }
    local function rec(name, okres)
        return function(...)
            r.calls[#r.calls + 1] = { name, ... }
            if r.refuse and r.refuse[name] then return false, r.refuse[name] end
            return true, okres
        end
    end
    r.stock = { shop = { id = 's' }, tier = 1, rows = { { id = 'a', label = 'Coat', owned = true } } }
    r.ward = { owned = {}, saved = {}, maxItems = 2, maxSaved = 3, fitted = false }
    r.ui = UI.new({
        exp = {
            actBuy = rec('actBuy', { entry_id = 'a' }), actEquip = rec('actEquip', {}), actSave = rec('actSave', true),
            actWear = rec('actWear', {}),
            actStock = function(src, shop) r.calls[#r.calls + 1] = { 'actStock', src, shop }
                if r.refuse and r.refuse.actStock then return false, r.refuse.actStock end
                return true, { shop = r.stock.shop, tier = 1, rows = r.stock.rows } end,
            actWardrobe = function(src) r.calls[#r.calls + 1] = { 'actWardrobe', src }
                if r.refuse and r.refuse.actWardrobe then return false, r.refuse.actWardrobe end
                return true, { owned = {}, saved = {}, maxItems = 2, maxSaved = 3, fitted = false } end,
            message = function(c) return 'MSG:' .. c end,
        },
        open = function(src, screen, data) r.sent[#r.sent + 1] = { 'open', src, screen, data } end,
        update = function(src, screen, data) r.sent[#r.sent + 1] = { 'update', src, screen, data } end,
        notify = function(src, t) r.notes[#r.notes + 1] = { src, t } end,
    })
    return r
end
local function ev(screen, payload, src) return { src = src or 5, screen = screen, action = 'x', payload = payload } end
local function has(r, name) for _, c in ipairs(r.calls) do if c[1] == name then return c end end end

case('openShop: refusal notifies message(code) and does not open or remember the shop', function()
    local r = rig(); r.refuse = { actStock = 'not_at_wardrobe' }
    eq(false, r.ui.openShop(5, 'valentine'))
    eq('MSG:not_at_wardrobe', r.notes[1][2]); eq(0, #r.sent); eq(nil, r.ui.shopOf[5])
end)
case('openShop then ui_buy: shop comes from server state, client payload shop is ignored', function()
    local r = rig()
    eq(true, r.ui.openShop(5, 'valentine')); eq('tailor', r.sent[1][3])
    r.ui.onBuy(ev('tailor', { entry_id = 'a', shop_id = 'evil', price = 0 }))
    local c = has(r, 'actBuy'); eq('valentine', c[3]); eq('a', c[4]); eq(5, c[2]); eq(4, #c)
    local u = r.sent[#r.sent]; eq('update', u[1]); eq('ok', u[4].notice_kind); assert(u[4].notice:find('Coat'))
end)
case('ui_buy without an opened shop is refused with no act call; drop/close clears the shop', function()
    local r = rig()
    r.ui.onBuy(ev('tailor', { entry_id = 'a' })); assert(not has(r, 'actBuy')); eq('err', r.sent[1][4].notice_kind)
    r.ui.openShop(5, 'v'); r.ui.onClose(ev('tailor', {})); eq(nil, r.ui.shopOf[5])
    r.ui.openShop(5, 'v'); r.ui.forget(5); eq(nil, r.ui.shopOf[5])
end)
case('buy refusal (too_fast / tier) becomes the notice; wrong screen and bad src ignored', function()
    local r = rig(); r.ui.openShop(5, 'v'); r.refuse = { actBuy = 'too_fast' }; r.sent = {}
    r.ui.onBuy(ev('tailor', { entry_id = 'a' }))
    eq('MSG:too_fast', r.sent[1][4].notice); eq('err', r.sent[1][4].notice_kind)
    r.sent = {}
    r.ui.onBuy(ev('wardrobe', { entry_id = 'a' })); r.ui.onBuy({ src = 'x', screen = 'tailor', payload = {} })
    r.ui.onBuy(ev('tailor', { entry_id = 7 })); eq(0, #r.sent)
end)
case('equip / save / wear call the guarded exports with validated args and refresh', function()
    local r = rig()
    r.ui.onEquip(ev('wardrobe', { outfit_id = 'o', item_ids = { 'i1' } }))
    local c = has(r, 'actEquip'); eq('o', c[3]); eq('i1', c[4][1])
    r.ui.onSave(ev('wardrobe', { slot = 2, label = 'Sun', outfit_id = 'o', item_ids = {} }))
    c = has(r, 'actSave'); eq(2, c[3]); eq('Sun', c[4]); eq('o', c[5])
    r.ui.onWear(ev('wardrobe', { slot = 2 })); eq(2, has(r, 'actWear')[3])
    eq('ok', r.sent[#r.sent][4].notice_kind)
    r.refuse = { actWear = 'empty_slot' }; r.ui.onWear(ev('wardrobe', { slot = 3 }))
    eq('MSG:empty_slot', r.sent[#r.sent][4].notice)
end)
case('malformed wardrobe payloads never reach the exports', function()
    local r = rig()
    r.ui.onEquip(ev('wardrobe', { outfit_id = 'o', item_ids = 'x' }))
    r.ui.onEquip(ev('wardrobe', { outfit_id = 5, item_ids = {} }))
    r.ui.onSave(ev('wardrobe', { slot = 1.5, outfit_id = 'o', item_ids = {} }))
    r.ui.onSave(ev('wardrobe', { slot = 1, label = {}, outfit_id = 'o', item_ids = {} }))
    r.ui.onWear(ev('wardrobe', { slot = 'a' }))
    r.ui.onWear(ev('tailor', { slot = 1 }))
    eq(0, #r.calls)
end)
case('openWardrobe opens wardrobe; refusal notifies', function()
    local r = rig(); eq(true, r.ui.openWardrobe(5)); eq('wardrobe', r.sent[1][3])
    r.refuse = { actWardrobe = 'not_at_wardrobe' }; eq(false, r.ui.openWardrobe(5)); eq('MSG:not_at_wardrobe', r.notes[1][2])
end)

T.finish()

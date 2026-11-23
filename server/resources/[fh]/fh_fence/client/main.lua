-- fh_fence client: stopgap ox_lib context-menu shop near the current stop (a @ui screen replaces it later).
-- Server decides everything; this only shows the menu and relays choices.
-- Natives: IsControlJustReleased (fh_core/docs/natives.md, unverified in-game). Not runtime-tested.
local INPUT_CONTEXT = 0xCEFD9220 -- E (unverified)
local point = nil
local stopId = nil

local MESSAGES = FhFenceLogic.messages -- shared/fence_logic.lua (every B7 charge/pay code covered)
local function why(code) return MESSAGES[code] or ('Refused: ' .. tostring(code)) end

local function notify(msg) lib.notify({ description = msg, type = 'inform' }) end

local function qtyPrompt(title)
    local r = lib.inputDialog(title, { { type = 'number', label = 'Amount', default = 1, min = 1, max = FhFenceConfig.maxQty } })
    return r and tonumber(r[1]) or nil
end

local function buy(e)
    local qty = e.lead and 1 or qtyPrompt(('Buy %s'):format(e.item))
    if not qty then return end
    local ok, a, b = lib.callback.await('fh:fence:buy', false, e.item, qty)
    if not ok then return notify(why(a)) end
    if a and a < qty then
        if b and b > 0 then return notify(('Bought %d of %d. No room for the rest: $%d refunded.'):format(a, qty, b)) end
        return notify(('Bought %d of %d. The refund for the rest failed: ask an admin.'):format(a, qty))
    end
    notify('Bought.')
end

local function sell(s)
    local qty = qtyPrompt(('Sell %s'):format(s.item))
    if not qty then return end
    local ok, a, b = lib.callback.await('fh:fence:sell', false, s.item, qty)
    notify(ok and ('Sold %d for $%d.'):format(a, b) or why(a))
end

local function openMenu()
    local m, err = lib.callback.await('fh:fence:menu', false)
    if not m then return notify(why(err)) end
    local opts = {}
    for _, e in ipairs(m.stock) do
        opts[#opts + 1] = { title = ('%s - $%d'):format(e.item, e.price), description = e.category,
            onSelect = function() buy(e) end }
    end
    for _, s in ipairs(m.sells) do
        opts[#opts + 1] = { title = ('Sell %s - $%d'):format(s.item, s.price), onSelect = function() sell(s) end }
    end
    lib.registerContext({ id = 'fh_fence_menu', title = m.label, options = opts })
    lib.showContext('fh_fence_menu')
end

local function setStop(w)
    if point then point:remove(); point = nil; lib.hideTextUI() end
    stopId = w and w.id
    if not w then return end
    point = lib.points.new({
        coords = vec3(w.coords.x, w.coords.y, w.coords.z), distance = w.range,
        onEnter = FH.wrap(function() lib.showTextUI('[E] ' .. w.label) end),
        onExit = FH.wrap(function() lib.hideTextUI() end),
        nearby = FH.wrap(function()
            if IsControlJustReleased(0, INPUT_CONTEXT) then openMenu() end
        end),
    })
end

FH.thread(function()
    while true do
        local w = lib.callback.await('fh:fence:where', false)
        if (w and w.id) ~= stopId then setStop(w) end
        Wait(15000)
    end
end)

FH.on('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    lib.hideTextUI()
end)

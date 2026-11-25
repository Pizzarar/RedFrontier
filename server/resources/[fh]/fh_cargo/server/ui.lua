-- fh_cargo <-> fh_ui screen `wagonyard` (ui-inbox-03 I3, replacing the R17 ox_lib menu).
-- AUTHORITY: fh_ui is dumb. The relay re-emits fh:cargo:ui_<action> as ONE table { src, screen, action, payload } where
-- src is the net source (never the payload). Handlers accept only { tier } for buy/call and nothing for stow; post,
-- region, price, ownership and live state are all derived server-side via FhCargoPost (exports.fh_trade:nearestPost,
-- FhCargoPost.buy -> buyWagon, FhCargoPost.call, FhCargoPost.stow). Error codes and details pass through unchanged so
-- the screen shows the same messages as the old client MSG table.
-- Pure factory (specced in spec/cargo_ui_spec.lua and spec/cargo_post_spec.lua); FiveM wiring is at the bottom.
local M = {}

M.MSG = {
    fh_not_at_post     = 'Stand at a trade post first.',
    fh_not_owned       = 'You do not own that wagon.',
    fh_wagon_live      = 'You already have a wagon out. Stow it first.',
    fh_no_wagon        = 'You have no wagon out.',
    fh_wagon_far       = 'Your wagon is too far from the post.',
    fh_wagon_not_ready = 'Your wagon is still arriving.',
    fh_busy            = 'One moment...',
    fh_buy_busy        = 'One moment...',
    fh_already_owned   = 'You already own that wagon.',
    fh_locked          = 'You have not earned that wagon yet.',
    fh_db_error        = 'The wagon ledger is unavailable.',
}

M.OK_MSG = {
    buy  = 'Wagon bought.',
    call = 'Wagon on its way.',
    stow = 'Wagon stowed. Cargo kept.',
}

function M.message(err)
    if type(err) == 'string' and M.MSG[err] then return M.MSG[err] end
    return tostring(err or 'Refused.')
end

local function validSrc(src) return type(src) == 'number' and src == src and src > 0 end

local function validEv(ev)
    return type(ev) == 'table' and ev.screen == 'wagonyard' and validSrc(ev.src) and type(ev.payload) == 'table'
end

local function validTierArg(tier)
    return type(tier) == 'string' and #tier >= 1 and #tier <= 16
end

---@param d table { menu(src), buy(src, tier), call(src, tier), stow(src), throttled(src), open(src, screen, data), update(src, screen, data), notify(src, text) }
function M.new(d)
    local U = {}

    local function pushResult(src, action, ok, err, detail)
        local data, menuErr = d.menu(src)
        if type(data) ~= 'table' then
            d.notify(src, ok and (M.OK_MSG[action] or 'Done.') or M.message(menuErr or err))
            return
        end
        if ok then
            data.notice = M.OK_MSG[action] or 'Done.'
            data.notice_kind = 'ok'
        else
            data.notice = M.message(err)
            data.notice_kind = 'err'
            data.err = err
            if detail ~= nil then data.detail = detail end
        end
        d.update(src, 'wagonyard', data)
    end

    function U.open(src)
        if not validSrc(src) then return false, 'fh_no_player' end
        if d.throttled and d.throttled(src) then return false, 'fh_busy' end
        local data, err = d.menu(src)
        if not data then
            d.notify(src, M.message(err))
            return false, err
        end
        d.open(src, 'wagonyard', data)
        return true
    end

    function U.onBuy(ev)
        if not validEv(ev) then return end
        local tier = ev.payload.tier
        if not validTierArg(tier) then return end
        local src = ev.src
        if d.throttled and d.throttled(src) then return end
        local ok, res, detail = d.buy(src, tier)
        pushResult(src, 'buy', ok == true, (not ok) and res or nil, (not ok) and detail or nil)
    end

    function U.onCall(ev)
        if not validEv(ev) then return end
        local tier = ev.payload.tier
        if not validTierArg(tier) then return end
        local src = ev.src
        if d.throttled and d.throttled(src) then return end
        local ok, res, detail = d.call(src, tier)
        pushResult(src, 'call', ok == true, (not ok) and res or nil, (not ok) and detail or nil)
    end

    function U.onStow(ev)
        if not validEv(ev) then return end
        local src = ev.src
        if d.throttled and d.throttled(src) then return end
        local ok, res, detail = d.stow(src)
        pushResult(src, 'stow', ok == true, (not ok) and res or nil, (not ok) and detail or nil)
    end

    function U.onClose(ev)
        if not validEv(ev) then return end
    end

    return U
end

if _G.GetCurrentResourceName then
    local api = FhCargoPostApi
    if api then
        local U = M.new({
            menu      = api.menu,
            buy       = api.buy,
            call      = api.call,
            stow      = api.stow,
            throttled = api.throttled,
            open      = function(src, screen, data) TriggerClientEvent('fh:ui:open', src, { screen = screen, data = data }) end,
            update    = function(src, screen, data) TriggerClientEvent('fh:ui:update', src, { screen = screen, data = data }) end,
            notify    = function(src, text) TriggerClientEvent('chat:addMessage', src, { args = { 'Wagons', text } }) end,
        })
        RegisterNetEvent('fh:cargo:menu_open', function() U.open(source) end)
        AddEventHandler('fh:cargo:ui_buy', U.onBuy)
        AddEventHandler('fh:cargo:ui_call', U.onCall)
        AddEventHandler('fh:cargo:ui_stow', U.onStow)
        AddEventHandler('fh:cargo:ui_close', U.onClose)
    end
end

return M

-- Pure builder for the fh_ui `tradepost` screen data + trade-result notices. No natives, no exports, no clock reads:
-- the server injects quote (P.quote with state), labelOf (rsg-core label), now (unix seconds) and reason (the server's
-- trade-neutral wording, idea-725). Specced in spec/trade_screen_spec.lua.
local M = {}

---tradepost screen data: goods (priced via quote) + supplies (flat config price). post = { label, region }.
---quote(region, item, now) -> price, detail ({ shortage, saturation, ... }). labelOf(item) -> label.
---@return table|nil data { label, region, goods, supplies, max_sell, max_buy }, nil when the post is unusable
function M.screenData(cfg, post, quote, labelOf, now)
    if type(post) ~= 'table' or type(post.region) ~= 'string' then return nil end
    local goods = {}
    for name, g in pairs(cfg.goods or {}) do
        local price, d = quote(post.region, name, now)
        goods[#goods + 1] = { item = name, label = g.label, price = price, shortage = d.shortage, saturation = d.saturation }
    end
    table.sort(goods, function(a, b) return a.item < b.item end)
    local supplies = {}
    for item, price in pairs(cfg.supplies or {}) do
        supplies[#supplies + 1] = { item = item, label = labelOf(item), price = price }
    end
    table.sort(supplies, function(a, b) return a.item < b.item end)
    return { label = post.label, region = post.region, goods = goods, supplies = supplies,
        max_sell = cfg.maxSellPerTx, max_buy = cfg.maxBuyPerTx or 100 }
end

---Buy-refusal text, shared with the chat fallback (fh:trade:buy -> doBuy). reason(code) -> string is injected.
function M.buyMessage(cfg, res, extra, reason)
    if res == 'invalid_amount' then return ('Amount must be a whole number from 1 to %d.'):format(cfg.maxBuyPerTx or 100) end
    if res == 'unknown_item' then return 'The post does not sell that.' end
    return reason(res) .. (extra and res ~= 'refund_failed' and (' (' .. tostring(extra) .. ')') or '')
end

---Sell result -> notice text, notice_kind ('ok'|'error'). ok/total = the sell() return (total dollars, or a refusal code).
function M.sellNotice(itemLabel, amount, ok, total, reason)
    if not ok then return reason(total), 'error' end
    return ('Sold %dx %s for $%d.'):format(amount, itemLabel, total), 'ok'
end

---Buy result -> notice text, notice_kind. ok/total/detail = the S.buy() return. Reuses buyMessage for refusals.
function M.buyNotice(cfg, itemLabel, amount, ok, total, detail, reason)
    if not ok then return M.buyMessage(cfg, total, detail, reason), 'error' end
    return ('Bought %dx %s for $%d.'):format(amount, itemLabel, total), 'ok'
end

if GetCurrentResourceName then FhTradeScreen = M end
return M

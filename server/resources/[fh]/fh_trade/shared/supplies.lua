-- Trade-post BUY side: the `supplies` list (idea-716 / idea-719, plan crafting-01-l5). Pure: no natives, no exports;
-- the server injects the side effects as `deps`. Specced in spec/trade_supplies_spec.lua.
--
-- Flat price per item from FhTradeConfig.supplies, unlimited stock. Buying never reads or writes the R3 price state
-- (shared/trade_prices.lua): no shortage, no saturation, no wobble.
--
-- buy() sequence (all-or-nothing, one trade per player at a time):
--   validate item/amount/post -> lock -> citizenid -> charge(src, total, 'trade_buy:<item>', post.region)
--   -> grant(src, item, amount)  [fh_core.addItem on the backpack: all-or-nothing, nothing added on refusal]
--   -> on grant failure: refund(citizenid, total, 'trade_buy_refund:<item>', post.region)  [fh_economy.credit]
-- The lock is released on every path, including a throw from any dep.
local M = {}

local function isInt(n) return type(n) == 'number' and n == n and n % 1 == 0 end

---Validate an item + amount against the supplies list. @return integer|nil total, integer|string priceOrErr
function M.validate(cfg, item, amount)
    local price = type(item) == 'string' and (cfg.supplies or {})[item] or nil
    if not isInt(price) or price <= 0 then return nil, 'unknown_item' end
    local max = cfg.maxBuyPerTx or 100
    if not isInt(amount) or amount < 1 or amount > max then return nil, 'invalid_amount' end
    return price * amount, price
end

---Sorted list for menus: { { item, price }, ... }.
function M.list(cfg)
    local out = {}
    for item, price in pairs(cfg.supplies or {}) do out[#out + 1] = { item = item, price = price } end
    table.sort(out, function(a, b) return a.item < b.item end)
    return out
end

local function call(f, ...)
    local ok, a, b, c = pcall(f, ...)
    if not ok then return false, 'threw', tostring(a) end
    return a, b, c
end

-- Logging must never turn a charged path into a throw.
local function say(deps, ...) if deps.log then pcall(deps.log, ...) end end

local function run(cfg, deps, src, post, item, amount)
    local total, price = M.validate(cfg, item, amount)
    if not total then return false, price end
    local region = post.region

    -- Read the citizenid with no yield before charge: charge charges the character loaded on src at its call and
    -- refuses (player_changed / no_player, no money) if that changes during its insert, so this cid is the payer.
    local cid = deps.citizenid(src)
    if type(cid) ~= 'string' or cid == '' then return false, 'no_player' end

    local reasonBuy = 'trade_buy:' .. item
    local charged, cerr, cdetail = call(deps.charge, src, total, reasonBuy, region)
    if charged ~= true then
        if cerr == 'threw' then
            -- Unknown whether money moved: never grant (no item without payment). fh_economy voids its own row on failure.
            say(deps, 'ALERT charge threw for src %s (%s) buying %sx%s $%s: no item granted', src, tostring(cdetail), amount, item, total)
            return false, 'charge_error'
        end
        -- fh_charge_busy, fh_insufficient_funds, no_player, player_changed, ...: plain refusal, no item, no refund.
        return false, cerr or 'charge_failed'
    end

    local granted, gerr, gdetail = call(deps.grant, src, item, amount)
    if granted == true then return true, total, price end

    -- addItem is all-or-nothing (fh_core README addItem row): a refusal added nothing, so refund the full charge.
    -- A throw is treated the same (the export did not complete); logged so an admin can check.
    if gerr == 'threw' then say(deps, 'ALERT grant threw for src %s (%s) after charging $%s for %sx%s; refunding', src, tostring(gdetail), total, amount, item) end
    local refunded, rerr, rdetail = call(deps.refund, cid, total, 'trade_buy_refund:' .. item, region)
    if refunded ~= true then
        say(deps, 'ALERT refund FAILED for %s (src %s): charged $%s for %sx%s, grant failed (%s), refund failed (%s %s): owed $%s',
            cid, src, total, amount, item, tostring(gerr), tostring(rerr), tostring(rdetail or ''), total)
        return false, 'refund_failed', gerr
    end
    return false, 'grant_failed_refunded', gerr
end

---Buy `amount` of `item` at `post` for `src`.
---deps = { citizenid(src) -> cid|nil, charge(src, total, reason, region) -> ok, err,
---         grant(src, item, amount) -> ok, err, refund(cid, total, reason, region) -> ok, err, log(fmt, ...) }
---lock = table src -> true (shared with the sell side: one trade at a time per player).
---@return boolean ok, integer|string totalOrErr, any priceOrDetail
function M.buy(cfg, deps, lock, src, post, item, amount)
    if type(src) ~= 'number' or src <= 0 then return false, 'no_player' end
    if type(post) ~= 'table' or type(post.region) ~= 'string' then return false, 'no_post' end
    if lock[src] then return false, 'busy' end
    lock[src] = true
    local ok, a, b, c = pcall(run, cfg, deps, src, post, item, amount)
    lock[src] = nil
    if not ok then
        say(deps, 'buy error: %s', tostring(a))
        return false, 'internal_error'
    end
    return a, b, c
end

if GetCurrentResourceName then
    FhTradeSupplies = M
else
    return M
end

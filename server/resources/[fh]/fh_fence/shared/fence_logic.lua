-- Fence rules: schedule math, tier-gated stock, buy/sell validation. Pure Lua, no FiveM globals; unit-tested.
local M = {}

local function isInt(n) return type(n) == 'number' and n == n and n == math.floor(n) end

---Convar string -> boolean (same accepted values as fh_core's parseFlag).
function M.parseFlag(s, default)
    s = tostring(s or ''):lower()
    if s == 'true' or s == '1' or s == 'yes' or s == 'on' then return true end
    if s == 'false' or s == '0' or s == 'no' or s == 'off' then return false end
    return default
end

---fh_spike_gated convar value -> may the fence NPC spawn? true/unset/garbage = gated (conservative) = no spawn.
function M.spawnEnabled(spikeGated) return not M.parseFlag(spikeGated, true) end

---Deterministic schedule. now = unix seconds. Returns { index, stop, nextStop, remaining, startedAt } or nil, reason.
function M.schedule(cfg, now)
    if type(cfg) ~= 'table' or type(cfg.rotation) ~= 'table' or #cfg.rotation == 0 then return nil, 'bad_rotation' end
    if type(cfg.dwellMinutes) ~= 'number' or cfg.dwellMinutes <= 0 then return nil, 'bad_dwell' end
    if type(now) ~= 'number' or now ~= now or now < 0 then return nil, 'bad_time' end
    for _, id in ipairs(cfg.rotation) do
        if type(cfg.stops) ~= 'table' or not cfg.stops[id] then return nil, 'unknown_stop' end
    end
    local dwell = cfg.dwellMinutes * 60
    local slot = math.floor(now / dwell)
    local n = #cfg.rotation
    local i = slot % n + 1
    local started = slot * dwell
    return { index = i, stop = cfg.rotation[i], nextStop = cfg.rotation[i % n + 1],
        remaining = started + dwell - now, startedAt = started }
end

---Seconds until the fence moves to its next stop (admin `fh_fence_next` skews the clock forward by this much).
function M.secondsToNext(cfg, now)
    local s = M.schedule(cfg, now)
    return s and s.remaining or nil
end

---Stock entries visible to a player: common always, rare / leads only when unlocked. Each result has category set.
---leadOk(entry) -> bool (optional, server): a `leads` entry is listed only when it is true (its spot id resolves in
---the server-only spot config), so a lead whose spot is missing is never sold. `lead` is the opaque spot id only.
function M.filterStock(stopStock, canRare, canLeads, leadOk)
    local out = {}
    if type(stopStock) ~= 'table' then return out end
    local function add(cat, list)
        for _, e in ipairs(list or {}) do
            if cat ~= 'leads' or not leadOk or leadOk(e) then
                out[#out + 1] = { item = e.item, price = e.price, category = cat, lead = e.lead }
            end
        end
    end
    add('common', stopStock.common)
    if canRare then add('rare', stopStock.rare) end
    if canLeads then add('leads', stopStock.leads) end
    return out
end

---Maps the `fh:fence:menu` payload to the fh_ui `fence` screen data (display only: the server re-prices and re-checks
---every trade). opts = { maxQty, labels = item->label, held = item->count }. Buy rows: qty = per-deal cap (1 for a
---`leads` row, a unique item). Sell rows: qty = units held, capped at maxQty (0 disables the button). Tier gating was
---already done server-side by visibleStock.
function M.screenData(menu, opts)
    menu = type(menu) == 'table' and menu or {}
    opts = opts or {}
    local cap = tonumber(opts.maxQty) or 20
    local labels, held = opts.labels or {}, opts.held or {}
    local stock, sell = {}, {}
    for _, e in ipairs(type(menu.stock) == 'table' and menu.stock or {}) do
        stock[#stock + 1] = { id = e.item, label = labels[e.item] or e.item, price = e.price,
            qty = (e.lead or e.category == 'leads') and 1 or cap, category = e.category }
    end
    for _, s in ipairs(type(menu.sells) == 'table' and menu.sells or {}) do
        sell[#sell + 1] = { id = s.item, label = labels[s.item] or s.item, price = s.price,
            qty = math.min(cap, math.max(0, math.floor(tonumber(held[s.item]) or 0))) }
    end
    return { title = menu.label, stock = stock, sell = sell }
end

---Unknown codes fall back to 'Refused: <code>'.
function M.why(code) return M.messages[code] or ('Refused: ' .. tostring(code)) end

---Inline notice text for a finished trade. kind 'buy'|'sell'; ok/a/b = the trader's return values
---(buy -> delivered, refunded | sell -> sold, total | refusal -> code).
function M.notice(kind, qty, ok, a, b)
    if not ok then return M.why(a) end
    if kind == 'sell' then return ('Sold %d for $%d.'):format(tonumber(a) or 0, tonumber(b) or 0) end
    a = tonumber(a) or 0
    qty = tonumber(qty)
    if qty and a < qty then
        if (tonumber(b) or 0) > 0 then
            return ('Bought %d of %d. No room for the rest: $%d refunded.'):format(a, qty, b)
        end
        return ('Bought %d of %d. The refund for the rest failed: ask an admin.'):format(a, qty)
    end
    return 'Bought.'
end

---Validates a buy against the visible stock. Returns { total, entry, qty } or nil, reason.
function M.quoteBuy(visible, item, qty, maxQty)
    if type(item) ~= 'string' then return nil, 'bad_item' end
    if not isInt(qty) or qty < 1 or qty > (maxQty or 20) then return nil, 'bad_qty' end
    for _, e in ipairs(visible or {}) do
        if e.item == item then
            if e.lead and qty ~= 1 then return nil, 'bad_qty' end -- each lead is a unique item
            return { total = e.price * qty, entry = e, qty = qty }
        end
    end
    return nil, 'not_in_stock'
end

---Validates a sell. Returns total or nil, reason. The payout cap is fh_economy's (pay refuses amount_too_large).
function M.quoteSell(cfg, item, qty)
    if type(item) ~= 'string' then return nil, 'bad_item' end
    if not isInt(qty) or qty < 1 or qty > (cfg.maxQty or 20) then return nil, 'bad_qty' end
    local price = cfg.buys and cfg.buys[item]
    if type(price) ~= 'number' then return nil, 'not_bought' end
    return price * qty
end

---Lead item info written at purchase: ONLY the opaque spot id, { lead = '<id>' }. Item info reaches the client, so it
---never carries coords or the hint: the server resolves the id (server/config_leads.lua) when the lead is dug or shown.
function M.leadInfo(entry)
    local id = entry and entry.lead
    if type(id) ~= 'string' or id == '' then return nil end
    return { lead = id }
end

---Distance check against a stop. Accepts {x,y,z} tables.
function M.inRange(pos, stop, range)
    if type(pos) ~= 'table' or type(stop) ~= 'table' then return false end
    if type(pos.x) ~= 'number' or type(pos.y) ~= 'number' or type(pos.z) ~= 'number' then return false end
    local dx, dy, dz = pos.x - stop.x, pos.y - stop.y, pos.z - stop.z
    return dx * dx + dy * dy + dz * dz <= range * range
end

---Sell rollback decision, after the goods were taken and pay was attempted.
---payOk/payErr: result of fh_economy:pay. restore: function() -> ok, err, called only when pay failed.
---Returns { action = 'complete'|'refunded'|'warning', reason, log }. 'warning' = goods lost, needs owner attention.
function M.sellOutcome(payOk, payErr, restore, who)
    if payOk then return { action = 'complete' } end
    local reason = tostring(payErr or 'pay_failed')
    local ok, err = restore()
    if ok then
        return { action = 'refunded', reason = reason,
            log = ('sell: pay failed (%s), item given back'):format(reason) }
    end
    who = who or {}
    return { action = 'warning', reason = reason,
        log = ('WARNING sell: pay failed (%s) AND item restore failed (%s): citizenid=%s item=%s qty=%s'):format(
            reason, tostring(err or 'restore_failed'), tostring(who.citizenid), tostring(who.item), tostring(who.qty)) }
end

---Admin `fh_fence_settle <serverId>` argument parsing: one whole positive server id.
---@return number|nil target, string|nil err
function M.parseSettleArgs(args)
    args = type(args) == 'table' and args or {}
    local t = tonumber(args[1])
    if not t or t ~= t or t <= 0 or t % 1 ~= 0 or t == math.huge or args[2] ~= nil then return nil, 'fh_bad_target' end
    return math.tointeger(t) or t
end

---Player-facing text per refusal code (client menu). Covers every core B7 charge / pay error so none shows as a raw
---code; a code not listed shows as "Refused: <code>". Nothing was taken for any buy refusal listed here.
M.messages = {
    -- charge (buy) / pay (sell), core B7
    fh_insufficient_funds = "You can't afford that.",
    fh_charge_busy = 'Your last payment is still going through. Try again in a moment.',
    ledger_failed = 'The fence could not write the deal down. Nothing was taken; try again later.',
    removemoney_refused = 'Your payment was refused. Nothing was taken.',
    addmoney_refused = 'The fence could not pay you. Your goods were given back.',
    no_player = 'Your character is not loaded.',
    player_changed = 'Your character changed during the deal. Nothing was taken.',
    charge_unavailable = 'The fence is not taking payment right now.',
    -- trade
    out_of_range = 'Step closer to the fence.',
    no_room = 'You have no room to carry that.',
    fence_busy = 'The fence is still handling your last deal.',
    fence_pending = 'The fence is holding goods from an earlier deal. Ask an admin.',
    not_enough_items = "You don't have that to sell.",
}

if _G.GetCurrentResourceName then _G.FhFenceLogic = M end
return M

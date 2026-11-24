-- Pure regional price model (spec L6). No natives, no DB, no os.time: the caller passes `now` (unix seconds) and the
-- config, so every result is deterministic given (cfg, state, region, item, now). Specced in spec/trade_prices_spec.lua.
--
-- unit price = base * regionFactor * (1 + gain*shortage) * (1 + wobble) * (1 - maxDrop*saturation), floored at base*minMultiplier
--  * shortage   0..max, set by events (setShortage), decays toward 0 (baseline) with a half-life, eased by selling into it
--  * wobble     slow seeded value-noise in +-amplitude (a pure function of seed/region/item/clock), the "drift"
--  * saturation 0..1, raised by selling into a region, decays toward 0 with a half-life (recovery)
-- State is lazy: entries store the value at `t` and are decayed to `now` when read. Quotes never mutate.
local M = {}

local function finite(n) return type(n) == 'number' and n == n and n > -math.huge and n < math.huge end
local function clamp(v, lo, hi) if v < lo then return lo elseif v > hi then return hi end return v end

-- Region validation is injected so this file stays free of fh_core: the server and the spec set this to
-- fh_core's regions.isKnownRegion. Default accepts any non-empty string.
M.isKnownRegion = function(id) return type(id) == 'string' and id ~= '' end

function M.newState() return { entries = {} } end

local function key(region, item) return region .. '|' .. item end

-- 32-bit FNV-1a over seed|region|item|bucket, then mixed -> [-1, 1]
local function noiseAt(seed, region, item, bucket)
    local h = 2166136261
    local s = tostring(seed) .. '|' .. region .. '|' .. item .. '|' .. tostring(bucket)
    for i = 1, #s do h = ((h ~ s:byte(i)) * 16777619) & 0xFFFFFFFF end
    h = ((h ~ (h >> 15)) * 2246822519) & 0xFFFFFFFF
    h = (h ~ (h >> 13)) & 0xFFFFFFFF
    return (h / 0xFFFFFFFF) * 2 - 1
end

---Drift in [-amplitude, amplitude]: smoothstep interpolation between periodSeconds-spaced noise knots.
function M.wobble(cfg, region, item, now)
    local w = cfg.wobble
    if not w or not w.amplitude or w.amplitude == 0 then return 0 end
    local x = now / w.periodSeconds
    local b = math.floor(x)
    local f = x - b
    f = f * f * (3 - 2 * f)
    local a, c = noiseAt(cfg.seed or 0, region, item, b), noiseAt(cfg.seed or 0, region, item, b + 1)
    return (a + (c - a) * f) * w.amplitude
end

local function decay(v, dt, half)
    if dt <= 0 or not half or half <= 0 then return v end
    return v * 0.5 ^ (dt / half)
end

-- decayed copy of the entry at `now` (or a fresh zero entry)
local function view(cfg, state, region, item, now)
    local e = state.entries[key(region, item)]
    if not e then return { region = region, item = item, shortage = 0, saturation = 0, t = now } end
    local dt = now - e.t
    return {
        region = region, item = item,
        shortage = decay(e.shortage, dt, cfg.shortage.halfLifeSeconds),
        saturation = decay(e.saturation, dt, cfg.saturation.halfLifeSeconds),
        t = math.max(now, e.t),
    }
end

local function check(cfg, region, item)
    if not cfg.goods[item] then return 'unknown_item' end
    if not M.isKnownRegion(region) then return 'unknown_region' end
end

local function baseline(cfg, region, item)
    local f = cfg.regionFactor and cfg.regionFactor[region] and cfg.regionFactor[region][item] or 1
    return cfg.goods[item].base * f
end

local function unitPrice(cfg, region, item, e, now)
    local mult = (1 + cfg.shortage.gain * e.shortage) * (1 + M.wobble(cfg, region, item, now))
        * (1 - cfg.saturation.maxDrop * e.saturation)
    return baseline(cfg, region, item) * math.max(mult, cfg.minMultiplier or 0)
end

local function round2(v) return math.floor(v * 100 + 0.5) / 100 end

---Current unit price at `region` for `item`. @return number|nil price, table|string detail (breakdown, or error code)
function M.quote(cfg, state, region, item, now)
    local err = check(cfg, region, item)
    if err then return nil, err end
    if not finite(now) then return nil, 'invalid_time' end
    local e = view(cfg, state, region, item, now)
    return round2(unitPrice(cfg, region, item, e, now)), {
        base = baseline(cfg, region, item), shortage = e.shortage, saturation = e.saturation,
        wobble = M.wobble(cfg, region, item, now),
    }
end

---Set the shortage level (0..max) for a region/item (event or admin). Level 0 = no shortage.
function M.setShortage(cfg, state, region, item, level, now)
    local err = check(cfg, region, item)
    if err then return false, err end
    if not finite(level) or not finite(now) then return false, 'invalid_amount' end
    local e = view(cfg, state, region, item, now)
    e.shortage = clamp(level, 0, cfg.shortage.max)
    state.entries[key(region, item)] = e
    return true
end

---Seed cfg.initialShortages into regions/items that have NO entry in `state` (idea-762). Call it right after the
---persisted rows were loaded with loadRow: an entry then means a persisted row exists, i.e. the region/item was
---touched before (sold into, set by an admin/event, or seeded on an earlier start), even if its shortage is now 0.
---Such entries are never changed, so a cleared shortage is not re-seeded on restart. Unknown goods/regions and bad
---levels are skipped. @return table[] seeded list of { region, item } (the caller persists them)
function M.seedShortages(cfg, state, now)
    local seeded = {}
    for _, e in ipairs(cfg.initialShortages or {}) do
        if type(e) == 'table' and type(e.region) == 'string' and type(e.item) == 'string'
            and state.entries[key(e.region, e.item)] == nil
            and M.setShortage(cfg, state, e.region, e.item, e.level, now) then
            seeded[#seeded + 1] = { region = e.region, item = e.item }
        end
    end
    return seeded
end

---Items currently in shortage at `region` (level >= cfg.shortage.threshold), worst first.
---@return table[] list of { item, level, multiplier, price }
function M.shortages(cfg, state, region, now)
    local out = {}
    if not M.isKnownRegion(region) or not finite(now) then return out end
    for item in pairs(cfg.goods) do
        local e = view(cfg, state, region, item, now)
        if e.shortage >= cfg.shortage.threshold then
            out[#out + 1] = {
                item = item, level = e.shortage, multiplier = 1 + cfg.shortage.gain * e.shortage,
                price = round2(unitPrice(cfg, region, item, e, now)),
            }
        end
    end
    table.sort(out, function(a, b) if a.level ~= b.level then return a.level > b.level end return a.item < b.item end)
    return out
end

local function plan(cfg, region, item, amount, e, now)
    local total, sat, short = 0, e.saturation, e.shortage
    for _ = 1, amount do
        total = total + unitPrice(cfg, region, item, { shortage = short, saturation = sat }, now)
        sat = math.min(1, sat + 1 / cfg.saturation.capacityUnits)
        short = math.max(0, short - cfg.shortage.reliefPerUnit)
    end
    return math.floor(total), sat, short
end

local function validateSell(cfg, state, region, item, amount, now)
    local err = check(cfg, region, item)
    if err then return err end
    if not finite(now) then return 'invalid_time' end
    if type(amount) ~= 'number' or amount % 1 ~= 0 or amount < 1 or amount > cfg.maxSellPerTx then return 'invalid_amount' end
end

---What selling `amount` would pay (whole dollars; the price falls per unit sold). Does not mutate.
---@return integer|nil total, string? err
function M.previewSell(cfg, state, region, item, amount, now)
    local err = validateSell(cfg, state, region, item, amount, now)
    if err then return nil, err end
    local total = plan(cfg, region, item, amount, view(cfg, state, region, item, now), now)
    if total < 1 then return nil, 'worthless' end
    return total
end

---Commit a sale into the state (saturation up, shortage eased). Same arithmetic as previewSell.
---@return integer|nil total, string? err
function M.sell(cfg, state, region, item, amount, now)
    local err = validateSell(cfg, state, region, item, amount, now)
    if err then return nil, err end
    local e = view(cfg, state, region, item, now)
    local total, sat, short = plan(cfg, region, item, amount, e, now)
    if total < 1 then return nil, 'worthless' end
    e.saturation, e.shortage = sat, short
    state.entries[key(region, item)] = e
    return total
end

---Rows for persistence: { region_id, item, shortage, saturation, updated_at }, sorted.
function M.toRows(state)
    local rows = {}
    for _, e in pairs(state.entries) do
        rows[#rows + 1] = { region_id = e.region, item = e.item, shortage = e.shortage, saturation = e.saturation, updated_at = e.t }
    end
    table.sort(rows, function(a, b) if a.region_id ~= b.region_id then return a.region_id < b.region_id end return a.item < b.item end)
    return rows
end

---Load one persisted row (ignored when the good/region is no longer known or values are bad).
function M.loadRow(cfg, state, row)
    if type(row) ~= 'table' or not cfg.goods[row.item] or not M.isKnownRegion(row.region_id) then return false end
    local s, a, t = tonumber(row.shortage), tonumber(row.saturation), tonumber(row.updated_at)
    if not (finite(s) and finite(a) and finite(t)) then return false end
    state.entries[key(row.region_id, row.item)] = {
        region = row.region_id, item = row.item,
        shortage = clamp(s, 0, cfg.shortage.max), saturation = clamp(a, 0, 1), t = t,
    }
    return true
end

if GetCurrentResourceName then
    FhTradePrices = M
else
    return M
end

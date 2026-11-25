-- fh_tailor pure logic: config/catalog validation, per-shop stock filter (town size + regional tier + sex), buy checks,
-- look (outfit + single items) validation, item list encoding, per-citizenid lock, charge-with-busy-retry and the
-- player-facing message map. No FiveM globals (shared script: never read `...`, it is a number in FXServer).
local M = {}

local function isNum(v) return type(v) == 'number' and v == v and v ~= math.huge and v ~= -math.huge end
local function isInt(v) return isNum(v) and v == math.floor(v) end
local function isStr(v) return type(v) == 'string' and v ~= '' end

M.MAX_ID = 64     -- fh_tailor_owned.entry_id varchar(64)
M.MAX_SOURCE = 32 -- fh_tailor_owned.source varchar(32)
M.MAX_LABEL = 32  -- fh_tailor_outfits.label varchar(32)
M.MAX_ITEMS_TEXT = 512 -- worn_items / items varchar(512)
M.MAX_TIER = 3

local SEXES = { male = true, female = true, any = true }
local KINDS = { outfit = true, item = true }

---Catalog / shop ids: lowercase letters, digits, underscore; no comma (item lists are comma-joined).
function M.validId(s)
    return type(s) == 'string' and #s <= M.MAX_ID and s:match('^[a-z0-9_]+$') ~= nil
end

---Same rule as fh_economy's FhLedgerLogic.validCitizenid: [%w_-], at most 50, not all digits (a mistyped server id).
function M.validCitizenid(s)
    return type(s) == 'string' and #s <= 50 and s:match('^[%w_%-]+$') ~= nil and s:match('^%d+$') == nil
end

local RESERVED_SOURCES = { buy = true, starter = true }

---Grant source tag, e.g. 'hunting:legendary_bear' or 'quests:q_marshal_3'. Refuses internal sources ('buy', 'starter').
function M.validSource(s)
    return type(s) == 'string' and #s <= M.MAX_SOURCE and not RESERVED_SOURCES[s] and s:match('^[%w_:%-%.]+$') ~= nil
end

---Price in whole cents (5, 5.0, 12.5, 1.13), > 0. Same idea as fh_economy toCents: no sub-cent part.
function M.validPrice(p)
    if not isNum(p) or p <= 0 then return false end
    local c = p * 100
    return math.abs(c - math.floor(c + 0.5)) < 1e-6
end

---rsg-core charinfo.gender (0 = male, 1 = female; rsg-character sv_appearance.lua) -> 'male' | 'female' | nil.
function M.sexOf(gender)
    local g = tonumber(gender)
    if g == 0 then return 'male' end
    if g == 1 then return 'female' end
    return nil
end

function M.sexFits(entry, sex)
    return entry.sex == 'any' or (sex ~= nil and entry.sex == sex)
end

local function validEntry(id, e, shops)
    if type(e) ~= 'table' then return false end
    if e.id ~= id or not M.validId(id) then return false end
    if not isStr(e.label) or not SEXES[e.sex] or not KINDS[e.kind] then return false end
    if e.kind == 'outfit' and not (isInt(e.preset) and e.preset >= 0) then return false end
    if e.kind == 'item' and not (isInt(e.component) or isStr(e.component)) then return false end
    if e.earned_only ~= nil and type(e.earned_only) ~= 'boolean' then return false end
    if not e.earned_only and not M.validPrice(e.price) then return false end
    if e.price ~= nil and not M.validPrice(e.price) then return false end
    if not (isInt(e.min_tier) and e.min_tier >= 1 and e.min_tier <= M.MAX_TIER) then return false end
    if e.shops ~= nil and e.size ~= nil then return false end -- one gating rule per entry
    if e.size ~= nil and not (isInt(e.size) and e.size >= 1) then return false end
    if e.shops ~= nil then
        if type(e.shops) ~= 'table' or #e.shops == 0 then return false end
        for _, s in ipairs(e.shops) do if not shops[s] then return false end end
    end
    return true
end

---@param isKnownRegion fun(id:any):boolean|nil  FhRegions.isKnownRegion (shop region check); nil skips it
---@return boolean ok, string? reason
function M.validateConfig(cfg, isKnownRegion)
    if type(cfg) ~= 'table' then return false, 'bad_config' end
    if type(cfg.FittedOutfits) ~= 'boolean' then return false, 'bad_FittedOutfits' end
    for _, k in ipairs({ 'maxItems', 'maxSavedOutfits', 'chargeRetries', 'chargeRetryMs', 'lockWaitMs' }) do
        if not (isInt(cfg[k]) and cfg[k] >= 0) then return false, 'bad_' .. k end
    end
    if cfg.maxSavedOutfits < 1 or cfg.maxSavedOutfits > 255 then return false, 'bad_maxSavedOutfits' end
    -- worn/saved items are comma-joined into varchar(512)
    if cfg.actionDebounceMs ~= nil and not (isInt(cfg.actionDebounceMs) and cfg.actionDebounceMs >= 0) then
        return false, 'bad_actionDebounceMs'
    end
    if cfg.maxItems * (M.MAX_ID + 1) > M.MAX_ITEMS_TEXT then return false, 'bad_maxItems' end
    if type(cfg.shops) ~= 'table' then return false, 'bad_shops' end
    for id, s in pairs(cfg.shops) do
        local ok = type(s) == 'table' and s.id == id and M.validId(id) and isStr(s.label) and isInt(s.size) and s.size >= 1
            and type(s.coords) == 'table' and isNum(s.coords.x) and isNum(s.coords.y) and isNum(s.coords.z)
            and isNum(s.radius) and s.radius > 0 and isStr(s.region_id)
            and (isKnownRegion == nil or isKnownRegion(s.region_id) == true)
        if not ok then return false, 'bad_shop_' .. tostring(id) end
    end
    if type(cfg.catalog) ~= 'table' then return false, 'bad_catalog' end
    for id, e in pairs(cfg.catalog) do
        if not validEntry(id, e, cfg.shops) then return false, 'bad_entry_' .. tostring(id) end
    end
    if type(cfg.starter) ~= 'table' then return false, 'bad_starter' end
    for _, sex in ipairs({ 'male', 'female' }) do
        local list = cfg.starter[sex]
        if type(list) ~= 'table' or #list == 0 then return false, 'bad_starter_' .. sex end
        for i, sid in ipairs(list) do
            local e = cfg.catalog[sid]
            if not e or not M.sexFits(e, sex) or (i == 1 and e.kind ~= 'outfit') then
                return false, 'bad_starter_' .. sex
            end
        end
    end
    return true
end

-- ---------------------------------------------------------------- stock

---Stocked at this shop by size / shop list (no tier or sex check). earned_only entries are never for sale.
function M.stocked(entry, shop)
    if type(entry) ~= 'table' or type(shop) ~= 'table' or entry.earned_only then return false end
    if entry.shops then
        for _, s in ipairs(entry.shops) do if s == shop.id then return true end end
        return false
    end
    return (entry.size or 1) <= (shop.size or 0)
end

---Why this entry can't be bought here, before any money moves. Order: what the shop has, then who is buying.
---@return boolean ok, string? code  earned_only | not_stocked | wrong_sex | tier_too_low | already_owned
function M.checkBuy(entry, shop, sex, tier, owned)
    if entry.earned_only then return false, 'earned_only' end
    if not M.stocked(entry, shop) then return false, 'not_stocked' end
    if not M.sexFits(entry, sex) then return false, 'wrong_sex' end
    if not isNum(tier) or tier < entry.min_tier then return false, 'tier_too_low' end
    if owned and owned[entry.id] then return false, 'already_owned' end
    return true
end

---Visible stock of a shop for one character: stocked, fits the sex, min_tier <= tier. Sorted by tier, price, id.
---owned (id -> source) marks rows the character already has. Rows are copies (safe to send to a client).
---@return table[] rows { id, label, kind, sex, price, min_tier, owned }
function M.stockFor(cfg, shop, tier, sex, owned)
    local rows = {}
    if not isNum(tier) then return rows end
    for id, e in pairs(cfg.catalog) do
        if M.stocked(e, shop) and M.sexFits(e, sex) and e.min_tier <= tier then
            rows[#rows + 1] = { id = id, label = e.label, kind = e.kind, sex = e.sex, price = e.price,
                min_tier = e.min_tier, owned = (owned and owned[id]) and true or false }
        end
    end
    table.sort(rows, function(a, b)
        if a.min_tier ~= b.min_tier then return a.min_tier < b.min_tier end
        if a.price ~= b.price then return a.price < b.price end
        return a.id < b.id
    end)
    return rows
end

-- ---------------------------------------------------------------- looks

---Comma-joined item ids <-> list. decode drops blanks; ids were validated (validId: no comma) on the way in.
function M.encodeItems(items)
    return table.concat(items or {}, ',')
end

function M.decodeItems(s)
    local out = {}
    if type(s) ~= 'string' then return out end
    for id in s:gmatch('[^,]+') do out[#out + 1] = id end
    return out
end

---A look = one owned outfit + up to cfg.maxItems owned single items, all fitting the character's sex.
---@return table|nil look { outfit = id, items = { id, ... } }, string? code
---  unknown_entry | not_owned | not_outfit | not_item | wrong_sex | too_many_items | duplicate_item
function M.validateLook(cfg, owned, sex, outfitId, itemIds)
    local o = type(outfitId) == 'string' and cfg.catalog[outfitId] or nil
    if not o then return nil, 'unknown_entry' end
    if o.kind ~= 'outfit' then return nil, 'not_outfit' end
    if not M.sexFits(o, sex) then return nil, 'wrong_sex' end
    if not (owned and owned[outfitId]) then return nil, 'not_owned' end
    if itemIds == nil then itemIds = {} end
    if type(itemIds) ~= 'table' then return nil, 'not_item' end
    local n = 0
    for _ in pairs(itemIds) do n = n + 1 end
    if n ~= #itemIds then return nil, 'not_item' end -- a plain list only
    if n > cfg.maxItems then return nil, 'too_many_items' end
    local seen, items = {}, {}
    for i, id in ipairs(itemIds) do
        local e = type(id) == 'string' and cfg.catalog[id] or nil
        if not e then return nil, 'unknown_entry' end
        if e.kind ~= 'item' then return nil, 'not_item' end
        if not M.sexFits(e, sex) then return nil, 'wrong_sex' end
        if not owned[id] then return nil, 'not_owned' end
        if seen[id] then return nil, 'duplicate_item' end
        seen[id] = true
        items[i] = id
    end
    return { outfit = outfitId, items = items }
end

---Saved / worn look as read from the DB: still valid now (catalog may have changed, ownership re-checked)?
---@return table|nil look, string? code
function M.lookFromRow(cfg, owned, sex, outfitId, itemsText)
    if outfitId == nil then return nil, 'no_look' end
    return M.validateLook(cfg, owned, sex, outfitId, M.decodeItems(itemsText))
end

-- ---------------------------------------------------------------- lock + charge

---Per-key mutex for a cooperative scheduler (one per citizenid; same shape as FhHandsLogic.withLock). Nothing yields
---between the check and the set, so two coroutines can never both hold a key. opts = { wait = fn (yields),
---clock = fn -> ms, timeoutMs = n|nil }: timeoutMs nil = try once. fn runs in pcall; the key is always released.
---@return boolean ok, any ... fn's results on success; false, 'busy' | false, 'error', msg on failure
function M.withLock(locks, key, opts, fn, ...)
    if locks[key] then
        if not opts.timeoutMs then return false, 'busy' end
        local deadline = opts.clock() + opts.timeoutMs
        while locks[key] do
            if opts.clock() >= deadline then return false, 'busy' end
            opts.wait()
        end
    end
    locks[key] = true
    local res = table.pack(pcall(fn, ...))
    locks[key] = nil
    if not res[1] then return false, 'error', tostring(res[2]) end
    return true, table.unpack(res, 2, res.n)
end

---Charge with a bounded retry on fh_charge_busy ONLY: B7 takes nothing on busy (another charge for this character is
---in flight), so trying again can never charge twice. Every other refusal is returned at once (nothing taken either).
---alive() is checked before EVERY attempt, with no yield between it and the charge call: a player who left or switched
---character is never charged (fh_economy charges whichever character src has loaded at call time).
---@return boolean ok, string? err, integer attempts
function M.chargeWithRetry(charge, alive, wait, retries, retryMs)
    local attempts, err = 0, nil
    for i = 1, retries + 1 do
        local live, why = alive()
        if not live then return false, why or 'player_changed', attempts end
        attempts = attempts + 1
        local ok, e = charge()
        if ok == true then return true, nil, attempts end
        err = type(e) == 'string' and e or 'charge_refused'
        if err ~= 'fh_charge_busy' or i > retries then break end
        wait(retryMs)
    end
    return false, err, attempts
end

---Player-facing text per refusal code (T2 menus / T4 catalog screen). Covers every core B7 charge error so none shows
---as a raw code; a code not listed shows as "Refused: <code>". Nothing was taken for any buy refusal listed here.
M.messages = {
    -- charge, core B7 (fh_economy.charge) and the fh_tailor wrapper
    fh_insufficient_funds = "You can't afford that.",
    fh_charge_busy = 'Your last payment is still going through. Try again in a moment.',
    ledger_failed = 'The shop could not write the sale down. Nothing was taken; try again later.',
    removemoney_refused = 'Your payment was refused. Nothing was taken.',
    no_player = 'Your character is not loaded.',
    player_changed = 'Your character changed during the sale. Nothing was taken.',
    invalid_amount = 'That price is wrong. Nothing was taken; tell an admin.',
    amount_too_large = 'That price is too high to take. Nothing was taken; tell an admin.',
    invalid_reason = 'The sale could not be booked. Nothing was taken; tell an admin.',
    unknown_region = 'This shop is not set up right. Nothing was taken; tell an admin.',
    charge_refused = 'Your payment was refused. Nothing was taken.',
    charge_unavailable = 'The shop could not confirm your payment. You keep the clothes; tell an admin if you were not charged.',
    -- shop / ownership
    not_ready = 'The tailor is not open yet. Try again in a moment.',
    tailor_busy = 'The tailor is still handling your last request.',
    tailor_error = 'Something went wrong. Nothing was taken; try again.',
    db_failed = 'The tailor could not write that down. Nothing was taken; try again later.',
    unknown_shop = 'There is no shop here.',
    unknown_entry = 'That is not in the catalog.',
    out_of_range = 'Step closer to the counter.',
    earned_only = 'That cannot be bought. It has to be earned.',
    not_stocked = 'This shop does not carry that.',
    wrong_sex = 'That is not cut for you.',
    tier_too_low = 'They will not sell you that yet. Earn more standing in this region.',
    tier_unavailable = 'The shop cannot check your standing right now. Try again later.',
    already_owned = 'You already own that.',
    -- wardrobe
    not_owned = 'You do not own that.',
    not_outfit = 'Pick a full outfit first.',
    not_item = 'That cannot be worn over an outfit.',
    too_many_items = 'That is too many pieces over one outfit.',
    duplicate_item = 'You listed the same piece twice.',
    bad_slot = 'There is no such wardrobe slot.',
    empty_slot = 'That wardrobe slot is empty.',
    bad_label = 'That name is not allowed.',
    too_fast = 'Slow down a moment.',
    bad_src = 'Unknown player.',
    not_at_wardrobe = 'You need to be at a tailor or your homestead wardrobe.',
    -- grant (other resources)
    invalid_citizenid = 'Invalid character id.',
    unknown_citizenid = 'No such character.',
    invalid_source = 'Invalid grant source.',
}

---@return string text
function M.message(code)
    return M.messages[code] or ('Refused: ' .. tostring(code))
end

-- ---------------------------------------------------------------- player-action guards (server)

---Per-key debounce. allow(key) is false when the last allowed call for this key was < ms ago (the refused call does
---not extend the window). ms <= 0 disables it. forget(key) drops the entry (player left).
function M.newDebounce(ms, clock)
    local last = {}
    return {
        allow = function(key)
            key = tonumber(key)
            if not key then return false end
            if not (isInt(ms) and ms > 0) then return true end
            local now = clock()
            local prev = last[key]
            if prev ~= nil and now >= prev and now - prev < ms then return false end
            last[key] = now
            return true
        end,
        forget = function(key) key = tonumber(key); if key then last[key] = nil end end,
    }
end

---Player-action wrappers around the core: exactly the guards a player's net event gets (range, debounce), so a relay
---(another resource forwarding a player action) cannot skip them. deps = { core, shops, inShopRange(src, shop),
---inWardrobeRange(src), debounce }. Every function returns the core's `ok, res|code`.
function M.makeActions(deps)
    local core = deps.core
    ---@return string|nil code, number|nil src (normalized with tonumber so debounce keys match forget())
    local function wardrobeGate(src)
        src = tonumber(src)
        if not src then return 'bad_src' end
        if not deps.inWardrobeRange(src) then return 'not_at_wardrobe', src end
        if not deps.debounce.allow(src) then return 'too_fast', src end
        return nil, src
    end
    local A = {}
    -- buy range + the per-character lock live in the core; no debounce (a refused buy takes nothing).
    function A.actBuy(src, shopId, entryId) return core.buy(src, shopId, entryId) end
    function A.actStock(src, shopId)
        local shop = type(shopId) == 'string' and deps.shops[shopId] or nil
        if not shop then return false, 'unknown_shop' end
        if not deps.inShopRange(src, shop) then return false, 'out_of_range' end
        return core.getStock(src, shopId)
    end
    function A.actWardrobe(src)
        if not deps.inWardrobeRange(src) then return false, 'not_at_wardrobe' end
        return core.getWardrobe(src)
    end
    function A.actEquip(src, outfitId, items)
        local code, nsrc = wardrobeGate(src)
        if code then return false, code end
        return core.equip(nsrc, outfitId, items)
    end
    function A.actSave(src, slot, label, outfitId, items)
        local code, nsrc = wardrobeGate(src)
        if code then return false, code end
        return core.saveOutfit(nsrc, slot, label, outfitId, items)
    end
    function A.actWear(src, slot)
        local code, nsrc = wardrobeGate(src)
        if code then return false, code end
        return core.wearSaved(nsrc, slot)
    end
    return A
end

-- ---------------------------------------------------------------- client apply + menu helpers

---Resolve a worn look into the ped apply plan ({ outfit, preset, components }) when cfg.FittedOutfits is on.
---When FittedOutfits is off (or the look is missing/invalid), returns nil so the client applies nothing.
---`force = true` (UI preview only, never persisted) resolves the look even with the flag off, and is strict: any
---unknown / wrong-kind item id refuses the look (nil). The normal path skips such items.
---@return table|nil plan { outfit = id, preset = int, components = { hash|name, ... } }
function M.resolveApply(cfg, look, force)
    if type(cfg) ~= 'table' or (cfg.FittedOutfits ~= true and force ~= true) then return nil end
    if type(look) ~= 'table' or type(look.outfit) ~= 'string' then return nil end
    local catalog = cfg.catalog
    if type(catalog) ~= 'table' then return nil end
    local o = catalog[look.outfit]
    if type(o) ~= 'table' or o.kind ~= 'outfit' or not (isInt(o.preset) and o.preset >= 0) then return nil end
    local components = {}
    if type(look.items) == 'table' then
        for _, id in ipairs(look.items) do
            local e = type(id) == 'string' and catalog[id] or nil
            if type(e) == 'table' and e.kind == 'item' and (isInt(e.component) or isStr(e.component)) then
                components[#components + 1] = e.component
            elseif force == true then
                return nil -- preview is strict: an unknown or wrong-kind item refuses the whole look
            end
        end
    end
    return { outfit = look.outfit, preset = o.preset, components = components }
end

---Toggle a single item id in a worn items list without mutating the input.
---@return string[]|nil nextItems, string action ('removed' | 'added' | 'full')
function M.toggleItem(items, itemId, maxItems)
    local out, removed = {}, false
    for _, id in ipairs(items or {}) do
        if id == itemId then
            removed = true
        else
            out[#out + 1] = id
        end
    end
    if removed then return out, 'removed' end
    if #out >= (maxItems or 0) then return nil, 'full' end
    out[#out + 1] = itemId
    return out, 'added'
end

---Format a price for display in menus ($12 or $12.50).
function M.formatPrice(price)
    if not isNum(price) then return '$0' end
    if price == math.floor(price) then return ('$%d'):format(price) end
    return ('$%.2f'):format(price)
end

---3D distance check between two { x, y, z } tables / vectors.
function M.withinDistance(a, b, radius)
    if a == nil or b == nil or not isNum(radius) or radius < 0 then return false end
    local dx, dy, dz = (a.x or 0) - (b.x or 0), (a.y or 0) - (b.y or 0), (a.z or 0) - (b.z or 0)
    return (dx * dx + dy * dy + dz * dz) <= (radius * radius)
end

if _G.GetCurrentResourceName then _G.FhTailorLogic = M end
return M

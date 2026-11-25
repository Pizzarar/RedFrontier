-- fh_tailor core: buy / grant / starter / equip / saved outfits. Pure Lua: every FiveM, DB and export call comes in
-- through `deps`, so spec/tailor_spec.lua drives this exact code with fakes that yield (coroutines).
--
-- Invariants (Tier A, money path):
--  1. One operation per citizenid at a time (FhTailorLogic.withLock, keyed by citizenid, in memory). buy never waits:
--     a second buy while one is in flight gets 'tailor_busy' at once. grant / load / equip wait up to cfg.lockWaitMs.
--  2. Ownership = rows in fh_tailor_owned (PK citizenid + entry_id). Every grant is INSERT IGNORE: 1 row = new,
--     0 = already owned. The PK is the DB-level guard against a double grant, the lock the guard against a double charge.
--  3. Buy: validate (shop, range, sex, stock, earned_only, regional tier, not owned) -> CLAIM the row (source 'buy')
--     -> charge (fh_economy B7) -> keep. The row is claimed BEFORE the money moves, so a retry or a concurrent buy
--     (even across an fh_tailor restart that lost the in-memory lock) sees it owned and is never charged again.
--     Charge refusals (every B7 code: nothing was taken) delete our own claim again (only a 'buy' row, under the lock).
--     fh_charge_busy is retried inside the buy (cfg.chargeRetries, B7 took nothing), with the character re-checked
--     before every attempt (fh_economy charges whichever character src has loaded at call time).
--     charge_unavailable (the export threw: outcome unknown) KEEPS the claim, like fh_hands: never charged twice, at
--     worst the clothes were free (logged ALERT with the amount; the fh_ledger charge row tells an admin).
--     A crash between claim and charge also leaves the clothes owned unpaid: the player's favour, never a double charge.
--  4. grant(citizenid, id, source) is idempotent (invariant 2) and works offline. Starter set: once per character
--     (fh_tailor_state.starter_at), one transaction (deps.db.grantStarter), INSERT IGNORE rows: re-running is a no-op.
--  5. equip / saved outfits only accept owned ids that fit the character's sex (FhTailorLogic.validateLook). Applying
--     the look on the ped is behind cfg.FittedOutfits (T2, after @spikes S1 PASS); with it off only the choice persists.
local M = {}

---deps: ready() -> bool; citizenOf(src) -> cid|nil (no yield); sexOf(src) -> 'male'|'female'|nil (no yield);
---onlineSrc(cid) -> src|nil (no yield); inRange(src, shop) -> bool (no yield); tierOf(src, region_id) -> number|nil;
---charge(src, amount, reason, region_id) -> ok, err; wait(ms); clock() -> ms; now() -> seconds; emit(name, payload);
---log(msg); db = { loadOwned(cid) -> rows|nil, loadState(cid) -> row|false|nil, loadSaved(cid) -> rows|nil,
---insertOwned(cid, id, source, now) -> 1|0|nil, deleteOwned(cid, id, source) -> n|nil,
---grantStarter(cid, ids, wornOutfit, now) -> bool, saveWorn(cid, outfit, itemsText) -> bool,
---saveSlot(cid, slot, label, outfit, itemsText) -> bool, citizenSex(cid) -> exists(bool|nil), sex|nil }.
---DB calls return nil on failure (never throw); a throw anywhere is still caught (tailor_error) and frees the lock.
function M.new(cfg, logic, deps)
    local db = deps.db
    local locks = {}   -- citizenid -> true while an operation for that character runs
    local entries = {} -- citizenid -> { cid, src, sex, owned = { [id] = source }, worn = look|nil, saved = { [slot] = s } }
    local C = { entries = entries, locks = locks }
    local WAIT = { wait = function() deps.wait(0) end, clock = deps.clock, timeoutMs = cfg.lockWaitMs }
    local TRY = { wait = function() deps.wait(0) end, clock = deps.clock }

    local function log(fmt, ...) deps.log(fmt:format(...)) end

    ---Run fn under the citizenid's lock. busy -> 'tailor_busy'; a throw -> 'tailor_error' (logged).
    local function locked(cid, opts, op, fn, ...)
        local res = table.pack(logic.withLock(locks, cid, opts, fn, ...))
        if not res[1] then
            if res[2] == 'error' then
                log('ERROR %s citizenid=%s: %s', op, tostring(cid), tostring(res[3]))
                return false, 'tailor_error'
            end
            return false, 'tailor_busy'
        end
        return table.unpack(res, 2, res.n)
    end

    local function aliveFn(src, cid)
        return function()
            local now = deps.citizenOf(src)
            if now == cid then return true end
            return false, now == nil and 'no_player' or 'player_changed'
        end
    end

    -- ------------------------------------------------------------ load + starter

    ---Caller holds the lock. Reads owned / state / saved, re-checks the character after the reads (they yield),
    ---grants the starter set once (invariant 4) and caches the entry.
    ---@return table|nil entry, string? err
    local function load(src, cid)
        local rows, state, saved = db.loadOwned(cid), db.loadState(cid), db.loadSaved(cid)
        if rows == nil or state == nil or saved == nil then return nil, 'db_failed' end
        local live, why = aliveFn(src, cid)()
        if not live then return nil, why end
        local sex = deps.sexOf(src)
        local e = { cid = cid, src = src, sex = sex, owned = {}, worn = nil, saved = {} }
        for _, r in ipairs(rows) do
            if type(r) == 'table' and type(r.entry_id) == 'string' then e.owned[r.entry_id] = r.source or 'unknown' end
        end
        local wornOutfit, wornItems = state and state.worn_outfit or nil, state and state.worn_items or ''

        if (state == false or state.starter_at == nil) and sex then
            local ids = cfg.starter[sex]
            if db.grantStarter(cid, ids, ids[1], deps.now()) then
                for _, id in ipairs(ids) do e.owned[id] = e.owned[id] or 'starter' end
                if wornOutfit == nil then wornOutfit, wornItems = ids[1], '' end -- DB: IFNULL(worn_outfit, ids[1])
                log('starter set granted: citizenid=%s sex=%s ids=%s', cid, sex, table.concat(ids, ','))
            else
                log('WARNING starter grant failed: citizenid=%s (retried on next load)', cid)
            end
            -- grantStarter yields: re-check the player before caching entries[cid] or evicting another entry on src
            local live2, why2 = aliveFn(src, cid)()
            if not live2 then return nil, why2 end
        elseif state == false or state.starter_at == nil then
            log('WARNING starter skipped, character sex unknown: citizenid=%s (retried on next load)', cid)
        end

        if wornOutfit ~= nil then
            local look, lwhy = logic.lookFromRow(cfg, e.owned, sex, wornOutfit, wornItems)
            if look then e.worn = look else log('worn look dropped (%s): citizenid=%s outfit=%s', lwhy, cid, tostring(wornOutfit)) end
        end
        for _, r in ipairs(saved) do
            local slot = tonumber(r.slot)
            if slot and slot >= 1 and slot <= cfg.maxSavedOutfits then
                local look = logic.lookFromRow(cfg, e.owned, sex, r.outfit_id, r.items)
                e.saved[slot] = { label = r.label or '', outfit = r.outfit_id, items = logic.decodeItems(r.items),
                    valid = look ~= nil }
            end
        end
        for other, oe in pairs(entries) do -- a src carries one character: drop anything still bound to it
            if oe.src == src and other ~= cid then entries[other] = nil end
        end
        entries[cid] = e
        return e
    end

    ---Caller holds the lock: the cached entry for this src, or a fresh load.
    local function ensure(src, cid)
        local e = entries[cid]
        if e and e.src == src then return e end
        return load(src, cid)
    end

    ---Common prologue: ready, src -> cid, then fn(e, cid) under the lock with the entry loaded.
    local function withPlayer(src, opts, op, fn)
        if not deps.ready() then return false, 'not_ready' end
        if type(src) ~= 'number' then return false, 'no_player' end
        local cid = deps.citizenOf(src)
        if not cid then return false, 'no_player' end
        return locked(cid, opts, op, function()
            local e, err = ensure(src, cid)
            if not e then return false, err end
            return fn(e, cid)
        end)
    end

    ---Login / resource start. @return boolean ok, string? err
    function C.load(src)
        return withPlayer(src, WAIT, 'load', function() return true end)
    end

    -- ------------------------------------------------------------ buy

    ---@return boolean ok, table|string result { entry_id, price, unverified? } | err code
    function C.buy(src, shopId, entryId)
        local shop = type(shopId) == 'string' and cfg.shops[shopId] or nil
        if not shop then return false, 'unknown_shop' end
        local entry = type(entryId) == 'string' and cfg.catalog[entryId] or nil
        if not entry then return false, 'unknown_entry' end
        return withPlayer(src, TRY, 'buy', function(e, cid)
            if e.owned[entryId] then return false, 'already_owned' end
            if not deps.inRange(src, shop) then return false, 'out_of_range' end
            local ok, why = logic.checkBuy(entry, shop, e.sex, entry.min_tier, e.owned) -- everything but the tier
            if not ok then return false, why end
            local tier = deps.tierOf(src, shop.region_id)
            if type(tier) ~= 'number' then return false, 'tier_unavailable' end
            ok, why = logic.checkBuy(entry, shop, e.sex, tier, e.owned)
            if not ok then return false, why end
            local alive = aliveFn(src, cid)
            local live, lwhy = alive()
            if not live then return false, lwhy end

            -- 1. claim (invariant 3): nobody can be charged for this entry again from here on
            local n = db.insertOwned(cid, entryId, 'buy', deps.now())
            if n == nil then return false, 'db_failed' end
            if n == 0 then -- owned in the DB already (cache was stale): no charge
                e.owned[entryId] = e.owned[entryId] or 'unknown'
                return false, 'already_owned'
            end

            -- 2. charge, busy retried (B7 took nothing on busy), character re-checked before every attempt
            local paid, err, attempts = logic.chargeWithRetry(function()
                return deps.charge(src, entry.price, 'tailor_buy:' .. entryId, shop.region_id)
            end, alive, deps.wait, cfg.chargeRetries, cfg.chargeRetryMs)

            if paid or err == 'charge_unavailable' then
                e.owned[entryId] = 'buy'
                if not paid then
                    log('ALERT charge threw (outcome unknown), claim kept: citizenid=%s entry=%s price=%s shop=%s',
                        cid, entryId, tostring(entry.price), shop.id)
                end
                deps.emit('fh:tailor:owned', { src = src, citizenid = cid, entry_id = entryId, source = 'buy',
                    price = entry.price, shop_id = shop.id, region_id = shop.region_id })
                return true, { entry_id = entryId, price = entry.price, unverified = (not paid) or nil }
            end

            -- 3. refused (nothing taken): hand the claim back. Only our own 'buy' row, under the lock.
            local del = db.deleteOwned(cid, entryId, 'buy')
            if del == nil or del < 1 then
                e.owned[entryId] = 'buy' -- the DB still says owned: keep the cache in step
                log('WARNING buy refused (%s) but the claim was not removed (%s): citizenid=%s entry=%s owned unpaid',
                    err, del == nil and 'db error' or 'no row', cid, entryId)
            end
            if attempts > 1 then log('buy %s for %s: %d charge attempts, last %s', entryId, cid, attempts, err) end
            return false, err
        end)
    end

    -- ------------------------------------------------------------ grant (other resources)

    ---Rewards from other systems (@hunting legendary coats, @quests rewards). Any catalog id, earned-only or buyable
    ---(lead decision). Idempotent; works with the character offline. The entry must fit the character's sex.
    ---@return boolean ok, string result 'granted' | 'already_owned' | err code
    function C.grant(citizenid, entryId, source)
        if not deps.ready() then return false, 'not_ready' end
        if not logic.validCitizenid(citizenid) then return false, 'invalid_citizenid' end
        local entry = type(entryId) == 'string' and cfg.catalog[entryId] or nil
        if not entry then return false, 'unknown_entry' end
        if not logic.validSource(source) then return false, 'invalid_source' end
        return locked(citizenid, WAIT, 'grant', function()
            local e = entries[citizenid]
            if e and e.owned[entryId] then return true, 'already_owned' end
            local sex = e and e.sex
            if not sex then
                local exists, s = db.citizenSex(citizenid)
                if exists == nil then return false, 'db_failed' end
                if not exists then return false, 'unknown_citizenid' end
                sex = s
            end
            if not logic.sexFits(entry, sex) then return false, 'wrong_sex' end
            local n = db.insertOwned(citizenid, entryId, source, deps.now())
            if n == nil then return false, 'db_failed' end
            e = entries[citizenid]
            if e then e.owned[entryId] = e.owned[entryId] or source end
            if n == 0 then return true, 'already_owned' end
            deps.emit('fh:tailor:owned', { src = deps.onlineSrc(citizenid), citizenid = citizenid, entry_id = entryId,
                source = source })
            return true, 'granted'
        end)
    end

    -- ------------------------------------------------------------ wardrobe

    local function wear(e, cid, src, look)
        if not db.saveWorn(cid, look.outfit, logic.encodeItems(look.items)) then return false, 'db_failed' end
        e.worn = look
        deps.emit('fh:tailor:equipped', { src = src, citizenid = cid, outfit_id = look.outfit, items = look.items,
            fitted = cfg.FittedOutfits })
        return true, { outfit = look.outfit, items = look.items, fitted = cfg.FittedOutfits }
    end

    ---Wear an owned outfit (+ up to cfg.maxItems owned single items). Persists the active look.
    ---@return boolean ok, table|string result { outfit, items, fitted } | err code
    function C.equip(src, outfitId, itemIds)
        return withPlayer(src, WAIT, 'equip', function(e, cid)
            local look, why = logic.validateLook(cfg, e.owned, e.sex, outfitId, itemIds)
            if not look then return false, why end
            return wear(e, cid, src, look)
        end)
    end

    local function validSlot(slot)
        return type(slot) == 'number' and slot == math.floor(slot) and slot >= 1 and slot <= cfg.maxSavedOutfits
    end

    ---Save a look into wardrobe slot 1..cfg.maxSavedOutfits (overwrites). label: optional, <= 32 printable chars.
    ---@return boolean ok, string? err
    function C.saveOutfit(src, slot, label, outfitId, itemIds)
        if not validSlot(slot) then return false, 'bad_slot' end
        if label == nil then label = '' end
        if type(label) ~= 'string' or #label > logic.MAX_LABEL or label:find('[%c]') then return false, 'bad_label' end
        return withPlayer(src, WAIT, 'saveOutfit', function(e, cid)
            local look, why = logic.validateLook(cfg, e.owned, e.sex, outfitId, itemIds)
            if not look then return false, why end
            if not db.saveSlot(cid, slot, label, look.outfit, logic.encodeItems(look.items)) then return false, 'db_failed' end
            e.saved[slot] = { label = label, outfit = look.outfit, items = look.items, valid = true }
            return true
        end)
    end

    ---Wear a saved outfit (ownership and sex re-checked now).
    function C.wearSaved(src, slot)
        if not validSlot(slot) then return false, 'bad_slot' end
        return withPlayer(src, WAIT, 'wearSaved', function(e, cid)
            local s = e.saved[slot]
            if not s then return false, 'empty_slot' end
            local look, why = logic.validateLook(cfg, e.owned, e.sex, s.outfit, s.items)
            if not look then return false, why end
            return wear(e, cid, src, look)
        end)
    end

    -- ------------------------------------------------------------ reads (UI data)

    ---Visible stock for this character at shopId (town size + regional tier + sex; earned_only never listed).
    ---@return boolean ok, table|string { shop = { id, label, region_id, size }, tier, rows } | err code
    function C.getStock(src, shopId)
        local shop = type(shopId) == 'string' and cfg.shops[shopId] or nil
        if not shop then return false, 'unknown_shop' end
        return withPlayer(src, WAIT, 'getStock', function(e)
            local tier = deps.tierOf(src, shop.region_id)
            if type(tier) ~= 'number' then return false, 'tier_unavailable' end
            return true, { shop = { id = shop.id, label = shop.label, region_id = shop.region_id, size = shop.size },
                tier = tier, rows = logic.stockFor(cfg, shop, tier, e.sex, e.owned) }
        end)
    end

    ---@return boolean ok, table|string { owned = { {id,label,kind,source} }, worn, saved, fitted, maxItems, maxSaved }
    function C.getWardrobe(src)
        return withPlayer(src, WAIT, 'getWardrobe', function(e)
            local owned = {}
            for id, source in pairs(e.owned) do
                local c = cfg.catalog[id]
                if c then owned[#owned + 1] = { id = id, label = c.label, kind = c.kind, source = source } end
            end
            table.sort(owned, function(a, b) return a.id < b.id end)
            local saved = {}
            for slot, s in pairs(e.saved) do
                saved[slot] = { label = s.label, outfit = s.outfit, items = { table.unpack(s.items) }, valid = s.valid }
            end
            local worn = e.worn and { outfit = e.worn.outfit, items = { table.unpack(e.worn.items) } } or nil
            return true, { owned = owned, worn = worn, saved = saved, fitted = cfg.FittedOutfits,
                maxItems = cfg.maxItems, maxSaved = cfg.maxSavedOutfits }
        end)
    end

    ---Logout / drop: forget the cache for that src (no lock: a running op keeps its own reference).
    function C.forget(src)
        for cid, e in pairs(entries) do if e.src == src then entries[cid] = nil end end
    end

    return C
end

if _G.GetCurrentResourceName then _G.FhTailorCore = M end
return M

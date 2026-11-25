-- fh_tailor server wiring: DB (migration 0020_fh_tailor), rsg-core / fh_progression / fh_economy lookups, lifecycle and
-- exports. All rules live in FhTailorCore (server/tailor.lua, specced in spec/tailor_spec.lua) and FhTailorLogic.
-- Client apply, shop / wardrobe menus (T2) and the @ui catalog screen (T4) build on the exports below.
local cfg = FhTailorConfig
local logic = FhTailorLogic

assert(logic.validateConfig(cfg, FhRegions.isKnownRegion))

local ready = false -- set once the tables exist; exports refuse ('not_ready') until then

local function log(msg) print(('^3[fh_tailor] %s^7'):format(msg)) end

local function playerData(src)
    local okP, P = pcall(function() return exports['rsg-core']:GetPlayer(src) end)
    return okP and type(P) == 'table' and type(P.PlayerData) == 'table' and P.PlayerData or nil
end

local function citizenOf(src)
    local pd = playerData(src)
    return pd and type(pd.citizenid) == 'string' and pd.citizenid or nil
end

local function sexOf(src)
    local pd = playerData(src)
    return pd and type(pd.charinfo) == 'table' and logic.sexOf(pd.charinfo.gender) or nil
end

local function onlineSrc(cid)
    local okP, P = pcall(function() return exports['rsg-core']:GetPlayerByCitizenId(cid) end)
    if not okP or type(P) ~= 'table' or type(P.PlayerData) ~= 'table' then return nil end
    if P.PlayerData.citizenid ~= cid then return nil end
    return P.PlayerData.source
end

local function inRange(src, shop)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false end
    local c = shop.coords
    return #(GetEntityCoords(ped) - vector3(c.x, c.y, c.z)) <= shop.radius
end

---True when the player is within range of any tailor shop OR their own claimed homestead (claim / town_lot).
---References fh_homestead read-only via its public exports; never edits fh_homestead.
local function inWardrobeRange(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false end
    local pos = GetEntityCoords(ped)
    for _, shop in pairs(cfg.shops) do
        local c = shop.coords
        if #(pos - vector3(c.x, c.y, c.z)) <= shop.radius then return true end
    end
    if GetResourceState('fh_homestead') == 'started' then
        local cid = citizenOf(src)
        if cid then
            local rad = cfg.homesteadWardrobeRadius or 35.0
            for _, class in ipairs({ 'claim', 'town_lot' }) do
                local okP, plotId = pcall(function() return exports.fh_homestead:getPlot(cid, class) end)
                if okP and type(plotId) == 'string' then
                    local okI, info = pcall(function() return exports.fh_homestead:plotInfo(plotId) end)
                    if okI and type(info) == 'table' and info.coords and logic.withinDistance(pos, info.coords, rad) then
                        return true
                    end
                end
            end
        end
    end
    return false
end

local function tierOf(src, region_id)
    local okT, tier = pcall(function() return exports.fh_progression:getTier(src, region_id) end)
    if not okT or type(tier) ~= 'number' then return nil end
    return tier
end

-- ---------------------------------------------------------------- DB (every call returns nil on failure, never throws)
local function affected(okCall, n)
    if not okCall or n == nil then return nil end
    return tonumber(n) or 0
end

local function dbUpdate(sql, params) return affected(pcall(MySQL.update.await, sql, params)) end

local function dbQuery(sql, params)
    local okQ, rows = pcall(MySQL.query.await, sql, params)
    if not okQ or type(rows) ~= 'table' then return nil end
    return rows
end

local db = {
    loadOwned = function(cid)
        return dbQuery('SELECT entry_id, source FROM fh_tailor_owned WHERE citizenid = ?', { cid })
    end,
    ---@return table|false|nil row, false = no row, nil = error
    loadState = function(cid)
        local rows = dbQuery('SELECT starter_at, worn_outfit, worn_items FROM fh_tailor_state WHERE citizenid = ?', { cid })
        if rows == nil then return nil end
        return rows[1] or false
    end,
    loadSaved = function(cid)
        return dbQuery('SELECT slot, label, outfit_id, items FROM fh_tailor_outfits WHERE citizenid = ?', { cid })
    end,
    insertOwned = function(cid, id, source, now)
        return dbUpdate('INSERT IGNORE INTO fh_tailor_owned (citizenid, entry_id, source, acquired_at) VALUES (?, ?, ?, ?)',
            { cid, id, source, now })
    end,
    deleteOwned = function(cid, id, source)
        return dbUpdate('DELETE FROM fh_tailor_owned WHERE citizenid = ? AND entry_id = ? AND source = ?', { cid, id, source })
    end,
    -- One transaction: starter rows (INSERT IGNORE) + starter_at set once + worn look only if none chosen yet.
    grantStarter = function(cid, ids, wornOutfit, now)
        local q = {}
        for _, id in ipairs(ids) do
            q[#q + 1] = { query = 'INSERT IGNORE INTO fh_tailor_owned (citizenid, entry_id, source, acquired_at) VALUES (?, ?, ?, ?)',
                values = { cid, id, 'starter', now } }
        end
        q[#q + 1] = { query = 'INSERT INTO fh_tailor_state (citizenid, starter_at, worn_outfit, worn_items) VALUES (?, ?, ?, ?) '
            .. 'ON DUPLICATE KEY UPDATE starter_at = IFNULL(starter_at, VALUES(starter_at)), '
            .. 'worn_items = IF(worn_outfit IS NULL, VALUES(worn_items), worn_items), '
            .. 'worn_outfit = IFNULL(worn_outfit, VALUES(worn_outfit))',
            values = { cid, now, wornOutfit, '' } }
        local okT, committed = pcall(MySQL.transaction.await, q)
        return okT and committed == true
    end,
    saveWorn = function(cid, outfit, itemsText)
        return dbUpdate('INSERT INTO fh_tailor_state (citizenid, worn_outfit, worn_items) VALUES (?, ?, ?) '
            .. 'ON DUPLICATE KEY UPDATE worn_outfit = VALUES(worn_outfit), worn_items = VALUES(worn_items)',
            { cid, outfit, itemsText }) ~= nil
    end,
    saveSlot = function(cid, slot, label, outfit, itemsText)
        return dbUpdate('INSERT INTO fh_tailor_outfits (citizenid, slot, label, outfit_id, items) VALUES (?, ?, ?, ?, ?) '
            .. 'ON DUPLICATE KEY UPDATE label = VALUES(label), outfit_id = VALUES(outfit_id), items = VALUES(items)',
            { cid, slot, label, outfit, itemsText }) ~= nil
    end,
    ---@return boolean|nil exists (nil = DB error), string|nil sex
    citizenSex = function(cid)
        local rows = dbQuery('SELECT charinfo FROM players WHERE citizenid = ?', { cid })
        if rows == nil then return nil end
        if not rows[1] then return false end
        local okJ, info = pcall(json.decode, rows[1].charinfo or '')
        return true, (okJ and type(info) == 'table') and logic.sexOf(info.gender) or nil
    end,
}

local core = FhTailorCore.new(cfg, logic, {
    ready = function() return ready end,
    citizenOf = citizenOf,
    sexOf = sexOf,
    onlineSrc = onlineSrc,
    inRange = inRange,
    tierOf = tierOf,
    charge = FhTailorCharge.charge,
    wait = function(ms) Wait(ms) end,
    clock = GetGameTimer,
    now = os.time,
    emit = function(name, payload) TriggerEvent(name, payload) end,
    log = log,
    db = db,
})

-- ---------------------------------------------------------------- lifecycle
local function pushApply(src)
    if not cfg.FittedOutfits then return end
    local ok, view = core.getWardrobe(src)
    if ok and type(view) == 'table' and type(view.worn) == 'table' then
        TriggerClientEvent('fh:tailor:apply', src, view.worn)
    end
end

local function onLoaded(src)
    while not ready do Wait(250) end
    local ok, err = core.load(src)
    if not ok then
        log(('load src=%s failed: %s'):format(tostring(src), tostring(err)))
        return
    end
    pushApply(src)
end

-- Push newly equipped looks to the owning client whenever equip / wearSaved succeeds (flag-gated).
AddEventHandler('fh:tailor:equipped', function(ev)
    if not cfg.FittedOutfits then return end
    if type(ev) == 'table' and type(ev.src) == 'number' and type(ev.outfit_id) == 'string' then
        TriggerClientEvent('fh:tailor:apply', ev.src, { outfit = ev.outfit_id, items = ev.items or {} })
    end
end)

-- Server-only event (rsg-core/server/player.lua Login); passes the Player object. Starter set is granted here (once).
AddEventHandler('RSGCore:Server:PlayerLoaded', function(Player)
    local pd = Player and Player.PlayerData
    if pd and type(pd.source) == 'number' then onLoaded(pd.source) end
end)

local debounce = logic.newDebounce(cfg.actionDebounceMs or 0, GetGameTimer)
local act = logic.makeActions({
    core = core, shops = cfg.shops, inShopRange = inRange, inWardrobeRange = inWardrobeRange, debounce = debounce,
})

AddEventHandler('RSGCore:Server:OnPlayerUnload', function(src)
    src = tonumber(src)
    core.forget(src)
    if src then debounce.forget(src) end
end)
AddEventHandler('playerDropped', function()
    local src = tonumber(source)
    core.forget(src)
    if src then debounce.forget(src) end
end)

CreateThread(function()
    -- Idempotent, same DDL as server/migrations/0020_fh_tailor.sql (belt and braces for a DB that skipped the migration).
    local ddl = {
        [[CREATE TABLE IF NOT EXISTS `fh_tailor_owned` (
          `citizenid` varchar(50) NOT NULL,
          `entry_id` varchar(64) NOT NULL,
          `source` varchar(32) NOT NULL,
          `acquired_at` bigint(20) NOT NULL,
          PRIMARY KEY (`citizenid`, `entry_id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci]],
        [[CREATE TABLE IF NOT EXISTS `fh_tailor_state` (
          `citizenid` varchar(50) NOT NULL,
          `starter_at` bigint(20) DEFAULT NULL,
          `worn_outfit` varchar(64) DEFAULT NULL,
          `worn_items` varchar(512) NOT NULL DEFAULT '',
          PRIMARY KEY (`citizenid`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci]],
        [[CREATE TABLE IF NOT EXISTS `fh_tailor_outfits` (
          `citizenid` varchar(50) NOT NULL,
          `slot` tinyint(3) unsigned NOT NULL,
          `label` varchar(32) NOT NULL DEFAULT '',
          `outfit_id` varchar(64) NOT NULL,
          `items` varchar(512) NOT NULL DEFAULT '',
          PRIMARY KEY (`citizenid`, `slot`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci]],
    }
    for _, sql in ipairs(ddl) do
        local okDDL, err = pcall(MySQL.query.await, sql)
        if not okDDL then log(('CREATE TABLE failed (relying on migration 0020): %s'):format(tostring(err))) end
    end
    ready = true
    if not cfg.FittedOutfits then log('FittedOutfits off (until @spikes S1 PASS): looks persist, nothing is applied') end
    -- Resource (re)start: load everyone already online (grants a missing starter set).
    for _, id in ipairs(GetPlayers()) do
        local src = tonumber(id)
        if src and citizenOf(src) then CreateThread(function() onLoaded(src) end) end
    end
end)

-- ---------------------------------------------------------------- client callbacks + net events (T2 stopgap menus)
-- Server validates everything (shop, range, wardrobe location, ownership, sex, tier, slot, label): client sends ids only.

lib.callback.register('fh:tailor:worn', function(src)
    if not cfg.FittedOutfits then return nil end
    local ok, view = core.getWardrobe(src)
    if not ok or type(view) ~= 'table' then return nil end
    return view.worn
end)

lib.callback.register('fh:tailor:stock', function(src, shopId) return act.actStock(src, shopId) end)

-- Plot ids of the caller's own claimed plots (claim / town lot): the client shows the [G] prompt only at those chests.
lib.callback.register('fh:tailor:own_plots', function(src)
    local out = {}
    local cid = citizenOf(src)
    if cid and GetResourceState('fh_homestead') == 'started' then
        for _, class in ipairs({ 'claim', 'town_lot' }) do
            local okP, plotId = pcall(function() return exports.fh_homestead:getPlot(cid, class) end)
            if okP and type(plotId) == 'string' then out[#out + 1] = plotId end
        end
    end
    return out
end)

lib.callback.register('fh:tailor:wardrobe', function(src) return act.actWardrobe(src) end)

RegisterNetEvent('fh:tailor:buy', function(payload)
    local src = source
    local shopId = type(payload) == 'table' and payload.shop_id or nil
    local entryId = type(payload) == 'table' and payload.entry_id or nil
    local ok, res = act.actBuy(src, shopId, entryId)
    TriggerClientEvent('fh:tailor:result', src, {
        action = 'buy', ok = ok, code = (not ok) and res or nil,
        shop_id = shopId, entry_id = entryId,
        price = ok and res.price or nil, unverified = ok and res.unverified or nil,
    })
end)

RegisterNetEvent('fh:tailor:equip', function(payload)
    local src = source
    local outfitId = type(payload) == 'table' and payload.outfit_id or nil
    local itemIds = type(payload) == 'table' and payload.items or nil
    local ok, res = act.actEquip(src, outfitId, itemIds)
    TriggerClientEvent('fh:tailor:result', src, {
        action = 'equip', ok = ok, code = (not ok) and res or nil,
        outfit_id = ok and res.outfit or nil,
    })
end)

RegisterNetEvent('fh:tailor:save_outfit', function(payload)
    local src = source
    local slot = type(payload) == 'table' and payload.slot or nil
    local label = type(payload) == 'table' and payload.label or nil
    local outfitId = type(payload) == 'table' and payload.outfit_id or nil
    local itemIds = type(payload) == 'table' and payload.items or nil
    local ok, err = act.actSave(src, slot, label, outfitId, itemIds)
    TriggerClientEvent('fh:tailor:result', src, {
        action = 'save_outfit', ok = ok, code = (not ok) and err or nil, slot = slot,
    })
end)

RegisterNetEvent('fh:tailor:wear_saved', function(payload)
    local src = source
    local slot = type(payload) == 'table' and payload.slot or nil
    local ok, res = act.actWear(src, slot)
    TriggerClientEvent('fh:tailor:result', src, {
        action = 'wear_saved', ok = ok, code = (not ok) and res or nil,
        slot = slot, outfit_id = ok and res.outfit or nil,
    })
end)

-- ---------------------------------------------------------------- exports (contract: README.md)
-- Raw exports below are trusted server-side calls: NO range check, NO debounce.
exports('buy', core.buy)
exports('grant', core.grant)
exports('equip', core.equip)
exports('saveOutfit', core.saveOutfit)
exports('wearSaved', core.wearSaved)
exports('getStock', core.getStock)
exports('getWardrobe', core.getWardrobe)
-- Player-action exports: the same range guards + debounce as the net events. Relays must use these, not the raw ones.
exports('actBuy', act.actBuy)
exports('actStock', act.actStock)
exports('actWardrobe', act.actWardrobe)
exports('actEquip', act.actEquip)
exports('actSave', act.actSave)
exports('actWear', act.actWear)
exports('message', logic.message)

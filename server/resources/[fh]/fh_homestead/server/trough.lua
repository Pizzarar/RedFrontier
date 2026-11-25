-- fh_homestead H20b (plan homestead-04): trough server. Pure rules (accepts, containerId, canRefill): shared/trough.lua (FhTrough, H20a).
--
-- The trough slot (kind 'station', stationType 'trough', claims only) owns one fh_core container `fh:trough:<plot>`
-- (type 'chest', registered at the slot prop). It takes the feedbag ONLY: fh_core has no per-item container filter, so the
-- rule is kept by construction: the container is never opened to a player (no chest prompt: the trough slot is not a
-- chest_<n> slot) and the only writer is `loadTrough` below (FhTrough.accepts checked before every add), reached by
-- USING a feedbag at your own trough. Nothing else in fh_homestead adds to it.
--
-- Load (the feedbag's use handler, tier A: no lost bag): gates (owner at own trough, within trough.reach) -> take 1 feedbag
--   from the BACKPACK (removeItem) -> add 1 to the trough container; if that add fails the bag goes back to the backpack
--   (else ITEM LOST logged, never rerouted).
-- Refill (`fh:homestead:trough_refill`, client asks when its owner mounts a horse): FhTrough.canRefill (owner, inside the
--   plot radius by the SERVER ped, >= 1 feedbag in the trough, cooldown since fh_plot_trough.last_refill_at) -> take exactly 1
--   feedbag from the trough -> record last_refill_at (conditional on ownership) -> only then tell the client to refill the
--   horse cores. If the record fails the feedbag goes back into the trough. Gated by trough.troughRefill (default false:
--   the server never consumes and the client never calls the unverified natives until the flag is flipped).
-- Locks: one trough flow per plot and per character, plus FhHomesteadClaims.beginChestWrite, so no unclaim runs mid-flow.
local cfg = FhHomesteadConfig
local rules = FhTrough
local plotRules = FhPlotRules

FhHomesteadTrough = {}
local T = FhHomesteadTrough

local CLAIM = 'claim'
local STATION = 'trough'
local busyPlot, busyCid = {}, {}
local gen = {} -- plotId -> unclaim counter (backstop; beginChestWrite already keeps unclaims out)

local LOG_COLOR = { error = '^1', info = '^2' }
local function log(level, msg) print(('%s[fh_homestead] %s^7'):format(LOG_COLOR[level] or '^3', msg)) end

local function slots() return FhHomesteadSlots end
local function claims() return FhHomesteadClaims end
local function genOf(plotId) return gen[plotId] or 0 end
local function now() return os.time() end
local function tcfg() return type(cfg.trough) == 'table' and cfg.trough or {} end

local function citizenidOf(src)
    if type(src) ~= 'number' or src <= 0 then return nil end
    local ok, p = pcall(function() return exports['rsg-core']:GetCoreObject().Functions.GetPlayer(src) end)
    return ok and p and p.PlayerData and p.PlayerData.citizenid or nil
end

local function bagRef(src) return { type = 'backpack', id = src } end
local function troughRef(plotId)
    local id = rules.containerId(plotId)
    return id and { type = 'chest', id = id } or nil
end

local function reach()
    local r = tonumber(tcfg().reach)
    return (r and r > 0 and r < math.huge) and r or 5.0
end

---Most feedbags the trough holds (trough.capacity, default 10 = maxWeight 20000 g / feedbag 2000 g).
local function capacity()
    local c = math.tointeger(tonumber(tcfg().capacity))
    return (c and c > 0) and c or 10
end

local function stillOwns(cid, plotId, g)
    local c = claims()
    return genOf(plotId) == g and c ~= nil and c.ownerOf(plotId) == cid and c.plotOf(cid, CLAIM) == plotId
end

local function vec(c)
    if vector3 then return vector3(c.x, c.y, c.z) end
    return { x = c.x, y = c.y, z = c.z }
end

-- ---------------------------------------------------------------- container

---Register the plot's trough container at the slot prop position. false, why on failure (logged by callers).
function T.register(plotId)
    local plot = cfg.plots[plotId]
    local slot = plot and plot.slots and plot.slots.trough
    local ref = troughRef(plotId)
    if not (slot and ref) then return false, 'fh_no_trough' end
    local place = FhBuildRules.slotPlacement(plot, slot, cfg.verifiedProps)
    if not place then return false, 'fh_no_coords' end
    local c = tcfg()
    local ok, res, why = pcall(function()
        return exports.fh_core:registerContainer(ref, { coords = vec(place.coords), label = 'Feed trough',
            slots = c.slots, maxWeight = c.maxWeight })
    end)
    if not ok or not res then return false, tostring(ok and why or res) end
    return true
end

local function registerAll()
    local S, C = slots(), claims()
    if not (S and S.isReady() and C and C.isReady()) then return end
    for plotId in pairs(cfg.plots) do
        if C.ownerOf(plotId) and (S.getTiers(plotId).trough or 0) >= 1 then
            local ok, why = T.register(plotId)
            if not ok then log('error', ('trough register failed for %s: %s'):format(plotId, tostring(why))) end
        end
    end
end

---Feedbags in the plot's trough container (sums every stack of the accepted item). nil, why when unreadable.
function T.feedbags(plotId)
    local ref = troughRef(plotId)
    if not ref then return nil, 'fh_bad_ref' end
    local ok, items, why = pcall(function() return exports.fh_core:snapshot(ref) end)
    if not ok then return nil, 'snapshot threw: ' .. tostring(items) end
    if type(items) ~= 'table' then return nil, tostring(why or 'fh_no_container') end
    local n = 0
    for _, it in pairs(items) do
        if type(it) == 'table' and rules.accepts(it.name) and type(it.amount) == 'number' then n = n + it.amount end
    end
    return n
end

-- ---------------------------------------------------------------- persistence (fh_plot_trough)

---last_refill_at (server unix seconds) of the plot, nil when never refilled; false, why when the read fails.
local function lastRefill(plotId)
    local ok, rows = pcall(MySQL.query.await, 'SELECT last_refill_at FROM fh_plot_trough WHERE plot_id = ?', { plotId })
    if not ok or type(rows) ~= 'table' then
        log('error', ('fh_plot_trough read for %s failed: %s'):format(tostring(plotId), tostring(rows)))
        return false, 'fh_trough_check_failed'
    end
    local r = rows[1]
    return r and math.tointeger(tonumber(r.last_refill_at)) or nil
end

-- ---------------------------------------------------------------- where + lock

---The caller's own claim plot with a built trough. cid, plotId | nil, reason.
local function troughOf(src)
    local S, C = slots(), claims()
    if not (S and S.isReady() and C and C.isReady()) then return nil, 'fh_not_ready' end
    local cid = citizenidOf(src)
    if not cid then return nil, 'fh_no_character' end
    local plotId = C.plotOf(cid, CLAIM)
    if not plotId then return nil, 'fh_no_plot' end
    if (S.getTiers(plotId).trough or 0) < 1 then return nil, 'fh_no_trough' end
    return cid, plotId
end

local function runLocked(src, cid, plotId, fn, onError, extra)
    if busyPlot[plotId] or busyCid[cid] then return false, 'fh_trough_busy' end
    local held, hwhy = claims().beginChestWrite(plotId)
    if not held then return false, hwhy end
    busyPlot[plotId], busyCid[cid] = true, true
    local st = { src = src, cid = cid, plotId = plotId, g = genOf(plotId) }
    for k, v in pairs(extra or {}) do st[k] = v end
    local r = table.pack(pcall(fn, st))
    local out
    if r[1] then
        out = table.pack(table.unpack(r, 2, r.n))
    else
        local okE, o = pcall(function()
            log('error', ('trough %s for %s on %s errored: %s'):format(tostring(st.op), cid, plotId, tostring(r[2])))
            return table.pack(onError(st))
        end)
        out = okE and o or table.pack(false, 'fh_trough_failed')
    end
    busyPlot[plotId], busyCid[cid] = nil, nil
    claims().endChestWrite(plotId)
    return table.unpack(out, 1, out.n)
end

local function locked(src, fn, onError, extra)
    local cid, plotId = troughOf(src)
    if not cid then return false, plotId end
    return runLocked(src, cid, plotId, fn, onError, extra)
end

-- ---------------------------------------------------------------- load (use a feedbag at the trough)

local function loadLocked(st)
    if not rules.accepts(st.item) then return false, 'fh_trough_wrong_item' end
    local ped = GetPlayerPed(st.src)
    if not ped or ped == 0 then return false, 'fh_no_player' end
    local at = slots().stationAt(GetEntityCoords(ped), reach(), STATION)
    if not at then return false, 'fh_not_near_trough' end
    if at.plot_id ~= st.plotId or claims().ownerOf(st.plotId) ~= st.cid then return false, 'fh_not_owner' end
    if not stillOwns(st.cid, st.plotId, st.g) then return false, 'fh_no_plot' end
    local ref = troughRef(st.plotId)
    local have, hwhy = T.feedbags(st.plotId)
    if not have then
        log('warn', ('trough read for %s failed: %s'):format(st.plotId, tostring(hwhy)))
        return false, 'fh_trough_check_failed'
    end
    if have >= capacity() then return false, 'fh_trough_full' end
    if citizenidOf(st.src) ~= st.cid then return false, 'player_changed' end
    local ok, res, rwhy = pcall(function() return exports.fh_core:removeItem(bagRef(st.src), st.item, 1) end)
    if not ok then return false, 'fh_removeitem_unavailable' end
    if res ~= true then
        if rwhy == 'fh_not_enough' then return false, 'fh_no_feedbag' end
        return false, type(rwhy) == 'string' and rwhy or 'fh_removeitem_failed'
    end
    st.taken = true
    local oka, resa, awhy = pcall(function() return exports.fh_core:addItem(ref, st.item, 1) end)
    if oka and resa == true then st.taken = false; return true end
    if not oka or awhy == nil then awhy = tostring(oka and 'refused' or resa) end
    -- the trough refused: the bag goes back to the backpack, else the loss is logged (never rerouted)
    st.taken = false
    local okb, resb = pcall(function() return exports.fh_core:addItem(bagRef(st.src), st.item, 1) end)
    if not (okb and resb == true) then
        log('error', ('ITEM LOST: feedbag refund failed: citizenid=%s plot=%s item=%s amount=1 trough_error=%s')
            :format(st.cid, st.plotId, st.item, tostring(awhy)))
        return false, 'fh_trough_refund_failed'
    end
    return false, tostring(awhy) == 'fh_inventory_full' and 'fh_trough_full' or awhy
end

---Load 1 `item` (feedbag only) from the caller's backpack into their own claim trough they stand at.
---Returns true | false, reason.
function T.load(src, item)
    return locked(src, loadLocked, function(st)
        if st.taken then -- errored between the take and the add: put the bag back, never lose it
            local okb, resb = pcall(function() return exports.fh_core:addItem(bagRef(st.src), st.item, 1) end)
            if okb and resb == true then return false, 'fh_trough_failed' end
            log('error', ('ITEM LOST: feedbag errored mid-load and the refund failed: citizenid=%s plot=%s'):format(st.cid, st.plotId))
            return false, 'fh_trough_refund_failed'
        end
        return false, 'fh_trough_failed'
    end, { op = 'load', item = item })
end

-- ---------------------------------------------------------------- refill (owner mounts a horse at home)

local function refillLocked(st)
    local plot = cfg.plots[st.plotId]
    local ped = GetPlayerPed(st.src)
    if not ped or ped == 0 then return false, 'fh_no_player' end
    local inRadius = plotRules.inRadius(plot, GetEntityCoords(ped))
    local last, lwhy = lastRefill(st.plotId)
    if last == false then return false, lwhy end
    local feedbags, fwhy = T.feedbags(st.plotId)
    if not feedbags then
        log('warn', ('trough read for %s failed: %s'):format(st.plotId, tostring(fwhy)))
        return false, 'fh_trough_check_failed'
    end
    local ok, why = rules.canRefill({ isOwner = claims().ownerOf(st.plotId) == st.cid, inRadius = inRadius,
        feedbags = feedbags, lastRefillAt = last, now = now() })
    if not ok then return false, why end
    if not stillOwns(st.cid, st.plotId, st.g) then return false, 'fh_no_plot' end
    local ref = troughRef(st.plotId)
    local okr, res, rwhy = pcall(function() return exports.fh_core:removeItem(ref, tcfg().item, 1) end)
    if not okr then return false, 'fh_removeitem_unavailable' end
    if res ~= true then return false, rwhy == 'fh_not_enough' and 'fh_trough_empty' or (rwhy or 'fh_removeitem_failed') end
    st.taken = true
    local okw, affected = pcall(MySQL.update.await,
        'INSERT INTO fh_plot_trough (plot_id, last_refill_at) SELECT ?, ? FROM fh_plots WHERE plot_id = ? AND citizenid = ?'
        .. ' ON DUPLICATE KEY UPDATE last_refill_at = VALUES(last_refill_at)',
        { st.plotId, now(), st.plotId, st.cid })
    if not okw or (tonumber(affected) or 0) < 1 then
        log('warn', ('trough refill %s: could not record the refill (%s); putting the feedbag back')
            :format(st.plotId, tostring(okw and ('affected ' .. tostring(affected)) or affected)))
        st.taken = false
        local okb, resb = pcall(function() return exports.fh_core:addItem(ref, tcfg().item, 1) end)
        if not (okb and resb == true) then
            log('error', ('ITEM LOST: feedbag refund into the trough failed: citizenid=%s plot=%s'):format(st.cid, st.plotId))
            return false, 'fh_trough_refund_failed'
        end
        return false, 'fh_trough_save_failed'
    end
    st.taken = false
    return true
end

---Refill for the caller: consumes 1 feedbag from their own trough and records it. true | false, reason.
function T.refill(src)
    if tcfg().troughRefill ~= true then return false, 'fh_refill_disabled' end
    return locked(src, refillLocked, function(st)
        if st.taken then
            -- errored after the take: the refill record may or may not have landed; put the bag back (never lose it)
            local okb, resb = pcall(function() return exports.fh_core:addItem(troughRef(st.plotId), tcfg().item, 1) end)
            if okb and resb == true then return false, 'fh_trough_failed' end
            log('error', ('ITEM LOST: feedbag errored mid-refill and the refund failed: citizenid=%s plot=%s'):format(st.cid, st.plotId))
            return false, 'fh_trough_refund_failed'
        end
        return false, 'fh_trough_failed'
    end, { op = 'refill' })
end

RegisterNetEvent('fh:homestead:trough_refill', function()
    local src = source
    local ok, why = T.refill(src)
    if ok then TriggerClientEvent('fh:homestead:trough_refilled', src) return end
    if why ~= 'fh_cooldown' and why ~= 'fh_out_of_range' and why ~= 'fh_trough_empty' and why ~= 'fh_no_trough'
        and why ~= 'fh_no_plot' and why ~= 'fh_refill_disabled' and why ~= 'fh_not_owner' then
        log('warn', ('trough refill for src %s refused: %s'):format(tostring(src), tostring(why)))
    end
end)

-- ---------------------------------------------------------------- export + unclaim support

---getTrough(citizenid) -> { plotId, count, capacity } of the character's claim trough (READ-ONLY: no container ref, so
---no caller can write into it; use feedTrough), or nil, why (fh_no_trough, fh_not_ready, fh_trough_check_failed).
local function getTrough(citizenid)
    local S, C = slots(), claims()
    if type(citizenid) ~= 'string' or citizenid == '' then return nil, 'fh_no_trough' end
    if not (S and S.isReady() and C and C.isReady()) then return nil, 'fh_not_ready' end
    local plotId = C.plotOf(citizenid, CLAIM)
    if not plotId or (S.getTiers(plotId).trough or 0) < 1 then return nil, 'fh_no_trough' end
    local count = T.feedbags(plotId)
    if not count then return nil, 'fh_trough_check_failed' end
    return { plotId = plotId, count = count, capacity = capacity() }
end

local function feedLocked(st)
    if not stillOwns(st.cid, st.plotId, st.g) then return false, 'fh_no_plot' end
    local item = tcfg().item
    if not rules.accepts(item) then return false, 'fh_trough_wrong_item' end
    local have, hwhy = T.feedbags(st.plotId)
    if not have then
        log('warn', ('trough read for %s failed: %s'):format(st.plotId, tostring(hwhy)))
        return false, 'fh_trough_check_failed'
    end
    local room = capacity() - have
    if room < 1 then return false, 'fh_trough_full' end
    local add = math.min(st.n, room)
    local ref = troughRef(st.plotId)
    local ok, res, why = pcall(function() return exports.fh_core:addItem(ref, item, add) end)
    if ok and res ~= true and why == 'fh_unknown_container' and T.register(st.plotId) then
        ok, res, why = pcall(function() return exports.fh_core:addItem(ref, item, add) end)
    end
    if not ok then return false, 'fh_trough_failed' end
    if res ~= true then
        if why == 'fh_inventory_full' then return false, 'fh_trough_full' end
        return false, type(why) == 'string' and why or 'fh_trough_failed'
    end
    return true, add
end

---feedTrough(citizenid, n) -> added | nil, why. The ONLY way another resource puts anything into a trough: n FEEDBAGS
---(the item is implicit) into the character's own claim trough, clamped to the room left under trough.capacity.
---Where the feedbags come from is the caller's job (we only add). Same lock as the use handler.
---Reasons: fh_bad_amount, fh_no_trough, fh_trough_full (no room), fh_trough_busy, fh_trough_check_failed, fh_not_ready.
local function feedTrough(citizenid, n)
    if type(n) ~= 'number' or n ~= n or n < 1 or math.tointeger(n) == nil then return nil, 'fh_bad_amount' end
    n = math.tointeger(n)
    local S, C = slots(), claims()
    if type(citizenid) ~= 'string' or citizenid == '' then return nil, 'fh_no_trough' end
    if not (S and S.isReady() and C and C.isReady()) then return nil, 'fh_not_ready' end
    local plotId = C.plotOf(citizenid, CLAIM)
    if not plotId or (S.getTiers(plotId).trough or 0) < 1 then return nil, 'fh_no_trough' end
    local ok, a, b = runLocked(nil, citizenid, plotId, feedLocked, function() return false, 'fh_trough_failed' end,
        { op = 'feed', n = n })
    if ok then return a end
    return nil, a
end
exports('feedTrough', feedTrough)
T.feedTrough = feedTrough
exports('getTrough', getTrough)
T.getTrough = getTrough

AddEventHandler('fh:homestead:unclaimed', function(data)
    if type(data) ~= 'table' or type(data.plot_id) ~= 'string' then return end
    gen[data.plot_id] = genOf(data.plot_id) + 1
    pcall(MySQL.update.await, 'DELETE FROM fh_plot_trough WHERE plot_id = ?', { data.plot_id }) -- FK cascade backstop
end)

AddEventHandler('fh:homestead:slot_changed', function(plotId, slotId, tier)
    if slotId ~= 'trough' or type(plotId) ~= 'string' or (tonumber(tier) or 0) < 1 then return end
    local ok, why = T.register(plotId)
    if not ok then log('error', ('trough register failed for %s: %s (retried on the next boot / fh_core restart)'):format(plotId, tostring(why))) end
end)

-- Belt and braces for a DB that skipped the trough migration (same DDL; needs fh_plots from 0003).
CreateThread(function()
    local ok, err = pcall(MySQL.query.await, [[CREATE TABLE IF NOT EXISTS `fh_plot_trough` (
  `plot_id` varchar(50) NOT NULL,
  `last_refill_at` bigint(20) unsigned NOT NULL,
  PRIMARY KEY (`plot_id`),
  CONSTRAINT `fh_plot_trough_plot` FOREIGN KEY (`plot_id`) REFERENCES `fh_plots` (`plot_id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci]])
    if not ok then log('error', 'fh_plot_trough create failed (apply the trough migration in server/migrations): ' .. tostring(err)) end
    while GetResourceState('fh_core') ~= 'started' do Wait(500) end
    local S = slots()
    while not (S and S.isReady()) do Wait(1000) end
    registerAll()
end)

AddEventHandler('onResourceStart', function(res)
    if res == 'fh_core' then registerAll() end
end)

-- ---------------------------------------------------------------- the feedbag's use handler (the real consumer)

local function onUse(src)
    if type(src) ~= 'number' then return end
    local ok, why = T.load(src, tcfg().item)
    local msg = ok and 'The feed trough is loaded.' or ('Could not load the trough: ' .. tostring(why))
    pcall(TriggerClientEvent, 'chat:addMessage', src, { args = { 'fh', msg } })
end

local function registerUse()
    local ok, err = pcall(function() exports['rsg-core']:CreateUseableItem('feedbag', onUse) end)
    if not ok then log('error', 'CreateUseableItem feedbag failed: ' .. tostring(err)) end
end

CreateThread(function()
    while GetResourceState('rsg-core') ~= 'started' do Wait(500) end
    registerUse()
end)
AddEventHandler('onResourceStart', function(res)
    if res == 'rsg-core' then registerUse() end
end)

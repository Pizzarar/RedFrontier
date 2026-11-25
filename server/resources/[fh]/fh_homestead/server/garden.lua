-- fh_homestead H19 (plan homestead-04): garden server. `/fh_plant <seed>`, `/fh_harvest [bed]`, `/fh_garden`.
-- Pure rules (crop table, timer, yield): shared/garden.lua (FhGarden, H18). Persistence: fh_plot_beds (migration
-- 0021): one row per planted bed (plot_id, bed, crop = seed key, planted_at = server unix seconds). The DB is the
-- only state (no cache): a crop grows while its owner is offline and keeps its timer across restarts.
--
-- Contract (core B7 + C3a): fh_core.removeItem(ref, item, n) all-or-nothing (fh_not_enough, fh_player_offline,
-- fh_bad_ref); fh_core.addItem(ref, item, n) all-or-nothing (nothing added on a refusal, except fh_inventory_error:
-- see server/build.lua BAG_ADD_UNCHANGED). The backpack ref is { type = 'backpack', id = src }.
--
-- Where: the garden slot (kind 'station', stationType 'garden', claims only) of the caller's own CLAIM, within
-- FhHomesteadConfig.garden.reach of its prop (FhHomesteadSlots.stationAt(coords, reach, 'garden'), owner-only).
-- Lock: one garden flow per plot AND per character (busyPlot/busyCid), plus FhHomesteadClaims.beginChestWrite for the
--   plot, so no unclaim runs while a seed is out or a harvest is mid-give (unclaim gets 'fh_chest_busy'); every DB write
--   is also conditional on fh_plots still naming the owner (backstop). Released on every path, also on a Lua error.
--
-- Plant (tier A: no free crop, no lost seed):
--   gates -> read the plot's beds (DB) -> first free bed (1..FhGarden.beds) -> take 1 seed from the BACKPACK
--   (removeItem, right after checking the same character is on src) -> only after that take succeeded:
--   INSERT the bed row (conditional on ownership; the (plot_id, bed) primary key refuses a second row). If the write
--   fails, the seed goes back: backpack, else (backpack refusal in BAG_ADD_UNCHANGED, or the character left src) plot
--   chest 1, else ITEM LOST logged (never rerouted: no dupe) and fh_garden_refund_failed.
-- Harvest (tier A: no double harvest, no lost crop):
--   gates -> read beds -> the bed must be ready (FhGarden.ready with the row's crop, never a nil crop) -> DELETE that
--   exact row (plot, bed, crop, planted_at, owner) and require exactly 1 affected row BEFORE anything is given, so a
--   second harvest of the same planting finds 0 rows and gives nothing -> give the crop's yield: backpack, else (as
--   above) plot chest 1. If both refuse with a reason known to leave them unchanged, the bed row is put back as it was
--   (same crop + planted_at) and the call says fh_no_room; any other failure is logged ITEM LOST (fh_harvest_lost).
local cfg = FhHomesteadConfig
local garden = FhGarden
local plotRules = FhPlotRules

FhHomesteadGarden = {}
local G = FhHomesteadGarden

local CLAIM = 'claim'
local STATION = 'garden'
local busyPlot, busyCid = {}, {}
local gen = {} -- plotId -> unclaim counter (backstop; beginChestWrite already keeps unclaims out)

local LOG_COLOR = { error = '^1', info = '^2' }
local function log(level, msg) print(('%s[fh_homestead] %s^7'):format(LOG_COLOR[level] or '^3', msg)) end

local function slots() return FhHomesteadSlots end
local function claims() return FhHomesteadClaims end
local function genOf(plotId) return gen[plotId] or 0 end
local function now() return os.time() end

local function citizenidOf(src)
    if type(src) ~= 'number' or src <= 0 then return nil end
    local ok, p = pcall(function() return exports['rsg-core']:GetCoreObject().Functions.GetPlayer(src) end)
    return ok and p and p.PlayerData and p.PlayerData.citizenid or nil
end

local function bagRef(src) return { type = 'backpack', id = src } end
local function chestRef(plotId) return { type = 'chest', id = plotRules.chestStashId(plotId, 1) } end

---server/build.lua's list of addItem refusals known to leave the target unchanged. Missing = empty: every refusal then
---fails closed (ITEM LOST, never rerouted).
local function unchangedReason(why)
    local B = FhHomesteadBuild
    local list = B and B.BAG_ADD_UNCHANGED
    return type(why) == 'string' and list ~= nil and list[why] == true
end

local function reach()
    local g = type(cfg.garden) == 'table' and cfg.garden or {}
    local r = tonumber(g.reach)
    return (r and r > 0 and r < math.huge) and r or 5.0
end

local function stillOwns(cid, plotId, g)
    local c = claims()
    return genOf(plotId) == g and c ~= nil and c.ownerOf(plotId) == cid and c.plotOf(cid, CLAIM) == plotId
end

-- ---------------------------------------------------------------- DB reads

---Every bed row of the plot, sorted by bed: { { bed, crop, planted_at } } (malformed rows kept: they still hold a bed).
---nil, 'fh_garden_check_failed' when the read fails.
function G.plantedBeds(plotId)
    local ok, rows = pcall(MySQL.query.await,
        'SELECT bed, crop, planted_at FROM fh_plot_beds WHERE plot_id = ? ORDER BY bed', { plotId })
    if not ok or type(rows) ~= 'table' then
        log('error', ('fh_plot_beds read for %s failed: %s'):format(tostring(plotId), tostring(rows)))
        return nil, 'fh_garden_check_failed'
    end
    local out = {}
    for _, r in ipairs(rows) do
        local bed = math.tointeger(tonumber(r.bed))
        out[#out + 1] = { bed = bed, crop = r.crop, planted_at = math.tointeger(tonumber(r.planted_at)) }
    end
    table.sort(out, function(a, b) return (a.bed or 0) < (b.bed or 0) end)
    return out
end

---Crop def of a stored row, or nil (review L: FhGarden.ready/remaining are only ever called with a non-nil crop).
local function rowCrop(row)
    if type(row) ~= 'table' or type(row.crop) ~= 'string' or row.crop == '' then return nil end
    return garden.crop(row.crop)
end

---ready, remaining seconds (nil when the row's crop or planted_at is unusable).
local function rowState(row, t)
    local def = rowCrop(row)
    if not def or row.planted_at == nil then return false, nil end
    return garden.ready(row.planted_at, t, row.crop) == true, garden.remaining(row.planted_at, t, row.crop)
end

---Lowest bed number in 1..beds with no row, or nil.
local function freeBed(rows)
    local used = {}
    for _, r in ipairs(rows) do if r.bed then used[r.bed] = true end end
    for b = 1, garden.beds() do if not used[b] then return b end end
    return nil
end

-- ---------------------------------------------------------------- gives (checked, at most once each)

---Give `amount` of `item`: backpack first; a backpack refusal known to leave it unchanged (or the character no longer on
---src: nothing tried) goes to plot chest 1. Never throws.
---@return string|nil where 'bag'|'chest', string|nil why, boolean unchanged  unchanged = nothing landed anywhere
local function giveBagThenChest(st, item, amount)
    local ok, res, rwhy, untried
    if citizenidOf(st.src) ~= st.cid then
        ok, res, rwhy, untried = true, false, 'character not on src', true
    else
        ok, res, rwhy = pcall(function() return exports.fh_core:addItem(bagRef(st.src), item, amount) end)
    end
    if ok and res == true then return 'bag' end
    if not (ok and (untried or unchangedReason(rwhy))) then
        return nil, ok and (tostring(rwhy) .. ' (outcome unknown: may already be in the backpack; not rerouted)')
            or ('backpack addItem threw: ' .. tostring(res)), false
    end
    local bagWhy = rwhy
    ok, res, rwhy = pcall(function() return exports.fh_core:addItem(chestRef(st.plotId), item, amount) end)
    if ok and res == true then return 'chest', bagWhy end
    return nil, ('backpack refused (%s), then plot chest: %s'):format(tostring(bagWhy), tostring(ok and rwhy or res)),
        ok and unchangedReason(rwhy)
end

---Put the taken seed back (plant failed after the take). Runs at most once (st.taken cleared first).
local function refundSeed(st, why)
    if not st.taken then return true end
    st.taken = false
    local where, gwhy = giveBagThenChest(st, st.seed, 1)
    if where == 'chest' then
        log('warn', ('garden refund: backpack refused 1 %s (%s); put into plot chest %s instead; citizenid=%s src=%s plant_error=%s')
            :format(st.seed, tostring(gwhy), plotRules.chestStashId(st.plotId, 1), st.cid, tostring(st.src), tostring(why)))
    elseif not where then
        log('error', ('ITEM LOST: garden seed refund failed: citizenid=%s plot=%s item=%s amount=1 refund_error=%s plant_error=%s')
            :format(st.cid, st.plotId, st.seed, tostring(gwhy), tostring(why)))
        return false
    end
    return true
end

local function plantAbort(st, why)
    if not refundSeed(st, why) then return false, 'fh_garden_refund_failed' end
    return false, why
end

---Write the bed row back exactly as it was (harvest could not give anything). Conditional on ownership.
local function restoreBed(st, row)
    local ok, affected = pcall(MySQL.update.await,
        'INSERT INTO fh_plot_beds (plot_id, bed, crop, planted_at) SELECT ?, ?, ?, ? FROM fh_plots'
        .. ' WHERE plot_id = ? AND citizenid = ?',
        { st.plotId, row.bed, row.crop, row.planted_at, st.plotId, st.cid })
    return ok and tonumber(affected) == 1, ok and affected or tostring(affected)
end

---Harvest could not give the crop: put the bed back when nothing landed (unchanged), else log ITEM LOST.
local function harvestUndo(st, gwhy, unchanged)
    local row, def = st.cleared, st.def
    st.cleared = nil
    if unchanged then
        local back, bwhy = restoreBed(st, row)
        if back then return false, 'fh_no_room' end
        gwhy = ('%s; bed restore failed: %s'):format(tostring(gwhy), tostring(bwhy))
    end
    log('error', ('ITEM LOST: garden harvest give failed: citizenid=%s plot=%s bed=%s item=%s amount=%d crop=%s planted_at=%s give_error=%s')
        :format(st.cid, st.plotId, tostring(row.bed), def.item, def.yield, tostring(row.crop), tostring(row.planted_at), tostring(gwhy)))
    return false, 'fh_harvest_lost'
end

-- ---------------------------------------------------------------- where

---The caller's own claim whose garden they stand at. cid, plotId | nil, reason.
local function gardenOf(src)
    local S = slots()
    local C = claims()
    if not (S and S.isReady() and C and C.isReady()) then return nil, 'fh_not_ready' end
    local cid = citizenidOf(src)
    if not cid then return nil, 'fh_no_character' end
    local plotId = C.plotOf(cid, CLAIM)
    if not plotId then return nil, 'fh_no_plot' end
    if (S.getTiers(plotId).garden or 0) < 1 then return nil, 'fh_no_garden' end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return nil, 'fh_no_player' end
    local at = S.stationAt(GetEntityCoords(ped), reach(), STATION)
    if not at then return nil, 'fh_not_near_garden' end
    if at.plot_id ~= plotId or C.ownerOf(plotId) ~= cid then return nil, 'fh_not_owner' end
    return cid, plotId
end

---Run fn(st) under the plot + character locks and the chest hold; onError(st, err) builds the result of a Lua error.
local function locked(src, fn, onError, extra)
    local cid, plotId = gardenOf(src)
    if not cid then return false, plotId end
    if busyPlot[plotId] or busyCid[cid] then return false, 'fh_garden_busy' end
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
            log('error', ('garden %s for %s on %s errored: %s'):format(tostring(st.op), cid, plotId, tostring(r[2])))
            return table.pack(onError(st))
        end)
        out = okE and o or table.pack(false, 'fh_garden_failed')
    end
    busyPlot[plotId], busyCid[cid] = nil, nil
    claims().endChestWrite(plotId)
    return table.unpack(out, 1, out.n)
end

-- ---------------------------------------------------------------- plant

local function plantLocked(st)
    local rows, why = G.plantedBeds(st.plotId)
    if not rows then return false, why end
    if not stillOwns(st.cid, st.plotId, st.g) then return false, 'fh_no_plot' end
    local bed = freeBed(rows)
    if not bed then return false, 'fh_garden_full' end
    st.bed = bed
    -- the backpack ref is by src: the same character must still be loaded there (no await between this and the take)
    if citizenidOf(st.src) ~= st.cid then return false, 'player_changed' end
    local ok, res, rwhy = pcall(function() return exports.fh_core:removeItem(bagRef(st.src), st.seed, 1) end)
    if not ok then
        log('warn', 'fh_core:removeItem failed: ' .. tostring(res))
        return false, 'fh_removeitem_unavailable'
    end
    if res ~= true then
        if rwhy == 'fh_not_enough' then return false, 'fh_no_seed', st.seed end
        return false, type(rwhy) == 'string' and rwhy or 'fh_removeitem_failed'
    end
    st.taken = true
    if not stillOwns(st.cid, st.plotId, st.g) then return plantAbort(st, 'fh_no_plot') end
    local plantedAt = now()
    local okw, affected = pcall(MySQL.update.await,
        'INSERT INTO fh_plot_beds (plot_id, bed, crop, planted_at) SELECT ?, ?, ?, ? FROM fh_plots'
        .. ' WHERE plot_id = ? AND citizenid = ?',
        { st.plotId, bed, st.seed, plantedAt, st.plotId, st.cid })
    if not okw or tonumber(affected) ~= 1 then
        log('warn', ('garden plant %s bed %d for %s: bed write failed (%s); refunding the seed')
            :format(st.plotId, bed, st.cid, tostring(okw and ('affected ' .. tostring(affected)) or affected)))
        return plantAbort(st, 'fh_garden_save_failed')
    end
    st.taken, st.written = false, true -- the seed is in the ground now
    return true, bed, plantedAt
end

---Plant one `seed` (seedcarrot, seedpotato, seedcorn: FhHomesteadConfig.garden.crops) in the first free bed of the
---caller's own claim garden they stand at. Returns true, bed, planted_at | false, reason, detail.
function G.plant(src, seed)
    if type(seed) ~= 'string' or seed == '' then return false, 'fh_unknown_seed' end
    local def, derr = garden.cropForSeed(seed)
    if not def then return false, derr end
    return locked(src, plantLocked, function(st)
        if st.written then return true, st.bed end
        return plantAbort(st, 'fh_garden_failed')
    end, { op = 'plant', seed = seed })
end

-- ---------------------------------------------------------------- harvest

local function harvestLocked(st)
    local rows, why = G.plantedBeds(st.plotId)
    if not rows then return false, why end
    if not stillOwns(st.cid, st.plotId, st.g) then return false, 'fh_no_plot' end
    local t = now()
    local pick, soonest
    for _, r in ipairs(rows) do
        if st.bed == nil or r.bed == st.bed then
            local ready, left = rowState(r, t)
            if ready then pick = r; break end
            if left and (soonest == nil or left < soonest) then soonest = left end
            if st.bed ~= nil and not rowCrop(r) then return false, 'fh_unknown_crop', r.crop end
        end
    end
    if not pick then
        if soonest then return false, 'fh_not_ripe', soonest end
        return false, st.bed and 'fh_bed_empty' or 'fh_garden_empty'
    end
    local def = rowCrop(pick)
    -- clear the bed first: only the exact planting, only while we own the plot. Exactly 1 row, or nothing is given.
    local okd, affected = pcall(MySQL.update.await,
        'DELETE b FROM fh_plot_beds b JOIN fh_plots p ON p.plot_id = b.plot_id'
        .. ' WHERE b.plot_id = ? AND b.bed = ? AND b.crop = ? AND b.planted_at = ? AND p.citizenid = ?',
        { st.plotId, pick.bed, pick.crop, pick.planted_at, st.cid })
    if not okd then
        log('warn', ('garden harvest %s bed %s for %s: bed clear failed (%s); nothing given')
            :format(st.plotId, tostring(pick.bed), st.cid, tostring(affected)))
        return false, 'fh_garden_save_failed'
    end
    if tonumber(affected) ~= 1 then return false, 'fh_bed_changed' end
    st.cleared, st.def = pick, def
    st.giving = true
    local where, gwhy, unchanged = giveBagThenChest(st, def.item, def.yield)
    st.giving = false
    if not where then return harvestUndo(st, gwhy, unchanged) end
    st.cleared = nil
    st.given = { bed = pick.bed, item = def.item, amount = def.yield, to = where }
    if where == 'chest' then
        log('warn', ('garden harvest: backpack refused %d %s (%s); put into plot chest %s instead; citizenid=%s src=%s bed=%d')
            :format(def.yield, def.item, tostring(gwhy), plotRules.chestStashId(st.plotId, 1), st.cid, tostring(st.src), pick.bed))
    end
    return true, st.given
end

---Harvest a ready bed of the caller's own claim garden they stand at (bed nil = the first ready one).
---Returns true, { bed, item, amount, to = 'bag'|'chest' } | false, reason, detail.
function G.harvest(src, bed)
    if bed ~= nil then
        bed = type(bed) == 'number' and math.tointeger(bed) or nil
        if not bed or bed < 1 or bed > garden.beds() then return false, 'fh_bad_bed' end
    end
    return locked(src, harvestLocked, function(st)
        if st.given then return true, st.given end
        if not st.cleared then return false, 'fh_garden_failed' end
        if st.giving then -- the give may have landed: never restore (no dupe)
            return harvestUndo(st, 'errored during the give (outcome unknown)', false)
        end
        local back = restoreBed(st, st.cleared)
        if back then st.cleared = nil; return false, 'fh_garden_failed' end
        return harvestUndo(st, 'errored before the give', false)
    end, { op = 'harvest', bed = bed })
end

-- ---------------------------------------------------------------- status + unclaim

---Status of the caller's claim garden: { { bed, crop, item, ready, remaining } } per bed 1..beds (empty beds: crop nil).
function G.status(src)
    local S, C = slots(), claims()
    if not (S and S.isReady() and C and C.isReady()) then return nil, 'fh_not_ready' end
    local cid = citizenidOf(src)
    local plotId = cid and C.plotOf(cid, CLAIM)
    if not plotId then return nil, 'fh_no_plot' end
    if (S.getTiers(plotId).garden or 0) < 1 then return nil, 'fh_no_garden' end
    local rows, why = G.plantedBeds(plotId)
    if not rows then return nil, why end
    local byBed, t, out = {}, now(), {}
    for _, r in ipairs(rows) do if r.bed then byBed[r.bed] = r end end
    for b = 1, garden.beds() do
        local r = byBed[b]
        local def = r and rowCrop(r)
        local ready, left = false, nil
        if r then ready, left = rowState(r, t) end
        out[#out + 1] = { bed = b, crop = r and r.crop, item = def and def.item, ready = ready, remaining = left }
    end
    return out, plotId
end

---Unclaim (server/main.lua, plot lock held): after the fh_plots DELETE of a force unclaim, log every bed read under
---the lock and delete the rows (the FK cascade normally already did; this is the backstop). Never throws.
function G.clearPlot(plotId, owner, rows, reason)
    for _, r in ipairs(rows or {}) do
        log('warn', ('%s: plot=%s owner=%s bed=%s crop=%s planted_at=%s cleared')
            :format(tostring(reason), plotId, tostring(owner), tostring(r.bed), tostring(r.crop), tostring(r.planted_at)))
    end
    local ok, err = pcall(MySQL.update.await, 'DELETE FROM fh_plot_beds WHERE plot_id = ?', { plotId })
    if not ok then
        log('error', ('plot %s released but its fh_plot_beds rows may remain (%s); delete them by hand before the next claim')
            :format(plotId, tostring(err)))
        return false
    end
    return true
end

AddEventHandler('fh:homestead:unclaimed', function(data)
    if type(data) ~= 'table' or type(data.plot_id) ~= 'string' then return end
    gen[data.plot_id] = genOf(data.plot_id) + 1
end)

-- Belt and braces for a DB that skipped migration 0021 (same DDL; needs fh_plots from 0003).
CreateThread(function()
    local ok, err = pcall(MySQL.query.await, [[CREATE TABLE IF NOT EXISTS `fh_plot_beds` (
  `plot_id` varchar(50) NOT NULL,
  `bed` tinyint(3) unsigned NOT NULL,
  `crop` varchar(50) NOT NULL,
  `planted_at` bigint(20) unsigned NOT NULL,
  PRIMARY KEY (`plot_id`, `bed`),
  CONSTRAINT `fh_plot_beds_plot` FOREIGN KEY (`plot_id`) REFERENCES `fh_plots` (`plot_id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci]])
    if not ok then log('error', 'fh_plot_beds create failed (apply server/migrations/0021_homestead_garden_beds.sql): ' .. tostring(err)) end
end)

-- ---------------------------------------------------------------- commands

local function reply(src, msg)
    if src == 0 then print('[fh_homestead] ' .. msg) else TriggerClientEvent('chat:addMessage', src, { args = { 'fh', msg } }) end
end

local function mins(s)
    s = math.max(0, math.ceil((tonumber(s) or 0) / 60))
    if s >= 60 then return ('%dh %02dm'):format(s // 60, s % 60) end
    return ('%dm'):format(s)
end

local HINT = {
    fh_no_seed = 'no %s in your backpack',
    fh_unknown_seed = 'seeds: seedcarrot, seedpotato, seedcorn',
    fh_garden_full = 'every bed is planted',
    fh_not_near_garden = 'stand at your garden',
    fh_no_garden = 'build it first: /fh_build garden',
    fh_garden_busy = 'a garden action is already in progress, try again in a moment',
    fh_no_room = 'no room in your backpack or plot chest; the bed was left as it was',
    fh_garden_refund_failed = 'planting failed and the seed refund did not go through; tell an admin (server log: LOST)',
    fh_harvest_lost = 'the harvest could not be given; tell an admin (server log: LOST)',
}

local function describe(why, detail)
    if why == 'fh_not_ripe' then return ('fh_not_ripe (ready in %s)'):format(mins(detail)) end
    local h = HINT[why]
    return h and (why .. ' (' .. h:format(tostring(detail)) .. ')') or tostring(why)
end

lib.addCommand('fh_plant', { help = 'Plant a seed in a free bed of your claim garden (stand at the garden)',
    params = { { name = 'seed', type = 'string', help = 'seedcarrot, seedpotato or seedcorn' } } },
    function(src, args)
        local ok, res, detail = G.plant(src, args and args.seed)
        if not ok then return reply(src, 'fh_plant: ' .. describe(res, detail)) end
        TriggerClientEvent('fh:anim:play', src, 'plant')
        local def = garden.cropForSeed(args.seed)
        reply(src, ('fh_plant: planted %s in bed %d (ready in %s)'):format(args.seed, res, mins(def and def.growthSeconds)))
    end)

lib.addCommand('fh_harvest', { help = 'Harvest a ready bed of your claim garden (no argument: the first ready bed)',
    params = { { name = 'bed', type = 'number', help = 'bed number', optional = true } } },
    function(src, args)
        local ok, res, detail = G.harvest(src, args and args.bed)
        if not ok then return reply(src, 'fh_harvest: ' .. describe(res, detail)) end
        TriggerClientEvent('fh:anim:play', src, 'harvest')
        reply(src, ('fh_harvest: bed %d gave %d %s (%s)'):format(res.bed, res.amount, res.item,
            res.to == 'bag' and 'backpack' or 'plot chest 1: backpack full'))
    end)

lib.addCommand('fh_garden', { help = 'Show your claim garden beds' }, function(src)
    local beds, why = G.status(src)
    if not beds then return reply(src, 'fh_garden: ' .. describe(why)) end
    local parts = {}
    for _, b in ipairs(beds) do
        local what = not b.crop and 'empty' or (b.item or tostring(b.crop)) .. ' '
            .. (b.ready and 'ready' or (b.remaining and mins(b.remaining) or 'unknown crop'))
        parts[#parts + 1] = ('bed %d %s'):format(b.bed, what)
    end
    reply(src, 'fh_garden: plot ' .. why .. ': ' .. table.concat(parts, '; '))
end)

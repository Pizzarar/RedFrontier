-- fh_homestead H3: slot tier cache + station API (server). Interface used by H2 (build) and H4 (comfort):
--   FhHomesteadSlots.load() / isReady() / getTiers(plot_id) / setTier(plot_id, slot_id, tier) / plotOf(citizenid)
-- Server-local events: fh:homestead:slot_changed (plot_id, slot_id, tier);
--   fh:homestead:station_built (citizenid, plot_id, slot_id, station_type).
-- Stations are OWNER-ONLY (see shared/stations.lua). No money/item handling here: H2 charges, then calls setTier.
-- Consistency rules (review rn-250ee6892de0):
--   * Nothing is read or written before the boot load finishes (state 'ready') and claims are loaded: reads return
--     empty + 'fh_not_ready', writes are refused with 'fh_not_ready'. So the load can never clobber a write.
--   * One setTier per plot at a time (inflight lock); a second one is refused with 'fh_slot_busy'.
--   * The DB write is conditional on fh_plots ownership, and after the await the claim epoch + owner are checked again:
--     a plot unclaimed (or unclaimed and re-claimed) mid-write keeps no cached slot and raises no events.
--   * tier 0 = no row (migration 0005): setTier(..., 0) deletes the row; the load ignores 0-tier / out-of-range rows.
local cfg = FhHomesteadConfig
local stations = FhStations
local cache = {}              -- [plot_id] = { [slot_id] = tier >= 1 }; tier 0 = no entry (= no DB row)
local state = 'idle'          -- idle | loading | ready | failed
local unclaimedDuringLoad = {} -- [plot_id] = true for plots unclaimed while the boot SELECT was in flight
local inflight = {}           -- [plot_id] = true while a setTier for that plot awaits MySQL
local epoch = {}              -- [plot_id] = n, bumped on every unclaim; a write is only kept if it did not change

FhHomesteadSlots = {}
local S = FhHomesteadSlots

local function claims() return FhHomesteadClaims end

---True once the slot cache is loaded and the claim table (server/main.lua) is loaded.
function S.isReady()
    local c = claims()
    return state == 'ready' and c ~= nil and c.isReady() == true
end

local function slotDef(plotId, slotId)
    local plot = cfg.plots[plotId]
    local slot = type(plot) == 'table' and type(plot.slots) == 'table' and plot.slots[slotId] or nil
    return type(slot) == 'table' and slot or nil
end

---Integer tier or nil. Strings are refused (math.tointeger would coerce '1').
local function toTier(v)
    if type(v) ~= 'number' then return nil end
    return math.tointeger(v)
end

---tier 0 (not built) or 1..maxTier with a tiers[tier] definition.
local function validTier(slot, tier)
    if tier == 0 then return true end
    return tier ~= nil and tier >= 1 and tier <= (tonumber(slot.maxTier) or 0)
        and type(slot.tiers) == 'table' and slot.tiers[tier] ~= nil
end

local function cachedTier(plotId, slotId) return (cache[plotId] and cache[plotId][slotId]) or 0 end

local function putCache(plotId, slotId, tier)
    if tier == 0 then
        if cache[plotId] then
            cache[plotId][slotId] = nil
            if next(cache[plotId]) == nil then cache[plotId] = nil end
        end
    else
        cache[plotId] = cache[plotId] or {}
        cache[plotId][slotId] = tier
    end
end

---Boot load. Runs once (again only after a failure); writes are refused until it finishes.
---@return boolean ok, string|nil reason
function S.load()
    if state == 'loading' or state == 'ready' then return false, 'fh_already_loaded' end
    state, unclaimedDuringLoad = 'loading', {}
    local ok, rows = pcall(MySQL.query.await, 'SELECT plot_id, slot_id, tier FROM fh_plot_slots')
    if not ok or type(rows) ~= 'table' then
        state = 'failed'
        print(('^1[fh_homestead] fh_plot_slots load failed: %s^7'):format(tostring(rows)))
        return false, 'fh_slot_load_failed'
    end
    local fresh = {}
    for _, r in ipairs(rows) do
        local n = tonumber(r.tier)
        local tier = n and math.tointeger(n)
        local slot = slotDef(r.plot_id, r.slot_id)
        if not slot or not tier or not validTier(slot, tier) then
            print(('^3[fh_homestead] fh_plot_slots row %s/%s tier %s not in config.lua; ignored^7'):format(
                tostring(r.plot_id), tostring(r.slot_id), tostring(r.tier)))
        elseif tier > 0 then
            fresh[r.plot_id] = fresh[r.plot_id] or {}
            fresh[r.plot_id][r.slot_id] = tier
        end
    end
    -- the SELECT may have run before an unclaim's cascade delete: do not resurrect those plots
    for plotId in pairs(unclaimedDuringLoad) do fresh[plotId] = nil end
    unclaimedDuringLoad = {}
    cache, state = fresh, 'ready'
    return true
end

---Copy of the plot's tiers (empty table if none); callers cannot mutate the cache through it.
---Before the load finishes: empty table + 'fh_not_ready'.
function S.getTiers(plotId)
    local out = {}
    if state ~= 'ready' then return out, 'fh_not_ready' end
    for k, v in pairs(cache[plotId] or {}) do out[k] = v end
    return out
end

---Plot id the character owns, or nil (claim state lives in server/main.lua).
function S.plotOf(citizenid)
    local c = claims()
    return c and c.plotOf(citizenid) or nil
end

---Persist + cache a slot tier, then raise events. Validates ids, tier against the slot's maxTier/tiers, and that
---the plot is claimed; rules/costs are H2's job. tier 0 removes the slot (deletes the row).
---@return boolean ok, string|nil reason
function S.setTier(plotId, slotId, tier)
    if not S.isReady() then return false, 'fh_not_ready' end
    local slot = slotDef(plotId, slotId)
    if not slot then return false, 'fh_no_slot' end
    tier = toTier(tier)
    if not tier or not validTier(slot, tier) then return false, 'fh_bad_tier' end
    local owner = claims().ownerOf(plotId)
    if not owner then return false, 'fh_plot_free' end
    if inflight[plotId] then return false, 'fh_slot_busy' end
    local old = cachedTier(plotId, slotId)
    if old == tier then return true end -- nothing to persist, no events
    local gen = epoch[plotId] or 0
    inflight[plotId] = true
    local ok, affected
    if tier == 0 then
        ok, affected = pcall(MySQL.update.await,
            'DELETE s FROM fh_plot_slots s JOIN fh_plots p ON p.plot_id = s.plot_id'
            .. ' WHERE s.plot_id = ? AND s.slot_id = ? AND p.citizenid = ?',
            { plotId, slotId, owner })
    else
        -- INSERT ... SELECT: writes only while fh_plots still says `owner` holds the plot (0 rows otherwise)
        ok, affected = pcall(MySQL.update.await,
            'INSERT INTO fh_plot_slots (plot_id, slot_id, tier) SELECT ?, ?, ? FROM fh_plots'
            .. ' WHERE plot_id = ? AND citizenid = ? ON DUPLICATE KEY UPDATE tier = VALUES(tier)',
            { plotId, slotId, tier, plotId, owner })
    end
    local claimChanged = (epoch[plotId] or 0) ~= gen or claims().ownerOf(plotId) ~= owner
    if ok and claimChanged and tier > 0 and (tonumber(affected) or 0) > 0 then
        -- unclaimed (+ maybe re-claimed by the same owner) while we waited and our row landed on the new claim:
        -- take it back while still holding the plot lock
        local undone = pcall(MySQL.update.await,
            'DELETE FROM fh_plot_slots WHERE plot_id = ? AND slot_id = ? AND tier = ?', { plotId, slotId, tier })
        if not undone then
            print(('^1[fh_homestead] could not undo stale slot write %s/%s^7'):format(plotId, slotId))
        end
    end
    inflight[plotId] = nil
    if not ok then return false, 'fh_slot_save_failed' end
    if claimChanged then return false, 'fh_plot_free' end
    if (tonumber(affected) or 0) == 0 then return false, 'fh_slot_save_failed' end
    putCache(plotId, slotId, tier)
    TriggerEvent('fh:homestead:slot_changed', plotId, slotId, tier)
    if stations.isStationBuilt(slot, old, tier) then
        TriggerEvent('fh:homestead:station_built', owner, plotId, slotId, slot.stationType)
    end
    return true
end

-- Unclaim deletes fh_plots; the FK cascades fh_plot_slots. Mirror that in the cache and invalidate in-flight writes.
AddEventHandler('fh:homestead:unclaimed', function(data)
    if type(data) ~= 'table' or data.plot_id == nil then return end
    local plotId = data.plot_id
    cache[plotId] = nil
    epoch[plotId] = (epoch[plotId] or 0) + 1
    if state == 'loading' then unclaimedDuringLoad[plotId] = true end
end)

CreateThread(function()
    for attempt = 1, 5 do
        local ok, why = S.load()
        if ok or why ~= 'fh_slot_load_failed' then return end
        Wait(5000 * attempt)
    end
end)

---Built stations of one plot (restricted to it) or of all plots when plotId is nil.
local function listStations(plotId)
    return stations.allStations(cfg.plots, cache, cfg.verifiedProps, plotId)
end

---Built stations on the character's own plot ({} before the load finishes).
local function getStations(citizenid)
    if not S.isReady() or type(citizenid) ~= 'string' then return {} end
    local plotId = S.plotOf(citizenid)
    return plotId and listStations(plotId) or {}
end

---Nearest built station (any plot) to coords within maxDist, or nil (nil before the load finishes).
local function stationAt(coords, maxDist)
    if not S.isReady() then return nil end
    local s = stations.nearest(listStations(), coords, maxDist)
    if not s then return nil end
    return { plot_id = s.plot_id, slot_id = s.slot_id, station_type = s.station_type }
end

---Owner-only: is the src's character within maxDist of a built station_type on their own plot? Uses the server ped.
local function isNearStation(src, stationType, maxDist)
    if not S.isReady() or type(stationType) ~= 'string' then return false end
    local p = exports['rsg-core']:GetCoreObject().Functions.GetPlayer(src)
    local cid = p and p.PlayerData.citizenid
    local plotId = cid and S.plotOf(cid)
    if not plotId then return false end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false end
    return stations.nearest(listStations(plotId), GetEntityCoords(ped), maxDist, stationType) ~= nil
end

exports('getStations', getStations)
exports('stationAt', stationAt)
exports('isNearStation', isNearStation)

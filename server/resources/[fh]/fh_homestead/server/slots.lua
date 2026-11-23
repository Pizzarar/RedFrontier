-- fh_homestead H3: slot tier cache + station API (server). Interface used by H2 (build) and H4 (comfort):
--   FhHomesteadSlots.load() / getTiers(plot_id) / setTier(plot_id, slot_id, tier) / plotOf(citizenid)
-- Server-local events: fh:homestead:slot_changed (plot_id, slot_id, tier);
--   fh:homestead:station_built (citizenid, plot_id, slot_id, station_type).
-- Stations are OWNER-ONLY (see shared/stations.lua). No money/item handling here: H2 charges, then calls setTier.
local cfg = FhHomesteadConfig
local stations = FhStations
local cache = {} -- [plot_id] = { [slot_id] = tier }

FhHomesteadSlots = {}
local S = FhHomesteadSlots

function S.load()
    local fresh = {}
    local rows = MySQL.query.await('SELECT plot_id, slot_id, tier FROM fh_plot_slots') or {}
    for _, r in ipairs(rows) do
        fresh[r.plot_id] = fresh[r.plot_id] or {}
        fresh[r.plot_id][r.slot_id] = tonumber(r.tier) or 0
    end
    cache = fresh
end

---Copy of the plot's tiers (empty table if none); callers cannot mutate the cache through it.
function S.getTiers(plotId)
    local out = {}
    for k, v in pairs(cache[plotId] or {}) do out[k] = v end
    return out
end

---Plot id the character owns, or nil (claim state lives in server/main.lua).
function S.plotOf(citizenid)
    local c = FhHomesteadClaims
    return c and c.byOwner[citizenid] or nil
end

---Persist + cache a slot tier, then raise events. Validates ids/tier range and that the plot is claimed;
---rules/costs are H2's job.
---@return boolean ok, string|nil reason
function S.setTier(plotId, slotId, tier)
    local plot = cfg.plots[plotId]
    local slot = plot and plot.slots and plot.slots[slotId]
    if not slot then return false, 'fh_no_slot' end
    tier = math.tointeger(tier)
    if not tier or tier < 0 or tier > (slot.maxTier or 0) then return false, 'fh_bad_tier' end
    local owner = FhHomesteadClaims and FhHomesteadClaims.byPlot[plotId]
    if not owner then return false, 'fh_plot_free' end
    local old = (cache[plotId] and cache[plotId][slotId]) or 0
    local ok = pcall(MySQL.query.await,
        'INSERT INTO fh_plot_slots (plot_id, slot_id, tier) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE tier = VALUES(tier)',
        { plotId, slotId, tier })
    if not ok then return false, 'fh_slot_save_failed' end
    cache[plotId] = cache[plotId] or {}
    cache[plotId][slotId] = tier
    TriggerEvent('fh:homestead:slot_changed', plotId, slotId, tier)
    if stations.isStationBuilt(slot, old, tier) then
        TriggerEvent('fh:homestead:station_built', owner, plotId, slotId, slot.stationType)
    end
    return true
end

-- Unclaim deletes fh_plots; the FK cascades fh_plot_slots. Mirror that in the cache.
AddEventHandler('fh:homestead:unclaimed', function(data)
    if type(data) == 'table' and data.plot_id then cache[data.plot_id] = nil end
end)

CreateThread(S.load)

---Built stations of one plot (restricted to it) or of all plots when plotId is nil.
local function listStations(plotId)
    return stations.allStations(cfg.plots, cache, cfg.verifiedProps, plotId)
end

---Built stations on the character's own plot.
local function getStations(citizenid)
    if type(citizenid) ~= 'string' then return {} end
    local plotId = S.plotOf(citizenid)
    return plotId and listStations(plotId) or {}
end

---Nearest built station (any plot) to coords within maxDist, or nil.
local function stationAt(coords, maxDist)
    local s = stations.nearest(listStations(), coords, maxDist)
    if not s then return nil end
    return { plot_id = s.plot_id, slot_id = s.slot_id, station_type = s.station_type }
end

---Owner-only: is the src's character within maxDist of a built station_type on their own plot? Uses the server ped.
local function isNearStation(src, stationType, maxDist)
    if type(stationType) ~= 'string' then return false end
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

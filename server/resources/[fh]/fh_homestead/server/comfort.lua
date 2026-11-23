-- fh_homestead H4 comfort (server). Cache per citizenid; value = FhComfort.compute(plot, tiers, trophies, cfg).
-- Reads tiers from H3's FhHomesteadSlots (guarded: if absent, tiers are empty). Homestead does NOT apply buffs.
--
-- Exports: getComfort(citizenid) -> number (0 if no plot);
--          placeTrophy(src, itemId) -> ok, err|trophy_id ; unplaceTrophy(src, trophy_id) -> ok, err  (owner-only, H2 wires the command)
--          addTrophy(citizenid, trophy_id, points) / removeTrophy(citizenid, trophy_id): internal/admin, no item movement.
-- Placement: item leaves the plot chest via fh_core removeItem (core B7; pcall'd, refused 'fh_removeitem_unavailable' if absent),
--   points = exports.fh_hunting:getTrophyComfort(itemId) (nil = not a trophy; hunting down = refused). Trophy ids are '<item>#<n>'.
-- Events emitted (server-local):
--   'fh:homestead:comfort_changed' (citizenid, newComfort, oldComfort), only when the value changes
--   'fh:homestead:trophy_placed' / 'fh:homestead:trophy_removed' ({ citizenid, trophy_id, comfort })
-- Events consumed: 'fh:homestead:slot_changed' (plot_id, slot_id, tier) from FhHomesteadSlots.setTier.
-- Trophies belong to the plot and are deleted with it on unclaim.
local cfg = FhHomesteadConfig
local calc = FhComfort
local rules = FhPlotRules

local cache = {}   -- citizenid -> { plotId, trophies = { [id] = points }, value }
local byPlot = {}  -- plotId -> citizenid (only for cached entries)

local function plotOf(citizenid)
    if type(citizenid) ~= 'string' or citizenid == '' then return nil end
    if FhHomesteadSlots and FhHomesteadSlots.plotOf then return FhHomesteadSlots.plotOf(citizenid) end
    return nil
end

local function tiersOf(plotId)
    if FhHomesteadSlots and FhHomesteadSlots.getTiers then return FhHomesteadSlots.getTiers(plotId) or {} end
    return {}
end

local function entryFor(citizenid, plotId)
    local e = cache[citizenid]
    if e and e.plotId == plotId then return e end
    if e then byPlot[e.plotId] = nil end
    local trophies = {}
    local rows = MySQL.query.await('SELECT trophy_id, points FROM fh_plot_trophies WHERE plot_id = ?', { plotId }) or {}
    for _, r in ipairs(rows) do trophies[r.trophy_id] = tonumber(r.points) or 0 end
    e = { plotId = plotId, trophies = trophies, value = nil }
    cache[citizenid], byPlot[plotId] = e, citizenid
    return e
end

local function drop(citizenid)
    local e = cache[citizenid]
    if e then byPlot[e.plotId] = nil end
    cache[citizenid] = nil
end

-- Recompute, store, and fire comfort_changed when it differs from the last known value (first computation counts from 0).
local function refresh(citizenid)
    local plotId = plotOf(citizenid)
    if not plotId then
        local old = cache[citizenid] and cache[citizenid].value or 0
        drop(citizenid)
        if old ~= 0 then TriggerEvent('fh:homestead:comfort_changed', citizenid, 0, old) end
        return 0
    end
    local e = entryFor(citizenid, plotId)
    local new = calc.compute(cfg.plots[plotId], tiersOf(plotId), e.trophies, cfg)
    local old = e.value or 0
    e.value = new
    if new ~= old then TriggerEvent('fh:homestead:comfort_changed', citizenid, new, old) end
    return new
end

local function getComfort(citizenid)
    return refresh(citizenid)
end

local function addTrophy(citizenid, trophyId, points)
    if type(trophyId) ~= 'string' or trophyId == '' or #trophyId > 64 then return false, 'fh_bad_trophy' end
    if not calc.validPoints(points) then return false, 'fh_bad_points' end
    points = math.floor(points)
    if points < 1 then return false, 'fh_bad_points' end
    local plotId = plotOf(citizenid)
    if not plotId then return false, 'fh_no_plot' end
    local e = entryFor(citizenid, plotId)
    if e.trophies[trophyId] then return false, 'fh_trophy_duplicate' end
    local ok = pcall(MySQL.insert.await,
        'INSERT INTO fh_plot_trophies (plot_id, trophy_id, points) VALUES (?, ?, ?)', { plotId, trophyId, points })
    if not ok then return false, 'fh_trophy_failed' end
    e.trophies[trophyId] = points
    refresh(citizenid)
    return true
end

local function removeTrophy(citizenid, trophyId)
    local plotId = plotOf(citizenid)
    if not plotId then return false, 'fh_no_plot' end
    local e = entryFor(citizenid, plotId)
    if type(trophyId) ~= 'string' or not e.trophies[trophyId] then return false, 'fh_no_trophy' end
    local ok = pcall(MySQL.update.await, 'DELETE FROM fh_plot_trophies WHERE plot_id = ? AND trophy_id = ?', { plotId, trophyId })
    if not ok then return false, 'fh_trophy_failed' end
    e.trophies[trophyId] = nil
    refresh(citizenid)
    return true
end

AddEventHandler('fh:homestead:slot_changed', function(plotId)
    local owner = byPlot[plotId]
    if not owner then
        local ok, row = pcall(MySQL.scalar.await, 'SELECT citizenid FROM fh_plots WHERE plot_id = ?', { plotId })
        owner = ok and row or nil
    end
    if owner then refresh(owner) end
end)

-- Small wrappers so specs/other code can stub the cross-resource calls.
local function trophyComfortOf(itemId)
    if GetResourceState('fh_hunting') ~= 'started' then
        print('^3[fh_homestead] fh_hunting not started; trophy placement refused^7')
        return nil, 'fh_hunting_unavailable'
    end
    local ok, res = pcall(function() return exports.fh_hunting:getTrophyComfort(itemId) end)
    if not ok then
        print('^3[fh_homestead] fh_hunting:getTrophyComfort failed: ' .. tostring(res) .. '^7')
        return nil, 'fh_hunting_unavailable'
    end
    return tonumber(res)
end

local function chestRef(plotId) return { type = 'chest', id = rules.chestStashId(plotId, 1) } end

local function removeFromChest(plotId, itemId)
    local ok, res, why = pcall(function() return exports.fh_core:removeItem(chestRef(plotId), itemId, 1) end)
    if not ok then
        print('^3[fh_homestead] fh_core:removeItem unavailable (core B7): ' .. tostring(res) .. '^7')
        return false, 'fh_removeitem_unavailable'
    end
    if not res then return false, why or 'fh_item_not_in_chest' end
    return true
end

local function citizenidOf(src)
    local p = exports['rsg-core']:GetCoreObject().Functions.GetPlayer(src)
    return p and p.PlayerData.citizenid or nil
end

local function placeTrophy(src, itemId)
    local cid = citizenidOf(src)
    local plotId = plotOf(cid)
    if not plotId then return false, 'fh_no_plot' end
    local e = entryFor(cid, plotId)
    local ok, res, trophyId = calc.place({
        citizenid = cid, ownerCitizenid = cid, tiers = tiersOf(plotId), trophies = e.trophies, cfg = cfg, itemId = itemId,
        lookup = trophyComfortOf,
        removeItem = function(id) return removeFromChest(plotId, id) end,
    })
    if not ok then return false, res end
    local added, why = addTrophy(cid, trophyId, res)
    if not added then
        pcall(function() return exports.fh_core:addItem(chestRef(plotId), itemId, 1) end) -- refund the item taken above
        return false, why
    end
    TriggerEvent('fh:homestead:trophy_placed', { citizenid = cid, trophy_id = trophyId, comfort = res })
    return true, trophyId
end

local function unplaceTrophy(src, trophyId)
    local cid = citizenidOf(src)
    local plotId = plotOf(cid)
    if not plotId then return false, 'fh_no_plot' end
    local e = entryFor(cid, plotId)
    local ok, why = calc.canUnplace({ citizenid = cid, ownerCitizenid = cid, trophyId = trophyId, trophies = e.trophies })
    if not ok then return false, why end
    local points = e.trophies[trophyId]
    local itemId = calc.itemOf(trophyId)
    local added, res = pcall(function() return exports.fh_core:addItem(chestRef(plotId), itemId, 1) end)
    if not added or not res then return false, 'fh_chest_full' end -- keep the trophy rather than lose the item
    local removed, rwhy = removeTrophy(cid, trophyId)
    if not removed then return false, rwhy end
    TriggerEvent('fh:homestead:trophy_removed', { citizenid = cid, trophy_id = trophyId, comfort = points })
    return true
end

exports('getComfort', getComfort)
exports('placeTrophy', placeTrophy)
exports('unplaceTrophy', unplaceTrophy)
exports('addTrophy', addTrophy)
exports('removeTrophy', removeTrophy)

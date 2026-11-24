-- fh_homestead H4 comfort (server). Cache per citizenid; value = FhComfort.compute(plot, tiers, trophies, cfg).
-- Reads tiers from H3's FhHomesteadSlots (guarded: if absent, tiers are empty). Homestead does NOT apply buffs.
--
-- Exports: getComfort(citizenid) -> number (0 if no plot). Best home (H15): max(claim comfort, town lot comfort); trophies
--          exist only on claims, so they add to the claim side only;
--          placeTrophy(src, itemId) -> ok, err|trophy_id ; unplaceTrophy(src, trophy_id) -> ok, err  (owner-only, H2 wires the command)
--          addTrophy(citizenid, trophy_id, points) / removeTrophy(citizenid, trophy_id): internal/admin, no item movement.
-- Placement: item leaves the plot chest via fh_core removeItem (core B7; pcall'd, refused 'fh_removeitem_unavailable' if absent),
--   points = exports.fh_hunting:getTrophyComfort(itemId) (nil = not a trophy; hunting down = refused). Trophy ids are '<item>#<n>'.
-- Events emitted (server-local):
--   'fh:homestead:comfort_changed' (citizenid, newComfort, oldComfort), only when the value changes
--   'fh:homestead:trophy_placed' / 'fh:homestead:trophy_removed' ({ citizenid, trophy_id, comfort })
-- Events consumed: 'fh:homestead:slot_changed' (plot_id, slot_id, tier) from FhHomesteadSlots.setTier;
--   'fh:homestead:unclaimed' ({ citizenid, plot_id }) from server/main.lua.
-- Trophies belong to the plot and are deleted with it on unclaim (FK cascade; the unclaimed handler is the backstop).
--
-- Concurrency: every trophy change on a plot runs under that plot's in-flight lock (busy[plotId]); a second change on the
-- same plot while one is suspended in a MySQL/export await is refused 'fh_busy'. Trophy rows are written only by SQL that
-- also checks the plot owner (INSERT ... SELECT / DELETE ... JOIN fh_plots), and a change counts only if it affected
-- exactly one row. gen[plotId] moves on unclaim so work suspended across an await can tell the plot changed hands.
-- Boot gate: until FhHomesteadSlots.isReady() (slot cache + claims loaded), trophy changes are refused 'fh_not_ready'
-- and getComfort neither caches nor emits (it would compute from empty tiers and stay stale: the load emits nothing).
local cfg = FhHomesteadConfig
local calc = FhComfort
local rules = FhPlotRules

local cache = {}   -- citizenid -> { plotId (claim|nil), lotId (town lot|nil), trophies = { [id] = points }, value }
local byPlot = {}  -- plotId (claim or lot) -> citizenid (only for cached entries)
local busy = {}    -- plotId -> true while a trophy change is in flight
local gen = {}     -- plotId -> unclaim counter

local function log(level, msg) print(('%s[fh_homestead] %s^7'):format(level == 'error' and '^1' or '^3', msg)) end

local function genOf(plotId) return gen[plotId] or 0 end

-- Comfort is the character's best home (H15): max(claim comfort, town lot comfort). plotOf = the claim (trophies live
-- only there), lotOf = the town lot (its own slots only).
local function classPlotOf(citizenid, class)
    if type(citizenid) ~= 'string' or citizenid == '' then return nil end
    if FhHomesteadSlots and FhHomesteadSlots.plotOf then return FhHomesteadSlots.plotOf(citizenid, class) end
    return nil
end
local function plotOf(citizenid) return classPlotOf(citizenid, 'claim') end
local function lotOf(citizenid) return classPlotOf(citizenid, 'town_lot') end

local function isReady()
    if FhHomesteadSlots and FhHomesteadSlots.isReady then return FhHomesteadSlots.isReady() == true end
    return true
end

---@return table tiers, string|nil reason ('fh_not_ready' before the slot load finishes)
local function tiersOf(plotId)
    if FhHomesteadSlots and FhHomesteadSlots.getTiers then
        local tiers, why = FhHomesteadSlots.getTiers(plotId)
        return tiers or {}, why
    end
    return {}
end

-- Same owner, same plot, and no unclaim since generation g was read.
local function stillOwns(citizenid, plotId, g)
    return genOf(plotId) == g and plotOf(citizenid) == plotId
end

---Replace the citizen's cache entry with one for claim plotId (nil = lot-only), keeping the last value and the lot link
---so comfort_changed still compares against what Survival last heard.
local function rebind(citizenid, plotId, trophies)
    local prev = cache[citizenid]
    if prev and prev.plotId and byPlot[prev.plotId] == citizenid then byPlot[prev.plotId] = nil end
    local e = { plotId = plotId, lotId = prev and prev.lotId or nil, trophies = trophies or {}, value = prev and prev.value or nil }
    cache[citizenid] = e
    if plotId then byPlot[plotId] = citizenid end
    return e
end

---Cached entry for the citizen's claim, loading its trophies on first use.
---@return table|nil entry, string|nil reason
local function entryFor(citizenid, plotId)
    local e = cache[citizenid]
    if e and e.plotId == plotId then return e end
    local g = genOf(plotId)
    local ok, rows = pcall(MySQL.query.await, 'SELECT trophy_id, points FROM fh_plot_trophies WHERE plot_id = ?', { plotId })
    if not ok then
        log('warn', 'trophy load failed for ' .. tostring(plotId) .. ': ' .. tostring(rows))
        return nil, 'fh_trophy_failed'
    end
    -- the plot was unclaimed while we read: these rows are not this citizen's any more
    if not stillOwns(citizenid, plotId, g) then return nil, 'fh_no_plot' end
    -- another caller may have loaded it while we were suspended in the query
    e = cache[citizenid]
    if e and e.plotId == plotId then return e end
    local trophies = {}
    for _, r in ipairs(rows or {}) do trophies[r.trophy_id] = tonumber(r.points) or 0 end
    return rebind(citizenid, plotId, trophies)
end

local function drop(citizenid)
    local e = cache[citizenid]
    if e then
        if e.plotId and byPlot[e.plotId] == citizenid then byPlot[e.plotId] = nil end
        if e.lotId and byPlot[e.lotId] == citizenid then byPlot[e.lotId] = nil end
    end
    cache[citizenid] = nil
end

-- Recompute, store, and fire comfort_changed when it differs from the last known value (first computation counts from 0).
-- The only await is the claim's trophy load inside entryFor. Anything read before it can be stale after it, so the claim
-- is re-checked afterwards (one bounded retry via `retried`) and the lot is read only AFTER it; nothing below suspends.
local refresh
function refresh(citizenid, retried)
    local function lastKnown() local c = cache[citizenid] return c and c.value or 0 end
    if not isReady() then
        -- slots/claims still loading: plotOf/tiers are not trustworthy yet. Report the last known value, cache nothing,
        -- emit nothing; the first refresh after the load counts from there.
        return lastKnown()
    end
    local plotId = plotOf(citizenid)
    local e
    if plotId then
        local why
        e, why = entryFor(citizenid, plotId)
        -- the claim moved while we were suspended (released, or swapped for another): recompute once from the new state
        if plotOf(citizenid) ~= plotId or not isReady() then
            if retried or not isReady() then return lastKnown() end
            return refresh(citizenid, true)
        end
        if not e then
            -- could not load (DB error): report the last known value, emit nothing
            return lastKnown()
        end
    end
    local lotId = lotOf(citizenid) -- read after the await
    if not plotId then
        if not lotId then
            local old = lastKnown()
            drop(citizenid)
            if old ~= 0 then TriggerEvent('fh:homestead:comfort_changed', citizenid, 0, old) end
            return 0
        end
        e = cache[citizenid]
        if not e or e.plotId then e = rebind(citizenid, nil, nil) end -- lot-only (or the claim is gone)
    end
    if e.lotId ~= lotId then
        if e.lotId and byPlot[e.lotId] == citizenid then byPlot[e.lotId] = nil end
        e.lotId = lotId
        if lotId then byPlot[lotId] = citizenid end
    end
    local best = 0
    if plotId then
        local tiers, twhy = tiersOf(plotId)
        if twhy then return e.value or 0 end
        best = calc.compute(cfg.plots[plotId], tiers, e.trophies, cfg)
    end
    if lotId then
        local tiers, twhy = tiersOf(lotId)
        if twhy then return e.value or 0 end
        local lot = calc.compute(cfg.plots[lotId], tiers, nil, cfg) -- no trophies on a lot
        if lot > best then best = lot end
    end
    local old = e.value or 0
    e.value = best
    if best ~= old then TriggerEvent('fh:homestead:comfort_changed', citizenid, best, old) end
    return best
end

local function getComfort(citizenid)
    return refresh(citizenid)
end

---Run fn holding plotId's in-flight lock. The lock is released on every path, including an error in fn.
local function withPlotLock(plotId, fn)
    if busy[plotId] then return false, 'fh_busy' end
    busy[plotId] = true
    local r = table.pack(pcall(fn))
    busy[plotId] = nil
    if not r[1] then
        log('error', ('trophy change on %s errored: %s'):format(tostring(plotId), tostring(r[2])))
        return false, 'fh_trophy_failed'
    end
    return table.unpack(r, 2, r.n)
end

-- Row writers. Caller holds the plot lock. Each succeeds only if it affected exactly one row AND the citizen still owns
-- the plot at that moment in the DB, so a write can never land on a plot that changed hands.

---Insert a trophy row for a plot the citizen owned at generation g. Mirrors slots.lua setTier: ownership is checked
---before the write (in SQL) and again after the await; a row that landed on a re-claim is taken back under the lock.
---@return boolean ok, string|nil reason, boolean|nil consumed  consumed = true when the trophy may have been placed and
---  then destroyed with the plot (cascade) or its state is unknown: the caller must NOT hand the item back.
local function insertTrophy(e, citizenid, plotId, trophyId, points, g)
    if not stillOwns(citizenid, plotId, g) then return false, 'fh_no_plot' end
    local ok, affected = pcall(MySQL.update.await,
        'INSERT INTO fh_plot_trophies (plot_id, trophy_id, points) SELECT plot_id, ?, ? FROM fh_plots WHERE plot_id = ? AND citizenid = ?',
        { trophyId, points, plotId, citizenid })
    if not ok then
        log('warn', ('trophy insert %s/%s failed: %s'):format(plotId, trophyId, tostring(affected)))
        return false, 'fh_trophy_failed'
    end
    local landed = (tonumber(affected) or 0) == 1
    if not stillOwns(citizenid, plotId, g) then
        -- unclaimed while we waited. Not landed: nothing to undo. Landed: either the unclaim cascade already removed it
        -- (the trophy went with the plot) or it sits on a re-claim (take it back; no other trophy change on this plot
        -- can have run, we hold busy[plotId]).
        if not landed then return false, 'fh_no_plot' end
        local undone, n = pcall(MySQL.update.await,
            'DELETE FROM fh_plot_trophies WHERE plot_id = ? AND trophy_id = ? AND points = ?', { plotId, trophyId, points })
        if not undone then
            log('error', ('could not undo stale trophy write %s/%s: %s'):format(plotId, trophyId, tostring(n)))
            return false, 'fh_no_plot', true
        end
        return false, 'fh_no_plot', (tonumber(n) or 0) ~= 1
    end
    if not landed then return false, 'fh_no_plot' end
    e.trophies[trophyId] = points
    return true
end

local function deleteTrophy(e, citizenid, plotId, trophyId)
    local ok, affected = pcall(MySQL.update.await,
        'DELETE t FROM fh_plot_trophies t JOIN fh_plots p ON p.plot_id = t.plot_id WHERE t.plot_id = ? AND t.trophy_id = ? AND p.citizenid = ?',
        { plotId, trophyId, citizenid })
    if not ok then
        log('warn', ('trophy delete %s/%s failed: %s'):format(plotId, trophyId, tostring(affected)))
        return false, 'fh_trophy_failed'
    end
    if (tonumber(affected) or 0) ~= 1 then
        -- already gone (cascade on unclaim, or removed elsewhere): the cache was stale, nothing was taken off the wall here
        e.trophies[trophyId] = nil
        return false, 'fh_no_trophy'
    end
    e.trophies[trophyId] = nil
    return true
end

---H13: withPlotLock plus a chest hold from server/main.lua (FhHomesteadClaims.beginChestWrite) for the trophy changes
---that move an item into the plot chest (place refund, unplace), so no unclaim of the plot runs meanwhile
---('fh_chest_busy' there; 'fh_claim_busy' here while an unclaim is in flight).
local function withChestHold(plotId, fn)
    local C = FhHomesteadClaims
    if not (C and C.beginChestWrite) then return false, 'fh_not_ready' end
    local held, hwhy = C.beginChestWrite(plotId)
    if not held then return false, hwhy end
    local r = table.pack(pcall(withPlotLock, plotId, fn))
    C.endChestWrite(plotId)
    if not r[1] then
        log('error', ('trophy change on %s errored: %s'):format(tostring(plotId), tostring(r[2])))
        return false, 'fh_trophy_failed'
    end
    return table.unpack(r, 2, r.n)
end

local function addTrophy(citizenid, trophyId, points)
    local valid, res = calc.checkTrophy(trophyId, points)
    if not valid then return false, res end
    points = res
    if not isReady() then return false, 'fh_not_ready' end
    local plotId = plotOf(citizenid)
    if not plotId then return false, 'fh_no_plot' end
    return withPlotLock(plotId, function()
        local g = genOf(plotId)
        local e, why = entryFor(citizenid, plotId)
        if not e then return false, why end
        if e.trophies[trophyId] then return false, 'fh_trophy_duplicate' end
        local ok, iwhy = insertTrophy(e, citizenid, plotId, trophyId, points, g)
        if not ok then return false, iwhy end
        refresh(citizenid)
        return true
    end)
end

local function removeTrophy(citizenid, trophyId)
    if not isReady() then return false, 'fh_not_ready' end
    local plotId = plotOf(citizenid)
    if not plotId then return false, 'fh_no_plot' end
    return withPlotLock(plotId, function()
        local e, why = entryFor(citizenid, plotId)
        if not e then return false, why end
        if type(trophyId) ~= 'string' or not e.trophies[trophyId] then return false, 'fh_no_trophy' end
        local ok, dwhy = deleteTrophy(e, citizenid, plotId, trophyId)
        refresh(citizenid)
        if not ok then return false, dwhy end
        return true
    end)
end

AddEventHandler('fh:homestead:slot_changed', function(plotId)
    local owner = byPlot[plotId]
    if not owner then
        local ok, row = pcall(MySQL.scalar.await, 'SELECT citizenid FROM fh_plots WHERE plot_id = ?', { plotId })
        owner = ok and row or nil
    end
    if owner then refresh(owner) end
end)

-- Plot released: its trophies are gone with it. Drop it from the cache for whoever had it cached and recompute (their other
-- home may remain; Survival hears one comfort_changed only if the best-home value moved), and bump the generation so any trophy change suspended mid-await aborts instead of writing.
AddEventHandler('fh:homestead:unclaimed', function(data)
    if type(data) ~= 'table' or type(data.plot_id) ~= 'string' then return end
    local plotId = data.plot_id
    gen[plotId] = genOf(plotId) + 1
    local holders = {}
    if type(data.citizenid) == 'string' then holders[data.citizenid] = true end
    if byPlot[plotId] then holders[byPlot[plotId]] = true end
    -- unbind now, before any refresh below can suspend: a plot re-claimed during that await is rebound by its new owner and
    -- a late clear here would wipe that binding
    byPlot[plotId] = nil
    for cid in pairs(holders) do
        local e = cache[cid]
        if e and (e.plotId == plotId or e.lotId == plotId) then
            -- forget the released plot, then recompute from whatever home is left (0 and one event if none)
            if e.plotId == plotId then e.plotId, e.trophies = nil, {} end
            if e.lotId == plotId then e.lotId = nil end
            refresh(cid)
        end
    end
    -- FK ON DELETE CASCADE (0011) already removed the rows with fh_plots; this only fires if that did not happen, and
    -- never touches a plot someone has claimed again since.
    local ok, err = pcall(MySQL.update.await,
        'DELETE t FROM fh_plot_trophies t LEFT JOIN fh_plots p ON p.plot_id = t.plot_id WHERE t.plot_id = ? AND p.plot_id IS NULL',
        { plotId })
    if not ok then log('warn', ('trophy cleanup for unclaimed %s failed: %s'):format(plotId, tostring(err))) end
end)

-- Small wrappers so specs/other code can stub the cross-resource calls.
local function trophyComfortOf(itemId)
    if GetResourceState('fh_hunting') ~= 'started' then
        log('warn', 'fh_hunting not started; trophy placement refused')
        return nil, 'fh_hunting_unavailable'
    end
    local ok, res = pcall(function() return exports.fh_hunting:getTrophyComfort(itemId) end)
    if not ok then
        log('warn', 'fh_hunting:getTrophyComfort failed: ' .. tostring(res))
        return nil, 'fh_hunting_unavailable'
    end
    return tonumber(res)
end

local function chestRef(plotId) return { type = 'chest', id = rules.chestStashId(plotId, 1) } end

local function removeFromChest(plotId, itemId)
    local ok, res, why = pcall(function() return exports.fh_core:removeItem(chestRef(plotId), itemId, 1) end)
    if not ok then
        log('warn', 'fh_core:removeItem unavailable (core B7): ' .. tostring(res))
        return false, 'fh_removeitem_unavailable'
    end
    if not res then return false, why or 'fh_item_not_in_chest' end
    return true
end

---Put one item into the plot chest. @return boolean ok, string|nil reason ('fh_additem_unavailable' when the export
---threw; otherwise fh_core's own refusal reason, e.g. a full chest)
local function giveToChest(plotId, itemId)
    local ok, res, why = pcall(function() return exports.fh_core:addItem(chestRef(plotId), itemId, 1) end)
    if not ok then
        log('warn', 'fh_core:addItem failed: ' .. tostring(res))
        return false, 'fh_additem_unavailable'
    end
    if res ~= true then return false, type(why) == 'string' and why or 'fh_chest_refused' end
    return true
end

local function citizenidOf(src)
    local p = exports['rsg-core']:GetCoreObject().Functions.GetPlayer(src)
    return p and p.PlayerData.citizenid or nil
end

local function placeTrophy(src, itemId)
    if not isReady() then return false, 'fh_not_ready' end
    local cid = citizenidOf(src)
    local plotId = plotOf(cid)
    if not plotId then return false, 'fh_no_plot' end
    return withChestHold(plotId, function()
        local g = genOf(plotId)
        local e, ewhy = entryFor(cid, plotId)
        if not e then return false, ewhy end
        local tiers, twhy = tiersOf(plotId)
        if twhy then return false, twhy end
        local ok, res, trophyId = calc.place({
            citizenid = cid, ownerCitizenid = cid, tiers = tiers, trophies = e.trophies, cfg = cfg, itemId = itemId,
            lookup = trophyComfortOf,
            removeItem = function(id) return removeFromChest(plotId, id) end,
        })
        if not ok then return false, res end
        -- The item is out of the chest. From here every failure puts it back, unless the trophy did land and then went
        -- with the plot on unclaim (consumed): handing it back then would be a free copy.
        local added, why, consumed = insertTrophy(e, cid, plotId, trophyId, res, g)
        if not added and consumed then
            log('warn', ('trophy %s on %s for %s landed, then the plot was unclaimed (gone with it or undo failed); no refund'):format(trophyId, plotId, cid))
            return false, why
        end
        if not added then
            local back, bwhy = giveToChest(plotId, itemId)
            if not back then
                log('error', ('ITEM LOST: trophy place on %s for %s failed (%s) and the refund of %s to %s failed (%s)')
                    :format(plotId, cid, why, itemId, rules.chestStashId(plotId, 1), tostring(bwhy)))
                return false, 'fh_place_refund_failed'
            end
            return false, why
        end
        refresh(cid)
        TriggerEvent('fh:homestead:trophy_placed', { citizenid = cid, trophy_id = trophyId, comfort = res })
        return true, trophyId
    end)
end

local function unplaceTrophy(src, trophyId)
    if not isReady() then return false, 'fh_not_ready' end
    local cid = citizenidOf(src)
    local plotId = plotOf(cid)
    if not plotId then return false, 'fh_no_plot' end
    return withChestHold(plotId, function()
        local g = genOf(plotId)
        local e, ewhy = entryFor(cid, plotId)
        if not e then return false, ewhy end
        local ok, why = calc.canUnplace({ citizenid = cid, ownerCitizenid = cid, trophyId = trophyId, trophies = e.trophies })
        if not ok then return false, why end
        local points = e.trophies[trophyId]
        local itemId = calc.itemOf(trophyId)
        -- Delete first: only a call whose DELETE removed exactly one row may hand the item back, so a repeat can't mint
        -- a second one.
        local removed, dwhy = deleteTrophy(e, cid, plotId, trophyId)
        if not removed then
            refresh(cid)
            return false, dwhy
        end
        local back, bwhy = giveToChest(plotId, itemId)
        if not back then
            -- Chest refused the item: put the trophy back on the wall rather than lose it.
            local restored = insertTrophy(e, cid, plotId, trophyId, points, g)
            refresh(cid)
            if not restored then
                log('error', ('ITEM LOST: trophy unplace %s/%s for %s: refund failed (%s) and the wall row could not be restored')
                    :format(plotId, trophyId, cid, tostring(bwhy)))
                return false, 'fh_unplace_refund_failed'
            end
            return false, bwhy -- trophy is back on the wall; the reason is fh_core's (e.g. chest full)
        end
        refresh(cid)
        TriggerEvent('fh:homestead:trophy_removed', { citizenid = cid, trophy_id = trophyId, comfort = points })
        return true
    end)
end

exports('getComfort', getComfort)
exports('placeTrophy', placeTrophy)
exports('unplaceTrophy', unplaceTrophy)
exports('addTrophy', addTrophy)
exports('removeTrophy', removeTrophy)

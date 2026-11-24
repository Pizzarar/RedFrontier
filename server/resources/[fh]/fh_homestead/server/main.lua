-- fh_homestead server (spec L138-139, M1 L107): fixed plot claim + one chest. The server owns all state.
-- Natives used: GetPlayerPed, GetEntityCoords, IsPlayerAceAllowed (see fh_core/docs/natives.md). NOT runtime-tested (no Cfx key).
-- Props are client-local only (server CreateObject is compiled out on RDR3). TODO(waits on B4c): any networked prop/spawn.
local cfg = FhHomesteadConfig
local rules = FhPlotRules

-- byPlot[plot_id] = citizenid; byOwner[class][citizenid] = plot_id (one plot per character per class, mirrors
-- UNIQUE(citizenid, class)); classByPlot[plot_id] = the class the row was written / loaded with.
local claims = { byPlot = {}, byOwner = { claim = {}, town_lot = {} }, classByPlot = {} }
local ready = false
-- Per-plot in-flight lock shared by claim AND unclaim: plot_id -> true from before the first MySQL await until every
-- exit. A second claim/unclaim of that plot meanwhile gets the retryable 'fh_claim_busy', so no two DB writes for one
-- plot ever interleave (and a stale unclaim can never clear a newer claim's memory).
local busy = {}

local DEFAULT_CLASS = 'claim'
---Normalise a class arg / DB value: missing or empty = 'claim'.
local function classArg(class)
    if type(class) ~= 'string' or class == '' then return DEFAULT_CLASS end
    return class
end

local function ownerBucket(class)
    class = classArg(class)
    local b = claims.byOwner[class]
    if not b then b = {}; claims.byOwner[class] = b end
    return b
end

---Plot id citizenid holds in class (default 'claim'), or nil.
local function plotOfClass(citizenid, class)
    if citizenid == nil then return nil end
    local b = claims.byOwner[classArg(class)]
    return b and b[citizenid] or nil
end

local function setClaim(plotId, citizenid, class)
    claims.byPlot[plotId], claims.classByPlot[plotId] = citizenid, class
    ownerBucket(class)[citizenid] = plotId
end

---Clear plotId / citizenid from the maps, but only the entries that still point at each other: never wipe a newer
---claim another call made meanwhile.
local function clearClaim(plotId, citizenid, class)
    if claims.byPlot[plotId] == citizenid then claims.byPlot[plotId], claims.classByPlot[plotId] = nil, nil end
    local b = claims.byOwner[classArg(class)]
    if b and b[citizenid] == plotId then b[citizenid] = nil end
end

-- Read-only view for server/slots.lua; the claim tables themselves stay private to this file.
FhHomesteadClaims = setmetatable({}, {
    __index = {
        isReady = function() return ready end,
        ownerOf = function(plotId) return claims.byPlot[plotId] end,
        ---plotOf(citizenid, class?) -> plot_id or nil; class defaults to 'claim' (slots/build/comfort read the claim).
        plotOf = function(citizenid, class) return plotOfClass(citizenid, class) end,
        ---classOf(plotId) -> class the claimed plot is held as (DB row), or nil when unclaimed.
        classOf = function(plotId) return claims.classByPlot[plotId] end,
    },
    __newindex = function() error('FhHomesteadClaims is read-only', 2) end,
    __metatable = false,
})

local function core() return exports['rsg-core']:GetCoreObject() end

local function citizenidOf(src)
    local p = core().Functions.GetPlayer(src)
    return p and p.PlayerData.citizenid or nil
end

---citizenidOf that never throws (nil on an rsg-core error): for use while a per-plot lock is held.
local function safeCitizenidOf(src)
    local called, cid = pcall(citizenidOf, src)
    return called and cid or nil
end

local function reply(src, msg)
    if src == 0 then print('[fh_homestead] ' .. msg) else TriggerClientEvent('chat:addMessage', src, { args = { 'fh', msg } }) end
end

local function chestRef(plot) return { type = 'chest', id = rules.chestStashId(plot.id, 1) } end

local function registerChest(plot)
    local ok, why = exports.fh_core:registerContainer(chestRef(plot), {
        coords = plot.chest.coords, label = plot.chest.label or 'Homestead chest',
    })
    if not ok then print(('^1[fh_homestead] chest register failed for %s: %s^7'):format(plot.id, tostring(why))) end
    return ok, why
end

local function loadClaims()
    -- SELECT * so a DB without the 0018 class column still loads (every row is then a claim)
    local rows = MySQL.query.await('SELECT * FROM fh_plots') or {}
    for _, r in ipairs(rows) do
        local plot = cfg.plots[r.plot_id]
        if plot then
            local class = classArg(r.class)
            if class ~= rules.classOf(plot) then
                print(('^3[fh_homestead] fh_plots row %s has class %s but config.lua says %s; using the row^7')
                    :format(r.plot_id, class, rules.classOf(plot)))
            end
            local held = plotOfClass(r.citizenid, class)
            if held and held ~= r.plot_id then
                print(('^1[fh_homestead] %s holds %s and %s in class %s (UNIQUE key missing?); %s ignored^7')
                    :format(r.citizenid, held, r.plot_id, class, r.plot_id))
            else
                setClaim(r.plot_id, r.citizenid, class)
                registerChest(plot)
            end
        else
            print(('^3[fh_homestead] fh_plots row %s has no plot in config.lua; ignored^7'):format(r.plot_id))
        end
    end
    ready = true
end

CreateThread(loadClaims)

-- If fh_core restarts, its registered-container table is gone: register ours again.
AddEventHandler('onResourceStart', function(res)
    if res == 'fh_core' and ready then
        for id in pairs(claims.byPlot) do registerChest(cfg.plots[id]) end
    end
end)

local TOWN_LOT = 'town_lot'

---Rep bump for buying a town lot, taken back on abandon (FhHomesteadConfig.townLot.rep; 0 = no rep change).
local function lotRep()
    local t = cfg.townLot
    return type(t) == 'table' and math.tointeger(t.rep) or 0
end

---Price of a town lot: the plot's own `price`, else FhHomesteadConfig.townLot.price. nil = not a positive integer.
local function lotPrice(plot)
    local t = cfg.townLot
    local price = math.tointeger(plot.price or (type(t) == 'table' and t.price) or nil)
    if not price or price <= 0 then return nil end
    return price
end

---Checks shared by claim and buyLot, all before any await: the plot the player stands in, of `class`, claimable by
---them (plot_rules.canClaim), and not mid-write.
---@return table|nil plot, string citizenid_or_reason
local function precheck(src, class)
    if not ready then return nil, 'fh_not_ready' end
    local citizenid = citizenidOf(src)
    if not citizenid then return nil, 'fh_no_character' end
    local ped = GetPlayerPed(src)
    if ped == 0 then return nil, 'fh_no_player' end
    local coords = GetEntityCoords(ped)
    local plot = rules.plotAt(cfg.plots, coords)
    if not plot then return nil, 'fh_not_in_plot' end
    if rules.classOf(plot) ~= class then return nil, 'fh_wrong_plot_class' end
    local ok, why = rules.canClaim(plot, coords, citizenid, claims)
    if not ok then return nil, why end
    if busy[plot.id] then return nil, 'fh_claim_busy' end
    return plot, citizenid
end

---Reserve plot for citizenid in memory and take the per-plot lock. No await may sit between precheck and this, so a
---second claim/buy in the same tick is refused by canClaim / busy; DB unique keys are the backstop.
local function reserve(plot, citizenid, class)
    setClaim(plot.id, citizenid, class)
    busy[plot.id] = true
end

local function release(plot, citizenid, class)
    busy[plot.id] = nil
    clearClaim(plot.id, citizenid, class)
end

---Write a reserved claim: fh_plots row, chest row, chest registration. On failure the lock is released here; on
---SUCCESS it is still held and the caller releases it once its own follow-up (rep, events) is done.
---@return boolean ok, boolean|nil kept  kept = the write failed but its fh_plots row could not be rolled back, so the
---plot stays held in memory and DB (unclaim it to retry).
local function writeClaim(plot, citizenid, class)
    local plotRow = pcall(MySQL.insert.await, 'INSERT INTO fh_plots (plot_id, citizenid, class) VALUES (?, ?, ?)',
        { plot.id, citizenid, class })
    if not plotRow then
        -- our insert did not happen (e.g. a unique-key conflict with someone else's row): delete nothing
        release(plot, citizenid, class)
        return false
    end
    local done = pcall(MySQL.insert.await, 'INSERT INTO fh_plot_chests (plot_id, chest_id, stash_id) VALUES (?, 1, ?)',
        { plot.id, rules.chestStashId(plot.id, 1) })
    if done then
        -- pcall: an fh_core error must roll back, not leave this plot reserved and `busy` stuck
        local called, registered = pcall(registerChest, plot)
        done = called and registered
    end
    if not done then
        -- roll back only the row this call inserted. Memory follows the DB: a deleted (or already absent) row clears
        -- the reservation; a failed DELETE leaves the row, so the claim stays in memory and an unclaim can retry.
        local rolledBack, affected = pcall(MySQL.update.await, 'DELETE FROM fh_plots WHERE plot_id = ? AND citizenid = ?',
            { plot.id, citizenid })
        busy[plot.id] = nil
        if rolledBack and tonumber(affected) then
            clearClaim(plot.id, citizenid, class)
            return false
        end
        print(('^1[fh_homestead] claim of %s by %s failed and its fh_plots row could not be rolled back (%s); kept as claimed, unclaim it to retry^7')
            :format(plot.id, citizenid, tostring(affected)))
        return false, true
    end
    return true
end

---Claim the plot containing the player's server-side ped position. class (default 'claim') is the class the caller
---means to claim; the plot you stand in must be of that class (a town lot is never claimed by /fh_claim).
---@return boolean ok, string|nil reason
local function claim(src, class)
    class = classArg(class)
    local plot, citizenid = precheck(src, class)
    if not plot then return false, citizenid end
    reserve(plot, citizenid, class)
    if not writeClaim(plot, citizenid, class) then return false, 'fh_claim_failed' end
    busy[plot.id] = nil
    TriggerEvent('fh:homestead:claimed', { src = src, citizenid = citizenid, plot_id = plot.id, region_id = plot.region,
        class = class })
    return true, plot.id
end

---Pay a successful lot charge back to the SAME character (by citizenid: online -> paid now, offline -> queued by
---fh_economy). Called at most once per buy. Only a failed credit is MONEY LOST.
local function refundLot(citizenid, price, plot, kept)
    local called, ok, err = pcall(function()
        return exports.fh_economy:credit(citizenid, price, 'town_lot_refund:' .. plot.id, plot.region)
    end)
    if not called or ok ~= true then
        print(('^1[fh_homestead] MONEY LOST: town lot %s refund of $%d to citizenid=%s failed (%s); pay it back by hand^7')
            :format(plot.id, price, citizenid, tostring(called and err or ok)))
    end
    if kept then
        print(('^1[fh_homestead] town lot %s purchase by %s failed and was refunded, but its fh_plots row is still held; admin: fh_unclaim %s^7')
            :format(plot.id, citizenid, plot.id))
    end
end

---After a lot is written (lock held by buyLot): rep +townLot.rep in the lot region, then claimed + lot_bought.
local function lotBought(src, citizenid, plot, price)
    local repDelta = lotRep()
    if repDelta ~= 0 then
        -- rep() credits whoever is loaded on src: skip it if the player switched character during the write
        local repOk, repErr = false, 'character_changed'
        if safeCitizenidOf(src) == citizenid then
            local rc, rok, rerr = pcall(function() return exports.fh_economy:rep(src, plot.region, repDelta, 'town_lot') end)
            repOk, repErr = rc and rok == true, rc and rerr or rok
        end
        if not repOk then
            print(('^3[fh_homestead] town lot %s bought by %s but rep +%d in %s failed (%s)^7')
                :format(plot.id, citizenid, repDelta, tostring(plot.region), tostring(repErr)))
        end
    end
    TriggerEvent('fh:homestead:claimed', { src = src, citizenid = citizenid, plot_id = plot.id, region_id = plot.region,
        class = TOWN_LOT })
    TriggerEvent('fh:homestead:lot_bought', { src = src, citizenid = citizenid, plot_id = plot.id,
        region_id = plot.region, price = price })
end

---Buy the town lot the player stands in (class 'town_lot', claimable). Order: checks (a second lot is refused here,
---before any money moves) -> reserve + per-plot lock -> fh_economy.charge -> the claim write. Any failure after the
---charge credits the same amount back once. On success: rep +townLot.rep in the lot's region.
---@return boolean ok, string plot_id_or_reason
local function buyLot(src)
    local plot, citizenid = precheck(src, TOWN_LOT)
    if not plot then return false, citizenid end
    local price = lotPrice(plot)
    if not price then return false, 'fh_lot_unpriced' end
    reserve(plot, citizenid, TOWN_LOT)
    -- no await since precheck: charge debits the character read there
    local called, charged, cerr = pcall(function()
        return exports.fh_economy:charge(src, price, 'town_lot:' .. plot.id, plot.region)
    end)
    if not called or charged ~= true then
        release(plot, citizenid, TOWN_LOT)
        if not called then
            print(('^3[fh_homestead] fh_economy:charge errored for lot %s: %s^7'):format(plot.id, tostring(charged)))
            return false, 'fh_charge_unavailable'
        end
        return false, type(cerr) == 'string' and cerr or 'fh_charge_failed'
    end
    local ok, kept = writeClaim(plot, citizenid, TOWN_LOT)
    if not ok then
        refundLot(citizenid, price, plot, kept)
        return false, 'fh_claim_failed'
    end
    -- the lot is written; rep + events run with the per-plot lock still held, so no unclaim can slip in between
    -- (an unclaimed event before claimed/lot_bought). pcall: whatever throws, the lock is released.
    local fin, ferr = pcall(lotBought, src, citizenid, plot, price)
    busy[plot.id] = nil
    if not fin then
        print(('^1[fh_homestead] town lot %s bought by %s; rep/events after the purchase errored: %s^7')
            :format(plot.id, citizenid, tostring(ferr)))
    end
    return true, plot.id
end

---Abandoning a town lot takes the purchase rep back from the owner by citizenid (fh_economy.repByCitizenid, idea-804:
---same clamp + ledger as rep(), works with the owner online or offline). Runs under the per-plot lock, so nothing here
---may throw (pcall). Returns ok, reason when not ok.
local function takeLotRep(owner, region, delta, reason)
    local rc, rok, rerr = pcall(function() return exports.fh_economy:repByCitizenid(owner, region, delta, reason) end)
    if rc and rok == true then return true end
    return false, tostring(rc and rerr or rok)
end

---Release a plot. Owner (by src) or admin (src 0 = console). Chest contents stay in the stash. With no plotId the
---caller's CLAIM is released; a town lot is only released by naming its id. The class comes from the plot's row.
---Town lot (abandon, no money back): rep -townLot.rep in the lot's region for the owner, before the DELETE. The owner
---abandoning their own lot is refused if that rep change fails (so buy/abandon/rebuy never farms rep). An admin can
---always clear a lot: the rep-back is taken by citizenid (owner online or offline); if that call fails or throws the lot
---is released anyway and the skipped rep-back is logged.
---TODO: spill leftover chest items to a drop bag on unclaim; until then a later owner of the plot inherits them.
---@return boolean ok, string|nil reason
local function unclaim(src, plotId)
    if not ready then return false, 'fh_not_ready' end
    local isAdmin = src == 0 or IsPlayerAceAllowed(src, 'command.fh_unclaim')
    local citizenid = src ~= 0 and citizenidOf(src) or nil
    if not plotId then plotId = plotOfClass(citizenid, DEFAULT_CLASS) end
    if not plotId then return false, 'fh_no_plot' end
    local ok, why = rules.canUnclaim(plotId, citizenid, isAdmin, claims)
    if not ok then return false, why end
    -- a claim or another unclaim of this plot is mid-write: retry once it has landed or rolled back
    if busy[plotId] then return false, 'fh_claim_busy' end
    local owner = claims.byPlot[plotId]
    local class = claims.classByPlot[plotId] or rules.classOf(cfg.plots[plotId])
    local region = cfg.plots[plotId] and cfg.plots[plotId].region
    busy[plotId] = true
    local repBack = class == TOWN_LOT and lotRep() or 0
    local repTaken, repWhy = false, nil
    if repBack ~= 0 then
        repTaken, repWhy = takeLotRep(owner, region, -repBack, 'town_lot_abandon')
        if not repTaken and citizenid == owner then
            busy[plotId] = nil
            return false, 'fh_rep_failed'
        end
    end
    local deleted, affected = pcall(MySQL.update.await, 'DELETE FROM fh_plots WHERE plot_id = ? AND citizenid = ?', { plotId, owner })
    affected = deleted and tonumber(affected) or nil
    if not affected or affected == 0 then
        -- 0 rows under the lock = the DB has no (plot, owner) row (removed outside this server): drop the stale memory
        -- so memory matches the DB again (the lot is gone, so a rep-back stays taken). An error / unknown count = the
        -- row may still be there: keep memory and give a rep-back taken above back to the owner.
        if affected == 0 then
            clearClaim(plotId, owner, class)
        elseif repTaken then
            local back, backWhy = takeLotRep(owner, region, repBack, 'town_lot_abandon_undo')
            if not back then
                print(('^1[fh_homestead] unclaim of lot %s failed after its rep-back; restoring rep +%d in %s to %s failed (%s): fix by hand^7')
                    :format(plotId, repBack, tostring(region), owner, tostring(backWhy)))
            end
        end
        busy[plotId] = nil
        return false, 'fh_unclaim_failed'
    end
    busy[plotId] = nil
    clearClaim(plotId, owner, class)
    if repBack ~= 0 and not repTaken then
        print(('^3[fh_homestead] town lot %s released by admin without rep-back: citizenid=%s region=%s amount=-%d (%s): fix by hand^7')
            :format(plotId, owner, tostring(region), repBack, tostring(repWhy)))
    end
    TriggerEvent('fh:homestead:unclaimed', { src = src, citizenid = owner, plot_id = plotId })
    return true, plotId
end

---Plot id the character holds in class (default 'claim'), or nil. getPlot(cid) is the homestead claim only, never
---a town lot (fh_hands and the other callers rely on that).
local function getPlot(citizenid, class) return plotOfClass(citizenid, class) end

---Plot ids claimed by anyone (every class), as a list. Read-only (for fh_ui's /where plot "unclaimed" pick).
local function claimedPlots()
    local out = {}
    for plotId in pairs(claims.byPlot) do out[#out + 1] = plotId end
    return out
end

---H9 plot facts for other resources (@alife raids, law AI): { class, raidable, lawSafe, owner } or nil for an unknown
---plot id. raidable = class 'claim', lawSafe = class 'town_lot'; owner = citizenid or nil (unclaimed). Class is the
---held row's class, else config.lua's.
-- Workaround: report only, nothing enforces lawSafe/raidable yet; follow-up idea-803 (@a-life) enforces it.
local function plotInfo(plotId)
    local plot = type(plotId) == 'string' and cfg.plots[plotId] or nil
    if not plot then return nil end
    local class = claims.classByPlot[plotId] or rules.classOf(plot)
    return { class = class, raidable = class == DEFAULT_CLASS, lawSafe = class == TOWN_LOT, owner = claims.byPlot[plotId] }
end

---Safe zone query (spec L139: homestead is a safe zone). True when coords are within the safe radius of a CLAIMED
---plot: FhHomesteadConfig.baseSafeRadius (else the plot radius) plus the built fence's safeRadiusBonus. An owned town
---lot (H9) counts too, radius = its plot.radius, no fence bonus. Unclaimed plots (either class) and everything before
---the claim load are not safe. Before the slot cache is loaded the fence bonus is not counted.
---TODO(fh_zones): AI/damage handling and the real zone registry live in fh_zones; nothing enforces this yet.
local plotIds = {}
for id in pairs(cfg.plots) do plotIds[#plotIds + 1] = id end
table.sort(plotIds)

---Shared rule of isInSafeZone and lawSafeAt: first owned plot (sorted id order) whose safe radius contains coords, or
---nil. lawSafeOnly = only plots whose plotInfo says lawSafe (town lots); owner (optional) = only plots that citizenid
---holds. Bad/nil coords: dist is nil, so nil.
local function safePlotAt(coords, lawSafeOnly, owner)
    if not ready then return nil end
    local slots = FhHomesteadSlots -- server/slots.lua (loaded after this file)
    for _, id in ipairs(plotIds) do
        local holder = claims.byPlot[id]
        if holder and (owner == nil or holder == owner) and (not lawSafeOnly or plotInfo(id).lawSafe) then
            local plot = cfg.plots[id]
            local tiers = slots and slots.getTiers and slots.getTiers(id) or {}
            local d = rules.dist(plot.center, coords)
            if d and d <= FhBuildRules.safeRadiusFor(plot, tiers, cfg.baseSafeRadius) then return id end
        end
    end
    return nil
end

local function isInSafeZone(coords)
    return safePlotAt(coords) ~= nil
end

---idea-803 (@a-life): plot id of the law-safe plot (town lot) that `citizenid` owns and coords fall in (within
---plot.radius, same rule as isInSafeZone), else nil. nil/empty citizenid, a non-owner in someone else's lot, wilderness
---claims, unowned lots and bad/nil coords = nil. Never throws.
local function lawSafeAt(coords, citizenid)
    if type(citizenid) ~= 'string' or citizenid == '' then return nil end
    local ok, id = pcall(safePlotAt, coords, true, citizenid)
    return ok and id or nil
end

---Is chest n of the plot usable? 1 = the claim chest; 2+ = the matching chest_<n> slot must be built.
local function chestBuilt(plot, n)
    if n == 1 then return true end
    local slots = FhHomesteadSlots
    if not (slots and slots.isReady and slots.isReady()) then return false end
    local slotId = 'chest_' .. n
    if FhBuildRules.chestNumber(slotId, plot.slots and plot.slots[slotId]) ~= n then return false end
    return (slots.getTiers(plot.id)[slotId] or 0) >= 1
end

-- Client prompt -> request. The server revalidates ownership and reach (fh_core.open re-checks distance from the
-- server-side ped position; fh_inventory checks again).
RegisterNetEvent('fh:homestead:open_chest', function(payload)
    local src = source
    if not ready then return end
    if type(payload) ~= 'table' or type(payload.plot_id) ~= 'string' then return end
    local plot = cfg.plots[payload.plot_id]
    if not plot then return end
    -- H2: payload.chest picks an extra chest (chest_2/chest_3 slots); default 1 = the claim chest
    local n = payload.chest == nil and 1 or (type(payload.chest) == 'number' and math.tointeger(payload.chest))
    if not n or n < 1 then return end
    local ok, why = rules.canOpenChest(plot.id, citizenidOf(src), claims)
    if not ok then return reply(src, 'chest: ' .. why) end
    if not chestBuilt(plot, n) then return reply(src, 'chest: fh_chest_not_built') end
    ok, why = exports.fh_core:open(src, { type = 'chest', id = rules.chestStashId(plot.id, n) })
    if not ok then reply(src, 'chest: ' .. tostring(why)) end
end)

-- Client asks which chests to draw; props are cosmetic, so sending every configured chest is fine.
lib.callback.register('fh:homestead:plots', function()
    local out = {}
    for id, p in pairs(cfg.plots) do
        out[#out + 1] = { id = id, coords = p.chest.coords, heading = p.chest.heading, model = p.chest.model }
    end
    return out
end)

lib.addCommand('fh_claim', { help = 'Claim the homestead plot you are standing in' }, function(src)
    local ok, res = claim(src)
    reply(src, ok and ('fh_claim: claimed plot ' .. res) or ('fh_claim: ' .. tostring(res)))
end)

lib.addCommand('fh_buylot', { help = 'Buy the town lot you are standing in' }, function(src)
    local ok, res = buyLot(src)
    reply(src, ok and ('fh_buylot: bought lot ' .. res) or ('fh_buylot: ' .. tostring(res)))
end)

lib.addCommand('fh_unclaim', { help = 'Release your claim (a town lot: fh_unclaim <lot_id>; admins: any plot id)' }, function(src, args, raw)
    local plotId = tostring(raw or ''):match('^%S+%s+(%S+)')
    local ok, res = unclaim(src, plotId)
    reply(src, ok and ('fh_unclaim: released plot ' .. res) or ('fh_unclaim: ' .. tostring(res)))
end)

exports('claim', claim)
exports('unclaim', unclaim)
exports('buyLot', buyLot)
exports('getPlot', getPlot)
exports('claimedPlots', claimedPlots)
exports('isInSafeZone', isInSafeZone)
exports('plotInfo', plotInfo)
exports('lawSafeAt', lawSafeAt)

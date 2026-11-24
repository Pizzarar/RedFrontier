-- fh_homestead server (spec L138-139, M1 L107): fixed plot claim + one chest. The server owns all state.
-- Natives used: GetPlayerPed, GetEntityCoords, IsPlayerAceAllowed (see fh_core/docs/natives.md). NOT runtime-tested (no Cfx key).
-- Props are client-local only (server CreateObject is compiled out on RDR3). TODO(waits on B4c): any networked prop/spawn.
local cfg = FhHomesteadConfig
local rules = FhPlotRules

-- byPlot[plot_id] = citizenid; byOwner[class][citizenid] = plot_id (one plot per character per class, mirrors
-- UNIQUE(citizenid, class)); classByPlot[plot_id] = the class the row was written / loaded with.
local claims = { byPlot = {}, byOwner = { claim = {}, town_lot = {} }, classByPlot = {} }
local ready = false
local claiming = {} -- plot_id -> true while a claim's DB writes are in flight (unclaim waits for it)

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
    },
    __newindex = function() error('FhHomesteadClaims is read-only', 2) end,
    __metatable = false,
})

local function core() return exports['rsg-core']:GetCoreObject() end

local function citizenidOf(src)
    local p = core().Functions.GetPlayer(src)
    return p and p.PlayerData.citizenid or nil
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

---Claim the plot containing the player's server-side ped position. class (default 'claim') is the class the caller
---means to claim; the plot you stand in must be of that class (a town lot is never claimed by /fh_claim).
---@return boolean ok, string|nil reason
local function claim(src, class)
    if not ready then return false, 'fh_not_ready' end
    class = classArg(class)
    local citizenid = citizenidOf(src)
    if not citizenid then return false, 'fh_no_character' end
    local ped = GetPlayerPed(src)
    if ped == 0 then return false, 'fh_no_player' end
    local coords = GetEntityCoords(ped)
    local plot = rules.plotAt(cfg.plots, coords)
    if not plot then return false, 'fh_not_in_plot' end
    if rules.classOf(plot) ~= class then return false, 'fh_wrong_plot_class' end
    local ok, why = rules.canClaim(plot, coords, citizenid, claims)
    if not ok then return false, why end
    -- reserve in memory first so a second claim in the same tick is refused; DB unique keys are the backstop
    setClaim(plot.id, citizenid, class)
    claiming[plot.id] = true
    local plotRow = pcall(MySQL.insert.await, 'INSERT INTO fh_plots (plot_id, citizenid, class) VALUES (?, ?, ?)',
        { plot.id, citizenid, class })
    if not plotRow then
        -- our insert did not happen (e.g. a unique-key conflict with someone else's row): delete nothing
        claiming[plot.id] = nil
        clearClaim(plot.id, citizenid, class)
        return false, 'fh_claim_failed'
    end
    local done = pcall(MySQL.insert.await, 'INSERT INTO fh_plot_chests (plot_id, chest_id, stash_id) VALUES (?, 1, ?)',
        { plot.id, rules.chestStashId(plot.id, 1) })
    if done then
        -- pcall: an fh_core error must roll back, not leave this plot reserved and `claiming` stuck
        local called, registered = pcall(registerChest, plot)
        done = called and registered
    end
    if not done then
        -- roll back only the row this call inserted
        pcall(MySQL.update.await, 'DELETE FROM fh_plots WHERE plot_id = ? AND citizenid = ?', { plot.id, citizenid })
        claiming[plot.id] = nil
        clearClaim(plot.id, citizenid, class)
        return false, 'fh_claim_failed'
    end
    claiming[plot.id] = nil
    TriggerEvent('fh:homestead:claimed', { src = src, citizenid = citizenid, plot_id = plot.id, region_id = plot.region })
    return true, plot.id
end

---Release a plot. Owner (by src) or admin (src 0 = console). Chest contents stay in the stash. With no plotId the
---caller's CLAIM is released; a town lot is only released by naming its id. The class comes from the plot's row.
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
    -- the claim's own writes (row, chest row, chest register) are still in flight: it either lands or rolls back
    if claiming[plotId] then return false, 'fh_claim_busy' end
    local owner = claims.byPlot[plotId]
    local class = claims.classByPlot[plotId] or rules.classOf(cfg.plots[plotId])
    local deleted, affected = pcall(MySQL.update.await, 'DELETE FROM fh_plots WHERE plot_id = ? AND citizenid = ?', { plotId, owner })
    -- a concurrent unclaim that already deleted the row affects 0 rows: only one caller emits the event
    if not deleted or (tonumber(affected) or 0) == 0 then
        if deleted then clearClaim(plotId, owner, class) end
        return false, 'fh_unclaim_failed'
    end
    clearClaim(plotId, owner, class)
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

---Safe zone query (spec L139: homestead is a safe zone). True when coords are within the safe radius of a CLAIMED
---plot: FhHomesteadConfig.baseSafeRadius (else the plot radius) plus the built fence's safeRadiusBonus. Unclaimed plots
---and everything before the claim load are not safe. Before the slot cache is loaded the fence bonus is not counted.
---TODO(fh_zones): AI/damage handling and the real zone registry live in fh_zones; nothing enforces this yet.
local plotIds = {}
for id in pairs(cfg.plots) do plotIds[#plotIds + 1] = id end
table.sort(plotIds)

local function isInSafeZone(coords)
    if not ready then return false end
    local slots = FhHomesteadSlots -- server/slots.lua (loaded after this file)
    for _, id in ipairs(plotIds) do
        if claims.byPlot[id] then
            local plot = cfg.plots[id]
            local tiers = slots and slots.getTiers and slots.getTiers(id) or {}
            local d = rules.dist(plot.center, coords)
            if d and d <= FhBuildRules.safeRadius(plot, tiers, cfg.baseSafeRadius) then return true end
        end
    end
    return false
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

lib.addCommand('fh_unclaim', { help = 'Release your plot (admins: fh_unclaim <plot_id>)' }, function(src, args, raw)
    local plotId = tostring(raw or ''):match('^%S+%s+(%S+)')
    local ok, res = unclaim(src, plotId)
    reply(src, ok and ('fh_unclaim: released plot ' .. res) or ('fh_unclaim: ' .. tostring(res)))
end)

exports('claim', claim)
exports('unclaim', unclaim)
exports('getPlot', getPlot)
exports('claimedPlots', claimedPlots)
exports('isInSafeZone', isInSafeZone)

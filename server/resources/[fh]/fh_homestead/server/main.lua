-- fh_homestead server (spec L138-139, M1 L107): fixed plot claim + one chest. The server owns all state.
-- Natives used: GetPlayerPed, GetEntityCoords, IsPlayerAceAllowed (see fh_core/docs/natives.md). NOT runtime-tested (no Cfx key).
-- Props are client-local only (server CreateObject is compiled out on RDR3). TODO(waits on B4c): any networked prop/spawn.
local cfg = FhHomesteadConfig
local rules = FhPlotRules

local claims = { byPlot = {}, byOwner = {} }
local ready = false

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
    local rows = MySQL.query.await('SELECT plot_id, citizenid FROM fh_plots') or {}
    for _, r in ipairs(rows) do
        local plot = cfg.plots[r.plot_id]
        if plot then
            claims.byPlot[r.plot_id], claims.byOwner[r.citizenid] = r.citizenid, r.plot_id
            registerChest(plot)
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

---Claim the plot containing the player's server-side ped position.
---@return boolean ok, string|nil reason
local function claim(src)
    if not ready then return false, 'fh_not_ready' end
    local citizenid = citizenidOf(src)
    if not citizenid then return false, 'fh_no_character' end
    local ped = GetPlayerPed(src)
    if ped == 0 then return false, 'fh_no_player' end
    local coords = GetEntityCoords(ped)
    local plot = rules.plotAt(cfg.plots, coords)
    if not plot then return false, 'fh_not_in_plot' end
    local ok, why = rules.canClaim(plot, coords, citizenid, claims)
    if not ok then return false, why end
    -- reserve in memory first so a second claim in the same tick is refused; DB unique keys are the backstop
    claims.byPlot[plot.id], claims.byOwner[citizenid] = citizenid, plot.id
    local plotRow = pcall(MySQL.insert.await, 'INSERT INTO fh_plots (plot_id, citizenid) VALUES (?, ?)', { plot.id, citizenid })
    if not plotRow then
        -- our insert did not happen (e.g. a unique-key conflict with someone else's row): delete nothing
        claims.byPlot[plot.id], claims.byOwner[citizenid] = nil, nil
        return false, 'fh_claim_failed'
    end
    local done = pcall(MySQL.insert.await, 'INSERT INTO fh_plot_chests (plot_id, chest_id, stash_id) VALUES (?, 1, ?)',
        { plot.id, rules.chestStashId(plot.id, 1) })
    done = done and registerChest(plot)
    if not done then
        -- roll back only the row this call inserted
        pcall(MySQL.update.await, 'DELETE FROM fh_plots WHERE plot_id = ? AND citizenid = ?', { plot.id, citizenid })
        claims.byPlot[plot.id], claims.byOwner[citizenid] = nil, nil
        return false, 'fh_claim_failed'
    end
    TriggerEvent('fh:homestead:claimed', { src = src, citizenid = citizenid, plot_id = plot.id, region_id = plot.region })
    return true, plot.id
end

---Release a plot. Owner (by src) or admin (src 0 = console). Chest contents stay in the stash.
---TODO: spill leftover chest items to a drop bag on unclaim; until then a later owner of the plot inherits them.
---@return boolean ok, string|nil reason
local function unclaim(src, plotId)
    if not ready then return false, 'fh_not_ready' end
    local isAdmin = src == 0 or IsPlayerAceAllowed(src, 'command.fh_unclaim')
    local citizenid = src ~= 0 and citizenidOf(src) or nil
    if not plotId then plotId = citizenid and claims.byOwner[citizenid] end
    if not plotId then return false, 'fh_no_plot' end
    local ok, why = rules.canUnclaim(plotId, citizenid, isAdmin, claims)
    if not ok then return false, why end
    local owner = claims.byPlot[plotId]
    local deleted, affected = pcall(MySQL.update.await, 'DELETE FROM fh_plots WHERE plot_id = ? AND citizenid = ?', { plotId, owner })
    -- a concurrent unclaim that already deleted the row affects 0 rows: only one caller emits the event
    if not deleted or (tonumber(affected) or 0) == 0 then
        if deleted and claims.byPlot[plotId] == owner then claims.byPlot[plotId], claims.byOwner[owner] = nil, nil end
        return false, 'fh_unclaim_failed'
    end
    claims.byPlot[plotId], claims.byOwner[owner] = nil, nil
    TriggerEvent('fh:homestead:unclaimed', { src = src, citizenid = owner, plot_id = plotId })
    return true, plotId
end

---Plot id the character owns, or nil.
local function getPlot(citizenid) return claims.byOwner[citizenid] end

---Safe zone query (spec L139: homestead is a safe zone). STUB: true when coords are inside ANY configured plot,
---claimed or not. TODO(fh_zones): AI/damage handling and the real zone registry live in fh_zones; nothing enforces this yet.
local function isInSafeZone(coords)
    return rules.plotAt(cfg.plots, coords) ~= nil
end

-- Client prompt -> request. The server revalidates ownership and reach (fh_core.open re-checks distance from the
-- server-side ped position; fh_inventory checks again).
RegisterNetEvent('fh:homestead:open_chest', function(payload)
    local src = source
    if not ready then return end
    if type(payload) ~= 'table' or type(payload.plot_id) ~= 'string' then return end
    local plot = cfg.plots[payload.plot_id]
    if not plot then return end
    local ok, why = rules.canOpenChest(plot.id, citizenidOf(src), claims)
    if not ok then return reply(src, 'chest: ' .. why) end
    ok, why = exports.fh_core:open(src, chestRef(plot))
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
exports('isInSafeZone', isInSafeZone)

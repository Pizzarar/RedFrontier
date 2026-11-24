-- Owned homestead campfire heat (plan survival-02, F2). A player's own homestead campfire stations become heat
-- sources through the existing exports.fh_survival:setHeatSource / removeHeatSource (server/actions.lua), so the
-- warm tick handles them with no change. Ownership only decides which fires exist: any player near a fire is
-- warmed. Stations come from exports.fh_homestead:getStations(citizenid) -> { plot_id, slot_id, station_type,
-- coords }; the decision/diff logic is FhSurvivalHomesteadHeat (pure, spec'd).
-- fh_homestead has no station-removed event and no all-stations accessor (station_built carries no coords, and
-- slot_changed carries no citizenid), so sources are synced per online player on a timer and on player
-- load/unload, ids `hs:<plot_id>:<slot_id>`, stale ids removed. Gate: GetResourceState('fh_homestead') ==
-- 'started', as S4b does; while homestead is stopped we clear our sources and leave the seeded Campfires alone.
local cfg = FhSurvivalConfig
local H = FhSurvivalHomesteadHeat

local ownedByCid = {}   -- [citizenid] = { [sourceId] = true } heat sources we registered for that character
local onlineCitizen = {} -- [src] = citizenid (for cleanup on drop, when rsg-core may already have forgotten them)

local function citizenOf(src)
    local ok, p = pcall(function() return exports['rsg-core']:GetPlayer(src) end)
    return ok and p and p.PlayerData and p.PlayerData.citizenid or nil
end

local function clearCid(cid)
    local owned = ownedByCid[cid]
    if not owned then return end
    for id in pairs(owned) do exports.fh_survival:removeHeatSource(id) end
    ownedByCid[cid] = nil
end

local function syncCitizen(cid)
    local started = GetResourceState('fh_homestead') == 'started'
    local stations = {}
    if started then
        local ok, res = pcall(function() return exports.fh_homestead:getStations(cid) end)
        if ok and type(res) == 'table' then stations = res end
    end
    local owned = ownedByCid[cid]
    if not owned then
        owned = {}
        ownedByCid[cid] = owned
    end
    local adds, removes = H.reconcile(started, owned, stations, cfg.HomesteadHeatRadius)
    for _, id in ipairs(removes) do
        exports.fh_survival:removeHeatSource(id)
        owned[id] = nil
    end
    for _, a in ipairs(adds) do
        if exports.fh_survival:setHeatSource(a.id, a.coords, a.radius) == true then
            owned[a.id] = true
        end
    end
end

-- ---- lifecycle ----

AddEventHandler('RSGCore:Server:PlayerLoaded', function(Player)
    local src = Player and Player.PlayerData and Player.PlayerData.source
    local cid = Player and Player.PlayerData and Player.PlayerData.citizenid
    if not (src and cid) then return end
    local old = onlineCitizen[src]
    onlineCitizen[src] = cid
    if old and old ~= cid then clearCid(old) end -- character switch on the same src
    syncCitizen(cid)
end)

local function forget(src)
    local cid = onlineCitizen[src]
    onlineCitizen[src] = nil
    if cid then clearCid(cid) end
end
AddEventHandler('RSGCore:Server:OnPlayerUnload', function(src) forget(src) end)
AddEventHandler('playerDropped', function() forget(source) end)

-- Homestead (re)started: re-sync every online player. Homestead stopped: clear ours at once (the timer + gate
-- would too), leaving the seeded config.Campfires untouched. Own resource start: pick up players already online.
AddEventHandler('onResourceStart', function(res)
    if res == 'fh_homestead' then
        for _, cid in pairs(onlineCitizen) do syncCitizen(cid) end
    elseif res == GetCurrentResourceName() then
        CreateThread(function()
            for _, id in ipairs(GetPlayers()) do
                local src = tonumber(id)
                local cid = src and citizenOf(src)
                if cid then
                    onlineCitizen[src] = cid
                    syncCitizen(cid)
                end
            end
        end)
    end
end)
AddEventHandler('onResourceStop', function(res)
    if res == 'fh_homestead' then
        for cid in pairs(ownedByCid) do clearCid(cid) end
    end
end)

-- Periodic re-sync: picks up builds/removals (no removal event exists) and any missed load/unload.
CreateThread(function()
    while true do
        Wait(math.max(1, cfg.HomesteadHeatSyncSeconds or 15) * 1000)
        local seen = {}
        for _, id in ipairs(GetPlayers()) do
            local src = tonumber(id)
            local cid = src and citizenOf(src)
            if cid then
                seen[cid] = true
                onlineCitizen[src] = cid
                syncCitizen(cid)
            end
        end
        for cid in pairs(ownedByCid) do
            if not seen[cid] then clearCid(cid) end -- left without an unload event: drop the stale sources
        end
    end
end)

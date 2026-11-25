-- Homestead campfire heat (plan survival-02 F2, idea-893). Any built homestead campfire near an online player
-- (whether or not its plot owner is online) becomes a heat source through the existing
-- exports.fh_survival:setHeatSource / removeHeatSource (server/actions.lua), so the warm tick handles it with
-- no change. On the periodic timer, each online player's server-side ped coords are queried against
-- exports.fh_homestead:stationAt(coords, maxDist, 'campfire') -> { plot_id, slot_id, station_type, coords } | nil;
-- the decision/diff logic is FhSurvivalHomesteadHeat (pure, spec'd). Ids are `hs:<plot_id>:<slot_id>`; ids no
-- player is near any more are removed. Gate: GetResourceState('fh_homestead') == 'started'; while homestead is
-- stopped we clear our sources and leave the seeded config.Campfires alone.
local cfg = FhSurvivalConfig
local H = FhSurvivalHomesteadHeat

local registered = {} -- [sourceId] = true; `hs:*` heat sources currently registered by this module

local function coordsOf(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return nil end
    local c = GetEntityCoords(ped)
    return { x = c.x, y = c.y, z = c.z }
end

local function clearAll()
    for id in pairs(registered) do
        exports.fh_survival:removeHeatSource(id)
        registered[id] = nil
    end
end

local function syncAll()
    local started = GetResourceState('fh_homestead') == 'started'
    local found = {}
    if started then
        local searchDist = H.searchRadius(cfg.HomesteadHeatSearchRadius)
        for _, id in ipairs(GetPlayers()) do
            local src = tonumber(id)
            local pos = src and coordsOf(src)
            if pos then
                local ok, res = pcall(function()
                    return exports.fh_homestead:stationAt(pos, searchDist, H.CAMPFIRE)
                end)
                if ok and type(res) == 'table' then
                    found[#found + 1] = res
                end
            end
        end
    end
    local adds, removes = H.reconcile(started, registered, found, cfg.HomesteadHeatRadius)
    for _, id in ipairs(removes) do
        exports.fh_survival:removeHeatSource(id)
        registered[id] = nil
    end
    for _, a in ipairs(adds) do
        if exports.fh_survival:setHeatSource(a.id, a.coords, a.radius) == true then
            registered[a.id] = true
        end
    end
end

-- ---- lifecycle ----

-- Homestead (re)started or own resource started: sync online players. Homestead stopped: clear ours at once
-- (the timer + gate would too), leaving the seeded config.Campfires untouched.
AddEventHandler('onResourceStart', function(res)
    if res == 'fh_homestead' or res == GetCurrentResourceName() then
        CreateThread(syncAll)
    end
end)
AddEventHandler('onResourceStop', function(res)
    if res == 'fh_homestead' then clearAll() end
end)

-- Periodic re-sync: discovers campfires near online players and removes `hs:*` ids no player is near any more.
CreateThread(function()
    while true do
        Wait(math.max(1, cfg.HomesteadHeatSyncSeconds or 15) * 1000)
        syncAll()
    end
end)

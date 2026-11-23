-- fh_survival server core (plan survival-01, S2). Needs are positive timed buffs held by fh_buffs; this resource
-- only reads them (exports.fh_buffs:get), derives a sluggish level, tells the client, and persists remaining
-- seconds across relogs/restarts. It never touches health and never reads/writes rsg-core hunger/thirst/cleanliness.
local cfg = FhSurvivalConfig
local N = FhSurvivalNeeds
local regions = FhRegions

local function now() return GetGameTimer() / 1000.0 end -- same clock as fh_buffs

local players = {} -- [src] = { citizenid, loginAt, hasRow, loadFailed, state = {level, missing}, snap = last buff snapshot }
-- [src] = token of the load allowed to finish. Each load takes a fresh token from a server-wide counter (never
-- reused, so a token from before a drop can never match a later load); drop() clears the slot.
local loadToken, lastToken = {}, 0

-- ---- DB / rsg glue (kept small; decisions live in shared/needs.lua) ----

local function citizenOf(src)
    local ok, p = pcall(function() return exports['rsg-core']:GetPlayer(src) end)
    return ok and p and p.PlayerData and p.PlayerData.citizenid or nil
end

local function loadRow(citizenid)
    local ok, row = pcall(MySQL.single.await, 'SELECT needs FROM fh_survival_needs WHERE citizenid = ?', { citizenid })
    if not ok then print(('[fh_survival] db_error load %s: %s'):format(citizenid, tostring(row))) return nil, false end
    if not row then return nil, true end
    local dok, saved = pcall(json.decode, row.needs)
    return (dok and type(saved) == 'table') and saved or {}, true
end

local SAVE_SQL = 'INSERT INTO fh_survival_needs (citizenid, needs, updated_at) VALUES (?, ?, ?) ' ..
    'ON DUPLICATE KEY UPDATE needs = VALUES(needs), updated_at = VALUES(updated_at)'

---`noWait`: dispatch without yielding (resource stop / shutdown: FXServer does not resume yielded handlers there).
local function saveRow(citizenid, saved, noWait)
    local params = { citizenid, json.encode(saved), os.time() }
    local ok, err = pcall(noWait and MySQL.update or MySQL.update.await, SAVE_SQL, params)
    if not ok then print(('[fh_survival] db_error save %s: %s'):format(citizenid, tostring(err))) end
    return ok
end

local function snapshotOf(src)
    local ok, s = pcall(function() return exports.fh_buffs:get(src) end)
    return ok and type(s) == 'table' and s or {}
end

---Region id of the player's position (via FhRegions territories), or nil.
local function regionOf(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return nil end
    local c = GetEntityCoords(ped)
    local t = regions.territoryAt(c.x, c.y)
    return t and t.region or nil
end

-- ---- save / restore ----

---Synchronously pop a player's record and build the row to write (never yields). Removing the record before any
---DB call means a second drop for the same src (OnPlayerUnload then playerDropped) finds nothing and never writes
---twice. Clearing the load token cancels any restore still waiting on the DB for this src.
---@return string? citizenid, table? saved  (nil when there is nothing that may be written)
local function takeRow(src)
    loadToken[src] = nil
    local p = players[src]
    if not p then return nil end
    players[src] = nil
    local saved = N.saveRemaining(N.pickSnapshot(snapshotOf(src), p.snap), now())
    if not N.shouldSave(p.loadFailed, saved) then
        print(('[fh_survival] skip save %s: login load failed and nothing to save (stored row kept)'):format(p.citizenid))
        return nil
    end
    return p.citizenid, saved
end

local function drop(src, noWait)
    local cid, saved = takeRow(src)
    if cid then saveRow(cid, saved, noWait) end
end

local function restorePlayer(src, citizenid)
    local cur = players[src]
    if cur and cur.citizenid == citizenid then return end -- already live (resource-start sweep vs PlayerLoaded)
    local oldCid, oldSaved = takeRow(src) -- another character still registered on this src (sync pop)
    lastToken = lastToken + 1
    local token = lastToken
    loadToken[src] = token -- taken before any yield, so a later load or drop always supersedes this one
    if oldCid then saveRow(oldCid, oldSaved) end -- yields
    local saved, dbOk = loadRow(citizenid) -- yields
    -- The player may have dropped, switched character, or started a newer load while we waited.
    if not N.loadIsCurrent(token, loadToken[src], citizenOf(src), citizenid) then return end
    local p = { citizenid = citizenid, loginAt = now(), hasRow = saved ~= nil, loadFailed = not dbOk, snap = {} }
    players[src] = p
    if dbOk and saved then -- no row (or DB down): login grace applies / ticks continue
        for _, r in ipairs(N.restore(saved, cfg.Durations)) do
            local ok, res = pcall(function() return exports.fh_buffs:apply(src, r.buff_id, r.magnitude, r.duration) end)
            if not ok or res == false then print(('[fh_survival] restore %s for %s refused'):format(r.buff_id, citizenid)) end
        end
    end
    -- Cache right away: a drop before the first tick must save the restored buffs, not an empty snapshot.
    p.snap = snapshotOf(src)
end

AddEventHandler('RSGCore:Server:PlayerLoaded', function(Player)
    local src = Player and Player.PlayerData and Player.PlayerData.source
    local cid = Player and Player.PlayerData and Player.PlayerData.citizenid
    if src and cid then restorePlayer(src, cid) end
end)

AddEventHandler('RSGCore:Server:OnPlayerUnload', function(src) drop(src) end)
AddEventHandler('playerDropped', function() drop(source) end)

-- Keep the drop cache fresh between ticks: fh_buffs clears its state on playerDropped, possibly before ours runs,
-- so a buff applied after the last tick would otherwise be lost on a quick disconnect.
AddEventHandler('fh:buffs:applied', function(e)
    local src = type(e) == 'table' and e.src or nil
    local p = src and players[src]
    if p then p.snap = snapshotOf(src) end
end)

-- ---- boot check ----

---Try every need buff id against fh_buffs' caps. An id it refuses as unknown is logged once and skipped; the
---other needs keep running. src 2147483647 is never a loaded player, so a known id ends in 'no_player' and
---nothing is ever applied.
local unknown = {}
local function bootCheck()
    for _, need in ipairs(N.NEEDS) do
        local id = N.NEED_BUFF[need]
        local ok, res, err = pcall(function() return exports.fh_buffs:apply(2147483647, id, 1.0, 1) end)
        if ok and res == false and err == 'unknown_buff' and not unknown[id] then
            unknown[id] = true
            print(('[fh_survival] unknown_buff %s (fh_buffs has no cap for it yet; %s will never count as met)'):format(id, need))
        end
    end
end

-- ---- tick ----

local function evaluatePlayer(src, p)
    local t = now()
    p.snap = snapshotOf(src)
    local level, missing = N.evaluate(p.snap, t, {
        regionId = regionOf(src), coldRegions = cfg.ColdRegions, levelMap = cfg.LevelMap,
        hasRow = p.hasRow, loginAt = p.loginAt, grace = cfg.LoginGraceSeconds,
    })
    if N.stateChanged(p.state, level, missing) then
        p.state = { level = level, missing = missing }
        TriggerClientEvent('fh:survival:state', src, { level = level, missing = missing })
    end
end

CreateThread(function()
    while true do
        Wait(math.max(1, cfg.TickSeconds) * 1000)
        for src, p in pairs(players) do
            if not GetPlayerName(src) then players[src] = nil; loadToken[src] = nil else evaluatePlayer(src, p) end
        end
    end
end)

-- ---- lifecycle ----

AddEventHandler('onResourceStart', function(res)
    if res ~= GetCurrentResourceName() then return end
    CreateThread(function()
        bootCheck()
        for _, id in ipairs(GetPlayers()) do -- resource restarted with players online
            local src = tonumber(id)
            local cid = src and citizenOf(src)
            if cid then restorePlayer(src, cid) end
        end
    end)
end)

---Save everyone without yielding: snapshots are read synchronously and every write is dispatched before this
---handler returns (FXServer would not resume a yielded onResourceStop, so players 2..N would never be saved).
local function saveAllNow()
    local srcs = {}
    for src in pairs(players) do srcs[#srcs + 1] = src end
    for _, src in ipairs(srcs) do drop(src, true) end
end

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then saveAllNow() end
end)
AddEventHandler('txAdmin:events:serverShuttingDown', saveAllNow)

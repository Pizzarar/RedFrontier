-- fh_survival server core (plan survival-01, S2). Needs are positive timed buffs held by fh_buffs; this resource
-- only reads them (exports.fh_buffs:get), derives a sluggish level, tells the client, and persists remaining
-- seconds across relogs/restarts. It never touches health and never reads/writes rsg-core hunger/thirst/cleanliness.
local cfg = FhSurvivalConfig
local N = FhSurvivalNeeds
local regions = FhRegions

local function now() return GetGameTimer() / 1000.0 end -- same clock as fh_buffs

local players = {} -- [src] = { citizenid, loginAt, hasRow, state = {level, missing}, snap = last buff snapshot }

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

local function saveRow(citizenid, saved)
    local ok, err = pcall(MySQL.update.await,
        'INSERT INTO fh_survival_needs (citizenid, needs, updated_at) VALUES (?, ?, ?) ' ..
        'ON DUPLICATE KEY UPDATE needs = VALUES(needs), updated_at = VALUES(updated_at)',
        { citizenid, json.encode(saved), os.time() })
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

local function savePlayer(src)
    local p = players[src]
    if not p then return end
    local snap = N.pickSnapshot(snapshotOf(src), p.snap)
    saveRow(p.citizenid, N.saveRemaining(snap, now()))
    p.hasRow = true
end

local function restorePlayer(src, citizenid)
    local saved, dbOk = loadRow(citizenid)
    local p = { citizenid = citizenid, loginAt = now(), hasRow = saved ~= nil, snap = {} }
    players[src] = p
    if not dbOk or not saved then return end -- no row (or DB down): login grace applies / ticks continue
    for _, r in ipairs(N.restore(saved, cfg.Durations)) do
        local ok, res = pcall(function() return exports.fh_buffs:apply(src, r.buff_id, r.magnitude, r.duration) end)
        if not ok or res == false then print(('[fh_survival] restore %s for %s refused'):format(r.buff_id, citizenid)) end
    end
end

AddEventHandler('RSGCore:Server:PlayerLoaded', function(Player)
    local src = Player and Player.PlayerData and Player.PlayerData.source
    local cid = Player and Player.PlayerData and Player.PlayerData.citizenid
    if src and cid then restorePlayer(src, cid) end
end)

local function drop(src)
    if not players[src] then return end
    savePlayer(src)
    players[src] = nil
end
AddEventHandler('RSGCore:Server:OnPlayerUnload', drop)
AddEventHandler('playerDropped', function() drop(source) end)

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
            if not GetPlayerName(src) then players[src] = nil else evaluatePlayer(src, p) end
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

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for src in pairs(players) do savePlayer(src) end
end)

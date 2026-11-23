-- fh_progression: per-player rep cache -> tiers and unlocks. Read-only; never writes rep (fh_economy owns that).
local cfg = FhProgressionConfig
local logic = FhProgressionLogic
local reader = FhProgressionRep

-- [src] = { citizenid = string, rep = { [region_id] = number }, complete = boolean }
-- `complete` is false when any region read failed; entry() retries those on the next access.
local cache = {}

local function citizenOf(src)
    local P = exports['rsg-core']:GetPlayer(src)
    return P and P.PlayerData and P.PlayerData.citizenid or nil
end

-- Reads EVERY configured region. Never emits events: with no prior values there is no crossing to report.
local function loadAll(src, citizenid)
    local e = { citizenid = citizenid, rep = {}, complete = true }
    for region_id in pairs(cfg.tiers) do
        local v = reader.read(citizenid, region_id)
        if v == nil then e.complete = false else e.rep[region_id] = v end
    end
    cache[src] = e
    return e
end

-- Cached entry for src, reloaded when missing, incomplete, or belonging to a different character.
local function entry(src)
    if type(src) ~= 'number' then return nil end
    local cid = citizenOf(src)
    if not cid then return nil end
    local e = cache[src]
    if not e or e.citizenid ~= cid or not e.complete then e = loadAll(src, cid) end
    return e
end

local function onRepChanged(src, citizenid, region_id, value)
    local e = cache[src]
    if not e or e.citizenid ~= citizenid or not e.complete then
        loadAll(src, citizenid) -- cold/stale: the read already includes this change, so no crossing is knowable
        return
    end
    local old = e.rep[region_id]
    if type(value) ~= 'number' then
        local v = reader.read(citizenid, region_id)
        if v == nil then return end -- read failed: keep the old value, emit nothing
        value = v
    end
    e.rep[region_id] = value
    local changed, oldTier, newTier = logic.crossing(cfg, region_id, old, value)
    if changed then
        TriggerEvent('fh:progression:tier_changed',
            { src = src, citizenid = citizenid, region_id = region_id, old = oldTier, new = newTier })
    end
end

AddEventHandler('fh:economy:rep_changed', function(p)
    if type(p) ~= 'table' or type(p.src) ~= 'number' or not p.citizenid or not cfg.tiers[p.region_id] then return end
    onRepChanged(p.src, p.citizenid, p.region_id, p.value)
end)

-- Server-side event; passes the Player object (rsg-core/server/player.lua).
AddEventHandler('RSGCore:Server:PlayerLoaded', function(Player)
    local pd = Player and Player.PlayerData
    if pd and pd.source and pd.citizenid then loadAll(pd.source, pd.citizenid) end
end)

AddEventHandler('RSGCore:Server:OnPlayerUnload', function(src) cache[src] = nil end)
AddEventHandler('playerDropped', function() cache[source] = nil end)

-- Resource (re)start: preload everyone already online.
AddEventHandler('onResourceStart', function(res)
    if res ~= GetCurrentResourceName() then return end
    for _, id in ipairs(GetPlayers()) do
        local src = tonumber(id)
        if src then entry(src) end
    end
end)

exports('getRep', function(src, region_id)
    local e = entry(src)
    return e and e.rep[region_id] or 0
end)

exports('getTier', function(src, region_id)
    local e = entry(src)
    return (logic.tierForRep(cfg, region_id, e and e.rep[region_id] or 0))
end)

exports('canUnlock', function(src, unlock_id)
    local e = entry(src)
    return logic.canUnlock(cfg, e and e.rep or {}, unlock_id)
end)

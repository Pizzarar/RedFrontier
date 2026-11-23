-- fh_progression: per-player rep cache -> tiers and unlocks. Read-only; never writes rep (fh_economy owns that).
local cfg = FhProgressionConfig
local logic = FhProgressionLogic
local reader = FhProgressionRep

local cache = {} -- [src] = { citizenid = string, rep = { [region_id] = number } }

local function citizenOf(src)
    local P = exports['rsg-core']:GetPlayer(src)
    return P and P.PlayerData and P.PlayerData.citizenid or nil
end

local function refresh(src, citizenid, region_id, value)
    local e = cache[src]
    if not e or e.citizenid ~= citizenid then e = { citizenid = citizenid, rep = {} }; cache[src] = e end
    local old = logic.tierForRep(cfg, region_id, e.rep[region_id] or 0)
    if type(value) ~= 'number' then value = reader.read(citizenid, region_id) end
    e.rep[region_id] = value
    local new = logic.tierForRep(cfg, region_id, value)
    if new ~= old then
        TriggerEvent('fh:progression:tier_changed', { src = src, region_id = region_id, old = old, new = new })
    end
end

local function loadAll(src, citizenid)
    cache[src] = { citizenid = citizenid, rep = {} }
    for region_id in pairs(cfg.tiers) do
        cache[src].rep[region_id] = reader.read(citizenid, region_id)
    end
end

-- Lazy load for players whose load event we missed (e.g. resource restart).
local function entry(src)
    if type(src) ~= 'number' then return nil end
    if not cache[src] then
        local cid = citizenOf(src)
        if not cid then return nil end
        loadAll(src, cid)
    end
    return cache[src]
end

AddEventHandler('fh:economy:rep_changed', function(p)
    if type(p) ~= 'table' or not p.src or not p.citizenid or not cfg.tiers[p.region_id] then return end
    refresh(p.src, p.citizenid, p.region_id, p.value)
end)

AddEventHandler('RSGCore:Server:OnPlayerLoaded', function(Player)
    local src = Player and Player.PlayerData and Player.PlayerData.source
    local cid = Player and Player.PlayerData and Player.PlayerData.citizenid
    if src and cid then loadAll(src, cid) end
end)

AddEventHandler('playerDropped', function() cache[source] = nil end)

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

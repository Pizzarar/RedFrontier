-- fh_progression: per-player rep cache -> tiers and unlocks. Read-only; never writes rep (fh_economy owns that).
-- Cache logic (incl. async-read races) lives in server/progression_cache.lua; this file only wires FiveM to it.
local cfg = FhProgressionConfig

local function citizenOf(src)
    local P = exports['rsg-core']:GetPlayer(src)
    return P and P.PlayerData and P.PlayerData.citizenid or nil
end

local store = FhProgressionCache.new({
    cfg = cfg,
    logic = FhProgressionLogic,
    read = FhProgressionRep.read,
    citizenOf = citizenOf,
    emit = function(payload) TriggerEvent('fh:progression:tier_changed', payload) end,
})

AddEventHandler('fh:economy:rep_changed', function(p)
    if type(p) ~= 'table' or type(p.src) ~= 'number' or not p.citizenid or not cfg.tiers[p.region_id] then return end
    store.onRepChanged(p.src, p.citizenid, p.region_id, p.value)
end)

-- Server-side event; passes the Player object (rsg-core/server/player.lua).
AddEventHandler('RSGCore:Server:PlayerLoaded', function(Player)
    local pd = Player and Player.PlayerData
    if pd and pd.source and pd.citizenid then store.loadAll(pd.source, pd.citizenid) end
end)

AddEventHandler('RSGCore:Server:OnPlayerUnload', function(src) store.invalidate(src) end)
AddEventHandler('playerDropped', function()
    local src = tonumber(source)
    if src then store.invalidate(src) end
end)

-- Resource (re)start: preload everyone already online.
AddEventHandler('onResourceStart', function(res)
    if res ~= GetCurrentResourceName() then return end
    for _, id in ipairs(GetPlayers()) do
        local src = tonumber(id)
        if src then store.entry(src) end
    end
end)

exports('getRep', store.getRep)
exports('getTier', store.getTier)
exports('canUnlock', store.canUnlock)

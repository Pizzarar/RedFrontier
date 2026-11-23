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

-- ---------------------------------------------------------------- admin test command
-- `fh_rep <serverId> <region> <delta>`: same exports.fh_economy:rep path as normal play (atomic upsert + ledger row).
-- Restricted: console, or ACE `command.fh_rep` (server.cfg: add_ace group.admin command allow).
RegisterCommand('fh_rep', function(source, args)
    if not (source == 0 or IsPlayerAceAllowed(source, 'command.fh_rep')) then return end
    local function say(msg)
        if source == 0 then print('[fh_progression] ' .. msg)
        else TriggerClientEvent('chat:addMessage', source, { args = { 'fh', msg } }) end
    end
    local p, err = FhProgressionLogic.parseRepCmd(args, FhRegions.isKnownRegion, 1000)
    if not p then return say('fh_rep: ' .. err) end
    local called, ok, rerr = pcall(function()
        return exports.fh_economy:rep(p.target, p.region_id, p.delta, 'console_test')
    end)
    if not called then return say('fh_rep: economy export failed: ' .. tostring(ok)) end
    say(ok and ('fh_rep: ok (%s %+d for %d)'):format(p.region_id, p.delta, p.target)
        or 'fh_rep: ' .. tostring(rerr))
end, true)

-- Sluggish effect (S5). Listens to fh:survival:state { level, missing }. NEVER lethal: no health natives anywhere.
-- Config.SluggishEffect: 'notify' (default; text only, no natives) | 'native' (opt-in, UNVERIFIED in game).
-- Natives used (all candidates, wrapped in pcall; hashes listed in fh_core/docs/natives.md):
--   stamina recharge multiplier, dead-eye recharge multiplier, movement clipset (level 3 only, needs SluggishClipset).
local E = FhSurvivalEffects
local C = FhSurvivalConfig

local level, lastNotify = 0, -1e9

-- Hashes are candidates (unproven). A failing invoke is swallowed so a wrong hash cannot break the client.
local H_STAMINA_RECHARGE = 0xFECA17CF3343694B -- SET_PLAYER_STAMINA_RECHARGE_MULTIPLIER(player, float)
-- Dead-eye recharge: no hash is known yet. C.SluggishDeadeyeHash (nil by default) takes (player, float); nil = skipped.
local H_SET_CLIPSET      = 0x923583741DC87BCE -- SET_PED_MOVEMENT_CLIPSET(ped, clipSetHash, transitionSpeed)
local H_RESET_CLIPSET    = 0x58F7DB5BD8FA2288 -- RESET_PED_MOVEMENT_CLIPSET(ped, transitionSpeed)

local applied = { stamina = false, deadeye = false, clipset = nil }

local function invoke(hash, ...)
    local ok = pcall(Citizen.InvokeNative, hash, ...)
    return ok
end

local function applyNative(p)
    local player = PlayerId()
    if p.staminaRegen ~= 1.0 or applied.stamina then
        invoke(H_STAMINA_RECHARGE, player, p.staminaRegen + 0.0)
        applied.stamina = p.staminaRegen ~= 1.0
    end
    if C.SluggishDeadeyeHash and (p.deadeyeRegen ~= 1.0 or applied.deadeye) then
        invoke(C.SluggishDeadeyeHash, player, p.deadeyeRegen + 0.0)
        applied.deadeye = p.deadeyeRegen ~= 1.0
    end
    local ped = PlayerPedId()
    if p.clipset and p.clipset ~= applied.clipset then
        local set = GetHashKey(p.clipset)
        if not HasClipSetLoaded(set) then
            RequestClipSet(set)
            local t = GetGameTimer() + 3000
            while not HasClipSetLoaded(set) and GetGameTimer() < t do Wait(50) end
        end
        if HasClipSetLoaded(set) then
            invoke(H_SET_CLIPSET, ped, set, 1.0)
            applied.clipset = p.clipset
        end
    elseif not p.clipset and applied.clipset then
        invoke(H_RESET_CLIPSET, ped, 1.0)
        applied.clipset = nil
    end
end

local function params(lvl)
    return E.params(lvl, C.SluggishEffect, { Text = C.SluggishText, Regen = C.SluggishRegen, Clipset = C.SluggishClipset })
end

FH.onNet('fh:survival:state', function(state)
    local new = type(state) == 'table' and state.level or 0
    local p = params(new)
    local prev = level
    level = p.level
    if E.shouldNotify(prev, level) then
        local now = GetGameTimer()
        if p.notify and now - lastNotify >= (C.SluggishNotifyCooldownMs or 60000) then
            lastNotify = now
            TriggerEvent('chat:addMessage', { args = { 'Survival', p.notify } }) -- plain chat line; @ui may replace it
        end
    end
    if p.native or applied.stamina or applied.deadeye or applied.clipset then applyNative(p) end
end)

-- Switching SluggishEffect back to notify (resource restart) or stopping must not leave natives applied.
AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    if applied.stamina then invoke(H_STAMINA_RECHARGE, PlayerId(), 1.0) end
    if applied.deadeye and C.SluggishDeadeyeHash then invoke(C.SluggishDeadeyeHash, PlayerId(), 1.0) end
    if applied.clipset then invoke(H_RESET_CLIPSET, PlayerPedId(), 1.0) end
end)

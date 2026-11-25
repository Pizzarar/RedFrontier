-- spk_outfit client: throwaway probe (S7) for fitted outfit presets and single-item layering on rsg-character peds.
--   /spk_outfit <n>                       — apply SetPedOutfitPreset(ped, n, false) + update variation.
--   /spk_outfit next | prev               — step preset index (+1 / -1, clamped >= 0).
--   /spk_outfit auto on|off               — store auto flag + last preset index in client KVP; re-apply after
--                                           rsg-character:client:ApplySkin (listen-only AddEventHandler) and on start.
--   /spk_outfit layer hat|bandana|gloves|coat [k] — apply candidate item hash k (default 1) over current preset.
--   /spk_outfit layer clear               — remove all 4 layer categories (hats, neckwear, gloves, coats).
--   /spk_outfit reset                     — re-trigger rsg-character's own skin load via exports['rsg-character']:ApplySkin().
-- Natives and hashes mirror server/resources/[rsg]/rsg-character (client/functions.lua:270,332-337,1072-1152;
-- client/charselect.lua:194; client/clothes.lua:272,842; client/spawn.lua:5; client/creator.lua:233,1154) and are
-- cross-checked against fh_core/docs/natives.md. All candidate preset indices and item hashes are candidate, unproven.
-- No convar/flag gates this (plan Decided); client-local only, ox_lib only, no rsg-character edits, no RSG inventory calls.

local N_APPLY_SHOP_ITEM_TO_PED = 0xD3A7B003ED343FD9           -- _APPLY_SHOP_ITEM_TO_PED(ped, componentHash, immediately, isMp, p4)
local N_REMOVE_TAG_FROM_META_PED = 0xD710A5007C2AC539         -- _REMOVE_TAG_FROM_META_PED(ped, categoryHash, p2)
local N_GET_SHOP_ITEM_COMPONENT_CATEGORY = 0x5FF9A878C3D115B8 -- _GET_SHOP_ITEM_COMPONENT_CATEGORY(componentHash, isFemale, isMp)
local N_FIX_MESH_ISSUES = 0x59BD177A1A48600A                  -- rsg-character NativeFixMeshIssues(ped, categoryHash)
local N_UPDATE_PED_VARIATION_PREP = 0x704C908E9C405136        -- rsg-character NativeUpdatePedVariation step 1
local N_UPDATE_PED_VARIATION = 0xCC8CA3E88256E58F             -- _UPDATE_PED_VARIATION(ped, false, true, true, true, false)
local N_UPDATE_PED_VARIATION_POST = 0xAAB86462966168CE        -- rsg-character NativeUpdatePedVariation step 3
local N_IS_PED_READY_TO_RENDER = 0xA0BC8FAED8CFEB3C           -- _IS_PED_READY_TO_RENDER(ped) (rsg-character NativeHasPedComponentLoaded)

local KVP_AUTO = 'spk_outfit:auto'
local KVP_INDEX = 'spk_outfit:index'

local MODEL_MALE = joaat('mp_male')
local MODEL_FEMALE = joaat('mp_female')

-- Category hashes from rsg-character/data/clothing.lua (matches joaat of category name).
local LAYER_CATEGORIES = {
    hat     = { cat = 'hats',     hash = 0x9925C067 },
    bandana = { cat = 'neckwear', hash = 0x5FC29285 },
    gloves  = { cat = 'gloves',   hash = 0xEABE0032 },
    coat    = { cat = 'coats',    hash = 0xE06D30CE },
}

local LAYER_CLEAR_ORDER = { 'hat', 'bandana', 'gloves', 'coat' }

-- Candidate shop-item hashes extracted from rsg-character/data/clothing.lua (all candidate, unproven in-game).
local LAYER_ITEMS = {
    male = {
        hat = {
            { hash = 1820410246, name = 'CLOTHING_ITEM_M_FRONTIER_HAT_000' },  -- 0x6C814186 (candidate, unproven)
            { hash = 2754281087, name = 'CLOTHING_ITEM_M_HAT_000_TINT_001' },  -- 0xA42AFE7F (candidate, unproven)
            { hash = 3382727215, name = 'CLOTHING_ITEM_M_HAT_001_TINT_001' },  -- 0xC9A0522F (candidate, unproven)
        },
        bandana = {
            { hash = 1906846397, name = 'bandana' },                           -- 0x71A82ABD (candidate, unproven)
            { hash = 2458134595, name = 'gathered_bandana' },                  -- 0x92842843 (candidate, unproven)
            { hash = 1580751299, name = 'patterned_bandana' },                 -- 0x5E3859C3 (candidate, unproven)
        },
        gloves = {
            { hash = 745251899,  name = 'CLOTHING_ITEM_M_GLOVES_000_TINT_001' }, -- 0x2C6BA43B (candidate, unproven)
            { hash = 2674335993, name = 'CLOTHING_ITEM_M_GLOVES_001_TINT_001' }, -- 0x9F6720F9 (candidate, unproven)
            { hash = 3799630629, name = 'CLOTHING_ITEM_M_GLOVES_002_TINT_001' }, -- 0xE279C325 (candidate, unproven)
        },
        coat = {
            { hash = 3349172660, name = 'CLOTHING_ITEM_M_COAT_000_TINT_001' }, -- 0xC7A051B4 (candidate, unproven)
            { hash = 1696062810, name = 'CLOTHING_ITEM_M_COAT_001_TINT_001' }, -- 0x6517DD5A (candidate, unproven)
            { hash = 3148604518, name = 'CLOTHING_ITEM_M_COAT_002_TINT_001' }, -- 0xBBABE466 (candidate, unproven)
        },
    },
    female = {
        hat = {
            { hash = 3313189151, name = 'CLOTHING_ITEM_F_FRONTIER_HAT_000' },  -- 0xC57B411F (candidate, unproven)
            { hash = 2424693915, name = 'CLOTHING_ITEM_F_HAT_000_TINT_001' },  -- 0x9085E49B (candidate, unproven)
            { hash = 414370589,  name = 'CLOTHING_ITEM_F_HAT_001_TINT_001' },  -- 0x18B2CB1D (candidate, unproven)
        },
        bandana = {
            { hash = 2401499311, name = 'bandana' },                           -- 0x8F23F8AF (candidate, unproven)
            { hash = 2410224255, name = 'gathered_bandana' },                  -- 0x8FA91A7F (candidate, unproven)
            { hash = 2262899489, name = 'patterned_bandana' },                 -- 0x86E11B21 (candidate, unproven)
        },
        gloves = {
            { hash = 590067755,  name = 'CLOTHING_ITEM_F_GLOVES_000_TINT_001' }, -- 0x232BB82B (candidate, unproven)
            { hash = 3682376111, name = 'CLOTHING_ITEM_F_GLOVES_001_TINT_001' }, -- 0xDB7C99AF (candidate, unproven)
            { hash = 1531697767, name = 'CLOTHING_ITEM_F_GLOVES_002_TINT_001' }, -- 0x5B4BDA67 (candidate, unproven)
        },
        coat = {
            { hash = 3555396598, name = 'CLOTHING_ITEM_F_COAT_000_TINT_001' }, -- 0xD3EB0BF6 (candidate, unproven)
            { hash = 422907192,  name = 'CLOTHING_ITEM_F_COAT_001_TINT_001' }, -- 0x19350D38 (candidate, unproven)
            { hash = 2588043597, name = 'CLOTHING_ITEM_F_COAT_002_TINT_001' }, -- 0x9A42694D (candidate, unproven)
        },
    },
}

local currentIndex = nil
local autoEnabled = false
local reapplyGen = 0 -- generation counter: guards re-entrant ApplySkin / startup / reset threads

local function say(msg)
    print('[spk_outfit] ' .. msg)
    lib.notify({ title = 'spk_outfit', description = msg, type = 'inform', duration = 6000 })
end

local function hex(h)
    return ('0x%08X'):format((tonumber(h) or 0) & 0xFFFFFFFF)
end

local function readSavedIndex()
    local raw = GetResourceKvpString(KVP_INDEX)
    if not raw or raw == '' then return nil end
    local n = tonumber(raw)
    if not n then return nil end
    return math.floor(n)
end

local function readAutoFlag()
    return GetResourceKvpString(KVP_AUTO) == '1'
end

local function saveIndex(idx)
    currentIndex = idx
    SetResourceKvp(KVP_INDEX, tostring(idx))
end

local function saveAutoFlag(enabled)
    autoEnabled = enabled and true or false
    SetResourceKvp(KVP_AUTO, autoEnabled and '1' or '0')
end

local function pedModelInfo(ped)
    local m = GetEntityModel(ped)
    local u = (tonumber(m) or 0) & 0xFFFFFFFF
    if u == (MODEL_MALE & 0xFFFFFFFF) then
        return 'mp_male', 'male', false
    elseif u == (MODEL_FEMALE & 0xFFFFFFFF) then
        return 'mp_female', 'female', true
    end
    return ('unknown(%s)'):format(hex(u)), 'male', false
end

-- Mirrors rsg-character/client/functions.lua NativeUpdatePedVariation (lines 1141-1152).
local function updatePedVariation(ped)
    Citizen.InvokeNative(N_UPDATE_PED_VARIATION_PREP, ped)
    Citizen.InvokeNative(N_UPDATE_PED_VARIATION, ped, false, true, true, true, false)
    Citizen.InvokeNative(N_UPDATE_PED_VARIATION_POST, ped, true)
    local deadline = GetGameTimer() + 5000
    while not Citizen.InvokeNative(N_IS_PED_READY_TO_RENDER, ped) do
        if GetGameTimer() > deadline then break end
        Wait(0)
    end
end

local function applyPreset(idx, reason)
    idx = math.floor(idx)
    if idx < 0 then idx = 0 end
    local ped = PlayerPedId()
    local modelLabel = pedModelInfo(ped)
    SetPedOutfitPreset(ped, idx, false) -- 0x77FF8D35EEC6BBC4
    updatePedVariation(ped)
    saveIndex(idx)
    if reason then
        say(('re-applied %d %s (model=%s)'):format(idx, reason, modelLabel))
    else
        say(('model=%s preset=%d (auto=%s)'):format(modelLabel, idx, autoEnabled and 'on' or 'off'))
    end
end

local function stepPreset(delta)
    local base = currentIndex
    if base == nil then
        base = readSavedIndex()
    end
    local nextIdx
    if base == nil then
        nextIdx = 0
    else
        nextIdx = base + delta
        if nextIdx < 0 then nextIdx = 0 end
    end
    applyPreset(nextIdx)
end

local function setAuto(arg)
    if arg == 'on' then
        saveAutoFlag(true)
        local idx = currentIndex ~= nil and currentIndex or readSavedIndex()
        say(('auto=on (saved index=%s)'):format(idx ~= nil and tostring(idx) or 'none'))
    elseif arg == 'off' then
        reapplyGen = reapplyGen + 1 -- cancel any pending re-apply thread
        saveAutoFlag(false)
        say('auto=off')
    else
        say(('auto is %s (saved index=%s). usage: /spk_outfit auto on|off'):format(
            autoEnabled and 'on' or 'off',
            tostring(currentIndex ~= nil and currentIndex or readSavedIndex())))
    end
end

local function clearLayers()
    local ped = PlayerPedId()
    for _, slot in ipairs(LAYER_CLEAR_ORDER) do
        local info = LAYER_CATEGORIES[slot]
        Citizen.InvokeNative(N_REMOVE_TAG_FROM_META_PED, ped, info.hash, 0)
    end
    updatePedVariation(ped)
    say('cleared layers (hat, bandana, gloves, coat)')
end

local function applyLayer(slot, kArg)
    if slot == 'clear' then
        return clearLayers()
    end
    if not LAYER_CATEGORIES[slot] then
        return say('usage: /spk_outfit layer hat|bandana|gloves|coat [k] | clear')
    end
    local ped = PlayerPedId()
    local modelLabel, sexKey, isFemale = pedModelInfo(ped)
    local list = LAYER_ITEMS[sexKey] and LAYER_ITEMS[sexKey][slot]
    if not list or #list == 0 then
        return say(('no candidate items for %s/%s'):format(sexKey, slot))
    end
    local k = tonumber(kArg) and math.floor(tonumber(kArg)) or 1
    if k < 1 or k > #list then
        return say(('layer %s index out of range (1..%d)'):format(slot, #list))
    end
    local item = list[k]
    -- Mirrors rsg-character/client/functions.lua NativeSetPedComponentEnabledClothes (lines 1124-1139).
    local catHash = Citizen.InvokeNative(N_GET_SHOP_ITEM_COMPONENT_CATEGORY, item.hash, isFemale, true)
    if catHash and catHash ~= 0 then
        Citizen.InvokeNative(N_FIX_MESH_ISSUES, ped, catHash)
    end
    Citizen.InvokeNative(N_APPLY_SHOP_ITEM_TO_PED, ped, item.hash, false, true, true)
    updatePedVariation(ped)
    say(('layer %s [%d/%d] %s hash=%s (%s) model=%s'):format(
        slot, k, #list, item.name, tostring(item.hash), hex(item.hash), modelLabel))
end

local function resetSkin()
    reapplyGen = reapplyGen + 1 -- do not let a queued auto re-apply overwrite the reset
    say('resetting via rsg-character ApplySkin export...')
    CreateThread(function()
        local ok, err = pcall(function()
            exports['rsg-character']:ApplySkin()
        end)
        if not ok then
            say(('reset failed (rsg-character ApplySkin): %s'):format(tostring(err)))
        else
            say('reset complete (rsg-character ApplySkin)')
        end
    end)
end

local function scheduleReapply(delayMs, reason)
    if not autoEnabled then return end
    local idx = currentIndex ~= nil and currentIndex or readSavedIndex()
    if idx == nil then return end
    reapplyGen = reapplyGen + 1
    local gen = reapplyGen
    CreateThread(function()
        Wait(delayMs)
        if gen ~= reapplyGen or not autoEnabled then return end
        applyPreset(idx, reason)
    end)
end

RegisterCommand('spk_outfit', function(source, args)
    local sub = args[1]
    if not sub then
        return say('usage: /spk_outfit <n> | next | prev | auto on|off | layer hat|bandana|gloves|coat [k] | layer clear | reset')
    end
    if sub == 'next' then return stepPreset(1) end
    if sub == 'prev' then return stepPreset(-1) end
    if sub == 'auto' then return setAuto(args[2]) end
    if sub == 'layer' then return applyLayer(args[2], args[3]) end
    if sub == 'reset' then return resetSkin() end
    local n = tonumber(sub)
    if n ~= nil then return applyPreset(n) end
    say('unknown arg "' .. tostring(sub) .. '". usage: /spk_outfit <n> | next | prev | auto on|off | layer ... | reset')
end, false)

-- Listen-only handler for rsg-character:client:ApplySkin (registered as net event by rsg-character/client/spawn.lua:5).
AddEventHandler('rsg-character:client:ApplySkin', function()
    scheduleReapply(2500, 'after ApplySkin')
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    reapplyGen = reapplyGen + 1
end)

-- Restore KVP state on resource start and re-apply if auto is enabled.
autoEnabled = readAutoFlag()
currentIndex = readSavedIndex()
if autoEnabled and currentIndex ~= nil then
    scheduleReapply(500, 'on resource start')
end

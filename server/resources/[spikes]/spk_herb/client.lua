-- spk_herb client: three throwaway probes to pick a herb-patch cue for the frontier.
--   /spk_herb props  — spawn ~6 candidate wild-plant/herb prop models in a line 2m apart, ~4m in front of you.
--   /spk_herb blip   — a coords blip at the player that cycles 3-4 candidate plant/herb sprite hashes every 3s.
--   /spk_herb clear  — delete every spawned entity and remove the blip (also run on resource stop).
-- Model/object natives are called by name, copied from the known-working pattern in fh_quests/client/board.lua
-- (lines 21-32). The blip is created by hash 0x554D9D53F696D002 (BLIP_ADD_FOR_COORDS), the pattern in
-- rsg-character/client/clothes.lua:804 and fh_ui/client/blips.lua. All hashes are cross-checked against
-- fh_core/docs/natives.md and alloc8or rdr3 nativedb; the model/sprite NAMES are guesses (candidate, unproven).
-- No convar/flag gates this (see the plan Decided): every command is always on, like the other spk_* spikes.

local N_BLIP_ADD_FOR_COORDS = 0x554D9D53F696D002 -- BLIP_ADD_FOR_COORDS(styleHash, x, y, z) -> Blip
local N_SET_BLIP_NAME = 0x9CB1A1623062F402 -- _SET_BLIP_NAME(blip, name)  (plain string, not VarString)
local N_GET_ENTITY_FORWARD_VECTOR = 0x2412D9C05BB09B97 -- GET_ENTITY_FORWARD_VECTOR(entity) -> vector3 (RDR3 hash; not the GTA5 one)

local BLIP_STYLE = 1664425300 -- BLIP_STYLE_PICKUP_WEAPON (the base style rsg-character/fh_ui use; sprite overridden)

-- Candidate wild-plant/herb prop models (candidate, unproven). Names are the RDR2 herb PICKUP models from
-- femga/rdr3_discoveries objects/object_list.lua (s_lev_des.rpf); joaat (signed) listed for cross-reference.
-- The first four are the herbs fh_crafting's tonic recipes already use (ginseng, wild mint, oregano, red sage).
local MODELS = {
    { name = 'yarrow01_p',  note = 'Yarrow' },
    { name = 'ginseng_p',   note = 'Ginseng (recipe herb)' },
    { name = 'wildmint_p',  note = 'Wild Mint (recipe herb)' },
    { name = 'oregano_p',   note = 'Oregano (recipe herb)' },
    { name = 'redsage_p',   note = 'Red Sage (recipe herb)' },
    { name = 'thyme_p',     note = 'Creeping Thyme' },
}

-- Candidate plant/herb blip sprite hashes (candidate, unproven). Names verified against femga/rdr3_discoveries
-- textures/blips; the signed joaat is listed next to each. Only `blip_plant` is literally a plant icon; the
-- other three are food/gathering icons included so the tester can compare which reads as "a herb to pick".
local SPRITES = {
    { name = 'blip_plant',         hash = joaat('blip_plant') },         -- -675651933
    { name = 'blip_grub',          hash = joaat('blip_grub') },          -- 935247438
    { name = 'blip_supplies_food', hash = joaat('blip_supplies_food') }, -- -1852063472
    { name = 'blip_donate_food',   hash = joaat('blip_donate_food') },   -- -1236018085
}

local props = {}       -- spawned object handles (local, non-networked)
local blip = nil       -- the cycle blip handle
local blipActive = false

local function say(msg)
    print('[spk_herb] ' .. msg)
    lib.notify({ title = 'spk_herb', description = msg, type = 'inform', duration = 6000 })
end

local function hex(h) return ('0x%08X'):format(h & 0xFFFFFFFF) end

-- Request + wait for a model; returns (hash, nil) or (nil, 'reason').
local function loadModel(name)
    local hash = joaat(name)
    if not IsModelValid(hash) then return nil, 'IsModelValid false' end
    RequestModel(hash, false)
    local t = GetGameTimer() + 5000
    while not HasModelLoaded(hash) and GetGameTimer() < t do Wait(50) end
    if not HasModelLoaded(hash) then return nil, 'load timed out' end
    return hash
end

-- /spk_herb props
local function spawnProps()
    clearProps()
    local ped = PlayerPedId()
    local c = GetEntityCoords(ped, true, true)
    local f = Citizen.InvokeNative(N_GET_ENTITY_FORWARD_VECTOR, ped, Citizen.ResultAsVector())
    local right = vector3(-f.y, f.x, 0.0) -- right-hand perpendicular (same trick as spk_pelt)
    say(('spawning %d candidate herb models in a line 2m apart, ~4m ahead'):format(#MODELS))
    for i, m in ipairs(MODELS) do
        local pos = c + f * 4.0 + right * ((i - 1) * 2.0 - (#MODELS - 1))
        local hash, err = loadModel(m.name)
        if not hash then
            say(('FAIL [%d] %s (%s): %s'):format(i, m.name, m.note, err))
        else
            local o = CreateObject(hash, pos.x, pos.y, pos.z, false, false, false) -- non-networked
            if o == 0 or not DoesEntityExist(o) then
                say(('FAIL [%d] %s (%s): CreateObject returned no entity'):format(i, m.name, m.note))
            else
                PlaceObjectOnGroundProperly(o) -- 0x58A850EAEE20FAA3
                FreezeEntityPosition(o, true)
                props[#props + 1] = o
                say(('[%d] %s (%s) joaat=%s (%s) — spawned local + frozen'):format(
                    i, m.name, m.note, tostring(hash), hex(hash)))
            end
            SetModelAsNoLongerNeeded(hash)
        end
    end
    say('done. Run /spk_herb clear to remove them.')
end

-- /spk_herb blip
local function spawnBlip()
    clearBlip()
    local ped = PlayerPedId()
    local c = GetEntityCoords(ped, true, true)
    blip = Citizen.InvokeNative(N_BLIP_ADD_FOR_COORDS, BLIP_STYLE, c.x, c.y, c.z)
    if not blip or blip == 0 then return say('BLIP_ADD_FOR_COORDS returned no blip') end
    SetBlipScale(blip, 0.8)
    Citizen.InvokeNative(N_SET_BLIP_NAME, blip, 'herb patch cue')
    blipActive = true
    say('blip created at the player; cycling ' .. #SPRITES .. ' candidate sprites every 3s')
    CreateThread(function()
        local i = 0
        while blipActive and blip and blip ~= 0 do
            local s = SPRITES[(i % #SPRITES) + 1]
            SetBlipSprite(blip, s.hash, 1) -- 0x74F74D3207ED525C, p2=1
            say(('showing sprite %d/%d: %s joaat=%s (%s)'):format(
                (i % #SPRITES) + 1, #SPRITES, s.name, tostring(s.hash), hex(s.hash)))
            i = i + 1
            Wait(3000)
        end
    end)
end

local function clearProps()
    for _, o in ipairs(props) do
        if DoesEntityExist(o) then DeleteEntity(o) end
    end
    props = {}
end

local function clearBlip()
    blipActive = false
    if blip and blip ~= 0 then
        RemoveBlip(blip) -- 0xF2C3C9DA47AAA54A
        blip = nil
    end
end

-- /spk_herb clear
local function clearAll()
    clearProps()
    clearBlip()
    say('cleared all spawned props and the blip')
end

RegisterCommand('spk_herb', function(source, args)
    local sub = args[1]
    if sub == 'props' then return spawnProps() end
    if sub == 'blip' then return spawnBlip() end
    if sub == 'clear' then return clearAll() end
    say('usage: /spk_herb props | blip | clear')
end, false)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    clearProps()
    clearBlip()
end)

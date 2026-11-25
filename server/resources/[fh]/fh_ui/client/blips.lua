-- fh_ui client: map blips for every findable place (mapblips). Coordinates come from each lane's shared config via the
-- `@`-includes in fxmanifest (read-only; never hardcoded here). The place list is pure (FhUiPlaces.gather); this file
-- only draws it. Gated by FhUiConfig.blips.
--
-- Blip natives, copied from the known-working pattern in rsg-character/client/clothes.lua (CreateBlips, lines 796-823),
-- hashes verified against alloc8or rdr3-nativedb-data natives.json:
--   BLIP_ADD_FOR_COORDS 0x554D9D53F696D002 (STYLE hash, x, y, z) -> blip   first arg is a blip STYLE, not a sprite
--   SetBlipSprite(blip, spriteHash, 1)   [exposed by name]  sprite comes from FhUiPlaces.sprite (joaat'd)
--   SetBlipScale(blip, scale)            [exposed by name]
--   _SET_BLIP_NAME      0x9CB1A1623062F402 (blip, name)   plain string, not a VarString (rsg-character passes RSG.BlipName)
--   RemoveBlip(blip)                     [exposed by name]  REMOVE_BLIP 0xF2C3C9DA47AAA54A takes Blip* (pointer)
-- Style 1664425300 = BLIP_STYLE_PICKUP_WEAPON (the base style rsg-character uses; the sprite is overridden anyway).
-- Sprite names are verified against femga/rdr3_discoveries textures/blips; still unverified in-game. Not runtime-tested.
local P = FhUiPlaces

local BLIP_ADD_FOR_COORDS = 0x554D9D53F696D002
local BLIP_STYLE = 1664425300 -- BLIP_STYLE_PICKUP_WEAPON
local _SET_BLIP_NAME = 0x9CB1A1623062F402

local blips = {}

-- The lane configs, read from the `@`-includes. A config a lane did not provide is nil and gather skips it.
-- Enabled-region trappers come from the read-only `fh:ui:trappers` callback (fh_ui server -> fh_hunting getTrappers);
-- when nil (e.g. fh_hunting not started yet), places.lua falls back to FhHuntingConfig.Trapper.
local function fetchTrappers()
    if not (lib and lib.callback) then return nil end
    local ok, list = pcall(function() return lib.callback.await('fh:ui:trappers', false) end)
    if ok and type(list) == 'table' then return list end
    return nil
end

local function sources(trappers)
    return {
        homestead = FhHomesteadConfig,
        trade = FhTradeConfig,
        hunting = FhHuntingConfig,
        trappers = trappers,
        zones = FhZonesConfig,
        crafting = FhCraftingConfig,
        fence = FhFenceConfig,
        quests = { givers = FhQuestsGivers, boards = FhQuestsBoardSpots },
    }
end

local function addBlip(place)
    local blip = Citizen.InvokeNative(BLIP_ADD_FOR_COORDS, BLIP_STYLE, place.x + 0.0, place.y + 0.0, place.z + 0.0)
    if blip and blip ~= 0 then
        SetBlipSprite(blip, joaat(P.sprite(place)), 1)
        SetBlipScale(blip, 0.8)
        Citizen.InvokeNative(_SET_BLIP_NAME, blip, place.label)
        return blip
    end
    return nil
end

local function clear()
    for _, b in ipairs(blips) do
        RemoveBlip(b) -- Blip* handled by the named-native wrapper (rsg-character does the same)
    end
    blips = {}
end

local function refresh()
    if not FhUiConfig or FhUiConfig.blips == false then clear(); return end
    local trappers = fetchTrappers()
    clear()
    for _, p in ipairs(P.gather(sources(trappers), { isEnabled = FhRegions and FhRegions.isEnabled })) do
        local b = addBlip(p)
        if b then blips[#blips + 1] = b end
    end
end

FH.thread(refresh)

-- fh_hunting starts after fh_ui in server.cfg: refresh blips when fh_hunting starts or restarts.
FH.on('onResourceStart', function(res)
    if res == 'fh_hunting' then FH.thread(refresh) end
end)

FH.on('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    clear()
end)

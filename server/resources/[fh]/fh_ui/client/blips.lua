-- fh_ui client: map blips for every findable place (mapblips). Coordinates come from each lane's shared config via the
-- `@`-includes in fxmanifest (read-only; never hardcoded here). The place list is pure (FhUiPlaces.gather); this file
-- only draws it. Gated by FhUiConfig.blips.
--
-- Natives (hashes verified against alloc8or rdr3-nativedb-data natives.json):
--   BLIP_ADD_FOR_COORDS 0x554D9D53F696D002 (blipHash, x, y, z) -> blip
--   _SET_BLIP_NAME      0x9CB1A1623062F402 (blip, name string)
--   SET_BLIP_SCALE      0xD38744167B2FA257 (blip, scale)
--   DOES_BLIP_EXIST     0xCD82FA174080B3B1 (blip)
--   REMOVE_BLIP         0xF2C3C9DA47AAA54A (blip)
-- Sprite names are RDR2 blip sprites (joaat()'d at call time); UNVERIFIED in-game. Not runtime-tested (no Cfx key).
local P = FhUiPlaces

local BLIP_ADD_FOR_COORDS = 0x554D9D53F696D002
local _SET_BLIP_NAME = 0x9CB1A1623062F402
local SET_BLIP_SCALE = 0xD38744167B2FA257
local DOES_BLIP_EXIST = 0xCD82FA174080B3B1
local REMOVE_BLIP = 0xF2C3C9DA47AAA54A

local blips = {}

-- The lane configs, read from the `@`-includes. A config a lane did not provide is nil and gather skips it.
local function sources()
    return {
        homestead = FhHomesteadConfig,
        trade = FhTradeConfig,
        hunting = FhHuntingConfig,
        zones = FhZonesConfig,
        crafting = FhCraftingConfig,
        fence = FhFenceConfig,
        quests = { givers = FhQuestsGivers, boards = FhQuestsBoardSpots },
    }
end

local function addBlip(place)
    local hash = joaat(P.sprite(place))
    local blip = Citizen.InvokeNative(BLIP_ADD_FOR_COORDS, hash, place.x + 0.0, place.y + 0.0, place.z + 0.0)
    if blip and blip ~= 0 then
        Citizen.InvokeNative(_SET_BLIP_NAME, blip, place.label)
        Citizen.InvokeNative(SET_BLIP_SCALE, blip, 0.8)
        return blip
    end
    return nil
end

local function clear()
    for _, b in ipairs(blips) do
        if Citizen.InvokeNative(DOES_BLIP_EXIST, b) then Citizen.InvokeNative(REMOVE_BLIP, b) end
    end
    blips = {}
end

local function refresh()
    clear()
    if not FhUiConfig or FhUiConfig.blips == false then return end
    for _, p in ipairs(P.gather(sources())) do
        local b = addBlip(p)
        if b then blips[#blips + 1] = b end
    end
end

FH.thread(refresh)

FH.on('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    clear()
end)

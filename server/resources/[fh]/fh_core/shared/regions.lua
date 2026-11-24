-- Static region / faction / territory registry (spec 4.4). Pure Lua, no natives.
-- Every other lane references these IDs and never defines its own.
--
-- NOTE: all coordinates are APPROXIMATE (real RDR2 town positions, z is a hint) and
-- must be verified in game (stand at the spot, read coords, adjust). The /where
-- command tags unverified entries so the owner can walk them in.
local regions = {}

regions.TIERS = { 'T1', 'T2', 'T3' }

-- 8 factions + 1 alias. Original names only: no RDR2 gang/company names.
-- `kind` is read by A-Life for hostility: 'law' | 'outlaw' | 'neutral'.
-- `home` is the faction's canonical region, used by fh_heat chargeRegion for the
-- bounty ledger when the player is off every territory (before the alphabetical fallback).
-- `alias_of` marks an id kept only for legacy rows (fh_heat may be keyed on it);
-- every lookup helper resolves it to the canonical faction.
regions.factions = {
    lawmen         = { id = 'lawmen',         label = 'Lawmen',               kind = 'law',     home = 'heartlands' },
    rhodes_law     = { id = 'rhodes_law',     label = 'Rhodes Law',           kind = 'law',     home = 'scarlett_meadows', alias_of = 'lawmen' },
    rail_mining    = { id = 'rail_mining',    label = 'Rail & Mining Company', kind = 'neutral', home = 'roanoke_ridge' },
    settlers       = { id = 'settlers',       label = 'Settlers League',      kind = 'neutral', home = 'heartlands' },
    traders        = { id = 'traders',        label = 'Traders Guild',        kind = 'neutral', home = 'bayou_nwa' },
    bounty_hunters = { id = 'bounty_hunters', label = 'Bounty Hunters',       kind = 'neutral', home = 'great_plains' },
    raiders        = { id = 'raiders',        label = 'Swamp Gang',           kind = 'outlaw',  home = 'bayou_nwa' },
    outlaws        = { id = 'outlaws',        label = 'Mountain Gang',        kind = 'outlaw',  home = 'heartlands' },
    desert_gang    = { id = 'desert_gang',    label = 'Desert Gang',          kind = 'outlaw',  home = 'gaptooth_ridge' },
}

-- All 15 regions (no Guarma). `enabled` gates spawn/blip//where for the owner's first walk.
regions.regions = {
    heartlands = {
        id = 'heartlands',
        label = 'Heartlands (Valentine)',
        kind = 'region',
        state = 'new_hanover',
        enabled = true,
        towns = {
            { id = 'valentine',     label = 'Valentine',     x = -169.47, y = 629.38,  z = 113.03 },
            { id = 'emerald_ranch', label = 'Emerald Ranch', x = 1411.0,  y = 355.0,   z = 96.0 },
        },
        -- Starter homestead plot, approximate.
        homestead = { x = -300.0, y = 790.0, z = 118.0 },
        factions = { 'lawmen', 'outlaws', 'traders', 'settlers' },
        territories = { 'heartlands_t1_camp' },
    },
    scarlett_meadows = {
        id = 'scarlett_meadows',
        label = 'Scarlett Meadows (Rhodes)',
        kind = 'region',
        state = 'lemoyne',
        enabled = true,
        towns = {
            { id = 'rhodes', label = 'Rhodes', x = 1263.6, y = -1305.7, z = 77.9 },
        },
        -- Starter homestead plot, approximate (north of Rhodes). (unverified)
        homestead = { x = 1250.0, y = -1210.0, z = 77.0 },
        factions = { 'lawmen', 'raiders', 'traders' },
        territories = { 'scarlett_meadows_t1_camp' },
    },
    bayou_nwa = {
        id = 'bayou_nwa',
        label = 'Bayou Nwa (Saint Denis)',
        kind = 'region',
        state = 'lemoyne',
        enabled = true,
        towns = {
            { id = 'saint_denis', label = 'Saint Denis', x = 2694.69, y = -1448.48, z = 45.27 },
            { id = 'lagras',      label = 'Lagras',      x = 2174.0,  y = -1120.0,  z = 25.0 },
        },
        factions = { 'lawmen', 'raiders', 'traders', 'bounty_hunters' },
        territories = {},
    },
    bluewater_marsh = {
        id = 'bluewater_marsh',
        label = 'Bluewater Marsh',
        kind = 'region',
        state = 'lemoyne',
        enabled = false,
        towns = {},
        factions = { 'lawmen', 'raiders' },
        territories = {},
    },
    roanoke_ridge = {
        id = 'roanoke_ridge',
        label = 'Roanoke Ridge (Annesburg)',
        kind = 'region',
        state = 'new_hanover',
        enabled = false,
        towns = {
            { id = 'annesburg', label = 'Annesburg', x = 2921.0, y = 1290.0, z = 96.0 },
            { id = 'van_horn',  label = 'Van Horn',  x = 2973.0, y = 606.0,  z = 38.0 },
        },
        factions = { 'lawmen', 'outlaws', 'rail_mining' },
        territories = {},
    },
    grizzlies_east = {
        id = 'grizzlies_east',
        label = 'Grizzlies East (Wapiti)',
        kind = 'region',
        state = 'ambarino',
        enabled = false,
        towns = {
            { id = 'wapiti', label = 'Wapiti', x = 1673.0, y = 1900.0, z = 200.0 },
        },
        factions = { 'lawmen', 'outlaws', 'settlers' },
        territories = {},
    },
    grizzlies_west = {
        id = 'grizzlies_west',
        label = 'Grizzlies West (Colter)',
        kind = 'region',
        state = 'ambarino',
        enabled = false,
        towns = {
            { id = 'colter', label = 'Colter', x = -1300.0, y = 1600.0, z = 240.0 },
        },
        factions = { 'lawmen', 'outlaws', 'rail_mining', 'settlers' },
        territories = {},
    },
    cumberland_forest = {
        id = 'cumberland_forest',
        label = 'Cumberland Forest',
        kind = 'region',
        state = 'new_hanover',
        enabled = false,
        towns = {
            { id = 'bacchus_station', label = 'Bacchus Station', x = -810.0, y = 1340.0, z = 130.0 },
        },
        factions = { 'lawmen', 'outlaws', 'settlers', 'rail_mining' },
        territories = {},
    },
    big_valley = {
        id = 'big_valley',
        label = 'Big Valley (Strawberry)',
        kind = 'region',
        state = 'west_elizabeth',
        enabled = false,
        towns = {
            { id = 'strawberry',      label = 'Strawberry',      x = -1814.0, y = -440.0, z = 120.0 },
            { id = 'wallace_station', label = 'Wallace Station', x = -1340.0, y = -440.0, z = 130.0 },
        },
        factions = { 'lawmen', 'outlaws', 'settlers', 'traders', 'rail_mining' },
        territories = {},
    },
    great_plains = {
        id = 'great_plains',
        label = 'Great Plains (Blackwater)',
        kind = 'region',
        state = 'west_elizabeth',
        enabled = true,
        towns = {
            { id = 'blackwater', label = 'Blackwater', x = -858.67, y = -1337.61, z = 44.49 },
        },
        factions = { 'lawmen', 'traders', 'bounty_hunters', 'settlers' },
        territories = {},
    },
    tall_trees = {
        id = 'tall_trees',
        label = 'Tall Trees',
        kind = 'region',
        state = 'west_elizabeth',
        enabled = false,
        towns = {
            { id = 'manzanita_post', label = 'Manzanita Post', x = -1795.0, y = -1600.0, z = 150.0 },
        },
        factions = { 'lawmen', 'outlaws', 'bounty_hunters' },
        territories = {},
    },
    hennigans_stead = {
        id = 'hennigans_stead',
        label = "Hennigan's Stead",
        kind = 'region',
        state = 'new_austin',
        enabled = false,
        towns = {
            { id = 'macfarlanes_ranch', label = "MacFarlane's Ranch", x = -2283.0, y = -2493.0, z = 60.0 },
            { id = 'thieves_landing',   label = 'Thieves Landing',    x = -1445.0, y = -2224.0, z = 40.0 },
        },
        factions = { 'lawmen', 'desert_gang', 'settlers' },
        territories = {},
    },
    cholla_springs = {
        id = 'cholla_springs',
        label = 'Cholla Springs (Armadillo)',
        kind = 'region',
        state = 'new_austin',
        enabled = false,
        towns = {
            { id = 'armadillo', label = 'Armadillo', x = -3711.0, y = -2581.0, z = 70.0 },
        },
        factions = { 'lawmen', 'desert_gang', 'bounty_hunters' },
        territories = {},
    },
    gaptooth_ridge = {
        id = 'gaptooth_ridge',
        label = 'Gaptooth Ridge (Tumbleweed)',
        kind = 'region',
        state = 'new_austin',
        enabled = false,
        towns = {
            { id = 'tumbleweed', label = 'Tumbleweed', x = -5522.0, y = -2938.0, z = 90.0 },
        },
        factions = { 'lawmen', 'desert_gang' },
        territories = {},
    },
    rio_bravo = {
        id = 'rio_bravo',
        label = 'Rio Bravo',
        kind = 'region',
        state = 'new_austin',
        enabled = false,
        towns = {},
        factions = { 'lawmen', 'desert_gang' },
        territories = {},
    },
}

regions.territories = {
    heartlands_t1_camp = {
        id = 'heartlands_t1_camp',
        label = 'Heartlands Outlaw Camp',
        region = 'heartlands',
        faction = 'outlaws',
        tier = 'T1',
        center = { x = -145.0, y = 845.0, z = 117.0 }, -- approximate
        radius = 60.0,
    },
    scarlett_meadows_t1_camp = {
        id = 'scarlett_meadows_t1_camp',
        label = 'Lemoyne Raiders Camp',
        region = 'scarlett_meadows',
        faction = 'raiders',
        tier = 'T1',
        center = { x = 1350.0, y = -1400.0, z = 76.0 }, -- approximate (unverified)
        radius = 60.0,
    },
}

function regions.getRegion(id) return regions.regions[id] end

---Resolve an alias id to its canonical faction (e.g. rhodes_law -> lawmen).
function regions.getFaction(id)
    local f = regions.factions[id]
    if f and f.alias_of then return regions.factions[f.alias_of] end
    return f
end

function regions.getTerritory(id) return regions.territories[id] end

---@return boolean
function regions.isKnownRegion(id)
    return type(id) == 'string' and regions.regions[id] ~= nil
end

---Return the territory containing (x, y), or nil. 2D distance; the nearest center wins on overlap.
function regions.territoryAt(x, y)
    if type(x) ~= 'number' or type(y) ~= 'number' then return nil end
    local best, bestD2
    for _, t in pairs(regions.territories) do
        local dx, dy = x - t.center.x, y - t.center.y
        local d2 = dx * dx + dy * dy
        if d2 <= t.radius * t.radius and (not bestD2 or d2 < bestD2) then
            best, bestD2 = t, d2
        end
    end
    return best
end

-- FXServer loads shared scripts as plain chunks; expose a global there, module under busted.
if _G.GetCurrentResourceName then _G.FhRegions = regions end
return regions

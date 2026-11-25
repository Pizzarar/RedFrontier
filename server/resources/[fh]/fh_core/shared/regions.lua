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
    lawmen = {
        id = 'lawmen', label = 'Lawmen', kind = 'law', home = 'heartlands',
        -- per-state label skin (plan world-01 block A): region.state -> law label
        skins = {
            new_hanover = 'New Hanover Law', lemoyne = 'Lemoyne Law', ambarino = 'Ambarino Law',
            west_elizabeth = 'West Elizabeth Law', new_austin = 'New Austin Law',
        },
    },
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
        factions = { 'lawmen', 'outlaws', 'traders', 'settlers' },
        territories = { 'heartlands_t1_camp', 'heartlands_t1_camp_2', 'heartlands_t1_camp_3', 'heartlands_t2_camp' },
        ambush = {
            { id = 'heartlands_amb_1', x = 640, y = 560, z = 100, label = 'East stage road bend', verified = false },
            { id = 'heartlands_amb_2', x = -120, y = 260, z = 95, label = 'South river crossing', verified = false },
            { id = 'heartlands_amb_3', x = -320, y = 1000, z = 115, label = 'North creekside trail', verified = false },
        },
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
        factions = { 'lawmen', 'raiders', 'traders' },
        territories = { 'scarlett_meadows_t1_camp', 'scarlett_meadows_t1_camp_2', 'scarlett_meadows_t2_camp' },
        ambush = {
            { id = 'scarlett_meadows_amb_1', x = 1000, y = -800, z = 70, label = 'North meadow road', verified = false },
            { id = 'scarlett_meadows_amb_2', x = 1450, y = -900, z = 70, label = 'East meadow road', verified = false },
            { id = 'scarlett_meadows_amb_3', x = 800, y = -1500, z = 60, label = 'South hollow road', verified = false },
        },
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
        territories = { 'bayou_nwa_t1_camp', 'bayou_nwa_t1_camp_2', 'bayou_nwa_t1_camp_3', 'bayou_nwa_t2_camp' },
        ambush = {
            { id = 'bayou_nwa_amb_1', x = 1650, y = -950, z = 25, label = 'West swamp trail', verified = false },
            { id = 'bayou_nwa_amb_2', x = 2480, y = -980, z = 25, label = 'North causeway', verified = false },
            { id = 'bayou_nwa_amb_3', x = 2400, y = -1500, z = 22, label = 'South causeway', verified = false },
        },
    },
    bluewater_marsh = {
        id = 'bluewater_marsh',
        label = 'Bluewater Marsh',
        kind = 'region',
        state = 'lemoyne',
        enabled = false,
        towns = {},
        factions = { 'lawmen', 'raiders' },
        territories = { 'bluewater_marsh_t1_camp', 'bluewater_marsh_t1_camp_2', 'bluewater_marsh_t2_camp' },
        ambush = {
            { id = 'bluewater_marsh_amb_1', x = 2200, y = -500, z = 20, label = 'Causeway trail', verified = false },
            { id = 'bluewater_marsh_amb_2', x = 2500, y = -500, z = 20, label = 'North marsh road', verified = false },
        },
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
        territories = { 'roanoke_ridge_t1_camp', 'roanoke_ridge_t1_camp_2', 'roanoke_ridge_t2_camp' },
        ambush = {
            { id = 'roanoke_ridge_amb_1', x = 2550, y = 950, z = 85, label = 'River valley road', verified = false },
            { id = 'roanoke_ridge_amb_2', x = 2900, y = 1000, z = 100, label = 'Ridge pass trail', verified = false },
            { id = 'roanoke_ridge_amb_3', x = 2500, y = 500, z = 60, label = 'Coast road', verified = false },
        },
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
        territories = { 'grizzlies_east_t1_camp', 'grizzlies_east_t1_camp_2', 'grizzlies_east_t2_camp' },
        ambush = {
            { id = 'grizzlies_east_amb_1', x = 1350, y = 1800, z = 230, label = 'Wapiti trail', verified = false },
            { id = 'grizzlies_east_amb_2', x = 1750, y = 1550, z = 200, label = 'East ridge trail', verified = false },
        },
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
        territories = { 'grizzlies_west_t1_camp', 'grizzlies_west_t1_camp_2', 'grizzlies_west_t2_camp' },
        ambush = {
            { id = 'grizzlies_west_amb_1', x = -1650, y = 1100, z = 220, label = 'Colter road', verified = false },
            { id = 'grizzlies_west_amb_2', x = -1250, y = 1800, z = 245, label = 'North pass trail', verified = false },
        },
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
        territories = { 'cumberland_forest_t1_camp', 'cumberland_forest_t1_camp_2', 'cumberland_forest_t2_camp' },
        ambush = {
            { id = 'cumberland_forest_amb_1', x = -850, y = 1000, z = 105, label = 'Forest stage road', verified = false },
            { id = 'cumberland_forest_amb_2', x = -500, y = 1480, z = 130, label = 'Timberline trail', verified = false },
        },
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
        territories = { 'big_valley_t1_camp', 'big_valley_t1_camp_2', 'big_valley_t2_camp' },
        ambush = {
            { id = 'big_valley_amb_1', x = -1560, y = -440, z = 125, label = 'Valley stage road', verified = false },
            { id = 'big_valley_amb_2', x = -1720, y = -980, z = 95, label = 'South valley road', verified = false },
            { id = 'big_valley_amb_3', x = -2050, y = -500, z = 100, label = 'West pass road', verified = false },
        },
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
        factions = { 'lawmen', 'traders', 'bounty_hunters', 'settlers', 'outlaws' },
        territories = { 'great_plains_t1_camp', 'great_plains_t1_camp_2', 'great_plains_t2_camp' },
        ambush = {
            { id = 'great_plains_amb_1', x = -1000, y = -1000, z = 45, label = 'North plains road', verified = false },
            { id = 'great_plains_amb_2', x = -1500, y = -1300, z = 40, label = 'West plains trail', verified = false },
            { id = 'great_plains_amb_3', x = -600, y = -1600, z = 40, label = 'East plains road', verified = false },
        },
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
        territories = { 'tall_trees_t1_camp', 'tall_trees_t1_camp_2', 'tall_trees_t2_camp' },
        ambush = {
            { id = 'tall_trees_amb_1', x = -1750, y = -1300, z = 135, label = 'North timber trail', verified = false },
            { id = 'tall_trees_amb_2', x = -1750, y = -1950, z = 125, label = 'South forest road', verified = false },
        },
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
        territories = { 'hennigans_stead_t1_camp', 'hennigans_stead_t1_camp_2', 'hennigans_stead_t2_camp' },
        ambush = {
            { id = 'hennigans_stead_amb_1', x = -1850, y = -2350, z = 50, label = 'Ranch road', verified = false },
            { id = 'hennigans_stead_amb_2', x = -2300, y = -2100, z = 65, label = 'North mesa road', verified = false },
        },
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
        territories = { 'cholla_springs_t1_camp', 'cholla_springs_t1_camp_2', 'cholla_springs_t2_camp' },
        ambush = {
            { id = 'cholla_springs_amb_1', x = -3300, y = -2200, z = 80, label = 'North desert road', verified = false },
            { id = 'cholla_springs_amb_2', x = -3900, y = -2150, z = 80, label = 'West flat road', verified = false },
        },
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
        territories = { 'gaptooth_ridge_t1_camp', 'gaptooth_ridge_t1_camp_2', 'gaptooth_ridge_t2_camp' },
        ambush = {
            { id = 'gaptooth_ridge_amb_1', x = -5200, y = -2500, z = 90, label = 'Canyon road', verified = false },
            { id = 'gaptooth_ridge_amb_2', x = -5600, y = -2600, z = 85, label = 'West canyon road', verified = false },
        },
    },
    rio_bravo = {
        id = 'rio_bravo',
        label = 'Rio Bravo',
        kind = 'region',
        state = 'new_austin',
        enabled = false,
        towns = {},
        factions = { 'lawmen', 'desert_gang' },
        territories = { 'rio_bravo_t1_camp', 'rio_bravo_t1_camp_2', 'rio_bravo_t2_camp' },
        ambush = {
            { id = 'rio_bravo_amb_1', x = -1850, y = -3000, z = 55, label = 'River bench trail', verified = false },
            { id = 'rio_bravo_amb_2', x = -2450, y = -2700, z = 60, label = 'West mesa trail', verified = false },
        },
    },
}

-- world-01 (block C): one territory per outlaw camp. `faction` is the default camp owner (A-Life contract a-life-01);
-- `center` is the single source for the camp's center in fh_zones (world-02 block F). Coords APPROXIMATE / unverified.
regions.territories = {
    -- Heartlands (outlaws = Mountain Gang)
    heartlands_t1_camp = {
        id = 'heartlands_t1_camp',
        label = 'Heartland Bluffs Camp',
        region = 'heartlands',
        faction = 'outlaws',
        tier = 'T1',
        center = { x = -145.0, y = 845.0, z = 117.0 }, -- approximate
        radius = 60.0,
    },
    heartlands_t1_camp_2 = {
        id = 'heartlands_t1_camp_2',
        label = 'Heartland Overflow Camp',
        region = 'heartlands',
        faction = 'outlaws',
        tier = 'T1',
        center = { x = 850.0, y = 850.0, z = 100.0 }, -- approximate (unverified)
        radius = 60.0,
    },
    heartlands_t1_camp_3 = {
        id = 'heartlands_t1_camp_3',
        label = 'Dakota West Camp',
        region = 'heartlands',
        faction = 'outlaws',
        tier = 'T1',
        center = { x = -900.0, y = 500.0, z = 105.0 }, -- approximate (unverified)
        radius = 60.0,
    },
    heartlands_t2_camp = {
        id = 'heartlands_t2_camp',
        label = 'Dakota South Camp',
        region = 'heartlands',
        faction = 'outlaws',
        tier = 'T2',
        center = { x = 600.0, y = 200.0, z = 90.0 }, -- approximate (unverified)
        radius = 60.0,
    },
    -- Scarlett Meadows (raiders = Swamp Gang)
    scarlett_meadows_t1_camp = {
        id = 'scarlett_meadows_t1_camp',
        label = 'Hill Haven Camp',
        region = 'scarlett_meadows',
        faction = 'raiders',
        tier = 'T1',
        center = { x = 850.0, y = -1050.0, z = 75.0 }, -- approximate (unverified)
        radius = 60.0,
    },
    scarlett_meadows_t1_camp_2 = {
        id = 'scarlett_meadows_t1_camp_2',
        label = 'Cedar Bottoms Camp',
        region = 'scarlett_meadows',
        faction = 'raiders',
        tier = 'T1',
        center = { x = 1500.0, y = -1650.0, z = 70.0 }, -- approximate (unverified)
        radius = 60.0,
    },
    scarlett_meadows_t2_camp = {
        id = 'scarlett_meadows_t2_camp',
        label = 'Catfish Bottom Camp',
        region = 'scarlett_meadows',
        faction = 'raiders',
        tier = 'T2',
        center = { x = 1700.0, y = -1750.0, z = 65.0 }, -- approximate (unverified)
        radius = 60.0,
    },
    -- Bayou Nwa (raiders = Swamp Gang)
    bayou_nwa_t1_camp = {
        id = 'bayou_nwa_t1_camp',
        label = 'Moss Bog Camp',
        region = 'bayou_nwa',
        faction = 'raiders',
        tier = 'T1',
        center = { x = 2050.0, y = -1500.0, z = 25.0 }, -- approximate (unverified)
        radius = 60.0,
    },
    bayou_nwa_t1_camp_2 = {
        id = 'bayou_nwa_t1_camp_2',
        label = 'Bayou Railroad Camp',
        region = 'bayou_nwa',
        faction = 'raiders',
        tier = 'T1',
        center = { x = 2400.0, y = -950.0, z = 25.0 }, -- approximate (unverified)
        radius = 60.0,
    },
    bayou_nwa_t1_camp_3 = {
        id = 'bayou_nwa_t1_camp_3',
        label = 'Lagras Swamp Camp',
        region = 'bayou_nwa',
        faction = 'raiders',
        tier = 'T1',
        center = { x = 2200.0, y = -1650.0, z = 25.0 }, -- approximate (unverified)
        radius = 60.0,
    },
    bayou_nwa_t2_camp = {
        id = 'bayou_nwa_t2_camp',
        label = 'Cypress Hollow Camp',
        region = 'bayou_nwa',
        faction = 'raiders',
        tier = 'T2',
        center = { x = 2550.0, y = -1750.0, z = 20.0 }, -- approximate (unverified)
        radius = 60.0,
    },
    -- Great Plains (outlaws = Mountain Gang)
    great_plains_t1_camp = {
        id = 'great_plains_t1_camp',
        label = 'Bison Bluff Camp',
        region = 'great_plains',
        faction = 'outlaws',
        tier = 'T1',
        center = { x = -1600.0, y = -1350.0, z = 40.0 }, -- approximate (unverified)
        radius = 60.0,
    },
    great_plains_t1_camp_2 = {
        id = 'great_plains_t1_camp_2',
        label = 'Great Plains North Camp',
        region = 'great_plains',
        faction = 'outlaws',
        tier = 'T1',
        center = { x = -1050.0, y = -900.0, z = 45.0 }, -- approximate (unverified)
        radius = 60.0,
    },
    great_plains_t2_camp = {
        id = 'great_plains_t2_camp',
        label = 'Great Plains East Camp',
        region = 'great_plains',
        faction = 'outlaws',
        tier = 'T2',
        center = { x = -700.0, y = -1600.0, z = 40.0 }, -- approximate (unverified)
        radius = 60.0,
    },
    -- Bluewater Marsh (raiders = Swamp Gang)
    bluewater_marsh_t1_camp = {
        id = 'bluewater_marsh_t1_camp',
        label = 'Marsh Ford Camp',
        region = 'bluewater_marsh',
        faction = 'raiders',
        tier = 'T1',
        center = { x = 2400.0, y = -400.0, z = 25.0 }, -- approximate (unverified)
        radius = 60.0,
    },
    bluewater_marsh_t1_camp_2 = {
        id = 'bluewater_marsh_t1_camp_2',
        label = 'Bullrush Camp',
        region = 'bluewater_marsh',
        faction = 'raiders',
        tier = 'T1',
        center = { x = 2000.0, y = -450.0, z = 20.0 }, -- approximate (unverified)
        radius = 60.0,
    },
    bluewater_marsh_t2_camp = {
        id = 'bluewater_marsh_t2_camp',
        label = 'Cypress Bend Camp',
        region = 'bluewater_marsh',
        faction = 'raiders',
        tier = 'T2',
        center = { x = 2850.0, y = -900.0, z = 20.0 }, -- approximate (unverified)
        radius = 60.0,
    },
    -- Roanoke Ridge (outlaws = Mountain Gang)
    roanoke_ridge_t1_camp = {
        id = 'roanoke_ridge_t1_camp',
        label = 'Riverbend Camp',
        region = 'roanoke_ridge',
        faction = 'outlaws',
        tier = 'T1',
        center = { x = 2250.0, y = 800.0, z = 90.0 }, -- approximate (unverified)
        radius = 60.0,
    },
    roanoke_ridge_t1_camp_2 = {
        id = 'roanoke_ridge_t1_camp_2',
        label = 'Timber Ridge Camp',
        region = 'roanoke_ridge',
        faction = 'outlaws',
        tier = 'T1',
        center = { x = 2600.0, y = 1450.0, z = 120.0 }, -- approximate (unverified)
        radius = 60.0,
    },
    roanoke_ridge_t2_camp = {
        id = 'roanoke_ridge_t2_camp',
        label = 'Iron Hollow Camp',
        region = 'roanoke_ridge',
        faction = 'outlaws',
        tier = 'T2',
        center = { x = 2450.0, y = 650.0, z = 70.0 }, -- approximate (unverified)
        radius = 60.0,
    },
    -- Grizzlies East (outlaws = Mountain Gang)
    grizzlies_east_t1_camp = {
        id = 'grizzlies_east_t1_camp',
        label = 'Frost Creek Camp',
        region = 'grizzlies_east',
        faction = 'outlaws',
        tier = 'T1',
        center = { x = 1380.0, y = 1380.0, z = 190.0 }, -- approximate (unverified)
        radius = 60.0,
    },
    grizzlies_east_t1_camp_2 = {
        id = 'grizzlies_east_t1_camp_2',
        label = 'Aspen Camp',
        region = 'grizzlies_east',
        faction = 'outlaws',
        tier = 'T1',
        center = { x = 1850.0, y = 1500.0, z = 200.0 }, -- approximate (unverified)
        radius = 60.0,
    },
    grizzlies_east_t2_camp = {
        id = 'grizzlies_east_t2_camp',
        label = 'Granite Camp',
        region = 'grizzlies_east',
        faction = 'outlaws',
        tier = 'T2',
        center = { x = 1500.0, y = 1150.0, z = 170.0 }, -- approximate (unverified)
        radius = 60.0,
    },
    -- Grizzlies West (outlaws = Mountain Gang)
    grizzlies_west_t1_camp = {
        id = 'grizzlies_west_t1_camp',
        label = 'Tundra Camp',
        region = 'grizzlies_west',
        faction = 'outlaws',
        tier = 'T1',
        center = { x = -1460.0, y = 980.0, z = 210.0 }, -- approximate (unverified)
        radius = 60.0,
    },
    grizzlies_west_t1_camp_2 = {
        id = 'grizzlies_west_t1_camp_2',
        label = 'High Pass Camp',
        region = 'grizzlies_west',
        faction = 'outlaws',
        tier = 'T1',
        center = { x = -1850.0, y = 1650.0, z = 230.0 }, -- approximate (unverified)
        radius = 60.0,
    },
    grizzlies_west_t2_camp = {
        id = 'grizzlies_west_t2_camp',
        label = 'Ravine Camp',
        region = 'grizzlies_west',
        faction = 'outlaws',
        tier = 'T2',
        center = { x = -1150.0, y = 1250.0, z = 200.0 }, -- approximate (unverified)
        radius = 60.0,
    },
    -- Cumberland Forest (outlaws = Mountain Gang)
    cumberland_forest_t1_camp = {
        id = 'cumberland_forest_t1_camp',
        label = 'Rapids Camp',
        region = 'cumberland_forest',
        faction = 'outlaws',
        tier = 'T1',
        center = { x = -930.0, y = 1120.0, z = 110.0 }, -- approximate (unverified)
        radius = 60.0,
    },
    cumberland_forest_t1_camp_2 = {
        id = 'cumberland_forest_t1_camp_2',
        label = 'Elm Grove Camp',
        region = 'cumberland_forest',
        faction = 'outlaws',
        tier = 'T1',
        center = { x = -430.0, y = 1020.0, z = 100.0 }, -- approximate (unverified)
        radius = 60.0,
    },
    cumberland_forest_t2_camp = {
        id = 'cumberland_forest_t2_camp',
        label = 'North Ridge Camp',
        region = 'cumberland_forest',
        faction = 'outlaws',
        tier = 'T2',
        center = { x = -600.0, y = 1500.0, z = 140.0 }, -- approximate (unverified)
        radius = 60.0,
    },
    -- Big Valley (outlaws = Mountain Gang)
    big_valley_t1_camp = {
        id = 'big_valley_t1_camp',
        label = 'Creekside Camp',
        region = 'big_valley',
        faction = 'outlaws',
        tier = 'T1',
        center = { x = -1650.0, y = -900.0, z = 90.0 }, -- approximate (unverified)
        radius = 60.0,
    },
    big_valley_t1_camp_2 = {
        id = 'big_valley_t1_camp_2',
        label = 'Hillside Camp',
        region = 'big_valley',
        faction = 'outlaws',
        tier = 'T1',
        center = { x = -1250.0, y = -950.0, z = 85.0 }, -- approximate (unverified)
        radius = 60.0,
    },
    big_valley_t2_camp = {
        id = 'big_valley_t2_camp',
        label = 'West Ridge Camp',
        region = 'big_valley',
        faction = 'outlaws',
        tier = 'T2',
        center = { x = -2100.0, y = -780.0, z = 95.0 }, -- approximate (unverified)
        radius = 60.0,
    },
    -- Tall Trees (outlaws = Mountain Gang)
    tall_trees_t1_camp = {
        id = 'tall_trees_t1_camp',
        label = 'Pine Flats Camp',
        region = 'tall_trees',
        faction = 'outlaws',
        tier = 'T1',
        center = { x = -2150.0, y = -1650.0, z = 130.0 }, -- approximate (unverified)
        radius = 60.0,
    },
    tall_trees_t1_camp_2 = {
        id = 'tall_trees_t1_camp_2',
        label = 'West Hollow Camp',
        region = 'tall_trees',
        faction = 'outlaws',
        tier = 'T1',
        center = { x = -2000.0, y = -1850.0, z = 130.0 }, -- approximate (unverified)
        radius = 60.0,
    },
    tall_trees_t2_camp = {
        id = 'tall_trees_t2_camp',
        label = 'East Timber Camp',
        region = 'tall_trees',
        faction = 'outlaws',
        tier = 'T2',
        center = { x = -2250.0, y = -1400.0, z = 140.0 }, -- approximate (unverified)
        radius = 60.0,
    },
    -- Hennigan's Stead (desert_gang = Desert Gang)
    hennigans_stead_t1_camp = {
        id = 'hennigans_stead_t1_camp',
        label = 'Tableland Camp',
        region = 'hennigans_stead',
        faction = 'desert_gang',
        tier = 'T1',
        center = { x = -1900.0, y = -1950.0, z = 60.0 }, -- approximate (unverified)
        radius = 60.0,
    },
    hennigans_stead_t1_camp_2 = {
        id = 'hennigans_stead_t1_camp_2',
        label = 'West Mesa Camp',
        region = 'hennigans_stead',
        faction = 'desert_gang',
        tier = 'T1',
        center = { x = -2400.0, y = -2250.0, z = 70.0 }, -- approximate (unverified)
        radius = 60.0,
    },
    hennigans_stead_t2_camp = {
        id = 'hennigans_stead_t2_camp',
        label = 'South Crossing Camp',
        region = 'hennigans_stead',
        faction = 'desert_gang',
        tier = 'T2',
        center = { x = -1650.0, y = -2600.0, z = 55.0 }, -- approximate (unverified)
        radius = 60.0,
    },
    -- Cholla Springs (desert_gang = Desert Gang)
    cholla_springs_t1_camp = {
        id = 'cholla_springs_t1_camp',
        label = 'Alkali Flat Camp',
        region = 'cholla_springs',
        faction = 'desert_gang',
        tier = 'T1',
        center = { x = -3350.0, y = -2480.0, z = 75.0 }, -- approximate (unverified)
        radius = 60.0,
    },
    cholla_springs_t1_camp_2 = {
        id = 'cholla_springs_t1_camp_2',
        label = 'Prickly Pear Camp',
        region = 'cholla_springs',
        faction = 'desert_gang',
        tier = 'T1',
        center = { x = -3900.0, y = -2400.0, z = 80.0 }, -- approximate (unverified)
        radius = 60.0,
    },
    cholla_springs_t2_camp = {
        id = 'cholla_springs_t2_camp',
        label = 'Sagebrush Camp',
        region = 'cholla_springs',
        faction = 'desert_gang',
        tier = 'T2',
        center = { x = -4200.0, y = -2600.0, z = 80.0 }, -- approximate (unverified)
        radius = 60.0,
    },
    -- Gaptooth Ridge (desert_gang = Desert Gang)
    gaptooth_ridge_t1_camp = {
        id = 'gaptooth_ridge_t1_camp',
        label = 'Gaptooth Camp',
        region = 'gaptooth_ridge',
        faction = 'desert_gang',
        tier = 'T1',
        center = { x = -5100.0, y = -2600.0, z = 90.0 }, -- approximate (unverified)
        radius = 60.0,
    },
    gaptooth_ridge_t1_camp_2 = {
        id = 'gaptooth_ridge_t1_camp_2',
        label = 'West Draw Camp',
        region = 'gaptooth_ridge',
        faction = 'desert_gang',
        tier = 'T1',
        center = { x = -5800.0, y = -2800.0, z = 85.0 }, -- approximate (unverified)
        radius = 60.0,
    },
    gaptooth_ridge_t2_camp = {
        id = 'gaptooth_ridge_t2_camp',
        label = 'South Canyon Camp',
        region = 'gaptooth_ridge',
        faction = 'desert_gang',
        tier = 'T2',
        center = { x = -5400.0, y = -3200.0, z = 90.0 }, -- approximate (unverified)
        radius = 60.0,
    },
    -- Rio Bravo (desert_gang = Desert Gang)
    rio_bravo_t1_camp = {
        id = 'rio_bravo_t1_camp',
        label = 'Rio Camp',
        region = 'rio_bravo',
        faction = 'desert_gang',
        tier = 'T1',
        center = { x = -1800.0, y = -3200.0, z = 55.0 }, -- approximate (unverified)
        radius = 60.0,
    },
    rio_bravo_t1_camp_2 = {
        id = 'rio_bravo_t1_camp_2',
        label = 'Mesa Camp',
        region = 'rio_bravo',
        faction = 'desert_gang',
        tier = 'T1',
        center = { x = -1450.0, y = -2700.0, z = 60.0 }, -- approximate (unverified)
        radius = 60.0,
    },
    rio_bravo_t2_camp = {
        id = 'rio_bravo_t2_camp',
        label = 'Bend Camp',
        region = 'rio_bravo',
        faction = 'desert_gang',
        tier = 'T2',
        center = { x = -2050.0, y = -3150.0, z = 55.0 }, -- approximate (unverified)
        radius = 60.0,
    },
}

-- world-02 (block F): 1-2 trade posts per region (enabled and disabled), town-adjacent. `region` + position here
-- are the single source for fh_trade posts (FhTradeConfig.posts keeps only gameplay fields and resolves these at
-- load). Coords APPROXIMATE / unverified in game.
regions.posts = {
    valentine_post = { id = 'valentine_post', region = 'heartlands', x = -176.0, y = 630.0, z = 114.0 },
    rhodes_post = { id = 'rhodes_post', region = 'scarlett_meadows', x = 1288.0, y = -1278.0, z = 77.0 },
    saint_denis_post = { id = 'saint_denis_post', region = 'bayou_nwa', x = 2700.0, y = -1430.0, z = 45.0 },
    blackwater_post = { id = 'blackwater_post', region = 'great_plains', x = -865.0, y = -1350.0, z = 44.0 },
    bluewater_marsh_post = { id = 'bluewater_marsh_post', region = 'bluewater_marsh', x = 2300.0, y = -600.0, z = 20.0 },
    annesburg_post = { id = 'annesburg_post', region = 'roanoke_ridge', x = 2925.0, y = 1295.0, z = 96.0 },
    van_horn_post = { id = 'van_horn_post', region = 'roanoke_ridge', x = 2975.0, y = 600.0, z = 38.0 },
    wapiti_post = { id = 'wapiti_post', region = 'grizzlies_east', x = 1675.0, y = 1895.0, z = 200.0 },
    colter_post = { id = 'colter_post', region = 'grizzlies_west', x = -1305.0, y = 1595.0, z = 240.0 },
    bacchus_station_post = { id = 'bacchus_station_post', region = 'cumberland_forest', x = -815.0, y = 1335.0, z = 130.0 },
    strawberry_post = { id = 'strawberry_post', region = 'big_valley', x = -1810.0, y = -435.0, z = 120.0 },
    wallace_station_post = { id = 'wallace_station_post', region = 'big_valley', x = -1345.0, y = -435.0, z = 130.0 },
    manzanita_post = { id = 'manzanita_post', region = 'tall_trees', x = -1790.0, y = -1595.0, z = 150.0 },
    macfarlanes_ranch_post = { id = 'macfarlanes_ranch_post', region = 'hennigans_stead', x = -2275.0, y = -2485.0, z = 60.0 },
    thieves_landing_post = { id = 'thieves_landing_post', region = 'hennigans_stead', x = -1438.0, y = -2218.0, z = 40.0 },
    armadillo_post = { id = 'armadillo_post', region = 'cholla_springs', x = -3703.0, y = -2573.0, z = 70.0 },
    tumbleweed_post = { id = 'tumbleweed_post', region = 'gaptooth_ridge', x = -5514.0, y = -2928.0, z = 90.0 },
    rio_bravo_post = { id = 'rio_bravo_post', region = 'rio_bravo', x = -2000.0, y = -3000.0, z = 55.0 },
}

function regions.getRegion(id) return regions.regions[id] end

function regions.getPost(id) return regions.posts[id] end

---Resolve an alias id to its canonical faction (e.g. rhodes_law -> lawmen).
function regions.getFaction(id)
    local f = regions.factions[id]
    if f and f.alias_of then return regions.factions[f.alias_of] end
    return f
end

---Per-state label for a faction (e.g. lawmen). Resolves aliases, then returns skins[region.state]
---when the faction has a skin for that region's state, otherwise the faction label.
function regions.factionLabel(factionId, regionId)
    local f = regions.getFaction(factionId)
    if not f then return nil end
    local r = regionId and regions.getRegion(regionId) or nil
    if r and type(f.skins) == 'table' and f.skins[r.state] then
        return f.skins[r.state]
    end
    return f.label
end

function regions.getTerritory(id) return regions.territories[id] end

---@return boolean
function regions.isKnownRegion(id)
    return type(id) == 'string' and regions.regions[id] ~= nil
end

-- world-03 (block I): `setr fh_regions_enabled "heartlands,scarlett_meadows,..."` in server.cfg replaces the static
-- `enabled` flags without a code edit. `setr` (not `set`) so the value replicates and this shared file reads the same
-- list on the client. Unset / empty / blank = the data flags apply. Ids split on commas and/or whitespace, are trimmed
-- and lowercased; unknown ids are logged once each and ignored (a list of only unknown ids enables nothing).
regions.ENABLED_CONVAR = 'fh_regions_enabled'
regions.log = function(msg) print(msg) end -- swappable in specs

local warnedUnknown = {}  -- unknown id -> true, so each is logged once per Lua state
local lastRaw, lastSet    -- parse cache keyed on the raw convar string (isEnabled reads the convar every call)

---Parse a convar value into a set of known region ids, or nil when it holds no ids (unset / empty / blank).
---@return table|nil set, string[] unknown
function regions.parseEnabledList(raw)
    if type(raw) ~= 'string' then return nil, {} end
    local set, unknown, any = {}, {}, false
    for token in raw:gmatch('[^,%s]+') do
        any = true
        local id = token:lower()
        if regions.regions[id] then set[id] = true else unknown[#unknown + 1] = id end
    end
    if not any then return nil, unknown end
    return set, unknown
end

---The convar override set, or nil when unset or when GetConvar is unavailable (specs, plain Lua).
local function enabledOverride()
    if type(GetConvar) ~= 'function' then return nil end
    local ok, raw = pcall(GetConvar, regions.ENABLED_CONVAR, '')
    if not ok or type(raw) ~= 'string' then return nil end
    if raw ~= lastRaw then
        local set, unknown = regions.parseEnabledList(raw)
        for _, id in ipairs(unknown) do
            if not warnedUnknown[id] then
                warnedUnknown[id] = true
                regions.log(('[fh_core] %s: unknown region id "%s" ignored'):format(regions.ENABLED_CONVAR, id))
            end
        end
        lastRaw, lastSet = raw, set
    end
    return lastSet
end

---Enabled gate (world-01 block D): true only for a known region that is enabled. Unknown/missing = false,
---so a place referencing a bogus region id is hidden rather than shown. With fh_regions_enabled set (world-03 I),
---the convar list replaces the static `enabled` flags; it is read at call time, never cached at load.
---@return boolean
function regions.isEnabled(id)
    local r = type(id) == 'string' and regions.regions[id] or nil
    if r == nil then return false end
    local override = enabledOverride()
    if override then return override[id] == true end
    return r.enabled == true
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

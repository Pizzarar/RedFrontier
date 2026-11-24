-- fh_crafting config (plan crafting-01 C1). Pure data: no natives, so the specs can load it.
FhCraftingConfig = {
    -- Registered through fh_core's item registry at start (fh_core/shared/items.lua definition shape).
    -- Already in rsg-core and NOT re-registered: resource_gunpowder, ammo_box_revolver, ammo_box_rifle, herb_*.
    items = {
        gun_parts = { label = 'Gun Parts', weight = 150, size_class = 'pocket', stackable = true, value_base = 6,
            image = 'gun_parts.png', useable = false, description = 'Springs, pins and screws for restoring a worn firearm.' },
        lead = { label = 'Lead', weight = 60, size_class = 'pocket', stackable = true, value_base = 1,
            image = 'lead.png', useable = false, description = 'Lead for casting bullets.' },
        casings = { label = 'Brass Casings', weight = 20, size_class = 'pocket', stackable = true, value_base = 1,
            image = 'casings.png', useable = false, description = 'Empty cartridge casings for reloading.' },
        tonic_vigor = { label = 'Vigor Tonic', weight = 200, size_class = 'pocket', stackable = true, value_base = 8,
            image = 'tonic_vigor.png', useable = true, description = 'Herbal tonic that boosts vigor for a while.' },
        tonic_steady = { label = 'Steady Tonic', weight = 200, size_class = 'pocket', stackable = true, value_base = 8,
            image = 'tonic_steady.png', useable = true, description = 'Herbal tonic that steadies the hands for a while.' },
    },

    -- Buff durations in seconds (magnitudes live in shared/craft_rules.lua tonicFor).
    TonicDurations = { tonic_vigor = 600, tonic_steady = 300 },

    -- Dev-only stations, used by server/stations.lua when fh_homestead has no station and convar fh_dev = 1.
    -- TODO-verify-in-game: placeholder coordinates.
    devStations = {
        gunsmith   = { x = -280.0, y = 805.0, z = 119.0 },
        reload     = { x = -283.0, y = 805.0, z = 119.0 },
        apothecary = { x = -286.0, y = 805.0, z = 119.0 },
    },
    stationMaxDist = 3.0,

    -- Crafting station type -> fh_homestead (H3) station type. Homestead only builds workbench/campfire/tanning_rack
    -- (fh_homestead/config.lua), so server/stations.lua maps every crafting type through this before any H3 call.
    stationTypeMap = {
        gunsmith   = 'workbench',
        reload     = 'workbench',
        apothecary = 'campfire',
    },

    -- Wild herb patches (plan crafting-02 C9a): walk up, press E, a short progress bar, and the server grants 1-2 of
    -- the patch's herb. Shared per-patch cooldown (`respawnSeconds`, server memory, cleared on restart). Two patches
    -- per herb, spread over 2 regions. TODO-verify-in-game: every coordinate is an approximate placeholder.
    herbPatches = {
        { id = 'ginseng_heartlands', herb = 'herb_american_ginseng', coords = { x = -290.0, y = 810.0, z = 118.0 }, yield = { 1, 2 }, respawnSeconds = 900 },
        { id = 'ginseng_scarlett',   herb = 'herb_american_ginseng', coords = { x = 1320.0, y = -1290.0, z = 76.0 }, yield = { 1, 2 }, respawnSeconds = 900 },
        { id = 'oregano_heartlands', herb = 'herb_oregano',          coords = { x = -275.0, y = 800.0, z = 119.0 }, yield = { 1, 2 }, respawnSeconds = 900 },
        { id = 'oregano_scarlett',   herb = 'herb_oregano',          coords = { x = 1292.0, y = -1282.0, z = 77.0 }, yield = { 1, 2 }, respawnSeconds = 900 },
        { id = 'red_sage_heartlands', herb = 'herb_red_sage',        coords = { x = -265.0, y = 808.0, z = 118.0 }, yield = { 1, 2 }, respawnSeconds = 900 },
        { id = 'red_sage_scarlett',   herb = 'herb_red_sage',        coords = { x = 1258.0, y = -1270.0, z = 78.0 }, yield = { 1, 2 }, respawnSeconds = 900 },
        { id = 'wild_mint_heartlands', herb = 'herb_wild_mint',      coords = { x = -150.0, y = 840.0, z = 117.0 }, yield = { 1, 2 }, respawnSeconds = 900 },
        { id = 'wild_mint_scarlett',   herb = 'herb_wild_mint',      coords = { x = 1295.0, y = -1285.0, z = 76.0 }, yield = { 1, 2 }, respawnSeconds = 900 },
    },
}

if not GetCurrentResourceName then return FhCraftingConfig end

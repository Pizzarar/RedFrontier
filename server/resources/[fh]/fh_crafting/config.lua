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
}

if not GetCurrentResourceName then return FhCraftingConfig end

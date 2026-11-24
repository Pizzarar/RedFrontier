-- fh_zones camps (spec L89 L3, M1 L107). ALL coordinates, models and weapons are guesses: TODO-verify-in-game.
-- The heartlands camp sits in territory heartlands_t1_camp; the Scarlett Meadows camp in scarlett_meadows_t1_camp
-- (fh_core shared/regions.lua). The second camp reuses the same loot/items as the first; positions are (unverified).
FhZonesConfig = {
    TickMs = 1000, -- ms between server camp ticks
    AbortCooldownMs = 60000, -- after every ped failed to spawn, the camp can't wake again for this long
    camps = {
        heartlands_t1_01 = {
            id = 'heartlands_t1_01',
            region = 'heartlands',
            territory = 'heartlands_t1_camp',
            center = vector3(-145.0, 845.0, 117.0),      -- TODO-verify-in-game
            activationRadius = 45.0,                     -- a player this close wakes the camp
            respawnMinutes = 10,                         -- cleared -> idle after this long (loot stays open meanwhile)
            -- outlaw peds: model/coords/heading/weapon are TODO-verify-in-game
            peds = {
                { model = 'g_m_m_unibanditos_01', coords = vector3(-148.0, 848.0, 117.0), heading = 90.0,  weapon = 'WEAPON_REVOLVER_CATTLEMAN' },
                { model = 'g_m_m_unibanditos_01', coords = vector3(-141.0, 842.0, 117.0), heading = 200.0, weapon = 'WEAPON_REPEATER_CARBINE' },
                { model = 'g_m_m_unibanditos_01', coords = vector3(-150.0, 840.0, 117.0), heading = 45.0,  weapon = 'WEAPON_REVOLVER_CATTLEMAN' },
                { model = 'g_m_m_unibanditos_01', coords = vector3(-139.0, 849.0, 117.0), heading = 270.0, weapon = 'WEAPON_RIFLE_BOLTACTION' },
            },
            -- loot stash: an fh_core `chest` container (accepts cargo). TODO-verify-in-game coords
            loot = {
                coords = vector3(-145.0, 845.0, 117.0),
                label = 'Outlaw camp stash',
                -- chance 0..1 per entry; condition = {min,max} is rolled per instance into info.condition (0-100)
                table = {
                    { name = 'worn_rifle', chance = 1.0, amount = 1, condition = { 20, 45 } },
                    { name = 'small_safe', chance = 1.0, amount = 1 },
                    { name = 'gun_parts', chance = 0.8, amount = { 2, 3 } }, -- item registered by fh_crafting
                },
            },
        },
        scarlett_meadows_t1_01 = {
            id = 'scarlett_meadows_t1_01',
            region = 'scarlett_meadows',
            territory = 'scarlett_meadows_t1_camp',
            center = vector3(1350.0, -1400.0, 76.0),    -- TODO-verify-in-game (unverified)
            activationRadius = 45.0,
            respawnMinutes = 10,
            -- Lemoyne Raiders (models/coords/heading/weapon TODO-verify-in-game; models reused from the heartlands camp)
            peds = {
                { model = 'g_m_m_unibanditos_01', coords = vector3(1347.0, -1397.0, 76.0), heading = 90.0,  weapon = 'WEAPON_REVOLVER_CATTLEMAN' },
                { model = 'g_m_m_unibanditos_01', coords = vector3(1354.0, -1403.0, 76.0), heading = 200.0, weapon = 'WEAPON_REPEATER_CARBINE' },
                { model = 'g_m_m_unibanditos_01', coords = vector3(1345.0, -1405.0, 76.0), heading = 45.0,  weapon = 'WEAPON_REVOLVER_CATTLEMAN' },
                { model = 'g_m_m_unibanditos_01', coords = vector3(1356.0, -1396.0, 76.0), heading = 270.0, weapon = 'WEAPON_RIFLE_BOLTACTION' },
            },
            loot = {
                coords = vector3(1350.0, -1400.0, 76.0),
                label = 'Raider camp stash',
                table = {
                    { name = 'worn_rifle', chance = 1.0, amount = 1, condition = { 20, 45 } },
                    { name = 'small_safe', chance = 1.0, amount = 1 },
                    { name = 'gun_parts', chance = 0.8, amount = { 2, 3 } },
                },
            },
        },
    },
    -- registered through fh_core's item registry at start (shared/items.lua shape)
    items = {
        worn_rifle = { label = 'Worn Rifle', weight = 4000, size_class = 'bulky', stackable = false, value_base = 25 },
        small_safe = { label = 'Small Safe', weight = 25000, size_class = 'bulky', stackable = false, value_base = 60, illicit = true },
    },
}

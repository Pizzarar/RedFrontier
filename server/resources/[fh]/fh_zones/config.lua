-- fh_zones camps (spec L89 L3, M1 L107). Ped models, weapons and loot coords are guesses: TODO-verify-in-game.
-- world-01 (block C): 14 outlaw camps, 3-4 per enabled region, each owned by its region's gang faction via
-- `territory` (fh_core shared/regions.lua territories[].faction). Camp center/region are NOT defined here:
-- they resolve from FhRegions.territories at load (world-02 block F, FhPlaceResolver) — single source of truth.
-- world-01 (block D): each camp carries `enabled` (a mirror of regions.lua `enabled` for its `region`); the camp
-- state machine refuses to activate a camp with enabled=false. world_spacing_spec asserts it matches isEnabled.
FhZonesConfig = {
    TickMs = 1000, -- ms between server camp ticks
    AbortCooldownMs = 60000, -- after every ped failed to spawn, the camp can't wake again for this long
    camps = {
        heartlands_t1_01 = {
            id = 'heartlands_t1_01',
            territory = 'heartlands_t1_camp',
            name = 'Heartland Bluffs camp',
            verified = false,
            enabled = true,
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
            territory = 'scarlett_meadows_t1_camp',
            name = 'Hill Haven camp',
            verified = false,
            enabled = true,
            activationRadius = 45.0,
            respawnMinutes = 10,
            -- Swamp Gang (models/coords/heading/weapon TODO-verify-in-game; models reused from the heartlands camp)
            peds = {
                { model = 'g_m_m_unibanditos_01', coords = vector3(847.0, -1047.0, 75.0), heading = 90.0,  weapon = 'WEAPON_REVOLVER_CATTLEMAN' },
                { model = 'g_m_m_unibanditos_01', coords = vector3(854.0, -1053.0, 75.0), heading = 200.0, weapon = 'WEAPON_REPEATER_CARBINE' },
                { model = 'g_m_m_unibanditos_01', coords = vector3(845.0, -1055.0, 75.0), heading = 45.0,  weapon = 'WEAPON_REVOLVER_CATTLEMAN' },
                { model = 'g_m_m_unibanditos_01', coords = vector3(856.0, -1046.0, 75.0), heading = 270.0, weapon = 'WEAPON_RIFLE_BOLTACTION' },
            },
            loot = {
                coords = vector3(850.0, -1050.0, 75.0),
                label = 'Raider camp stash',
                table = {
                    { name = 'worn_rifle', chance = 1.0, amount = 1, condition = { 20, 45 } },
                    { name = 'small_safe', chance = 1.0, amount = 1 },
                    { name = 'gun_parts', chance = 0.8, amount = { 2, 3 } },
                },
            },
        },
        -- Heartlands (outlaws = Mountain Gang)
        heartlands_t1_02 = {
            id = 'heartlands_t1_02',
            territory = 'heartlands_t1_camp_2',
            name = 'Heartland Overflow camp',
            verified = false,
            enabled = true,
            activationRadius = 45.0,
            respawnMinutes = 10,
            peds = {
                { model = 'g_m_m_unibanditos_01', coords = vector3(847.0, 853.0, 100.0), heading = 90.0,  weapon = 'WEAPON_REVOLVER_CATTLEMAN' },
                { model = 'g_m_m_unibanditos_01', coords = vector3(854.0, 847.0, 100.0), heading = 200.0, weapon = 'WEAPON_REPEATER_CARBINE' },
                { model = 'g_m_m_unibanditos_01', coords = vector3(845.0, 845.0, 100.0), heading = 45.0,  weapon = 'WEAPON_REVOLVER_CATTLEMAN' },
                { model = 'g_m_m_unibanditos_01', coords = vector3(856.0, 854.0, 100.0), heading = 270.0, weapon = 'WEAPON_RIFLE_BOLTACTION' },
            },
            loot = {
                coords = vector3(850.0, 850.0, 100.0),
                label = 'Outlaw camp stash',
                table = {
                    { name = 'worn_rifle', chance = 1.0, amount = 1, condition = { 20, 45 } },
                    { name = 'small_safe', chance = 1.0, amount = 1 },
                    { name = 'gun_parts', chance = 0.8, amount = { 2, 3 } },
                },
            },
        },
        heartlands_t1_03 = {
            id = 'heartlands_t1_03',
            territory = 'heartlands_t1_camp_3',
            name = 'Dakota West camp',
            verified = false,
            enabled = true,
            activationRadius = 45.0,
            respawnMinutes = 10,
            peds = {
                { model = 'g_m_m_unibanditos_01', coords = vector3(-903.0, 503.0, 105.0), heading = 90.0,  weapon = 'WEAPON_REVOLVER_CATTLEMAN' },
                { model = 'g_m_m_unibanditos_01', coords = vector3(-896.0, 497.0, 105.0), heading = 200.0, weapon = 'WEAPON_REPEATER_CARBINE' },
                { model = 'g_m_m_unibanditos_01', coords = vector3(-905.0, 495.0, 105.0), heading = 45.0,  weapon = 'WEAPON_REVOLVER_CATTLEMAN' },
                { model = 'g_m_m_unibanditos_01', coords = vector3(-894.0, 504.0, 105.0), heading = 270.0, weapon = 'WEAPON_RIFLE_BOLTACTION' },
            },
            loot = {
                coords = vector3(-900.0, 500.0, 105.0),
                label = 'Outlaw camp stash',
                table = {
                    { name = 'worn_rifle', chance = 1.0, amount = 1, condition = { 20, 45 } },
                    { name = 'small_safe', chance = 1.0, amount = 1 },
                    { name = 'gun_parts', chance = 0.8, amount = { 2, 3 } },
                },
            },
        },
        heartlands_t2_01 = {
            id = 'heartlands_t2_01',
            territory = 'heartlands_t2_camp',
            name = 'Dakota South camp',
            verified = false,
            enabled = true,
            activationRadius = 45.0,
            respawnMinutes = 10,
            peds = {
                { model = 'g_m_m_unibanditos_01', coords = vector3(597.0, 203.0, 90.0), heading = 90.0,  weapon = 'WEAPON_REVOLVER_CATTLEMAN' },
                { model = 'g_m_m_unibanditos_01', coords = vector3(604.0, 197.0, 90.0), heading = 200.0, weapon = 'WEAPON_REPEATER_CARBINE' },
                { model = 'g_m_m_unibanditos_01', coords = vector3(595.0, 195.0, 90.0), heading = 45.0,  weapon = 'WEAPON_REVOLVER_CATTLEMAN' },
                { model = 'g_m_m_unibanditos_01', coords = vector3(606.0, 204.0, 90.0), heading = 270.0, weapon = 'WEAPON_RIFLE_BOLTACTION' },
            },
            loot = {
                coords = vector3(600.0, 200.0, 90.0),
                label = 'Outlaw camp stash',
                table = {
                    { name = 'worn_rifle', chance = 1.0, amount = 1, condition = { 20, 45 } },
                    { name = 'small_safe', chance = 1.0, amount = 1 },
                    { name = 'gun_parts', chance = 0.8, amount = { 2, 3 } },
                },
            },
        },
        -- Scarlett Meadows (raiders = Swamp Gang)
        scarlett_meadows_t1_02 = {
            id = 'scarlett_meadows_t1_02',
            territory = 'scarlett_meadows_t1_camp_2',
            name = 'Cedar Bottoms camp',
            verified = false,
            enabled = true,
            activationRadius = 45.0,
            respawnMinutes = 10,
            peds = {
                { model = 'g_m_m_unibanditos_01', coords = vector3(1497.0, -1647.0, 70.0), heading = 90.0,  weapon = 'WEAPON_REVOLVER_CATTLEMAN' },
                { model = 'g_m_m_unibanditos_01', coords = vector3(1504.0, -1653.0, 70.0), heading = 200.0, weapon = 'WEAPON_REPEATER_CARBINE' },
                { model = 'g_m_m_unibanditos_01', coords = vector3(1495.0, -1655.0, 70.0), heading = 45.0,  weapon = 'WEAPON_REVOLVER_CATTLEMAN' },
                { model = 'g_m_m_unibanditos_01', coords = vector3(1506.0, -1646.0, 70.0), heading = 270.0, weapon = 'WEAPON_RIFLE_BOLTACTION' },
            },
            loot = {
                coords = vector3(1500.0, -1650.0, 70.0),
                label = 'Raider camp stash',
                table = {
                    { name = 'worn_rifle', chance = 1.0, amount = 1, condition = { 20, 45 } },
                    { name = 'small_safe', chance = 1.0, amount = 1 },
                    { name = 'gun_parts', chance = 0.8, amount = { 2, 3 } },
                },
            },
        },
        scarlett_meadows_t2_01 = {
            id = 'scarlett_meadows_t2_01',
            territory = 'scarlett_meadows_t2_camp',
            name = 'Catfish Bottom camp',
            verified = false,
            enabled = true,
            activationRadius = 45.0,
            respawnMinutes = 10,
            peds = {
                { model = 'g_m_m_unibanditos_01', coords = vector3(1697.0, -1747.0, 65.0), heading = 90.0,  weapon = 'WEAPON_REVOLVER_CATTLEMAN' },
                { model = 'g_m_m_unibanditos_01', coords = vector3(1704.0, -1753.0, 65.0), heading = 200.0, weapon = 'WEAPON_REPEATER_CARBINE' },
                { model = 'g_m_m_unibanditos_01', coords = vector3(1695.0, -1755.0, 65.0), heading = 45.0,  weapon = 'WEAPON_REVOLVER_CATTLEMAN' },
                { model = 'g_m_m_unibanditos_01', coords = vector3(1706.0, -1746.0, 65.0), heading = 270.0, weapon = 'WEAPON_RIFLE_BOLTACTION' },
            },
            loot = {
                coords = vector3(1700.0, -1750.0, 65.0),
                label = 'Raider camp stash',
                table = {
                    { name = 'worn_rifle', chance = 1.0, amount = 1, condition = { 20, 45 } },
                    { name = 'small_safe', chance = 1.0, amount = 1 },
                    { name = 'gun_parts', chance = 0.8, amount = { 2, 3 } },
                },
            },
        },
        -- Bayou Nwa (raiders = Swamp Gang)
        bayou_nwa_t1_01 = {
            id = 'bayou_nwa_t1_01',
            territory = 'bayou_nwa_t1_camp',
            name = 'Moss Bog camp',
            verified = false,
            enabled = true,
            activationRadius = 45.0,
            respawnMinutes = 10,
            peds = {
                { model = 'g_m_m_unibanditos_01', coords = vector3(2047.0, -1497.0, 25.0), heading = 90.0,  weapon = 'WEAPON_REVOLVER_CATTLEMAN' },
                { model = 'g_m_m_unibanditos_01', coords = vector3(2054.0, -1503.0, 25.0), heading = 200.0, weapon = 'WEAPON_REPEATER_CARBINE' },
                { model = 'g_m_m_unibanditos_01', coords = vector3(2045.0, -1505.0, 25.0), heading = 45.0,  weapon = 'WEAPON_REVOLVER_CATTLEMAN' },
                { model = 'g_m_m_unibanditos_01', coords = vector3(2056.0, -1496.0, 25.0), heading = 270.0, weapon = 'WEAPON_RIFLE_BOLTACTION' },
            },
            loot = {
                coords = vector3(2050.0, -1500.0, 25.0),
                label = 'Raider camp stash',
                table = {
                    { name = 'worn_rifle', chance = 1.0, amount = 1, condition = { 20, 45 } },
                    { name = 'small_safe', chance = 1.0, amount = 1 },
                    { name = 'gun_parts', chance = 0.8, amount = { 2, 3 } },
                },
            },
        },
        bayou_nwa_t1_02 = {
            id = 'bayou_nwa_t1_02',
            territory = 'bayou_nwa_t1_camp_2',
            name = 'Bayou Railroad camp',
            verified = false,
            enabled = true,
            activationRadius = 45.0,
            respawnMinutes = 10,
            peds = {
                { model = 'g_m_m_unibanditos_01', coords = vector3(2397.0, -947.0, 25.0), heading = 90.0,  weapon = 'WEAPON_REVOLVER_CATTLEMAN' },
                { model = 'g_m_m_unibanditos_01', coords = vector3(2404.0, -953.0, 25.0), heading = 200.0, weapon = 'WEAPON_REPEATER_CARBINE' },
                { model = 'g_m_m_unibanditos_01', coords = vector3(2395.0, -955.0, 25.0), heading = 45.0,  weapon = 'WEAPON_REVOLVER_CATTLEMAN' },
                { model = 'g_m_m_unibanditos_01', coords = vector3(2406.0, -946.0, 25.0), heading = 270.0, weapon = 'WEAPON_RIFLE_BOLTACTION' },
            },
            loot = {
                coords = vector3(2400.0, -950.0, 25.0),
                label = 'Raider camp stash',
                table = {
                    { name = 'worn_rifle', chance = 1.0, amount = 1, condition = { 20, 45 } },
                    { name = 'small_safe', chance = 1.0, amount = 1 },
                    { name = 'gun_parts', chance = 0.8, amount = { 2, 3 } },
                },
            },
        },
        bayou_nwa_t1_03 = {
            id = 'bayou_nwa_t1_03',
            territory = 'bayou_nwa_t1_camp_3',
            name = 'Lagras Swamp camp',
            verified = false,
            enabled = true,
            activationRadius = 45.0,
            respawnMinutes = 10,
            peds = {
                { model = 'g_m_m_unibanditos_01', coords = vector3(2197.0, -1647.0, 25.0), heading = 90.0,  weapon = 'WEAPON_REVOLVER_CATTLEMAN' },
                { model = 'g_m_m_unibanditos_01', coords = vector3(2204.0, -1653.0, 25.0), heading = 200.0, weapon = 'WEAPON_REPEATER_CARBINE' },
                { model = 'g_m_m_unibanditos_01', coords = vector3(2195.0, -1655.0, 25.0), heading = 45.0,  weapon = 'WEAPON_REVOLVER_CATTLEMAN' },
                { model = 'g_m_m_unibanditos_01', coords = vector3(2206.0, -1646.0, 25.0), heading = 270.0, weapon = 'WEAPON_RIFLE_BOLTACTION' },
            },
            loot = {
                coords = vector3(2200.0, -1650.0, 25.0),
                label = 'Raider camp stash',
                table = {
                    { name = 'worn_rifle', chance = 1.0, amount = 1, condition = { 20, 45 } },
                    { name = 'small_safe', chance = 1.0, amount = 1 },
                    { name = 'gun_parts', chance = 0.8, amount = { 2, 3 } },
                },
            },
        },
        bayou_nwa_t2_01 = {
            id = 'bayou_nwa_t2_01',
            territory = 'bayou_nwa_t2_camp',
            name = 'Cypress Hollow camp',
            verified = false,
            enabled = true,
            activationRadius = 45.0,
            respawnMinutes = 10,
            peds = {
                { model = 'g_m_m_unibanditos_01', coords = vector3(2547.0, -1747.0, 20.0), heading = 90.0,  weapon = 'WEAPON_REVOLVER_CATTLEMAN' },
                { model = 'g_m_m_unibanditos_01', coords = vector3(2554.0, -1753.0, 20.0), heading = 200.0, weapon = 'WEAPON_REPEATER_CARBINE' },
                { model = 'g_m_m_unibanditos_01', coords = vector3(2545.0, -1755.0, 20.0), heading = 45.0,  weapon = 'WEAPON_REVOLVER_CATTLEMAN' },
                { model = 'g_m_m_unibanditos_01', coords = vector3(2556.0, -1746.0, 20.0), heading = 270.0, weapon = 'WEAPON_RIFLE_BOLTACTION' },
            },
            loot = {
                coords = vector3(2550.0, -1750.0, 20.0),
                label = 'Raider camp stash',
                table = {
                    { name = 'worn_rifle', chance = 1.0, amount = 1, condition = { 20, 45 } },
                    { name = 'small_safe', chance = 1.0, amount = 1 },
                    { name = 'gun_parts', chance = 0.8, amount = { 2, 3 } },
                },
            },
        },
        -- Great Plains (outlaws = Mountain Gang)
        great_plains_t1_01 = {
            id = 'great_plains_t1_01',
            territory = 'great_plains_t1_camp',
            name = 'Bison Bluff camp',
            verified = false,
            enabled = true,
            activationRadius = 45.0,
            respawnMinutes = 10,
            peds = {
                { model = 'g_m_m_unibanditos_01', coords = vector3(-1603.0, -1347.0, 40.0), heading = 90.0,  weapon = 'WEAPON_REVOLVER_CATTLEMAN' },
                { model = 'g_m_m_unibanditos_01', coords = vector3(-1596.0, -1353.0, 40.0), heading = 200.0, weapon = 'WEAPON_REPEATER_CARBINE' },
                { model = 'g_m_m_unibanditos_01', coords = vector3(-1605.0, -1355.0, 40.0), heading = 45.0,  weapon = 'WEAPON_REVOLVER_CATTLEMAN' },
                { model = 'g_m_m_unibanditos_01', coords = vector3(-1594.0, -1346.0, 40.0), heading = 270.0, weapon = 'WEAPON_RIFLE_BOLTACTION' },
            },
            loot = {
                coords = vector3(-1600.0, -1350.0, 40.0),
                label = 'Outlaw camp stash',
                table = {
                    { name = 'worn_rifle', chance = 1.0, amount = 1, condition = { 20, 45 } },
                    { name = 'small_safe', chance = 1.0, amount = 1 },
                    { name = 'gun_parts', chance = 0.8, amount = { 2, 3 } },
                },
            },
        },
        great_plains_t1_02 = {
            id = 'great_plains_t1_02',
            territory = 'great_plains_t1_camp_2',
            name = 'Great Plains North camp',
            verified = false,
            enabled = true,
            activationRadius = 45.0,
            respawnMinutes = 10,
            peds = {
                { model = 'g_m_m_unibanditos_01', coords = vector3(-1053.0, -897.0, 45.0), heading = 90.0,  weapon = 'WEAPON_REVOLVER_CATTLEMAN' },
                { model = 'g_m_m_unibanditos_01', coords = vector3(-1046.0, -903.0, 45.0), heading = 200.0, weapon = 'WEAPON_REPEATER_CARBINE' },
                { model = 'g_m_m_unibanditos_01', coords = vector3(-1055.0, -905.0, 45.0), heading = 45.0,  weapon = 'WEAPON_REVOLVER_CATTLEMAN' },
                { model = 'g_m_m_unibanditos_01', coords = vector3(-1044.0, -896.0, 45.0), heading = 270.0, weapon = 'WEAPON_RIFLE_BOLTACTION' },
            },
            loot = {
                coords = vector3(-1050.0, -900.0, 45.0),
                label = 'Outlaw camp stash',
                table = {
                    { name = 'worn_rifle', chance = 1.0, amount = 1, condition = { 20, 45 } },
                    { name = 'small_safe', chance = 1.0, amount = 1 },
                    { name = 'gun_parts', chance = 0.8, amount = { 2, 3 } },
                },
            },
        },
        great_plains_t2_01 = {
            id = 'great_plains_t2_01',
            territory = 'great_plains_t2_camp',
            name = 'Great Plains East camp',
            verified = false,
            enabled = true,
            activationRadius = 45.0,
            respawnMinutes = 10,
            peds = {
                { model = 'g_m_m_unibanditos_01', coords = vector3(-703.0, -1597.0, 40.0), heading = 90.0,  weapon = 'WEAPON_REVOLVER_CATTLEMAN' },
                { model = 'g_m_m_unibanditos_01', coords = vector3(-696.0, -1603.0, 40.0), heading = 200.0, weapon = 'WEAPON_REPEATER_CARBINE' },
                { model = 'g_m_m_unibanditos_01', coords = vector3(-705.0, -1605.0, 40.0), heading = 45.0,  weapon = 'WEAPON_REVOLVER_CATTLEMAN' },
                { model = 'g_m_m_unibanditos_01', coords = vector3(-694.0, -1596.0, 40.0), heading = 270.0, weapon = 'WEAPON_RIFLE_BOLTACTION' },
            },
            loot = {
                coords = vector3(-700.0, -1600.0, 40.0),
                label = 'Outlaw camp stash',
                table = {
                    { name = 'worn_rifle', chance = 1.0, amount = 1, condition = { 20, 45 } },
                    { name = 'small_safe', chance = 1.0, amount = 1 },
                    { name = 'gun_parts', chance = 0.8, amount = { 2, 3 } },
                },
            },
        },
        -- Bluewater Marsh (raiders = Swamp Gang)
        bluewater_marsh_t1_01 = {
            id = 'bluewater_marsh_t1_01',
            territory = 'bluewater_marsh_t1_camp',
            name = 'Marsh Ford camp',
            verified = false,
            enabled = false,
            activationRadius = 45.0,
            respawnMinutes = 10,
            peds = {
                { model = 'g_m_m_unibanditos_01', coords = vector3(2397.0, -397.0, 25.0), heading = 90.0,  weapon = 'WEAPON_REVOLVER_CATTLEMAN' },
                { model = 'g_m_m_unibanditos_01', coords = vector3(2404.0, -403.0, 25.0), heading = 200.0, weapon = 'WEAPON_REPEATER_CARBINE' },
                { model = 'g_m_m_unibanditos_01', coords = vector3(2395.0, -405.0, 25.0), heading = 45.0,  weapon = 'WEAPON_REVOLVER_CATTLEMAN' },
                { model = 'g_m_m_unibanditos_01', coords = vector3(2406.0, -396.0, 25.0), heading = 270.0, weapon = 'WEAPON_RIFLE_BOLTACTION' },
            },
            loot = {
                coords = vector3(2400.0, -400.0, 25.0),
                label = 'Raider camp stash',
                table = {
                    { name = 'worn_rifle', chance = 1.0, amount = 1, condition = { 20, 45 } },
                    { name = 'small_safe', chance = 1.0, amount = 1 },
                    { name = 'gun_parts', chance = 0.8, amount = { 2, 3 } },
                },
            },
        },
        bluewater_marsh_t1_02 = {
            id = 'bluewater_marsh_t1_02',
            territory = 'bluewater_marsh_t1_camp_2',
            name = 'Bullrush camp',
            verified = false,
            enabled = false,
            activationRadius = 45.0,
            respawnMinutes = 10,
            peds = {
                { model = 'g_m_m_unibanditos_01', coords = vector3(1997.0, -447.0, 20.0), heading = 90.0,  weapon = 'WEAPON_REVOLVER_CATTLEMAN' },
                { model = 'g_m_m_unibanditos_01', coords = vector3(2004.0, -453.0, 20.0), heading = 200.0, weapon = 'WEAPON_REPEATER_CARBINE' },
                { model = 'g_m_m_unibanditos_01', coords = vector3(1995.0, -455.0, 20.0), heading = 45.0,  weapon = 'WEAPON_REVOLVER_CATTLEMAN' },
                { model = 'g_m_m_unibanditos_01', coords = vector3(2006.0, -446.0, 20.0), heading = 270.0, weapon = 'WEAPON_RIFLE_BOLTACTION' },
            },
            loot = {
                coords = vector3(2000.0, -450.0, 20.0),
                label = 'Raider camp stash',
                table = {
                    { name = 'worn_rifle', chance = 1.0, amount = 1, condition = { 20, 45 } },
                    { name = 'small_safe', chance = 1.0, amount = 1 },
                    { name = 'gun_parts', chance = 0.8, amount = { 2, 3 } },
                },
            },
        },
        bluewater_marsh_t2_01 = {
            id = 'bluewater_marsh_t2_01',
            territory = 'bluewater_marsh_t2_camp',
            name = 'Cypress Bend camp',
            verified = false,
            enabled = false,
            activationRadius = 45.0,
            respawnMinutes = 10,
            peds = {
                { model = 'g_m_m_unibanditos_01', coords = vector3(2847.0, -897.0, 20.0), heading = 90.0,  weapon = 'WEAPON_REVOLVER_CATTLEMAN' },
                { model = 'g_m_m_unibanditos_01', coords = vector3(2854.0, -903.0, 20.0), heading = 200.0, weapon = 'WEAPON_REPEATER_CARBINE' },
                { model = 'g_m_m_unibanditos_01', coords = vector3(2845.0, -905.0, 20.0), heading = 45.0,  weapon = 'WEAPON_REVOLVER_CATTLEMAN' },
                { model = 'g_m_m_unibanditos_01', coords = vector3(2856.0, -896.0, 20.0), heading = 270.0, weapon = 'WEAPON_RIFLE_BOLTACTION' },
            },
            loot = {
                coords = vector3(2850.0, -900.0, 20.0),
                label = 'Raider camp stash',
                table = {
                    { name = 'worn_rifle', chance = 1.0, amount = 1, condition = { 20, 45 } },
                    { name = 'small_safe', chance = 1.0, amount = 1 },
                    { name = 'gun_parts', chance = 0.8, amount = { 2, 3 } },
                },
            },
        },
        -- Roanoke Ridge (outlaws = Mountain Gang)
        roanoke_ridge_t1_01 = {
            id = 'roanoke_ridge_t1_01',
            territory = 'roanoke_ridge_t1_camp',
            name = 'Riverbend camp',
            verified = false,
            enabled = false,
            activationRadius = 45.0,
            respawnMinutes = 10,
            peds = {
                { model = 'g_m_m_unibanditos_01', coords = vector3(2247.0, 803.0, 90.0), heading = 90.0,  weapon = 'WEAPON_REVOLVER_CATTLEMAN' },
                { model = 'g_m_m_unibanditos_01', coords = vector3(2254.0, 797.0, 90.0), heading = 200.0, weapon = 'WEAPON_REPEATER_CARBINE' },
                { model = 'g_m_m_unibanditos_01', coords = vector3(2245.0, 795.0, 90.0), heading = 45.0,  weapon = 'WEAPON_REVOLVER_CATTLEMAN' },
                { model = 'g_m_m_unibanditos_01', coords = vector3(2256.0, 804.0, 90.0), heading = 270.0, weapon = 'WEAPON_RIFLE_BOLTACTION' },
            },
            loot = {
                coords = vector3(2250.0, 800.0, 90.0),
                label = 'Outlaw camp stash',
                table = {
                    { name = 'worn_rifle', chance = 1.0, amount = 1, condition = { 20, 45 } },
                    { name = 'small_safe', chance = 1.0, amount = 1 },
                    { name = 'gun_parts', chance = 0.8, amount = { 2, 3 } },
                },
            },
        },
        roanoke_ridge_t1_02 = {
            id = 'roanoke_ridge_t1_02',
            territory = 'roanoke_ridge_t1_camp_2',
            name = 'Timber Ridge camp',
            verified = false,
            enabled = false,
            activationRadius = 45.0,
            respawnMinutes = 10,
            peds = {
                { model = 'g_m_m_unibanditos_01', coords = vector3(2597.0, 1453.0, 120.0), heading = 90.0,  weapon = 'WEAPON_REVOLVER_CATTLEMAN' },
                { model = 'g_m_m_unibanditos_01', coords = vector3(2604.0, 1447.0, 120.0), heading = 200.0, weapon = 'WEAPON_REPEATER_CARBINE' },
                { model = 'g_m_m_unibanditos_01', coords = vector3(2595.0, 1445.0, 120.0), heading = 45.0,  weapon = 'WEAPON_REVOLVER_CATTLEMAN' },
                { model = 'g_m_m_unibanditos_01', coords = vector3(2606.0, 1454.0, 120.0), heading = 270.0, weapon = 'WEAPON_RIFLE_BOLTACTION' },
            },
            loot = {
                coords = vector3(2600.0, 1450.0, 120.0),
                label = 'Outlaw camp stash',
                table = {
                    { name = 'worn_rifle', chance = 1.0, amount = 1, condition = { 20, 45 } },
                    { name = 'small_safe', chance = 1.0, amount = 1 },
                    { name = 'gun_parts', chance = 0.8, amount = { 2, 3 } },
                },
            },
        },
        roanoke_ridge_t2_01 = {
            id = 'roanoke_ridge_t2_01',
            territory = 'roanoke_ridge_t2_camp',
            name = 'Iron Hollow camp',
            verified = false,
            enabled = false,
            activationRadius = 45.0,
            respawnMinutes = 10,
            peds = {
                { model = 'g_m_m_unibanditos_01', coords = vector3(2447.0, 653.0, 70.0), heading = 90.0,  weapon = 'WEAPON_REVOLVER_CATTLEMAN' },
                { model = 'g_m_m_unibanditos_01', coords = vector3(2454.0, 647.0, 70.0), heading = 200.0, weapon = 'WEAPON_REPEATER_CARBINE' },
                { model = 'g_m_m_unibanditos_01', coords = vector3(2445.0, 645.0, 70.0), heading = 45.0,  weapon = 'WEAPON_REVOLVER_CATTLEMAN' },
                { model = 'g_m_m_unibanditos_01', coords = vector3(2456.0, 654.0, 70.0), heading = 270.0, weapon = 'WEAPON_RIFLE_BOLTACTION' },
            },
            loot = {
                coords = vector3(2450.0, 650.0, 70.0),
                label = 'Outlaw camp stash',
                table = {
                    { name = 'worn_rifle', chance = 1.0, amount = 1, condition = { 20, 45 } },
                    { name = 'small_safe', chance = 1.0, amount = 1 },
                    { name = 'gun_parts', chance = 0.8, amount = { 2, 3 } },
                },
            },
        },
        -- Grizzlies East (outlaws = Mountain Gang)
        grizzlies_east_t1_01 = {
            id = 'grizzlies_east_t1_01',
            territory = 'grizzlies_east_t1_camp',
            name = 'Frost Creek camp',
            verified = false,
            enabled = false,
            activationRadius = 45.0,
            respawnMinutes = 10,
            peds = {
                { model = 'g_m_m_unibanditos_01', coords = vector3(1377.0, 1383.0, 190.0), heading = 90.0,  weapon = 'WEAPON_REVOLVER_CATTLEMAN' },
                { model = 'g_m_m_unibanditos_01', coords = vector3(1384.0, 1377.0, 190.0), heading = 200.0, weapon = 'WEAPON_REPEATER_CARBINE' },
                { model = 'g_m_m_unibanditos_01', coords = vector3(1375.0, 1375.0, 190.0), heading = 45.0,  weapon = 'WEAPON_REVOLVER_CATTLEMAN' },
                { model = 'g_m_m_unibanditos_01', coords = vector3(1386.0, 1384.0, 190.0), heading = 270.0, weapon = 'WEAPON_RIFLE_BOLTACTION' },
            },
            loot = {
                coords = vector3(1380.0, 1380.0, 190.0),
                label = 'Outlaw camp stash',
                table = {
                    { name = 'worn_rifle', chance = 1.0, amount = 1, condition = { 20, 45 } },
                    { name = 'small_safe', chance = 1.0, amount = 1 },
                    { name = 'gun_parts', chance = 0.8, amount = { 2, 3 } },
                },
            },
        },
        grizzlies_east_t1_02 = {
            id = 'grizzlies_east_t1_02',
            territory = 'grizzlies_east_t1_camp_2',
            name = 'Aspen camp',
            verified = false,
            enabled = false,
            activationRadius = 45.0,
            respawnMinutes = 10,
            peds = {
                { model = 'g_m_m_unibanditos_01', coords = vector3(1847.0, 1503.0, 200.0), heading = 90.0,  weapon = 'WEAPON_REVOLVER_CATTLEMAN' },
                { model = 'g_m_m_unibanditos_01', coords = vector3(1854.0, 1497.0, 200.0), heading = 200.0, weapon = 'WEAPON_REPEATER_CARBINE' },
                { model = 'g_m_m_unibanditos_01', coords = vector3(1845.0, 1495.0, 200.0), heading = 45.0,  weapon = 'WEAPON_REVOLVER_CATTLEMAN' },
                { model = 'g_m_m_unibanditos_01', coords = vector3(1856.0, 1504.0, 200.0), heading = 270.0, weapon = 'WEAPON_RIFLE_BOLTACTION' },
            },
            loot = {
                coords = vector3(1850.0, 1500.0, 200.0),
                label = 'Outlaw camp stash',
                table = {
                    { name = 'worn_rifle', chance = 1.0, amount = 1, condition = { 20, 45 } },
                    { name = 'small_safe', chance = 1.0, amount = 1 },
                    { name = 'gun_parts', chance = 0.8, amount = { 2, 3 } },
                },
            },
        },
        grizzlies_east_t2_01 = {
            id = 'grizzlies_east_t2_01',
            territory = 'grizzlies_east_t2_camp',
            name = 'Granite camp',
            verified = false,
            enabled = false,
            activationRadius = 45.0,
            respawnMinutes = 10,
            peds = {
                { model = 'g_m_m_unibanditos_01', coords = vector3(1497.0, 1153.0, 170.0), heading = 90.0,  weapon = 'WEAPON_REVOLVER_CATTLEMAN' },
                { model = 'g_m_m_unibanditos_01', coords = vector3(1504.0, 1147.0, 170.0), heading = 200.0, weapon = 'WEAPON_REPEATER_CARBINE' },
                { model = 'g_m_m_unibanditos_01', coords = vector3(1495.0, 1145.0, 170.0), heading = 45.0,  weapon = 'WEAPON_REVOLVER_CATTLEMAN' },
                { model = 'g_m_m_unibanditos_01', coords = vector3(1506.0, 1154.0, 170.0), heading = 270.0, weapon = 'WEAPON_RIFLE_BOLTACTION' },
            },
            loot = {
                coords = vector3(1500.0, 1150.0, 170.0),
                label = 'Outlaw camp stash',
                table = {
                    { name = 'worn_rifle', chance = 1.0, amount = 1, condition = { 20, 45 } },
                    { name = 'small_safe', chance = 1.0, amount = 1 },
                    { name = 'gun_parts', chance = 0.8, amount = { 2, 3 } },
                },
            },
        },
        -- Grizzlies West (outlaws = Mountain Gang)
        grizzlies_west_t1_01 = {
            id = 'grizzlies_west_t1_01',
            territory = 'grizzlies_west_t1_camp',
            name = 'Tundra camp',
            verified = false,
            enabled = false,
            activationRadius = 45.0,
            respawnMinutes = 10,
            peds = {
                { model = 'g_m_m_unibanditos_01', coords = vector3(-1463.0, 983.0, 210.0), heading = 90.0,  weapon = 'WEAPON_REVOLVER_CATTLEMAN' },
                { model = 'g_m_m_unibanditos_01', coords = vector3(-1456.0, 977.0, 210.0), heading = 200.0, weapon = 'WEAPON_REPEATER_CARBINE' },
                { model = 'g_m_m_unibanditos_01', coords = vector3(-1465.0, 975.0, 210.0), heading = 45.0,  weapon = 'WEAPON_REVOLVER_CATTLEMAN' },
                { model = 'g_m_m_unibanditos_01', coords = vector3(-1454.0, 984.0, 210.0), heading = 270.0, weapon = 'WEAPON_RIFLE_BOLTACTION' },
            },
            loot = {
                coords = vector3(-1460.0, 980.0, 210.0),
                label = 'Outlaw camp stash',
                table = {
                    { name = 'worn_rifle', chance = 1.0, amount = 1, condition = { 20, 45 } },
                    { name = 'small_safe', chance = 1.0, amount = 1 },
                    { name = 'gun_parts', chance = 0.8, amount = { 2, 3 } },
                },
            },
        },
        grizzlies_west_t1_02 = {
            id = 'grizzlies_west_t1_02',
            territory = 'grizzlies_west_t1_camp_2',
            name = 'High Pass camp',
            verified = false,
            enabled = false,
            activationRadius = 45.0,
            respawnMinutes = 10,
            peds = {
                { model = 'g_m_m_unibanditos_01', coords = vector3(-1853.0, 1653.0, 230.0), heading = 90.0,  weapon = 'WEAPON_REVOLVER_CATTLEMAN' },
                { model = 'g_m_m_unibanditos_01', coords = vector3(-1846.0, 1647.0, 230.0), heading = 200.0, weapon = 'WEAPON_REPEATER_CARBINE' },
                { model = 'g_m_m_unibanditos_01', coords = vector3(-1855.0, 1645.0, 230.0), heading = 45.0,  weapon = 'WEAPON_REVOLVER_CATTLEMAN' },
                { model = 'g_m_m_unibanditos_01', coords = vector3(-1844.0, 1654.0, 230.0), heading = 270.0, weapon = 'WEAPON_RIFLE_BOLTACTION' },
            },
            loot = {
                coords = vector3(-1850.0, 1650.0, 230.0),
                label = 'Outlaw camp stash',
                table = {
                    { name = 'worn_rifle', chance = 1.0, amount = 1, condition = { 20, 45 } },
                    { name = 'small_safe', chance = 1.0, amount = 1 },
                    { name = 'gun_parts', chance = 0.8, amount = { 2, 3 } },
                },
            },
        },
        grizzlies_west_t2_01 = {
            id = 'grizzlies_west_t2_01',
            territory = 'grizzlies_west_t2_camp',
            name = 'Ravine camp',
            verified = false,
            enabled = false,
            activationRadius = 45.0,
            respawnMinutes = 10,
            peds = {
                { model = 'g_m_m_unibanditos_01', coords = vector3(-1153.0, 1253.0, 200.0), heading = 90.0,  weapon = 'WEAPON_REVOLVER_CATTLEMAN' },
                { model = 'g_m_m_unibanditos_01', coords = vector3(-1146.0, 1247.0, 200.0), heading = 200.0, weapon = 'WEAPON_REPEATER_CARBINE' },
                { model = 'g_m_m_unibanditos_01', coords = vector3(-1155.0, 1245.0, 200.0), heading = 45.0,  weapon = 'WEAPON_REVOLVER_CATTLEMAN' },
                { model = 'g_m_m_unibanditos_01', coords = vector3(-1144.0, 1254.0, 200.0), heading = 270.0, weapon = 'WEAPON_RIFLE_BOLTACTION' },
            },
            loot = {
                coords = vector3(-1150.0, 1250.0, 200.0),
                label = 'Outlaw camp stash',
                table = {
                    { name = 'worn_rifle', chance = 1.0, amount = 1, condition = { 20, 45 } },
                    { name = 'small_safe', chance = 1.0, amount = 1 },
                    { name = 'gun_parts', chance = 0.8, amount = { 2, 3 } },
                },
            },
        },
        -- Cumberland Forest (outlaws = Mountain Gang)
        cumberland_forest_t1_01 = {
            id = 'cumberland_forest_t1_01',
            territory = 'cumberland_forest_t1_camp',
            name = 'Rapids camp',
            verified = false,
            enabled = false,
            activationRadius = 45.0,
            respawnMinutes = 10,
            peds = {
                { model = 'g_m_m_unibanditos_01', coords = vector3(-933.0, 1123.0, 110.0), heading = 90.0,  weapon = 'WEAPON_REVOLVER_CATTLEMAN' },
                { model = 'g_m_m_unibanditos_01', coords = vector3(-926.0, 1117.0, 110.0), heading = 200.0, weapon = 'WEAPON_REPEATER_CARBINE' },
                { model = 'g_m_m_unibanditos_01', coords = vector3(-935.0, 1115.0, 110.0), heading = 45.0,  weapon = 'WEAPON_REVOLVER_CATTLEMAN' },
                { model = 'g_m_m_unibanditos_01', coords = vector3(-924.0, 1124.0, 110.0), heading = 270.0, weapon = 'WEAPON_RIFLE_BOLTACTION' },
            },
            loot = {
                coords = vector3(-930.0, 1120.0, 110.0),
                label = 'Outlaw camp stash',
                table = {
                    { name = 'worn_rifle', chance = 1.0, amount = 1, condition = { 20, 45 } },
                    { name = 'small_safe', chance = 1.0, amount = 1 },
                    { name = 'gun_parts', chance = 0.8, amount = { 2, 3 } },
                },
            },
        },
        cumberland_forest_t1_02 = {
            id = 'cumberland_forest_t1_02',
            territory = 'cumberland_forest_t1_camp_2',
            name = 'Elm Grove camp',
            verified = false,
            enabled = false,
            activationRadius = 45.0,
            respawnMinutes = 10,
            peds = {
                { model = 'g_m_m_unibanditos_01', coords = vector3(-433.0, 1023.0, 100.0), heading = 90.0,  weapon = 'WEAPON_REVOLVER_CATTLEMAN' },
                { model = 'g_m_m_unibanditos_01', coords = vector3(-426.0, 1017.0, 100.0), heading = 200.0, weapon = 'WEAPON_REPEATER_CARBINE' },
                { model = 'g_m_m_unibanditos_01', coords = vector3(-435.0, 1015.0, 100.0), heading = 45.0,  weapon = 'WEAPON_REVOLVER_CATTLEMAN' },
                { model = 'g_m_m_unibanditos_01', coords = vector3(-424.0, 1024.0, 100.0), heading = 270.0, weapon = 'WEAPON_RIFLE_BOLTACTION' },
            },
            loot = {
                coords = vector3(-430.0, 1020.0, 100.0),
                label = 'Outlaw camp stash',
                table = {
                    { name = 'worn_rifle', chance = 1.0, amount = 1, condition = { 20, 45 } },
                    { name = 'small_safe', chance = 1.0, amount = 1 },
                    { name = 'gun_parts', chance = 0.8, amount = { 2, 3 } },
                },
            },
        },
        cumberland_forest_t2_01 = {
            id = 'cumberland_forest_t2_01',
            territory = 'cumberland_forest_t2_camp',
            name = 'North Ridge camp',
            verified = false,
            enabled = false,
            activationRadius = 45.0,
            respawnMinutes = 10,
            peds = {
                { model = 'g_m_m_unibanditos_01', coords = vector3(-603.0, 1503.0, 140.0), heading = 90.0,  weapon = 'WEAPON_REVOLVER_CATTLEMAN' },
                { model = 'g_m_m_unibanditos_01', coords = vector3(-596.0, 1497.0, 140.0), heading = 200.0, weapon = 'WEAPON_REPEATER_CARBINE' },
                { model = 'g_m_m_unibanditos_01', coords = vector3(-605.0, 1495.0, 140.0), heading = 45.0,  weapon = 'WEAPON_REVOLVER_CATTLEMAN' },
                { model = 'g_m_m_unibanditos_01', coords = vector3(-594.0, 1504.0, 140.0), heading = 270.0, weapon = 'WEAPON_RIFLE_BOLTACTION' },
            },
            loot = {
                coords = vector3(-600.0, 1500.0, 140.0),
                label = 'Outlaw camp stash',
                table = {
                    { name = 'worn_rifle', chance = 1.0, amount = 1, condition = { 20, 45 } },
                    { name = 'small_safe', chance = 1.0, amount = 1 },
                    { name = 'gun_parts', chance = 0.8, amount = { 2, 3 } },
                },
            },
        },
        -- Big Valley (outlaws = Mountain Gang)
        big_valley_t1_01 = {
            id = 'big_valley_t1_01',
            territory = 'big_valley_t1_camp',
            name = 'Creekside camp',
            verified = false,
            enabled = false,
            activationRadius = 45.0,
            respawnMinutes = 10,
            peds = {
                { model = 'g_m_m_unibanditos_01', coords = vector3(-1653.0, -897.0, 90.0), heading = 90.0,  weapon = 'WEAPON_REVOLVER_CATTLEMAN' },
                { model = 'g_m_m_unibanditos_01', coords = vector3(-1646.0, -903.0, 90.0), heading = 200.0, weapon = 'WEAPON_REPEATER_CARBINE' },
                { model = 'g_m_m_unibanditos_01', coords = vector3(-1655.0, -905.0, 90.0), heading = 45.0,  weapon = 'WEAPON_REVOLVER_CATTLEMAN' },
                { model = 'g_m_m_unibanditos_01', coords = vector3(-1644.0, -896.0, 90.0), heading = 270.0, weapon = 'WEAPON_RIFLE_BOLTACTION' },
            },
            loot = {
                coords = vector3(-1650.0, -900.0, 90.0),
                label = 'Outlaw camp stash',
                table = {
                    { name = 'worn_rifle', chance = 1.0, amount = 1, condition = { 20, 45 } },
                    { name = 'small_safe', chance = 1.0, amount = 1 },
                    { name = 'gun_parts', chance = 0.8, amount = { 2, 3 } },
                },
            },
        },
        big_valley_t1_02 = {
            id = 'big_valley_t1_02',
            territory = 'big_valley_t1_camp_2',
            name = 'Hillside camp',
            verified = false,
            enabled = false,
            activationRadius = 45.0,
            respawnMinutes = 10,
            peds = {
                { model = 'g_m_m_unibanditos_01', coords = vector3(-1253.0, -947.0, 85.0), heading = 90.0,  weapon = 'WEAPON_REVOLVER_CATTLEMAN' },
                { model = 'g_m_m_unibanditos_01', coords = vector3(-1246.0, -953.0, 85.0), heading = 200.0, weapon = 'WEAPON_REPEATER_CARBINE' },
                { model = 'g_m_m_unibanditos_01', coords = vector3(-1255.0, -955.0, 85.0), heading = 45.0,  weapon = 'WEAPON_REVOLVER_CATTLEMAN' },
                { model = 'g_m_m_unibanditos_01', coords = vector3(-1244.0, -946.0, 85.0), heading = 270.0, weapon = 'WEAPON_RIFLE_BOLTACTION' },
            },
            loot = {
                coords = vector3(-1250.0, -950.0, 85.0),
                label = 'Outlaw camp stash',
                table = {
                    { name = 'worn_rifle', chance = 1.0, amount = 1, condition = { 20, 45 } },
                    { name = 'small_safe', chance = 1.0, amount = 1 },
                    { name = 'gun_parts', chance = 0.8, amount = { 2, 3 } },
                },
            },
        },
        big_valley_t2_01 = {
            id = 'big_valley_t2_01',
            territory = 'big_valley_t2_camp',
            name = 'West Ridge camp',
            verified = false,
            enabled = false,
            activationRadius = 45.0,
            respawnMinutes = 10,
            peds = {
                { model = 'g_m_m_unibanditos_01', coords = vector3(-2103.0, -777.0, 95.0), heading = 90.0,  weapon = 'WEAPON_REVOLVER_CATTLEMAN' },
                { model = 'g_m_m_unibanditos_01', coords = vector3(-2096.0, -783.0, 95.0), heading = 200.0, weapon = 'WEAPON_REPEATER_CARBINE' },
                { model = 'g_m_m_unibanditos_01', coords = vector3(-2105.0, -785.0, 95.0), heading = 45.0,  weapon = 'WEAPON_REVOLVER_CATTLEMAN' },
                { model = 'g_m_m_unibanditos_01', coords = vector3(-2094.0, -776.0, 95.0), heading = 270.0, weapon = 'WEAPON_RIFLE_BOLTACTION' },
            },
            loot = {
                coords = vector3(-2100.0, -780.0, 95.0),
                label = 'Outlaw camp stash',
                table = {
                    { name = 'worn_rifle', chance = 1.0, amount = 1, condition = { 20, 45 } },
                    { name = 'small_safe', chance = 1.0, amount = 1 },
                    { name = 'gun_parts', chance = 0.8, amount = { 2, 3 } },
                },
            },
        },
        -- Tall Trees (outlaws = Mountain Gang)
        tall_trees_t1_01 = {
            id = 'tall_trees_t1_01',
            territory = 'tall_trees_t1_camp',
            name = 'Pine Flats camp',
            verified = false,
            enabled = false,
            activationRadius = 45.0,
            respawnMinutes = 10,
            peds = {
                { model = 'g_m_m_unibanditos_01', coords = vector3(-2153.0, -1647.0, 130.0), heading = 90.0,  weapon = 'WEAPON_REVOLVER_CATTLEMAN' },
                { model = 'g_m_m_unibanditos_01', coords = vector3(-2146.0, -1653.0, 130.0), heading = 200.0, weapon = 'WEAPON_REPEATER_CARBINE' },
                { model = 'g_m_m_unibanditos_01', coords = vector3(-2155.0, -1655.0, 130.0), heading = 45.0,  weapon = 'WEAPON_REVOLVER_CATTLEMAN' },
                { model = 'g_m_m_unibanditos_01', coords = vector3(-2144.0, -1646.0, 130.0), heading = 270.0, weapon = 'WEAPON_RIFLE_BOLTACTION' },
            },
            loot = {
                coords = vector3(-2150.0, -1650.0, 130.0),
                label = 'Outlaw camp stash',
                table = {
                    { name = 'worn_rifle', chance = 1.0, amount = 1, condition = { 20, 45 } },
                    { name = 'small_safe', chance = 1.0, amount = 1 },
                    { name = 'gun_parts', chance = 0.8, amount = { 2, 3 } },
                },
            },
        },
        tall_trees_t1_02 = {
            id = 'tall_trees_t1_02',
            territory = 'tall_trees_t1_camp_2',
            name = 'West Hollow camp',
            verified = false,
            enabled = false,
            activationRadius = 45.0,
            respawnMinutes = 10,
            peds = {
                { model = 'g_m_m_unibanditos_01', coords = vector3(-2003.0, -1847.0, 130.0), heading = 90.0,  weapon = 'WEAPON_REVOLVER_CATTLEMAN' },
                { model = 'g_m_m_unibanditos_01', coords = vector3(-1996.0, -1853.0, 130.0), heading = 200.0, weapon = 'WEAPON_REPEATER_CARBINE' },
                { model = 'g_m_m_unibanditos_01', coords = vector3(-2005.0, -1855.0, 130.0), heading = 45.0,  weapon = 'WEAPON_REVOLVER_CATTLEMAN' },
                { model = 'g_m_m_unibanditos_01', coords = vector3(-1994.0, -1846.0, 130.0), heading = 270.0, weapon = 'WEAPON_RIFLE_BOLTACTION' },
            },
            loot = {
                coords = vector3(-2000.0, -1850.0, 130.0),
                label = 'Outlaw camp stash',
                table = {
                    { name = 'worn_rifle', chance = 1.0, amount = 1, condition = { 20, 45 } },
                    { name = 'small_safe', chance = 1.0, amount = 1 },
                    { name = 'gun_parts', chance = 0.8, amount = { 2, 3 } },
                },
            },
        },
        tall_trees_t2_01 = {
            id = 'tall_trees_t2_01',
            territory = 'tall_trees_t2_camp',
            name = 'East Timber camp',
            verified = false,
            enabled = false,
            activationRadius = 45.0,
            respawnMinutes = 10,
            peds = {
                { model = 'g_m_m_unibanditos_01', coords = vector3(-2253.0, -1397.0, 140.0), heading = 90.0,  weapon = 'WEAPON_REVOLVER_CATTLEMAN' },
                { model = 'g_m_m_unibanditos_01', coords = vector3(-2246.0, -1403.0, 140.0), heading = 200.0, weapon = 'WEAPON_REPEATER_CARBINE' },
                { model = 'g_m_m_unibanditos_01', coords = vector3(-2255.0, -1405.0, 140.0), heading = 45.0,  weapon = 'WEAPON_REVOLVER_CATTLEMAN' },
                { model = 'g_m_m_unibanditos_01', coords = vector3(-2244.0, -1396.0, 140.0), heading = 270.0, weapon = 'WEAPON_RIFLE_BOLTACTION' },
            },
            loot = {
                coords = vector3(-2250.0, -1400.0, 140.0),
                label = 'Outlaw camp stash',
                table = {
                    { name = 'worn_rifle', chance = 1.0, amount = 1, condition = { 20, 45 } },
                    { name = 'small_safe', chance = 1.0, amount = 1 },
                    { name = 'gun_parts', chance = 0.8, amount = { 2, 3 } },
                },
            },
        },
        -- Hennigan's Stead (desert_gang = Desert Gang)
        hennigans_stead_t1_01 = {
            id = 'hennigans_stead_t1_01',
            territory = 'hennigans_stead_t1_camp',
            name = 'Tableland camp',
            verified = false,
            enabled = false,
            activationRadius = 45.0,
            respawnMinutes = 10,
            peds = {
                { model = 'g_m_m_unibanditos_01', coords = vector3(-1903.0, -1947.0, 60.0), heading = 90.0,  weapon = 'WEAPON_REVOLVER_CATTLEMAN' },
                { model = 'g_m_m_unibanditos_01', coords = vector3(-1896.0, -1953.0, 60.0), heading = 200.0, weapon = 'WEAPON_REPEATER_CARBINE' },
                { model = 'g_m_m_unibanditos_01', coords = vector3(-1905.0, -1955.0, 60.0), heading = 45.0,  weapon = 'WEAPON_REVOLVER_CATTLEMAN' },
                { model = 'g_m_m_unibanditos_01', coords = vector3(-1894.0, -1946.0, 60.0), heading = 270.0, weapon = 'WEAPON_RIFLE_BOLTACTION' },
            },
            loot = {
                coords = vector3(-1900.0, -1950.0, 60.0),
                label = 'Outlaw camp stash',
                table = {
                    { name = 'worn_rifle', chance = 1.0, amount = 1, condition = { 20, 45 } },
                    { name = 'small_safe', chance = 1.0, amount = 1 },
                    { name = 'gun_parts', chance = 0.8, amount = { 2, 3 } },
                },
            },
        },
        hennigans_stead_t1_02 = {
            id = 'hennigans_stead_t1_02',
            territory = 'hennigans_stead_t1_camp_2',
            name = 'West Mesa camp',
            verified = false,
            enabled = false,
            activationRadius = 45.0,
            respawnMinutes = 10,
            peds = {
                { model = 'g_m_m_unibanditos_01', coords = vector3(-2403.0, -2247.0, 70.0), heading = 90.0,  weapon = 'WEAPON_REVOLVER_CATTLEMAN' },
                { model = 'g_m_m_unibanditos_01', coords = vector3(-2396.0, -2253.0, 70.0), heading = 200.0, weapon = 'WEAPON_REPEATER_CARBINE' },
                { model = 'g_m_m_unibanditos_01', coords = vector3(-2405.0, -2255.0, 70.0), heading = 45.0,  weapon = 'WEAPON_REVOLVER_CATTLEMAN' },
                { model = 'g_m_m_unibanditos_01', coords = vector3(-2394.0, -2246.0, 70.0), heading = 270.0, weapon = 'WEAPON_RIFLE_BOLTACTION' },
            },
            loot = {
                coords = vector3(-2400.0, -2250.0, 70.0),
                label = 'Outlaw camp stash',
                table = {
                    { name = 'worn_rifle', chance = 1.0, amount = 1, condition = { 20, 45 } },
                    { name = 'small_safe', chance = 1.0, amount = 1 },
                    { name = 'gun_parts', chance = 0.8, amount = { 2, 3 } },
                },
            },
        },
        hennigans_stead_t2_01 = {
            id = 'hennigans_stead_t2_01',
            territory = 'hennigans_stead_t2_camp',
            name = 'South Crossing camp',
            verified = false,
            enabled = false,
            activationRadius = 45.0,
            respawnMinutes = 10,
            peds = {
                { model = 'g_m_m_unibanditos_01', coords = vector3(-1653.0, -2597.0, 55.0), heading = 90.0,  weapon = 'WEAPON_REVOLVER_CATTLEMAN' },
                { model = 'g_m_m_unibanditos_01', coords = vector3(-1646.0, -2603.0, 55.0), heading = 200.0, weapon = 'WEAPON_REPEATER_CARBINE' },
                { model = 'g_m_m_unibanditos_01', coords = vector3(-1655.0, -2605.0, 55.0), heading = 45.0,  weapon = 'WEAPON_REVOLVER_CATTLEMAN' },
                { model = 'g_m_m_unibanditos_01', coords = vector3(-1644.0, -2596.0, 55.0), heading = 270.0, weapon = 'WEAPON_RIFLE_BOLTACTION' },
            },
            loot = {
                coords = vector3(-1650.0, -2600.0, 55.0),
                label = 'Outlaw camp stash',
                table = {
                    { name = 'worn_rifle', chance = 1.0, amount = 1, condition = { 20, 45 } },
                    { name = 'small_safe', chance = 1.0, amount = 1 },
                    { name = 'gun_parts', chance = 0.8, amount = { 2, 3 } },
                },
            },
        },
        -- Cholla Springs (desert_gang = Desert Gang)
        cholla_springs_t1_01 = {
            id = 'cholla_springs_t1_01',
            territory = 'cholla_springs_t1_camp',
            name = 'Alkali Flat camp',
            verified = false,
            enabled = false,
            activationRadius = 45.0,
            respawnMinutes = 10,
            peds = {
                { model = 'g_m_m_unibanditos_01', coords = vector3(-3353.0, -2477.0, 75.0), heading = 90.0,  weapon = 'WEAPON_REVOLVER_CATTLEMAN' },
                { model = 'g_m_m_unibanditos_01', coords = vector3(-3346.0, -2483.0, 75.0), heading = 200.0, weapon = 'WEAPON_REPEATER_CARBINE' },
                { model = 'g_m_m_unibanditos_01', coords = vector3(-3355.0, -2485.0, 75.0), heading = 45.0,  weapon = 'WEAPON_REVOLVER_CATTLEMAN' },
                { model = 'g_m_m_unibanditos_01', coords = vector3(-3344.0, -2476.0, 75.0), heading = 270.0, weapon = 'WEAPON_RIFLE_BOLTACTION' },
            },
            loot = {
                coords = vector3(-3350.0, -2480.0, 75.0),
                label = 'Outlaw camp stash',
                table = {
                    { name = 'worn_rifle', chance = 1.0, amount = 1, condition = { 20, 45 } },
                    { name = 'small_safe', chance = 1.0, amount = 1 },
                    { name = 'gun_parts', chance = 0.8, amount = { 2, 3 } },
                },
            },
        },
        cholla_springs_t1_02 = {
            id = 'cholla_springs_t1_02',
            territory = 'cholla_springs_t1_camp_2',
            name = 'Prickly Pear camp',
            verified = false,
            enabled = false,
            activationRadius = 45.0,
            respawnMinutes = 10,
            peds = {
                { model = 'g_m_m_unibanditos_01', coords = vector3(-3903.0, -2397.0, 80.0), heading = 90.0,  weapon = 'WEAPON_REVOLVER_CATTLEMAN' },
                { model = 'g_m_m_unibanditos_01', coords = vector3(-3896.0, -2403.0, 80.0), heading = 200.0, weapon = 'WEAPON_REPEATER_CARBINE' },
                { model = 'g_m_m_unibanditos_01', coords = vector3(-3905.0, -2405.0, 80.0), heading = 45.0,  weapon = 'WEAPON_REVOLVER_CATTLEMAN' },
                { model = 'g_m_m_unibanditos_01', coords = vector3(-3894.0, -2396.0, 80.0), heading = 270.0, weapon = 'WEAPON_RIFLE_BOLTACTION' },
            },
            loot = {
                coords = vector3(-3900.0, -2400.0, 80.0),
                label = 'Outlaw camp stash',
                table = {
                    { name = 'worn_rifle', chance = 1.0, amount = 1, condition = { 20, 45 } },
                    { name = 'small_safe', chance = 1.0, amount = 1 },
                    { name = 'gun_parts', chance = 0.8, amount = { 2, 3 } },
                },
            },
        },
        cholla_springs_t2_01 = {
            id = 'cholla_springs_t2_01',
            territory = 'cholla_springs_t2_camp',
            name = 'Sagebrush camp',
            verified = false,
            enabled = false,
            activationRadius = 45.0,
            respawnMinutes = 10,
            peds = {
                { model = 'g_m_m_unibanditos_01', coords = vector3(-4203.0, -2597.0, 80.0), heading = 90.0,  weapon = 'WEAPON_REVOLVER_CATTLEMAN' },
                { model = 'g_m_m_unibanditos_01', coords = vector3(-4196.0, -2603.0, 80.0), heading = 200.0, weapon = 'WEAPON_REPEATER_CARBINE' },
                { model = 'g_m_m_unibanditos_01', coords = vector3(-4205.0, -2605.0, 80.0), heading = 45.0,  weapon = 'WEAPON_REVOLVER_CATTLEMAN' },
                { model = 'g_m_m_unibanditos_01', coords = vector3(-4194.0, -2596.0, 80.0), heading = 270.0, weapon = 'WEAPON_RIFLE_BOLTACTION' },
            },
            loot = {
                coords = vector3(-4200.0, -2600.0, 80.0),
                label = 'Outlaw camp stash',
                table = {
                    { name = 'worn_rifle', chance = 1.0, amount = 1, condition = { 20, 45 } },
                    { name = 'small_safe', chance = 1.0, amount = 1 },
                    { name = 'gun_parts', chance = 0.8, amount = { 2, 3 } },
                },
            },
        },
        -- Gaptooth Ridge (desert_gang = Desert Gang)
        gaptooth_ridge_t1_01 = {
            id = 'gaptooth_ridge_t1_01',
            territory = 'gaptooth_ridge_t1_camp',
            name = 'Gaptooth camp',
            verified = false,
            enabled = false,
            activationRadius = 45.0,
            respawnMinutes = 10,
            peds = {
                { model = 'g_m_m_unibanditos_01', coords = vector3(-5103.0, -2597.0, 90.0), heading = 90.0,  weapon = 'WEAPON_REVOLVER_CATTLEMAN' },
                { model = 'g_m_m_unibanditos_01', coords = vector3(-5096.0, -2603.0, 90.0), heading = 200.0, weapon = 'WEAPON_REPEATER_CARBINE' },
                { model = 'g_m_m_unibanditos_01', coords = vector3(-5105.0, -2605.0, 90.0), heading = 45.0,  weapon = 'WEAPON_REVOLVER_CATTLEMAN' },
                { model = 'g_m_m_unibanditos_01', coords = vector3(-5094.0, -2596.0, 90.0), heading = 270.0, weapon = 'WEAPON_RIFLE_BOLTACTION' },
            },
            loot = {
                coords = vector3(-5100.0, -2600.0, 90.0),
                label = 'Outlaw camp stash',
                table = {
                    { name = 'worn_rifle', chance = 1.0, amount = 1, condition = { 20, 45 } },
                    { name = 'small_safe', chance = 1.0, amount = 1 },
                    { name = 'gun_parts', chance = 0.8, amount = { 2, 3 } },
                },
            },
        },
        gaptooth_ridge_t1_02 = {
            id = 'gaptooth_ridge_t1_02',
            territory = 'gaptooth_ridge_t1_camp_2',
            name = 'West Draw camp',
            verified = false,
            enabled = false,
            activationRadius = 45.0,
            respawnMinutes = 10,
            peds = {
                { model = 'g_m_m_unibanditos_01', coords = vector3(-5803.0, -2797.0, 85.0), heading = 90.0,  weapon = 'WEAPON_REVOLVER_CATTLEMAN' },
                { model = 'g_m_m_unibanditos_01', coords = vector3(-5796.0, -2803.0, 85.0), heading = 200.0, weapon = 'WEAPON_REPEATER_CARBINE' },
                { model = 'g_m_m_unibanditos_01', coords = vector3(-5805.0, -2805.0, 85.0), heading = 45.0,  weapon = 'WEAPON_REVOLVER_CATTLEMAN' },
                { model = 'g_m_m_unibanditos_01', coords = vector3(-5794.0, -2796.0, 85.0), heading = 270.0, weapon = 'WEAPON_RIFLE_BOLTACTION' },
            },
            loot = {
                coords = vector3(-5800.0, -2800.0, 85.0),
                label = 'Outlaw camp stash',
                table = {
                    { name = 'worn_rifle', chance = 1.0, amount = 1, condition = { 20, 45 } },
                    { name = 'small_safe', chance = 1.0, amount = 1 },
                    { name = 'gun_parts', chance = 0.8, amount = { 2, 3 } },
                },
            },
        },
        gaptooth_ridge_t2_01 = {
            id = 'gaptooth_ridge_t2_01',
            territory = 'gaptooth_ridge_t2_camp',
            name = 'South Canyon camp',
            verified = false,
            enabled = false,
            activationRadius = 45.0,
            respawnMinutes = 10,
            peds = {
                { model = 'g_m_m_unibanditos_01', coords = vector3(-5403.0, -3197.0, 90.0), heading = 90.0,  weapon = 'WEAPON_REVOLVER_CATTLEMAN' },
                { model = 'g_m_m_unibanditos_01', coords = vector3(-5396.0, -3203.0, 90.0), heading = 200.0, weapon = 'WEAPON_REPEATER_CARBINE' },
                { model = 'g_m_m_unibanditos_01', coords = vector3(-5405.0, -3205.0, 90.0), heading = 45.0,  weapon = 'WEAPON_REVOLVER_CATTLEMAN' },
                { model = 'g_m_m_unibanditos_01', coords = vector3(-5394.0, -3196.0, 90.0), heading = 270.0, weapon = 'WEAPON_RIFLE_BOLTACTION' },
            },
            loot = {
                coords = vector3(-5400.0, -3200.0, 90.0),
                label = 'Outlaw camp stash',
                table = {
                    { name = 'worn_rifle', chance = 1.0, amount = 1, condition = { 20, 45 } },
                    { name = 'small_safe', chance = 1.0, amount = 1 },
                    { name = 'gun_parts', chance = 0.8, amount = { 2, 3 } },
                },
            },
        },
        -- Rio Bravo (desert_gang = Desert Gang)
        rio_bravo_t1_01 = {
            id = 'rio_bravo_t1_01',
            territory = 'rio_bravo_t1_camp',
            name = 'Rio camp',
            verified = false,
            enabled = false,
            activationRadius = 45.0,
            respawnMinutes = 10,
            peds = {
                { model = 'g_m_m_unibanditos_01', coords = vector3(-1803.0, -3197.0, 55.0), heading = 90.0,  weapon = 'WEAPON_REVOLVER_CATTLEMAN' },
                { model = 'g_m_m_unibanditos_01', coords = vector3(-1796.0, -3203.0, 55.0), heading = 200.0, weapon = 'WEAPON_REPEATER_CARBINE' },
                { model = 'g_m_m_unibanditos_01', coords = vector3(-1805.0, -3205.0, 55.0), heading = 45.0,  weapon = 'WEAPON_REVOLVER_CATTLEMAN' },
                { model = 'g_m_m_unibanditos_01', coords = vector3(-1794.0, -3196.0, 55.0), heading = 270.0, weapon = 'WEAPON_RIFLE_BOLTACTION' },
            },
            loot = {
                coords = vector3(-1800.0, -3200.0, 55.0),
                label = 'Outlaw camp stash',
                table = {
                    { name = 'worn_rifle', chance = 1.0, amount = 1, condition = { 20, 45 } },
                    { name = 'small_safe', chance = 1.0, amount = 1 },
                    { name = 'gun_parts', chance = 0.8, amount = { 2, 3 } },
                },
            },
        },
        rio_bravo_t1_02 = {
            id = 'rio_bravo_t1_02',
            territory = 'rio_bravo_t1_camp_2',
            name = 'Mesa camp',
            verified = false,
            enabled = false,
            activationRadius = 45.0,
            respawnMinutes = 10,
            peds = {
                { model = 'g_m_m_unibanditos_01', coords = vector3(-1453.0, -2697.0, 60.0), heading = 90.0,  weapon = 'WEAPON_REVOLVER_CATTLEMAN' },
                { model = 'g_m_m_unibanditos_01', coords = vector3(-1446.0, -2703.0, 60.0), heading = 200.0, weapon = 'WEAPON_REPEATER_CARBINE' },
                { model = 'g_m_m_unibanditos_01', coords = vector3(-1455.0, -2705.0, 60.0), heading = 45.0,  weapon = 'WEAPON_REVOLVER_CATTLEMAN' },
                { model = 'g_m_m_unibanditos_01', coords = vector3(-1444.0, -2696.0, 60.0), heading = 270.0, weapon = 'WEAPON_RIFLE_BOLTACTION' },
            },
            loot = {
                coords = vector3(-1450.0, -2700.0, 60.0),
                label = 'Outlaw camp stash',
                table = {
                    { name = 'worn_rifle', chance = 1.0, amount = 1, condition = { 20, 45 } },
                    { name = 'small_safe', chance = 1.0, amount = 1 },
                    { name = 'gun_parts', chance = 0.8, amount = { 2, 3 } },
                },
            },
        },
        rio_bravo_t2_01 = {
            id = 'rio_bravo_t2_01',
            territory = 'rio_bravo_t2_camp',
            name = 'Bend camp',
            verified = false,
            enabled = false,
            activationRadius = 45.0,
            respawnMinutes = 10,
            peds = {
                { model = 'g_m_m_unibanditos_01', coords = vector3(-2053.0, -3147.0, 55.0), heading = 90.0,  weapon = 'WEAPON_REVOLVER_CATTLEMAN' },
                { model = 'g_m_m_unibanditos_01', coords = vector3(-2046.0, -3153.0, 55.0), heading = 200.0, weapon = 'WEAPON_REPEATER_CARBINE' },
                { model = 'g_m_m_unibanditos_01', coords = vector3(-2055.0, -3155.0, 55.0), heading = 45.0,  weapon = 'WEAPON_REVOLVER_CATTLEMAN' },
                { model = 'g_m_m_unibanditos_01', coords = vector3(-2044.0, -3146.0, 55.0), heading = 270.0, weapon = 'WEAPON_RIFLE_BOLTACTION' },
            },
            loot = {
                coords = vector3(-2050.0, -3150.0, 55.0),
                label = 'Outlaw camp stash',
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
    -- Optional loot override by OWNING faction x tier (A-life camp ownership, plan a-life-01; world-02 block E fills
    -- the 8x3 data). FhZonesConfig.camps is @world's data (do not add keys there); this top-level map is keyed by
    -- fh_core faction id (regions.factions, alias excluded: rhodes_law resolves to lawmen via getFaction), then tier
    -- T1/T2/T3 (regions.TIERS). rules.pickLootTable falls back to camp.loot.table when the owner/tier has no entry or
    -- fh_alife is absent; a flat [faction] -> table (the v1 shape) still resolves for backward compatibility.
    lootByFaction = {
        -- lawmen (kind law): ammunition + money + field medical
        lawmen = {
            T1 = {
                { name = 'ammo_box_revolver', chance = 0.8, amount = 1 },
                { name = 'ammo_box_rifle',    chance = 0.5, amount = 1 },
                { name = 'bandage',           chance = 0.7, amount = { 1, 2 } },
                { name = 'dollar',            chance = 0.9, amount = { 1, 3 } },
                { name = 'fieldbandage',      chance = 0.4, amount = 1 },
            },
            T2 = {
                { name = 'ammo_box_revolver', chance = 0.9, amount = { 1, 2 } },
                { name = 'ammo_box_rifle',    chance = 0.6, amount = 1 },
                { name = 'ammo_box_repeater', chance = 0.5, amount = 1 },
                { name = 'dollar',            chance = 1.0, amount = { 3, 8 } },
                { name = 'tonic_healing',     chance = 0.4, amount = 1 },
                { name = 'fieldbandage',      chance = 0.5, amount = { 1, 2 } },
            },
            T3 = {
                { name = 'money_clip',                chance = 0.5, amount = 1 },
                { name = 'dollar',                    chance = 1.0, amount = { 6, 12 } },
                { name = 'ammo_box_revolver_express', chance = 0.5, amount = 1 },
                { name = 'ammo_box_rifle_express',    chance = 0.4, amount = 1 },
                { name = 'ammo_box_shotgun',          chance = 0.4, amount = 1 },
                { name = 'tonic_healing',             chance = 0.5, amount = { 1, 2 } },
                { name = 'firstaid',                  chance = 0.3, amount = 1 },
            },
        },
        -- bounty_hunters (neutral): ammunition + money + tracking gear
        bounty_hunters = {
            T1 = {
                { name = 'ammo_box_revolver', chance = 0.7, amount = 1 },
                { name = 'ammo_box_rifle',    chance = 0.5, amount = 1 },
                { name = 'dollar',            chance = 0.9, amount = { 2, 4 } },
                { name = 'weapon_gun_oil',    chance = 0.5, amount = 1 },
                { name = 'bandage',           chance = 0.5, amount = 1 },
            },
            T2 = {
                { name = 'ammo_box_repeater', chance = 0.6, amount = { 1, 2 } },
                { name = 'ammo_box_rifle',    chance = 0.6, amount = 1 },
                { name = 'ammo_box_revolver', chance = 0.8, amount = { 1, 2 } },
                { name = 'dollar',            chance = 1.0, amount = { 4, 8 } },
                { name = 'tonic_stamina',     chance = 0.4, amount = 1 },
                { name = 'weapon_repair_kit', chance = 0.4, amount = 1 },
            },
            T3 = {
                { name = 'money_clip',                chance = 0.6, amount = 1 },
                { name = 'dollar',                    chance = 1.0, amount = { 8, 15 } },
                { name = 'ammo_box_revolver_express', chance = 0.5, amount = 1 },
                { name = 'ammo_box_rifle_express',    chance = 0.4, amount = 1 },
                { name = 'weapon_kit_binoculars',     chance = 0.4, amount = 1 },
                { name = 'tonic_energy',              chance = 0.5, amount = 1 },
            },
        },
        -- traders (neutral): goods + money + tools
        traders = {
            T1 = {
                { name = 'dollar',        chance = 0.9, amount = { 2, 5 } },
                { name = 'canned_beans',  chance = 0.6, amount = { 1, 2 } },
                { name = 'coffee',        chance = 0.5, amount = 1 },
                { name = 'flour_wheat',   chance = 0.4, amount = { 1, 2 } },
                { name = 'sugar',         chance = 0.4, amount = 1 },
                { name = 'resource_rope', chance = 0.4, amount = 1 },
            },
            T2 = {
                { name = 'dollar',          chance = 1.0, amount = { 5, 10 } },
                { name = 'canned_salmon',   chance = 0.5, amount = { 1, 2 } },
                { name = 'canned_peaches',  chance = 0.5, amount = { 1, 2 } },
                { name = 'coffee_beans',    chance = 0.4, amount = { 1, 2 } },
                { name = 'resource_cloth',  chance = 0.5, amount = { 1, 2 } },
                { name = 'resource_wood',   chance = 0.4, amount = { 1, 2 } },
                { name = 'shovel',          chance = 0.4, amount = 1 },
            },
            T3 = {
                { name = 'money_clip',          chance = 0.5, amount = 1 },
                { name = 'dollar',              chance = 1.0, amount = { 8, 18 } },
                { name = 'canned_apricots',     chance = 0.5, amount = { 1, 2 } },
                { name = 'resource_copper_bar', chance = 0.4, amount = { 1, 2 } },
                { name = 'resource_iron_bar',   chance = 0.4, amount = { 1, 2 } },
                { name = 'axe',                 chance = 0.4, amount = 1 },
                { name = 'oilcan',              chance = 0.3, amount = 1 },
            },
        },
        -- settlers (neutral): goods + tools + money + trail food
        settlers = {
            T1 = {
                { name = 'dollar',       chance = 0.8, amount = { 1, 3 } },
                { name = 'fh_biscuit',   chance = 0.6, amount = { 1, 2 } },
                { name = 'fh_jerky',     chance = 0.5, amount = { 1, 2 } },
                { name = 'fh_canteen',   chance = 0.4, amount = 1 },
                { name = 'bread',        chance = 0.5, amount = { 1, 2 } },
                { name = 'canned_beans', chance = 0.4, amount = 1 },
            },
            T2 = {
                { name = 'dollar',         chance = 0.9, amount = { 3, 7 } },
                { name = 'fh_stew',        chance = 0.5, amount = { 1, 2 } },
                { name = 'coffee',         chance = 0.4, amount = { 1, 2 } },
                { name = 'resource_wood',  chance = 0.4, amount = { 1, 2 } },
                { name = 'resource_cloth', chance = 0.4, amount = { 1, 2 } },
                { name = 'bucket',         chance = 0.4, amount = 1 },
                { name = 'shovel',         chance = 0.4, amount = 1 },
            },
            T3 = {
                { name = 'dollar',          chance = 1.0, amount = { 6, 12 } },
                { name = 'money_clip',      chance = 0.3, amount = 1 },
                { name = 'bedroll',         chance = 0.4, amount = 1 },
                { name = 'resource_iron_bar', chance = 0.3, amount = { 1, 2 } },
                { name = 'mortarpestle',    chance = 0.3, amount = 1 },
                { name = 'pickaxe',         chance = 0.3, amount = 1 },
                { name = 'canned_salmon',   chance = 0.4, amount = { 1, 2 } },
            },
        },
        -- rail_mining (neutral): goods + mining/tool supplies + money
        rail_mining = {
            T1 = {
                { name = 'dollar',          chance = 0.8, amount = { 2, 4 } },
                { name = 'canned_beans',    chance = 0.5, amount = { 1, 2 } },
                { name = 'coffee',          chance = 0.4, amount = 1 },
                { name = 'resource_coal',   chance = 0.5, amount = { 1, 2 } },
                { name = 'resource_iron_bar', chance = 0.3, amount = 1 },
                { name = 'pickaxe',         chance = 0.4, amount = 1 },
            },
            T2 = {
                { name = 'dollar',          chance = 0.9, amount = { 4, 9 } },
                { name = 'resource_wood',   chance = 0.4, amount = { 1, 2 } },
                { name = 'resource_coal',   chance = 0.5, amount = { 1, 2 } },
                { name = 'resource_iron_bar', chance = 0.4, amount = { 1, 2 } },
                { name = 'resource_rope',   chance = 0.4, amount = { 1, 2 } },
                { name = 'shovel',          chance = 0.4, amount = 1 },
                { name = 'oilcan',          chance = 0.3, amount = 1 },
            },
            T3 = {
                { name = 'money_clip',        chance = 0.4, amount = 1 },
                { name = 'dollar',            chance = 1.0, amount = { 6, 14 } },
                { name = 'resource_copper_bar', chance = 0.4, amount = { 1, 2 } },
                { name = 'resource_gunpowder', chance = 0.4, amount = { 1, 2 } },
                { name = 'resource_cloth',    chance = 0.3, amount = { 1, 2 } },
                { name = 'axe',               chance = 0.3, amount = 1 },
                { name = 'tool_goldpan',      chance = 0.3, amount = 1 },
            },
        },
        -- outlaws (Mountain Gang, outlaw): contraband / stolen goods
        outlaws = {
            T1 = {
                { name = 'worn_rifle',     chance = 0.6, amount = 1, condition = { 20, 45 } },
                { name = 'small_safe',     chance = 0.5, amount = 1 },
                { name = 'gun_parts',      chance = 0.7, amount = { 2, 3 } },
                { name = 'cigarettes',     chance = 0.6, amount = { 1, 2 } },
                { name = 'chewingtobacco', chance = 0.5, amount = 1 },
                { name = 'bandana',        chance = 0.4, amount = 1 },
            },
            T2 = {
                { name = 'worn_rifle',                chance = 0.7, amount = 1, condition = { 20, 45 } },
                { name = 'small_safe',                chance = 0.6, amount = 1 },
                { name = 'gun_parts',                 chance = 0.8, amount = { 2, 4 } },
                { name = 'money_clip',                chance = 0.5, amount = 1 },
                { name = 'moonshine',                 chance = 0.5, amount = 1 },
                { name = 'weapon_revolver_cattleman', chance = 0.4, amount = 1, condition = { 25, 50 } },
                { name = 'tool_lockpick',             chance = 0.4, amount = 1 },
            },
            T3 = {
                { name = 'small_safe',               chance = 0.7, amount = 1 },
                { name = 'money_clip',               chance = 0.6, amount = 1 },
                { name = 'weapon_repeater_carbine',  chance = 0.4, amount = 1, condition = { 30, 60 } },
                { name = 'moonshine',                chance = 0.6, amount = { 1, 2 } },
                { name = 'resource_gold_nugget',     chance = 0.5, amount = { 1, 2 } },
                { name = 'blood_money_clip',         chance = 0.5, amount = 1 },
                { name = 'cigar',                    chance = 0.4, amount = 1 },
                { name = 'weapon_gun_oil',           chance = 0.4, amount = 1 },
            },
        },
        -- raiders (Swamp Gang, outlaw): contraband / stolen goods
        raiders = {
            T1 = {
                { name = 'worn_rifle',     chance = 0.6, amount = 1, condition = { 20, 45 } },
                { name = 'small_safe',     chance = 0.5, amount = 1 },
                { name = 'gun_parts',      chance = 0.7, amount = { 2, 3 } },
                { name = 'pipetobacco',    chance = 0.5, amount = 1 },
                { name = 'cigarettes',     chance = 0.5, amount = 1 },
                { name = 'bandana',        chance = 0.4, amount = 1 },
            },
            T2 = {
                { name = 'worn_rifle',                chance = 0.7, amount = 1, condition = { 20, 45 } },
                { name = 'small_safe',                chance = 0.6, amount = 1 },
                { name = 'gun_parts',                 chance = 0.8, amount = { 2, 4 } },
                { name = 'money_clip',                chance = 0.5, amount = 1 },
                { name = 'moonshine',                 chance = 0.5, amount = 1 },
                { name = 'weapon_revolver_cattleman', chance = 0.4, amount = 1, condition = { 25, 50 } },
                { name = 'tool_lockpick',             chance = 0.4, amount = 1 },
            },
            T3 = {
                { name = 'small_safe',                 chance = 0.7, amount = 1 },
                { name = 'money_clip',                 chance = 0.6, amount = 1 },
                { name = 'weapon_shotgun_doublebarrel', chance = 0.4, amount = 1, condition = { 30, 60 } },
                { name = 'moonshine',                  chance = 0.6, amount = { 1, 2 } },
                { name = 'resource_gold_nugget',       chance = 0.5, amount = { 1, 2 } },
                { name = 'blood_money_clip',           chance = 0.5, amount = 1 },
                { name = 'pipe',                       chance = 0.4, amount = 1 },
                { name = 'weapon_repair_kit',          chance = 0.4, amount = 1 },
            },
        },
        -- desert_gang (Desert Gang, outlaw): contraband / stolen goods (own tables)
        desert_gang = {
            T1 = {
                { name = 'worn_rifle',     chance = 0.6, amount = 1, condition = { 20, 45 } },
                { name = 'small_safe',     chance = 0.5, amount = 1 },
                { name = 'gun_parts',      chance = 0.7, amount = { 2, 3 } },
                { name = 'cigarettes',     chance = 0.5, amount = 1 },
                { name = 'chewingtobacco', chance = 0.4, amount = 1 },
                { name = 'bandana',        chance = 0.5, amount = 1 },
            },
            T2 = {
                { name = 'worn_rifle',                chance = 0.7, amount = 1, condition = { 20, 45 } },
                { name = 'small_safe',                chance = 0.6, amount = 1 },
                { name = 'gun_parts',                 chance = 0.8, amount = { 2, 4 } },
                { name = 'money_clip',                chance = 0.5, amount = 1 },
                { name = 'moonshine',                 chance = 0.4, amount = 1 },
                { name = 'weapon_revolver_cattleman', chance = 0.5, amount = 1, condition = { 25, 50 } },
                { name = 'tool_lockpick',             chance = 0.3, amount = 1 },
            },
            T3 = {
                { name = 'small_safe',              chance = 0.7, amount = 1 },
                { name = 'money_clip',              chance = 0.6, amount = 1 },
                { name = 'weapon_rifle_boltaction', chance = 0.4, amount = 1, condition = { 30, 60 } },
                { name = 'resource_gold_nugget',    chance = 0.5, amount = { 1, 2 } },
                { name = 'resource_silver_bar',     chance = 0.5, amount = { 1, 2 } },
                { name = 'blood_dollar',            chance = 0.5, amount = { 2, 4 } },
                { name = 'cigar',                   chance = 0.4, amount = 1 },
                { name = 'weapon_gun_oil',          chance = 0.4, amount = 1 },
            },
        },
    },
}

-- Single source for camp coordinates (world-02 block F, idea-809): fill center/region from FhRegions at load.
-- FhRegions + FhPlaceResolver are loaded before this file in every fxmanifest and spec that reads it.
if FhPlaceResolver and FhRegions then FhPlaceResolver.resolveCamps(FhZonesConfig.camps, FhRegions) end

-- world-02 block E: each camp's loot tier resolves from its territory (FhRegions.territories[].tier), the same single
-- source as center/region — no duplicated tier field. The server reads camp.tier to index lootByFaction[owner][tier].
if FhRegions then
    for _, camp in pairs(FhZonesConfig.camps) do
        local terr = FhRegions.territories[camp.territory]
        if terr and terr.tier then camp.tier = terr.tier end
    end
end

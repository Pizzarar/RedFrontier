-- fh_zones camps (spec L89 L3, M1 L107). ALL coordinates, models and weapons are guesses: TODO-verify-in-game.
-- world-01 (block C): 14 outlaw camps, 3-4 per enabled region, each owned by its region's gang faction via
-- `territory` (fh_core shared/regions.lua territories[].faction). Positions are APPROXIMATE / unverified.
-- WORKAROUND world-01: dup of regions.lua territories, collapse later -- `center` is repeated in
-- regions.lua territories[<territory>].center (A-Life's node-graph source of truth); keep both in sync.
-- world-01 (block D): each camp carries `enabled` (a mirror of regions.lua `enabled` for its `region`); the camp
-- state machine refuses to activate a camp with enabled=false. world_spacing_spec asserts it matches isEnabled.
FhZonesConfig = {
    TickMs = 1000, -- ms between server camp ticks
    AbortCooldownMs = 60000, -- after every ped failed to spawn, the camp can't wake again for this long
    camps = {
        heartlands_t1_01 = {
            id = 'heartlands_t1_01',
            region = 'heartlands',
            territory = 'heartlands_t1_camp',
            name = 'Heartland Bluffs camp',
            verified = false,
            enabled = true,
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
            name = 'Hill Haven camp',
            verified = false,
            enabled = true,
            center = vector3(850.0, -1050.0, 75.0),     -- moved off Rhodes (<200 m floor), TODO-verify-in-game (unverified)
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
            region = 'heartlands',
            territory = 'heartlands_t1_camp_2',
            name = 'Heartland Overflow camp',
            verified = false,
            enabled = true,
            center = vector3(850.0, 850.0, 100.0),     -- TODO-verify-in-game (unverified)
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
            region = 'heartlands',
            territory = 'heartlands_t1_camp_3',
            name = 'Dakota West camp',
            verified = false,
            enabled = true,
            center = vector3(-900.0, 500.0, 105.0),    -- TODO-verify-in-game (unverified)
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
            region = 'heartlands',
            territory = 'heartlands_t2_camp',
            name = 'Dakota South camp',
            verified = false,
            enabled = true,
            center = vector3(600.0, 200.0, 90.0),      -- TODO-verify-in-game (unverified)
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
            region = 'scarlett_meadows',
            territory = 'scarlett_meadows_t1_camp_2',
            name = 'Cedar Bottoms camp',
            verified = false,
            enabled = true,
            center = vector3(1500.0, -1650.0, 70.0),   -- TODO-verify-in-game (unverified)
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
            region = 'scarlett_meadows',
            territory = 'scarlett_meadows_t2_camp',
            name = 'Catfish Bottom camp',
            verified = false,
            enabled = true,
            center = vector3(1700.0, -1750.0, 65.0),   -- TODO-verify-in-game (unverified)
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
            region = 'bayou_nwa',
            territory = 'bayou_nwa_t1_camp',
            name = 'Moss Bog camp',
            verified = false,
            enabled = true,
            center = vector3(2050.0, -1500.0, 25.0),   -- TODO-verify-in-game (unverified)
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
            region = 'bayou_nwa',
            territory = 'bayou_nwa_t1_camp_2',
            name = 'Bayou Railroad camp',
            verified = false,
            enabled = true,
            center = vector3(2400.0, -950.0, 25.0),    -- TODO-verify-in-game (unverified)
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
            region = 'bayou_nwa',
            territory = 'bayou_nwa_t1_camp_3',
            name = 'Lagras Swamp camp',
            verified = false,
            enabled = true,
            center = vector3(2200.0, -1650.0, 25.0),   -- TODO-verify-in-game (unverified)
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
            region = 'bayou_nwa',
            territory = 'bayou_nwa_t2_camp',
            name = 'Cypress Hollow camp',
            verified = false,
            enabled = true,
            center = vector3(2550.0, -1750.0, 20.0),   -- TODO-verify-in-game (unverified)
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
            region = 'great_plains',
            territory = 'great_plains_t1_camp',
            name = 'Bison Bluff camp',
            verified = false,
            enabled = true,
            center = vector3(-1600.0, -1350.0, 40.0),  -- TODO-verify-in-game (unverified)
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
            region = 'great_plains',
            territory = 'great_plains_t1_camp_2',
            name = 'Great Plains North camp',
            verified = false,
            enabled = true,
            center = vector3(-1050.0, -900.0, 45.0),   -- TODO-verify-in-game (unverified)
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
            region = 'great_plains',
            territory = 'great_plains_t2_camp',
            name = 'Great Plains East camp',
            verified = false,
            enabled = true,
            center = vector3(-700.0, -1600.0, 40.0),   -- TODO-verify-in-game (unverified)
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
    },
    -- registered through fh_core's item registry at start (shared/items.lua shape)
    items = {
        worn_rifle = { label = 'Worn Rifle', weight = 4000, size_class = 'bulky', stackable = false, value_base = 25 },
        small_safe = { label = 'Small Safe', weight = 25000, size_class = 'bulky', stackable = false, value_base = 60, illicit = true },
    },
    -- Optional loot override by OWNING faction (A-life camp ownership, plan a-life-01). FhZonesConfig.camps is @world's
    -- data (do not add keys there); this top-level map is keyed by fh_core faction id (regions.factions). Entries are
    -- copies of today's per-camp tables; rules.pickLootTable falls back to camp.loot.table when the owner has no entry
    -- or fh_alife is absent.
    lootByFaction = {
        outlaws = {
            { name = 'worn_rifle', chance = 1.0, amount = 1, condition = { 20, 45 } },
            { name = 'small_safe', chance = 1.0, amount = 1 },
            { name = 'gun_parts', chance = 0.8, amount = { 2, 3 } },
        },
        raiders = {
            { name = 'worn_rifle', chance = 1.0, amount = 1, condition = { 20, 45 } },
            { name = 'small_safe', chance = 1.0, amount = 1 },
            { name = 'gun_parts', chance = 0.8, amount = { 2, 3 } },
        },
    },
}

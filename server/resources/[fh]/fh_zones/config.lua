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

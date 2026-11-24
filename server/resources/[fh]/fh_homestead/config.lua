-- fh_homestead fixed plots (spec L138-139). Coordinates are APPROXIMATE (from fh_core regions) and must be verified
-- in game: stand at the spot, read coords, adjust. One entry per plot; ids are stable (stored in fh_plots).
-- H1: each plot also lists build SLOTS (cabin, fence, stations, trophy wall, chests). Costs/comfort are data only here;
-- the build flow and the money/item debit are H2 (server/build.lua). Slot ids are stable (stored in fh_plot_slots).
local function V(x, y, z) if vector3 then return vector3(x, y, z) end return { x = x, y = y, z = z } end

-- Slot templates per plot class (H9): slotTemplates.claim = every wilderness claim, slotTemplates.town_lot = every town
-- lot (applied by class at the end of this file; a lot never gets the claim's cabin/fence/trophy wall).
-- tiers[n] = what building tier n costs and gives; tier 0 = not built.
--   cost   = { money = <dollars>, items = { <item> = <count> } }   (debit: server/build.lua, items from the plot chest)
--   comfort= comfort points that tier adds (build_rules.totalComfort sums every built tier)
--   unlocks= { chests = {slot ids}, safeRadiusBonus = m, stationType = id, trophyComfort = bool }
--   requires = { [slotId] = minTier } prerequisite slots
--   prop   = fallback (B6a) model + offset from plot center; propVerified (optional) is used when verifiedProps is true.
local slotTemplates = {}
function slotTemplates.claim()
    return {
        cabin = {
            kind = 'cabin', maxTier = 2,
            tiers = {
                [1] = { cost = { money = 150, items = { lumber = 20 } }, comfort = 10, unlocks = { chests = { 'chest_2' } } },
                [2] = { cost = { money = 400, items = { lumber = 40, nails = 20 } }, comfort = 15, unlocks = { chests = { 'chest_3' } } },
            },
            prop = { model = 'p_chest01x', offset = { x = -8.0, y = 0.0, z = 0.0 } }, -- TODO-verify: real cabin prop
        },
        fence = {
            kind = 'fence', maxTier = 1,
            tiers = { [1] = { cost = { money = 100, items = { lumber = 15 } }, comfort = 5, unlocks = { safeRadiusBonus = 10.0 } } },
            prop = { model = 'p_chest01x', offset = { x = 0.0, y = 12.0, z = 0.0 } }, -- TODO-verify
        },
        station_1 = {
            kind = 'station', stationType = 'workbench', maxTier = 1,
            tiers = { [1] = { cost = { money = 60, items = { lumber = 10 } }, comfort = 3, unlocks = { stationType = 'workbench' } } },
            prop = { model = 'p_chest01x', offset = { x = 6.0, y = 4.0, z = 0.0 } }, -- TODO-verify
        },
        station_2 = {
            kind = 'station', stationType = 'campfire', maxTier = 1,
            tiers = { [1] = { cost = { money = 25, items = { lumber = 5 } }, comfort = 3, unlocks = { stationType = 'campfire' } } },
            prop = { model = 'p_chest01x', offset = { x = 6.0, y = -4.0, z = 0.0 } }, -- TODO-verify
        },
        station_3 = {
            kind = 'station', stationType = 'tanning_rack', maxTier = 1,
            tiers = { [1] = { cost = { money = 80, items = { lumber = 12 } }, comfort = 3, unlocks = { stationType = 'tanning_rack' } } },
            prop = { model = 'p_chest01x', offset = { x = 10.0, y = 0.0, z = 0.0 } }, -- TODO-verify
        },
        trophy_wall = {
            kind = 'trophy_wall', maxTier = 1,
            tiers = { [1] = { cost = { money = 120, items = { lumber = 10 } }, comfort = 5, unlocks = { trophyComfort = true } } },
            prop = { model = 'p_chest01x', offset = { x = -8.0, y = 4.0, z = 0.0 } }, -- TODO-verify
        },
        chest_2 = {
            kind = 'chest', maxTier = 1, requires = { cabin = 1 },
            tiers = { [1] = { cost = { money = 40, items = { lumber = 8 } }, comfort = 2, unlocks = {} } },
            prop = { model = 'p_chest01x', offset = { x = -4.0, y = 0.0, z = 0.0 } }, -- TODO-verify
        },
        chest_3 = {
            kind = 'chest', maxTier = 1, requires = { cabin = 2 },
            tiers = { [1] = { cost = { money = 60, items = { lumber = 10 } }, comfort = 2, unlocks = {} } },
            prop = { model = 'p_chest01x', offset = { x = -4.0, y = 4.0, z = 0.0 } }, -- TODO-verify
        },
    }
end
-- Town lot (owner Q3 default): one extra chest and a workbench only. No cabin, so chest_2 has no cabin prerequisite.
function slotTemplates.town_lot()
    local c = slotTemplates.claim()
    c.chest_2.requires = nil
    return { chest_2 = c.chest_2, station_1 = c.station_1 }
end
local function slotTemplate() return slotTemplates.claim() end

FhHomesteadConfig = {
    -- false = every slot uses its fallback prop (B6a model + offset). Flip to true only after propVerified is filled in.
    verifiedProps = false,
    baseSafeRadius = 25.0,
    -- H8 town lots (class = 'town_lot'): /fh_buylot price in dollars (a plot's own `price` overrides it) and the rep
    -- given in the lot's region on purchase (taken back on abandon).
    townLot = { price = 300, rep = 25 },
    -- H4: trophy comfort counts only with the trophy wall built. Cap on total trophy points, and how many trophies
    -- (best-valued first) count per wall tier.
    trophyComfortCap = 20,
    trophyMaxByWallTier = { [1] = 6 },
    -- H2: build materials, registered with exports.fh_core:registerItems from fh_homestead ONLY (full §4.1 defs).
    -- Materials are taken from the plot's main chest (fh:chest:<plot>:1) when a slot is built. Weights in grams.
    buildItems = {
        lumber = { label = 'Lumber', weight = 500, size_class = 'pocket', stackable = true, value_base = 2,
            illicit = false, image = 'resource_wood.png', useable = false, description = 'Sawn planks for building.' },
        nails = { label = 'Nails', weight = 10, size_class = 'pocket', stackable = true, value_base = 1,
            illicit = false, image = 'nails.png', useable = false, description = 'A handful of iron nails.' },
    },
    -- world-01 (block B): real countryside wilderness claims + town lots (data only), replacing the old Valentine
    -- 150 m grid. Coords are RDR2 map positions (near water/timber), all unverified -> the owner walks them in with
    -- /where. Every claim is >=150 m (2D) from every town center in fh_core/shared/regions.lua and from every other
    -- claim (asserted in spec/homestead_sites_spec.lua). class = 'claim' | 'town_lot'; town lots are claimable=false
    -- until @homestead H10 flips them. ids are stable (DB keys): heartlands_01..04 and scarlett_meadows_01..04 are
    -- kept (coords moved only); new ids follow the <region>_NN / <region>_lot_NN pattern.
    plots = {
        -- Heartlands (Valentine) — Dakota River, creeks and the eastern marsh timber.
        heartlands_01 = {
            id = 'heartlands_01',
            name = 'Dakota Bend claim',
            class = 'claim',
            region = 'heartlands',
            verified = false,
            center = V(-500.0, 750.0, 105.0),
            radius = 25.0,
            chest = { coords = V(-496.0, 750.0, 105.0), heading = 90.0, model = 'p_chest01x', label = 'Homestead chest' },
            slots = slotTemplate(),
        },
        heartlands_02 = {
            id = 'heartlands_02',
            name = 'Creekside Pines claim',
            class = 'claim',
            region = 'heartlands',
            verified = false,
            center = V(-620.0, 430.0, 90.0),
            radius = 25.0,
            chest = { coords = V(-616.0, 430.0, 90.0), heading = 90.0, model = 'p_chest01x', label = 'Homestead chest' },
            slots = slotTemplate(),
        },
        heartlands_03 = {
            id = 'heartlands_03',
            name = 'Cattail Marsh claim',
            class = 'claim',
            region = 'heartlands',
            verified = false,
            center = V(1550.0, 700.0, 100.0),
            radius = 25.0,
            chest = { coords = V(1554.0, 700.0, 100.0), heading = 90.0, model = 'p_chest01x', label = 'Homestead chest' },
            slots = slotTemplate(),
        },
        heartlands_04 = {
            id = 'heartlands_04',
            name = 'Larkspur Meadow claim',
            class = 'claim',
            region = 'heartlands',
            verified = false,
            center = V(300.0, 980.0, 110.0),
            radius = 25.0,
            chest = { coords = V(304.0, 980.0, 110.0), heading = 90.0, model = 'p_chest01x', label = 'Homestead chest' },
            slots = slotTemplate(),
        },
        -- Scarlett Meadows (Rhodes) — creek bottoms and cedar flats.
        scarlett_meadows_01 = {
            id = 'scarlett_meadows_01',
            name = 'Red Cane claim',
            class = 'claim',
            region = 'scarlett_meadows',
            verified = false,
            center = V(1580.0, -1230.0, 70.0),
            radius = 25.0,
            chest = { coords = V(1584.0, -1230.0, 70.0), heading = 90.0, model = 'p_chest01x', label = 'Homestead chest' },
            slots = slotTemplate(),
        },
        scarlett_meadows_02 = {
            id = 'scarlett_meadows_02',
            name = 'Wildcat Hollow claim',
            class = 'claim',
            region = 'scarlett_meadows',
            verified = false,
            center = V(1180.0, -980.0, 75.0),
            radius = 25.0,
            chest = { coords = V(1184.0, -980.0, 75.0), heading = 90.0, model = 'p_chest01x', label = 'Homestead chest' },
            slots = slotTemplate(),
        },
        scarlett_meadows_03 = {
            id = 'scarlett_meadows_03',
            name = 'Cedar Flat claim',
            class = 'claim',
            region = 'scarlett_meadows',
            verified = false,
            center = V(1720.0, -1450.0, 60.0),
            radius = 25.0,
            chest = { coords = V(1724.0, -1450.0, 60.0), heading = 90.0, model = 'p_chest01x', label = 'Homestead chest' },
            slots = slotTemplate(),
        },
        scarlett_meadows_04 = {
            id = 'scarlett_meadows_04',
            name = 'Sorghum Furrow claim',
            class = 'claim',
            region = 'scarlett_meadows',
            verified = false,
            center = V(1150.0, -1600.0, 65.0),
            radius = 25.0,
            chest = { coords = V(1154.0, -1600.0, 65.0), heading = 90.0, model = 'p_chest01x', label = 'Homestead chest' },
            slots = slotTemplate(),
        },
        -- Bayou Nwa (Saint Denis) — swamp and cypress bayou.
        bayou_nwa_01 = {
            id = 'bayou_nwa_01',
            name = 'Cypress Reach claim',
            class = 'claim',
            region = 'bayou_nwa',
            verified = false,
            center = V(2440.0, -1300.0, 30.0),
            radius = 25.0,
            chest = { coords = V(2444.0, -1300.0, 30.0), heading = 90.0, model = 'p_chest01x', label = 'Homestead chest' },
            slots = slotTemplate(),
        },
        bayou_nwa_02 = {
            id = 'bayou_nwa_02',
            name = 'Sugar Cane claim',
            class = 'claim',
            region = 'bayou_nwa',
            verified = false,
            center = V(1960.0, -1200.0, 25.0),
            radius = 25.0,
            chest = { coords = V(1964.0, -1200.0, 25.0), heading = 90.0, model = 'p_chest01x', label = 'Homestead chest' },
            slots = slotTemplate(),
        },
        bayou_nwa_03 = {
            id = 'bayou_nwa_03',
            name = 'Tupelo Gut claim',
            class = 'claim',
            region = 'bayou_nwa',
            verified = false,
            center = V(2830.0, -1650.0, 20.0),
            radius = 25.0,
            chest = { coords = V(2834.0, -1650.0, 20.0), heading = 90.0, model = 'p_chest01x', label = 'Homestead chest' },
            slots = slotTemplate(),
        },
        -- Great Plains (Blackwater) — river ford and timber line.
        great_plains_01 = {
            id = 'great_plains_01',
            name = 'Cottonwood Ford claim',
            class = 'claim',
            region = 'great_plains',
            verified = false,
            center = V(-1100.0, -1500.0, 40.0),
            radius = 25.0,
            chest = { coords = V(-1096.0, -1500.0, 40.0), heading = 90.0, model = 'p_chest01x', label = 'Homestead chest' },
            slots = slotTemplate(),
        },
        great_plains_02 = {
            id = 'great_plains_02',
            name = 'Sage Creek claim',
            class = 'claim',
            region = 'great_plains',
            verified = false,
            center = V(-1200.0, -1150.0, 45.0),
            radius = 25.0,
            chest = { coords = V(-1196.0, -1150.0, 45.0), heading = 90.0, model = 'p_chest01x', label = 'Homestead chest' },
            slots = slotTemplate(),
        },
        great_plains_03 = {
            id = 'great_plains_03',
            name = 'Pine Timber claim',
            class = 'claim',
            region = 'great_plains',
            verified = false,
            center = V(-1350.0, -1750.0, 50.0),
            radius = 25.0,
            chest = { coords = V(-1346.0, -1750.0, 50.0), heading = 90.0, model = 'p_chest01x', label = 'Homestead chest' },
            slots = slotTemplate(),
        },
        -- Town lots (data only): in/next to each town, claimable=false until @homestead H10. Exempt from the 150 m
        -- town rule; still far from every claim (town lots sit at the town edge, claims are >=150 m out).
        heartlands_lot_01 = {
            id = 'heartlands_lot_01',
            name = 'Valentine Main Street lot',
            class = 'town_lot',
            region = 'heartlands',
            verified = false,
            claimable = false,
            center = V(-180.0, 620.0, 113.0),
            radius = 14.0,
            chest = { coords = V(-180.0, 620.0, 113.0), heading = 90.0, model = 'p_chest01x', label = 'Town lot chest' },
            slots = slotTemplate(),
        },
        heartlands_lot_02 = {
            id = 'heartlands_lot_02',
            name = 'Emerald Ranch lot',
            class = 'town_lot',
            region = 'heartlands',
            verified = false,
            claimable = false,
            center = V(1420.0, 345.0, 96.0),
            radius = 14.0,
            chest = { coords = V(1420.0, 345.0, 96.0), heading = 90.0, model = 'p_chest01x', label = 'Town lot chest' },
            slots = slotTemplate(),
        },
        scarlett_meadows_lot_01 = {
            id = 'scarlett_meadows_lot_01',
            name = 'Rhodes lot',
            class = 'town_lot',
            region = 'scarlett_meadows',
            verified = false,
            claimable = false,
            center = V(1275.0, -1300.0, 77.0),
            radius = 14.0,
            chest = { coords = V(1275.0, -1300.0, 77.0), heading = 90.0, model = 'p_chest01x', label = 'Town lot chest' },
            slots = slotTemplate(),
        },
        bayou_nwa_lot_01 = {
            id = 'bayou_nwa_lot_01',
            name = 'Saint Denis lot',
            class = 'town_lot',
            region = 'bayou_nwa',
            verified = false,
            claimable = false,
            center = V(2700.0, -1450.0, 45.0),
            radius = 14.0,
            chest = { coords = V(2700.0, -1450.0, 45.0), heading = 90.0, model = 'p_chest01x', label = 'Town lot chest' },
            slots = slotTemplate(),
        },
        bayou_nwa_lot_02 = {
            id = 'bayou_nwa_lot_02',
            name = 'Lagras lot',
            class = 'town_lot',
            region = 'bayou_nwa',
            verified = false,
            claimable = false,
            center = V(2175.0, -1110.0, 25.0),
            radius = 14.0,
            chest = { coords = V(2175.0, -1110.0, 25.0), heading = 90.0, model = 'p_chest01x', label = 'Town lot chest' },
            slots = slotTemplate(),
        },
        great_plains_lot_01 = {
            id = 'great_plains_lot_01',
            name = 'Blackwater lot',
            class = 'town_lot',
            region = 'great_plains',
            verified = false,
            claimable = false,
            center = V(-860.0, -1350.0, 44.0),
            radius = 14.0,
            chest = { coords = V(-860.0, -1350.0, 44.0), heading = 90.0, model = 'p_chest01x', label = 'Town lot chest' },
            slots = slotTemplate(),
        },
    },
}
FhHomesteadConfig.slotTemplates = slotTemplates
-- H9: a plot's slots come from its class template (missing class = 'claim'). Claims keep an explicit `slots`; any
-- other class (town_lot) always gets its own template, even if the entry lists slots. Unknown class = no slots.
for _, p in pairs(FhHomesteadConfig.plots) do
    local class = (type(p.class) == 'string' and p.class ~= '') and p.class or 'claim'
    if class ~= 'claim' or p.slots == nil then p.slots = slotTemplates[class] and slotTemplates[class]() or {} end
end

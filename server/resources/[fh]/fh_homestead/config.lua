-- fh_homestead fixed plots (spec L138-139). Coordinates are APPROXIMATE (from fh_core regions) and must be verified
-- in game: stand at the spot, read coords, adjust. One entry per plot; ids are stable (stored in fh_plots).
-- H1: each plot also lists build SLOTS (cabin, fence, stations, trophy wall, chests). Costs/comfort are data only here;
-- the build flow and the money/item debit are H2 (server/build.lua). Slot ids are stable (stored in fh_plot_slots).
local function V(x, y, z) if vector3 then return vector3(x, y, z) end return { x = x, y = y, z = z } end

-- Slot template shared by every plot. tiers[n] = what building tier n costs and gives; tier 0 = not built.
--   cost   = { money = <dollars>, items = { <item> = <count> } }   (debit: server/build.lua, items from the plot chest)
--   comfort= comfort points that tier adds (build_rules.totalComfort sums every built tier)
--   unlocks= { chests = {slot ids}, safeRadiusBonus = m, stationType = id, trophyComfort = bool }
--   requires = { [slotId] = minTier } prerequisite slots
--   prop   = fallback (B6a) model + offset from plot center; propVerified (optional) is used when verifiedProps is true.
local function slotTemplate()
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

FhHomesteadConfig = {
    -- false = every slot uses its fallback prop (B6a model + offset). Flip to true only after propVerified is filled in.
    verifiedProps = false,
    baseSafeRadius = 25.0,
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
    plots = {
        heartlands_01 = {
            id = 'heartlands_01',
            region = 'heartlands',
            center = V(-300.0, 790.0, 118.0),
            radius = 25.0,
            chest = { coords = V(-296.0, 790.0, 118.0), heading = 90.0, model = 'p_chest01x', label = 'Homestead chest' },
            slots = slotTemplate(),
        },
        -- Plots 2-4: TODO-verify. Placeholder coords 150 apart so plots never overlap even at max fenced radius; fh_plots.citizenid stays UNIQUE (one plot per character).
        heartlands_02 = {
            id = 'heartlands_02',
            region = 'heartlands',
            center = V(-150.0, 790.0, 118.0), -- TODO-verify
            radius = 25.0,
            chest = { coords = V(-146.0, 790.0, 118.0), heading = 90.0, model = 'p_chest01x', label = 'Homestead chest' },
            slots = slotTemplate(),
        },
        heartlands_03 = {
            id = 'heartlands_03',
            region = 'heartlands',
            center = V(-300.0, 940.0, 118.0), -- TODO-verify
            radius = 25.0,
            chest = { coords = V(-296.0, 940.0, 118.0), heading = 90.0, model = 'p_chest01x', label = 'Homestead chest' },
            slots = slotTemplate(),
        },
        heartlands_04 = {
            id = 'heartlands_04',
            region = 'heartlands',
            center = V(-150.0, 940.0, 118.0), -- TODO-verify
            radius = 25.0,
            chest = { coords = V(-146.0, 940.0, 118.0), heading = 90.0, model = 'p_chest01x', label = 'Homestead chest' },
            slots = slotTemplate(),
        },
        -- Scarlett Meadows (Rhodes) plots. TODO-verify: placeholder coords 150 apart (same pattern as heartlands 2-4).
        scarlett_meadows_01 = {
            id = 'scarlett_meadows_01',
            region = 'scarlett_meadows',
            center = V(1250.0, -1210.0, 77.0), -- TODO-verify (unverified)
            radius = 25.0,
            chest = { coords = V(1254.0, -1210.0, 77.0), heading = 90.0, model = 'p_chest01x', label = 'Homestead chest' },
            slots = slotTemplate(),
        },
        scarlett_meadows_02 = {
            id = 'scarlett_meadows_02',
            region = 'scarlett_meadows',
            center = V(1400.0, -1210.0, 77.0), -- TODO-verify (unverified)
            radius = 25.0,
            chest = { coords = V(1404.0, -1210.0, 77.0), heading = 90.0, model = 'p_chest01x', label = 'Homestead chest' },
            slots = slotTemplate(),
        },
        scarlett_meadows_03 = {
            id = 'scarlett_meadows_03',
            region = 'scarlett_meadows',
            center = V(1250.0, -1060.0, 77.0), -- TODO-verify (unverified)
            radius = 25.0,
            chest = { coords = V(1254.0, -1060.0, 77.0), heading = 90.0, model = 'p_chest01x', label = 'Homestead chest' },
            slots = slotTemplate(),
        },
        scarlett_meadows_04 = {
            id = 'scarlett_meadows_04',
            region = 'scarlett_meadows',
            center = V(1400.0, -1060.0, 77.0), -- TODO-verify (unverified)
            radius = 25.0,
            chest = { coords = V(1404.0, -1060.0, 77.0), heading = 90.0, model = 'p_chest01x', label = 'Homestead chest' },
            slots = slotTemplate(),
        },
    },
}

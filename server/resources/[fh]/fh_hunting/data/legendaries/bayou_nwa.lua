-- bayou_nwa legendary (plan hunting-02 B2). Pure data: runs with no globals and returns one entry (shape: the header of
-- shared/legendaries.lua). Clue 1 is bought at a rumour point in the region; clues 2 and 3 are inspectable markers; the
-- final area spawns the legendary through fh_core requestSpawn.
-- All coordinates UNVERIFIED in game (stand at each spot, read coords, adjust).
return {
    id = 'legendary_mossback_gator',
    label = 'Legendary Mossback Gator',
    species_model = 'a_c_alligator_01', -- same model as the plain alligator; identified as legendary by the chain's spawn
    outfit = 0,                         -- TODO-verify-in-game
    scale = 1.15,                       -- TODO-verify-in-game
    pelt = { item = 'pelt_legendary_mossback_gator', label = 'Legendary Mossback Gator Pelt', value = 73, weight = 25000,
        image = 'perfect_pelt.png' },
    trophy = { item = 'trophy_legendary_mossback_gator', label = 'Legendary Mossback Gator Trophy', comfort = 25 },
    -- The region's trapper: sells pelts and hosts the rumour (rumour.coords follows it).
    trapper = { label = 'Bayou Nwa Trapper', coords = { x = 2175.0, y = -1120.0, z = 25.0 } }, -- TODO-verify-in-game
    rumour = {
        coords = { x = 2175.0, y = -1120.0, z = 25.0 }, -- TODO-verify-in-game
        price = 25,
        label = 'Ask about the mossback gator',
        text = 'The ferryman pockets your money and mutters about drag marks and split cypress roots out in the bayou.',
    },
    markers = {
        [2] = { id = 'track',   label = 'Drag marks',        coords = { x = 2300.0, y = -1250.0, z = 25.0 }, radius = 3.0 }, -- TODO-verify-in-game
        [3] = { id = 'carcass', label = 'Half-eaten carcass', coords = { x = 2420.0, y = -1380.0, z = 25.0 }, radius = 3.0 }, -- TODO-verify-in-game
    },
    spawn = {
        coords = { x = 2550.0, y = -1500.0, z = 24.0, heading = 0.0 }, -- TODO-verify-in-game
    },
}

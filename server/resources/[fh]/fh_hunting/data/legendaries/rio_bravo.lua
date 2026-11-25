-- rio_bravo legendary (plan hunting-02 B4). Pure data: runs with no globals and returns one entry (shape: the
-- header of shared/legendaries.lua). Original name, label and description only (no real-world, film or game legendary).
-- Clue 1 is bought at the region's rumour point; clues 2 and 3 are inspectable markers; the final area spawns the
-- animal through fh_core requestSpawn. All coordinates UNVERIFIED in game (stand at each spot, read coords, adjust).
return {
    id = 'legendary_canyonback_boar',
    label = 'Canyonback Boar',
    species_model = 'a_c_boar_01', -- plain row in shared/animals.lua; identified as legendary by the chain's spawn
    outfit = 0,                    -- TODO-verify-in-game
    scale = 1.2,                   -- TODO-verify-in-game
    pelt = { item = 'pelt_legendary_canyonback_boar', label = 'Canyonback Boar Pelt', value = 28, weight = 6000,
        image = 'good_pelt.png' },
    trophy = { item = 'trophy_legendary_canyonback_boar', label = 'Canyonback Boar Trophy', comfort = 25 },
    rumour = {
        coords = { x = -2000.0, y = -3000.0, z = 55.0 }, -- TODO-verify-in-game
        price = 25, -- fh_economy amount, reason 'hunting:rumour', ledger region = this file's region
        label = 'Ask about the canyonback boar',
        text = 'The trapper pockets your money and points toward a tusked boar rooting through the river bravo brush.',
    },
    markers = {
        [2] = { id = 'track',   label = 'Boar tracks',  coords = { x = -1850.0, y = -3050.0, z = 58.0 }, radius = 3.0 }, -- TODO-verify-in-game
        [3] = { id = 'carcass', label = 'Rooted earth', coords = { x = -1700.0, y = -3100.0, z = 55.0 }, radius = 3.0 }, -- TODO-verify-in-game
    },
    spawn = {
        coords = { x = -1550.0, y = -3150.0, z = 56.0, heading = 0.0 }, -- TODO-verify-in-game (the final area)
    },
}

-- big_valley legendary (plan hunting-02 B3). Pure data: runs with no globals and returns one entry (shape: the
-- header of shared/legendaries.lua). Original name, label and description only (no real-world, film or game legendary).
-- Clue 1 is bought at the region's rumour point; clues 2 and 3 are inspectable markers; the final area spawns the
-- animal through fh_core requestSpawn. All coordinates UNVERIFIED in game (stand at each spot, read coords, adjust).
return {
    id = 'legendary_copperhide_deer',
    label = 'Copperhide Deer',
    species_model = 'a_c_deer_01', -- plain row in shared/animals.lua; identified as legendary by the chain's spawn
    outfit = 0,                    -- TODO-verify-in-game
    scale = 1.2,                   -- TODO-verify-in-game
    pelt = { item = 'pelt_legendary_copperhide_deer', label = 'Copperhide Deer Pelt', value = 19, weight = 6000,
        image = 'good_pelt.png' },
    trophy = { item = 'trophy_legendary_copperhide_deer', label = 'Copperhide Deer Trophy', comfort = 25 },
    rumour = {
        coords = { x = -1814.0, y = -440.0, z = 120.0 }, -- TODO-verify-in-game
        price = 25, -- fh_economy amount, reason 'hunting:rumour', ledger region = this file's region
        label = 'Ask about the copperhide deer',
        text = 'The trapper pockets the money and tells of a copper-coated stag grazing the valley meadows.',
    },
    markers = {
        [2] = { id = 'track',   label = 'Deer tracks',   coords = { x = -1700.0, y = -550.0, z = 105.0 }, radius = 3.0 }, -- TODO-verify-in-game
        [3] = { id = 'carcass', label = 'Copper tuft',   coords = { x = -1600.0, y = -650.0, z = 95.0 }, radius = 3.0 }, -- TODO-verify-in-game
    },
    spawn = {
        coords = { x = -1500.0, y = -750.0, z = 90.0, heading = 0.0 }, -- TODO-verify-in-game (the final area)
    },
}

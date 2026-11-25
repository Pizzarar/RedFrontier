-- grizzlies_west legendary (plan hunting-02 B3). Pure data: runs with no globals and returns one entry (shape: the
-- header of shared/legendaries.lua). Original name, label and description only (no real-world, film or game legendary).
-- Clue 1 is bought at the region's rumour point; clues 2 and 3 are inspectable markers; the final area spawns the
-- animal through fh_core requestSpawn. All coordinates UNVERIFIED in game (stand at each spot, read coords, adjust).
return {
    id = 'legendary_palehorn_elk',
    label = 'Legendary Palehorn Elk',
    species_model = 'a_c_elk_01', -- plain row in shared/animals.lua; identified as legendary by the chain's spawn
    outfit = 0,                   -- TODO-verify-in-game
    scale = 1.25,                 -- TODO-verify-in-game
    pelt = { item = 'pelt_legendary_palehorn_elk', label = 'Legendary Palehorn Elk Pelt', value = 51, weight = 24000,
        image = 'perfect_pelt.png' },
    trophy = { item = 'trophy_legendary_palehorn_elk', label = 'Legendary Palehorn Elk Trophy', comfort = 25 },
    rumour = {
        coords = { x = -1300.0, y = 1600.0, z = 240.0 }, -- TODO-verify-in-game
        price = 25, -- fh_economy amount, reason 'hunting:rumour', ledger region = this file's region
        label = 'Ask about the palehorn elk',
        text = 'The trapper pockets your money and whispers of a pale-antlered elk seen above the frozen pass.',
    },
    markers = {
        [2] = { id = 'track',   label = 'Elk tracks',    coords = { x = -1400.0, y = 1450.0, z = 220.0 }, radius = 3.0 }, -- TODO-verify-in-game
        [3] = { id = 'carcass', label = 'Pale antler',   coords = { x = -1500.0, y = 1300.0, z = 215.0 }, radius = 3.0 }, -- TODO-verify-in-game
    },
    spawn = {
        coords = { x = -1600.0, y = 1200.0, z = 210.0, heading = 0.0 }, -- TODO-verify-in-game (the final area)
    },
}

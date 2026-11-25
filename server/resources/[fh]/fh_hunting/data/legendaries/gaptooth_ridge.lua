-- gaptooth_ridge legendary (plan hunting-02 B4). Pure data: runs with no globals and returns one entry (shape: the
-- header of shared/legendaries.lua). Original name, label and description only (no real-world, film or game legendary).
-- Clue 1 is bought at the region's rumour point; clues 2 and 3 are inspectable markers; the final area spawns the
-- animal through fh_core requestSpawn. All coordinates UNVERIFIED in game (stand at each spot, read coords, adjust).
return {
    id = 'legendary_sandveil_fox',
    label = 'Legendary Sandveil Fox',
    species_model = 'a_c_fox_01', -- plain row in shared/animals.lua; identified as legendary by the chain's spawn
    outfit = 0,                   -- TODO-verify-in-game
    scale = 1.3,                  -- TODO-verify-in-game
    pelt = { item = 'pelt_legendary_sandveil_fox', label = 'Legendary Sandveil Fox Pelt', value = 11, weight = 3500,
        image = 'resource_pelt_fox.png' },
    trophy = { item = 'trophy_legendary_sandveil_fox', label = 'Legendary Sandveil Fox Trophy', comfort = 25 },
    rumour = {
        coords = { x = -5514.0, y = -2928.0, z = 90.0 }, -- TODO-verify-in-game
        price = 25, -- fh_economy amount, reason 'hunting:rumour', ledger region = this file's region
        label = 'Ask about the sandveil fox',
        text = 'The trapper counts your coins and whispers of a pale fox that slips between the canyon walls.',
    },
    markers = {
        [2] = { id = 'track',   label = 'Fox tracks', coords = { x = -5650.0, y = -2900.0, z = 88.0 }, radius = 3.0 }, -- TODO-verify-in-game
        [3] = { id = 'carcass', label = 'Dusty den',  coords = { x = -5750.0, y = -2820.0, z = 85.0 }, radius = 3.0 }, -- TODO-verify-in-game
    },
    spawn = {
        coords = { x = -5820.0, y = -2750.0, z = 84.0, heading = 0.0 }, -- TODO-verify-in-game (the final area)
    },
}

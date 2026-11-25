-- cumberland_forest legendary (plan hunting-02 B3). Pure data: runs with no globals and returns one entry (shape: the
-- header of shared/legendaries.lua). Original name, label and description only (no real-world, film or game legendary).
-- Clue 1 is bought at the region's rumour point; clues 2 and 3 are inspectable markers; the final area spawns the
-- animal through fh_core requestSpawn. All coordinates UNVERIFIED in game (stand at each spot, read coords, adjust).
return {
    id = 'legendary_greyhowl_wolf',
    label = 'Greyhowl Wolf',
    species_model = 'a_c_wolf', -- plain row in shared/animals.lua; identified as legendary by the chain's spawn
    outfit = 0,                 -- TODO-verify-in-game
    scale = 1.2,                -- TODO-verify-in-game
    pelt = { item = 'pelt_legendary_greyhowl_wolf', label = 'Greyhowl Wolf Pelt', value = 27, weight = 8000,
        image = 'resource_pelt_wolf.png' },
    trophy = { item = 'trophy_legendary_greyhowl_wolf', label = 'Greyhowl Wolf Trophy', comfort = 25 },
    rumour = {
        coords = { x = -810.0, y = 1340.0, z = 130.0 }, -- TODO-verify-in-game
        price = 25, -- fh_economy amount, reason 'hunting:rumour', ledger region = this file's region
        label = 'Ask about the greyhowl wolf',
        text = 'The trapper takes your coins and warns of a grey wolf that hunts the timber north of Bacchus Station.',
    },
    markers = {
        [2] = { id = 'track',   label = 'Wolf tracks',    coords = { x = -700.0, y = 1250.0, z = 120.0 }, radius = 3.0 }, -- TODO-verify-in-game
        [3] = { id = 'carcass', label = 'Fresh wolf kill', coords = { x = -600.0, y = 1150.0, z = 115.0 }, radius = 3.0 }, -- TODO-verify-in-game
    },
    spawn = {
        coords = { x = -500.0, y = 1080.0, z = 110.0, heading = 0.0 }, -- TODO-verify-in-game (the final area)
    },
}

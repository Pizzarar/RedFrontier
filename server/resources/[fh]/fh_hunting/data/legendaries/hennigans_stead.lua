-- hennigans_stead legendary (plan hunting-02 B4). Pure data: runs with no globals and returns one entry (shape: the
-- header of shared/legendaries.lua). Original name, label and description only (no real-world, film or game legendary).
-- Clue 1 is bought at the region's rumour point; clues 2 and 3 are inspectable markers; the final area spawns the
-- animal through fh_core requestSpawn. All coordinates UNVERIFIED in game (stand at each spot, read coords, adjust).
return {
    id = 'legendary_saltbrush_buck',
    label = 'Saltbrush Buck',
    species_model = 'a_c_deer_01', -- plain row in shared/animals.lua; identified as legendary by the chain's spawn
    outfit = 0,                    -- TODO-verify-in-game
    scale = 1.25,                  -- TODO-verify-in-game
    pelt = { item = 'pelt_legendary_saltbrush_buck', label = 'Saltbrush Buck Pelt', value = 19, weight = 6000,
        image = 'good_pelt.png' },
    trophy = { item = 'trophy_legendary_saltbrush_buck', label = 'Saltbrush Buck Trophy', comfort = 25 },
    rumour = {
        coords = { x = -2275.0, y = -2485.0, z = 60.0 }, -- TODO-verify-in-game
        price = 25, -- fh_economy amount, reason 'hunting:rumour', ledger region = this file's region
        label = 'Ask about the saltbrush buck',
        text = 'The rancher pockets your coins and points toward a big buck seen at the edge of the tablelands.',
    },
    markers = {
        [2] = { id = 'track',   label = 'Buck tracks',    coords = { x = -2150.0, y = -2400.0, z = 62.0 }, radius = 3.0 }, -- TODO-verify-in-game
        [3] = { id = 'carcass', label = 'Rubbed juniper', coords = { x = -2000.0, y = -2300.0, z = 60.0 }, radius = 3.0 }, -- TODO-verify-in-game
    },
    spawn = {
        coords = { x = -1850.0, y = -2200.0, z = 58.0, heading = 0.0 }, -- TODO-verify-in-game (the final area)
    },
}

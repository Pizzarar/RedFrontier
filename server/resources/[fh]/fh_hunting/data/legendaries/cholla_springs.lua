-- cholla_springs legendary (plan hunting-02 B4). Pure data: runs with no globals and returns one entry (shape: the
-- header of shared/legendaries.lua). Original name, label and description only (no real-world, film or game legendary).
-- Clue 1 is bought at the region's rumour point; clues 2 and 3 are inspectable markers; the final area spawns the
-- animal through fh_core requestSpawn. All coordinates UNVERIFIED in game (stand at each spot, read coords, adjust).
return {
    id = 'legendary_cinderjaw_coyote',
    label = 'Legendary Cinderjaw Coyote',
    species_model = 'a_c_coyote_01', -- plain row in shared/animals.lua; identified as legendary by the chain's spawn
    outfit = 0,                      -- TODO-verify-in-game
    scale = 1.25,                    -- TODO-verify-in-game
    pelt = { item = 'pelt_legendary_cinderjaw_coyote', label = 'Legendary Cinderjaw Coyote Pelt', value = 11, weight = 4000,
        image = 'resource_pelt_coyote.png' },
    trophy = { item = 'trophy_legendary_cinderjaw_coyote', label = 'Legendary Cinderjaw Coyote Trophy', comfort = 25 },
    -- The region's trapper: sells pelts and hosts the rumour (rumour.coords follows it).
    trapper = { label = 'Cholla Springs Trapper', coords = { x = -3703.0, y = -2573.0, z = 70.0 } }, -- TODO-verify-in-game
    rumour = {
        coords = { x = -3703.0, y = -2573.0, z = 70.0 }, -- TODO-verify-in-game
        price = 25, -- fh_economy amount, reason 'hunting:rumour', ledger region = this file's region
        label = 'Ask about the cinderjaw coyote',
        text = 'The trapper pockets your money and tells of a singed-jaw coyote that roams the alkali flats.',
    },
    markers = {
        [2] = { id = 'track',   label = 'Coyote tracks',  coords = { x = -3550.0, y = -2500.0, z = 72.0 }, radius = 3.0 }, -- TODO-verify-in-game
        [3] = { id = 'carcass', label = 'Scavenged kill', coords = { x = -3450.0, y = -2430.0, z = 74.0 }, radius = 3.0 }, -- TODO-verify-in-game
    },
    spawn = {
        coords = { x = -3400.0, y = -2360.0, z = 76.0, heading = 0.0 }, -- TODO-verify-in-game (the final area)
    },
}

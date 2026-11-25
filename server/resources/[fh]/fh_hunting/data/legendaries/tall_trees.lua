-- tall_trees legendary (plan hunting-02 B3). Pure data: runs with no globals and returns one entry (shape: the
-- header of shared/legendaries.lua). Original name, label and description only (no real-world, film or game legendary).
-- Clue 1 is bought at the region's rumour point; clues 2 and 3 are inspectable markers; the final area spawns the
-- animal through fh_core requestSpawn. All coordinates UNVERIFIED in game (stand at each spot, read coords, adjust).
return {
    id = 'legendary_embercoat_coyote',
    label = 'Legendary Embercoat Coyote',
    species_model = 'a_c_coyote_01', -- plain row in shared/animals.lua; identified as legendary by the chain's spawn
    outfit = 0,                      -- TODO-verify-in-game
    scale = 1.2,                     -- TODO-verify-in-game
    pelt = { item = 'pelt_legendary_embercoat_coyote', label = 'Legendary Embercoat Coyote Pelt', value = 11, weight = 4000,
        image = 'resource_pelt_coyote.png' },
    trophy = { item = 'trophy_legendary_embercoat_coyote', label = 'Legendary Embercoat Coyote Trophy', comfort = 25 },
    rumour = {
        coords = { x = -1795.0, y = -1600.0, z = 150.0 }, -- TODO-verify-in-game
        price = 25, -- fh_economy amount, reason 'hunting:rumour', ledger region = this file's region
        label = 'Ask about the embercoat coyote',
        text = 'The trapper takes your coin and speaks of a red-furred coyote skulking the pines past Manzanita Post.',
    },
    markers = {
        [2] = { id = 'track',   label = 'Coyote tracks',  coords = { x = -1900.0, y = -1550.0, z = 145.0 }, radius = 3.0 }, -- TODO-verify-in-game
        [3] = { id = 'carcass', label = 'Scavenged kill', coords = { x = -2000.0, y = -1500.0, z = 140.0 }, radius = 3.0 }, -- TODO-verify-in-game
    },
    spawn = {
        coords = { x = -2100.0, y = -1450.0, z = 135.0, heading = 0.0 }, -- TODO-verify-in-game (the final area)
    },
}

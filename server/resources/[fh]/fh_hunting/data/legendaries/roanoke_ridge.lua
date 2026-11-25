-- roanoke_ridge legendary (plan hunting-02 B2). Pure data: runs with no globals and returns one entry (shape: the header
-- of shared/legendaries.lua). Clue 1 is bought at a rumour point in the region; clues 2 and 3 are inspectable markers;
-- the final area spawns the legendary through fh_core requestSpawn.
-- All coordinates UNVERIFIED in game (stand at each spot, read coords, adjust).
return {
    id = 'legendary_coalhorn_moose',
    label = 'Legendary Coalhorn Moose',
    species_model = 'a_c_moose_01', -- same model as the plain moose; identified as legendary by the chain's spawn
    outfit = 0,                     -- TODO-verify-in-game
    scale = 1.15,                   -- TODO-verify-in-game
    pelt = { item = 'pelt_legendary_coalhorn_moose', label = 'Legendary Coalhorn Moose Pelt', value = 62, weight = 30000,
        image = 'perfect_pelt.png' },
    trophy = { item = 'trophy_legendary_coalhorn_moose', label = 'Legendary Coalhorn Moose Trophy', comfort = 25 },
    rumour = {
        coords = { x = 2975.0, y = 600.0, z = 38.0 }, -- TODO-verify-in-game
        price = 25,
        label = 'Ask about the coalhorn moose',
        text = 'The miner pockets your money and points upriver toward gouged bark and shed antler velvet in the pines.',
    },
    markers = {
        [2] = { id = 'track',   label = 'Moose tracks',     coords = { x = 2900.0, y = 750.0, z = 55.0 }, radius = 3.0 }, -- TODO-verify-in-game
        [3] = { id = 'carcass', label = 'Gouged tree bark', coords = { x = 2850.0, y = 950.0, z = 75.0 }, radius = 3.0 }, -- TODO-verify-in-game
    },
    spawn = {
        coords = { x = 2830.0, y = 1150.0, z = 90.0, heading = 0.0 }, -- TODO-verify-in-game
    },
}

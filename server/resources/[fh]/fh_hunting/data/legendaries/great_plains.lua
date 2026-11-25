-- great_plains legendary (plan hunting-02 B2). Pure data: runs with no globals and returns one entry (shape: the header
-- of shared/legendaries.lua). Clue 1 is bought at a rumour point in the region; clues 2 and 3 are inspectable markers;
-- the final area spawns the legendary through fh_core requestSpawn.
-- All coordinates UNVERIFIED in game (stand at each spot, read coords, adjust).
return {
    id = 'legendary_dusthorn_bison',
    label = 'Legendary Dusthorn Bison',
    species_model = 'a_c_buffalo_01', -- same model as the plain bison; identified as legendary by the chain's spawn
    outfit = 0,                       -- TODO-verify-in-game
    scale = 1.15,                     -- TODO-verify-in-game
    pelt = { item = 'pelt_legendary_dusthorn_bison', label = 'Legendary Dusthorn Bison Pelt', value = 53, weight = 30000,
        image = 'perfect_pelt.png' },
    trophy = { item = 'trophy_legendary_dusthorn_bison', label = 'Legendary Dusthorn Bison Trophy', comfort = 25 },
    rumour = {
        coords = { x = -865.0, y = -1335.0, z = 44.0 }, -- TODO-verify-in-game
        price = 25,
        label = 'Ask about the dusthorn bison',
        text = 'The plainsman pockets your money and points toward a dust trail where the grass is trampled flat to the west.',
    },
    markers = {
        [2] = { id = 'track',   label = 'Bison tracks',     coords = { x = -1000.0, y = -1250.0, z = 45.0 }, radius = 3.0 }, -- TODO-verify-in-game
        [3] = { id = 'carcass', label = 'Trampled carcass', coords = { x = -1150.0, y = -1200.0, z = 45.0 }, radius = 3.0 }, -- TODO-verify-in-game
    },
    spawn = {
        coords = { x = -1300.0, y = -1180.0, z = 42.0, heading = 0.0 }, -- TODO-verify-in-game
    },
}

-- scarlett_meadows legendary (plan hunting-02 B2). Pure data: runs with no globals and returns one entry (shape: the
-- header of shared/legendaries.lua). Clue 1 is bought at a rumour point in the region; clues 2 and 3 are inspectable
-- markers; the final area spawns the legendary through fh_core requestSpawn.
-- All coordinates UNVERIFIED in game (stand at each spot, read coords, adjust).
return {
    id = 'legendary_redclay_stag',
    label = 'Legendary Red Clay Stag',
    species_model = 'a_c_deer_01', -- same model as the plain deer; identified as legendary by the chain's spawn
    outfit = 0,                    -- TODO-verify-in-game
    scale = 1.1,                   -- TODO-verify-in-game
    pelt = { item = 'pelt_legendary_redclay_stag', label = 'Legendary Red Clay Stag Pelt', value = 19, weight = 4000,
        image = 'good_pelt.png' },
    trophy = { item = 'trophy_legendary_redclay_stag', label = 'Legendary Red Clay Stag Trophy', comfort = 25 },
    -- The region's trapper: sells pelts and hosts the rumour (rumour.coords follows it).
    trapper = { label = 'Scarlett Meadows Trapper', coords = { x = 1265.0, y = -1305.0, z = 77.0 } }, -- TODO-verify-in-game
    rumour = {
        coords = { x = 1265.0, y = -1305.0, z = 77.0 }, -- TODO-verify-in-game
        price = 25,
        label = 'Ask about the red clay stag',
        text = 'The gossip pockets your money and points you toward fresh stag tracks through the red-earth fields to the south.',
    },
    markers = {
        [2] = { id = 'track',   label = 'Stag tracks', coords = { x = 1350.0, y = -1400.0, z = 75.0 }, radius = 3.0 }, -- TODO-verify-in-game
        [3] = { id = 'carcass', label = 'Shed antler', coords = { x = 1450.0, y = -1480.0, z = 72.0 }, radius = 3.0 }, -- TODO-verify-in-game
    },
    spawn = {
        coords = { x = 1520.0, y = -1560.0, z = 70.0, heading = 0.0 }, -- TODO-verify-in-game
    },
}

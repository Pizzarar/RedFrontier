-- bluewater_marsh legendary (plan hunting-02 B2). Pure data: runs with no globals and returns one entry (shape: the
-- header of shared/legendaries.lua). Clue 1 is bought at a rumour point in the region; clues 2 and 3 are inspectable
-- markers; the final area spawns the legendary through fh_core requestSpawn.
-- All coordinates UNVERIFIED in game (stand at each spot, read coords, adjust).
return {
    id = 'legendary_brackhide_boar',
    label = 'Legendary Brackhide Boar',
    species_model = 'a_c_boar_01', -- same model as the plain boar; identified as legendary by the chain's spawn
    outfit = 0,                    -- TODO-verify-in-game
    scale = 1.1,                   -- TODO-verify-in-game
    pelt = { item = 'pelt_legendary_brackhide_boar', label = 'Legendary Brackhide Boar Pelt', value = 52, weight = 4000,
        image = 'good_pelt.png' },
    trophy = { item = 'trophy_legendary_brackhide_boar', label = 'Legendary Brackhide Boar Trophy', comfort = 25 },
    rumour = {
        coords = { x = 2300.0, y = -600.0, z = 20.0 }, -- TODO-verify-in-game
        price = 25,
        label = 'Ask about the brackhide boar',
        text = 'The marsh guide pockets your money and points you toward churned mud and uprooted bullrushes to the north.',
    },
    markers = {
        [2] = { id = 'track',   label = 'Boar prints',     coords = { x = 2450.0, y = -550.0, z = 22.0 }, radius = 3.0 }, -- TODO-verify-in-game
        [3] = { id = 'carcass', label = 'Rooted-up earth', coords = { x = 2600.0, y = -600.0, z = 20.0 }, radius = 3.0 }, -- TODO-verify-in-game
    },
    spawn = {
        coords = { x = 2720.0, y = -700.0, z = 20.0, heading = 0.0 }, -- TODO-verify-in-game
    },
}

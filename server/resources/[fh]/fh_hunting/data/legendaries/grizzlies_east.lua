-- grizzlies_east legendary (plan hunting-02 B3). Pure data: runs with no globals and returns one entry (shape: the
-- header of shared/legendaries.lua). Original name, label and description only (no real-world, film or game legendary).
-- Clue 1 is bought at the region's rumour point; clues 2 and 3 are inspectable markers; the final area spawns the
-- animal through fh_core requestSpawn. All coordinates UNVERIFIED in game (stand at each spot, read coords, adjust).
return {
    id = 'legendary_frostmane_moose',
    label = 'Legendary Frostmane Moose',
    species_model = 'a_c_moose_01', -- plain row in shared/animals.lua; identified as legendary by the chain's spawn
    outfit = 0,                     -- TODO-verify-in-game
    scale = 1.3,                    -- TODO-verify-in-game
    pelt = { item = 'pelt_legendary_frostmane_moose', label = 'Legendary Frostmane Moose Pelt', value = 67, weight = 32000,
        image = 'perfect_pelt.png' },
    trophy = { item = 'trophy_legendary_frostmane_moose', label = 'Legendary Frostmane Moose Trophy', comfort = 25 },
    rumour = {
        coords = { x = 1675.0, y = 1900.0, z = 200.0 }, -- TODO-verify-in-game
        price = 25, -- fh_economy amount, reason 'hunting:rumour', ledger region = this file's region
        label = 'Ask about the frostmane moose',
        text = 'The trapper counts your coins and tells of a scarred bull moose that walks the high snowline above Wapiti.',
    },
    markers = {
        [2] = { id = 'track',   label = 'Moose tracks',    coords = { x = 1550.0, y = 1750.0, z = 190.0 }, radius = 3.0 }, -- TODO-verify-in-game
        [3] = { id = 'carcass', label = 'Scraped sapling', coords = { x = 1450.0, y = 1600.0, z = 185.0 }, radius = 3.0 }, -- TODO-verify-in-game
    },
    spawn = {
        coords = { x = 1350.0, y = 1450.0, z = 185.0, heading = 0.0 }, -- TODO-verify-in-game (the final area)
    },
}

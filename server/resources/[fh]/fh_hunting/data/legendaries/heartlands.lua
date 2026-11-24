-- heartlands legendary (plan hunting-02). Pure data: runs with no globals and returns one entry (shape: the header of
-- shared/legendaries.lua). The Legendary Bear (spec L8 H4), moved here from config.LegendaryBear unchanged.
-- Clue 1 is bought at the heartlands trapper (rumour.coords = config Trapper.coords, so the trapper prompt hosts it);
-- clues 2 and 3 are inspectable markers; the final area spawns the bear through fh_core requestSpawn.
-- All coordinates UNVERIFIED in game (stand at each spot, read coords, adjust).
return {
    id = 'legendary_bear',
    label = 'Legendary Bear',
    species_model = 'a_c_bear_01', -- same model as the plain bear; identified as legendary by the chain's spawn
    outfit = 0,                    -- TODO-verify-in-game
    scale = 1.0,
    pelt = { item = 'pelt_legendary_bear', label = 'Legendary Bear Pelt', value = 60, weight = 30000,
        image = 'legendary_bear_pelt.png' },
    trophy = { item = 'trophy_legendary_bear', label = 'Legendary Bear Trophy', comfort = 25 },
    rumour = {
        coords = { x = -299.0, y = 792.0, z = 118.2 },
        price = 25, -- fh_economy amount, reason 'hunting:rumour', ledger region = this file's region
        label = 'Ask about the legendary bear',
        text = 'The trapper pockets your money and points you toward fresh bear tracks to the east.',
    },
    markers = {
        [2] = { id = 'track',   label = 'Bear tracks',    coords = { x = -260.0, y = 800.0, z = 116.0 }, radius = 3.0 },
        [3] = { id = 'carcass', label = 'Mauled carcass', coords = { x = -215.0, y = 812.0, z = 115.0 }, radius = 3.0 },
    },
    spawn = {
        coords = { x = -170.0, y = 820.0, z = 114.0, heading = 0.0 }, -- the final area
    },
}

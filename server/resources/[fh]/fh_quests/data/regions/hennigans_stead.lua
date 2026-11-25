-- hennigans_stead job templates (fh_quests built-in job types). Coords/models are guesses: TODO-verify-in-game.
local JT = (type((...)) == 'table' and (...)) or FhQuestsJobTypes -- chunk arg in specs (table), the global in FXServer (where ... is a number)

JT.registerRegion('hennigans_stead', {
    hunt = { -- { animal, stars, money }: deliver an N-star pelt of that animal (sold at the fh_hunting buyer)
        { 'rabbit', 1, 6 },
    },
    camps = { -- fh_zones camp ids (fh_zones/config.lua)
        { id = 'hennigans_stead_t1_01', label = 'Tableland camp', money = 40, rep = 3 },
    },
    bounties = { -- wanted NPCs (model/coords TODO-verify-in-game)
        { key = 'rufus_slate', name = 'Rufus Slate', model = 'g_m_m_unibanditos_01',
            coords = { x = -2290.0, y = -2500.0, z = 60.0 }, heading = 90.0, money = 36, rep = 2 },
    },
    supply = { -- { post, item, amount, money, rep }: sell `amount` (or more) of `item` at that fh_trade post
        { post = 'macfarlanes_ranch_post', item = 'trade_salt', amount = 3, money = 9, rep = 1 },
    },
    surveys = { -- ride-out surveys: reach every point (in order unless ordered = false). Coords TODO-verify-in-game
        { key = 'stead_bounds', name = 'Stead bounds', money = 24, rep = 2, ordered = true, points = {
            { x = -2285.0, y = -2495.0, z = 60.0 }, -- TODO-verify-in-game
            { x = -2100.0, y = -2200.0, z = 55.0 }, -- TODO-verify-in-game
            { x = -1960.0, y = -2030.0, z = 60.0 }, -- TODO-verify-in-game
        } },
    },
    escorts = { -- escortee spawns at start, follows the holder to destination. Coords/model TODO-verify-in-game
        { key = 'rosalind_mercer', name = 'Rosalind Mercer', model = 'a_f_m_valtownfolk_01', heading = 90.0, money = 28, rep = 2,
            start = { x = -2285.0, y = -2495.0, z = 60.0 },       -- TODO-verify-in-game
            destination = { x = -1960.0, y = -2030.0, z = 60.0 }, -- TODO-verify-in-game
        },
    },
    rescues = { -- captive held at an fh_zones camp: clear that camp, then reach the captive. Coords/model TODO-verify-in-game
        { key = 'maribel_soto', name = 'Maribel Soto', camp = 'hennigans_stead_t1_01', model = 'a_f_m_valtownfolk_01',
            heading = 180.0, money = 34, rep = 3,
            coords = { x = -1905.0, y = -1955.0, z = 60.0 }, -- TODO-verify-in-game (beside the Tableland camp)
        },
    },
    legendaries = { -- one-shot tier-3 legendary commission (fh_hunting/data/legendaries/hennigans_stead.lua)
        { chain_id = 'legendary_saltbrush_buck', legendary = 'legendary_saltbrush_buck', money = 60, rep = 5, min_tier = 3 },
    },
})

-- rio_bravo job templates (fh_quests built-in job types). Coords/models are guesses: TODO-verify-in-game.
local JT = (type((...)) == 'table' and (...)) or FhQuestsJobTypes -- chunk arg in specs (table), the global in FXServer (where ... is a number)

JT.registerRegion('rio_bravo', {
    hunt = { -- { animal, stars, money }: deliver an N-star pelt of that animal (sold at the fh_hunting buyer)
        { 'rabbit', 3, 12 },
    },
    camps = { -- fh_zones camp ids (fh_zones/config.lua)
        { id = 'rio_bravo_t1_01', label = 'Rio camp', money = 40, rep = 3 },
    },
    bounties = { -- wanted NPCs (model/coords TODO-verify-in-game)
        { key = 'dashiell_mott', name = 'Dashiell Mott', model = 'g_m_m_unibanditos_01',
            coords = { x = -2010.0, y = -3010.0, z = 55.0 }, heading = 180.0, money = 40, rep = 2 },
    },
    supply = { -- { post, item, amount, money, rep }: sell `amount` (or more) of `item` at that fh_trade post
        { post = 'rio_bravo_post', item = 'trade_whiskey', amount = 1, money = 16, rep = 1 },
    },
    surveys = { -- ride-out surveys: reach every point (in order unless ordered = false). Coords TODO-verify-in-game
        { key = 'bravo_overlooks', name = 'Bravo overlooks', money = 24, rep = 2, ordered = true, points = {
            { x = -2005.0, y = -3005.0, z = 55.0 }, -- TODO-verify-in-game
            { x = -1900.0, y = -3100.0, z = 55.0 }, -- TODO-verify-in-game
            { x = -1800.0, y = -3080.0, z = 55.0 }, -- TODO-verify-in-game
        } },
    },
    escorts = { -- escortee spawns at start, follows the holder to destination. Coords/model TODO-verify-in-game
        { key = 'vida_salazar', name = 'Vida Salazar', model = 'a_f_m_valtownfolk_01', heading = 90.0, money = 28, rep = 2,
            start = { x = -2005.0, y = -3005.0, z = 55.0 },       -- TODO-verify-in-game
            destination = { x = -1870.0, y = -3130.0, z = 55.0 }, -- TODO-verify-in-game
        },
    },
    rescues = { -- captive held at an fh_zones camp: clear that camp, then reach the captive. Coords/model TODO-verify-in-game
        { key = 'mateo_reyes', name = 'Mateo Reyes', camp = 'rio_bravo_t1_01', model = 'a_m_m_valtownfolk_01',
            heading = 180.0, money = 34, rep = 3,
            coords = { x = -1805.0, y = -3195.0, z = 55.0 }, -- TODO-verify-in-game (beside the Rio camp)
        },
    },
})

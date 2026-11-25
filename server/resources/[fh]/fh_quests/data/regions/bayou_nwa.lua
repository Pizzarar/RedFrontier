-- bayou_nwa job templates (fh_quests built-in job types). Coords/models are guesses: TODO-verify-in-game.
local JT = (type((...)) == 'table' and (...)) or FhQuestsJobTypes -- chunk arg in specs (table), the global in FXServer (where ... is a number)

JT.registerRegion('bayou_nwa', {
    hunt = { -- { animal, stars, money }: deliver an N-star pelt of that animal (sold at the fh_hunting buyer)
        { 'alligator', 1, 28 }, { 'alligator', 2, 38 }, { 'alligator', 3, 54 },
    },
    camps = { -- fh_zones camp ids (fh_zones/config.lua)
        { id = 'bayou_nwa_t1_01', label = 'Moss Bog camp', money = 40, rep = 3 },
    },
    bounties = { -- wanted NPCs (model/coords TODO-verify-in-game)
        { key = 'jasper_bly', name = 'Jasper Bly', model = 'g_m_m_unibanditos_01',
            coords = { x = 2710.0, y = -1450.0, z = 45.0 }, heading = 180.0, money = 34, rep = 2 },
    },
    supply = { -- { post, item, amount, money, rep }: sell `amount` (or more) of `item` at that fh_trade post
        { post = 'saint_denis_post', item = 'trade_whiskey', amount = 1, money = 16, rep = 1 },
    },
    surveys = { -- ride-out surveys: reach every point (in order unless ordered = false). Coords TODO-verify-in-game
        { key = 'bayou_bends', name = 'Bayou bends', money = 24, rep = 2, ordered = true, points = {
            { x = 2700.0, y = -1445.0, z = 45.0 }, -- TODO-verify-in-game
            { x = 2350.0, y = -1350.0, z = 30.0 }, -- TODO-verify-in-game
            { x = 2150.0, y = -1490.0, z = 25.0 }, -- TODO-verify-in-game
        } },
    },
    escorts = { -- escortee spawns at start, follows the holder to destination. Coords/model TODO-verify-in-game
        { key = 'remy_thibodeau', name = 'Remy Thibodeau', model = 'a_m_m_valtownfolk_01', heading = 90.0, money = 28, rep = 2,
            start = { x = 2695.0, y = -1445.0, z = 45.0 },       -- TODO-verify-in-game
            destination = { x = 2150.0, y = -1490.0, z = 25.0 }, -- TODO-verify-in-game
        },
    },
    rescues = { -- captive held at an fh_zones camp: clear that camp, then reach the captive. Coords/model TODO-verify-in-game
        { key = 'beau_landry', name = 'Beau Landry', camp = 'bayou_nwa_t1_01', model = 'a_m_m_valtownfolk_01',
            heading = 180.0, money = 34, rep = 3,
            coords = { x = 2055.0, y = -1495.0, z = 25.0 }, -- TODO-verify-in-game (beside the Moss Bog camp)
        },
    },
})

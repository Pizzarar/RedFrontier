-- grizzlies_west job templates (fh_quests built-in job types). Coords/models are guesses: TODO-verify-in-game.
local JT = (type((...)) == 'table' and (...)) or FhQuestsJobTypes -- chunk arg in specs (table), the global in FXServer (where ... is a number)

JT.registerRegion('grizzlies_west', {
    hunt = { -- { animal, stars, money }: deliver an N-star pelt of that animal (sold at the fh_hunting buyer)
        { 'elk', 2, 28 },
    },
    camps = { -- fh_zones camp ids (fh_zones/config.lua)
        { id = 'grizzlies_west_t1_01', label = 'Tundra camp', money = 40, rep = 3 },
    },
    bounties = { -- wanted NPCs (model/coords TODO-verify-in-game)
        { key = 'edmund_vale', name = 'Edmund Vale', model = 'g_m_m_unibanditos_01',
            coords = { x = -1310.0, y = 1610.0, z = 240.0 }, heading = 90.0, money = 36, rep = 2 },
    },
    supply = { -- { post, item, amount, money, rep }: sell `amount` (or more) of `item` at that fh_trade post
        { post = 'colter_post', item = 'trade_whiskey', amount = 1, money = 16, rep = 1 },
    },
    surveys = { -- ride-out surveys: reach every point (in order unless ordered = false). Coords TODO-verify-in-game
        { key = 'tundra_points', name = 'Tundra points', money = 24, rep = 2, ordered = true, points = {
            { x = -1305.0, y = 1600.0, z = 240.0 }, -- TODO-verify-in-game
            { x = -1380.0, y = 1300.0, z = 225.0 }, -- TODO-verify-in-game
            { x = -1455.0, y = 985.0,  z = 210.0 }, -- TODO-verify-in-game
        } },
    },
    escorts = { -- escortee spawns at start, follows the holder to destination. Coords/model TODO-verify-in-game
        { key = 'ingrid_solberg', name = 'Ingrid Solberg', model = 'a_f_m_valtownfolk_01', heading = 90.0, money = 28, rep = 2,
            start = { x = -1305.0, y = 1600.0, z = 240.0 },       -- TODO-verify-in-game
            destination = { x = -1455.0, y = 985.0, z = 210.0 }, -- TODO-verify-in-game
        },
    },
    rescues = { -- captive held at an fh_zones camp: clear that camp, then reach the captive. Coords/model TODO-verify-in-game
        { key = 'bjorn_halvorsen', name = 'Bjorn Halvorsen', camp = 'grizzlies_west_t1_01', model = 'a_m_m_valtownfolk_01',
            heading = 180.0, money = 34, rep = 3,
            coords = { x = -1455.0, y = 985.0, z = 210.0 }, -- TODO-verify-in-game (beside the Tundra camp)
        },
    },
})

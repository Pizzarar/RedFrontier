-- scarlett_meadows job templates (fh_quests built-in job types). Coords/models are guesses: TODO-verify-in-game.
local JT = (type((...)) == 'table' and (...)) or FhQuestsJobTypes -- chunk arg in specs (table), the global in FXServer (where ... is a number)

JT.registerRegion('scarlett_meadows', {
    hunt = { -- { animal, stars, money [, min_tier = N] }: deliver an N-star pelt of that animal (sold at the fh_hunting buyer)
        { 'boar', 1, 9 }, { 'boar', 2, 14 }, { 'fox', 1, 10 },
        { 'boar', 3, 22, min_tier = 2 },
    },
    camps = { -- fh_zones camp ids (fh_zones/config.lua)
        { id = 'scarlett_meadows_t1_01', label = 'Hill Haven camp', money = 40, rep = 3 },
        { id = 'scarlett_meadows_t2_01', label = 'Catfish Bottom camp', money = 52, rep = 4, min_tier = 2 },
    },
    bounties = { -- wanted NPCs (model/coords TODO-verify-in-game)
        { key = 'corbett_nash', name = 'Corbett Nash', model = 'g_m_m_unibanditos_01',
            coords = { x = 1280.0, y = -1310.0, z = 78.0 }, heading = 90.0, money = 30, rep = 2 },
        { key = 'graham_lockett', name = 'Graham Lockett', model = 'g_m_m_unibanditos_01',
            coords = { x = 1580.0, y = -1690.0, z = 68.0 }, heading = 150.0, money = 44, rep = 3, min_tier = 2 }, -- TODO-verify-in-game
        { key = 'celeste_kane', name = 'Celeste Kane', model = 'g_m_m_unibanditos_01',
            coords = { x = 1790.0, y = -1810.0, z = 64.0 }, heading = 310.0, money = 58, rep = 4, min_tier = 3 }, -- TODO-verify-in-game
    },
    supply = { -- { post, item, amount, money, rep }: sell `amount` (or more) of `item` at that fh_trade post
        { post = 'rhodes_post', item = 'trade_cloth', amount = 2, money = 10, rep = 1 },
        { post = 'rhodes_post', item = 'trade_whiskey', amount = 3, money = 28, rep = 2, min_tier = 2 },
    },
    surveys = { -- ride-out surveys: reach every point (in order unless ordered = false). Coords TODO-verify-in-game
        { key = 'rhodes_ridges', name = 'Rhodes ridges', money = 24, rep = 2, ordered = true, points = {
            { x = 1270.0, y = -1300.0, z = 78.0 }, -- TODO-verify-in-game
            { x = 1100.0, y = -1150.0, z = 76.0 }, -- TODO-verify-in-game
            { x = 935.0,  y = -1100.0, z = 75.0 }, -- TODO-verify-in-game
        } },
    },
    escorts = { -- escortee spawns at start, follows the holder to destination. Coords/model TODO-verify-in-game
        { key = 'etta_callahan', name = 'Etta Callahan', model = 'a_f_m_valtownfolk_01', heading = 90.0, money = 28, rep = 2,
            start = { x = 1265.0, y = -1300.0, z = 78.0 },       -- TODO-verify-in-game
            destination = { x = 935.0, y = -1100.0, z = 75.0 }, -- TODO-verify-in-game
        },
    },
    rescues = { -- captive held at an fh_zones camp: clear that camp, then reach the captive. Coords/model TODO-verify-in-game
        { key = 'willa_trent', name = 'Willa Trent', camp = 'scarlett_meadows_t1_01', model = 'a_f_m_valtownfolk_01',
            heading = 180.0, money = 34, rep = 3,
            coords = { x = 855.0, y = -1045.0, z = 75.0 }, -- TODO-verify-in-game (beside the Hill Haven camp)
        },
        { key = 'otis_brent', name = 'Otis Brent', camp = 'scarlett_meadows_t2_01', model = 'a_m_m_valtownfolk_01',
            heading = 240.0, money = 46, rep = 4, min_tier = 3,
            coords = { x = 1705.0, y = -1745.0, z = 65.0 }, -- TODO-verify-in-game (beside the Catfish Bottom camp)
        },
    },
    legendaries = { -- one-shot tier-3 legendary commission (fh_hunting/data/legendaries/scarlett_meadows.lua)
        { chain_id = 'legendary_redclay_stag', legendary = 'legendary_redclay_stag', money = 60, rep = 5, min_tier = 3 },
    },
})

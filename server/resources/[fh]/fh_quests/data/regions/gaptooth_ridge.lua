-- gaptooth_ridge job templates (fh_quests built-in job types). Coords/models are guesses: TODO-verify-in-game.
local JT = (type((...)) == 'table' and (...)) or FhQuestsJobTypes -- chunk arg in specs (table), the global in FXServer (where ... is a number)

JT.registerRegion('gaptooth_ridge', {
    hunt = { -- { animal, stars, money }: deliver an N-star pelt of that animal (sold at the fh_hunting buyer)
        { 'coyote', 2, 14 },
    },
    camps = { -- fh_zones camp ids (fh_zones/config.lua)
        { id = 'gaptooth_ridge_t1_01', label = 'Gaptooth camp', money = 40, rep = 3 },
    },
    bounties = { -- wanted NPCs (model/coords TODO-verify-in-game)
        { key = 'vernon_ashe', name = 'Vernon Ashe', model = 'g_m_m_unibanditos_01',
            coords = { x = -5530.0, y = -2945.0, z = 90.0 }, heading = 90.0, money = 40, rep = 2 },
    },
    supply = { -- { post, item, amount, money, rep }: sell `amount` (or more) of `item` at that fh_trade post
        { post = 'tumbleweed_post', item = 'trade_salt', amount = 3, money = 9, rep = 1 },
    },
    surveys = { -- ride-out surveys: reach every point (in order unless ordered = false). Coords TODO-verify-in-game
        { key = 'ridge_waypoints', name = 'Ridge waypoints', money = 24, rep = 2, ordered = true, points = {
            { x = -5525.0, y = -2940.0, z = 90.0 }, -- TODO-verify-in-game
            { x = -5300.0, y = -2750.0, z = 90.0 }, -- TODO-verify-in-game
            { x = -5180.0, y = -2660.0, z = 90.0 }, -- TODO-verify-in-game
        } },
    },
    escorts = { -- escortee spawns at start, follows the holder to destination. Coords/model TODO-verify-in-game
        { key = 'sable_dunham', name = 'Sable Dunham', model = 'a_f_m_valtownfolk_01', heading = 90.0, money = 28, rep = 2,
            start = { x = -5525.0, y = -2940.0, z = 90.0 },       -- TODO-verify-in-game
            destination = { x = -5180.0, y = -2660.0, z = 90.0 }, -- TODO-verify-in-game
        },
    },
    rescues = { -- captive held at an fh_zones camp: clear that camp, then reach the captive. Coords/model TODO-verify-in-game
        { key = 'honora_keel', name = 'Honora Keel', camp = 'gaptooth_ridge_t1_01', model = 'a_f_m_valtownfolk_01',
            heading = 180.0, money = 34, rep = 3,
            coords = { x = -5105.0, y = -2605.0, z = 90.0 }, -- TODO-verify-in-game (beside the Gaptooth camp)
        },
    },
})

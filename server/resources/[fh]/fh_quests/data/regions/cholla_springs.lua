-- cholla_springs job templates (fh_quests built-in job types). Coords/models are guesses: TODO-verify-in-game.
local JT = (type((...)) == 'table' and (...)) or FhQuestsJobTypes -- chunk arg in specs (table), the global in FXServer (where ... is a number)

JT.registerRegion('cholla_springs', {
    hunt = { -- { animal, stars, money }: deliver an N-star pelt of that animal (sold at the fh_hunting buyer)
        { 'rabbit', 2, 8 },
    },
    camps = { -- fh_zones camp ids (fh_zones/config.lua)
        { id = 'cholla_springs_t1_01', label = 'Alkali Flat camp', money = 40, rep = 3 },
    },
    bounties = { -- wanted NPCs (model/coords TODO-verify-in-game)
        { key = 'amos_quill', name = 'Amos Quill', model = 'g_m_m_unibanditos_01',
            coords = { x = -3720.0, y = -2590.0, z = 70.0 }, heading = 180.0, money = 38, rep = 2 },
    },
    supply = { -- { post, item, amount, money, rep }: sell `amount` (or more) of `item` at that fh_trade post
        { post = 'armadillo_post', item = 'trade_cloth', amount = 2, money = 10, rep = 1 },
    },
    surveys = { -- ride-out surveys: reach every point (in order unless ordered = false). Coords TODO-verify-in-game
        { key = 'springs_traverse', name = 'Springs traverse', money = 24, rep = 2, ordered = true, points = {
            { x = -3715.0, y = -2585.0, z = 70.0 }, -- TODO-verify-in-game
            { x = -3550.0, y = -2530.0, z = 72.0 }, -- TODO-verify-in-game
            { x = -3355.0, y = -2485.0, z = 75.0 }, -- TODO-verify-in-game
        } },
    },
    escorts = { -- escortee spawns at start, follows the holder to destination. Coords/model TODO-verify-in-game
        { key = 'petra_moreno', name = 'Petra Moreno', model = 'a_f_m_valtownfolk_01', heading = 90.0, money = 28, rep = 2,
            start = { x = -3715.0, y = -2585.0, z = 70.0 },       -- TODO-verify-in-game
            destination = { x = -3355.0, y = -2485.0, z = 75.0 }, -- TODO-verify-in-game
        },
    },
    rescues = { -- captive held at an fh_zones camp: clear that camp, then reach the captive. Coords/model TODO-verify-in-game
        { key = 'cyrus_flint', name = 'Cyrus Flint', camp = 'cholla_springs_t1_01', model = 'a_m_m_valtownfolk_01',
            heading = 180.0, money = 34, rep = 3,
            coords = { x = -3355.0, y = -2485.0, z = 75.0 }, -- TODO-verify-in-game (beside the Alkali Flat camp)
        },
    },
})

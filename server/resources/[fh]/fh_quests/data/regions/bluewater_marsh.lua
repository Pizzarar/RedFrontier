-- bluewater_marsh job templates (fh_quests built-in job types). Coords/models are guesses: TODO-verify-in-game.
local JT = (type((...)) == 'table' and (...)) or FhQuestsJobTypes -- chunk arg in specs (table), the global in FXServer (where ... is a number)

JT.registerRegion('bluewater_marsh', {
    hunt = { -- { animal, stars, money }: deliver an N-star pelt of that animal (sold at the fh_hunting buyer)
        { 'fox', 2, 14 },
    },
    camps = { -- fh_zones camp ids (fh_zones/config.lua)
        { id = 'bluewater_marsh_t1_01', label = 'Marsh Ford camp', money = 40, rep = 3 },
    },
    bounties = { -- wanted NPCs (model/coords TODO-verify-in-game)
        { key = 'marion_thatch', name = 'Marion Thatch', model = 'g_m_m_unibanditos_01',
            coords = { x = 2310.0, y = -605.0, z = 20.0 }, heading = 0.0, money = 30, rep = 2 },
    },
    supply = { -- { post, item, amount, money, rep }: sell `amount` (or more) of `item` at that fh_trade post
        { post = 'bluewater_marsh_post', item = 'trade_cloth', amount = 2, money = 10, rep = 1 },
    },
    surveys = { -- ride-out surveys: reach every point (in order unless ordered = false). Coords TODO-verify-in-game
        { key = 'marsh_line', name = 'Marsh line', money = 24, rep = 2, ordered = true, points = {
            { x = 2300.0, y = -600.0, z = 20.0 }, -- TODO-verify-in-game
            { x = 2350.0, y = -500.0, z = 22.0 }, -- TODO-verify-in-game
            { x = 2450.0, y = -500.0, z = 25.0 }, -- TODO-verify-in-game
        } },
    },
    escorts = { -- escortee spawns at start, follows the holder to destination. Coords/model TODO-verify-in-game
        { key = 'delphine_roy', name = 'Delphine Roy', model = 'a_f_m_valtownfolk_01', heading = 90.0, money = 28, rep = 2,
            start = { x = 2300.0, y = -600.0, z = 20.0 },       -- TODO-verify-in-game
            destination = { x = 2355.0, y = -490.0, z = 25.0 }, -- TODO-verify-in-game
        },
    },
    rescues = { -- captive held at an fh_zones camp: clear that camp, then reach the captive. Coords/model TODO-verify-in-game
        { key = 'mireille_dupont', name = 'Mireille Dupont', camp = 'bluewater_marsh_t1_01', model = 'a_f_m_valtownfolk_01',
            heading = 180.0, money = 34, rep = 3,
            coords = { x = 2395.0, y = -405.0, z = 25.0 }, -- TODO-verify-in-game (beside the Marsh Ford camp)
        },
    },
})

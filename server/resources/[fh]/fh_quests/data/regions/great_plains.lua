-- great_plains job templates (fh_quests built-in job types). Coords/models are guesses: TODO-verify-in-game.
local JT = (type((...)) == 'table' and (...)) or FhQuestsJobTypes -- chunk arg in specs (table), the global in FXServer (where ... is a number)

JT.registerRegion('great_plains', {
    hunt = { -- { animal, stars, money }: deliver an N-star pelt of that animal (sold at the fh_hunting buyer)
        { 'bison', 1, 22 }, { 'bison', 2, 30 }, { 'bison', 3, 44 },
    },
    camps = { -- fh_zones camp ids (fh_zones/config.lua)
        { id = 'great_plains_t1_01', label = 'Bison Bluff camp', money = 40, rep = 3 },
    },
    bounties = { -- wanted NPCs (model/coords TODO-verify-in-game)
        { key = 'winslow_pike', name = 'Winslow Pike', model = 'g_m_m_unibanditos_01',
            coords = { x = -870.0, y = -1345.0, z = 44.0 }, heading = 270.0, money = 36, rep = 2 },
    },
    supply = { -- { post, item, amount, money, rep }: sell `amount` (or more) of `item` at that fh_trade post
        { post = 'blackwater_post', item = 'trade_salt', amount = 3, money = 9, rep = 1 },
    },
    surveys = { -- ride-out surveys: reach every point (in order unless ordered = false). Coords TODO-verify-in-game
        { key = 'plains_markers', name = 'Plains markers', money = 24, rep = 2, ordered = true, points = {
            { x = -860.0,  y = -1340.0, z = 44.0 }, -- TODO-verify-in-game
            { x = -1200.0, y = -1340.0, z = 42.0 }, -- TODO-verify-in-game
            { x = -1500.0, y = -1350.0, z = 40.0 }, -- TODO-verify-in-game
        } },
    },
    escorts = { -- escortee spawns at start, follows the holder to destination. Coords/model TODO-verify-in-game
        { key = 'inez_barlow', name = 'Inez Barlow', model = 'a_f_m_valtownfolk_01', heading = 90.0, money = 28, rep = 2,
            start = { x = -860.0, y = -1340.0, z = 44.0 },       -- TODO-verify-in-game
            destination = { x = -1500.0, y = -1350.0, z = 40.0 }, -- TODO-verify-in-game
        },
    },
    rescues = { -- captive held at an fh_zones camp: clear that camp, then reach the captive. Coords/model TODO-verify-in-game
        { key = 'clive_harrow', name = 'Clive Harrow', camp = 'great_plains_t1_01', model = 'a_m_m_valtownfolk_01',
            heading = 180.0, money = 34, rep = 3,
            coords = { x = -1595.0, y = -1345.0, z = 40.0 }, -- TODO-verify-in-game (beside the Bison Bluff camp)
        },
    },
})

-- grizzlies_east job templates (fh_quests built-in job types). Coords/models are guesses: TODO-verify-in-game.
local JT = (type((...)) == 'table' and (...)) or FhQuestsJobTypes -- chunk arg in specs (table), the global in FXServer (where ... is a number)

JT.registerRegion('grizzlies_east', {
    hunt = { -- { animal, stars, money }: deliver an N-star pelt of that animal (sold at the fh_hunting buyer)
        { 'elk', 1, 20 },
    },
    camps = { -- fh_zones camp ids (fh_zones/config.lua)
        { id = 'grizzlies_east_t1_01', label = 'Frost Creek camp', money = 40, rep = 3 },
    },
    bounties = { -- wanted NPCs (model/coords TODO-verify-in-game)
        { key = 'thaddeus_wren', name = 'Thaddeus Wren', model = 'g_m_m_unibanditos_01',
            coords = { x = 1680.0, y = 1910.0, z = 200.0 }, heading = 180.0, money = 34, rep = 2 },
    },
    supply = { -- { post, item, amount, money, rep }: sell `amount` (or more) of `item` at that fh_trade post
        { post = 'wapiti_post', item = 'trade_cloth', amount = 2, money = 10, rep = 1 },
    },
    surveys = { -- ride-out surveys: reach every point (in order unless ordered = false). Coords TODO-verify-in-game
        { key = 'frost_heights', name = 'Frost heights', money = 24, rep = 2, ordered = true, points = {
            { x = 1675.0, y = 1900.0, z = 200.0 }, -- TODO-verify-in-game
            { x = 1550.0, y = 1650.0, z = 195.0 }, -- TODO-verify-in-game
            { x = 1430.0, y = 1465.0, z = 190.0 }, -- TODO-verify-in-game
        } },
    },
    escorts = { -- escortee spawns at start, follows the holder to destination. Coords/model TODO-verify-in-game
        { key = 'nell_brightwater', name = 'Nell Brightwater', model = 'a_f_m_valtownfolk_01', heading = 90.0, money = 28, rep = 2,
            start = { x = 1675.0, y = 1900.0, z = 200.0 },       -- TODO-verify-in-game
            destination = { x = 1430.0, y = 1465.0, z = 190.0 }, -- TODO-verify-in-game
        },
    },
    rescues = { -- captive held at an fh_zones camp: clear that camp, then reach the captive. Coords/model TODO-verify-in-game
        { key = 'tansy_oakes', name = 'Tansy Oakes', camp = 'grizzlies_east_t1_01', model = 'a_f_m_valtownfolk_01',
            heading = 180.0, money = 34, rep = 3,
            coords = { x = 1385.0, y = 1385.0, z = 190.0 }, -- TODO-verify-in-game (beside the Frost Creek camp)
        },
    },
    legendaries = { -- one-shot tier-3 legendary commission (fh_hunting/data/legendaries/grizzlies_east.lua)
        { chain_id = 'legendary_frostmane_moose', legendary = 'legendary_frostmane_moose', money = 60, rep = 5, min_tier = 3 },
    },
})

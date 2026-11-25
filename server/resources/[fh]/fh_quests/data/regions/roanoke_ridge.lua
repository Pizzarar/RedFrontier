-- roanoke_ridge job templates (fh_quests built-in job types). Coords/models are guesses: TODO-verify-in-game.
local JT = (type((...)) == 'table' and (...)) or FhQuestsJobTypes -- chunk arg in specs (table), the global in FXServer (where ... is a number)

JT.registerRegion('roanoke_ridge', {
    hunt = { -- { animal, stars, money }: deliver an N-star pelt of that animal (sold at the fh_hunting buyer)
        { 'moose', 1, 26 },
    },
    camps = { -- fh_zones camp ids (fh_zones/config.lua)
        { id = 'roanoke_ridge_t1_01', label = 'Riverbend camp', money = 40, rep = 3 },
    },
    bounties = { -- wanted NPCs (model/coords TODO-verify-in-game)
        { key = 'gideon_falk', name = 'Gideon Falk', model = 'g_m_m_unibanditos_01',
            coords = { x = 2930.0, y = 1295.0, z = 96.0 }, heading = 270.0, money = 32, rep = 2 },
    },
    supply = { -- { post, item, amount, money, rep }: sell `amount` (or more) of `item` at that fh_trade post
        { post = 'annesburg_post', item = 'trade_salt', amount = 3, money = 9, rep = 1 },
    },
    surveys = { -- ride-out surveys: reach every point (in order unless ordered = false). Coords TODO-verify-in-game
        { key = 'ridge_crests', name = 'Ridge crests', money = 24, rep = 2, ordered = true, points = {
            { x = 2925.0, y = 1290.0, z = 96.0 }, -- TODO-verify-in-game
            { x = 2600.0, y = 1100.0, z = 92.0 }, -- TODO-verify-in-game
            { x = 2330.0, y = 860.0,  z = 90.0 }, -- TODO-verify-in-game
        } },
    },
    escorts = { -- escortee spawns at start, follows the holder to destination. Coords/model TODO-verify-in-game
        { key = 'cordelia_harker', name = 'Cordelia Harker', model = 'a_f_m_valtownfolk_01', heading = 90.0, money = 28, rep = 2,
            start = { x = 2925.0, y = 1290.0, z = 96.0 },       -- TODO-verify-in-game
            destination = { x = 2330.0, y = 860.0, z = 90.0 }, -- TODO-verify-in-game
        },
    },
    rescues = { -- captive held at an fh_zones camp: clear that camp, then reach the captive. Coords/model TODO-verify-in-game
        { key = 'asa_bell', name = 'Asa Bell', camp = 'roanoke_ridge_t1_01', model = 'a_m_m_valtownfolk_01',
            heading = 180.0, money = 34, rep = 3,
            coords = { x = 2255.0, y = 805.0, z = 90.0 }, -- TODO-verify-in-game (beside the Riverbend camp)
        },
    },
    legendaries = { -- one-shot tier-3 legendary commission (fh_hunting/data/legendaries/roanoke_ridge.lua)
        { chain_id = 'legendary_coalhorn_moose', legendary = 'legendary_coalhorn_moose', money = 60, rep = 5, min_tier = 3 },
    },
})

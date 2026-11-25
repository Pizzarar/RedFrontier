-- cumberland_forest job templates (fh_quests built-in job types). Coords/models are guesses: TODO-verify-in-game.
local JT = (type((...)) == 'table' and (...)) or FhQuestsJobTypes -- chunk arg in specs (table), the global in FXServer (where ... is a number)

JT.registerRegion('cumberland_forest', {
    hunt = { -- { animal, stars, money }: deliver an N-star pelt of that animal (sold at the fh_hunting buyer)
        { 'deer', 3, 18 },
    },
    camps = { -- fh_zones camp ids (fh_zones/config.lua)
        { id = 'cumberland_forest_t1_01', label = 'Rapids camp', money = 40, rep = 3 },
    },
    bounties = { -- wanted NPCs (model/coords TODO-verify-in-game)
        { key = 'barnaby_cole', name = 'Barnaby Cole', model = 'g_m_m_unibanditos_01',
            coords = { x = -820.0, y = 1350.0, z = 130.0 }, heading = 180.0, money = 30, rep = 2 },
    },
    supply = { -- { post, item, amount, money, rep }: sell `amount` (or more) of `item` at that fh_trade post
        { post = 'bacchus_station_post', item = 'trade_salt', amount = 3, money = 9, rep = 1 },
    },
    surveys = { -- ride-out surveys: reach every point (in order unless ordered = false). Coords TODO-verify-in-game
        { key = 'forest_cornerstones', name = 'Forest cornerstones', money = 24, rep = 2, ordered = true, points = {
            { x = -815.0, y = 1340.0, z = 130.0 }, -- TODO-verify-in-game
            { x = -870.0, y = 1230.0, z = 120.0 }, -- TODO-verify-in-game
            { x = -970.0, y = 1230.0, z = 110.0 }, -- TODO-verify-in-game
        } },
    },
    escorts = { -- escortee spawns at start, follows the holder to destination. Coords/model TODO-verify-in-game
        { key = 'cora_lindqvist', name = 'Cora Lindqvist', model = 'a_f_m_valtownfolk_01', heading = 90.0, money = 28, rep = 2,
            start = { x = -815.0, y = 1340.0, z = 130.0 },       -- TODO-verify-in-game
            destination = { x = -885.0, y = 1210.0, z = 110.0 }, -- TODO-verify-in-game
        },
    },
    rescues = { -- captive held at an fh_zones camp: clear that camp, then reach the captive. Coords/model TODO-verify-in-game
        { key = 'fern_ashworth', name = 'Fern Ashworth', camp = 'cumberland_forest_t1_01', model = 'a_f_m_valtownfolk_01',
            heading = 180.0, money = 34, rep = 3,
            coords = { x = -925.0, y = 1125.0, z = 110.0 }, -- TODO-verify-in-game (beside the Rapids camp)
        },
    },
    legendaries = { -- one-shot tier-3 legendary commission (fh_hunting/data/legendaries/cumberland_forest.lua)
        { chain_id = 'legendary_greyhowl_wolf', legendary = 'legendary_greyhowl_wolf', money = 60, rep = 5, min_tier = 3 },
    },
})

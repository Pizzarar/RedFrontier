-- heartlands job templates (fh_quests built-in job types). Coords/models are guesses: TODO-verify-in-game.
local JT = (type((...)) == 'table' and (...)) or FhQuestsJobTypes -- chunk arg in specs (table), the global in FXServer (where ... is a number)

JT.registerRegion('heartlands', {
    hunt = { -- { animal, stars, money [, min_tier = N] }: deliver an N-star pelt of that animal (sold at the fh_hunting buyer)
        { 'deer', 1, 6 }, { 'deer', 2, 10 }, { 'wolf', 2, 16 }, { 'wolf', 3, 24 }, { 'bear', 2, 34 }, { 'bear', 3, 50 },
        { 'elk', 3, 42, min_tier = 2 },
    },
    camps = { -- fh_zones camp ids (fh_zones/config.lua)
        { id = 'heartlands_t1_01', label = 'Heartlands outlaw camp', money = 40, rep = 3 },
        { id = 'heartlands_t2_01', label = 'Dakota South camp', money = 52, rep = 4, min_tier = 2 },
    },
    bounties = { -- wanted NPCs (model/coords TODO-verify-in-game)
        { key = 'silas_crow', name = 'Silas Crow', model = 'g_m_m_unibanditos_01',
            coords = { x = -128.0, y = 826.0, z = 117.0 }, heading = 140.0, money = 30, rep = 2 },
        { key = 'mabel_teague', name = 'Mabel Teague', model = 'g_m_m_unibanditos_01',
            coords = { x = -170.0, y = 860.0, z = 118.0 }, heading = 20.0, money = 36, rep = 2 },
        { key = 'harlan_voss', name = 'Harlan Voss', model = 'g_m_m_unibanditos_01',
            coords = { x = 510.0, y = 260.0, z = 92.0 }, heading = 210.0, money = 44, rep = 3, min_tier = 2 }, -- TODO-verify-in-game
        { key = 'calvin_dredge', name = 'Calvin Dredge', model = 'g_m_m_unibanditos_01',
            coords = { x = 690.0, y = 140.0, z = 88.0 }, heading = 35.0, money = 58, rep = 4, min_tier = 3 }, -- TODO-verify-in-game
    },
    supply = { -- { post, item, amount, money, rep }: sell `amount` (or more) of `item` at that fh_trade post
        { post = 'valentine_post', item = 'trade_cloth', amount = 2, money = 10, rep = 1 },
        { post = 'valentine_post', item = 'trade_whiskey', amount = 3, money = 26, rep = 2, min_tier = 2 },
    },
    surveys = { -- ride-out surveys: reach every point (in order unless ordered = false). Coords TODO-verify-in-game
        { key = 'ridge_markers', name = 'Ridge markers', money = 24, rep = 2, ordered = true, points = {
            { x = -260.0, y = 760.0, z = 116.0 }, -- TODO-verify-in-game
            { x = -330.0, y = 700.0, z = 118.0 }, -- TODO-verify-in-game
            { x = -410.0, y = 650.0, z = 121.0 }, -- TODO-verify-in-game
        } },
    },
    escorts = { -- escortee spawns at start, follows the holder to destination. Coords/model TODO-verify-in-game
        { key = 'doc_hollis', name = 'Doc Hollis', model = 'a_m_m_valtownfolk_01', heading = 90.0, money = 28, rep = 2,
            start = { x = -175.0, y = 627.0, z = 114.0 },       -- TODO-verify-in-game
            destination = { x = -360.0, y = 795.0, z = 116.0 }, -- TODO-verify-in-game
        },
    },
    rescues = { -- captive held at an fh_zones camp: clear that camp, then reach the captive. Coords/model TODO-verify-in-game
        { key = 'ada_brennan', name = 'Ada Brennan', camp = 'heartlands_t1_01', model = 'a_f_m_valtownfolk_01',
            heading = 180.0, money = 34, rep = 3,
            coords = { x = -143.0, y = 851.0, z = 117.0 }, -- TODO-verify-in-game (beside the Heartland Bluffs camp)
        },
        { key = 'nora_whitfield', name = 'Nora Whitfield', camp = 'heartlands_t2_01', model = 'a_f_m_valtownfolk_01',
            heading = 120.0, money = 46, rep = 4, min_tier = 3,
            coords = { x = 605.0, y = 205.0, z = 90.0 }, -- TODO-verify-in-game (beside the Dakota South camp)
        },
    },
    legendaries = { -- one-shot tier-3 legendary commission (fh_hunting/data/legendaries/heartlands.lua)
        { chain_id = 'legendary_bear', legendary = 'legendary_bear', money = 60, rep = 5, min_tier = 3 },
    },
})

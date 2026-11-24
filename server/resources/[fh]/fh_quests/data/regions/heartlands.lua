-- heartlands job templates (fh_quests built-in job types). Coords/models are guesses: TODO-verify-in-game.
local JT = (type((...)) == 'table' and (...)) or FhQuestsJobTypes -- chunk arg in specs (table), the global in FXServer (where ... is a number)

JT.registerRegion('heartlands', {
    hunt = { -- { animal, stars, money }: deliver an N-star pelt of that animal (sold at the fh_hunting buyer)
        { 'deer', 1, 6 }, { 'deer', 2, 10 }, { 'wolf', 2, 16 }, { 'wolf', 3, 24 }, { 'bear', 2, 34 }, { 'bear', 3, 50 },
    },
    camps = { -- fh_zones camp ids (fh_zones/config.lua)
        { id = 'heartlands_t1_01', label = 'Heartlands outlaw camp', money = 40, rep = 3 },
    },
    bounties = { -- wanted NPCs (model/coords TODO-verify-in-game)
        { key = 'silas_crow', name = 'Silas Crow', model = 'g_m_m_unibanditos_01',
            coords = { x = -128.0, y = 826.0, z = 117.0 }, heading = 140.0, money = 30, rep = 2 },
        { key = 'mabel_teague', name = 'Mabel Teague', model = 'g_m_m_unibanditos_01',
            coords = { x = -170.0, y = 860.0, z = 118.0 }, heading = 20.0, money = 36, rep = 2 },
    },
    supply = { -- { post, item, amount, money, rep }: sell `amount` (or more) of `item` at that fh_trade post
        { post = 'valentine_post', item = 'trade_cloth', amount = 2, money = 10, rep = 1 },
    },
    surveys = { -- ride-out surveys: reach every point (in order unless ordered = false). Coords TODO-verify-in-game
        { key = 'ridge_markers', name = 'Ridge markers', money = 24, rep = 2, ordered = true, points = {
            { x = -260.0, y = 760.0, z = 116.0 }, -- TODO-verify-in-game
            { x = -330.0, y = 700.0, z = 118.0 }, -- TODO-verify-in-game
            { x = -410.0, y = 650.0, z = 121.0 }, -- TODO-verify-in-game
        } },
    },
})

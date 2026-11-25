-- big_valley job templates (fh_quests built-in job types). Coords/models are guesses: TODO-verify-in-game.
local JT = (type((...)) == 'table' and (...)) or FhQuestsJobTypes -- chunk arg in specs (table), the global in FXServer (where ... is a number)

JT.registerRegion('big_valley', {
    hunt = { -- { animal, stars, money }: deliver an N-star pelt of that animal (sold at the fh_hunting buyer)
        { 'coyote', 1, 10 },
    },
    camps = { -- fh_zones camp ids (fh_zones/config.lua)
        { id = 'big_valley_t1_01', label = 'Creekside camp', money = 40, rep = 3 },
    },
    bounties = { -- wanted NPCs (model/coords TODO-verify-in-game)
        { key = 'orville_crane', name = 'Orville Crane', model = 'g_m_m_unibanditos_01',
            coords = { x = -1820.0, y = -450.0, z = 120.0 }, heading = 180.0, money = 32, rep = 2 },
    },
    supply = { -- { post, item, amount, money, rep }: sell `amount` (or more) of `item` at that fh_trade post
        { post = 'strawberry_post', item = 'trade_cloth', amount = 2, money = 10, rep = 1 },
    },
    surveys = { -- ride-out surveys: reach every point (in order unless ordered = false). Coords TODO-verify-in-game
        { key = 'valley_survey', name = 'Valley survey', money = 24, rep = 2, ordered = true, points = {
            { x = -1815.0, y = -445.0, z = 120.0 }, -- TODO-verify-in-game
            { x = -1700.0, y = -650.0, z = 105.0 }, -- TODO-verify-in-game
            { x = -1685.0, y = -805.0, z = 90.0 },  -- TODO-verify-in-game
        } },
    },
    escorts = { -- escortee spawns at start, follows the holder to destination. Coords/model TODO-verify-in-game
        { key = 'marta_vasquez', name = 'Marta Vasquez', model = 'a_f_m_valtownfolk_01', heading = 90.0, money = 28, rep = 2,
            start = { x = -1815.0, y = -445.0, z = 120.0 },       -- TODO-verify-in-game
            destination = { x = -1685.0, y = -805.0, z = 90.0 }, -- TODO-verify-in-game
        },
    },
    rescues = { -- captive held at an fh_zones camp: clear that camp, then reach the captive. Coords/model TODO-verify-in-game
        { key = 'eamon_grady', name = 'Eamon Grady', camp = 'big_valley_t1_01', model = 'a_m_m_valtownfolk_01',
            heading = 180.0, money = 34, rep = 3,
            coords = { x = -1655.0, y = -895.0, z = 90.0 }, -- TODO-verify-in-game (beside the Creekside camp)
        },
    },
    legendaries = { -- one-shot tier-3 legendary commission (fh_hunting/data/legendaries/big_valley.lua)
        { chain_id = 'legendary_copperhide_deer', legendary = 'legendary_copperhide_deer', money = 60, rep = 5, min_tier = 3 },
    },
})

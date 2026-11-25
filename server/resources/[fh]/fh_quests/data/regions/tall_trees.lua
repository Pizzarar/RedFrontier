-- tall_trees job templates (fh_quests built-in job types). Coords/models are guesses: TODO-verify-in-game.
local JT = (type((...)) == 'table' and (...)) or FhQuestsJobTypes -- chunk arg in specs (table), the global in FXServer (where ... is a number)

JT.registerRegion('tall_trees', {
    hunt = { -- { animal, stars, money }: deliver an N-star pelt of that animal (sold at the fh_hunting buyer)
        { 'wolf', 1, 14 },
    },
    camps = { -- fh_zones camp ids (fh_zones/config.lua)
        { id = 'tall_trees_t1_01', label = 'Pine Flats camp', money = 40, rep = 3 },
    },
    bounties = { -- wanted NPCs (model/coords TODO-verify-in-game)
        { key = 'lucille_grange', name = 'Lucille Grange', model = 'g_m_m_unibanditos_01',
            coords = { x = -1805.0, y = -1610.0, z = 150.0 }, heading = 270.0, money = 34, rep = 2 },
    },
    supply = { -- { post, item, amount, money, rep }: sell `amount` (or more) of `item` at that fh_trade post
        { post = 'manzanita_post', item = 'trade_whiskey', amount = 1, money = 16, rep = 1 },
    },
    surveys = { -- ride-out surveys: reach every point (in order unless ordered = false). Coords TODO-verify-in-game
        { key = 'timber_line', name = 'Timber line', money = 24, rep = 2, ordered = true, points = {
            { x = -1800.0, y = -1600.0, z = 150.0 }, -- TODO-verify-in-game
            { x = -1950.0, y = -1620.0, z = 140.0 }, -- TODO-verify-in-game
            { x = -2050.0, y = -1635.0, z = 130.0 }, -- TODO-verify-in-game
        } },
    },
    escorts = { -- escortee spawns at start, follows the holder to destination. Coords/model TODO-verify-in-game
        { key = 'odessa_finch', name = 'Odessa Finch', model = 'a_f_m_valtownfolk_01', heading = 90.0, money = 28, rep = 2,
            start = { x = -1800.0, y = -1600.0, z = 150.0 },       -- TODO-verify-in-game
            destination = { x = -2050.0, y = -1635.0, z = 130.0 }, -- TODO-verify-in-game
        },
    },
    rescues = { -- captive held at an fh_zones camp: clear that camp, then reach the captive. Coords/model TODO-verify-in-game
        { key = 'wren_gale', name = 'Wren Gale', camp = 'tall_trees_t1_01', model = 'a_f_m_valtownfolk_01',
            heading = 180.0, money = 34, rep = 3,
            coords = { x = -2145.0, y = -1645.0, z = 130.0 }, -- TODO-verify-in-game (beside the Pine Flats camp)
        },
    },
    legendaries = { -- one-shot tier-3 legendary commission (fh_hunting/data/legendaries/tall_trees.lua)
        { chain_id = 'legendary_embercoat_coyote', legendary = 'legendary_embercoat_coyote', money = 60, rep = 5, min_tier = 3 },
    },
})

-- fh_trade tuning (spec L6 regional price model). Pure data: no natives. Global FhTradeConfig.
-- All coordinates are APPROXIMATE and unverified in game (stand at the spot, read coords, adjust).
FhTradeConfig = {
    seed = 1337,                  -- seeds the price wobble; change it to reshuffle the whole world's drift
    maxSellPerTx = 100,           -- units per sale request
    minMultiplier = 0.1,          -- final price is never below base * this
    wobble = { amplitude = 0.08, periodSeconds = 3600 },                        -- slow deterministic drift around baseline (+-8%)
    shortage = { gain = 1.0, max = 1.0, halfLifeSeconds = 7200, threshold = 0.15, reliefPerUnit = 0.02 },
    saturation = { capacityUnits = 40, maxDrop = 0.5, halfLifeSeconds = 3600 }, -- 40 units into one region = -50% (before recovery)
    saveMs = 60000,               -- flush dirty price rows at most this often

    -- Trade goods. Registered from this resource via fh_core.registerItems (never in fh_core's config).
    -- base = baseline $ per unit; the item fields mirror fh_core/shared/items.lua.
    goods = {
        trade_salt    = { label = 'Salt Sack',     base = 6,  weight = 1500,  size_class = 'pocket', stackable = true, value_base = 6 },
        trade_cloth   = { label = 'Bolt of Cloth', base = 14, weight = 2500,  size_class = 'pocket', stackable = true, value_base = 14 },
        trade_whiskey = { label = 'Whiskey Crate', base = 40, weight = 15000, size_class = 'cargo',  stackable = true, value_base = 40 },
    },

    -- Supplies the post SELLS to players (idea-716/719): flat whole-dollar price per unit, unlimited stock, every post.
    -- Never touches the price model above (no shortage/saturation/wobble). Priced just above the items' value_base
    -- (lumber 2, nails/lead/casings 1, herbs/gunpowder 0) so buying-to-sell never profits; trade goods sell at 6-40.
    maxBuyPerTx = 100,            -- units per buy request
    supplies = {
        lumber = 3, nails = 2,                                  -- homestead builds (fh_homestead)
        lead = 2, casings = 2, resource_gunpowder = 3,          -- reload bench ammo (fh_crafting)
        herb_american_ginseng = 3, herb_oregano = 3, herb_red_sage = 3, herb_wild_mint = 3, -- apothecary tonics
    },

    -- Regional baseline factor on top of goods[item].base. Unlisted = 1.0. Region ids from fh_core shared/regions.lua.
    -- Scarlett Meadows (Rhodes) prices differ from the Heartlands by design (spec L6 "regional price model").
    regionFactor = {
        heartlands = { trade_salt = 1.0, trade_cloth = 1.1, trade_whiskey = 0.9 },
        scarlett_meadows = { trade_salt = 1.1, trade_cloth = 0.9, trade_whiskey = 1.2 },
    },

    -- Trade posts (server checks the player is within `radius` of the post). `region` must be a known region id.
    -- Coordinates APPROXIMATE / unverified in game (Rhodes general store, Scarlett Meadows).
    posts = {
        { id = 'valentine_post', label = 'Valentine Trade Post', region = 'heartlands', x = -176.0, y = 630.0, z = 114.0, radius = 6.0 },
        { id = 'rhodes_post', label = 'Rhodes Trade Post', region = 'scarlett_meadows', x = 1288.0, y = -1278.0, z = 77.0, radius = 6.0 },
    },

    -- Freight contracts (R4): a fh_quests job type generated from shortages. Destinations are where your OWN wagon
    -- (holding the cargo) must be to deliver. APPROXIMATE, unverified in game.
    freight = {
        minQty = 1, maxQty = 20,       -- cargo units per contract
        qtyPerLevel = 20,              -- qty = ceil(shortage level * this), clamped
        premium = 1.25,                -- reward = qty * current quote * premium
        repDelta = 2,                  -- rep gained at the destination region
        deadlineSeconds = 1800,        -- from accept
        maxOffers = 3, rewardCapMultiple = 4,
        cooldownMin = 30,              -- fh_quests cooldown_min: minutes before the same route/cargo offer can be taken again (= deadline)
        maxActivePerPlayer = 2,
        allowSameRegion = false,       -- two regions exist now: offers are generated between them (set true to test one-region)
        checkMs = 5000, graceChecks = 3, -- delivery/loss scan period; consecutive misses before wagon/cargo loss counts
        acceptReach = 8.0,             -- m: your wagon must be this close to you to take a contract
        destinations = {
            heartlands = { x = -176.0, y = 630.0, z = 114.0, radius = 40.0 },
            scarlett_meadows = { x = 1288.0, y = -1278.0, z = 77.0, radius = 40.0 }, -- Rhodes trade post (unverified)
        },
    },

    -- Initial shortages (data): seeded at startup ONLY while the region/item has no persisted shortage, so a fresh
    -- server already produces freight offers in both directions (heartlands -> scarlett and back). The seed is marked
    -- dirty and persists/decays like any other shortage; `fh_trade_shortage` can re-set it anytime.
    initialShortages = {
        { region = 'scarlett_meadows', item = 'trade_whiskey', level = 0.6 }, -- heartlands board -> haul whiskey to Rhodes
        { region = 'heartlands',       item = 'trade_salt',    level = 0.5 }, -- Rhodes board     -> haul salt to Valentine
    },
}

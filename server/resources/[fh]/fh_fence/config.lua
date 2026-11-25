-- Fence config. Region ids come from fh_core/shared/regions.lua; never define new ones here.
-- Stop coords are APPROXIMATE (Heartlands): verify in game and adjust.
FhFenceConfig = {
    dwellMinutes = 20,                                    -- how long the fence stays at each stop
    rotation = { 'heartlands_road', 'heartlands_camp' },  -- stop ids, visited in this order, then repeat
    range = 6.0,                                          -- metres: player must be this close to the current stop
    maxQty = 20,                                          -- per buy/sell request
    fenceId = 'roving',                                   -- fence_stash id: fh:fence:<citizenid>:<fenceId>
    lockStaleSeconds = 120,                               -- a trade lock this old is reclaimable (hung await)
    npc = { kind = 'ped', model = 'u_m_m_valtownfolk_01' }, -- placeholder model, verify in game

    stops = {
        heartlands_road = {
            region_id = 'heartlands', label = 'Roadside Fence',
            coords = { x = -280.0, y = 800.0, z = 118.0, h = 90.0 },
        },
        heartlands_camp = {
            region_id = 'heartlands', label = 'Camp-Edge Fence',
            coords = { x = -170.0, y = 830.0, z = 117.0, h = 180.0 },
        },
    },

    -- Items this resource registers via fh_core registerItems (register only).
    items = {
        fh_part_gunsmith = { label = 'Gunsmith Parts',    weight = 500, size_class = 'pocket', value_base = 40, illicit = true },
        fh_part_saddlery = { label = 'Saddlery Fittings', weight = 600, size_class = 'pocket', value_base = 45, illicit = true },
        fh_treasure_lead = { label = 'Treasure Lead',     weight = 50,  size_class = 'pocket', value_base = 0, stackable = false },
    },

    -- Stock per stop. Entries: { item, price }. A `leads` entry names its spot by an opaque id (lead = '<id>'); the
    -- coords + hint live in the SERVER-ONLY server/config_leads.lua (this file is shared: clients download it). The
    -- id is all the bought item's info holds. An id missing there is not sold.
    -- common: always; rare: needs fh_progression canUnlock('fence_rare_stock'); leads: 'fence_treasure_leads'.
    stock = {
        heartlands_road = {
            common = { { item = 'bread', price = 3 }, { item = 'water', price = 2 } },
            rare   = { { item = 'fh_part_gunsmith', price = 90 } },
            leads  = { { item = 'fh_treasure_lead', price = 250, lead = 'lead_hl_01' } },
        },
        heartlands_camp = {
            common = { { item = 'bread', price = 3 } },
            rare   = { { item = 'fh_part_gunsmith', price = 95 }, { item = 'fh_part_saddlery', price = 100 } },
            leads  = { { item = 'fh_treasure_lead', price = 300, lead = 'lead_hl_02' } },
        },
    },

    -- What the fence buys from players: item -> price per unit.
    buys = { fh_part_gunsmith = 30, fh_part_saddlery = 35 },

    -- Treasure lead dig (progression-02 G2, server/leads.lua + shared/leads_logic.lua).
    -- digRadius: metres (3D, server-side ped coords) from the lead's spot (server/config_leads.lua) within which a dig
    -- counts.
    -- areaRadius: radius of the map blip; its centre is offset from the target (the blip never marks the spot).
    -- loot: weighted outcomes, ONE is rolled per dig. money = { min, max } dollars (whole, paid via fh_economy pay);
    -- item/qty = a part added to the backpack (room checked before the lead is taken). Keep max money under
    -- fh_economy maxPay. regionId: pay region when the lead's spot is sold at no stop (e.g. a pre-G2b lead whose stored
    -- target matches no spot any more).
    leads = {
        item = 'fh_treasure_lead',
        digRadius = 8.0,
        areaRadius = 60.0,
        cooldownSeconds = 3,       -- min gap between two dig attempts of one character
        lockStaleSeconds = 120,    -- a dig lock this old is reclaimable (hung await)
        regionId = 'heartlands',
        loot = {
            { weight = 50, money = { 150, 300 } },
            { weight = 25, money = { 100, 200 }, item = 'fh_part_gunsmith', qty = 2 },
            { weight = 15, money = { 100, 200 }, item = 'fh_part_saddlery', qty = 2 },
            { weight = 10, money = { 400, 700 } },
        },
    },
}

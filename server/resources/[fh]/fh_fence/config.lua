-- Fence config. Region ids come from fh_core/shared/regions.lua; never define new ones here.
-- Stop coords are APPROXIMATE (Heartlands): verify in game and adjust.
FhFenceConfig = {
    dwellMinutes = 20,                                    -- how long the fence stays at each stop
    rotation = { 'heartlands_road', 'heartlands_camp' },  -- stop ids, visited in this order, then repeat
    range = 6.0,                                          -- metres: player must be this close to the current stop
    maxQty = 20,                                          -- per buy/sell request
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

    -- Stock per stop. Entries: { item, price }. A `lead` entry carries target coords + hint, written to item info.
    -- common: always; rare: needs fh_progression canUnlock('fence_rare_stock'); leads: 'fence_treasure_leads'.
    stock = {
        heartlands_road = {
            common = { { item = 'bread', price = 3 }, { item = 'water', price = 2 } },
            rare   = { { item = 'fh_part_gunsmith', price = 90 } },
            leads  = { { item = 'fh_treasure_lead', price = 250,
                         lead = { coords = { x = -520.0, y = 910.0, z = 120.0 }, hint = 'Where the old rail line meets the creek.' } } },
        },
        heartlands_camp = {
            common = { { item = 'bread', price = 3 } },
            rare   = { { item = 'fh_part_gunsmith', price = 95 }, { item = 'fh_part_saddlery', price = 100 } },
            leads  = { { item = 'fh_treasure_lead', price = 300,
                         lead = { coords = { x = -60.0, y = 760.0, z = 116.0 }, hint = 'Under the split oak east of the ridge.' } } },
        },
    },

    -- What the fence buys from players: item -> price per unit.
    buys = { fh_part_gunsmith = 30, fh_part_saddlery = 35 },
}

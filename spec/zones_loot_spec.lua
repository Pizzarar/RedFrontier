-- world-02 (block E): the fh_zones lootByFaction contract — every faction (alias excluded) ships T1-T3 loot tables,
-- every loot item id exists in the item registry, every camp's owner faction + tier resolves to a table, and the old
-- flat [faction] -> table shape (v1) still resolves through pickLootTable (backward compat).
-- Run: `python tools/run-specs.py spec/zones_loot_spec.lua`.
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local case, eq = T.it, T.eq
local fh = here .. '../server/resources/[fh]/'
local rsg = here .. '../server/resources/[rsg]/'

local R = dofile(fh .. 'fh_zones/shared/camp_rules.lua')
local coreConfig = require('config')

-- Set _G.FhRegions/_G.FhPlaceResolver + vector3 (world-02 block F), then load fh_zones/config.lua (resolves camps).
local regions = dofile(here .. 'support/world_config.lua')
dofile(fh .. 'fh_zones/config.lua')
local cfg = FhZonesConfig

-- Item registry: the union of every item definition a loot table may name, across fh_core, fh_zones, fh_crafting,
-- fh_survival and rsg-core. An item id is "existing" iff it appears in one of these.
local known = {}
local function addItems(tbl)
    for name in pairs(tbl or {}) do known[name] = true end
end
addItems(coreConfig.Items or {})
addItems(cfg.items or {})
addItems(dofile(fh .. 'fh_crafting/config.lua').items or {})
addItems(dofile(fh .. 'fh_survival/shared/items.lua').ITEMS or {})
dofile(rsg .. 'rsg-core/shared/items.lua')
addItems((RSGShared and RSGShared.Items) or {})

local TIERS = { T1 = true, T2 = true, T3 = true }

case('lootByFaction keys are exactly the non-alias factions', function()
    local want = {}
    for id, f in pairs(regions.factions) do if not f.alias_of then want[id] = true end end
    for id in pairs(cfg.lootByFaction) do assert(want[id], 'unexpected lootByFaction key ' .. tostring(id)) end
    for id in pairs(want) do assert(cfg.lootByFaction[id], 'missing lootByFaction key ' .. tostring(id)) end
end)

case('rhodes_law is an alias of lawmen, not a separate loot key', function()
    eq('lawmen', regions.getFaction('rhodes_law').id)
    eq(nil, cfg.lootByFaction.rhodes_law)
end)

case('every faction (alias excluded) has exactly T1-T3 loot tables', function()
    for id, f in pairs(regions.factions) do
        if not f.alias_of then
            assert(type(cfg.lootByFaction[id]) == 'table', id .. ' missing lootByFaction entry')
            for tier in pairs(TIERS) do
                assert(type(cfg.lootByFaction[id][tier]) == 'table', id .. ' missing ' .. tier .. ' table')
            end
            for tier in pairs(cfg.lootByFaction[id]) do
                assert(TIERS[tier], id .. ' has unexpected tier key ' .. tostring(tier))
            end
        end
    end
end)

case('every loot entry is a non-empty list of { name, chance } entries', function()
    for faction, tiers in pairs(cfg.lootByFaction) do
        for tier, tbl in pairs(tiers) do
            assert(type(tbl) == 'table' and #tbl >= 1, faction .. '/' .. tier .. ' is not a non-empty list')
            for _, e in ipairs(tbl) do
                assert(type(e.name) == 'string' and type(e.chance) == 'number',
                    faction .. '/' .. tier .. ' malformed entry ' .. tostring(e and e.name))
            end
        end
    end
end)

case('item registry is populated (dollar/ammo/fh foods/tools known)', function()
    assert(known.dollar and known.ammo_box_revolver and known.fh_jerky and known.resource_coal and known.tonic_healing,
        'registry empty or incomplete')
end)

case('every loot item id exists in the item registry', function()
    local bad = {}
    for faction, tiers in pairs(cfg.lootByFaction) do
        for tier, tbl in pairs(tiers) do
            for _, e in ipairs(tbl) do
                if not known[e.name] then bad[#bad + 1] = faction .. '/' .. tier .. ': ' .. tostring(e.name) end
            end
        end
    end
    table.sort(bad)
    assert(#bad == 0, 'unknown item ids: ' .. table.concat(bad, ', '))
end)

case('every camp resolves its tier through its territory to a tiered loot table', function()
    for id, camp in pairs(cfg.camps) do
        local terr = regions.getTerritory(camp.territory)
        assert(terr, id .. ' missing territory')
        -- tier comes from the territory (camp carries no tier field); never hardcoded
        local tier = camp.tier or (terr or {}).tier
        assert(type(tier) == 'string', id .. ' no territory tier')
        local owner = regions.getFaction(terr.faction)
        assert(owner, id .. ' missing faction ' .. tostring(terr.faction))
        local tbl = R.pickLootTable(cfg.lootByFaction, owner.id, camp.loot.table, tier)
        eq(cfg.lootByFaction[owner.id][tier], tbl, id .. ' tiered table ' .. owner.id .. '/' .. tostring(tier))
    end
end)

case('legacy rhodes_law owner canonicalises to lawmen before the loot lookup', function()
    local camp = cfg.camps.heartlands_t1_01
    local tier = (regions.getTerritory(camp.territory) or {}).tier
    assert(type(tier) == 'string', 'no territory tier')
    local owner = 'rhodes_law'
    local f = regions.getFaction(owner)
    owner = f and f.id or owner
    eq('lawmen', owner)
    eq(cfg.lootByFaction.lawmen[tier], R.pickLootTable(cfg.lootByFaction, owner, camp.loot.table, tier))
end)

case('old flat [faction] -> table shape still resolves (backward compat)', function()
    local flat = { { name = 'worn_rifle', chance = 1.0, amount = 1 } }
    eq(flat, R.pickLootTable({ outlaws = flat }, 'outlaws', nil))
    eq(flat, R.pickLootTable({ outlaws = flat }, 'outlaws', nil, 'T1'))
end)

T.finish()

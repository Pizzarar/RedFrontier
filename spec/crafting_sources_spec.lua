-- Every item a recipe or homestead build consumes must have a registered source (idea-712, plan crafting-01-l5).
-- Pure: loads configs only, no natives. Run: `python tools/run-specs.py spec/crafting_sources_spec.lua`.
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local it = T.it
local fh = here .. '../server/resources/[fh]/'
local Recipes = dofile(fh .. 'fh_crafting/shared/recipes.lua')
dofile(here .. 'support/world_config.lua') -- FhRegions + FhPlaceResolver + vector3 (world-02 block F)
dofile(fh .. 'fh_homestead/config.lua')   -- outside CfxLua there is no vector3: config falls back to {x,y,z}
dofile(fh .. 'fh_trade/config.lua')
dofile(fh .. 'fh_zones/config.lua')
dofile(fh .. 'fh_crafting/config.lua')  -- herbPatches (idea-720 herb gathering, plan crafting-02 C9)

-- PENDING: input item -> owning card that will add its source. TARGET: PENDING = {} (shrink it as cards land).
-- idea-716/719 landed: lumber, nails, lead, casings, resource_gunpowder and the 4 herbs are FhTradeConfig.supplies;
-- gun_parts (idea-717) is zone loot (core-05 K1). Cooking inputs (crafting-03 C10a) wait on idea-914/915.
local PENDING = {
    raw_meat = 'idea-914', -- @hunting skin grant (plan crafting-03)
    carrot = 'idea-915', potato = 'idea-915', corn = 'idea-915', -- @roads supplies (plan crafting-03)
}

-- External sources (outside [fh]). An entry needs a CONFIRMED in-game way to obtain the item (a gatherer, shop or
-- drop you can point at); an item definition alone is not a source. Empty today.
local EXTERNAL = {}

-- Required inputs: item -> list of consumers.
local inputs = {}
local function need(item, who) inputs[item] = inputs[item] or {}; table.insert(inputs[item], who) end
for _, r in ipairs(Recipes.list) do for _, i in ipairs(r.inputs) do need(i.item, 'recipe ' .. r.id) end end
-- Non-recipe consumer: /fh_restore takes gun_parts (fh_gunsmith shared/restore_flow.lua:95).
need('gun_parts', '/fh_restore')
for plotId, plot in pairs(FhHomesteadConfig.plots) do
    for slotId, slot in pairs(plot.slots) do
        for tier, t in pairs(slot.tiers) do
            for item in pairs((t.cost or {}).items or {}) do need(item, ('build %s %s t%d'):format(plotId, slotId, tier)) end
        end
    end
end

-- Sources. Trade `supplies`: scan defensively (item->price map, or list of { item = .. } / { name = .. } / strings).
local sources = {}
-- A string key that is a known input is an item whatever its value (item -> price | item -> { price = .. });
-- other string keys with table values are region/post nesting and are recursed into.
local function addSupplies(s, known, out, depth)
    depth = depth or 0
    if type(s) ~= 'table' or depth > 4 then return end
    for k, v in pairs(s) do
        if type(k) == 'string' and known[k] then out[k] = 'trade supplies'
        elseif type(k) == 'string' and type(v) == 'table' then addSupplies(v, known, out, depth + 1)
        elseif type(k) == 'string' then out[k] = 'trade supplies'
        elseif type(v) == 'string' then out[v] = 'trade supplies'
        elseif type(v) == 'table' and (v.item or v.name) then out[v.item or v.name] = 'trade supplies'
        elseif type(v) == 'table' then addSupplies(v, known, out, depth + 1) end
    end
end
local function scan(t, depth, seen)
    if type(t) ~= 'table' or depth > 5 or seen[t] then return end
    seen[t] = true
    for k, v in pairs(t) do
        if k == 'supplies' then addSupplies(v, inputs, sources) else scan(v, depth + 1, seen) end
    end
end
scan(FhTradeConfig, 0, {})
for _, camp in pairs(FhZonesConfig.camps or {}) do
    for _, e in ipairs(((camp.loot or {}).table) or {}) do sources[e.name or e.item] = 'zone loot' end
end
-- Herb gathering (idea-720): each patch names a herb the player can pick in the world. A second source for the
-- herbs (buying at trade posts stays); gathering is free but slow.
for _, patch in ipairs(FhCraftingConfig.herbPatches or {}) do
    if type(patch) == 'table' and type(patch.herb) == 'string' then sources[patch.herb] = 'herb gathering' end
end
for item in pairs(EXTERNAL) do sources[item] = sources[item] or 'external' end

it('addSupplies handles item->{price=} and region->{item=price} shapes (fake config)', function()
    local known = { lumber = true, nails = true, lead = true }
    local o1 = {}
    addSupplies({ lumber = { price = 5 }, nails = { price = 1 } }, known, o1)
    assert(o1.lumber and o1.nails, 'item -> { price = } not recorded')
    assert(not o1.price, 'price field leaked as an item')
    local o2 = {}
    addSupplies({ heartlands = { lead = 3, lumber = 4 } }, known, o2)
    assert(o2.lead and o2.lumber, 'region -> { item = price } not recorded')
    assert(not o2.heartlands, 'region key recorded as an item')
end)

it('source configs loaded (so the PENDING checks cannot go silent)', function()
    assert(type(FhTradeConfig) == 'table', 'FhTradeConfig missing: renamed?')
    assert(type(FhZonesConfig) == 'table' and type(FhZonesConfig.camps) == 'table' and next(FhZonesConfig.camps) ~= nil,
        'FhZonesConfig.camps missing or empty: renamed?')
    assert(type(FhCraftingConfig) == 'table' and type(FhCraftingConfig.herbPatches) == 'table'
        and #FhCraftingConfig.herbPatches > 0, 'FhCraftingConfig.herbPatches missing or empty: renamed?')
end)

it('herb gathering (idea-720) sources the four herbs', function()
    for _, herb in ipairs({ 'herb_american_ginseng', 'herb_oregano', 'herb_red_sage', 'herb_wild_mint' }) do
        assert(sources[herb] == 'herb gathering', herb .. ' not sourced by gathering (got ' .. tostring(sources[herb]) .. ')')
    end
end)

it('every required input has a source or is PENDING', function()
    local bad = {}
    for item, who in pairs(inputs) do
        if not sources[item] and not PENDING[item] then bad[#bad + 1] = item .. ' (' .. who[1] .. ')' end
    end
    table.sort(bad)
    assert(#bad == 0, 'unsourced inputs, add a source or PENDING entry: ' .. table.concat(bad, ', '))
end)

it('PENDING items still have no source (set must shrink to empty)', function()
    for item, card in pairs(PENDING) do
        assert(not sources[item], ('remove %s from PENDING (now sourced via %s; was %s)'):format(item, tostring(sources[item]), card))
    end
end)

it('PENDING holds only real inputs', function()
    for item in pairs(PENDING) do assert(inputs[item], 'PENDING has ' .. item .. ' which is not a recipe/build input') end
end)

it('EXTERNAL allowlist holds only real inputs', function()
    for item in pairs(EXTERNAL) do assert(inputs[item], 'EXTERNAL has ' .. item .. ' which is not an input') end
end)

T.finish()

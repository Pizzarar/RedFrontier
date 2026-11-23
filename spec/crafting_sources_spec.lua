-- Every item a recipe or homestead build consumes must have a registered source (idea-712, plan crafting-01-l5).
-- Pure: loads configs only, no natives. Run: `python tools/run-specs.py spec/crafting_sources_spec.lua`.
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local it = T.it
local fh = here .. '../server/resources/[fh]/'
local Recipes = dofile(fh .. 'fh_crafting/shared/recipes.lua')
dofile(fh .. 'fh_homestead/config.lua')   -- outside CfxLua there is no vector3: config falls back to {x,y,z}
dofile(fh .. 'fh_trade/config.lua')
vector3 = vector3 or function(x, y, z) return { x = x, y = y, z = z } end -- fh_zones config needs it
dofile(fh .. 'fh_zones/config.lua')

-- PENDING: input item -> owning card that will add its source. TARGET: PENDING = {} (shrink it as cards land).
local PENDING = {
    lumber   = 'idea-716', nails = 'idea-716', lead = 'idea-716', casings = 'idea-716', -- trade post `supplies`
    -- bought via the same trade post `supplies` list (idea-718 ruling); herb gathering is a parked later spike
    resource_gunpowder = 'idea-716', herb_american_ginseng = 'idea-716', herb_oregano = 'idea-716',
    herb_red_sage = 'idea-716', herb_wild_mint = 'idea-716',
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

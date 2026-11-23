-- Run from repo root: `lua spec/homestead_items_spec.lua` (or via tools/run-specs.py).
-- H2d: fh_homestead build materials (lumber, nails) really pass fh_core's registerItems validation, resolve after
-- registration (so /fh_give works) and every item named in a slot tier cost is defined in cfg.buildItems.
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local case = T.it
local fh = here .. '../server/resources/[fh]/'

dofile(fh .. 'fh_homestead/config.lua')
local cfg = assert(_G.FhHomesteadConfig, 'config defines FhHomesteadConfig')
local Args = dofile(fh .. 'fh_core/shared/admin_args.lua')

local function freshCore()
    _G.FhConfig = { Items = {} }
    local Core = dofile(fh .. 'fh_core/shared/items.lua')
    Core._reset()
    return Core
end

local function notBase() return false end

case('buildItems pass fh_core registerItems validation', function()
    local saved = _G.FhConfig
    local Core = freshCore()
    local ok, err, bad = Core.checkRegister(cfg.buildItems, 'fh_homestead', notBase)
    assert(ok, tostring(err) .. ' / ' .. tostring(bad))
    for name, def in pairs(cfg.buildItems) do
        assert(Core.validName(name), name)
        assert(def.illicit == false, name .. ' has explicit illicit')
    end
    ok, err = Core.register(cfg.buildItems, 'fh_homestead', notBase)
    assert(ok, tostring(err))
    assert(Core.register(cfg.buildItems, 'fh_homestead', notBase), 'fh_core restart: re-register is fine')
    _G.FhConfig = saved
end)

case('lumber and nails resolve after registration (so /fh_give works)', function()
    local saved = _G.FhConfig
    local Core = freshCore()
    local known = function(n) return Core.resolve(n) ~= nil end
    -- before registration /fh_give refuses them
    local p, err = Args.parseGive({ '1', 'lumber', '5' }, known)
    assert(p == nil and err == 'fh_unknown_item', tostring(err))
    assert(Core.resolve('lumber') == nil)
    assert(Core.register(cfg.buildItems, 'fh_homestead', notBase))
    local lumber, nails = Core.resolve('lumber'), Core.resolve('nails')
    assert(lumber and lumber.size_class == 'pocket' and lumber.weight == 500 and lumber.stackable == true and lumber.illicit == false)
    assert(nails and nails.size_class == 'pocket' and nails.weight == 10 and nails.stackable == true and nails.illicit == false)
    p, err = Args.parseGive({ '1', 'lumber', '5' }, known)
    assert(p and p.item == 'lumber' and p.count == 5, tostring(err))
    p = Args.parseGive({ '1', 'nails' }, known)
    assert(p and p.item == 'nails')
    _G.FhConfig = saved
end)

case('build.lua registerItems handles the registerItems return shape', function()
    -- build.lua: ok, res, err, bad = pcall(exports.fh_core:registerItems); success = ok and res (true), failure = false, err, bad
    local saved = _G.FhConfig
    local Core = freshCore()
    local ok, res = pcall(function() return Core.register(cfg.buildItems, 'fh_homestead', notBase) end)
    assert(ok and res == true)
    local ok2, res2, err2, bad2 = pcall(function() return Core.register({ Bad = cfg.buildItems.lumber }, 'fh_homestead', notBase) end)
    assert(ok2 and res2 == false and err2 == 'fh_bad_item_name' and bad2 == 'Bad')
    _G.FhConfig = saved
end)

case('every slot tier cost item is defined in buildItems', function()
    local n = 0
    for plotId, plot in pairs(cfg.plots) do
        for slotId, slot in pairs(plot.slots) do
            for tier, t in pairs(slot.tiers) do
                for item, count in pairs((t.cost and t.cost.items) or {}) do
                    n = n + 1
                    assert(cfg.buildItems[item], ('%s/%s tier %s costs undefined item %s'):format(plotId, slotId, tostring(tier), item))
                    assert(type(count) == 'number' and count > 0)
                end
            end
        end
    end
    assert(n > 0, 'cost items were visited')
end)

T.finish()

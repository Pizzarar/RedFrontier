-- Run from repo root: `lua spec/hunting_registry_boot_spec.lua` (or via tools/run-specs.py).
-- FXServer-mode boot of fh_hunting's shared + pure server scripts, in fxmanifest order, with LoadResourceFile serving
-- the real data files plus bad ones. Pins (L1 review MEDIUM): an entry whose id is a plain animal key or whose
-- species_model has no plain row is rejected by the registry itself, so FhHuntingLegendaries, FhHuntingChain,
-- FhHuntingTrophies and FhHuntingAnimals all agree it does not exist; and every warning is printed at resource start.
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local describe, it, eq, same = T.describe, T.it, T.eq, T.same
local root = here .. '../server/resources/[fh]/'
local base = root .. 'fh_hunting/'

local function slurp(path)
    local f = assert(io.open(path, 'r'))
    local s = f:read('a')
    f:close()
    return s
end

---The script list of one fxmanifest block (`shared_scripts { ... }`), in order.
local function manifestBlock(name)
    local body = assert(slurp(base .. 'fxmanifest.lua'):match(name .. '%s*(%b{})'), name)
    local out = {}
    for s in body:gmatch("'([^']+)'") do out[#out + 1] = s end
    return out
end

local function resolve(script)
    local res, rel = script:match('^@([^/]+)/(.+)$')
    if res then return root .. res .. '/' .. rel end
    return base .. script
end

---Boot in FXServer mode. `files` = { [relPath] = source } overriding LoadResourceFile; `pre(G)` runs before the boot.
---@return string[] printed lines
local function boot(files, pre)
    local printed, realPrint = {}, print
    GetCurrentResourceName = function() return 'fh_hunting' end
    LoadResourceFile = function(res, path)
        assert(res == 'fh_hunting', res)
        if files[path] ~= nil then return files[path] end
        local f = io.open(base .. path, 'r')
        if not f then return nil end
        local s = f:read('a')
        f:close()
        return s
    end
    print = function(...)
        local parts = {}
        for i = 1, select('#', ...) do parts[i] = tostring((select(i, ...))) end
        printed[#printed + 1] = table.concat(parts, '\t')
    end
    if pre then pre() end
    local ok, err = pcall(function()
        for _, s in ipairs(manifestBlock('shared_scripts')) do
            if s ~= '@ox_lib/init.lua' then dofile(resolve(s)) end
        end
        for _, s in ipairs(manifestBlock('server_scripts')) do
            if not s:match('^@') and s ~= 'server/main.lua' then dofile(resolve(s)) end
        end
    end)
    print = realPrint
    if not ok then error(err, 0) end
    return printed
end

local BAD = {
    -- id = a plain animal key (the plain wolf) in an enabled region
    great_plains = [[return {
        id = 'wolf', label = 'Legendary Wolf', species_model = 'a_c_wolf',
        pelt = { item = 'pelt_wolf', label = 'Legendary Wolf Pelt', value = 50, weight = 20000, image = 'p.png' },
        trophy = { item = 'trophy_wolf', label = 'Legendary Wolf Trophy', comfort = 20 },
        rumour = { coords = { x = 0, y = 0, z = 10 }, price = 30, label = 'Ask about it' },
        markers = { [2] = { label = 'Prints', coords = { x = 50, y = 0, z = 10 } },
            [3] = { label = 'Remains', coords = { x = 100, y = 0, z = 10 } } },
        spawn = { coords = { x = 150, y = 0, z = 10 } },
    }]],
    -- species_model with no plain row
    roanoke_ridge = [[return {
        id = 'legendary_panther', label = 'Legendary Panther', species_model = 'a_c_panther_01',
        pelt = { item = 'pelt_legendary_panther', label = 'Pelt', value = 50, weight = 20000, image = 'p.png' },
        trophy = { item = 'trophy_legendary_panther', label = 'Trophy', comfort = 20 },
        rumour = { coords = { x = 900, y = 0, z = 10 }, price = 30, label = 'Ask about it' },
        markers = { [2] = { label = 'Prints', coords = { x = 950, y = 0, z = 10 } },
            [3] = { label = 'Remains', coords = { x = 1000, y = 0, z = 10 } } },
        spawn = { coords = { x = 1050, y = 0, z = 10 } },
    }]],
}

describe('hunting registry boot (FXServer mode, fxmanifest order)', function()
    local files = {}
    for rid, src in pairs(BAD) do files['data/legendaries/' .. rid .. '.lua'] = src end
    local printed = boot(files)
    local L, A, Tr, Chain = FhHuntingLegendaries, FhHuntingAnimals, FhHuntingTrophies, FhHuntingChain

    it('boots: every global is set and the real bear is served', function()
        assert(FhHuntingPlainAnimals and L and A and Tr and Chain, 'a global is missing')
        eq('legendary_bear', L:get('legendary_bear').id)
        eq('pelt_legendary_bear', A.get('a_c_bear_01', 'legendary_bear').pelt)
        eq(25, Tr.getComfort('trophy_legendary_bear'))
    end)
    it('a colliding id and an unknown species_model are absent from every consumer', function()
        eq(true, FhRegions.isEnabled('great_plains'))
        same({ 'legendary_bear' }, (function()
            local ids = {}
            for _, e in ipairs(L.list) do ids[#ids + 1] = e.id end
            return ids
        end)())
        eq(nil, L:get('wolf')); eq(nil, L:get('legendary_panther'))
        eq(nil, L.byRegion.great_plains); eq(nil, L.byRegion.roanoke_ridge)
        for _, e in ipairs(L:active()) do assert(e.id ~= 'wolf' and e.id ~= 'legendary_panther', e.id) end
        -- animals: the plain wolf row is untouched and is not a legendary; no panther row or items
        eq('pelt_wolf', A.byKey.wolf.pelt); eq(nil, A.byKey.wolf.legendary)
        eq(nil, A.byLegendary.wolf); eq(nil, A.get('a_c_wolf', 'wolf'))
        eq(nil, A.byKey.legendary_panther); eq(nil, A.get('a_c_panther_01', 'legendary_panther'))
        local defs = A.itemDefs()
        eq(nil, defs.trophy_wolf); eq(nil, defs.pelt_legendary_panther); eq(nil, defs.trophy_legendary_panther)
        same({}, A.warnings) -- the registry rejected them, so animals.lua had nothing left to skip
        -- trophies
        eq(nil, Tr.getComfort('trophy_wolf')); eq(nil, Tr.getComfort('trophy_legendary_panther'))
        -- chain: unknown, nothing charged
        local charged = 0
        local c = Chain.new({ cfg = FhHuntingConfig, deps = {
            load = function() end, save = function() return true end,
            charge = function() charged = charged + 1; return true end,
            spawn = function() return 1 end, despawn = function() end, emit = function() end,
        } })
        for _, id in ipairs({ 'wolf', 'legendary_panther' }) do
            eq('fh_chain_unknown', select(2, c.buyRumour(1, 'CID', { x = 0, y = 0, z = 10 }, id)))
        end
        eq(0, charged)
    end)
    it('the loader warnings are printed at resource start', function()
        same({ 'great_plains: id wolf collides with a plain animal',
            'roanoke_ridge: species_model a_c_panther_01 has no plain animal row' }, L.warnings)
        local want = {}
        for _, w in ipairs(L.warnings) do want[#want + 1] = '^3[fh_hunting] legendaries: ' .. w .. '^7' end
        same(want, printed)
    end)
    it("animals.lua's own warnings are printed too (a registry that bypassed the loader check)", function()
        local plainWolf = FhHuntingPlainAnimals.byKey.wolf
        local out = boot({}, function()
            -- animals.lua reads the FhHuntingLegendaries global; swap in a hand-built registry after legendaries.lua
            local realDofile = dofile
            dofile = function(path)
                local r = realDofile(path)
                if path:match('shared/legendaries%.lua$') then
                    FhHuntingLegendaries = { list = { { id = 'wolf', label = 'X', species_model = 'a_c_wolf',
                        region_id = 'great_plains', pelt = { item = 'pelt_wolf2', value = 1, weight = 1, image = 'i' },
                        trophy = { item = 'trophy_wolf2', comfort = 1 } } } }
                    dofile = realDofile
                end
                return r
            end
        end)
        same({ 'legendary wolf collides with an existing animal or item' }, FhHuntingAnimals.warnings)
        same({ '^3[fh_hunting] animals: legendary wolf collides with an existing animal or item^7' }, out)
        eq(plainWolf.pelt, FhHuntingAnimals.byKey.wolf.pelt)
    end)
end)

GetCurrentResourceName, LoadResourceFile = nil, nil
T.finish()

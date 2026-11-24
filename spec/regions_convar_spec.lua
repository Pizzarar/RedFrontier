-- Run from repo root: `~/.venvs/rf/bin/python tools/run-specs.py spec/regions_convar_spec.lua`.
-- world-03 (block I): `setr fh_regions_enabled "a,b,..."` replaces the static `enabled` flags in FhRegions.isEnabled.
-- Unset / empty / blank = data flags; set = only the listed known ids; unknown ids logged once and ignored; whitespace
-- and case tolerated; unknown ids passed to isEnabled stay false (fail closed). GetConvar is stubbed per case.
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local it, eq = T.it, T.eq
local fh = here .. '../server/resources/[fh]/'

local regions = dofile(here .. 'support/world_config.lua')

local logs = {}
regions.log = function(msg) logs[#logs + 1] = msg end

local function withConvar(value, fn)
    local prev = _G.GetConvar
    _G.GetConvar = function(name, default)
        if name == 'fh_regions_enabled' then
            if value == nil then return default end
            return value
        end
        return default
    end
    local ok, err = pcall(fn)
    _G.GetConvar = prev
    if not ok then error(err, 0) end
end

local function dataFlag(id) return regions.regions[id].enabled == true end

it('without GetConvar (plain Lua / specs) the data flags apply', function()
    assert(_G.GetConvar == nil, 'expected no GetConvar global in specs')
    for id in pairs(regions.regions) do eq(dataFlag(id), regions.isEnabled(id), id) end
end)

it('unset (GetConvar returns the default) -> data flags', function()
    withConvar(nil, function()
        for id in pairs(regions.regions) do eq(dataFlag(id), regions.isEnabled(id), id) end
    end)
end)

it('empty string and blank string count as unset -> data flags', function()
    for _, v in ipairs({ '', '   ', ' , ,', '\t' }) do
        withConvar(v, function()
            for id in pairs(regions.regions) do eq(dataFlag(id), regions.isEnabled(id), id .. ' with "' .. v .. '"') end
        end)
    end
end)

it('set -> only the listed ids are enabled (data flags ignored both ways)', function()
    assert(dataFlag('heartlands') and not dataFlag('roanoke_ridge'), 'fixture assumption')
    withConvar('roanoke_ridge,rio_bravo', function()
        eq(true, regions.isEnabled('roanoke_ridge'))
        eq(true, regions.isEnabled('rio_bravo'))
        eq(false, regions.isEnabled('heartlands'), 'data-enabled region not listed must be off')
        eq(false, regions.isEnabled('scarlett_meadows'))
    end)
end)

it('whitespace and case are tolerated (commas and/or spaces separate)', function()
    withConvar('  Heartlands ,ROANOKE_RIDGE   Big_Valley,,', function()
        eq(true, regions.isEnabled('heartlands'))
        eq(true, regions.isEnabled('roanoke_ridge'))
        eq(true, regions.isEnabled('big_valley'))
        eq(false, regions.isEnabled('bayou_nwa'))
    end)
end)

it('unknown ids in the convar are logged once and ignored', function()
    logs = {}
    withConvar('heartlands,atlantis', function()
        eq(true, regions.isEnabled('heartlands'))
        eq(false, regions.isEnabled('atlantis'), 'unknown id must stay closed even when listed')
        eq(false, regions.isEnabled('bayou_nwa'))
        regions.isEnabled('heartlands')
    end)
    withConvar('Atlantis, scarlett_meadows', function() -- new value, same unknown id: not logged again
        eq(true, regions.isEnabled('scarlett_meadows'))
    end)
    eq(1, #logs, 'log count')
    assert(logs[1]:find('atlantis', 1, true) and logs[1]:find('fh_regions_enabled', 1, true), logs[1])
end)

it('a list of only unknown ids enables nothing', function()
    withConvar('atlantis2', function()
        for id in pairs(regions.regions) do eq(false, regions.isEnabled(id), id) end
    end)
end)

it('isEnabled keeps failing closed for unknown / non-string ids, set or unset', function()
    for _, v in ipairs({ false, 'heartlands' }) do
        withConvar(v or nil, function()
            eq(false, regions.isEnabled('nowhere'))
            eq(false, regions.isEnabled(nil))
            eq(false, regions.isEnabled(42))
        end)
    end
end)

it('the convar is read at call time (a changed value applies to the next call)', function()
    withConvar('heartlands', function() eq(false, regions.isEnabled('rio_bravo')) end)
    withConvar('rio_bravo', function() eq(true, regions.isEnabled('rio_bravo')) end)
    eq(dataFlag('rio_bravo'), regions.isEnabled('rio_bravo'), 'back to data flags once GetConvar is gone')
end)

it('a GetConvar that throws falls back to the data flags', function()
    local prev = _G.GetConvar
    _G.GetConvar = function() error('boom') end
    local ok, err = pcall(function()
        for id in pairs(regions.regions) do eq(dataFlag(id), regions.isEnabled(id), id) end
    end)
    _G.GetConvar = prev
    assert(ok, err)
end)

it('fh_zones camp.enabled follows the convar at config load (camps wake in a region switched on)', function()
    withConvar('roanoke_ridge', function()
        dofile(fh .. 'fh_zones/config.lua')
        local n = 0
        for id, c in pairs(_G.FhZonesConfig.camps) do
            eq(c.region == 'roanoke_ridge', c.enabled, id)
            if c.region == 'roanoke_ridge' then n = n + 1 end
        end
        assert(n >= 3, 'expected roanoke_ridge camps, got ' .. n)
    end)
    dofile(fh .. 'fh_zones/config.lua')
    for id, c in pairs(_G.FhZonesConfig.camps) do eq(dataFlag(c.region), c.enabled, id .. ' (unset)') end
end)

T.finish()

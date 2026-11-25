-- Run from repo root: `lua spec/ui_trappers_spec.lua` (or via tools/run-specs.py).
-- Spec coverage for ui-i2-lows:
--   1. fh_hunting/server/trappers_export.lua (getTrappers): enabled-region filter, fresh copies, read-only, FXServer export path.
--   2. fh_ui/server/main.lua (fh:ui:trappers callback): returns export list; nil + cfg.Trapper fallback when absent or erroring.
--   3. fh_ui/client/trappers.lua + blips.lua + where.lua: shared cached helper, stale blips & /where cache cleared on
--      onResourceStop('fh_hunting') -> fallback trapper, refetched on onResourceStart('fh_hunting').
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local case, eq, same = T.it, T.eq, T.same

local fhBase = here .. '../server/resources/[fh]/'
local P = dofile(fhBase .. 'fh_ui/shared/places.lua')

-- Helper: run fn with temporary global overrides, restoring every touched global even on error.
local function withGlobals(overrides, fn)
    local saved = {}
    for k, v in pairs(overrides) do
        saved[k] = _G[k]
        if v == '__NIL__' then _G[k] = nil else _G[k] = v end
    end
    local ok, err = pcall(fn)
    for k, v in pairs(saved) do _G[k] = v end
    if not ok then error(err, 2) end
end

local function loadHuntingDeps()
    local regions = dofile(fhBase .. 'fh_core/shared/regions.lua')
    local hCfg = dofile(fhBase .. 'fh_hunting/config.lua')
    local wagon = dofile(fhBase .. 'fh_hunting/shared/wagon.lua')
    local sell
    withGlobals({ FhHuntingWagon = wagon }, function()
        sell = dofile(fhBase .. 'fh_hunting/shared/sell.lua')
    end)
    local leg = dofile(fhBase .. 'fh_hunting/shared/legendaries.lua')
    return regions, hCfg, sell, leg
end

case('fh_hunting getTrappers: filters to enabled regions via FhRegions.isEnabled', function()
    local regions, hCfg, sell, leg = loadHuntingDeps()

    -- 1) Synthetic FhRegions.isEnabled: only heartlands + scarlett_meadows enabled.
    local enabled = { heartlands = true, scarlett_meadows = true }
    withGlobals({
        FhHuntingSell = sell,
        FhHuntingConfig = hCfg,
        FhHuntingLegendaries = leg,
        FhRegions = { isEnabled = function(rid) return enabled[rid] == true end },
        exports = '__NIL__',
    }, function()
        local getTrappers = dofile(fhBase .. 'fh_hunting/server/trappers_export.lua')
        local list = getTrappers()
        eq(2, #list)
        local byRegion = {}
        for _, t in ipairs(list) do
            byRegion[t.region_id] = t
            eq(true, enabled[t.region_id])
            assert(type(t.label) == 'string' and t.label ~= '', 'label present')
            assert(type(t.coords) == 'table' and type(t.coords.x) == 'number', 'coords present')
        end
        assert(byRegion.heartlands, 'heartlands included')
        assert(byRegion.scarlett_meadows, 'scarlett_meadows included')
        eq(nil, byRegion.bayou_nwa)
    end)

    -- 2) Real FhRegions.isEnabled: matches every enabled region in sell.trappers.
    withGlobals({
        FhHuntingSell = sell,
        FhHuntingConfig = hCfg,
        FhHuntingLegendaries = leg,
        FhRegions = regions,
        exports = '__NIL__',
    }, function()
        local getTrappers = dofile(fhBase .. 'fh_hunting/server/trappers_export.lua')
        local list = getTrappers()
        local all = sell.trappers(hCfg, leg)
        local expected = 0
        for _, t in ipairs(all) do
            if regions.isEnabled(t.region_id) then expected = expected + 1 end
        end
        eq(expected, #list)
        eq(true, #list >= 1)
        for _, t in ipairs(list) do
            eq(true, regions.isEnabled(t.region_id))
        end
    end)
end)

case('fh_hunting getTrappers: returns fresh copies and is read-only (mutating result does not change config)', function()
    local regions, hCfg, sell, leg = loadHuntingDeps()
    local origLabel = hCfg.Trapper.label
    local origX, origY, origZ = hCfg.Trapper.coords.x, hCfg.Trapper.coords.y, hCfg.Trapper.coords.z
    local origLegLabel = leg.byRegion.heartlands.trapper.label
    local origLegX = leg.byRegion.heartlands.trapper.coords.x

    withGlobals({
        FhHuntingSell = sell,
        FhHuntingConfig = hCfg,
        FhHuntingLegendaries = leg,
        FhRegions = { isEnabled = function(rid) return rid == 'heartlands' end },
        exports = '__NIL__',
    }, function()
        local getTrappers = dofile(fhBase .. 'fh_hunting/server/trappers_export.lua')
        local first = getTrappers()
        eq(1, #first)
        eq('heartlands', first[1].region_id)

        -- Mutate every field of the returned result and append a bogus entry.
        first[1].label = 'MUTATED'
        first[1].region_id = 'evil_region'
        first[1].coords.x = 999999
        first[1].coords.y = -999999
        first[1].coords.z = 0
        first[2] = { region_id = 'injected', label = 'Fake', coords = { x = 0, y = 0, z = 0 } }

        -- Config and legendaries registry are completely untouched.
        eq(origLabel, hCfg.Trapper.label)
        eq(origX, hCfg.Trapper.coords.x)
        eq(origY, hCfg.Trapper.coords.y)
        eq(origZ, hCfg.Trapper.coords.z)
        eq(origLegLabel, leg.byRegion.heartlands.trapper.label)
        eq(origLegX, leg.byRegion.heartlands.trapper.coords.x)

        -- A second call returns fresh tables with the original values.
        local second = getTrappers()
        eq(1, #second)
        assert(second ~= first, 'fresh outer array')
        assert(second[1] ~= first[1], 'fresh entry table')
        assert(second[1].coords ~= first[1].coords, 'fresh coords table')
        eq('heartlands', second[1].region_id)
        eq(origLabel, second[1].label)
        same({ x = origX, y = origY, z = origZ }, second[1].coords)
    end)
end)

case('fh_hunting getTrappers: FXServer exports() registration and fxmanifest presence', function()
    local regions, hCfg, sell, leg = loadHuntingDeps()
    local registered = {}
    withGlobals({
        FhHuntingSell = sell,
        FhHuntingConfig = hCfg,
        FhHuntingLegendaries = leg,
        FhRegions = regions,
        exports = function(name, fn) registered[name] = fn end,
    }, function()
        dofile(fhBase .. 'fh_hunting/server/trappers_export.lua')
        assert(type(registered.getTrappers) == 'function', 'registered getTrappers export')
        local list = registered.getTrappers()
        eq(true, type(list) == 'table' and #list >= 1)
    end)

    -- Presence-only check on fh_hunting/fxmanifest.lua (never assert exact full lists; hunting-1050 adds chain_export/chainState).
    local f = assert(io.open(fhBase .. 'fh_hunting/fxmanifest.lua', 'r'))
    local manifest = f:read('*a')
    f:close()
    assert(manifest:find("server/trappers_export.lua", 1, true), 'trappers_export.lua listed in fh_hunting fxmanifest')
    assert(manifest:find("'getTrappers'", 1, true), 'getTrappers present in fh_hunting fxmanifest')
end)

-- Helper: load fh_ui/server/main.lua with stubbed FXServer globals and return its registered callbacks.
local function loadUiServer(state)
    local callbacks = {}
    local relay = dofile(fhBase .. 'fh_ui/shared/relay.lua')
    local env = {
        FhUiRelay = relay,
        FhUiFixtures = { fixtures = {}, parseDemo = function() return nil, 'bad' end },
        RegisterNetEvent = function() end,
        AddEventHandler = function() end,
        RegisterCommand = function() end,
        lib = { callback = { register = function(name, fn) callbacks[name] = fn end } },
        GetResourceState = function(res) return state.resourceState[res] or 'missing' end,
        exports = state.exports,
    }
    return env, callbacks
end

case('fh:ui:trappers server callback: returns fh_hunting getTrappers list when started', function()
    local regions, hCfg, sell, leg = loadHuntingDeps()
    local getTrappers
    withGlobals({
        FhHuntingSell = sell,
        FhHuntingConfig = hCfg,
        FhHuntingLegendaries = leg,
        FhRegions = { isEnabled = function(rid) return rid == 'heartlands' or rid == 'scarlett_meadows' end },
        exports = '__NIL__',
    }, function()
        getTrappers = dofile(fhBase .. 'fh_hunting/server/trappers_export.lua')
        local state = {
            resourceState = { fh_hunting = 'started' },
            exports = { fh_hunting = { getTrappers = function() return getTrappers() end } },
        }
        local env, callbacks = loadUiServer(state)
        withGlobals(env, function()
            dofile(fhBase .. 'fh_ui/server/main.lua')
            assert(type(callbacks['fh:ui:trappers']) == 'function', 'fh:ui:trappers registered')
            local list = callbacks['fh:ui:trappers']()
            eq(2, #list)
            local places = P.gather({ hunting = hCfg, trappers = list }, {
                isEnabled = function(rid) return rid == 'heartlands' or rid == 'scarlett_meadows' end,
            })
            eq(2, #places)
        end)
    end)
end)

case('fh:ui:trappers server callback: returns nil (cfg.Trapper fallback) when fh_hunting is absent or errors', function()
    local _, hCfg = loadHuntingDeps()
    local state = {
        resourceState = { fh_hunting = 'stopped' },
        exports = { fh_hunting = {} },
    }
    local env, callbacks = loadUiServer(state)
    withGlobals(env, function()
        dofile(fhBase .. 'fh_ui/server/main.lua')
        local cb = callbacks['fh:ui:trappers']

        -- 1) fh_hunting stopped / absent
        eq(nil, cb())
        local fb1 = P.gather({ hunting = hCfg, trappers = cb() })
        eq(1, #fb1)
        eq('trapper', fb1[1].kind)
        eq(hCfg.Trapper.label, fb1[1].label)

        -- 2) fh_hunting started, but getTrappers export missing
        state.resourceState.fh_hunting = 'started'
        state.exports.fh_hunting = {}
        eq(nil, cb())

        -- 3) fh_hunting export throws an error
        state.exports.fh_hunting = { getTrappers = function() error('boom') end }
        eq(nil, cb())

        -- 4) fh_hunting export returns non-table
        state.exports.fh_hunting = { getTrappers = function() return 'not_a_table' end }
        eq(nil, cb())
        local fb4 = P.gather({ hunting = hCfg, trappers = cb() })
        eq(1, #fb4)
        eq(hCfg.Trapper.label, fb4[1].label)
    end)
end)

-- Helper: tiny synchronous FH + event bus stub for client/trappers.lua, blips.lua, where.lua.
local function makeClientBus()
    local handlers = {}
    local fh = {
        on = function(ev, fn)
            handlers[ev] = handlers[ev] or {}
            handlers[ev][#handlers[ev] + 1] = fn
        end,
        thread = function(fn) fn() end,
    }
    local function fire(ev, ...)
        for _, fn in ipairs(handlers[ev] or {}) do fn(...) end
    end
    return fh, fire
end

case('client/trappers.lua: FXServer load path, caches fetch, clears on stop and refetches on start', function()
    local fh, fire = makeClientBus()
    local calls = 0
    local serverList = {
        { region_id = 'heartlands', label = 'Trapper', coords = { x = -299, y = 792, z = 118 } },
        { region_id = 'scarlett_meadows', label = 'Scarlett Meadows Trapper', coords = { x = 1265, y = -1305, z = 77 } },
    }
    local noticed = {}

    withGlobals({
        FH = fh,
        GetCurrentResourceName = function() return 'fh_ui' end,
        FhUiTrappers = '__NIL__',
        lib = { callback = { await = function(name)
            if name == 'fh:ui:trappers' then
                calls = calls + 1
                return serverList
            end
        end } },
    }, function()
        dofile(fhBase .. 'fh_ui/client/trappers.lua')
        assert(type(FhUiTrappers) == 'table', 'FXServer load sets FhUiTrappers global')
        FhUiTrappers.onChange(function(list) noticed[#noticed + 1] = list == nil and 'NIL' or #list end)

        -- Cached across repeated fetch() calls
        local a = FhUiTrappers.fetch()
        local b = FhUiTrappers.fetch()
        eq(2, #a)
        eq(a, b)
        eq(1, calls)

        -- onResourceStop('fh_hunting'): clears cache, notifies nil, fetch() returns nil without hitting server
        fire('onResourceStop', 'fh_hunting')
        eq('NIL', noticed[1])
        eq(nil, FhUiTrappers.fetch())
        eq(1, calls)

        -- onResourceStart('fh_hunting'): refetches, updates cache, notifies fresh list
        serverList = {
            { region_id = 'heartlands', label = 'Trapper', coords = { x = -299, y = 792, z = 118 } },
            { region_id = 'scarlett_meadows', label = 'Scarlett Meadows Trapper', coords = { x = 1265, y = -1305, z = 77 } },
            { region_id = 'lemoyne', label = 'Lemoyne Trapper', coords = { x = 2100, y = -1100, z = 42 } },
        }
        fire('onResourceStart', 'fh_hunting')
        eq(2, calls)
        eq(3, noticed[2])
        eq(3, #FhUiTrappers.fetch())
        eq(2, calls) -- served from refreshed cache
    end)
end)

case('client/blips.lua: clears per-region trapper blips on fh_hunting stop (falls back) and refetches on start', function()
    local fh, fire = makeClientBus()
    local nextId = 0
    local active = {}
    local serverList = {
        { region_id = 'heartlands', label = 'Trapper', coords = { x = -299, y = 792, z = 118 } },
        { region_id = 'scarlett_meadows', label = 'Scarlett Meadows Trapper', coords = { x = 1265, y = -1305, z = 77 } },
    }

    local function activeLabels()
        local out = {}
        for _, info in pairs(active) do out[#out + 1] = info.label end
        table.sort(out)
        return out
    end

    withGlobals({
        FH = fh,
        FhUiPlaces = P,
        FhUiConfig = { blips = true },
        FhRegions = { isEnabled = function(rid) return rid == 'heartlands' or rid == 'scarlett_meadows' end },
        FhHuntingConfig = { Trapper = { region_id = 'heartlands', label = 'Trapper', coords = { x = -299, y = 792, z = 118 } } },
        FhHomesteadConfig = '__NIL__', FhTradeConfig = '__NIL__', FhZonesConfig = '__NIL__',
        FhCraftingConfig = '__NIL__', FhFenceConfig = '__NIL__', FhQuestsGivers = '__NIL__', FhQuestsBoardSpots = '__NIL__',
        GetCurrentResourceName = function() return 'fh_ui' end,
        FhUiTrappers = '__NIL__',
        joaat = function(s) return s end,
        SetBlipSprite = function() end,
        SetBlipScale = function() end,
        RemoveBlip = function(id) active[id] = nil end,
        Citizen = { InvokeNative = function(hash, a, b)
            if hash == 0x554D9D53F696D002 then
                nextId = nextId + 1
                active[nextId] = { label = '' }
                return nextId
            elseif hash == 0x9CB1A1623062F402 then
                if active[a] then active[a].label = b end
            end
        end },
        lib = { callback = { await = function(name)
            if name == 'fh:ui:trappers' then return serverList end
        end } },
    }, function()
        dofile(fhBase .. 'fh_ui/client/trappers.lua')
        dofile(fhBase .. 'fh_ui/client/blips.lua')
        same({ 'Scarlett Meadows Trapper', 'Trapper' }, activeLabels())

        -- fh_hunting stops: per-region trapper blip removed, fallback heartlands trapper remains
        fire('onResourceStop', 'fh_hunting')
        same({ 'Trapper' }, activeLabels())

        -- fh_hunting starts again: refetches and restores per-region trapper blips
        fire('onResourceStart', 'fh_hunting')
        same({ 'Scarlett Meadows Trapper', 'Trapper' }, activeLabels())

        -- fh_ui stops: all blips cleared
        fire('onResourceStop', 'fh_ui')
        same({}, activeLabels())
    end)
end)

case('client/where.lua: uses shared FhUiTrappers cache, falls back on fh_hunting stop, refetches on start', function()
    local fh, fire = makeClientBus()
    local commands = {}
    local chats = {}
    local fetchCount = 0
    local serverList = {
        { region_id = 'heartlands', label = 'Trapper', coords = { x = -299, y = 792, z = 118 } },
        { region_id = 'scarlett_meadows', label = 'Scarlett Meadows Trapper', coords = { x = 1265, y = -1305, z = 77 } },
    }

    withGlobals({
        FH = fh,
        FhUiPlaces = P,
        FhRegions = { isEnabled = function(rid) return rid == 'heartlands' or rid == 'scarlett_meadows' end },
        FhHuntingConfig = { Trapper = { region_id = 'heartlands', label = 'Trapper', coords = { x = -299, y = 792, z = 118 } } },
        FhHomesteadConfig = '__NIL__', FhTradeConfig = '__NIL__', FhZonesConfig = '__NIL__',
        FhCraftingConfig = '__NIL__', FhFenceConfig = '__NIL__', FhQuestsGivers = '__NIL__', FhQuestsBoardSpots = '__NIL__',
        GetCurrentResourceName = function() return 'fh_ui' end,
        FhUiTrappers = '__NIL__',
        PlayerPedId = function() return 1 end,
        GetEntityCoords = function() return { x = 1260, y = -1300, z = 77 } end,
        RegisterCommand = function(name, fn) commands[name] = fn end,
        TriggerEvent = function(ev, payload)
            if ev == 'chat:addMessage' then chats[#chats + 1] = payload.args[2] end
        end,
        joaat = function(s) return s end,
        SetBlipSprite = function() end,
        SetBlipScale = function() end,
        RemoveBlip = function() end,
        Citizen = { InvokeNative = function(hash)
            if hash == 0x554D9D53F696D002 then return 1 end
        end },
        lib = { callback = { await = function(name)
            if name == 'fh:ui:trappers' then
                fetchCount = fetchCount + 1
                return serverList
            end
            if name == 'fh:ui:plot_claims' then return {} end
            if name == 'fh:ui:show_ids' then return false end
        end } },
    }, function()
        dofile(fhBase .. 'fh_ui/client/trappers.lua')
        dofile(fhBase .. 'fh_ui/client/where.lua')

        -- Near Scarlett Meadows: /where trapper picks Scarlett Meadows Trapper and caches list
        commands.where(0, { 'trapper' })
        assert(chats[#chats]:find('Scarlett Meadows Trapper', 1, true), 'picked regional trapper: ' .. tostring(chats[#chats]))
        eq(1, fetchCount)

        -- Second /where trapper reuses cached list (no extra callback)
        commands.where(0, { 'trapper' })
        eq(1, fetchCount)

        -- fh_hunting stops: cached list dropped, /where trapper falls back to heartlands Trapper
        fire('onResourceStop', 'fh_hunting')
        commands.where(0, { 'trapper' })
        assert(chats[#chats]:find('Trapper (trapper_heartlands)', 1, true), 'fell back to heartlands trapper: ' .. tostring(chats[#chats]))
        eq(1, fetchCount)

        -- fh_hunting starts again: refetches, /where trapper picks Scarlett Meadows Trapper again
        fire('onResourceStart', 'fh_hunting')
        eq(2, fetchCount)
        commands.where(0, { 'trapper' })
        assert(chats[#chats]:find('Scarlett Meadows Trapper', 1, true), 'restored regional trapper: ' .. tostring(chats[#chats]))
    end)
end)

T.finish()

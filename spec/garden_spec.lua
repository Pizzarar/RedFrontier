-- Homestead H18: pure garden rules (shared/garden.lua + config.lua garden block).
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local case = T.it
local dir = here .. '../server/resources/[fh]/fh_homestead/'
local rsgItemsPath = here .. '../server/resources/[rsg]/rsg-core/shared/items.lua'

dofile(dir .. 'config.lua')
local G = dofile(dir .. 'shared/garden.lua')

case('default config defines beds=3, 2h growth, yield=3, and seed->veg mapping for existing rsg-core items', function()
    local gcfg = FhHomesteadConfig.garden
    assert(type(gcfg) == 'table')
    T.eq(3, G.beds())
    T.eq(7200, gcfg.growthSeconds)
    T.eq(3, gcfg.yield)

    T.eq('carrot', G.seedToCrop('seedcarrot'))
    T.eq('potato', G.seedToCrop('seedpotato'))
    T.eq('corn', G.seedToCrop('seedcorn'))

    local def = G.cropForSeed('seedcarrot')
    T.eq('seedcarrot', def.seed)
    T.eq('carrot', def.item)
    T.eq(7200, def.growthSeconds)
    T.eq(3, def.yield)

    -- Verify every configured seed and harvested veg item exists in rsg-core/shared/items.lua
    local env = setmetatable({ RSGShared = {} }, { __index = _G })
    assert(loadfile(rsgItemsPath, 't', env))()
    local items = env.RSGShared.Items
    assert(type(items) == 'table')
    for seed, entry in pairs(gcfg.crops) do
        assert(items[seed] ~= nil, 'missing rsg-core seed item: ' .. tostring(seed))
        assert(items[entry.item] ~= nil, 'missing rsg-core veg item: ' .. tostring(entry.item))
    end
end)

case('ready: not ready before timer, ready at and after timer', function()
    local t0 = 1700000000
    T.eq(false, G.ready(t0, t0, 'seedcarrot'))
    T.eq(false, G.ready(t0, t0 + 3600, 'seedcarrot'))
    T.eq(false, G.ready(t0, t0 + 7199, 'seedcarrot'))
    T.eq(true, G.ready(t0, t0 + 7200, 'seedcarrot'))
    T.eq(true, G.ready(t0, t0 + 7201, 'seedcarrot'))
    T.eq(true, G.ready(t0, t0 + 86400, 'seedpotato'))
    -- also works when passed the harvested crop/veg name or crop def table
    T.eq(false, G.ready(t0, t0 + 7199, 'carrot'))
    T.eq(true, G.ready(t0, t0 + 7200, 'carrot'))
    T.eq(true, G.ready(t0, t0 + 7200, G.cropForSeed('seedcorn')))
    -- remaining seconds helper
    T.eq(1, G.remaining(t0, t0 + 7199, 'seedcarrot'))
    T.eq(0, G.remaining(t0, t0 + 7200, 'seedcarrot'))
    T.eq(0, G.remaining(t0, t0 + 9000, 'seedcarrot'))
end)

case('unknown seed refused with nil, fh_unknown_seed', function()
    for _, bad in ipairs({ 'seedweed', 'seedapple', 'carrot_seed', '', 'unknown', 123, true, {} }) do
        local def, err = G.cropForSeed(bad)
        T.eq(nil, def)
        T.eq('fh_unknown_seed', err)

        local item, err2 = G.seedToCrop(bad)
        T.eq(nil, item)
        T.eq('fh_unknown_seed', err2)

        local y, err3 = G.yield(bad)
        T.eq(nil, y)
        T.eq('fh_unknown_seed', err3)

        T.eq(false, G.ready(1000, 100000, bad))
    end
    local defN, errN = G.cropForSeed(nil)
    T.eq(nil, defN); T.eq('fh_unknown_seed', errN)
    local yN, errYN = G.yield(nil)
    T.eq(nil, yN); T.eq('fh_unknown_seed', errYN)
end)

case('yield from config for all configured crops', function()
    T.eq(3, G.yield('seedcarrot'))
    T.eq(3, G.yield('seedpotato'))
    T.eq(3, G.yield('seedcorn'))
    T.eq(3, G.yield('carrot'))
    T.eq(3, G.yield('potato'))
    T.eq(3, G.yield('corn'))
end)

case('config override changes growth and yield (garden defaults and per-crop)', function()
    local custom = {
        beds = 5,
        growthSeconds = 600,
        yield = 4,
        crops = {
            seedcarrot = { item = 'carrot' },
            seedpotato = { item = 'potato', growthSeconds = 1200, yield = 6 },
            seedcorn   = { item = 'corn', growthSeconds = 0, yield = 2 },
        },
    }
    T.eq(5, G.beds(custom))
    -- inherits garden default override
    T.eq(600, G.growthSeconds('seedcarrot', custom))
    T.eq(4, G.yield('seedcarrot', custom))
    T.eq(false, G.ready(100, 699, 'seedcarrot', custom))
    T.eq(true, G.ready(100, 700, 'seedcarrot', custom))
    -- per-crop override wins over garden default
    T.eq(1200, G.growthSeconds('seedpotato', custom))
    T.eq(6, G.yield('seedpotato', custom))
    T.eq(false, G.ready(100, 1299, 'seedpotato', custom))
    T.eq(true, G.ready(100, 1300, 'seedpotato', custom))
    -- 0-second growth is ready immediately when now >= plantedAt, not before
    T.eq(true, G.ready(100, 100, 'seedcorn', custom))
    T.eq(false, G.ready(100, 99, 'seedcorn', custom))
    T.eq(2, G.yield('seedcorn', custom))
    -- also accepts full config wrapper { garden = custom }
    T.eq(6, G.yield('seedpotato', { garden = custom }))
end)

case('bad inputs (nil, negative, NaN, inf, clock skew) are safe', function()
    T.eq(false, G.ready(nil, 10000, 'seedcarrot'))
    T.eq(false, G.ready(1000, nil, 'seedcarrot'))
    T.eq(false, G.ready(nil, nil, 'seedcarrot'))
    T.eq(false, G.ready(-1, 10000, 'seedcarrot'))
    T.eq(false, G.ready(0, -1, 'seedcarrot'))
    T.eq(false, G.ready(-100, -1, 'seedcarrot'))
    T.eq(false, G.ready(0 / 0, 10000, 'seedcarrot'))
    T.eq(false, G.ready(1000, 0 / 0, 'seedcarrot'))
    T.eq(false, G.ready(math.huge, 10000, 'seedcarrot'))
    T.eq(false, G.ready(1000, math.huge, 'seedcarrot'))
    T.eq(false, G.ready('1000', 10000, 'seedcarrot'))
    T.eq(false, G.ready(1000, '10000', 'seedcarrot'))
    -- clock skew: now < plantedAt is never ready
    T.eq(false, G.ready(5000, 4000, 'seedcarrot'))
    -- t0 = 0 is valid
    T.eq(false, G.ready(0, 7199, 'seedcarrot'))
    T.eq(true, G.ready(0, 7200, 'seedcarrot'))
    -- remaining returns nil on bad times or unknown crop
    T.eq(nil, G.remaining(nil, 10000, 'seedcarrot'))
    T.eq(nil, G.remaining(-5, 10000, 'seedcarrot'))
    T.eq(nil, G.remaining(1000, -1, 'seedcarrot'))
    T.eq(nil, G.remaining(1000, 10000, 'seedbogus'))
end)

T.finish()

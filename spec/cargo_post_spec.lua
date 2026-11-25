-- Run from repo root: `lua spec/cargo_post_spec.lua` (or via tools/run-specs.py).
-- roads-04 R17: call / stow / menu / buy at a trade post (server/wagon_post.lua + its wiring in server/main.lua).
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local case = T.it
local CARGO = here .. '../server/resources/[fh]/fh_cargo/'
local R = dofile(CARGO .. 'shared/cargo_rules.lua')
local P = dofile(CARGO .. 'server/wagon_post.lua')
local CFG = (function()
    local env = setmetatable({}, { __index = _G })
    assert(loadfile(CARGO .. 'config.lua', 't', env))()
    return env.FhCargoConfig
end)()

local POST = { id = 'valentine_post', label = 'Valentine Trade Post', region = 'heartlands', x = 100.0, y = 200.0, z = 30.0, radius = 6.0 }

---Fakes. o.at = player at the post (default true); o.owned = { t1 = true }; o.live = live entry.
local function mk(o)
    o = o or {}
    local E = { spawned = {}, stowed = {}, buys = {}, cleared = 0, live = o.live }
    E.deps = {
        citizenid = function(src) return src == 7 and 'CID1' or nil end,
        nearestPost = function() if o.at == false then return nil end return o.post or POST end,
        owned = function(_, tier) if o.dbDown then return nil end return (o.owned or {})[tier] == true end,
        ownedSet = function() if o.dbDown then return nil end return o.owned or {} end,
        live = function() return E.live end,
        spawnPoint = function() return { x = 101.0, y = 202.0, z = 30.0, w = 0.0 } end,
        spawn = function(src, tier, at)
            if o.spawnErr then return nil, o.spawnErr end
            E.spawned[#E.spawned + 1] = { src = src, tier = tier, at = at }
            E.live = { id = 'CID1:' .. tier, tier = tier, coords = nil }
            return 'CID1:' .. tier
        end,
        stow = function(live) E.stowed[#E.stowed + 1] = live.id E.live = nil return true end,
        buy = function(src, tier, region) E.buys[#E.buys + 1] = { src = src, tier = tier, region = region } return true end,
        canUnlock = function(_, id) if o.locked then return false, 'tier_too_low' end return true end,
        log = function() end,
    }
    return E
end

case('call: not at a post refused (server decides, nothing spawned)', function()
    local E = mk({ at = false, owned = { t1 = true } })
    local ok, err = P.call(CFG, R, E.deps, {}, 7, 't1')
    T.eq(false, ok); T.eq('fh_not_at_post', err); T.eq(0, #E.spawned)
end)

case('call: a post with a bad radius or no region is not a post', function()
    for _, bad in ipairs({ { id = 'x', region = 'r', x = 0, y = 0, radius = 0 }, { id = 'x', x = 0, y = 0, radius = 5 }, 'junk' }) do
        local E = mk({ post = bad, owned = { t1 = true } })
        T.eq('fh_not_at_post', select(2, P.call(CFG, R, E.deps, {}, 7, 't1')))
    end
end)

case('call: unowned tier refused, db failure fails closed', function()
    local E = mk({ owned = { t1 = true } })
    T.eq('fh_not_owned', select(2, P.call(CFG, R, E.deps, {}, 7, 't2')))
    T.eq(0, #E.spawned)
    local D = mk({ dbDown = true })
    T.eq('fh_db_error', select(2, P.call(CFG, R, D.deps, {}, 7, 't1')))
    T.eq('fh_bad_tier', select(2, P.call(CFG, R, E.deps, {}, 7, 'zzz')))
end)

case('call: owned tier spawns near the player at the post via spawnWagon', function()
    local E = mk({ owned = { t1 = true, t3 = true } })
    local ok, res = P.call(CFG, R, E.deps, {}, 7, 'freight')
    T.eq(true, ok); T.eq('CID1:t3', res.wagon); T.eq('valentine_post', res.post)
    T.eq(1, #E.spawned); T.eq('t3', E.spawned[1].tier); T.eq(101.0, E.spawned[1].at.x)
end)

case('call: spawnWagon refusal (rep gate) is passed through, no wagon', function()
    local E = mk({ owned = { t2 = true }, spawnErr = 'tier_too_low' })
    local ok, err = P.call(CFG, R, E.deps, {}, 7, 't2')
    T.eq(false, ok); T.eq('tier_too_low', err)
end)

case('call: one live wagon rule refuses (never loses cargo), pending spawn counts', function()
    local E = mk({ owned = { t1 = true, t2 = true }, live = { id = 'CID1:t1', tier = 't1', coords = { x = 100, y = 200, z = 30 } } })
    local ok, err, detail = P.call(CFG, R, E.deps, {}, 7, 't2')
    T.eq(false, ok); T.eq('fh_wagon_live', err); T.eq('t1', detail); T.eq(0, #E.spawned)
    local F = mk({ owned = { t1 = true } })
    T.eq(true, (P.call(CFG, R, F.deps, {}, 7, 't1')))
    T.eq('fh_wagon_live', select(2, P.call(CFG, R, F.deps, {}, 7, 't1')), 'second call while the first is pending')
    T.eq(1, #F.spawned)
end)

case('call: busy lock refuses a concurrent action and is released after', function()
    local E = mk({ owned = { t1 = true } })
    local locks = { ['src:7'] = true }
    T.eq('fh_busy', select(2, P.call(CFG, R, E.deps, locks, 7, 't1')))
    T.eq('fh_busy', select(2, P.stow(CFG, R, E.deps, locks, 7)))
    local free = {}
    P.call(CFG, R, E.deps, free, 7, 't1')
    T.eq(nil, next(free), 'released')
    local thrower = mk({ owned = { t1 = true } })
    thrower.deps.spawn = function() error('boom') end
    T.eq('fh_call_error', select(2, P.call(CFG, R, thrower.deps, free, 7, 't1')))
    T.eq(nil, next(free), 'released after a throw')
end)

case('stow: near the post despawns the entity only (stow dep called, nothing cleared)', function()
    local E = mk({ live = { id = 'CID1:t1', tier = 't1', coords = { x = 103, y = 200, z = 30 } } })
    local ok, res = P.stow(CFG, R, E.deps, {}, 7)
    T.eq(true, ok); T.eq('CID1:t1', res.wagon); T.same({ 'CID1:t1' }, E.stowed)
end)

case('stow: wagon beyond post radius + margin refused; just inside margin allowed', function()
    local far = mk({ live = { id = 'a', tier = 't1', coords = { x = 100 + 6 + CFG.StowMargin + 1, y = 200, z = 30 } } })
    T.eq('fh_wagon_far', select(2, P.stow(CFG, R, far.deps, {}, 7))); T.eq(0, #far.stowed)
    local across = mk({ live = { id = 'a', tier = 't1', coords = { x = 5000, y = 5000, z = 30 } } })
    T.eq('fh_wagon_far', select(2, P.stow(CFG, R, across.deps, {}, 7)))
    local edge = mk({ live = { id = 'a', tier = 't1', coords = { x = 100 + 6 + CFG.StowMargin - 0.5, y = 200, z = 30 } } })
    T.eq(true, (P.stow(CFG, R, edge.deps, {}, 7)))
end)

case('stow: player not at a post / no wagon / still spawning refused', function()
    T.eq('fh_not_at_post', select(2, P.stow(CFG, R, mk({ at = false, live = { id = 'a', tier = 't1', coords = { x = 100, y = 200, z = 30 } } }).deps, {}, 7)))
    T.eq('fh_no_wagon', select(2, P.stow(CFG, R, mk().deps, {}, 7)))
    local pend = mk({ live = { id = 'a', tier = 't1' } })
    T.eq('fh_wagon_not_ready', select(2, P.stow(CFG, R, pend.deps, {}, 7))); T.eq(0, #pend.stowed)
    T.eq('fh_no_character', select(2, P.stow(CFG, R, mk().deps, {}, 99)))
end)

case('buy: passes the POST region (not a client one) and refuses away from a post', function()
    local E = mk()
    T.eq(true, (P.buy(CFG, R, E.deps, {}, 7, 't2')))
    T.same({ { src = 7, tier = 't2', region = 'heartlands' } }, E.buys)
    local A = mk({ at = false })
    T.eq('fh_not_at_post', select(2, P.buy(CFG, R, A.deps, {}, 7, 't1'))); T.eq(0, #A.buys)
    T.eq('fh_bad_tier', select(2, P.buy(CFG, R, E.deps, {}, 7, 'x')))
end)

case('buy: passes buyWagon detail through (refunded on fh_already_owned)', function()
    local E = mk()
    E.deps.buy = function() return false, 'fh_already_owned', 'refunded' end
    local ok, err, detail = P.buy(CFG, R, E.deps, {}, 7, 't1')
    T.eq(false, ok); T.eq('fh_already_owned', err); T.eq('refunded', detail)
end)

case('menu: price, owned, locked and live state', function()
    local E = mk({ owned = { t1 = true }, locked = true, live = { id = 'CID1:t1', tier = 't1' } })
    local m = assert(P.menu(CFG, R, E.deps, 7))
    T.eq('heartlands', m.post.region); T.eq('t1', m.live.tier)
    T.eq(3, #m.tiers)
    T.eq(true, m.tiers[1].owned); T.eq(CFG.Prices.t1, m.tiers[1].price); T.eq(nil, m.tiers[1].locked)
    T.eq(true, m.tiers[2].locked); T.eq('tier_too_low', m.tiers[2].reason); T.eq(false, m.tiers[2].owned)
    T.eq('fh_not_at_post', select(2, P.menu(CFG, R, mk({ at = false }).deps, 7)))
end)

-- ---------------------------------------------------------------- wiring: the real server/main.lua under stubs

local function boot(o)
    o = o or {}
    local E = { handlers = {}, client = {}, despawns = {}, cleared = {}, charges = {}, registers = {}, spawns = {}, rows = o.rows or {},
        at = true, wagonPos = { x = 100, y = 200, z = 30 }, now = 0 }
    local reqN = 0
    local exportsT = setmetatable({
        ['rsg-core'] = { GetCoreObject = function() return { Functions = {
            GetPlayer = function(src) return src == 7 and { PlayerData = { citizenid = 'CID1' } } or nil end },
            Shared = { Items = {} } } end },
        fh_core = {
            requestSpawn = function(_, spec, opts)
                reqN = reqN + 1
                E.spawns[#E.spawns + 1] = spec
                E.ready = function() opts.onReady(100 + reqN) end
                E.fail = function(why) opts.onFailed(why) end
                return reqN
            end,
            despawn = function(_, id) E.despawns[#E.despawns + 1] = id end,
            registerContainer = function(_, ref) E.registers[#E.registers + 1] = ref return true end,
            clearContainer = function(_, ref) E.cleared[#E.cleared + 1] = ref return true end,
            deleteContainer = function(_, ref) E.cleared[#E.cleared + 1] = ref return true end,
        },
        fh_trade = { nearestPost = function() return E.at and POST or nil end },
        fh_progression = { canUnlock = function() return true end },
        fh_economy = { charge = function(_, src, amount, why, region) E.charges[#E.charges + 1] = { region = region, amount = amount } return true end,
            credit = function() return true end },
    }, { __call = function() end })
    local MySQL = {
        query = { await = function(sql, params)
            local out = {}
            for _, r in ipairs(E.rows) do
                if r.citizenid == params[1] and (params[2] == nil or r.tier == params[2]) then out[#out + 1] = params[2] and { ['1'] = 1 } or { tier = r.tier } end
            end
            return out
        end },
        update = { await = function(_, params) E.rows[#E.rows + 1] = { citizenid = params[1], tier = params[2] } return 1 end },
    }
    local env = setmetatable({
        exports = exportsT, MySQL = MySQL, lib = { addCommand = function() end },
        GetCurrentResourceName = function() return 'fh_cargo' end, GetResourceState = function() return 'started' end,
        RegisterNetEvent = function(name, fn) E.handlers[name] = fn end, AddEventHandler = function() end,
        CreateThread = function() end, Wait = function() end, TriggerEvent = function() end,
        TriggerClientEvent = function(name, src, payload) E.client[#E.client + 1] = { name = name, src = src, payload = payload } end,
        GetPlayers = function() return {} end, GetConvar = function() return 'true' end,
        GetGameTimer = function() E.now = E.now + 10000 return E.now end,
        GetPlayerPed = function() return 5 end, GetEntityHeading = function() return 0.0 end,
        NetworkGetEntityFromNetworkId = function(n) return n end, DoesEntityExist = function() return not E.gone end,
        GetEntityCoords = function(ent) if ent == 5 then return { x = 100, y = 200, z = 30 } end return E.wagonPos end,
        vector4 = function(x, y, z, w) return { x = x, y = y, z = z, w = w } end,
        print = function() end,
    }, { __index = _G })
    env._G = env
    env.source = 7
    for _, p in ipairs({ CARGO .. 'shared/cargo_rules.lua', CARGO .. 'config.lua', CARGO .. 'server/wagon_buy.lua',
        CARGO .. 'server/wagon_post.lua', CARGO .. 'server/main.lua' }) do
        local fh = assert(io.open(p, 'rb')); local s = fh:read('a'); fh:close()
        assert(load(s, '@' .. p, 't', env))()
    end
    function E.act(action, tier) env.source = 7 E.client = {} E.handlers['fh:cargo:menu_action']({ action = action, tier = tier }) return E.client[#E.client].payload end
    return E
end

case('wiring: buy via menu charges the post region; call then stow keeps the container', function()
    local E = boot()
    local r = E.act('buy', 't1')
    T.eq(true, r.ok); T.eq('heartlands', E.charges[1].region)
    r = E.act('call', 't1')
    T.eq(true, r.ok); T.eq('wagon', E.spawns[1].kind); T.eq('CID1:t1', E.spawns[1].owner.id)
    r = E.act('call', 't1')
    T.eq('fh_wagon_live', r.err, 'pending spawn is live')
    E.ready()
    r = E.act('stow')
    T.eq(true, r.ok); T.same({ 1 }, E.despawns); T.eq(0, #E.cleared, 'container untouched')
    r = E.act('call', 't1')
    T.eq(true, r.ok); T.eq(2, #E.spawns); T.eq('CID1:t1', E.spawns[2].owner.id, 'same wagon id, same stash')
end)

case('wiring: stow refused when the wagon is far; call refused unowned and away from a post; failed spawn frees the slot', function()
    local E = boot({ rows = { { citizenid = 'CID1', tier = 't1' } } })
    T.eq('fh_not_owned', E.act('call', 't2').err)
    T.eq(true, E.act('call', 't1').ok)
    E.ready()
    E.wagonPos = { x = 900, y = 900, z = 30 }
    T.eq('fh_wagon_far', E.act('stow').err); T.eq(0, #E.despawns)
    E.at = false
    T.eq('fh_not_at_post', E.act('stow').err)
    T.eq('fh_not_at_post', E.act('call', 't1').err)
    E.at = true; E.wagonPos = { x = 100, y = 200, z = 30 }
    T.eq(true, E.act('stow').ok)
    T.eq(true, E.act('call', 't1').ok)
    E.fail('no_model')
    T.eq(true, E.act('call', 't1').ok, 'a failed spawn request is not a live wagon')
end)

case('wiring: bad payloads ignored, menu event returns rows', function()
    local E = boot({ rows = { { citizenid = 'CID1', tier = 't1' } } })
    E.client = {}
    E.handlers['fh:cargo:menu_action']({ action = 'rm -rf', tier = 't1' })
    E.handlers['fh:cargo:menu_action']({ action = 'buy', tier = 5 })
    E.handlers['fh:cargo:menu_action']('x')
    T.eq(0, #E.client)
    E.handlers['fh:cargo:menu_open']()
    T.eq('fh:cargo:menu', E.client[1].name); T.eq(true, E.client[1].payload.tiers[1].owned)
end)
T.finish()

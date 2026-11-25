-- Stubbed-server spec (plan a-life-01 A2): loads fh_alife's real server/main.lua with a fake fh_heat, fh_trade,
-- KVP and json, and drives the camp_cleared handler + admin command end to end. Focus: the fh_trade setShortage call,
-- the fh:alife:camp_flipped event, the KVP JSON save/load and the /alife tick admin command. fh_alife emits no heat:
-- camp_clear heat is owned by fh_heat's own fh:zones:camp_cleared listener (heatCalls stays empty, asserted below).
-- Not a substitute for a live boot: exports are captured in-process, KVP is in-memory, the tick loop thread is not run.
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local R = here .. '../server/resources/[fh]/'

-- Minimal JSON (encode/decode) for the KVP round-trip: the spec runs under plain Lua 5.4 (no CfxLua `json` global).
-- Handles the state shape (objects, arrays, strings, integers, booleans, null); an empty table encodes as [].
local Json = {}
do
    local esc = { ['"'] = '\\"', ['\\'] = '\\\\', ['\b'] = '\\b', ['\f'] = '\\f', ['\n'] = '\\n', ['\r'] = '\\r',
        ['\t'] = '\\t' }
    local function enc(v)
        local t = type(v)
        if v == nil then return 'null' end
        if t == 'boolean' then return v and 'true' or 'false' end
        if t == 'number' then
            if v == math.floor(v) and math.abs(v) < 1e15 then return string.format('%d', v) end
            return string.format('%.14g', v)
        end
        if t == 'string' then
            return '"' .. v:gsub('[%z\1-\31"\\]', function(c) return esc[c] or string.format('\\u%04x', string.byte(c)) end) .. '"'
        end
        if t == 'table' then
            local n, isArr = 0, true
            for k in pairs(v) do
                if type(k) ~= 'number' or k < 1 or k % 1 ~= 0 then isArr = false break end
                n = n + 1
            end
            if isArr then
                local parts = {}
                for i = 1, n do parts[i] = enc(v[i]) end
                return '[' .. table.concat(parts, ',') .. ']'
            end
            local parts = {}
            for k, x in pairs(v) do parts[#parts + 1] = enc(tostring(k)) .. ':' .. enc(x) end
            table.sort(parts)
            return '{' .. table.concat(parts, ',') .. '}'
        end
        error('cannot encode ' .. t)
    end
    Json.encode = enc

    local function dec(s)
        local pos, len = 1, #s
        local function skip() while pos <= len and s:sub(pos, pos):match('[ \t\r\n]') do pos = pos + 1 end end
        local function str()
            pos = pos + 1 -- opening quote
            local out = {}
            while true do
                local c = s:sub(pos, pos); pos = pos + 1
                if c == '"' then break end
                if c == '\\' then
                    local e = s:sub(pos, pos); pos = pos + 1
                    out[#out + 1] = ({ ['n'] = '\n', ['t'] = '\t', ['r'] = '\r', ['"'] = '"', ['\\'] = '\\', ['/'] = '/' })[e] or e
                else out[#out + 1] = c end
            end
            return table.concat(out)
        end
        local function num()
            local i = pos
            if s:sub(i, i) == '-' then i = i + 1 end
            while s:sub(i, i):match('%d') do i = i + 1 end
            if s:sub(i, i) == '.' then i = i + 1 while s:sub(i, i):match('%d') do i = i + 1 end end
            local n = tonumber(s:sub(pos, i - 1)); pos = i; return n
        end
        local function val()
            skip()
            local c = s:sub(pos, pos)
            if c == '{' then
                pos = pos + 1
                local t = {}
                skip()
                if s:sub(pos, pos) == '}' then pos = pos + 1 return t end
                while true do
                    skip()
                    local k = str(); skip(); pos = pos + 1 -- ':'
                    t[k] = val()
                    skip()
                    local d = s:sub(pos, pos); pos = pos + 1
                    if d == '}' then break end
                end
                return t
            end
            if c == '[' then -- arrays (an empty Lua table encodes as [])
                pos = pos + 1
                local t = {}
                skip()
                if s:sub(pos, pos) == ']' then pos = pos + 1 return t end
                while true do
                    t[#t + 1] = val()
                    skip()
                    local d = s:sub(pos, pos); pos = pos + 1
                    if d == ']' then break end
                end
                return t
            end
            if c == '"' then return str() end
            if c == 't' then pos = pos + 4 return true end
            if c == 'f' then pos = pos + 5 return false end
            if c == 'n' then pos = pos + 4 return nil end
            return num()
        end
        return val()
    end
    Json.decode = dec
end

---Boot a fresh copy of server/main.lua + server/squads.lua. `preKvp` = the KVP store to load from; `ambush` =
---{ [regionId] = { ambush node entries } } overlaid onto FhRegions before the rules build the node graph. Returns a
---probe table with captured exports, handlers, commands, KVP writes, cross-resource calls and squad spawn/despawn
---records (the stubbed fh_core adopts each spawn synchronously with a fake netId).
local function boot(preKvp, ambush, opts)
    local B = {
        exported = {}, handlers = {}, commands = {}, broadcasts = {}, flipped = {}, heatCalls = {},
        shortageCalls = {}, printed = {}, kvp = preKvp or {},
        spawns = {}, despawns = {}, wiped = {}, healths = {}, nextReq = 1,
        players = {}, playerPeds = {}, pedCoords = {}, cids = {}, killers = {},
        -- a-life-03 C2: fh_homestead claims (plotId -> plotInfo facts), fh_core containers (id -> slot -> item),
        -- container op log, failure knobs, raid_repelled events, resource states (default 'started').
        plots = {}, containers = {}, invLog = {}, failAdd = {}, failRemove = {}, noFit = {}, bags = {},
        repelled = {}, resState = {},
    }
    local function copy(t)
        if type(t) ~= 'table' then return t end
        local o = {}
        for k, v in pairs(t) do o[k] = copy(v) end
        return o
    end
    local function sortedPlotIds()
        local ids = {}
        for id in pairs(B.plots) do ids[#ids + 1] = id end
        table.sort(ids)
        return ids
    end
    local exportsT = setmetatable({
        -- fh_heat is stubbed as a spy: fh_alife must NOT call addSource (camp_clear heat is fh_heat's own job).
        fh_heat = { addSource = function(_, src, faction, key)
            B.heatCalls[#B.heatCalls + 1] = { src, faction, key } return true, 1 end },
        fh_trade = { setShortage = function(_, region, item, level)
            B.shortageCalls[#B.shortageCalls + 1] = { region, item, level } return true end },
        -- fh_core is stubbed: requestSpawn records the spec and "adopts" synchronously (onReady with a fake netId);
        -- despawn records the request id. Ambush squads own their entities through this contract.
        fh_core = {
            requestSpawn = function(_, spec, opts)
                local id = B.nextReq; B.nextReq = B.nextReq + 1
                local netId = 9000 + id
                B.spawns[id] = { spec = spec, opts = opts, netId = netId }
                B.healths[netId] = 100
                if type(opts) == 'table' and type(opts.onReady) == 'function' then opts.onReady(netId, id) end
                return id
            end,
            despawn = function(_, id) B.despawns[#B.despawns + 1] = id B.spawns[id] = nil end,
            -- container API (fh_core/server/inventory.lua): stash ids -> slot maps; removeItem/addItem all-or-nothing
            snapshot = function(_, ref)
                local c = B.containers[ref.id]
                if not c then return nil, 'fh_no_container' end
                return copy(c)
            end,
            canFit = function(_, ref, name, amount)
                if not B.containers[ref.id] then return false, 'fh_no_container' end
                if B.noFit[ref.id] then return false, B.noFit[ref.id] end
                return true
            end,
            removeItem = function(_, ref, name, amount)
                B.invLog[#B.invLog + 1] = { 'remove', ref.id, name, amount }
                local c = B.containers[ref.id]
                if not c then return false, 'fh_unknown_container' end
                if B.failRemove[ref.id] then return false, B.failRemove[ref.id] end
                local have = 0
                for _, it in pairs(c) do if it.name == name then have = have + it.amount end end
                if have < amount then return false, 'fh_not_enough' end
                local slots = {}
                for slot, it in pairs(c) do if it.name == name then slots[#slots + 1] = slot end end
                table.sort(slots)
                local left = amount
                for _, slot in ipairs(slots) do
                    local take = math.min(left, c[slot].amount)
                    c[slot].amount = c[slot].amount - take
                    if c[slot].amount == 0 then c[slot] = nil end
                    left = left - take
                    if left == 0 then break end
                end
                return true
            end,
            addItem = function(_, ref, name, amount, info)
                B.invLog[#B.invLog + 1] = { 'add', ref.id, name, amount }
                local c = B.containers[ref.id]
                if not c then return false, 'fh_unknown_container' end
                if B.failAdd[ref.id] then return false, B.failAdd[ref.id] end
                for _, it in pairs(c) do
                    if it.name == name then it.amount = it.amount + amount return true end
                end
                local slot = 1
                while c[slot] do slot = slot + 1 end
                c[slot] = { name = name, amount = amount, info = copy(info) }
                return true
            end,
            createDropBag = function(_, coords, items, opts)
                if type(B.failBag) == 'function' then
                    local why = B.failBag(items, coords, opts)
                    if why then return nil, why end
                elseif B.failBag then
                    return nil, B.failBag
                end
                B.bags[#B.bags + 1] = { coords = coords, items = copy(items), opts = opts }
                return 'drop:' .. #B.bags
            end,
        },
        -- fh_homestead (soft dependency): claimedPlots + plotInfo from B.plots
        fh_homestead = {
            claimedPlots = function() return sortedPlotIds() end,
            plotInfo = function(_, id) return copy(B.plots[id]) end,
        },
        -- rsg-core: src -> citizenid via B.cids (the lookup fh_zones also uses for camp_cleared participants).
        ['rsg-core'] = { GetCoreObject = function() return { Functions = { GetPlayer = function(src)
            return B.cids[src] and { PlayerData = { citizenid = B.cids[src] } } or nil end } } end },
    }, { __call = function(_, name, fn) B.exported[name] = fn end })
    local env = setmetatable({
        exports = exportsT,
        GetCurrentResourceName = function() return 'fh_alife' end,
        GetResourceState = function(name) return B.resState[name] or 'started' end,
        GetPlayers = function() return B.players end,
        GetPlayerPed = function(src) return B.playerPeds[src] or 0 end,
        GetEntityCoords = function(e) return B.pedCoords[e] end,
        GetEntityHealth = function(e) return B.healths[e] or 100 end,
        NetworkGetEntityFromNetworkId = function(netId) return netId end,
        DoesEntityExist = function(e) return e ~= 0 end,
        GetPedSourceOfDeath = function(e) return B.killers[e] or 0 end,
        GetGameTimer = function() return 0 end,
        SetResourceKvp = function(k, v)
            if B.failKvp then error(B.failKvp) end
            B.kvp[k] = v
        end,
        GetResourceKvpString = function(k) return B.kvp[k] end,
        TriggerEvent = function(name, payload)
            if name == 'fh:alife:camp_flipped' then B.flipped[#B.flipped + 1] = payload end
            if name == 'fh:alife:squad_wiped' then B.wiped[#B.wiped + 1] = payload end
            if name == 'fh:alife:raid_repelled' then B.repelled[#B.repelled + 1] = payload end
            local h = B.handlers[name]
            if h then h(payload) end
        end,
        TriggerClientEvent = function(name, target, payload) B.broadcasts[#B.broadcasts + 1] = { target, payload } end,
        AddEventHandler = function(name, fn) B.handlers[name] = fn end,
        RegisterCommand = function() end, RegisterNetEvent = function() end,
        CreateThread = function() end, Wait = function() end, -- tick loop not driven; tick tested via the admin command
        lib = { addCommand = function(name, props, cb) B.commands[name] = cb end },
        json = Json,
        vector3 = function(x, y, z) return { x = x, y = y, z = z } end,
        vector4 = function(x, y, z, w) return { x = x, y = y, z = z, w = w } end,
        print = function(...) B.printed[#B.printed + 1] = table.concat({ ... }, ' ') end,
    }, { __index = _G })
    env._G = env
    local function run(p)
        local fh = assert(io.open(p, 'rb')); local src = fh:read('a'); fh:close()
        assert(load(src, '@' .. p, 't', env))()
    end
    run(R .. 'fh_core/shared/regions.lua')
    -- regions.lua carries world-03 H ambush nodes; strip them all so `ambush` (or nil = no ambush data anywhere) is
    -- the only ambush data the rules see, as alife_rules_spec's fixtureRegions does.
    for _, r in pairs(env.FhRegions.regions) do r.ambush = nil end
    if ambush then
        for rid, list in pairs(ambush) do env.FhRegions.regions[rid].ambush = list end
    end
    run(R .. 'fh_core/shared/place_resolver.lua')
    run(R .. 'fh_zones/config.lua')
    run(R .. 'fh_zones/shared/camp_rules.lua')
    run(R .. 'fh_homestead/shared/plot_rules.lua')
    run(R .. 'fh_alife/config.lua')
    run(R .. 'fh_alife/shared/alife_rules.lua')
    run(R .. 'fh_alife/shared/raid_rules.lua') -- fxmanifest order: reads the FhAlifeRules global
    if opts and opts.beforeLoad then opts.beforeLoad(B) end
    run(R .. 'fh_alife/server/homestead.lua')
    run(R .. 'fh_alife/server/main.lua')
    run(R .. 'fh_alife/server/squads.lua')
    run(R .. 'fh_alife/server/raids.lua')
    B.env = env
    B.cfg = env.FhAlifeConfig
    B.rules = env.FhAlifeRules
    B.raidRules = env.FhAlifeRaidRules
    B.server = env.FhAlifeServer
    B.squads = env.FhAlifeSquads
    B.regions = env.FhRegions
    return B
end

T.describe('fh_alife server wiring (stubbed server)', function()
    T.it('a-life-03: raid_rules loads after alife_rules as the FhAlifeRaidRules global', function()
        local B = boot()
        T.eq('table', type(B.raidRules))
        T.eq('function', type(B.raidRules.tick))
        T.eq(B.rules.serialize, B.raidRules.serialize)
    end)

    T.it('exports: getOwner default owner + isLawHeld', function()
        local B = boot()
        T.eq('outlaws', B.exported.getOwner('heartlands_t1_01'))
        T.eq('raiders', B.exported.getOwner('scarlett_meadows_t1_01'))
        T.eq(nil, B.exported.getOwner('bogus'))
        T.eq(false, B.exported.isLawHeld('heartlands_t1_01'))
    end)

    T.it('camp_cleared: flips to law, applies no heat, relieves shortage, broadcasts, saves KVP', function()
        local B = boot()
        B.handlers['fh:zones:camp_cleared']({ camp_id = 'heartlands_t1_01', region_id = 'heartlands',
            participants = { 'CID1', 'CID2' } })
        T.eq('lawmen', B.exported.getOwner('heartlands_t1_01'))
        T.eq(true, B.exported.isLawHeld('heartlands_t1_01'))
        T.eq(0, #B.heatCalls, 'no fh_heat.addSource call: fh_alife must not apply camp_clear heat')
        T.same({ { 'heartlands', 'trade_salt', 0 } }, B.shortageCalls, 'shortage relieved on law flip')
        T.eq(1, #B.flipped)
        T.same({ camp_id = 'heartlands_t1_01', region_id = 'heartlands', from = 'outlaws', to = 'lawmen' }, B.flipped[1])
        local found = false
        for _, b in ipairs(B.broadcasts) do
            if b[1] == -1 and b[2].args[2]:find('New Hanover Law has taken', 1, true) then found = true end
        end
        assert(found, 'law-taken broadcast sent to all')
        assert(type(B.kvp.fh_alife_state) == 'string' and #B.kvp.fh_alife_state > 0, 'KVP state saved')
    end)

    T.it('KVP load: persisted state is restored on boot', function()
        local seedState = { version = 1, tick = 7, owners = { heartlands_t1_01 = 'lawmen' }, squads = {}, nextSquadId = 2 }
        local B = boot({ fh_alife_state = Json.encode(seedState) })
        T.eq('lawmen', B.exported.getOwner('heartlands_t1_01'))
        T.eq(true, B.exported.isLawHeld('heartlands_t1_01'))
    end)

    T.it('/alife tick 30: retake squad resolves, flips back to outlaws and raises the shortage', function()
        local B = boot()
        B.handlers['fh:zones:camp_cleared']({ camp_id = 'heartlands_t1_01', region_id = 'heartlands', participants = {} })
        T.eq('lawmen', B.exported.getOwner('heartlands_t1_01'))
        B.commands.alife(1, {}, 'alife tick 30') -- >= max etaTick (30)
        T.eq('outlaws', B.exported.getOwner('heartlands_t1_01'))
        T.eq(false, B.exported.isLawHeld('heartlands_t1_01'))
        local raised = false
        for _, c in ipairs(B.shortageCalls) do
            if c[1] == 'heartlands' and c[2] == 'trade_salt' and c[3] == 0.5 then raised = true end
        end
        assert(raised, 'shortage raised on retake')
        T.eq(2, #B.flipped, 'two flips: law take then outlaw retake')
        T.same({ camp_id = 'heartlands_t1_01', region_id = 'heartlands', from = 'lawmen', to = 'outlaws' }, B.flipped[2])
    end)

    T.it('/alife status replies with the live state', function()
        local B = boot()
        B.commands.alife(1, {}, 'alife')
        local replied = false
        for _, b in ipairs(B.broadcasts) do
            if b[1] == 1 and b[2].args[2]:find('tick 0', 1, true) then replied = true end
        end
        assert(replied, 'status reply sent to the admin')
    end)

    T.it('/alife from the server console (src 0) prints instead of dropping', function()
        local B = boot()
        B.commands.alife(0, {}, 'alife')
        local seen = false
        for _, l in ipairs(B.printed) do if l:find('tick 0', 1, true) then seen = true end end
        assert(seen, 'console status printed')
    end)

    -- ---------------------------------------------------------------- a-life-02 B2: squads (materialise / despawn / death watch)

    local HEART_AMBUSH = {
        { id = 'heartlands_amb_bend', x = 100.0, y = 500.0, z = 110.0, label = 'Dakota bend', verified = true },
    }
    local function always(lo) return lo end -- deterministic rng: chance hits, first node, min travel/strength
    local function count(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end

    ---Boot with heartlands ambush data, create one ambush squad (sq1) and hold it at the node, with a player at the node.
    local function heldSquad()
        local B = boot(nil, { heartlands = HEART_AMBUSH })
        local st = B.server.getState()
        B.rules.planRaids(B.server.ctx, st, always) -- sq1: heartlands_amb_bend, strength = raids.strengthMin (2)
        st.squads.sq1.phase = 'hold'
        B.players = { 1 }
        B.playerPeds[1] = 101
        B.pedCoords[101] = { x = 100, y = 500, z = 110 }
        B.cids[1] = 'CID1'
        return B, st
    end

    T.it('B2 materialise: one ped per strength, owner tag {kind="alife_squad"}', function()
        local B, st = heldSquad()
        B.squads.sweep()
        local spawns = {}
        for _, s in pairs(B.spawns) do spawns[#spawns + 1] = s end
        T.eq(st.squads.sq1.strength, #spawns, 'one ped per strength point')
        for _, s in ipairs(spawns) do
            T.eq('ped', s.spec.kind)
            T.eq('alife_squad', s.spec.owner.kind)
            T.eq('sq1', s.spec.owner.id)
        end
    end)

    T.it('B2 a travelling squad stays invisible (no peds) even with a player at the node', function()
        local B = boot(nil, { heartlands = HEART_AMBUSH })
        B.rules.planRaids(B.server.ctx, B.server.getState(), always) -- phase 'travel'
        B.players = { 1 }; B.playerPeds[1] = 101; B.pedCoords[101] = { x = 100, y = 500, z = 110 }
        B.squads.sweep()
        T.eq(0, count(B.spawns), 'no visible riding: a travelling squad does not materialise')
    end)

    T.it('B2 despawn when no player near keeps surviving strength', function()
        local B, st = heldSquad()
        B.squads.sweep() -- materialise
        assert(count(B.spawns) > 0, 'materialised first')
        B.pedCoords[101] = { x = 99999, y = 99999, z = 0 } -- player leaves
        B.squads.sweep()
        assert(#B.despawns >= 1, 'peds despawned')
        T.eq(2, st.squads.sq1.strength, 'strength preserved (no kill counted)')
    end)

    T.it('B2 a region with no ambush data is a clean no-op (sweep does nothing)', function()
        local B = boot() -- real FhRegions, ambush stripped: no ambush data anywhere
        B.squads.sweep()
        T.eq(0, count(B.spawns))
        T.eq(0, #B.despawns)
    end)

    T.it('B2 squad_wiped is emitted once when the last member dies (server health check)', function()
        local B, st = heldSquad()
        B.squads.sweep() -- materialise
        for _, s in pairs(B.spawns) do B.healths[s.netId] = 0 end -- every member dies
        B.squads.sweep()
        T.eq(1, #B.wiped, 'one wipe event')
        T.same({ squad_id = 'sq1', node_id = 'heartlands_amb_bend', region_id = 'heartlands', faction = 'outlaws',
            participants = { 'CID1' }, goal = 'ambush', camp_id = 'heartlands_t1_01', label = 'Dakota bend' },
            B.wiped[1])
        T.eq(nil, st.squads.sq1, 'squad removed from state')
    end)

    T.it('B2 squad_wiped participants: in-radius players + an out-of-radius killer, deduped; far bystander excluded', function()
        local B = heldSquad()
        B.players = { 1, 2, 3 }
        B.playerPeds[2] = 102; B.pedCoords[102] = { x = 300, y = 500, z = 110 }; B.cids[2] = 'CID2' -- sniper, 200 m
        B.playerPeds[3] = 103; B.pedCoords[103] = { x = 900, y = 900, z = 110 }; B.cids[3] = 'CID3' -- bystander
        B.squads.sweep()
        local first = true
        for _, s in pairs(B.spawns) do
            B.healths[s.netId] = 0
            B.killers[s.netId] = first and 102 or 101 -- one kill by the sniper, the rest by the in-radius player
            first = false
        end
        B.squads.sweep()
        T.eq(1, #B.wiped)
        T.same({ 'CID1', 'CID2' }, B.wiped[1].participants)
    end)

    T.it('B2 -> B3: the real squad_wiped payload pays an accepted alife_contract ambush job', function()
        local qshared = here .. '../server/resources/[fh]/fh_quests/shared/'
        package.path = qshared .. '?.lua;' .. package.path
        local Jobs, E, I = require('jobs'), require('engine'), require('intake')
        local C = dofile(R .. 'fh_alife/shared/contracts_rules.lua')
        local B, st = heldSquad()
        -- accept the "break the ambush" offer while sq1 holds the node (as fh_quests api.lua does)
        local offer
        for _, o in ipairs(C.offers(B.server.ctx, st, 'heartlands')) do
            if o.key == 'ambush_heartlands_amb_bend' then offer = o end
        end
        assert(offer, 'ambush offer posted for the held node')
        local evset = { [C.SQUAD_EVENT] = true }
        for _, n in ipairs(E.INTAKE) do evset[n] = true end
        local snap = assert(Jobs.snapshot(C.JOB_TYPE, offer, 'heartlands', true))
        local def = assert(Jobs.def(snap, { regions = B.regions.regions, events = evset }))
        local job = assert(E.start(def, {}, 'CID1', 1795651200))
        job.progress.job = snap
        -- wipe the squad through squads.lua; feed the captured payload through intake + the B3 verdict
        B.squads.sweep()
        for _, s in pairs(B.spawns) do B.healths[s.netId] = 0 end
        B.squads.sweep()
        T.eq(1, #B.wiped)
        local hook = function(n, p, s) return C.verdict(C.JOB_TYPE, n, p, s) end
        local changes = I.feed({ [def.id] = def }, { [def.id] = job }, C.SQUAD_EVENT, B.wiped[1], 1795651200,
            function() return hook end)
        T.eq('done', changes[1] and changes[1].after.status, 'credited player CID1 paid')
        -- a player who was not present is not credited by the same payload
        local other = assert(E.start(def, {}, 'NOTHERE', 1795651200)); other.progress.job = snap
        local ch2 = I.feed({ [def.id] = def }, { [def.id] = other }, C.SQUAD_EVENT, B.wiped[1], 1795651200,
            function() return hook end)
        T.eq('active', ch2[1] and ch2[1].after.status or other.status, 'absent player not paid')
    end)

    T.it('/alife lists squads by goal, node and strength; prints "no ambush nodes" for empty regions', function()
        -- no ambush data (stripped): every camp region prints "<region>: no ambush nodes"
        local B0 = boot()
        B0.commands.alife(1, {}, 'alife')
        local msg0
        for _, b in ipairs(B0.broadcasts) do if b[1] == 1 then msg0 = b[2].args[2] end end
        assert(msg0 and msg0:find('heartlands: no ambush nodes', 1, true), 'no-ambush line: ' .. tostring(msg0))
        -- with ambush data and a held squad: the squad line shows goal, node label and strength
        local B = heldSquad()
        B.commands.alife(1, {}, 'alife')
        local msg
        for _, b in ipairs(B.broadcasts) do if b[1] == 1 then msg = b[2].args[2] end end
        assert(msg and msg:find('sq1 ambush@Dakota bend x2 hold', 1, true), 'squad line: ' .. tostring(msg))
    end)

    -- ---------------------------------------------------------------- a-life-03 C2: claim raids (server/raids.lua)
    -- Implemented A-Life — Thanks to S.T.A.L.K.E.R. A-Life by GSC Game World.

    local CLAIM_AT = { x = 1000.0, y = 1000.0, z = 50.0 }
    local CHEST = 'fh:chest:p1:1'
    local STASH = 'fh:camp:heartlands_t1_01' -- first outlaw-held heartlands camp = the raiding camp
    local function lo(a) return a end -- server rng: odds roll 1 (hit), min strength, first stack, take 1

    local function claimFacts(owner, extra)
        local p = { class = 'claim', raidable = true, lawSafe = false, owner = owner,
            coords = { x = CLAIM_AT.x, y = CLAIM_AT.y, z = CLAIM_AT.z }, region = 'heartlands', fenceBuilt = false }
        for k, v in pairs(extra or {}) do p[k] = v end
        return p
    end

    ---Boot with claim p1 owned by CID1 (player 1, ped 101). home = the ped stands at the claim, else 5 km away.
    local function raidBoot(home, kvp, opts)
        local B = boot(kvp, nil, opts)
        B.server.rng = lo
        B.plots.p1 = claimFacts('CID1')
        B.containers[CHEST] = { [1] = { name = 'bread', amount = 4 }, [2] = { name = 'rope', amount = 2, info = { q = 1 } } }
        B.containers[STASH] = {}
        B.players = { '1' }
        B.playerPeds[1] = 101
        B.cids[1] = 'CID1'
        B.pedCoords[101] = home and { x = CLAIM_AT.x + 5, y = CLAIM_AT.y, z = CLAIM_AT.z }
            or { x = CLAIM_AT.x + 5000, y = CLAIM_AT.y, z = CLAIM_AT.z }
        return B
    end

    local function toOwner(B)
        local out = {}
        for _, b in ipairs(B.broadcasts) do if b[1] == 1 then out[#out + 1] = b[2].args[2] end end
        return out
    end
    local function said(B, needle)
        for _, m in ipairs(toOwner(B)) do if m:find(needle, 1, true) then return m end end
        return nil
    end
    local function total(c, name)
        local n = 0
        for _, it in pairs(c or {}) do if it.name == name then n = n + it.amount end end
        return n
    end
    local function raids(B) return B.raidRules.listRaids(B.server.getState()) end
    local function spawnList(B)
        local out = {}
        for _, s in pairs(B.spawns) do out[#out + 1] = s end
        return out
    end

    T.it('C2 schedule: /alife tick 6 runs the raid step after every tick (warn at tick 1, steal at tick 6)', function()
        local B = raidBoot(false)
        B.commands.alife(1, {}, 'alife tick 1')
        local st = B.server.getState()
        T.eq(1, #raids(B), 'raid planned on the first step')
        local sq = raids(B)[1]
        T.eq('warn', sq.phase); T.eq('p1', sq.plot); T.eq('heartlands_t1_01', sq.from); T.eq(6, sq.etaTick)
        assert(said(B, 'are heading for your claim (~5 min)'), 'warning notice to the owner: ' .. table.concat(toOwner(B), ' / '))
        -- 5 more ticks in ONE command: arrival at tick 6 only happens if R.tick ran after each single step
        B.commands.alife(1, {}, 'alife tick 5')
        T.eq(6, st.tick)
        T.eq('return', sq.phase); T.eq('steal', sq.mode)
        assert(said(B, 'took from your chest: 1x bread, 1x rope'), 'itemised steal notice')
    end)

    local CAMP = 'heartlands_t1_01'
    local function ledger(B) return (B.server.getState().raidLoot or {})[CAMP] end
    local function clearCamp(B) B.handlers['fh:zones:camp_cleared']({ camp_id = CAMP, region_id = 'heartlands',
        participants = {} }) end
    local function savedLedger(B)
        local t = Json.decode(B.kvp.fh_alife_state)
        return t.raidLoot and t.raidLoot[CAMP] or nil
    end

    T.it('C2c steal: remove per pick into the camp loot ledger (no stash add); conserved, info kept, saved', function()
        local B = raidBoot(false)
        B.commands.alife(1, {}, 'alife tick 6')
        T.same({ { 'remove', CHEST, 'bread', 1 }, { 'remove', CHEST, 'rope', 1 } }, B.invLog, 'chest removes only')
        T.eq(3, total(B.containers[CHEST], 'bread')); T.eq(1, total(B.containers[CHEST], 'rope'))
        T.same({}, B.containers[STASH], 'the fh_zones stash is not touched at steal time')
        T.same({ { name = 'bread', amount = 1 }, { name = 'rope', amount = 1, info = { q = 1 } } }, ledger(B))
        T.same(ledger(B), savedLedger(B), 'ledger persisted to KVP')
        assert(said(B, 'took from your chest: 1x bread, 1x rope. Clear their camp'), 'itemised notice')
        T.eq(0, #B.bags)
    end)

    T.it('C2c restart: steal -> KVP -> reboot (stash wiped) -> camp_cleared -> items in the stash, ledger empty',
        function()
        local B0 = raidBoot(false)
        B0.commands.alife(1, {}, 'alife tick 6')
        local B = boot({ fh_alife_state = B0.kvp.fh_alife_state })
        T.eq(2, B.raidRules.lootCount(B.server.getState(), CAMP), 'ledger survived the restart')
        B.containers[STASH] = { [1] = { name = 'worn_rifle', amount = 1 } } -- fh_zones rollIntoStash ran first
        clearCamp(B)
        T.same({ { 'add', STASH, 'bread', 1 }, { 'add', STASH, 'rope', 1 } }, B.invLog)
        T.eq(1, total(B.containers[STASH], 'bread')); T.eq(1, total(B.containers[STASH], 'rope'))
        T.eq(1, total(B.containers[STASH], 'worn_rifle'), 'with the camp loot')
        local rope
        for _, it in pairs(B.containers[STASH]) do if it.name == 'rope' then rope = it end end
        T.same({ q = 1 }, rope.info, 'info survived the JSON round trip')
        T.eq(nil, ledger(B)); T.eq(nil, savedLedger(B), 'empty ledger persisted')
        -- a second clear (or a re-entry) delivers nothing
        clearCamp(B)
        T.eq(2, #B.invLog, 'no double delivery')
        T.eq(1, total(B.containers[STASH], 'bread'))
        local B2 = boot({ fh_alife_state = B.kvp.fh_alife_state })
        B2.containers[STASH] = {}
        clearCamp(B2)
        T.eq(0, #B2.invLog, 'nothing re-delivered after another restart')
    end)

    T.it('C2c steal: a refused remove records nothing; the notice says nothing was taken', function()
        local B = raidBoot(false)
        B.failRemove[CHEST] = 'fh_refused'
        B.commands.alife(1, {}, 'alife tick 6')
        for _, op in ipairs(B.invLog) do T.eq('remove', op[1], 'no add at steal time') end
        T.eq(4, total(B.containers[CHEST], 'bread')); T.eq(2, total(B.containers[CHEST], 'rope'))
        T.eq(nil, ledger(B), 'nothing recorded')
        assert(said(B, 'left without taking anything'), 'truthful notice')
        T.eq(nil, said(B, 'took from your chest'), 'never claims items it did not take')
        clearCamp(B)
        T.eq(0, total(B.containers[STASH], 'bread'), 'nothing delivered')
    end)

    T.it('C2c clear: stash add refused -> one drop bag per stack at camp coords; failed bag -> kept in ledger',
        function()
        local B = raidBoot(false)
        B.commands.alife(1, {}, 'alife tick 6')
        B.failAdd[STASH] = 'fh_too_heavy'
        clearCamp(B)
        T.eq(2, #B.bags, 'one drop bag per refused stack')
        T.same({ { name = 'bread', amount = 1 } }, B.bags[1].items)
        T.same({ { name = 'rope', amount = 1, info = { q = 1 } } }, B.bags[2].items)
        local at = B.server.ctx.camps[CAMP].loot.coords
        T.eq(at.x, B.bags[1].coords.x); T.eq(at.y, B.bags[1].coords.y)
        T.eq(at.x, B.bags[2].coords.x); T.eq(at.y, B.bags[2].coords.y)
        T.eq(nil, ledger(B), 'bagged entries leave the ledger')
        clearCamp(B)
        T.eq(2, #B.bags, 'second clear: no extra bags')
        -- partial bag failure: bread bagged, rope bag refused -> rope restored to ledger, nothing lost
        local Bp = raidBoot(false)
        Bp.commands.alife(1, {}, 'alife tick 6')
        Bp.failAdd[STASH] = 'fh_too_heavy'
        Bp.failBag = function(items)
            if items[1] and items[1].name == 'rope' then return 'fh_bag_refused' end
            return nil
        end
        clearCamp(Bp)
        T.eq(1, #Bp.bags, 'only accepted stack bagged')
        T.same({ { name = 'bread', amount = 1 } }, Bp.bags[1].items)
        T.same({ { name = 'rope', amount = 1, info = { q = 1 } } }, ledger(Bp), 'refused stack restored to ledger')
        T.same(ledger(Bp), savedLedger(Bp))
        Bp.failAdd[STASH], Bp.failBag = nil, nil
        clearCamp(Bp)
        T.eq(0, total(Bp.containers[STASH], 'bread'), 'already-bagged bread not delivered twice')
        T.eq(1, total(Bp.containers[STASH], 'rope'), 'restored rope delivered on next clear')
        T.eq(nil, ledger(Bp))
        -- all bags refused: all entries stay in the ledger (never destroyed) and the next clear delivers them
        local B2 = raidBoot(false)
        B2.commands.alife(1, {}, 'alife tick 6')
        B2.failAdd[STASH], B2.failBag = 'fh_too_heavy', 'fh_refused'
        clearCamp(B2)
        T.eq(0, #B2.bags)
        T.same({ { name = 'bread', amount = 1 }, { name = 'rope', amount = 1, info = { q = 1 } } }, ledger(B2))
        T.same(ledger(B2), savedLedger(B2))
        B2.failAdd[STASH], B2.failBag = nil, nil
        clearCamp(B2)
        T.eq(1, total(B2.containers[STASH], 'bread')); T.eq(1, total(B2.containers[STASH], 'rope'))
        T.eq(nil, ledger(B2))
    end)

    T.it('idea-959 steal: same-name stacks with different info are left alone; equal-info stacks are conserved',
        function()
        -- two revolvers (serials A and B): removeItem has no slot, so neither may be picked; bread is taken instead
        local B = raidBoot(false)
        B.containers[CHEST] = {
            [1] = { name = 'weapon_revolver', amount = 1, info = { serial = 'A' } },
            [2] = { name = 'weapon_revolver', amount = 1, info = { serial = 'B' } },
            [3] = { name = 'bread', amount = 4 },
        }
        B.commands.alife(1, {}, 'alife tick 6')
        T.same({ { 'remove', CHEST, 'bread', 1 } }, B.invLog, 'only the bread is removed (picks fewer)')
        T.same({ serial = 'A' }, B.containers[CHEST][1].info); T.same({ serial = 'B' }, B.containers[CHEST][2].info)
        T.same({ { name = 'bread', amount = 1 } }, ledger(B))
        -- two ropes with the same info: interchangeable, so whichever stack removeItem takes, the ledger is right
        local B2 = raidBoot(false)
        B2.containers[CHEST] = {
            [1] = { name = 'rope', amount = 1, info = { q = 1, tags = { 'tar' } } },
            [2] = { name = 'rope', amount = 4, info = { q = 1, tags = { 'tar' } } },
        }
        B2.commands.alife(1, {}, 'alife tick 6')
        T.same({ { 'remove', CHEST, 'rope', 1 }, { 'remove', CHEST, 'rope', 1 } }, B2.invLog)
        T.eq(3, total(B2.containers[CHEST], 'rope'))
        T.same({ { name = 'rope', amount = 1, info = { q = 1, tags = { 'tar' } } },
            { name = 'rope', amount = 1, info = { q = 1, tags = { 'tar' } } } }, ledger(B2), 'list info kept (L3)')
        T.same(ledger(B2), savedLedger(B2))
    end)

    T.it('L2 load: a saved camp ledger over lootStacksMax is trimmed on load and each dropped stack is logged',
        function()
        local big = {}
        for i = 1, 22 do big[i] = { name = 'l' .. i, amount = i } end
        local B = boot({ fh_alife_state = Json.encode({ version = 3, tick = 1, owners = {}, squads = {},
            raidLoot = { [CAMP] = big } }) })
        T.eq(20, B.raidRules.lootCount(B.server.getState(), CAMP))
        for _, want in ipairs({ 'dropped oldest 1x l1', 'dropped oldest 2x l2' }) do
            local hit = false
            for _, l in ipairs(B.printed) do
                if l:find('load: raid loot ledger ' .. CAMP .. ' full (20 stacks): ' .. want, 1, true) then hit = true end
            end
            assert(hit, 'logged: ' .. want)
        end
    end)

    T.it('C2c save resilience: non-JSON info sanitised before ledger; KVP save throw logs, notifies owner, never stops ticks',
        function()
        -- non-JSON info in chest item is sanitised by lootAdd so json.encode succeeds
        local B = raidBoot(false)
        B.containers[CHEST] = {
            [1] = { name = 'bread', amount = 4 },
            [2] = { name = 'rope', amount = 2, info = { q = 1, badFn = function() end, [1] = 'numkey' } },
        }
        B.commands.alife(1, {}, 'alife tick 6')
        T.same({ { name = 'bread', amount = 1 }, { name = 'rope', amount = 1, info = { q = 1 } } }, ledger(B))
        T.same(ledger(B), savedLedger(B), 'sanitised ledger saved cleanly to KVP')
        assert(said(B, 'took from your chest: 1x bread, 1x rope'), 'owner notified')
        -- KVP failure during steal: save is pcall-guarded, logged, notifyOwner still runs, later ticks continue
        local B2 = raidBoot(false)
        B2.failKvp = 'kvp_write_boom'
        B2.commands.alife(1, {}, 'alife tick 6')
        T.same({ { name = 'bread', amount = 1 }, { name = 'rope', amount = 1, info = { q = 1 } } }, ledger(B2))
        assert(said(B2, 'took from your chest: 1x bread, 1x rope'), 'owner still notified despite save failure')
        local loggedSaveErr = false
        for _, l in ipairs(B2.printed) do if l:find('save failed', 1, true) then loggedSaveErr = true end end
        assert(loggedSaveErr, 'save failure logged')
        local ok, err = B2.server.save()
        T.eq(false, ok); assert(tostring(err):find('kvp_write_boom', 1, true))
        -- tick loop continues after a save failure
        B2.failKvp = nil
        B2.commands.alife(1, {}, 'alife tick 1')
        T.eq(7, B2.server.getState().tick)
        T.same(ledger(B2), savedLedger(B2), 'next save persists the ledger once KVP recovers')
    end)

    T.it('C2c steal: chest unreadable -> nothing taken, owner told they rode off empty-handed', function()
        local B = raidBoot(false)
        B.containers[CHEST] = nil
        B.commands.alife(1, {}, 'alife tick 6')
        T.eq(0, #B.invLog)
        T.eq(nil, ledger(B))
        assert(said(B, 'rode off empty-handed'), 'skip notice')
        T.eq('steal', raids(B)[1].mode, 'raid still rides home')
    end)

    T.it('C2c cap: the ledger keeps lootStacksMax stacks per camp, oldest dropped (logged); /alife shows counts',
        function()
        local B = raidBoot(false)
        B.cfg.claimRaids.lootStacksMax = 3
        local st = B.server.getState()
        st.raidLoot[CAMP] = { { name = 'old1', amount = 1 }, { name = 'old2', amount = 1 } }
        B.commands.alife(1, {}, 'alife tick 6')
        T.same({ 'old2', 'bread', 'rope' }, (function()
            local o = {} for _, e in ipairs(ledger(B)) do o[#o + 1] = e.name end return o end)())
        local logged = false
        for _, l in ipairs(B.printed) do if l:find('dropped oldest 1x old1', 1, true) then logged = true end end
        assert(logged, 'drop logged')
        B.commands.alife(1, {}, 'alife')
        assert(said(B, 'raid loot: ' .. CAMP .. '=3'), '/alife ledger count')
        B.cfg.claimRaids.lootStacksMax = 20
    end)

    T.it('C2 fight: owner home -> squad spawns at the claim with owner tag alife_raid and is not swept away', function()
        local B = raidBoot(true)
        B.commands.alife(1, {}, 'alife tick 6')
        local sq = raids(B)[1]
        T.eq('fight', sq.phase)
        assert(said(B, 'The raiders are at your claim'), 'fight notice')
        B.squads.sweep()
        local sp = spawnList(B)
        T.eq(sq.strength, #sp, 'one ped per strength point')
        for _, s in ipairs(sp) do
            T.eq('alife_raid', s.spec.owner.kind); T.eq(sq.id, s.spec.owner.id)
            T.eq(CLAIM_AT.x, s.spec.coords.x); T.eq(CLAIM_AT.y, s.spec.coords.y)
        end
        B.squads.sweep()
        T.eq(0, #B.despawns, 'raid fight squads have their own branch: the non-ambush sweep leaves them')
        T.eq(sq.strength, #spawnList(B), 'no double spawn')
        -- the fight ends (fightTicks) -> withdrew -> peds despawn
        B.commands.alife(1, {}, 'alife tick ' .. B.cfg.claimRaids.fightTicks)
        T.eq('return', sq.phase)
        assert(said(B, 'pulled back'), 'withdraw notice')
        B.squads.sweep()
        T.eq(0, #spawnList(B), 'withdrawn squad despawned')
        T.eq(0, #B.wiped); T.eq(0, #B.repelled)
    end)

    T.it('C2 repelled: wiping the raid squad emits squad_wiped + raid_repelled once (same participants)', function()
        local B = raidBoot(true)
        B.commands.alife(1, {}, 'alife tick 6')
        local sq = raids(B)[1]
        local strength = sq.strength
        B.squads.sweep()
        for _, s in pairs(B.spawns) do B.healths[s.netId] = 0 end
        B.squads.sweep()
        B.squads.sweep()
        T.eq(1, #B.wiped); T.eq(1, #B.repelled, 'raid_repelled exactly once')
        T.same({ plot_id = 'p1', region_id = 'heartlands', faction = 'outlaws', camp_id = 'heartlands_t1_01',
            squad_id = sq.id, participants = { 'CID1' } }, B.repelled[1])
        T.same(B.wiped[1].participants, B.repelled[1].participants)
        T.eq('raid', B.wiped[1].goal)
        T.eq(nil, B.server.getState().squads[sq.id], 'squad gone from state')
        T.eq(strength, B.rules.getPressure(B.server.getState(), 'heartlands', 'outlaws'), 'regionPressure added')
        assert(said(B, 'drove the raiders off'), 'repel notice')
        B.commands.alife(1, {}, 'alife tick 20')
        T.eq(1, #B.repelled, 'no second repel after later ticks')
    end)

    T.it('C2 logoff mid-fight: peds despawn on playerDropped, next tick cancels the raid, no respawn', function()
        local B = raidBoot(true)
        B.commands.alife(1, {}, 'alife tick 6')
        local sq = raids(B)[1]
        B.squads.sweep()
        assert(#spawnList(B) > 0, 'fight squad up')
        B.players, B.playerPeds[1] = {}, nil
        B.env.source = 1
        B.handlers.playerDropped()
        B.squads.sweep()
        T.eq(0, #spawnList(B), 'despawned within one sweep of the logoff')
        B.commands.alife(0, {}, 'alife tick 1')
        T.eq('return', sq.phase); T.eq('owner_offline', sq.cancelled)
        B.squads.sweep()
        T.eq(0, #spawnList(B), 'a cancelled raid never re-materialises')
        T.eq(0, #B.invLog, 'nothing stolen')
    end)

    T.it('C2 logoff during the warning cancels the raid; nothing is stolen at the old arrival tick', function()
        local B = raidBoot(false)
        B.commands.alife(1, {}, 'alife tick 1')
        local sq = raids(B)[1]
        B.players = {}
        B.commands.alife(0, {}, 'alife tick 1')
        T.eq('owner_offline', sq.cancelled); T.eq('return', sq.phase)
        B.commands.alife(0, {}, 'alife tick 4')
        T.eq(0, #raids(B), 'rode home and removed')
        T.eq(0, #B.invLog)
    end)

    T.it('C2 /alife raid <plotId>: forces a raid (admin); /alife lists it via describeRaid; refusals reply', function()
        local B = raidBoot(true)
        B.commands.alife(1, {}, 'alife raid p1')
        local sq = raids(B)[1]
        assert(sq and sq.phase == 'warn', 'forced raid in warn')
        assert(said(B, 'Raid started: ' .. sq.id .. ' raid p1 by outlaws'), 'admin reply')
        assert(said(B, 'are heading for your claim'), 'owner warned')
        assert(B.kvp.fh_alife_state, 'saved')
        B.commands.alife(1, {}, 'alife')
        assert(said(B, B.raidRules.describeRaid(B.server.ctx, sq)), '/alife lists the raid line')
        B.commands.alife(1, {}, 'alife raid p1')
        assert(said(B, 'Raid on p1 refused: fh_alife_raid_live'), 'second force refused')
        B.commands.alife(1, {}, 'alife raid nope')
        assert(said(B, 'No such claim: nope'), 'unknown plot')
        B.plots.lot = claimFacts('CID1', { class = 'town_lot', raidable = false, lawSafe = true })
        B.commands.alife(1, {}, 'alife raid lot')
        assert(said(B, 'Raid on lot refused: fh_alife_not_raidable'), 'town lot never raided')
        T.eq(1, #raids(B))
    end)

    T.it('C2 no homestead -> no raids; town lots never raided by the schedule', function()
        local B = raidBoot(false)
        B.resState.fh_homestead = 'missing'
        B.commands.alife(1, {}, 'alife tick 10')
        T.eq(0, #raids(B))
        local B2 = raidBoot(false)
        B2.plots.p1 = claimFacts('CID1', { class = 'town_lot', raidable = false, lawSafe = true })
        B2.commands.alife(1, {}, 'alife tick 10')
        T.eq(0, #raids(B2))
    end)

    T.it('C2 boot: a live raid loaded from KVP survives while claims are not loaded yet (boot grace)', function()
        local B0 = raidBoot(true)
        B0.commands.alife(1, {}, 'alife raid p1')
        local saved = B0.kvp.fh_alife_state
        -- reboot: fh_homestead started but its claim cache is still empty
        local B = boot({ fh_alife_state = saved }, nil)
        B.server.rng = lo
        T.eq(1, #raids(B), 'not dropped at load (plots not passed to deserialize)')
        B.players = { '1' }; B.playerPeds[1] = 101; B.cids[1] = 'CID1'
        B.pedCoords[101] = { x = CLAIM_AT.x, y = CLAIM_AT.y, z = CLAIM_AT.z }
        B.commands.alife(1, {}, 'alife tick ' .. B.cfg.claimRaids.bootGraceTicks)
        T.eq(nil, raids(B)[1].cancelled, 'not cancelled during the grace')
        B.plots.p1 = claimFacts('CID1') -- claims loaded
        B.commands.alife(1, {}, 'alife tick 1')
        T.eq(nil, raids(B)[1].cancelled)
        -- loaded at boot with claims ready: a raid whose plot is gone is dropped by deserialize
        local B2 = boot({ fh_alife_state = saved }, nil, { beforeLoad = function(b) b.plots.other = claimFacts('X') end })
        T.eq(0, #raids(B2), 'plots passed once claims are loaded: missing plot dropped')
    end)
end)

T.finish()

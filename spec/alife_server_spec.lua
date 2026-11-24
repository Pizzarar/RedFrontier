-- Stubbed-server spec (plan a-life-01 A2): loads fh_alife's real server/main.lua with a fake fh_heat, fh_trade,
-- KVP and json, and drives the camp_cleared handler + admin command end to end. Focus: the fh_trade setShortage call,
-- the fh:alife:camp_flipped event, the KVP JSON save/load and the /alife tick admin command. fh_alife emits no heat:
-- camp_clear heat is owned by fh_heat's own fh:zones:camp_cleared listener (heatCalls stays empty, asserted below).
-- Not a substitute for a live boot: exports are captured in-process, KVP is in-memory, the tick loop thread is not run.
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local R = here .. '../server/resources/[fh]/'

-- Minimal JSON (encode/decode) for the KVP round-trip: the spec runs under plain Lua 5.4 (no CfxLua `json` global).
-- Handles the state shape (objects, strings, integers, booleans, null); no arrays are needed by fh_alife state.
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
local function boot(preKvp, ambush)
    local B = {
        exported = {}, handlers = {}, commands = {}, broadcasts = {}, flipped = {}, heatCalls = {},
        shortageCalls = {}, printed = {}, kvp = preKvp or {},
        spawns = {}, despawns = {}, wiped = {}, healths = {}, nextReq = 1,
        players = {}, playerPeds = {}, pedCoords = {},
    }
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
        },
    }, { __call = function(_, name, fn) B.exported[name] = fn end })
    local env = setmetatable({
        exports = exportsT,
        GetCurrentResourceName = function() return 'fh_alife' end,
        GetResourceState = function() return 'started' end,
        GetPlayers = function() return B.players end,
        GetPlayerPed = function(src) return B.playerPeds[src] or 0 end,
        GetEntityCoords = function(e) return B.pedCoords[e] end,
        GetEntityHealth = function(e) return B.healths[e] or 100 end,
        NetworkGetEntityFromNetworkId = function(netId) return netId end,
        DoesEntityExist = function(e) return e ~= 0 end,
        GetGameTimer = function() return 0 end,
        SetResourceKvp = function(k, v) B.kvp[k] = v end,
        GetResourceKvpString = function(k) return B.kvp[k] end,
        TriggerEvent = function(name, payload)
            if name == 'fh:alife:camp_flipped' then B.flipped[#B.flipped + 1] = payload end
            if name == 'fh:alife:squad_wiped' then B.wiped[#B.wiped + 1] = payload end
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
    if ambush then
        for rid, list in pairs(ambush) do env.FhRegions.regions[rid].ambush = list end
    end
    run(R .. 'fh_core/shared/place_resolver.lua')
    run(R .. 'fh_zones/config.lua')
    run(R .. 'fh_alife/config.lua')
    run(R .. 'fh_alife/shared/alife_rules.lua')
    run(R .. 'fh_alife/server/main.lua')
    run(R .. 'fh_alife/server/squads.lua')
    B.cfg = env.FhAlifeConfig
    B.rules = env.FhAlifeRules
    B.server = env.FhAlifeServer
    B.squads = env.FhAlifeSquads
    return B
end

T.describe('fh_alife server wiring (stubbed server)', function()
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
        local B = boot() -- real FhRegions: no ambush data anywhere
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
        T.same({ squad_id = 'sq1', goal = 'ambush', faction = 'outlaws', node = 'heartlands_amb_bend',
            camp_id = 'heartlands_t1_01', region_id = 'heartlands', label = 'Dakota bend' }, B.wiped[1])
        T.eq(nil, st.squads.sq1, 'squad removed from state')
    end)

    T.it('/alife lists squads by goal, node and strength; prints "no ambush nodes" for empty regions', function()
        -- no ambush data: every camp region prints "<region>: no ambush nodes"
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
end)

T.finish()

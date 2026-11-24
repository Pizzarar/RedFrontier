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

---Boot a fresh copy of server/main.lua. `preKvp` = the KVP store to load from. Returns a probe table with captured
---exports, handlers, commands, KVP writes and cross-resource calls.
local function boot(preKvp)
    local B = {
        exported = {}, handlers = {}, commands = {}, broadcasts = {}, flipped = {}, heatCalls = {},
        shortageCalls = {}, kvp = preKvp or {},
    }
    local exportsT = setmetatable({
        -- fh_heat is stubbed as a spy: fh_alife must NOT call addSource (camp_clear heat is fh_heat's own job).
        fh_heat = { addSource = function(_, src, faction, key)
            B.heatCalls[#B.heatCalls + 1] = { src, faction, key } return true, 1 end },
        fh_trade = { setShortage = function(_, region, item, level)
            B.shortageCalls[#B.shortageCalls + 1] = { region, item, level } return true end },
    }, { __call = function(_, name, fn) B.exported[name] = fn end })
    local env = setmetatable({
        exports = exportsT,
        GetCurrentResourceName = function() return 'fh_alife' end,
        GetResourceState = function() return 'started' end,
        GetPlayers = function() return {} end, GetPlayerPed = function() return 0 end, GetGameTimer = function() return 0 end,
        SetResourceKvp = function(k, v) B.kvp[k] = v end,
        GetResourceKvpString = function(k) return B.kvp[k] end,
        TriggerEvent = function(name, payload)
            if name == 'fh:alife:camp_flipped' then B.flipped[#B.flipped + 1] = payload end
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
        print = function() end,
    }, { __index = _G })
    env._G = env
    for _, p in ipairs({ R .. 'fh_core/shared/regions.lua', R .. 'fh_zones/config.lua', R .. 'fh_alife/config.lua',
        R .. 'fh_alife/shared/alife_rules.lua', R .. 'fh_alife/server/main.lua' }) do
        local fh = assert(io.open(p, 'rb')); local src = fh:read('a'); fh:close()
        assert(load(src, '@' .. p, 't', env))()
    end
    B.cfg = env.FhAlifeConfig
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
            if b[1] == -1 and b[2].args[2]:find('Valentine Law has taken', 1, true) then found = true end
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
end)

T.finish()

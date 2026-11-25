-- Stubbed-server spec for the rsg-character new-character path (rf-fp2-char).
-- Loads the real server/sv_appearance.lua with a fake rsg-core, MySQL, json and natives, and drives:
--   1. SaveSkin for a brand-new character that never picked clothes: the configured default outfit is substituted,
--      saved, and sent back to the client via rsg-character:client:ApplySkin, so the first spawn is not underwear.
--   2. createCharacter no longer grants starter items (no add-item toasts over the creator): they are granted once
--      on RSGCore:Server:OnPlayerLoaded (first spawn), keyed by citizenid.
-- Not a live boot: exports/natives are fakes, MySQL is in-memory, and the shared/functions.lua validation
-- (ValidateClothesData / RSG.IsValidBirthdate, which need the 10 MB data/clothing.lua) is stubbed.
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local CHAR = here .. '../server/resources/[rsg]/rsg-character/'

-- Minimal JSON (encode/decode) for the skin/clothes round-trip (plain Lua 5.4 has no CfxLua `json` global).
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
            pos = pos + 1
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
                    local k = str(); skip(); pos = pos + 1
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

-- Same hashes as RSG.DefaultClothes in rsg-character/shared/config.lua.
local DEFAULT_MALE = { shirts_full = { hash = 2795762245 }, pants = { hash = 1094172669 }, boots = { hash = 4076107613 } }
local DEFAULT_FEMALE = { shirts_full = { hash = 3726847883 }, pants = { hash = 3545812420 }, boots = { hash = 3723064563 } }
local STARTER_ITEMS = { { item = 'bread', amount = 2 }, { item = 'water', amount = 2 }, { item = 'bandage', amount = 1 } }

local function loadInto(env, rel)
    local p = CHAR .. rel
    local fh = assert(io.open(p, 'rb')); local src = fh:read('a'); fh:close()
    assert(load(src, '@' .. p, 't', env))()
end

local function boot()
    local W = { handlers = {}, sent = {}, localEvents = {}, players = {}, addItemCalls = {}, skins = {} }

    local RSGCore = {
        Functions = {
            GetPlayer = function(src) return W.players[src] end,
            CreateCallback = function(_, fn) end,
            GetIdentifier = function(_, kind) return 'license:test' end,
        },
        Shared = { Items = {
            bread = { name = 'bread', label = 'Bread Bun' },
            water = { name = 'water', label = 'Water' },
            bandage = { name = 'bandage', label = 'Bandage' },
        } },
        Player = {
            Login = function(src, _, data)
                W.players[src] = { PlayerData = { charinfo = data.charinfo, citizenid = 'CID' .. data.cid } }
            end,
        },
    }

    local exportsT = setmetatable({
        ['rsg-core'] = { GetCoreObject = function() return RSGCore end },
        ['rsg-inventory'] = { AddItem = function(_, src, name, amount, ...)
            W.addItemCalls[#W.addItemCalls + 1] = { src = src, name = name, amount = amount } return true
        end },
    }, { __index = function() return nil end })

    local env = setmetatable({
        exports = exportsT,
        RSG = {
            DefaultClothes = { male = DEFAULT_MALE, female = DEFAULT_FEMALE },
            StarterItems = STARTER_ITEMS,
            Nationalities = { 'american' },
            ProfanityWords = {},
            UniqueNames = false,
            IsValidBirthdate = function() return true end, -- shared/functions.lua (not loaded: needs 10 MB data)
            WebhookIdentityFields = function() return {} end,
            SendWebhook = function() end,
        },
        ValidateClothesData = function() return true end, -- shared/functions.lua (not loaded)
        MySQL = {
            update = { await = function(_, params) W.skins[params[3]] = { skin = params[1], clothes = params[2] } return 1 end },
            insert = { await = function() return 1 end },
            scalar = { await = function() return nil end },
            single = { await = function() return nil end },
        },
        json = Json,
        locale = function(k, ...) return k end,
        GetCurrentResourceName = function() return 'rsg-character' end,
        LoadResourceFile = function() return nil end,
        RegisterNetEvent = function(name, fn) W.handlers[name] = fn end,
        AddEventHandler = function(name, fn) W.handlers[name] = fn end,
        TriggerClientEvent = function(name, target, ...) W.sent[#W.sent + 1] = { name = name, target = target, args = table.pack(...) } end,
        TriggerEvent = function(name, ...) W.localEvents[#W.localEvents + 1] = { name = name, args = table.pack(...) } end,
        GetPlayerRoutingBucket = function() return 0 end,
        SetRoutingBucketPopulationEnabled = function() end,
        SetPlayerRoutingBucket = function() end,
        GetPlayerPed = function() return 0 end,
        GetEntityCoords = function() return { x = 0, y = 0, z = 0 } end,
        print = function() end,
    }, { __index = _G })
    env._G = env
    loadInto(env, 'server/sv_appearance.lua')
    W.env = env

    function W.setNewSession(src, gender)
        env.CreatorSessions[src] = { cid = 1, isNew = true, created = true }
        W.players[src] = { PlayerData = { charinfo = { gender = gender or 0 }, citizenid = 'CID1' } }
    end
    function W.fire(src, name, ...) env.source = src; W.handlers[name](...) end
    function W.sentNamed(name) local o = {} for _, e in ipairs(W.sent) do if e.name == name then o[#o + 1] = e end end return o end
    function W.savedClothes(cid) local r = W.skins[cid] return r and Json.decode(r.clothes) or nil end
    return W
end

T.describe('rsg-character new-character path (sv_appearance.lua)', function()
    T.describe('SaveSkin default outfit (naked-spawn fix)', function()
        T.it('a new character with empty clothes is sent the default outfit via ApplySkin, not underwear', function()
            local W = boot()
            W.setNewSession(1, 0) -- male
            W.fire(1, 'rsg-character:server:SaveSkin', {}, {})

            local apply = W.sentNamed('rsg-character:client:ApplySkin')
            T.eq(1, #apply, 'ApplySkin sent once')
            T.same(DEFAULT_MALE, apply[1].args[2], 'client receives the substituted default clothes')
            T.eq(1, apply[1].args[1].sex, 'skin carries the server-set sex')

            local spawn = W.sentNamed('rsg-character:client:OpenSpawnSelect')
            T.eq(1, #spawn, 'OpenSpawnSelect follows ApplySkin')
            T.eq(true, spawn[1].args[2], 'isNew flag passed to the spawn flow')

            T.same(DEFAULT_MALE, W.savedClothes('CID1'), 'default outfit is what gets persisted')
        end)

        T.it('a female new character with empty clothes gets the female default outfit', function()
            local W = boot()
            W.setNewSession(1, 1)
            W.fire(1, 'rsg-character:server:SaveSkin', {}, {})
            T.same(DEFAULT_FEMALE, W.sentNamed('rsg-character:client:ApplySkin')[1].args[2])
            T.same(DEFAULT_FEMALE, W.savedClothes('CID1'))
        end)

        T.it('clothes the player actually picked are left untouched and still sent to the client', function()
            local W = boot()
            W.setNewSession(1, 0)
            local picked = { shirts_full = { hash = 2795762245 } }
            W.fire(1, 'rsg-character:server:SaveSkin', {}, picked)
            T.same(picked, W.sentNamed('rsg-character:client:ApplySkin')[1].args[2], 'picked clothes are not replaced')
        end)
    end)

    T.describe('starter items deferred to first spawn (creator-toast fix)', function()
        T.it('createCharacter grants nothing (no add-item toast over the creator)', function()
            local W = boot()
            W.env.CreatorSessions[1] = { cid = 1, isNew = true, created = false }
            W.fire(1, 'rsg-multicharacter:server:createCharacter', {
                cid = 1, firstname = 'John', lastname = 'Doe',
                nationality = 'nationalities.american', birthdate = '1870-01-01', gender = 0,
            })
            T.eq(0, #W.addItemCalls, 'no AddItem during character creation')
            T.eq(0, #W.sentNamed('rsg-inventory:client:ItemBox'), 'no item-box toast over the creator')
            T.eq('CID1', W.players[1] and W.players[1].PlayerData.citizenid, 'character logged in')
        end)

        T.it('first spawn (OnPlayerLoaded) grants the starter kit exactly once', function()
            local W = boot()
            W.env.CreatorSessions[1] = { cid = 1, isNew = true, created = false }
            W.fire(1, 'rsg-multicharacter:server:createCharacter', {
                cid = 1, firstname = 'John', lastname = 'Doe',
                nationality = 'nationalities.american', birthdate = '1870-01-01', gender = 0,
            })
            W.fire(1, 'RSGCore:Server:OnPlayerLoaded')
            local want = { { src = 1, name = 'bread', amount = 2 }, { src = 1, name = 'water', amount = 2 }, { src = 1, name = 'bandage', amount = 1 } }
            T.same(want, W.addItemCalls, 'starter kit granted on first spawn')

            W.fire(1, 'RSGCore:Server:OnPlayerLoaded')
            T.eq(3, #W.addItemCalls, 'a second load does not re-grant')
        end)

        T.it('a returning character with no pending grant gets nothing on load', function()
            local W = boot()
            W.players[1] = { PlayerData = { charinfo = { gender = 0 }, citizenid = 'CID9' } }
            W.fire(1, 'RSGCore:Server:OnPlayerLoaded')
            T.eq(0, #W.addItemCalls)
        end)
    end)
end)

T.finish()

-- Stubbed-server spec for the rsg-character new-character path (rf-fp2-char).
-- Loads the real server/sv_appearance.lua with a fake rsg-core, MySQL, json and natives, and drives:
--   1. SaveSkin for a brand-new character that never picked clothes: the configured default outfit is substituted,
--      saved, and sent back to the client via rsg-character:client:ApplySkin, so the first spawn is not underwear.
--   2. createCharacter no longer grants starter items (no add-item toasts over the creator): they are granted once
--      on RSGCore:Server:OnPlayerLoaded (first spawn), keyed by citizenid.
--   3. core-10 I2: the pending grant is a row in a fake `fh_starter_granted` table (not resource memory), so a
--      restart between create and first spawn still grants once, a concurrent spawn grants once (atomic claim), a
--      deleted character's row does not affect other characters, and a failed grant is logged, never retried.
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

-- Fake MariaDB table fh_starter_granted (PK citizenid). Shared across boot() calls to model a restart: resource
-- memory is rebuilt, the DB survives. `fail = true` makes every starter query raise (DB down / table missing).
local function newDb() return { starter = {}, fail = false } end

-- Tables rsg-core's deleteCharacterRows clears (parsed from the real player.lua, so the spec follows the edit).
local function rsgCoreDeleteTables()
    local fh = assert(io.open(here .. '../server/resources/[rsg]/rsg-core/server/player.lua', 'rb'))
    local src = fh:read('a'); fh:close()
    local block = assert(src:match('local playertables = (%b{})'), 'playertables block')
    local out = {}
    for name in block:gmatch("table%s*=%s*'([^']+)'") do out[name] = true end
    return out
end

local function boot(opts)
    opts = opts or {}
    local db = opts.db or newDb()
    local W = { handlers = {}, sent = {}, localEvents = {}, players = {}, addItemCalls = {}, skins = {}, logs = {}, db = db }

    local function starterQuery(q) return q:find('fh_starter_granted', 1, true) ~= nil end
    -- Real oxmysql awaits yield the handler's coroutine; W.yieldClaims models that so two loads can interleave.
    -- The UPDATE itself runs atomically on resume, as MariaDB serialises it on the row.
    local function claim(params)
        if W.yieldClaims and coroutine.isyieldable() then coroutine.yield('db') end
        if db.fail then error('fake db: starter query failed') end
        local row = db.starter[params[1]]
        if row and row.granted == 0 then row.granted = 1 return 1 end
        return 0
    end

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
            if opts.addItem then return opts.addItem(W, src, name, amount) end
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
            update = { await = function(q, params)
                if starterQuery(q) then return claim(params) end
                W.skins[params[3]] = { skin = params[1], clothes = params[2] } return 1
            end },
            insert = { await = function(q, params)
                if starterQuery(q) then
                    if db.fail then error('fake db: starter query failed') end
                    db.starter[params[1]] = { granted = 0 } -- INSERT ... ON DUPLICATE KEY UPDATE granted = 0
                    return 0
                end
                return 1
            end },
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
        print = function(...) W.logs[#W.logs + 1] = table.concat({ ... }, ' ') end,
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
    function W.create(src, cid)
        env.CreatorSessions[src] = { cid = cid, isNew = true, created = false }
        W.fire(src, 'rsg-multicharacter:server:createCharacter', {
            cid = cid, firstname = 'John', lastname = 'Doe',
            nationality = 'nationalities.american', birthdate = '1870-01-01', gender = 0,
        })
    end
    -- rsg-core DeleteCharacter: deletes the citizenid from every table in its playertables list.
    function W.deleteCharacter(citizenid)
        if rsgCoreDeleteTables()['fh_starter_granted'] then db.starter[citizenid] = nil end
    end
    function W.logged(pat) for _, l in ipairs(W.logs) do if l:find(pat, 1, true) then return true end end return false end
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

T.describe('starter items from DB state (core-10 I2)', function()
    local KIT = 3 -- STARTER_ITEMS entries

    T.it('no in-memory pending map remains; the migration keys fh_starter_granted by citizenid', function()
        local fh = assert(io.open(CHAR .. 'server/sv_appearance.lua', 'rb')); local src = fh:read('a'); fh:close()
        T.eq(nil, src:find('pendingStarterItems', 1, true), 'pendingStarterItems map removed')
        local mf = assert(io.open(here .. '../server/migrations/0023_fh_starter_granted.sql', 'rb'))
        local sql = mf:read('a'); mf:close()
        T.eq(true, sql:find('CREATE TABLE IF NOT EXISTS `fh_starter_granted`', 1, true) ~= nil, 'idempotent create')
        T.eq(true, sql:find('PRIMARY KEY (`citizenid`)', 1, true) ~= nil, 'unique per citizenid')
    end)

    T.it('a restart between create and first spawn still grants exactly once', function()
        local db = newDb()
        local before = boot({ db = db })
        before.create(1, 1)
        T.eq(0, #before.addItemCalls, 'nothing granted in the creator')
        T.same({ granted = 0 }, db.starter.CID1, 'pending row written at create')

        local after = boot({ db = db }) -- resource/server restart: memory gone, DB kept
        after.players[1] = { PlayerData = { charinfo = { gender = 0 }, citizenid = 'CID1' } }
        after.fire(1, 'RSGCore:Server:OnPlayerLoaded')
        T.eq(KIT, #after.addItemCalls, 'first spawn after the restart grants the kit')
        after.fire(1, 'RSGCore:Server:OnPlayerLoaded')
        local again = boot({ db = db })
        again.players[1] = { PlayerData = { charinfo = { gender = 0 }, citizenid = 'CID1' } }
        again.fire(1, 'RSGCore:Server:OnPlayerLoaded')
        T.eq(KIT, #after.addItemCalls, 'a later load in the same run grants nothing')
        T.eq(0, #again.addItemCalls, 'a load after another restart grants nothing')
        T.eq(1, db.starter.CID1.granted, 'row claimed')
    end)

    T.it('two interleaved first-spawn loads for one character grant once (atomic claim)', function()
        local W = boot()
        W.create(1, 1)
        W.players[2] = { PlayerData = { charinfo = { gender = 0 }, citizenid = 'CID1' } } -- same character, 2nd src
        W.yieldClaims = true
        local a = coroutine.create(function() W.fire(1, 'RSGCore:Server:OnPlayerLoaded') end)
        local b = coroutine.create(function() W.fire(2, 'RSGCore:Server:OnPlayerLoaded') end)
        T.eq('db', select(2, coroutine.resume(a)), 'load A waits on its claim')
        T.eq('db', select(2, coroutine.resume(b)), 'load B waits on its claim before A finishes')
        assert(coroutine.resume(a)); assert(coroutine.resume(b))
        T.eq('dead', coroutine.status(a)); T.eq('dead', coroutine.status(b))
        T.eq(KIT, #W.addItemCalls, 'exactly one kit across both loads')
    end)

    T.it('two server runs sharing the DB grant once between them', function()
        local db = newDb()
        local A, B = boot({ db = db }), boot({ db = db })
        A.create(1, 1)
        B.players[7] = { PlayerData = { charinfo = { gender = 0 }, citizenid = 'CID1' } }
        A.fire(1, 'RSGCore:Server:OnPlayerLoaded')
        B.fire(7, 'RSGCore:Server:OnPlayerLoaded')
        T.eq(KIT, #A.addItemCalls + #B.addItemCalls, 'one kit total')
    end)

    T.it('deleting an unspawned character leaves no row, and other characters are unaffected', function()
        local W = boot()
        W.create(1, 1) -- CID1, never spawned
        W.create(2, 2) -- CID2
        W.deleteCharacter('CID1')
        T.eq(nil, W.db.starter.CID1, 'rsg-core DeleteCharacter drops the fh_starter_granted row')
        T.same({ granted = 0 }, W.db.starter.CID2, 'other character row untouched')
        W.fire(2, 'RSGCore:Server:OnPlayerLoaded')
        T.eq(KIT, #W.addItemCalls, 'CID2 still gets its kit once')
    end)

    T.it('a reused citizenid after delete is a fresh character and gets one kit, even over a stale granted row', function()
        local W = boot()
        W.create(1, 1); W.fire(1, 'RSGCore:Server:OnPlayerLoaded')
        T.eq(KIT, #W.addItemCalls)
        -- worst case: the delete did not reach the row (e.g. table added after the delete ran), so a granted row stays
        W.db.starter.CID1 = { granted = 1 }
        W.players[1] = nil -- logged out to char select, where the delete happens
        W.create(1, 1) -- rsg-core hands out CID1 again (CreateCitizenId only checks `players`)
        W.fire(1, 'RSGCore:Server:OnPlayerLoaded'); W.fire(1, 'RSGCore:Server:OnPlayerLoaded')
        T.eq(2 * KIT, #W.addItemCalls, 'new character on the reused id gets exactly one kit')
    end)

    T.it('a failed AddItem after the claim is logged and never retried (no double grant)', function()
        local db = newDb()
        local W = boot({ db = db, addItem = function(W, src, name, amount)
            if name == 'water' then error('inventory exploded') end
            W.addItemCalls[#W.addItemCalls + 1] = { src = src, name = name, amount = amount } return name ~= 'bandage'
        end })
        W.create(1, 1)
        W.fire(1, 'RSGCore:Server:OnPlayerLoaded')
        T.same({ { src = 1, name = 'bread', amount = 2 }, { src = 1, name = 'bandage', amount = 1 } }, W.addItemCalls,
            'a throw on one item does not stop the rest')
        T.eq(true, W.logged('water x2 NOT granted to CID1'), 'thrown item logged')
        T.eq(true, W.logged('bandage x1 NOT granted to CID1'), 'refused item logged')
        T.eq(1, db.starter.CID1.granted, 'claim stays taken')
        W.fire(1, 'RSGCore:Server:OnPlayerLoaded')
        T.eq(2, #W.addItemCalls, 'next load does not retry')
    end)

    T.it('a DB error grants nothing and does not break character creation', function()
        local db = newDb()
        db.fail = true
        local W = boot({ db = db })
        W.create(1, 1)
        T.eq('CID1', W.players[1] and W.players[1].PlayerData.citizenid, 'creation still logs the character in')
        local created = false
        for _, e in ipairs(W.localEvents) do if e.name == 'rsg-character:server:characterCreated' then created = true end end
        T.eq(true, created, 'characterCreated still fires')
        T.eq(true, W.logged('could not mark CID1 pending'), 'mark failure logged')
        W.fire(1, 'RSGCore:Server:OnPlayerLoaded')
        T.eq(0, #W.addItemCalls, 'claim failure grants nothing')
        T.eq(true, W.logged('claim failed for CID1'), 'claim failure logged')
    end)
end)

T.finish()

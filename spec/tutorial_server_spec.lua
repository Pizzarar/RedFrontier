-- fh_tutorial stubbed-server spec (guide-02): loads the real server/main.lua the way FXServer loads it (a number as
-- the chunk argument, the manifest's shared-script order, GetCurrentResourceName defined), then replays a NEW
-- character's load exactly as rsg-core/rsg-character fire it, and checks the greeting only auto-starts once the
-- character is actually in the game world.
--
-- This is the gap the pure tutorial_spec.lua cannot cover: it only loads shared/tutorial.lua, never the server glue.
-- The live bug was that the server auto-started on RSGCore:Server:PlayerLoaded, which rsg-core fires when the Player
-- object is created (rsg-core/server/player.lua:462) — for a brand-new character that is still inside the creator
-- (rsg-multicharacter:server:createCharacter), so the notify was hidden and its 2.5s ack advanced the tutorial before
-- the player spawned. The server must instead auto-start on RSGCore:Server:OnPlayerLoaded, the net event
-- rsg-character's client fires after the spawn teleport (rsg-character/client/spawn.lua:111).
local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
local T = dofile(here .. 'support/fh_prelude.lua')
local R = here .. '../server/resources/[fh]/'

local loaded = {}        -- event name -> handler (server-local events via AddEventHandler)
local netEvents = {}     -- event name -> handler (net events via RegisterNetEvent)
local clientEvents = {}  -- { { event = name, src = src, payload = payload } }
local commands = {}      -- command name -> handler
local mysqlWrites = {}   -- captured MySQL.update calls (saveRecord)
local registered = {}    -- quest defs seen by registerQuest
local started = {}       -- { src, quest_id } seen by start
local fhQuestDefs = {}   -- fake fh_quests registry: quest_id -> def
local activeBySrc = {}   -- fake fh_quests active state: src -> { quest_id = step }
local players = {}       -- src -> { PlayerData = { source, citizenid } }
local tutorialRows = {}  -- citizenid -> { skipped = bool } (the fh_tutorial_state table)

local function addHandler(name, fn) loaded[name] = fn end
local function trigger(name, payload)
    local fn = loaded[name]
    if fn then return fn(payload) end
end

-- The fh_quests exports fh_tutorial builds against. registerQuest/start/abandon/getActive/talk are the only ones
-- fh_tutorial calls (fh_tutorial/README.md "Server exports"); they mirror the real contract closely enough to exercise
-- the auto-start path end to end, including the fh:quests:started echo that routes the prompt back to the client.
local fh_quests = {
    registerQuest = function(_, def)
        registered[#registered + 1] = def
        fhQuestDefs[def.id] = def
        return true
    end,
    start = function(_, src, quest_id)
        started[#started + 1] = { src = src, quest_id = quest_id }
        if not fhQuestDefs[quest_id] then return false, 'fh_unknown_quest' end
        activeBySrc[src] = activeBySrc[src] or {}
        activeBySrc[src][quest_id] = 1
        -- The real Q.commit emits fh:quests:started after the state is saved (fh_quests/shared/intake.lua M.emits,
        -- payload { citizenid, quest_id, kind, step }); the tutorial's prompt routing listens for it. Echo it
        -- synchronously, as FXServer's TriggerEvent is synchronous.
        local cid = players[src] and players[src].PlayerData and players[src].PlayerData.citizenid
        trigger('fh:quests:started', { citizenid = cid, quest_id = quest_id, kind = 'tutorial', step = 1 })
        return true
    end,
    talk = function(_, src, npc) return true end,
    abandon = function(_, src, quest_id) activeBySrc[src] = activeBySrc[src] or {}; activeBySrc[src][quest_id] = nil; return true end,
    getActive = function(_, src)
        local out = {}
        for qid, step in pairs(activeBySrc[src] or {}) do out[#out + 1] = { quest_id = qid, step = step } end
        return out
    end,
}

local exportsT = {
    fh_quests = fh_quests,
    ['rsg-core'] = {
        GetCoreObject = function()
            return {
                Functions = {
                    -- fh_tutorial calls core().Functions.GetPlayer(src) with DOT syntax (one arg), unlike the
                    -- exports['rsg-core']:GetPlayer(src) colon form fh_economy uses.
                    GetPlayer = function(src) return players[src] end,
                },
            }
        end,
    },
}

local MySQL = {
    query = { await = function(q, params)
        assert(q:find('fh_tutorial_state', 1, true), q)
        local row = tutorialRows[params[1]]
        if not row then return {} end
        return { { skipped = row.skipped and 1 or 0 } }
    end },
    update = { await = function(q, params)
        assert(q:find('fh_tutorial_state', 1, true), q)
        mysqlWrites[#mysqlWrites + 1] = { citizenid = params[1], skipped = params[2], updated_at = params[3] }
        tutorialRows[params[1]] = { skipped = params[2] == 1 }
        return 1
    end },
}

local env = setmetatable({
    exports = exportsT, MySQL = MySQL,
    GetCurrentResourceName = function() return 'fh_tutorial' end,
    GetResourceState = function(res) return 'started' end,
    GetGameTimer = function() return 1000 end,
    GetPlayers = function() return {} end,
    CreateThread = function(fn) fn() end, -- run synchronously; Wait is a no-op so register()/restore threads run now
    Wait = function() end,
    AddEventHandler = addHandler,
    RegisterNetEvent = function(name, fn) netEvents[name] = fn end,
    RegisterCommand = function(name, fn) commands[name] = fn end,
    TriggerEvent = trigger,
    TriggerClientEvent = function(name, src, payload)
        clientEvents[#clientEvents + 1] = { event = name, src = src, payload = payload }
    end,
    print = function() end,
    source = nil,
    os = os,
}, { __index = _G })
env._G = env

-- Load the real files in the manifest's shared-script order, each with a NUMBER chunk argument (FXServer passes a
-- number as `...`, not nil — see spec/quests_chunk_arg_spec.lua and the C0 regression).
local function loadChunk(path, ...)
    local fh = assert(io.open(path, 'rb'))
    local src = fh:read('a'); fh:close()
    local fn, err = load(src, '@' .. path, 't', env)
    assert(fn, err)
    return fn(...)
end
loadChunk(R .. 'fh_tutorial/config.lua', 7)
loadChunk(R .. 'fh_tutorial/shared/tutorial.lua', 7)
loadChunk(R .. 'fh_tutorial/server/main.lua', 7)

local GreetingText = 'Welcome to RedFrontier. This short guide covers your first day and never blocks you (skip any time with /tutorial skip).'

local function mkPlayer(src, cid)
    players[src] = { PlayerData = { source = src, citizenid = cid } }
    return players[src]
end

-- Fire the net event RSGCore:Server:OnPlayerLoaded the way rsg-character's client does (TriggerServerEvent): `source`
-- is the player, no payload.
local function fireOnPlayerLoaded(src)
    local prev = rawget(env, 'source')
    rawset(env, 'source', src)
    local fn = netEvents['RSGCore:Server:OnPlayerLoaded']
    assert(fn, 'RSGCore:Server:OnPlayerLoaded net handler not registered')
    fn()
    rawset(env, 'source', prev)
end

local function prompts()
    local out = {}
    for _, e in ipairs(clientEvents) do
        if e.event == 'fh:tutorial:prompt' then out[#out + 1] = e end
    end
    return out
end
local function chatLines()
    local out = {}
    for _, e in ipairs(clientEvents) do
        if e.event == 'chat:addMessage' then out[#out + 1] = e end
    end
    return out
end

T.describe('fh_tutorial server: registration (loaded the FXServer way)', function()
    T.it('registerQuest receives the tutorial def with the config order', function()
        T.eq(1, #registered)
        local def = registered[1]
        T.eq('tutorial_intro', def.id)
        T.eq('tutorial', def.kind)
        T.eq('heartlands', def.region_id)
        T.eq(12, #def.steps)
        T.eq('greeting', def.steps[1].id)
    end)
    T.it('registers the spawn-time net event, not just the Player-object event', function()
        T.eq('function', type(netEvents['RSGCore:Server:OnPlayerLoaded']))
    end)
end)

T.describe('fh_tutorial server: a NEW character auto-starts on spawn, not in the creator', function()
    T.it('the Player object loading (creator, for a new character) does not auto-start', function()
        local src, cid = 1, 'BRANDNEW'
        mkPlayer(src, cid)
        local nStart, nPrompts = #started, #prompts()
        -- rsg-core fires this with the Player object when the object is created (during Login, inside the creator).
        trigger('RSGCore:Server:PlayerLoaded', players[src])
        T.eq(nStart, #started, 'must not auto-start on RSGCore:Server:PlayerLoaded')
        T.eq(nPrompts, #prompts(), 'must not prompt while still in the creator')
        T.eq(0, #mysqlWrites, 'must not persist an auto-start yet')
    end)
    T.it('the spawn event starts the quest and the greeting reaches the client (prompt + chat line)', function()
        local src, cid = 1, 'BRANDNEW'
        local nClient = #clientEvents
        fireOnPlayerLoaded(src)
        T.eq(1, #started)
        T.eq(src, started[1].src)
        T.eq('tutorial_intro', started[1].quest_id)
        local ps = prompts()
        T.eq(1, #ps)
        T.eq(src, ps[1].src)
        T.eq(GreetingText, ps[1].payload.text)
        T.same({ check = 'greeting', after_ms = 2500 }, ps[1].payload.ack)
        T.eq(nil, ps[1].payload.waypoint, 'the greeting has no waypoint')
        local chats = chatLines()
        T.eq(1, #chats)
        T.same({ 'Tutorial', GreetingText }, chats[1].payload.args)
        T.eq(src, chats[1].src)
        -- the auto-start flag is persisted after a successful start
        T.eq(1, #mysqlWrites)
        T.eq(cid, mysqlWrites[1].citizenid)
        T.eq(0, mysqlWrites[1].skipped)
        T.eq(#clientEvents, nClient + 2)
    end)
    T.it('a spammed or faked repeat of the spawn event neither restarts nor re-prompts', function()
        local nStart, nPrompts, nWrites = #started, #prompts(), #mysqlWrites
        for _ = 1, 3 do fireOnPlayerLoaded(1) end
        T.eq(nStart, #started)
        T.eq(nPrompts, #prompts())
        T.eq(nWrites, #mysqlWrites)
    end)
    T.it('no prompt reaches a character who has not spawned yet (step events before OnPlayerLoaded)', function()
        local src, cid = 4, 'INCREATOR'
        mkPlayer(src, cid)
        trigger('RSGCore:Server:PlayerLoaded', players[src])
        local nPrompts = #prompts()
        trigger('fh:quests:step', { citizenid = cid, quest_id = 'tutorial_intro', step = 9 })
        T.eq(nPrompts, #prompts())
    end)
    T.it('a character with a row (started before) does not auto-start on spawn', function()
        local src, cid = 2, 'RETURNING'
        mkPlayer(src, cid)
        tutorialRows[cid] = { skipped = false }
        local nStart = #started
        fireOnPlayerLoaded(src)
        T.eq(nStart, #started)
    end)
    T.it('a skipped character does not auto-start on spawn', function()
        local src, cid = 3, 'SKIPPED'
        mkPlayer(src, cid)
        tutorialRows[cid] = { skipped = true }
        local nStart = #started
        fireOnPlayerLoaded(src)
        T.eq(nStart, #started)
    end)
end)

T.finish()

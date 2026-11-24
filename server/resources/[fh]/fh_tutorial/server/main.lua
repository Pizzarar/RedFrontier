-- fh_tutorial server (guide-02): register the intro tutorial on the fh_quests API, auto-start it on a new
-- character's first load, advance the client-check / survival / giver steps through fh_quests.talk, and back the
-- /tutorial commands. Persistence: the quest's done/step state lives in fh_quest_state (via fh_quests); the
-- skip/auto-start flag lives in fh_tutorial_state (server/migrations/0016_fh_tutorial.sql).
--
-- fh_quests is a hard dependency (ensured first in server.cfg), so its exports are always available. The tutorial
-- only ever calls the public exports registerQuest / start / abandon / talk / getActive; it never writes fh_quests'
-- tables and never feeds its intake directly.
local T = FhTutorial

local srcOf = {}    -- citizenid -> src (online characters)
local lastLoad = {} -- src -> game time (ms) of the character's load; survival buffs are restored on load

local function core() return exports['rsg-core']:GetCoreObject() end

local function citizenidOf(src)
    if type(src) ~= 'number' or src < 1 then return nil end
    local ok, p = pcall(function() return core().Functions.GetPlayer(src) end)
    return ok and p and p.PlayerData and p.PlayerData.citizenid or nil
end

local function questsReady() return GetResourceState('fh_quests') == 'started' end

-- ------------------------------------------------------------------ registration
local function register()
    if not questsReady() then return end
    local ok, err = exports.fh_quests:registerQuest(T.def)
    if not ok then print(('[fh_tutorial] registerQuest failed: %s'):format(tostring(err))) end
end
CreateThread(function() Wait(0) register() end)
AddEventHandler('onResourceStart', function(res)
    if res == 'fh_quests' then register() end -- re-register if fh_quests restarts out from under us
end)

-- ------------------------------------------------------------------ prompts
-- One client event carries the text, the GPS waypoint (nil = clear the route) and an optional ack: for an
-- informational step with no player action, the client reports the step's check after `after_ms` on screen.
local function sendPrompt(src, text, waypoint, ack)
    TriggerClientEvent('fh:tutorial:prompt', src, {
        text = text,
        waypoint = waypoint and { x = waypoint.x, y = waypoint.y, z = waypoint.z, label = waypoint.label } or nil,
        ack = ack,
    })
end

local function stepPrompt(i)
    local step = T.stepOf(T.def, i)
    if not step then return nil end
    local ack = step.ack_ms and step.check and { check = step.check, after_ms = step.ack_ms } or nil
    return step.text, T.waypointOf(step), ack
end

AddEventHandler('fh:quests:started', function(p)
    if type(p) ~= 'table' or p.quest_id ~= T.QUEST_ID then return end
    local src = srcOf[p.citizenid]
    if src then
        local text, wp, ack = stepPrompt(p.step)
        sendPrompt(src, text, wp, ack)
    end
end)
AddEventHandler('fh:quests:step', function(p)
    if type(p) ~= 'table' or p.quest_id ~= T.QUEST_ID then return end
    local src = srcOf[p.citizenid]
    if src then
        local text, wp, ack = stepPrompt(p.step)
        sendPrompt(src, text, wp, ack)
    end
end)
AddEventHandler('fh:quests:completed', function(p)
    if type(p) ~= 'table' or p.quest_id ~= T.QUEST_ID then return end
    local src = srcOf[p.citizenid]
    if src then sendPrompt(src, 'Tutorial complete — you know your way around now. Stay sharp out there.') end
end)

-- ------------------------------------------------------------------ persistence (skip / auto-start flag)
local SKIP_SELECT = 'SELECT skipped FROM fh_tutorial_state WHERE citizenid = ?'
local SKIP_UPSERT = 'INSERT INTO fh_tutorial_state (citizenid, skipped, updated_at) VALUES (?, ?, ?) '
    .. 'ON DUPLICATE KEY UPDATE skipped = VALUES(skipped), updated_at = VALUES(updated_at)'

---@return table|nil record  nil = no row; { skipped = bool } otherwise
local function loadRecord(cid)
    local ok, rows = pcall(MySQL.query.await, SKIP_SELECT, { cid })
    if not ok or type(rows) ~= 'table' or rows[1] == nil then return nil end
    local s = rows[1].skipped
    return { skipped = (s == 1 or s == true) }
end

local function saveRecord(cid, skipped)
    pcall(MySQL.update.await, SKIP_UPSERT, { cid, skipped and 1 or 0, os.time() })
end

-- ------------------------------------------------------------------ client checks + survival + cargo
-- Client reports a check; the server maps it to a synthetic talk npc. talk() only advances when the current step is
-- that npc's talk step, so a stray or forged report is a no-op.
RegisterNetEvent('fh:tutorial:check', function(checkId)
    local npc = T.checkNpc(checkId)
    if not npc or not questsReady() then return end
    exports.fh_quests:talk(source, npc)
end)

-- Eat/drink: a real server event (fh_buffs). Ignore the buffs fh_survival re-applies during character load, so a
-- relog does not skip the step.
AddEventHandler('fh:buffs:applied', function(p)
    if type(p) ~= 'table' or not T.SURVIVAL_BUFFS[p.buff_id] then return end
    local src = p.src
    if type(src) ~= 'number' or src < 1 then return end
    if GetGameTimer() - (lastLoad[src] or 0) < 10000 then return end
    if not questsReady() then return end
    exports.fh_quests:talk(src, T.SURVIVAL_NPC)
end)

-- Cargo: a real server event (fh:cargo:wagon_spawned). The payload carries the owner's src, so the tutorial calls
-- talk for that source directly; only the wagon owner's tutorial can advance.
AddEventHandler(T.CARGO_EVENT, function(p)
    if type(p) ~= 'table' then return end
    local src = p.src
    if type(src) ~= 'number' or src < 1 then return end
    if not questsReady() then return end
    exports.fh_quests:talk(src, T.CARGO_NPC)
end)

-- ------------------------------------------------------------------ commands
local function activeStep(src)
    if not questsReady() then return nil end
    local entries = exports.fh_quests:getActive(src)
    if type(entries) ~= 'table' then return nil end
    for _, e in ipairs(entries) do
        if e.quest_id == T.QUEST_ID then return e.step end
    end
    return nil
end

RegisterCommand('tutorial', function(src, args)
    if type(src) ~= 'number' or src < 1 then return end
    local cid = citizenidOf(src)
    local sub = args and args[1]

    if sub == 'skip' then
        if not cid then return end
        if questsReady() then exports.fh_quests:abandon(src, T.QUEST_ID) end -- ignore result (fh_not_active is fine)
        saveRecord(cid, true)
        sendPrompt(src, 'Tutorial skipped. Bring it back any time with /tutorial restart.')
        return
    end

    if sub == 'restart' then
        if not cid then return end
        saveRecord(cid, false)
        if questsReady() then
            exports.fh_quests:abandon(src, T.QUEST_ID) -- ignore result; abandons only an active run
            exports.fh_quests:start(src, T.QUEST_ID)   -- repeatable (cooldown 0): restarts even after done
        end
        return
    end

    -- No subcommand: show the current step and re-set its waypoint.
    local step = activeStep(src)
    if step then
        local text, wp, ack = stepPrompt(step)
        sendPrompt(src, text, wp, ack)
    else
        sendPrompt(src, 'No active tutorial. Use /tutorial restart to replay it.')
    end
end, false)

-- ------------------------------------------------------------------ lifecycle
AddEventHandler('RSGCore:Server:PlayerLoaded', function(Player)
    local d = Player and Player.PlayerData
    if not (d and type(d.source) == 'number' and type(d.citizenid) == 'string') then return end
    local src, cid = d.source, d.citizenid
    srcOf[cid] = src
    lastLoad[src] = GetGameTimer()
    local record = loadRecord(cid)
    if T.shouldAutoStart(record) then
        local ok = false
        if questsReady() then ok = exports.fh_quests:start(src, T.QUEST_ID) end
        -- Persist only after a successful start; otherwise retry on the next load (a failed start must not
        -- permanently burn the one auto-start).
        if ok == true then saveRecord(cid, false) end
    else
        -- Returning character: started/step events are not replayed on load, so show the in-flight step again.
        -- (The greeting has no player action; without this a relog during it would wait for /tutorial.) Retry
        -- briefly in case fh_quests has not finished its own load yet.
        CreateThread(function()
            for _ = 1, 10 do
                if questsReady() then
                    local step = activeStep(src)
                    if step then
                        local text, wp, ack = stepPrompt(step)
                        sendPrompt(src, text, wp, ack)
                    end
                    return
                end
                Wait(500)
            end
        end)
    end
end)

local function forget(src)
    for cid, s in pairs(srcOf) do
        if s == src then srcOf[cid] = nil end
    end
    lastLoad[src] = nil
end
AddEventHandler('RSGCore:Server:OnPlayerUnload', function(src) forget(src) end)
AddEventHandler('playerDropped', function() forget(tonumber(source)) end)

-- Resource restart with players online: their PlayerLoaded won't re-fire, so restore srcOf (prompt routing).
CreateThread(function()
    Wait(0)
    for _, id in ipairs(GetPlayers()) do
        local src = tonumber(id)
        local cid = citizenidOf(src)
        if cid then srcOf[cid] = src end
    end
end)

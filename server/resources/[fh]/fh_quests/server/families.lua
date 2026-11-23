-- Q4: load the family questline data files and register them through the public registerQuest export, at start.
-- registerQuest replaces by id, so a restart re-registers cleanly.
local FILES = { 'hale', 'marrow', 'whitlock' }

CreateThread(function()
    Wait(0) -- api.lua's exports are registered by now
    for _, name in ipairs(FILES) do
        local path = ('data/families/%s.lua'):format(name)
        local src = LoadResourceFile(GetCurrentResourceName(), path)
        local chunk, lerr = load(src or '', '@' .. path)
        local ok, def = false, nil
        if chunk then ok, def = pcall(chunk) end
        if not ok or type(def) ~= 'table' then
            FhQuestsServer.log('family %s failed to load: %s', name, tostring(lerr or def or 'file missing'))
        else
            local rok, err = exports.fh_quests:registerQuest(def)
            if not rok then FhQuestsServer.log('family %s rejected: %s', name, tostring(err)) end
        end
    end
end)

-- Giver NPCs: spawned at fixed points through fh_core (unowned, persistent for the resource run).
local G = FhQuestsGivers
local function spawnGivers()
    for _, id in ipairs(G.ORDER) do
        local g = G[id]
        local c = g.coords
        local reqId, err = exports.fh_core:requestSpawn({
            kind = 'ped', model = g.model, coords = vector4(c.x, c.y, c.z, c.w),
            owner = { kind = 'quest', id = 'giver:' .. id }, tag = 'fh_quests:giver:' .. id,
        }, {
            near = vector3(c.x, c.y, c.z),
            onFailed = function(reason) FhQuestsServer.log('giver %s spawn failed: %s', id, tostring(reason)) end,
        })
        if not reqId then FhQuestsServer.log('giver %s spawn refused: %s', id, tostring(err)) end
    end
end
CreateThread(function() Wait(1000) spawnGivers() end)

-- WORKAROUND (plan quests-01 Q4): callbacks for the ox_lib giver dialogue (client/givers.lua). Thin, whitelisted
-- over the public exports. Replaced by the @ui quest journal/dialogue screen.
-- Proximity is enforced HERE, in the net handlers, because they are the only client-reachable path: the talk/start
-- exports are server-only and also serve non-giver callers (other resources, npc ids with no fixed point), so they
-- cannot know a position. The @ui screen's own net handler must run the same check (FhQuestsGivers.within).
-- Position = the player's server-side ped vs the giver's fixed point (the ped is spawned there and frozen).
local function near(src, giver)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false end
    return G.within(giver, GetEntityCoords(ped))
end

lib.callback.register('fh:quests:giver:talk', function(src, npc_id)
    local g = G.get(npc_id)
    if not g then return false, 'fh_bad_npc' end
    if not near(src, g) then return false, 'fh_too_far' end
    return exports.fh_quests:talk(src, npc_id)
end)

lib.callback.register('fh:quests:giver:start', function(src, quest_id)
    local g = G.byQuest(quest_id)
    if not g then return false, 'fh_unknown_quest' end
    if not near(src, g) then return false, 'fh_too_far' end
    return exports.fh_quests:start(src, quest_id)
end)

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
lib.callback.register('fh:quests:giver:talk', function(src, npc_id)
    if type(npc_id) ~= 'string' or not G[npc_id] then return false, 'fh_bad_npc' end
    return exports.fh_quests:talk(src, npc_id)
end)

lib.callback.register('fh:quests:giver:start', function(src, quest_id)
    local ok = false
    for _, id in ipairs(G.ORDER) do if G[id].quest == quest_id then ok = true end end
    if not ok then return false, 'fh_unknown_quest' end
    return exports.fh_quests:start(src, quest_id)
end)

-- Q4: load the family questline data files and register them through the public registerQuest export, at start.
-- registerQuest replaces by id, so a restart re-registers cleanly.
local FILES = { 'hale', 'marrow', 'whitlock', 'cormier', 'ashby' } -- cormier (Lemoyne), ashby (West Elizabeth): C6

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

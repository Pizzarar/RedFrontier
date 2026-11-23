-- WORKAROUND (plan quests-01 Q4): ox_lib text dialogue for the family giver NPCs, opened with rsg-target. It shows
-- the talk lines, calls the server talk export (so talk steps advance) and offers to start a line not yet started.
-- Replaced by the @ui quest journal/dialogue screen; delete this file, the callbacks in server/families.lua and the
-- fxmanifest line then. No NUI. The giver peds are spawned server side (fh_core requestSpawn); the target zone sits
-- at the same fixed point, TODO-verify-in-game.
local G = FhQuestsGivers

local function say(g, lines)
    for _, line in ipairs(lines) do
        lib.alertDialog({ header = g.label, content = line, centered = true, labels = { confirm = 'Next' } })
    end
end

local function talkTo(g)
    local ok, err, dialogue = lib.callback.await('fh:quests:giver:talk', false, g.npc)
    if not ok then
        return lib.notify({ title = g.label, description = 'Not now (' .. tostring(err) .. ').', type = 'error' })
    end
    local spoke = false
    for _, d in ipairs(dialogue or {}) do
        spoke = true
        say(g, d.lines or {})
    end
    for _, qid in ipairs((dialogue or {}).offers or {}) do
        if qid == g.quest then
            say(g, g.intro or {})
            local a = lib.alertDialog({ header = g.label, content = 'Will you take the job?', centered = true, cancel = true,
                labels = { confirm = 'I will', cancel = 'Not yet' } })
            if a == 'confirm' then
                local sok, serr = lib.callback.await('fh:quests:giver:start', false, qid)
                lib.notify({ title = g.label, description = sok and 'Quest started.' or tostring(serr),
                    type = sok and 'success' or 'error' })
            end
            return
        end
    end
    if not spoke then
        lib.notify({ title = g.label, description = 'Nothing more to say right now.', type = 'inform' })
    end
end

CreateThread(function()
    if GetResourceState('rsg-target') ~= 'started' then return end
    for _, id in ipairs(G.ORDER) do
        local g = G[id]
        exports['rsg-target']:addSphereZone({
            coords = vector3(g.coords.x, g.coords.y, g.coords.z), radius = 1.5, debug = false,
            options = { { label = 'Talk to ' .. g.label, icon = 'fa-solid fa-comments', distance = 2.5,
                onSelect = function() talkTo(g) end } },
        })
    end
end)

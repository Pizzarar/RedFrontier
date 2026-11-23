-- fh_ui jobs board + journal glue (plan ui-wiring W2/W3). Thin: the client opens the board, fh_ui relays `accept`, and the
-- answer goes back as `fh:ui:update` (a notice-only update; the board itself arrives via fh:quests:sync).
local T = FhQuestsUiText
local regions = FhRegions.regions

RegisterNetEvent('fh:quests:ui_open', function(region_id)
    local src = source
    if type(region_id) ~= 'string' or #region_id > 48 or not regions[region_id] then return end
    local view, err = exports.fh_quests:getBoard(src, region_id)
    if not view then
        TriggerClientEvent('fh:ui:open', src, { screen = 'jobs', data = { region_id = region_id, expires_at = 0,
            offers = {}, notice = T.TEXT[err] or T.DEFAULT, notice_kind = 'error' } })
        return
    end
    -- Same shape the fh_ui client adapter builds from fh:quests:sync.
    TriggerClientEvent('fh:ui:open', src, { screen = 'jobs', data = {
        region_id = view.region_id, expires_at = view.expires_at, offers = view.offers } })
end)

-- fh_ui relay: fh:ui:action { screen = 'jobs', action = 'accept' } -> this event { src, screen, action, payload }.
AddEventHandler('fh:quests:ui_accept', function(ev)
    if type(ev) ~= 'table' or type(ev.src) ~= 'number' then return end
    local src, p = ev.src, ev.payload
    local ok, err = false, 'fh_offer_gone'
    if type(p) == 'table' and type(p.id) == 'string' and #p.id <= 128 then
        ok, err = exports.fh_quests:acceptOffer(src, p.id)
        -- acceptOffer already syncs on success; refresh the board only on refusal so the offer list is current
        local region = not ok and p.id:match('^([^:]+):') or nil
        if region and regions[region] then exports.fh_quests:getBoard(src, region) end
    end
    TriggerClientEvent('fh:ui:update', src, { screen = 'jobs', data = T.acceptNotice(ok, err) })
end)

-- W3: /journal. The screen opens empty-handed; the fh_ui client adapter fills it from the player's last fh:quests:sync
-- (journal rows + history). A player whose character is not loaded gets the screen with an error notice instead.
RegisterNetEvent('fh:quests:ui_journal_open', function()
    local src = source
    local _, err = exports.fh_quests:getActive(src)
    local data = { entries = {} }
    if err then data.notice, data.notice_kind = T.journalOpenText(err), 'error' end
    TriggerClientEvent('fh:ui:open', src, { screen = 'journal', data = data })
end)

-- fh_ui relay: fh:ui:action { screen = 'journal', action = 'abandon', payload = { id } } -> this event. Server-local
-- (fh_ui does TriggerEvent), so AddEventHandler receives it; clients cannot fire it directly.
AddEventHandler('fh:quests:ui_abandon', function(ev)
    if type(ev) ~= 'table' or type(ev.src) ~= 'number' then return end
    local src, p = ev.src, ev.payload
    local ok, err = false, 'fh_not_active'
    if type(p) == 'table' and type(p.id) == 'string' and #p.id <= 128 then
        ok, err = exports.fh_quests:abandon(src, p.id)
    end
    -- abandon() already pushes a fresh fh:quests:sync on success; the notice goes separately.
    TriggerClientEvent('fh:ui:update', src, { screen = 'journal', data = T.abandonNotice(ok, err) })
end)

-- Giver dialogue (plan ui-giver-dialogue D2). The reach check lives HERE, in the net handlers, because they are the only
-- client-reachable path: the talk/start exports are server-only and also serve non-giver callers, so they cannot know a
-- position. Never trust client coords: position = the player's server-side ped vs the giver's fixed point.
local G = FhQuestsGivers
local D = FhQuestsDialogue
local function near(src, giver)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false end
    return G.within(giver, GetEntityCoords(ped))
end

RegisterNetEvent('fh:quests:ui_talk', function(npc_id)
    local src = source
    if type(npc_id) ~= 'string' or #npc_id > 48 then return end
    local g = G.get(npc_id)
    local data
    if not g then return end -- not a giver: nothing to show a speaker for
    if not near(src, g) then
        data = T.talkRefused(g, 'fh_too_far')
    else
        local ok, err, dialogue = exports.fh_quests:talk(src, npc_id)
        data = ok and D.build(g, dialogue) or T.talkRefused(g, err)
    end
    TriggerClientEvent('fh:ui:open', src, { screen = 'dialogue', data = data })
end)

-- fh_ui relay: fh:ui:action { screen = 'dialogue', action = 'start', payload = { quest_id } } -> this event.
AddEventHandler('fh:quests:ui_start', function(ev)
    if type(ev) ~= 'table' or type(ev.src) ~= 'number' then return end
    local src, p = ev.src, ev.payload
    local ok, err = false, 'fh_unknown_quest'
    if type(p) == 'table' and type(p.quest_id) == 'string' and #p.quest_id <= 128 then
        local g = G.byQuest(p.quest_id)
        if g then
            if not near(src, g) then
                err = 'fh_too_far'
            else
                ok, err = exports.fh_quests:start(src, p.quest_id)
            end
        end
    end
    TriggerClientEvent('fh:ui:update', src, { screen = 'dialogue', data = T.startNotice(ok, err) })
end)

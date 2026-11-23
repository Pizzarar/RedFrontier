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
    end
    local region = p and type(p.id) == 'string' and p.id:match('^([^:]+):') or nil
    if region and regions[region] then exports.fh_quests:getBoard(src, region) end -- refresh via sync (also on refusal)
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

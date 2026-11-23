-- fh_ui jobs board glue (plan ui-wiring W2). Thin: the client opens the board, fh_ui relays `accept`, and the
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

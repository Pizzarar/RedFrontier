-- fh_ui client adapter: producer events -> `fh:ui:update` for screens that are open. Pure mapping lives in
-- shared/quests_view.lua; add a feed there (W3: journal) and it is picked up here. Not runtime-tested (no Cfx key).
local view = FhUiQuestsView
local ui = FhUiClient -- set by client/main.lua

FH.onNet('fh:quests:sync', function(snap)
    if type(snap) ~= 'table' then return end
    local now = GetCloudTimeAsInt and GetCloudTimeAsInt() or nil
    for screen, feed in pairs(view.feeds) do
        if ui.isOpen(screen) then
            local ok, data = pcall(feed, snap, now)
            if ok and data ~= nil then ui.update(screen, data) end
        end
    end
end)

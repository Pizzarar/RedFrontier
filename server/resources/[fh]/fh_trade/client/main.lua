-- fh_trade client: /tradepost opens the fh_ui `tradepost` screen (no ox_lib menu; @ui owns screens). The server decides
-- everything (post proximity, prices, items, payout) and re-sends the screen data; this only opens it and keeps the
-- chat fallbacks (/tradequote, /tradesell, /tradebuy). Not runtime-tested (no Cfx key).

RegisterCommand('tradepost', function() TriggerServerEvent('fh:trade:menu') end, false)

RegisterNetEvent('fh:trade:sold', function(r)
    if type(r) == 'table' then lib.notify({ title = 'Trade post', description = ('Sold for $%d'):format(tonumber(r.total) or 0), type = 'success' }) end
end)

RegisterNetEvent('fh:trade:bought', function(r)
    if type(r) == 'table' then lib.notify({ title = 'Trade post', description = ('Bought for $%d'):format(tonumber(r.total) or 0), type = 'success' }) end
end)

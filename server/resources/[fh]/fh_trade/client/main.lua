-- fh_trade client: ox_lib context-menu fallback for the trade post (no NUI; @ui owns screens). The server decides
-- everything (post proximity, prices, items, payout); this only shows its menu data and sends the choice back.
-- Not runtime-tested (no Cfx key).

RegisterCommand('tradepost', function() TriggerServerEvent('fh:trade:menu') end, false)

RegisterNetEvent('fh:trade:menu', function(data)
    if type(data) ~= 'table' or type(data.goods) ~= 'table' then return end
    local options = {}
    for _, g in ipairs(data.goods) do
        local hot = (g.shortage or 0) >= 0.15
        options[#options + 1] = {
            title = ('%s  $%.2f'):format(g.label, g.price),
            description = hot and 'In demand here' or (g.saturation or 0) > 0.3 and 'Market is flooded' or nil,
            onSelect = function()
                local input = lib.inputDialog(g.label, {
                    { type = 'number', label = 'Amount to sell', default = 1, min = 1, max = data.maxAmount, required = true },
                })
                if input and input[1] then TriggerServerEvent('fh:trade:sell', g.item, math.floor(input[1])) end
            end,
        }
    end
    for _, e in ipairs(data.supplies or {}) do
        options[#options + 1] = {
            title = ('Buy %s  $%d'):format(e.label, e.price),
            onSelect = function()
                local input = lib.inputDialog('Buy ' .. e.label, {
                    { type = 'number', label = 'Amount to buy', default = 1, min = 1, max = data.maxBuy, required = true },
                })
                if input and input[1] then TriggerServerEvent('fh:trade:buy', e.item, math.floor(input[1])) end
            end,
        }
    end
    lib.registerContext({ id = 'fh_trade_post', title = data.label or 'Trade Post', options = options })
    lib.showContext('fh_trade_post')
end)

RegisterNetEvent('fh:trade:sold', function(r)
    if type(r) == 'table' then lib.notify({ title = 'Trade post', description = ('Sold for $%d'):format(tonumber(r.total) or 0), type = 'success' }) end
end)

RegisterNetEvent('fh:trade:bought', function(r)
    if type(r) == 'table' then lib.notify({ title = 'Trade post', description = ('Bought for $%d'):format(tonumber(r.total) or 0), type = 'success' }) end
end)

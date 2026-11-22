-- fh_economy: the only path for payouts and rep (spec 4.6). Every call writes a ledger row.
local cfg = FhEconomyConfig
local logic = FhLedgerLogic
local regions = FhRegions
local ctx = { isKnownRegion = regions.isKnownRegion, maxPay = cfg.maxPay, maxRepDelta = cfg.maxRepDelta,
    maxReason = cfg.maxReason }

local function getPlayer(src)
    if not logic.validSrc(src) then return nil end
    -- rsg-core/server/api.lua exports GetPlayer; nil when no character is loaded
    return exports['rsg-core']:GetPlayer(src)
end

local INSERT_LEDGER = 'INSERT INTO fh_ledger (citizenid, kind, amount, reason, region_id) VALUES (?, ?, ?, ?, ?)'

---Pay: ledger row FIRST, then AddMoney. If the money step fails the row is deleted again
---(it is our own just-inserted row), so there is never money without a row nor a row without money.
---@return boolean ok, string? err, integer? ledgerId
local function pay(src, amount, reason, region_id)
    local ok, err = logic.validatePay({ amount = amount, reason = reason, region_id = region_id }, ctx)
    if not ok then return false, err end
    local Player = getPlayer(src)
    if not Player then return false, 'no_player' end
    local citizenid = Player.PlayerData.citizenid

    local inserted, id = pcall(MySQL.insert.await, INSERT_LEDGER, { citizenid, 'pay', amount, reason, region_id })
    if not inserted or not id then return false, 'ledger_failed' end

    -- Player.Functions.AddMoney(moneytype, amount, reason) -> boolean (rsg-core/server/player.lua:353)
    local called, added = pcall(Player.Functions.AddMoney, cfg.moneyType, amount, reason)
    if not called or not added then
        local voided = pcall(MySQL.update.await, 'DELETE FROM fh_ledger WHERE id = ?', { id })
        if not voided then print(('[fh_economy] WARNING: could not void ledger row %s after failed AddMoney'):format(id)) end
        return false, 'addmoney_refused'
    end

    TriggerEvent('fh:economy:paid', { src = src, citizenid = citizenid, amount = amount,
        reason = reason, region_id = region_id, ledger_id = id })
    return true, nil, id
end

---Rep: atomic clamped `value = value + delta` upsert plus ledger insert in one transaction.
---@return boolean ok, string? err
local function rep(src, region_id, delta, reason)
    local ok, err = logic.validateRep({ delta = delta, reason = reason, region_id = region_id }, ctx)
    if not ok then return false, err end
    local Player = getPlayer(src)
    if not Player then return false, 'no_player' end
    local citizenid = Player.PlayerData.citizenid

    local done, committed = pcall(MySQL.transaction.await, {
        { query = 'INSERT INTO fh_rep (citizenid, region_id, `value`) VALUES (?, ?, LEAST(?, GREATEST(?, ?))) '
            .. 'ON DUPLICATE KEY UPDATE `value` = LEAST(?, GREATEST(?, `value` + ?))',
          values = { citizenid, region_id, cfg.repMax, cfg.repMin, delta, cfg.repMax, cfg.repMin, delta } },
        { query = INSERT_LEDGER, values = { citizenid, 'rep', delta, reason, region_id } },
    })
    if not done or not committed then return false, 'ledger_failed' end

    -- The write already committed: a failed read-back must not turn into a failure. Emit with value = nil instead.
    local readOk, value = pcall(MySQL.scalar.await, 'SELECT `value` FROM fh_rep WHERE citizenid = ? AND region_id = ?',
        { citizenid, region_id })
    if not readOk then value = nil end
    TriggerEvent('fh:economy:rep_changed', { src = src, citizenid = citizenid, region_id = region_id,
        delta = delta, value = value, reason = reason })
    return true
end

exports('pay', pay)
exports('rep', rep)

-- Server-console test helpers (source 0 only): `fh_pay <serverId> <amount>`, `fh_rep <serverId> <delta>`
RegisterCommand('fh_pay', function(source, args)
    if source ~= 0 then return end
    print(json.encode({ pay(tonumber(args[1]), tonumber(args[2]), 'console_test', 'heartlands') }))
end, true)
RegisterCommand('fh_rep', function(source, args)
    if source ~= 0 then return end
    print(json.encode({ rep(tonumber(args[1]), 'heartlands', tonumber(args[2]), 'console_test') }))
end, true)

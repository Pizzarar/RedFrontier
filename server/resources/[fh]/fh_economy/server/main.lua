-- fh_economy: the only path for payouts and rep (spec 4.6). Every call writes an append-only ledger row.
local cfg = FhEconomyConfig
local logic = FhLedgerLogic
local regions = FhRegions
local ctx = { isKnownRegion = regions.isKnownRegion, maxPay = cfg.maxPay, maxRepDelta = cfg.maxRepDelta }

local function getPlayer(src)
    -- rsg-core/server/api.lua exports GetPlayer
    return exports['rsg-core']:GetPlayer(src)
end

local function insertLedger(citizenid, kind, value, reason, regionId)
    return MySQL.insert.await(
        'INSERT INTO fh_ledger (citizenid, kind, amount, reason, region_id) VALUES (?, ?, ?, ?, ?)',
        { citizenid, kind, value, reason, regionId })
end

---@return boolean ok, string? err, integer? ledgerId
local function pay(src, amount, reason, region_id)
    local ok, err = logic.validatePay({ amount = amount, reason = reason, region_id = region_id }, ctx)
    if not ok then return false, err end
    local Player = getPlayer(src)
    if not Player then return false, 'no_player' end
    -- Player.Functions.AddMoney(moneytype, amount, reason) -> boolean (rsg-core/server/player.lua:353)
    if not Player.Functions.AddMoney(cfg.moneyType, amount, reason) then return false, 'addmoney_refused' end
    local citizenid = Player.PlayerData.citizenid
    local id = insertLedger(citizenid, 'pay', amount, reason, region_id)
    TriggerEvent('fh:economy:paid', { src = src, citizenid = citizenid, amount = amount,
        reason = reason, region_id = region_id, ledger_id = id })
    return true, nil, id
end

---@return boolean ok, string? err, integer? ledgerId
local function rep(src, region_id, delta, reason)
    local ok, err = logic.validateRep({ delta = delta, reason = reason, region_id = region_id }, ctx)
    if not ok then return false, err end
    local Player = getPlayer(src)
    if not Player then return false, 'no_player' end
    local citizenid = Player.PlayerData.citizenid
    local current = MySQL.scalar.await('SELECT `value` FROM fh_rep WHERE citizenid = ? AND region_id = ?',
        { citizenid, region_id }) or 0
    local value = logic.applyRep(current, delta, cfg.repMin, cfg.repMax)
    MySQL.insert.await(
        'INSERT INTO fh_rep (citizenid, region_id, `value`) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE `value` = VALUES(`value`)',
        { citizenid, region_id, value })
    local id = insertLedger(citizenid, 'rep', delta, reason, region_id)
    TriggerEvent('fh:economy:rep_changed', { src = src, citizenid = citizenid, region_id = region_id,
        delta = delta, value = value, reason = reason, ledger_id = id })
    return true, nil, id
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

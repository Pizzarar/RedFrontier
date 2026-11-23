-- fh_economy: the only path for payouts and rep (spec 4.6). Every call writes a ledger row.
local cfg = FhEconomyConfig
local logic = FhLedgerLogic
local regions = FhRegions
local ctx = { isKnownRegion = regions.isKnownRegion, maxPay = cfg.maxPay, maxRepDelta = cfg.maxRepDelta,
    maxCharge = cfg.maxCharge, maxReason = cfg.maxReason }

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

---Charge (debit, B7): mirror of pay. Balance check, ledger row (kind='charge') FIRST, then RemoveMoney; a refused
---RemoveMoney deletes our own just-inserted row again. Never goes negative. Sequence: FhLedgerLogic.runCharge.
---@return boolean ok, string? err, integer? ledgerId
local function charge(src, amount, reason, region_id)
    local ok, err = logic.validateCharge({ amount = amount, reason = reason, region_id = region_id }, ctx)
    if not ok then return false, err end
    local Player = getPlayer(src)
    if not Player then return false, 'no_player' end
    local citizenid = Player.PlayerData.citizenid

    local done, why, id = logic.runCharge({
        balance = function()
            local money = Player.PlayerData.money
            return type(money) == 'table' and tonumber(money[cfg.moneyType]) or nil
        end,
        insert = function()
            local inserted, newId = pcall(MySQL.insert.await, INSERT_LEDGER, { citizenid, 'charge', amount, reason, region_id })
            return inserted and newId or nil
        end,
        -- Player.Functions.RemoveMoney(moneytype, amount, reason) -> boolean (rsg-core/server/player.lua:368)
        remove = function()
            local called, removed = pcall(Player.Functions.RemoveMoney, cfg.moneyType, amount, reason)
            return called and removed == true
        end,
        void = function(rowId) return (pcall(MySQL.update.await, 'DELETE FROM fh_ledger WHERE id = ?', { rowId })) end,
        warn = function(rowId)
            print(('[fh_economy] WARNING: could not void ledger row %s after failed RemoveMoney'):format(rowId))
        end,
    }, amount)
    if not done then return false, why end

    TriggerEvent('fh:economy:charged', { src = src, citizenid = citizenid, amount = amount,
        reason = reason, region_id = region_id, ledger_id = id })
    return true, nil, id
end

---Rep value for a character in a region: integer, 0 when there is no row. `who` = player server id, or a
---citizenid string (offline reads, e.g. fh_progression's loader).
---@return integer|nil rep, string? err
local function getRep(who, region_id)
    if not regions.isKnownRegion(region_id) then return nil, 'unknown_region' end
    local citizenid
    if type(who) == 'string' then
        -- an all-digit string is a mistyped server id, not a citizenid: refuse instead of reading "no row" = 0
        if not who:match('%S') or who:match('^%s*%d+%s*$') then return nil, 'no_player' end
        citizenid = who
    else
        local Player = getPlayer(who)
        if not Player then return nil, 'no_player' end
        citizenid = Player.PlayerData.citizenid
    end
    local readOk, value = pcall(MySQL.scalar.await, 'SELECT `value` FROM fh_rep WHERE citizenid = ? AND region_id = ?',
        { citizenid, region_id })
    if not readOk then return nil, 'ledger_failed' end
    return logic.repValue(value)
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
exports('charge', charge)
exports('getRep', getRep)

-- Server-console test helpers (source 0 only): `fh_pay <serverId> <amount>`, `fh_rep <serverId> <delta>`,
-- `fh_charge <serverId> <amount>`
RegisterCommand('fh_pay', function(source, args)
    if source ~= 0 then return end
    print(json.encode({ pay(tonumber(args[1]), tonumber(args[2]), 'console_test', 'heartlands') }))
end, true)
RegisterCommand('fh_rep', function(source, args)
    if source ~= 0 then return end
    print(json.encode({ rep(tonumber(args[1]), 'heartlands', tonumber(args[2]), 'console_test') }))
end, true)
RegisterCommand('fh_charge', function(source, args)
    if source ~= 0 then return end
    print(json.encode({ charge(tonumber(args[1]), tonumber(args[2]), 'console_test', 'heartlands') }))
end, true)

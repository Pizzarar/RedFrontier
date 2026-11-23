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
local VOID_LEDGER = 'DELETE FROM fh_ledger WHERE id = ?'

---Fresh lookup of the character a call started for. Every MySQL await yields, and during the yield the player can
---drop or switch character: after a yield, call this again and never touch the Player object from before it.
---@return table|nil Player, string? err  'no_player' (gone) | 'player_changed' (another character on this src)
local function playerFor(src, citizenid)
    local Player = getPlayer(src)
    if not Player then return nil, 'no_player' end
    if type(Player.PlayerData) ~= 'table' or Player.PlayerData.citizenid ~= citizenid then return nil, 'player_changed' end
    return Player
end

-- Our own just-inserted row (the only DELETE on fh_ledger), true when it went through.
local function voidRow(rowId) return (pcall(MySQL.update.await, VOID_LEDGER, { rowId })) end

local function warnVoid(rowId, why)
    print(('[fh_economy] WARNING: could not void ledger row %s after a failed money step (%s)'):format(rowId, why))
end

-- citizenid of the character loaded on src, looked up once before any yield; nil when none is loaded.
local function loadedCitizenid(src)
    local Player = getPlayer(src)
    local citizenid = Player and type(Player.PlayerData) == 'table' and Player.PlayerData.citizenid
    if type(citizenid) ~= 'string' or citizenid == '' then return nil end
    return citizenid
end

---Pay: ledger row FIRST, then AddMoney on a Player looked up again after the insert yield. If the player left or
---switched character during the yield, or AddMoney fails, our own just-inserted row is deleted again, so there is
---never money without a row nor a row without money. Sequence: FhLedgerLogic.runPay.
---@return boolean ok, string? err, integer? ledgerId
local function pay(src, amount, reason, region_id)
    local ok, err = logic.validatePay({ amount = amount, reason = reason, region_id = region_id }, ctx)
    if not ok then return false, err end
    local citizenid = loadedCitizenid(src)
    if not citizenid then return false, 'no_player' end

    local done, why, id = logic.runPay({
        player = function() return playerFor(src, citizenid) end,
        insert = function()
            local inserted, newId = pcall(MySQL.insert.await, INSERT_LEDGER, { citizenid, 'pay', amount, reason, region_id })
            return inserted and newId or nil
        end,
        -- Player.Functions.AddMoney(moneytype, amount, reason) -> boolean (rsg-core/server/player.lua:353)
        add = function(Player)
            local called, added = pcall(Player.Functions.AddMoney, cfg.moneyType, amount, reason)
            return called and added == true
        end,
        void = voidRow,
        warn = warnVoid,
    })
    if not done then return false, why end

    TriggerEvent('fh:economy:paid', { src = src, citizenid = citizenid, amount = amount,
        reason = reason, region_id = region_id, ledger_id = id })
    return true, nil, id
end

-- citizenid -> true while a charge for that character is in flight (see charge).
local chargeLocks = {}

---Charge (debit, B7): mirror of pay. Balance check, ledger row (kind='charge') FIRST, then a fresh Player lookup
---(same citizenid, else fail closed and void the row), balance re-check and RemoveMoney with no yield between them;
---a refused RemoveMoney deletes our own just-inserted row again. Never goes negative. Sequence:
---FhLedgerLogic.runCharge. Serialized per citizenid: while one charge for a character is in flight, a second one
---returns `false, 'fh_charge_busy'` at once (no row, no money); the caller may retry.
---@return boolean ok, string? err, integer? ledgerId
local function charge(src, amount, reason, region_id)
    local ok, err = logic.validateCharge({ amount = amount, reason = reason, region_id = region_id }, ctx)
    if not ok then return false, err end
    local citizenid = loadedCitizenid(src)
    if not citizenid then return false, 'no_player' end

    -- No yield between the lookup above and taking the lock.
    local done, why, id = logic.serialized(chargeLocks, citizenid, 'fh_charge_busy', logic.runCharge, {
        player = function() return playerFor(src, citizenid) end,
        balance = function(Player)
            local money = Player.PlayerData.money
            return type(money) == 'table' and tonumber(money[cfg.moneyType]) or nil
        end,
        insert = function()
            local inserted, newId = pcall(MySQL.insert.await, INSERT_LEDGER, { citizenid, 'charge', amount, reason, region_id })
            return inserted and newId or nil
        end,
        -- Player.Functions.RemoveMoney(moneytype, amount, reason) -> boolean (rsg-core/server/player.lua:368)
        remove = function(Player)
            local called, removed = pcall(Player.Functions.RemoveMoney, cfg.moneyType, amount, reason)
            return called and removed == true
        end,
        void = voidRow,
        warn = warnVoid,
    }, amount)
    if not done then return false, why end

    TriggerEvent('fh:economy:charged', { src = src, citizenid = citizenid, amount = amount,
        reason = reason, region_id = region_id, ledger_id = id })
    return true, nil, id
end

---Rep value for a character in a region: integer, 0 when there is no row. `who` = player server id, or a
---citizenid string (offline reads, e.g. fh_progression's loader; FhLedgerLogic.validCitizenid, else no_player).
---@return integer|nil rep, string? err
local function getRep(who, region_id)
    if not regions.isKnownRegion(region_id) then return nil, 'unknown_region' end
    local citizenid
    if type(who) == 'string' then
        -- all-digit = a mistyped server id; padded / blank / junk would silently read "no row" = 0: refuse them
        if not logic.validCitizenid(who) then return nil, 'no_player' end
        citizenid = who
    else
        citizenid = loadedCitizenid(who)
        if not citizenid then return nil, 'no_player' end
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

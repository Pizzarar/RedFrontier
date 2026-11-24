-- fh_economy: the only path for payouts and rep (spec 4.6). Every call writes a ledger row.
local cfg = FhEconomyConfig
local logic = FhLedgerLogic
local regions = FhRegions
local ctx = { isKnownRegion = regions.isKnownRegion, maxPay = cfg.maxPay, maxRepDelta = cfg.maxRepDelta,
    maxCharge = cfg.maxCharge, maxCredit = cfg.maxCredit, maxReason = cfg.maxReason }

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

---Shared rep write (rep + repByCitizenid): atomic clamped `value = value + delta` upsert plus ledger insert in one
---transaction, then the read-back and fh:economy:rep_changed. `src` = the online server id, or nil (offline write).
---@return boolean ok, string? err
local function applyRep(citizenid, src, region_id, delta, reason)
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

---Rep for an online player (server id).
---@return boolean ok, string? err
local function rep(src, region_id, delta, reason)
    local ok, err = logic.validateRep({ delta = delta, reason = reason, region_id = region_id }, ctx)
    if not ok then return false, err end
    local Player = getPlayer(src)
    if not Player then return false, 'no_player' end
    return applyRep(Player.PlayerData.citizenid, src, region_id, delta, reason)
end

-- ---------------------------------------------------------------------------------------------------------------
-- credit (core-04 E2, idea-700): a payout to a citizenid that never loses money, online or offline.
-- Offline credits are queued in fh_pending_credit (never a write to the players.money column: rsg-core keeps a loaded
-- player's money in memory and saves it back, so a raw UPDATE racing a login is overwritten) and paid on the next
-- character load by an atomic claim. Ledger kinds: 'credit' = money actually added; 'credit_pending' = queued, no
-- money moved yet (a liability; the matching 'credit' row is written when the claim pays it).

local INSERT_PENDING = 'INSERT INTO fh_pending_credit (citizenid, amount, reason, region_id) VALUES (?, ?, ?, ?)'
-- The claim guard: only unclaimed rows, in one UPDATE. Two loads racing for the same character cannot both own a row.
local CLAIM_PENDING = 'UPDATE fh_pending_credit SET claimed_by = ? WHERE citizenid = ? AND claimed_by IS NULL'
local SELECT_CLAIMED = 'SELECT id, amount, reason, region_id FROM fh_pending_credit WHERE claimed_by = ?'
local DELETE_CLAIMED = 'DELETE FROM fh_pending_credit WHERE id = ? AND claimed_by = ?'
local RELEASE_CLAIMED = 'UPDATE fh_pending_credit SET claimed_by = NULL WHERE id = ? AND claimed_by = ?'
local RELEASE_TOKEN = 'UPDATE fh_pending_credit SET claimed_by = NULL WHERE claimed_by = ?'

---Online Player for a citizenid (rsg-core's loaded players only), nil when not loaded or on any doubt.
local function onlineByCitizenid(citizenid)
    local called, Player = pcall(function() return exports['rsg-core']:GetPlayerByCitizenId(citizenid) end)
    if not called or type(Player) ~= 'table' or type(Player.PlayerData) ~= 'table' then return nil end
    if Player.PlayerData.citizenid ~= citizenid or not logic.validSrc(Player.PlayerData.source) then return nil end
    return Player
end

---Rep by citizenid (idea-804): same clamp / ledger row / event as `rep`, for an offline owner too. Rep lives in our
---own fh_rep table (rsg-core holds no copy), so a direct write is safe offline. The event's `src` is the online
---server id when that character is loaded, else nil. Refused: invalid_citizenid, unknown_citizenid (no `players` row),
---plus rep's own delta / reason / region errors.
---@return boolean ok, string? err
local function repByCitizenid(citizenid, region_id, delta, reason)
    if not logic.validCitizenid(citizenid) then return false, 'invalid_citizenid' end
    local ok, err = logic.validateRep({ delta = delta, reason = reason, region_id = region_id }, ctx)
    if not ok then return false, err end
    local Player = onlineByCitizenid(citizenid)
    if not Player then
        local okQ, known = pcall(MySQL.scalar.await, 'SELECT 1 FROM players WHERE citizenid = ? LIMIT 1', { citizenid })
        if not okQ then return false, 'ledger_failed' end
        if known == nil then return false, 'unknown_citizenid' end
    end
    return applyRep(citizenid, Player and Player.PlayerData.source or nil, region_id, delta, reason)
end

local function cashOf(Player)
    local money = type(Player.PlayerData) == 'table' and Player.PlayerData.money
    return type(money) == 'table' and tonumber(money[cfg.moneyType]) or nil
end

---AddMoney that tells "added" from "not added" even when it throws: rsg-core's AddMoney adds to PlayerData.money
---first and only then runs its client / log side effects, so a throw can come after the money moved. Nothing in here
---yields, so the balance change is ours alone. true = the money is on the character.
---The check redoes rsg-core's own float addition (`money[mt] + amount`, player.lua:357, amount unchanged by
---prepMoney's tonumber) and compares exactly: same IEEE operation, same operands -> bit-identical result. Never
---`after - before == amount`: with a fractional balance (127.2 + 5) - 127.2 ~= 5, which would class money that
---moved as unpaid and pay it again.
local function addMoneyChecked(Player, amount, reason)
    local before = cashOf(Player)
    local called, added = pcall(Player.Functions.AddMoney, cfg.moneyType, amount, reason)
    if called then return added == true end
    local after = cashOf(Player)
    return before ~= nil and after ~= nil and after == before + amount
end

local function enqueueCredit(citizenid, amount, reason, region_id)
    local done, committed = pcall(MySQL.transaction.await, {
        { query = INSERT_LEDGER, values = { citizenid, 'credit_pending', amount, reason, region_id } },
        { query = INSERT_PENDING, values = { citizenid, amount, reason, region_id } },
    })
    return done and committed == true
end

local function warnCredit(msg) print('[fh_economy] WARNING: ' .. msg) end

-- Claim tokens: unique per boot (time + random) and per claim (sequence), so a claim never matches another's rows.
local bootNonce = ('%x%04x'):format(os.time(), math.random(0, 0xffff))
local claimSeq = 0

---Pay every pending credit of a loaded character exactly once.
---  1. claim: UPDATE ... SET claimed_by = <fresh token> WHERE citizenid = ? AND claimed_by IS NULL (atomic: a
---     concurrent / double load claims nothing that is already claimed), then SELECT the rows by that token.
---  2. the awaits yielded: look the character up again; gone -> release the claim (nothing was paid), next load retries.
---  3. AddMoney per row, with no yield between the lookup and the last AddMoney (addMoneyChecked).
---  4. paid rows: one transaction writes their 'credit' ledger rows and deletes them (by id AND token).
---     If that transaction fails the money is already on the character: the rows stay CLAIMED (never released, so
---     never paid again) and a WARNING names them for a manual audit. Not lost, not paid twice.
---  5. rows AddMoney refused (money verifiably not added): released (claimed_by = NULL), retried on the next load.
---     A failed release leaves them claimed with a WARNING (audit), never re-paid automatically.
---@return integer paid  number of rows paid
local function claimPending(citizenid)
    claimSeq = claimSeq + 1
    local token = ('%s:%d:%s'):format(bootNonce, claimSeq, citizenid)
    local okU, claimed = pcall(MySQL.update.await, CLAIM_PENDING, { token, citizenid })
    if not okU then warnCredit(('could not claim pending credits for %s (db)'):format(citizenid)); return 0 end
    if (tonumber(claimed) or 0) == 0 then return 0 end

    local okS, rows = pcall(MySQL.query.await, SELECT_CLAIMED, { token })
    if not okS or type(rows) ~= 'table' then
        -- nothing paid: hand every row of this claim back for the next load
        if not pcall(MySQL.update.await, RELEASE_TOKEN, { token }) then
            warnCredit(('pending credits for %s left claimed by %s after a failed read (audit)'):format(citizenid, token))
        end
        return 0
    end

    local Player = onlineByCitizenid(citizenid)
    local paid, unpaid = {}, {}
    for _, row in ipairs(rows) do
        local amount = math.tointeger(tonumber(row.amount))
        if Player and amount and amount > 0 and addMoneyChecked(Player, amount, row.reason) then
            paid[#paid + 1] = { id = row.id, amount = amount, reason = row.reason, region_id = row.region_id }
        else
            unpaid[#unpaid + 1] = row
        end
    end
    local src = Player and Player.PlayerData.source

    if #paid > 0 then
        local queries = {}
        for _, r in ipairs(paid) do
            queries[#queries + 1] = { query = INSERT_LEDGER, values = { citizenid, 'credit', r.amount, r.reason, r.region_id } }
            queries[#queries + 1] = { query = DELETE_CLAIMED, values = { r.id, token } }
        end
        local done, committed = pcall(MySQL.transaction.await, queries)
        if not (done and committed == true) then
            local ids = {}
            for _, r in ipairs(paid) do ids[#ids + 1] = tostring(r.id) end
            warnCredit(('pending credits %s for %s were PAID but not cleared; left claimed by %s so they are never paid '
                .. 'again (audit: delete them, add their credit ledger rows)'):format(table.concat(ids, ','), citizenid, token))
        end
        for _, r in ipairs(paid) do
            TriggerEvent('fh:economy:credited', { src = src, citizenid = citizenid, amount = r.amount,
                reason = r.reason, region_id = r.region_id, queued = true })
        end
    end
    for _, row in ipairs(unpaid) do
        if not pcall(MySQL.update.await, RELEASE_CLAIMED, { row.id, token }) then
            warnCredit(('pending credit %s for %s not paid and left claimed by %s (audit)'):format(tostring(row.id),
                citizenid, token))
        end
    end
    return #paid
end

---Credit (idea-700): pay `amount` to a character by citizenid, online or offline. Never loses money:
---  - online: the pay path (ledger row kind='credit' FIRST, fresh lookup after the yield, AddMoney, void on failure).
---    If that fails with nothing moved (player left / switched / AddMoney refused / ledger insert failed), the credit
---    is queued as if offline instead.
---  - offline: one transaction inserts the fh_pending_credit row and a ledger row kind='credit_pending'; paid on the
---    next character load (claimPending). If the character loaded while the queue insert was in flight, it is
---    claimed at once. A citizenid with no `players` row is refused (`unknown_citizenid`): nobody could claim it.
---@return boolean ok, string? err, string? mode  'paid' (money on the character now) | 'pending' (queued)
local function credit(citizenid, amount, reason, region_id)
    local ok, err, n = logic.validateCredit({ citizenid = citizenid, amount = amount, reason = reason,
        region_id = region_id }, ctx)
    if not ok then return false, err end
    amount = n

    local Player = onlineByCitizenid(citizenid)
    if Player then
        local src = Player.PlayerData.source
        local done, _, id = logic.runPay({
            player = function() return playerFor(src, citizenid) end,
            insert = function()
                local inserted, newId = pcall(MySQL.insert.await, INSERT_LEDGER, { citizenid, 'credit', amount, reason, region_id })
                return inserted and newId or nil
            end,
            add = function(P) return addMoneyChecked(P, amount, reason) end,
            void = voidRow,
            warn = warnVoid,
        })
        if done then
            TriggerEvent('fh:economy:credited', { src = src, citizenid = citizenid, amount = amount,
                reason = reason, region_id = region_id, ledger_id = id, queued = false })
            return true, nil, 'paid'
        end
        -- nothing moved (runPay only fails before AddMoney or when the money verifiably was not added): queue it
    else
        local okQ, known = pcall(MySQL.scalar.await, 'SELECT 1 FROM players WHERE citizenid = ? LIMIT 1', { citizenid })
        if not okQ then return false, 'ledger_failed' end
        if known == nil then return false, 'unknown_citizenid' end
    end

    if not enqueueCredit(citizenid, amount, reason, region_id) then return false, 'ledger_failed' end
    -- the insert yielded: a character that loaded meanwhile may have run its claim before our row existed
    if onlineByCitizenid(citizenid) then claimPending(citizenid) end
    return true, nil, 'pending'
end

-- Server-only event (rsg-core/server/player.lua Login); passes the Player object. Event handlers run in a thread,
-- so the claim's awaits are fine here.
AddEventHandler('RSGCore:Server:PlayerLoaded', function(Player)
    local pd = type(Player) == 'table' and Player.PlayerData
    if type(pd) == 'table' and logic.validCitizenid(pd.citizenid) then claimPending(pd.citizenid) end
end)

-- No claim is in flight at start: any claimed row now is from an earlier run (crash mid-claim, or a failed clear).
-- Those may or may not have been paid, so they are never released automatically: warn for a manual audit.
if MySQL.ready then
    MySQL.ready(function()
        local okC, stale = pcall(MySQL.scalar.await,
            'SELECT COUNT(*) FROM fh_pending_credit WHERE claimed_by IS NOT NULL', {})
        if okC and (tonumber(stale) or 0) > 0 then
            warnCredit(('%d fh_pending_credit row(s) are claimed from an earlier run (audit before releasing: they '
                .. 'may already be paid)'):format(tonumber(stale)))
        end
    end)
end

exports('pay', pay)
exports('rep', rep)
exports('repByCitizenid', repByCitizenid)
exports('charge', charge)
exports('getRep', getRep)
exports('credit', credit)

-- Server-console test helpers (source 0 only): `fh_pay <serverId> <amount>`, `fh_rep <serverId> <delta>`,
-- `fh_charge <serverId> <amount>`, `fh_credit <citizenid> <amount>`
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
RegisterCommand('fh_credit', function(source, args)
    if source ~= 0 then return end
    print(json.encode({ credit(args[1], tonumber(args[2]), 'console_test', 'heartlands') }))
end, true)

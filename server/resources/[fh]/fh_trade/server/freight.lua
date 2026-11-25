-- fh_trade freight contracts (roads R4): a fh_quests job type. Thin wiring over shared/freight.lua (specced).
-- Uses fh_core §4 exports + fh_cargo exports (+ its shared TIERS, read-only) only. T2/T3 contracts (roads-02 R9,
-- roads-03 R13/R14) are gated at accept by fh_progression getTier in the origin region (soft dependency, fail closed),
-- the lane-local freight.t<N>.enabled kill switch, and the wagon's tier. Payout is NOT done here: fh_trade emits
-- fh:trade:contract_delivered and the fh_quests engine pays (engine.apply, exactly once). NOT runtime-tested (no Cfx key).
-- Natives: GetCurrentResourceName, GetResourceState, GetPlayerPed, GetEntityCoords, CreateThread, Wait.
local cfg = FhTradeConfig
local F = FhFreight
local fcfg = cfg.freight or {}

local contracts = {}   -- citizenid -> { [key] = contract }
local busy = {}        -- citizenid|key -> true while a delivery check is in flight (exports may yield)
local accepting = {}  -- citizenid -> true while an accept is in flight (one at a time: keeps maxActivePerPlayer exact)
local STASH = 'fh:wagon:'

local function log(fmt, ...) print(('[fh_trade/freight] ' .. fmt):format(...)) end
local function core() return exports['rsg-core']:GetCoreObject() end
local function citizenidOf(src)
    local p = core().Functions.GetPlayer(src)
    return p and p.PlayerData.citizenid or nil
end
local function srcOf(citizenid)
    local p = core().Functions.GetPlayerByCitizenId(citizenid)
    return p and p.PlayerData.source or nil
end
local function now() return os.time() end
local function wagonIdOfRef(ref)
    if type(ref) ~= 'table' or type(ref.id) ~= 'string' then return nil end
    if ref.id:sub(1, #STASH) ~= STASH or #ref.id <= #STASH then return nil end
    return ref.id:sub(#STASH + 1)
end
local function wagonRef(wagonId) return { type = 'wagon', id = STASH .. wagonId } end

-- ---------------------------------------------------------------- persistence

local function persist(c)
    local ok, err = pcall(MySQL.query.await,
        'INSERT INTO fh_trade_contracts (citizenid, ckey, wagon, from_region, to_region, item, qty, reward, accepted_at, deadline) '
        .. 'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?) ON DUPLICATE KEY UPDATE deadline = VALUES(deadline)',
        { c.citizenid, c.key, c.wagon, c.from_region, c.to_region, c.item, c.qty, c.reward, c.accepted_at, c.deadline })
    if not ok then log('could not save contract %s (%s): did the fh_trade_contracts migration run?', c.key, tostring(err)) end
end

local function unpersist(c)
    local ok, err = pcall(MySQL.query.await, 'DELETE FROM fh_trade_contracts WHERE citizenid = ? AND ckey = ?', { c.citizenid, c.key })
    if not ok then log('could not delete contract %s (%s)', c.key, tostring(err)) end
end

local function load()
    local ok, rows = pcall(MySQL.query.await, 'SELECT * FROM fh_trade_contracts')
    if not ok then return log('could not load contracts (%s)', tostring(rows)) end
    local n = 0
    for _, r in ipairs(rows or {}) do
        if cfg.goods[r.item] then
            contracts[r.citizenid] = contracts[r.citizenid] or {}
            contracts[r.citizenid][r.ckey] = {
                key = r.ckey, citizenid = r.citizenid, wagon = r.wagon, from_region = r.from_region, to_region = r.to_region,
                item = r.item, qty = r.qty, reward = r.reward, accepted_at = r.accepted_at, deadline = r.deadline, miss = 0, seen = false, -- seen=false: wait for the wagon to spawn
            }
            n = n + 1
        end
    end
    log('loaded %d active contracts', n)
end

local function drop(c)
    if contracts[c.citizenid] then contracts[c.citizenid][c.key] = nil end
    unpersist(c)
end

local function countActive(citizenid) local n = 0 for _ in pairs(contracts[citizenid] or {}) do n = n + 1 end return n end

-- ---------------------------------------------------------------- cargo helpers (fh_core §4 only)

---Units of `item` in the wagon stash, or nil when unreadable (fail closed).
local function cargoCount(wagonId, item)
    local snap = exports.fh_core:snapshot(wagonRef(wagonId))
    if type(snap) ~= 'table' then return nil end
    local n = 0
    for _, it in pairs(snap) do if it.name == item then n = n + (tonumber(it.amount) or 1) end end
    return n
end

---Take the contract's cargo out of its wagon (fh_core:removeItem, all-or-nothing). Idempotent per contract
---(c.cargoGone). @return boolean ok, string? why
local function takeCargo(c)
    if c.cargoGone then return true end
    local ok, a, b = pcall(function() return exports.fh_core:removeItem(wagonRef(c.wagon), c.item, c.qty) end)
    if not ok then return false, tostring(a) end
    if a ~= true then return false, b or 'remove_failed' end
    c.cargoGone = true
    return true
end

-- ---------------------------------------------------------------- tier gates (roads-02 R9, roads-03 R13)

---Per-player contract-tier gate (roads-03 R13). T1 always passes. A gated tier (F.gateFor) needs fh_progression
---getTier(src, origin_region) >= gate.minRegionTier: rep in the offer's origin region opens that region's board. No
---global canUnlock; the kill switch is lane-local (freight.t<N>.enabled, checked in validateOffer before the lock).
---Soft dependency, fail closed: not started / missing export / throws / non-number / too low -> 'fh_locked'.
---getTier may yield (rep cache load), so the character is re-checked after it: swapped -> 'fh_no_player'.
---`originRegion` must be validateOffer-checked (bound to the offer key). Covers both T2 and T3 via F.TIER_GATES.
local function tierUnlocked(src, citizenid, tier, originRegion)
    local gate = F.gateFor(cfg, tier)
    if not gate then return true end
    local ok, why = F.checkRegionTier(GetResourceState,
        function() return exports.fh_progression:getTier(src, originRegion) end, gate.minRegionTier)
    if citizenidOf(src) ~= citizenid then return false, 'fh_no_player' end
    if not ok then
        log('T%s contract refused for src %s: needs tier %s in %s (%s)', tostring(tier), tostring(src), tostring(gate.minRegionTier), tostring(originRegion), tostring(why))
        return false, 'fh_locked'
    end
    return true
end

---fh_cargo tier row ({ tier, slots, maxWeight }) of a live wagon, or nil when unreadable. Read-only: getWagon export +
---FhCargoRules.TIERS (fh_cargo shared/cargo_rules.lua, loaded as a shared script).
local function wagonTierRow(wagonId)
    local ok, w = pcall(function() return exports.fh_cargo:getWagon(wagonId) end)
    if not ok or type(w) ~= 'table' or type(w.tier) ~= 'string' then return nil end
    local tiers = type(FhCargoRules) == 'table' and FhCargoRules.TIERS
    return type(tiers) == 'table' and tiers[w.tier] or nil
end

-- ---------------------------------------------------------------- job type hooks

local function offers(regionId)
    if FhRegions.isEnabled and not FhRegions.isEnabled(regionId) then return {} end
    local byRegion = {}
    for id in pairs(FhRegions.regions) do
        if not FhRegions.isEnabled or FhRegions.isEnabled(id) then
            byRegion[id] = exports.fh_trade:getShortages(id)
        end
    end
    return F.generate(cfg, regionId, byRegion, FhRegions)
end

local function accept(src, offer)
    local citizenid = citizenidOf(src)
    if not citizenid then return false, 'fh_no_player' end
    local ok, err = F.validateOffer(cfg, offer, FhRegions.isKnownRegion, FhRegions)
    if not ok then return false, 'fh_freight_' .. err end
    if FhRegions.isEnabled and not (FhRegions.isEnabled(offer.from_region) and FhRegions.isEnabled(offer.to_region)) then
        return false, 'fh_freight_region_disabled'
    end
    if accepting[citizenid] then return false, 'fh_busy' end
    accepting[citizenid] = true -- held across the yielding exports below, so two accepts cannot both pass the cap
    local rok, res, extra = pcall(function()
        if (contracts[citizenid] or {})[offer.key] then return false, 'fh_freight_active' end
        if countActive(citizenid) >= (fcfg.maxActivePerPlayer or 2) then return false, 'fh_freight_too_many' end
        local tier = F.tierOf(offer)
        local unlocked, lerr = tierUnlocked(src, citizenid, tier, offer.from_region) -- from_region: key-bound origin
        if not unlocked then return false, lerr end
        local ref = exports.fh_cargo:nearestWagon(src, nil, fcfg.acceptReach or 8.0)
        local wagonId = wagonIdOfRef(ref)
        if not wagonId then return false, 'fh_freight_no_wagon' end
        local sized, serr = F.wagonFits(cfg, offer, wagonTierRow(wagonId))
        if not sized then return false, serr end
        local fit, why = exports.fh_core:canFit(ref, offer.item, offer.qty)
        if not fit then return false, why or 'fh_too_heavy' end
        local added, awhy = exports.fh_core:addItem(ref, offer.item, offer.qty, { freight = offer.key })
        if not added then return false, awhy or 'fh_add_failed' end
        local c = F.newContract(offer, citizenid, wagonId, now())
        contracts[citizenid] = contracts[citizenid] or {}
        contracts[citizenid][offer.key] = c
        persist(c)
        return true
    end)
    accepting[citizenid] = nil
    if not rok then log('accept error: %s', tostring(res)) return false, 'internal_error' end
    return res, extra
end

---Undo an accept / drop an abandoned contract. Called on player abandon AND when fh_quests could not save the
---accept, so it must fully undo accept (cargo out, row gone) and be idempotent. Never calls back into fh_quests
---(hooks run inside its per-character lock). No abandon event: the contract just stops.
local function abandon(src, state)
    local key = F.keyOfState(state)
    local citizenid = type(state) == 'table' and state.citizenid or citizenidOf(src)
    local c = citizenid and key and (contracts[citizenid] or {})[key]
    if not c then return end
    c.abandoned = true -- an in-flight check sees this and emits nothing
    drop(c)
    if busy[citizenid .. '|' .. key] then return end -- that check removes the cargo itself on its way out
    local ok, why = takeCargo(c)
    if not ok then log('abandon: could not take cargo of %s out of the wagon (%s)', key, tostring(why)) end
end

local function onEvent(name, payload, state) return F.eventVerdict(name, payload, state) end

---Per-player display lock for fh_quests (roads R20, idea-1039). Uses the same tier kill switch (F.tierEnabled) and
---regional tier gate as accept (tierUnlocked) so board display and accept can never disagree. Display only: accept()
---stays authoritative. Intentionally does NOT check wagon tier here: the player's wagon need not be out while browsing
---the board; accept() keeps the wagon-fits-qty check.
local function lockedFor(offer, src)
    if type(offer) ~= 'table' then return { reason = 'freight_gate' } end
    local tier = F.tierOf(offer)
    if tier == 1 then return nil end
    local gate = F.gateFor(cfg, tier)
    if not gate then return { reason = 'freight_gate' } end
    if not F.tierEnabled(cfg, tier) then
        return { min_tier = gate.minRegionTier, reason = 'freight_disabled' }
    end
    if type(offer.from_region) ~= 'string' or offer.from_region == '' then
        return { min_tier = gate.minRegionTier, reason = 'freight_gate' }
    end
    local citizenid = citizenidOf(src)
    if not citizenid then
        return { min_tier = gate.minRegionTier, reason = 'freight_gate' }
    end
    local unlocked = tierUnlocked(src, citizenid, tier, offer.from_region)
    if not unlocked then
        return { min_tier = gate.minRegionTier, reason = 'freight_gate' }
    end
    return nil
end

-- ---------------------------------------------------------------- emit + check loop

local function payloadOf(c, src, reason)
    return {
        src = src, citizenid = c.citizenid, key = c.key, quest_id = F.questId(c.key), from_region = c.from_region,
        to_region = c.to_region, item = c.item, qty = c.qty, reward = c.reward, reason = reason,
    }
end

local function fail(c, reason)
    drop(c)
    TriggerEvent(F.EVENT_FAILED, payloadOf(c, srcOf(c.citizenid), reason))
end

local function check(c)
    local tag = c.citizenid .. '|' .. c.key
    if busy[tag] or c.abandoned then return end
    busy[tag] = true
    local ok, err = pcall(function()
        local src = srcOf(c.citizenid)
        local facts = { online = src ~= nil }
        if src then
            local gok, w = pcall(function() return exports.fh_cargo:getWagon(c.wagon) end)
            local usable = gok and w and w.coords and w or nil
            facts.wagon = usable
            facts.owner_ok = usable == nil or usable.owner == c.citizenid
            if usable then
                facts.cargoCount = cargoCount(c.wagon, c.item)
                facts.atTarget = F.atTarget(F.destinationFor(cfg, c.to_region, FhRegions), usable.coords)
            end
        end
        if c.abandoned then return end
        local verdict, miss, seen = F.evaluate(c, facts, now(), fcfg.graceChecks or 3)
        c.miss, c.seen = miss, seen
        if not verdict then return end
        if verdict ~= 'delivered' then return fail(c, verdict) end
        local removed, why = takeCargo(c) -- all-or-nothing; on false nothing was removed and nothing is emitted
        if c.abandoned then return end -- abandon() ran meanwhile: it already dropped the contract
        if not removed then return log('delivery cargo removal failed for %s: %s', c.key, tostring(why)) end
        drop(c)
        TriggerEvent(F.EVENT_DELIVERED, payloadOf(c, src))
    end)
    if c.abandoned then takeCargo(c) end -- abandon() skipped removal while we were in flight: finish the undo (no-op if done)
    busy[tag] = nil -- only after the undo: an abandon parked in drop() must still see busy and not take the cargo again
    if not ok then log('check error for %s: %s', c.key, tostring(err)) end
end

CreateThread(function()
    load()
    while true do
        Wait(fcfg.checkMs or 5000)
        local list = {}
        for _, byKey in pairs(contracts) do for _, c in pairs(byKey) do list[#list + 1] = c end end
        for _, c in ipairs(list) do check(c) end
    end
end)

-- ---------------------------------------------------------------- registration (soft dependency on fh_quests)

local function registerFreight()
    local ok, err = F.register(GetResourceState, exports.fh_quests, { offers = offers, accept = accept, onEvent = onEvent, abandon = abandon, lockedFor = lockedFor })
    if ok then log('registered job type freight with fh_quests') elseif err ~= 'quests_not_started' then log('registerJobType failed: %s', tostring(err)) end
end

AddEventHandler('onResourceStart', function(res)
    if res == 'fh_quests' or res == GetCurrentResourceName() then registerFreight() end
end)

---Active contracts of a player (read-only copy). @return table[]
exports('getContracts', function(src)
    local citizenid = citizenidOf(src)
    local out = {}
    for _, c in pairs(contracts[citizenid or ''] or {}) do
        out[#out + 1] = { key = c.key, from_region = c.from_region, to_region = c.to_region, item = c.item, qty = c.qty, reward = c.reward, deadline = c.deadline }
    end
    table.sort(out, function(a, b) return a.key < b.key end)
    return out
end)

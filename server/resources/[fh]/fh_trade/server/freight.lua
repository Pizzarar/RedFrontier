-- fh_trade freight contracts (roads R4): a fh_quests job type. Thin wiring over shared/freight.lua (specced).
-- Uses fh_core §4 exports + fh_cargo exports only. Payout is NOT done here: fh_trade emits fh:trade:contract_delivered
-- and the fh_quests engine pays (engine.apply, exactly once). NOT runtime-tested (no Cfx key).
-- Natives: GetCurrentResourceName, GetResourceState, GetPlayerPed, GetEntityCoords, CreateThread, Wait.
local cfg = FhTradeConfig
local F = FhFreight
local fcfg = cfg.freight or {}

local contracts = {}   -- citizenid -> { [key] = contract }
local busy = {}        -- citizenid|key -> true while an accept / delivery is in flight (exports may yield)
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
local function wagonIdOfRef(ref) return ref and ref.id and ref.id:sub(1, #STASH) == STASH and ref.id:sub(#STASH + 1) or nil end
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
                item = r.item, qty = r.qty, reward = r.reward, accepted_at = r.accepted_at, deadline = r.deadline, miss = 0,
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

---Remove `qty` of `item` from the wagon. fh_core has no removeItem for world containers, so the cargo is moved into a
---throwaway drop bag at `coords`, which is then deleted. @return boolean ok, string? err
local function consume(wagonId, item, qty, coords, src)
    local from = wagonRef(wagonId)
    local snap = exports.fh_core:snapshot(from)
    if type(snap) ~= 'table' then return false, 'fh_unreadable' end
    local slots = {}
    for slot, it in pairs(snap) do if it.name == item then slots[#slots + 1] = { slot = slot, have = tonumber(it.amount) or 1 } end end
    table.sort(slots, function(a, b) return a.slot < b.slot end)
    local bagId = exports.fh_core:createDropBag(coords, {}, { label = 'freight' })
    if not bagId then return false, 'fh_no_sink' end
    local to, need, toSlot = { type = 'drop_bag', id = bagId }, qty, 0
    for _, s in ipairs(slots) do
        if need <= 0 then break end
        local take = math.min(need, s.have)
        toSlot = toSlot + 1
        local ok, why = exports.fh_core:move(from, to, s.slot, toSlot, take, src)
        if not ok then
            exports.fh_core:transferAll(to, from, src) -- put back what already moved
            exports.fh_core:deleteContainer(to)
            return false, why or 'fh_move_failed'
        end
        need = need - take
    end
    exports.fh_core:deleteContainer(to)
    if need > 0 then return false, 'fh_not_enough' end
    return true
end

-- ---------------------------------------------------------------- job type hooks

local function offers(regionId)
    local byRegion = {}
    for id in pairs(FhRegions.regions) do byRegion[id] = exports.fh_trade:getShortages(id) end
    return F.generate(cfg, regionId, byRegion)
end

local function accept(src, offer)
    local citizenid = citizenidOf(src)
    if not citizenid then return false, 'fh_no_player' end
    local ok, err = F.validateOffer(cfg, offer, FhRegions.isKnownRegion)
    if not ok then return false, 'fh_freight_' .. err end
    local tag = citizenid .. '|' .. offer.key
    if busy[tag] then return false, 'fh_busy' end
    if (contracts[citizenid] or {})[offer.key] then return false, 'fh_freight_active' end
    if countActive(citizenid) >= (fcfg.maxActivePerPlayer or 2) then return false, 'fh_freight_too_many' end
    busy[tag] = true
    local rok, res, extra = pcall(function()
        local ref = exports.fh_cargo:nearestWagon(src, nil, fcfg.acceptReach or 8.0)
        local wagonId = wagonIdOfRef(ref)
        if not wagonId then return false, 'fh_freight_no_wagon' end
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
    busy[tag] = nil
    if not rok then log('accept error: %s', tostring(res)) return false, 'internal_error' end
    return res, extra
end

local function abandon(src, state)
    local citizenid = citizenidOf(src)
    local key = type(state) == 'table' and F.keyOf(state.quest_id or state.id) or nil
    local c = citizenid and key and (contracts[citizenid] or {})[key]
    if not c then return end
    local w = exports.fh_cargo:getWagon(c.wagon)
    drop(c) -- stop the timers first: abandoning must not also fire contract_failed
    if w and w.coords then pcall(consume, c.wagon, c.item, c.qty, w.coords, src) end -- best effort: take the cargo back
end

local function onEvent(name, payload, state) return F.eventVerdict(name, payload, state) end

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
    if busy[tag] then return end
    busy[tag] = true
    local ok, err = pcall(function()
        local w = exports.fh_cargo:getWagon(c.wagon)
        local usable = w and w.coords and w or nil
        local facts = { wagon = usable, owner_ok = usable == nil or usable.owner == c.citizenid }
        if usable then
            facts.cargoCount = cargoCount(c.wagon, c.item)
            facts.atTarget = F.atTarget(fcfg.destinations[c.to_region], usable.coords)
        end
        local verdict, miss = F.evaluate(c, facts, now(), fcfg.graceChecks or 3)
        c.miss = miss
        if not verdict then return end
        if verdict ~= 'delivered' then return fail(c, verdict) end
        local src = srcOf(c.citizenid)
        if not src then return end -- offline: deliver when they are back (deadline still runs)
        local done, why = consume(c.wagon, c.item, c.qty, usable.coords, src)
        if not done then c.miss = (c.miss or 0) + 1 log('delivery consume failed for %s: %s', c.key, tostring(why)) return end
        drop(c)
        TriggerEvent(F.EVENT_DELIVERED, payloadOf(c, src))
    end)
    busy[tag] = nil
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
    local ok, err = F.register(GetResourceState, exports.fh_quests, { offers = offers, accept = accept, onEvent = onEvent, abandon = abandon })
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

-- fh_heat server (spec L7): per-character per-faction heat 0-100. The server owns it; HUD (@ui) reads getAll/get.
-- Natives: GetPlayers, GetPlayerPed, GetEntityCoords, GetGameTimer. NOT runtime-tested (no Cfx key yet).
-- Roadblocks / ambush / chase are R6: they hook `fh:heat:threshold` { src, citizenid, faction, old_level, level, value }
-- or exports.fh_heat:level. Event payloads follow fh_core/docs/events.md (one table argument).
local cfg = FhHeatConfig
local rules = FhHeatRules
local regions = FhRegions

local byCid = {}   -- citizenid -> { [faction] = heat }
local cidOf = {}   -- src -> citizenid (cached at first use, dropped on playerDropped)
local payoffLocks = rules.newLocks() -- (citizenid, faction) -> bounty payoff in flight

local function log(fmt, ...) print(('[fh_heat] ' .. fmt):format(...)) end
local function reply(src, msg)
    if src and src > 0 then TriggerClientEvent('chat:addMessage', src, { args = { 'fh', msg } }) end
end

local function citizenidOf(src)
    if type(src) ~= 'number' then return nil end
    local p = exports['rsg-core']:GetPlayer(src)
    local cid = p and p.PlayerData and p.PlayerData.citizenid or nil
    cidOf[src] = cid
    return cid
end

local function knownFaction(f) return type(f) == 'string' and regions.getFaction(f) ~= nil end

local function load(cid)
    if byCid[cid] then return byCid[cid] end
    local rows = MySQL.query.await('SELECT faction, heat FROM fh_heat WHERE citizenid = ?', { cid }) or {}
    local t = {}
    for _, r in ipairs(rows) do t[r.faction] = rules.clamp(tonumber(r.heat), cfg.min, cfg.max) end
    byCid[cid] = byCid[cid] or t -- a concurrent load may have won while we awaited
    return byCid[cid]
end

local UPSERT = 'INSERT INTO fh_heat (citizenid, faction, heat) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE heat = VALUES(heat)'

-- Fire-and-forget write (heat gains, decay, admin set: a lost write only costs heat accuracy, never money).
local function save(cid, faction, value) MySQL.query(UPSERT, { cid, faction, value }) end

-- Awaited write for money-backed changes (bounty payoff): true only once the row is written.
local function saveAwait(cid, faction, value)
    local ok, res = pcall(MySQL.query.await, UPSERT, { cid, faction, value })
    if not ok then log('ERROR heat write %s %s: %s', tostring(cid), faction, tostring(res)) end
    return ok and not not res -- truthy only (as fh_economy): a false / nil result is not a persisted write
end

-- Every change goes through here: persists, emits fh:heat:changed and (on a level change) fh:heat:threshold
-- (R6 hook point). One table payload each, built by rules.changeEvents.
-- durable = await the DB write; on failure the in-memory change is rolled back, no events fire, persisted = false.
-- Events fire only after the write and are pcall-guarded, so nothing after a persisted write can throw.
---@return number old, number new, boolean persisted
local function apply(src, cid, faction, new, reason, durable)
    local heats = load(cid)
    local old = heats[faction] or 0
    new = rules.clamp(new, cfg.min, cfg.max)
    if new == old then return old, new, true end
    heats[faction] = new
    if durable then
        if not saveAwait(cid, faction, new) then
            -- undo only our delta: other changes may have landed on this table while the write awaited
            heats[faction] = rules.clamp((heats[faction] or 0) + (old - new), cfg.min, cfg.max)
            return old, old, false
        end
    else
        save(cid, faction, new)
    end
    for _, ev in ipairs(rules.changeEvents(src, cid, faction, old, new, cfg.thresholds, reason)) do
        local ok, e = pcall(TriggerEvent, ev[1], ev[2])
        if not ok then log('ERROR emitting %s: %s', ev[1], tostring(e)) end
    end
    return old, new, true
end

local function resolve(src, faction)
    if not knownFaction(faction) then return nil, 'fh_unknown_faction' end
    local cid = citizenidOf(src)
    if not cid then return nil, 'fh_no_character' end
    return cid
end

-- ---------------------------------------------------------------- exports

---@return number|nil heat, string|nil err
local function get(src, faction)
    local cid, err = resolve(src, faction)
    if not cid then return nil, err end
    return load(cid)[faction] or 0
end

---@return boolean ok, number|string newOrErr
local function set(src, faction, value)
    local cid, err = resolve(src, faction)
    if not cid then return false, err end
    if not rules.finite(value) then return false, 'fh_bad_amount' end
    local _, new = apply(src, cid, faction, value, 'set')
    return true, new
end

---@return boolean ok, number|string newOrErr
local function add(src, faction, amount, reason)
    local cid, err = resolve(src, faction)
    if not cid then return false, err end
    local target, aerr = rules.add(load(cid)[faction] or 0, amount, cfg.min, cfg.max)
    if not target then return false, aerr end
    local _, new = apply(src, cid, faction, target, reason)
    log('add %s %s %+g -> %g (%s)', tostring(src), faction, amount, new, tostring(reason))
    return true, new
end

---Add heat for a configured source key (cfg.sources), optionally scaled.
local function addSource(src, faction, key, mult)
    local amount, err = rules.sourceAmount(cfg.sources, key, mult)
    if not amount then return false, err end
    return add(src, faction, amount, key)
end

---HUD data: { [faction] = { heat, level } } for every known faction.
local function getAll(src)
    local cid = citizenidOf(src)
    if not cid then return nil, 'fh_no_character' end
    local heats, out = load(cid), {}
    for id in pairs(regions.factions) do
        local h = heats[id] or 0
        out[id] = { heat = h, level = rules.level(cfg.thresholds, h) }
    end
    return out
end

local function level(src, faction)
    local h, err = get(src, faction)
    if not h then return nil, err end
    return rules.level(cfg.thresholds, h)
end

-- Region for the ledger row: the region of the territory the player stands in, else the faction's home region.
local function chargeRegion(src, faction)
    local x, y
    local ped = GetPlayerPed(src)
    if ped and ped ~= 0 then
        local c = GetEntityCoords(ped)
        x, y = c.x, c.y
    end
    return rules.chargeRegion(regions, faction, x, y)
end

-- Bounty payoff. points nil = all heat with that faction (capped to current heat).
-- One payoff per (citizenid, faction) at a time: the charge yields (DB await), so without the lock two requests
-- could both read the same heat and both charge. A second request while one is in flight gets fh_payoff_busy and is
-- never charged. rules.runPayoff always releases the lock (success, refusal, early return, error), after any refund.
local function payoff(src, faction, points)
    local cid, err = resolve(src, faction)
    if not cid then return false, err end
    local region = chargeRegion(src, faction)
    if not region then return false, 'fh_unknown_region' end
    local result = table.pack(rules.runPayoff({
        locks = payoffLocks,
        key = rules.lockKey(cid, faction),
        heat = function() return load(cid)[faction] or 0 end,
        perPoint = cfg.bountyPerPoint,
        points = points,
        -- fh_economy.charge(src, amount, reason, region_id) -> ok, err, ledgerId (@core B7); false,'fh_insufficient_funds'.
        charge = function(amount)
            if GetResourceState('fh_economy') ~= 'started' then return false, 'fh_economy_unavailable' end
            local ok, a, b = pcall(function() return exports.fh_economy:charge(src, amount, cfg.payoffReason, region) end)
            if not ok then -- export missing until B7 merges, or it threw
                log('ERROR fh_economy:charge %s %s amount=%s: %s', tostring(cid), faction, tostring(amount), tostring(a))
                return false, 'fh_economy_unavailable'
            end
            return a, b
        end,
        -- post-charge failure: credit the exact amount back by captured citizenid (fh_economy.credit, same region),
        -- so a player drop queues a pending credit and a character switch still credits the original citizenid.
        -- Runs under the lock.
        refund = function(amount)
            if GetResourceState('fh_economy') ~= 'started' then return false, 'fh_economy_unavailable' end
            local ok, a, b, mode = pcall(function() return exports.fh_economy:credit(cid, amount, cfg.refundReason, region) end)
            if not ok then return false, 'fh_economy_error: ' .. tostring(a) end
            if not a then return false, b end
            if mode == 'pending' then
                log('refund queued (pending) cid=%s faction=%s amount=%s', tostring(cid), faction, tostring(amount))
            end
            return true, nil, mode
        end,
        -- subtract the points paid from the CURRENT heat so heat gained during the (yielding) charge is not wiped.
        -- Awaited write: the payoff succeeds only once the reset is persisted.
        commit = function(paid)
            local _, _, persisted = apply(src, cid, faction, (load(cid)[faction] or 0) - paid, 'bounty_payoff', true)
            return persisted
        end,
        onError = function(msg, charged, amount)
            log('ERROR payoff cid=%s faction=%s amount=%s charged=%s: %s', tostring(cid), faction, tostring(amount),
                tostring(charged), msg)
        end,
    }))
    -- the player may have dropped while the charge / write yielded: playerDropped already cleared the cache, but the
    -- commit's load() refilled it. Every payoff change is persisted, so drop it unless the character is online again.
    if cidOf[src] ~= cid then
        local online = false
        for _, c in pairs(cidOf) do if c == cid then online = true break end end
        if not online then byCid[cid] = nil end
    end
    return table.unpack(result, 1, result.n)
end

exports('get', get)
exports('set', set)
exports('add', add)
exports('addSource', addSource)
exports('getAll', getAll)
exports('level', level)
exports('payoff', payoff)

-- ---------------------------------------------------------------- heat HUD (@ui, plan T3)
-- Read-only: builds the fh_ui `heat` screen data from getAll(src) (pure: shared/heat_hud.lua) and opens it for ONE
-- player via fh:ui:open. `open` is the passive-widget path (relay.passive.heat, so no NUI focus) and it also unhides
-- #screen-heat, which fh:ui:update alone does not. No state is mutated, no heat value or rule changes, and nothing is
-- saved (idea-669: no fire-and-forget writes). Other players' heat is never sent.
local function pushHeatHud(src)
    if not (type(src) == 'number' and src > 0) then return end
    local all = getAll(src)
    if not all then return end -- no character (console, or dropped mid-yield)
    TriggerClientEvent('fh:ui:open', src, { screen = 'heat', data = FhHeatHud.build(all, regions.factions) })
end

-- Every change (gains, decay, admin set, bounty payoff) re-pushes that player's own heat HUD.
AddEventHandler('fh:heat:changed', function(e)
    if type(e) ~= 'table' then return end
    pushHeatHud(e.src)
end)

-- Initial HUD on character load: restores persisted heat before any change event fires.
AddEventHandler('RSGCore:Server:PlayerLoaded', function(Player)
    local pd = Player and Player.PlayerData
    if pd and pd.source then pushHeatHud(pd.source) end
end)

-- ---------------------------------------------------------------- command: /paybounty [faction] [points]
-- chat fallback (ox_lib not required); a HUD/menu from @ui can call exports.fh_heat:payoff instead.
RegisterCommand('paybounty', function(src, args)
    if src == 0 then return end
    local all = getAll(src)
    if not all then return reply(src, 'No character loaded.') end
    local faction = args[1]
    if not faction then
        local parts = {}
        for id, v in pairs(all) do
            parts[#parts + 1] = ('%s: %d heat (cost %d)'):format(id, math.floor(v.heat + 0.5), math.ceil(v.heat * cfg.bountyPerPoint))
        end
        table.sort(parts)
        return reply(src, 'Heat: ' .. table.concat(parts, ' | ') .. '. Pay with /paybounty <faction> [points]')
    end
    if not all[faction] then return reply(src, 'Unknown faction.') end
    if all[faction].heat <= 0 then return reply(src, 'No heat with them.') end
    -- only an omitted points arg means "all"; junk / <= 0 / more than the current heat is refused, nothing charged
    local pok, points = rules.parsePoints(args[2], all[faction].heat)
    if not pok then
        return reply(src, ('Points must be a number above 0 and at most your heat with them (%g).'):format(all[faction].heat))
    end
    local ok, a, b = payoff(src, faction, points)
    if ok then return reply(src, ('Bounty paid: %g heat cleared for %d.'):format(a, b)) end
    local msgs = { fh_insufficient_funds = 'You cannot afford that bounty.', fh_no_heat = 'No heat with them.',
        fh_unknown_faction = 'Unknown faction.', fh_economy_unavailable = 'Bounty payoff is not available yet.',
        fh_payoff_busy = 'A bounty payment is already being processed.', fh_bad_amount = 'Invalid points.',
        fh_unknown_region = 'Bounty payoff is not available here.',
        fh_payoff_refunded = 'Bounty payment failed and you were not charged. Try again.',
        fh_payoff_refund_failed = 'Bounty payment failed after you were charged. Do not retry; contact an admin.' }
    reply(src, msgs[a] or ('Could not pay bounty (' .. tostring(a) .. ').'))
end, false)

-- ---------------------------------------------------------------- sources

-- fh_zones emits fh:zones:camp_cleared { camp_id, region_id, loot } with no player. Credit every player standing inside a
-- territory of that region: heat goes to that territory's faction (regions.territoryAt).
AddEventHandler('fh:zones:camp_cleared', function(data)
    if type(data) ~= 'table' then return end
    for _, s in ipairs(GetPlayers()) do
        local src = tonumber(s)
        local ped = src and GetPlayerPed(src)
        if ped and ped ~= 0 then
            local c = GetEntityCoords(ped)
            local t = regions.territoryAt(c.x, c.y)
            if t and t.region == data.region_id then addSource(src, t.faction, 'camp_clear') end
        end
    end
end)

-- ---------------------------------------------------------------- lay-low decay

local function decayPlayer(src, dt)
    local cid = citizenidOf(src)
    if not cid then return end
    local ped = GetPlayerPed(src)
    local here
    if ped and ped ~= 0 then
        local c = GetEntityCoords(ped)
        here = rules.factionAt(regions, c.x, c.y)
    end
    local changes = {} -- collect first: apply() writes into the table being iterated
    for faction, heat in pairs(load(cid)) do
        if heat > 0 then
            local nv = rules.decay(heat, dt, cfg.decayPerMinute, here == faction, cfg.min, cfg.max)
            if nv ~= heat then changes[faction] = nv end
        end
    end
    for faction, nv in pairs(changes) do apply(src, cid, faction, nv, 'decay') end
end

local function decayTick(dt)
    for _, s in ipairs(GetPlayers()) do
        local src = tonumber(s)
        -- per player too: one bad player record does not skip everyone after it
        if src then rules.safeTick(decayPlayer, function(e) log('ERROR decay src %d: %s', src, e) end, src, dt) end
    end
end

-- Each tick runs protected (rules.safeTick): an error is logged and the loop keeps running.
CreateThread(function()
    local last = GetGameTimer()
    while true do
        Wait(math.floor(cfg.decayTickSeconds * 1000))
        local now = GetGameTimer()
        local dt = (now - last) / 1000
        last = now
        rules.safeTick(decayTick, function(e) log('ERROR decay tick: %s', e) end, dt)
    end
end)

AddEventHandler('playerDropped', function()
    local src = source
    local cid = cidOf[src]
    cidOf[src] = nil
    if cid then byCid[cid] = nil end -- every change is already persisted; reload on next login
end)

-- fh_heat server (spec L7): per-character per-faction heat 0-100. The server owns it; HUD (@ui) reads getAll/get.
-- Natives: GetPlayers, GetPlayerPed, GetEntityCoords, GetGameTimer. NOT runtime-tested (no Cfx key yet).
-- Roadblocks / ambush / chase are R6: they hook `fh:heat:threshold` (src, faction, oldLevel, newLevel) or exports.fh_heat:level.
local cfg = FhHeatConfig
local rules = FhHeatRules
local regions = FhRegions

local byCid = {}   -- citizenid -> { [faction] = heat }
local cidOf = {}   -- src -> citizenid (cached at first use, dropped on playerDropped)

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

local function save(cid, faction, value)
    MySQL.query('INSERT INTO fh_heat (citizenid, faction, heat) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE heat = VALUES(heat)',
        { cid, faction, value })
end

-- Every change goes through here: persists, emits fh:heat:changed and (on a level change) fh:heat:threshold.
local function apply(src, cid, faction, new)
    local heats = load(cid)
    local old = heats[faction] or 0
    new = rules.clamp(new, cfg.min, cfg.max)
    if new == old then return old, new end
    heats[faction] = new
    save(cid, faction, new)
    TriggerEvent('fh:heat:changed', src, faction, old, new)
    local lo, ln = rules.level(cfg.thresholds, old), rules.level(cfg.thresholds, new)
    if lo ~= ln then TriggerEvent('fh:heat:threshold', src, faction, lo, ln) end -- R6 hook point
    return old, new
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
    local _, new = apply(src, cid, faction, value)
    return true, new
end

---@return boolean ok, number|string newOrErr
local function add(src, faction, amount, reason)
    local cid, err = resolve(src, faction)
    if not cid then return false, err end
    local target, aerr = rules.add(load(cid)[faction] or 0, amount, cfg.min, cfg.max)
    if not target then return false, aerr end
    local _, new = apply(src, cid, faction, target)
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

-- Bounty payoff. points nil = all heat with that faction.
local function payoff(src, faction, points)
    local cid, err = resolve(src, faction)
    if not cid then return false, err end
    local heat = load(cid)[faction] or 0
    local charge = function(amount)
        -- TODO(B7 @core): fh_economy.charge(src, amount, reason, region) lands with @core B7 (returns false,'fh_insufficient_funds').
        if GetResourceState('fh_economy') ~= 'started' then return false, 'fh_economy_unavailable' end
        local ok, a, b = pcall(function() return exports.fh_economy:charge(src, amount, cfg.payoffReason, nil) end)
        if not ok then return false, 'fh_economy_unavailable' end -- export missing until B7 merges
        return a, b
    end
    local ok, paid, cost, perr = rules.payoff(heat, cfg.bountyPerPoint, points, charge)
    if not ok then return false, perr, cost end
    -- subtract the points paid from the CURRENT heat so heat gained during the (yielding) charge is not wiped
    apply(src, cid, faction, (load(cid)[faction] or 0) - paid)
    return true, paid, cost
end

exports('get', get)
exports('set', set)
exports('add', add)
exports('addSource', addSource)
exports('getAll', getAll)
exports('level', level)
exports('payoff', payoff)

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
    local ok, a, b = payoff(src, faction, tonumber(args[2]))
    if ok then return reply(src, ('Bounty paid: %g heat cleared for %d.'):format(a, b)) end
    local msgs = { fh_insufficient_funds = 'You cannot afford that bounty.', fh_no_heat = 'No heat with them.',
        fh_unknown_faction = 'Unknown faction.', fh_economy_unavailable = 'Bounty payoff is not available yet.' }
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

CreateThread(function()
    local last = GetGameTimer()
    while true do
        Wait(math.floor(cfg.decayTickSeconds * 1000))
        local now = GetGameTimer()
        local dt = (now - last) / 1000
        last = now
        for _, s in ipairs(GetPlayers()) do
            local src = tonumber(s)
            local cid = src and citizenidOf(src)
            if cid then
                local ped = GetPlayerPed(src)
                local here
                if ped and ped ~= 0 then
                    local c = GetEntityCoords(ped)
                    here = rules.factionAt(regions, c.x, c.y)
                end
                for faction, heat in pairs(load(cid)) do
                    if heat > 0 then
                        local nv = rules.decay(heat, dt, cfg.decayPerMinute, here == faction, cfg.min, cfg.max)
                        if nv ~= heat then apply(src, cid, faction, nv) end
                    end
                end
            end
        end
    end
end)

AddEventHandler('playerDropped', function()
    local src = source
    local cid = cidOf[src]
    cidOf[src] = nil
    if cid then byCid[cid] = nil end -- every change is already persisted; reload on next login
end)

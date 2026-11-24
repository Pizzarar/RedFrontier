-- fh_alife server (plan a-life-01): owns camp ownership. fh_zones asks getOwner/isLawHeld before spawning a camp's
-- peds; a cleared camp flips to law and schedules an outlaw retake squad that marches back ~retake.minTicks..maxTicks
-- later. State persists as a KVP JSON blob. Natives: GetPlayers, GetGameTimer, SetResourceKvp, GetResourceKvpString,
-- TriggerEvent / TriggerClientEvent (fh_core/docs/natives.md, unverified in-game). NOT runtime-tested (no Cfx key).
local cfg = FhAlifeConfig
local rules = FhAlifeRules
local regions = FhRegions

local KVP_KEY = 'fh_alife_state'
local ctx = rules.context(cfg, regions, FhZonesConfig.camps)
local state = rules.newState()

local function log(fmt, ...) print(('[fh_alife] ' .. fmt):format(...)) end
-- The rules module takes a single pre-formatted string; this adapter forwards it through our formatted logger.
local function notify(msg) log('%s', msg) end
local function reply(src, msg)
    if src and src > 0 then TriggerClientEvent('chat:addMessage', src, { args = { 'fh', msg } }) end
end

-- ---------------------------------------------------------------- persistence

local function save()
    SetResourceKvp(KVP_KEY, json.encode(rules.serialize(state)))
end

local function load()
    local raw = GetResourceKvpString(KVP_KEY)
    if not raw or raw == '' then return end
    local ok, t = pcall(json.decode, raw)
    if not ok or type(t) ~= 'table' then
        log('bad KVP state, starting fresh: %s', tostring(t))
        return
    end
    local s, err = rules.deserialize(t)
    if not s then
        log('deserialize failed (%s), starting fresh', tostring(err))
        return
    end
    state = s
    local nOwners, nSquads = 0, 0
    for _ in pairs(state.owners) do nOwners = nOwners + 1 end
    for _ in pairs(state.squads) do nSquads = nSquads + 1 end
    log('loaded state: tick=%d, %d owners, %d squads', state.tick, nOwners, nSquads)
end

-- ---------------------------------------------------------------- effect application

local function srcOfCitizenid(citizenid)
    local ok, p = pcall(function() return exports['rsg-core']:GetPlayerByCitizenId(citizenid) end)
    if ok and p and p.PlayerData and p.PlayerData.source then return p.PlayerData.source end
    return nil
end

local function applyHeat(effect)
    local src = srcOfCitizenid(effect.citizenid)
    if not src then return end
    local ok, a, b = pcall(function() return exports.fh_heat:addSource(src, effect.faction, 'camp_clear') end)
    if not ok then log('heat apply failed for %s: %s', tostring(effect.citizenid), tostring(a))
    elseif a == false then log('heat refused for %s: %s', tostring(effect.citizenid), tostring(b)) end
end

local function applyShortage(effect)
    local ok, a, b = pcall(function() return exports.fh_trade:setShortage(effect.region, effect.item, effect.level) end)
    if not ok then log('shortage apply failed for %s/%s: %s', tostring(effect.region), tostring(effect.item), tostring(a))
    elseif a == false then log('shortage refused for %s/%s: %s', tostring(effect.region), tostring(effect.item), tostring(b)) end
end

local function applyEffect(effect)
    local t = effect.type
    if t == 'broadcast' then
        TriggerClientEvent('chat:addMessage', -1, { args = { 'fh', effect.message } })
    elseif t == 'flipped' then
        TriggerEvent('fh:alife:camp_flipped', { camp_id = effect.camp_id, region_id = effect.region_id,
            from = effect.from, to = effect.to })
    elseif t == 'heat' then
        applyHeat(effect)
    elseif t == 'shortage' then
        applyShortage(effect)
    end
end

local function applyEffects(effects)
    for _, e in ipairs(effects or {}) do
        local ok, err = pcall(applyEffect, e)
        if not ok then log('effect apply error: %s', tostring(err)) end
    end
end

-- ---------------------------------------------------------------- exports (FIXED API CONTRACT)

---@return string|nil factionId
local function getOwner(campId) return rules.getOwner(ctx, state, campId) end
---@return boolean
local function isLawHeld(campId) return rules.isLawHeld(ctx, state, campId) end

exports('getOwner', getOwner)
exports('isLawHeld', isLawHeld)

-- ---------------------------------------------------------------- events

AddEventHandler('fh:zones:camp_cleared', function(data)
    if type(data) ~= 'table' or type(data.camp_id) ~= 'string' then return end
    local effects = rules.onCampCleared(ctx, state, data.camp_id, data.participants, nil, notify)
    applyEffects(effects)
    save()
end)

-- ---------------------------------------------------------------- tick loop

CreateThread(function()
    while true do
        Wait(math.floor((cfg.tickSeconds or 60) * 1000))
        local effects = rules.tick(ctx, state, 1)
        applyEffects(effects)
        save()
    end
end)

-- ---------------------------------------------------------------- admin commands (/alife, /alife tick [n])

local function split(raw)
    local out = {}
    for tok in tostring(raw or ''):gmatch('%S+') do out[#out + 1] = tok end
    table.remove(out, 1) -- command name
    return out
end

local function statusLine()
    local parts = { ('tick %d'):format(state.tick) }
    local ids = {}
    for id in pairs(ctx.camps) do ids[#ids + 1] = id end
    table.sort(ids)
    for _, id in ipairs(ids) do
        local owner = rules.getOwner(ctx, state, id)
        parts[#parts + 1] = ('%s=%s%s'):format(id, owner or 'none', rules.isLawHeld(ctx, state, id) and '(law)' or '')
    end
    local sqs = {}
    for _, sq in pairs(state.squads) do
        sqs[#sqs + 1] = ('%s:%s->%s eta%d'):format(sq.id, tostring(sq.faction), tostring(sq.to), tostring(sq.etaTick))
    end
    table.sort(sqs)
    for _, s in ipairs(sqs) do parts[#parts + 1] = s end
    return table.concat(parts, ' | ')
end

lib.addCommand('alife', {
    help = 'A-Life camp sim: /alife (status) | /alife tick [n]',
    restricted = 'group.admin',
}, function(src, args, raw)
    local a = split(raw)
    if a[1] == 'tick' then
        local n = tonumber(a[2])
        if not n or n < 1 then n = 1 end
        n = math.min(math.floor(n), 1000)
        local effects = rules.tick(ctx, state, n)
        applyEffects(effects)
        save()
        return reply(src, ('Advanced A-Life %d tick(s) -> %d effect(s).'):format(n, #effects))
    end
    reply(src, 'A-Life: ' .. statusLine())
end)

load()

-- fh_alife server (plan a-life-01): owns camp ownership. fh_zones asks getOwner/isLawHeld before spawning a camp's
-- peds; a cleared camp flips to law and schedules an outlaw retake squad that marches back ~retake.minTicks..maxTicks
-- later. State persists as a KVP JSON blob. Natives: SetResourceKvp, GetResourceKvpString,
-- TriggerEvent / TriggerClientEvent (fh_core/docs/natives.md, unverified in-game). NOT runtime-tested (no Cfx key).
local cfg = FhAlifeConfig
local rules = FhAlifeRules
local raidRules = FhAlifeRaidRules -- a-life-03 claim raids (shared/raid_rules.lua); server side in server/raids.lua
local regions = FhRegions

local KVP_KEY = 'fh_alife_state'
local ctx = rules.context(cfg, regions, FhZonesConfig.camps)
local state = rules.newState()

local function log(fmt, ...) print(('[fh_alife] ' .. fmt):format(...)) end
-- The rules module takes a single pre-formatted string; this adapter forwards it through our formatted logger.
local function notify(msg) log('%s', msg) end
local function reply(src, msg)
    if src == 0 then print('[fh_alife] ' .. msg)
    elseif src and src > 0 then TriggerClientEvent('chat:addMessage', src, { args = { 'fh', msg } }) end
end

-- ---------------------------------------------------------------- persistence

local function save()
    local ok, err = pcall(function()
        SetResourceKvp(KVP_KEY, json.encode(rules.serialize(state)))
    end)
    if not ok then
        log('^1save failed: %s^7', tostring(err))
        return false, err
    end
    return true
end

local function load()
    local raw = GetResourceKvpString(KVP_KEY)
    if not raw or raw == '' then return end
    local ok, t = pcall(json.decode, raw)
    if not ok or type(t) ~= 'table' then
        log('bad KVP state, starting fresh: %s', tostring(t))
        return
    end
    -- a-life-03 C2: raids are checked against the claims only once fh_homestead's claim cache has loaded (a non-empty
    -- claimedPlots). Before that, pass nil: live raids are kept and raid_rules.tick cancels any whose plot is gone.
    local plots, claims = FhAlifeHomestead.plots()
    local s, err, dropped = raidRules.deserialize(t, ctx, (plots and claims > 0) and plots or nil)
    if not s then
        log('deserialize failed (%s), starting fresh', tostring(err))
        return
    end
    state = s
    for _, e in ipairs(dropped or {}) do
        if e.type == 'loot_dropped' then
            log('^1load: raid loot ledger %s full (%d stacks): dropped oldest %dx %s^7', tostring(e.camp_id),
                tonumber(e.kept) or 0, tonumber(e.amount) or 0, tostring(e.name))
        else
            log('load: dropped %s %s (%s)', tostring(e.type), tostring(e.squad_id), tostring(e.reason))
        end
    end
    local nOwners, nSquads = 0, 0
    for _ in pairs(state.owners) do nOwners = nOwners + 1 end
    for _ in pairs(state.squads) do nSquads = nSquads + 1 end
    log('loaded state: tick=%d, %d owners, %d squads', state.tick, nOwners, nSquads)
end

-- ---------------------------------------------------------------- effect application

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

-- ---------------------------------------------------------------- shared surface (server/squads.lua)
-- squads.lua (loaded after this file) materialises/despawns ambush squads near players and runs the death watch. It
-- shares this resource's context, state and persistence through this table.
FhAlifeServer = {
    ctx = ctx,
    getState = function() return state end, -- state is reassigned by load()
    save = save,
    -- rng = nil: raids.lua uses math.random unless a test sets FhAlifeServer.rng(lo, hi).
    -- raidStep / raidCommand / raidNotify / raidCenter / raidOwnerOnline / raidLootDeliver: set by server/raids.lua
    -- (a-life-03 C2, C2c).
}

---One sim step: FhAlifeRules.tick(ctx, state, 1), then the claim-raid step right after it (server/raids.lua runs
---FhAlifeRaidRules.tick on the same state), then the camp effects. A raid error is logged and never stops the sim.
---@return integer effects  camp effects + raid effects
local function step()
    local effects = rules.tick(ctx, state, 1)
    local nRaid = 0
    if FhAlifeServer.raidStep then
        local ok, n = pcall(FhAlifeServer.raidStep)
        if ok then nRaid = tonumber(n) or 0 else log('raid step error: %s', tostring(n)) end
    end
    applyEffects(effects)
    return #effects + nRaid
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
    -- a-life-03 C2c: the camp's raid loot ledger goes into its stash (fired after fh_zones' rollIntoStash)
    if FhAlifeServer.raidLootDeliver then
        local ok, err = pcall(FhAlifeServer.raidLootDeliver, data.camp_id)
        if not ok then log('raid loot delivery error for %s: %s', data.camp_id, tostring(err)) end
    end
    save()
end)

-- ---------------------------------------------------------------- tick loop

CreateThread(function()
    while true do
        Wait(math.floor((cfg.tickSeconds or 60) * 1000))
        local ok, err = pcall(step)
        if not ok then log('^1tick step error: %s^7', tostring(err)) end
        save()
    end
end)

-- ---------------------------------------------------------------- admin commands (/alife, /alife tick [n], /alife raid)

local function split(raw)
    local out = {}
    for tok in tostring(raw or ''):gmatch('%S+') do out[#out + 1] = tok end
    table.remove(out, 1) -- command name
    return out
end

-- One /alife line per squad: "<id> <goal>[@<node label>|-><to>] x<strength> [<phase>]". Ambush squads use their
-- node's display label when present (rules.nodeLabel), else the node id; strength is the surviving member count.
local function squadLine(sq)
    local where
    if sq.goal == 'ambush' then
        where = sq.node and ('@' .. rules.nodeLabel(ctx, sq.node)) or ''
    else
        where = sq.to and ('->' .. sq.to) or ''
    end
    return ('%s %s%s x%d%s'):format(tostring(sq.id), tostring(sq.goal), where, sq.strength or 0,
        sq.phase and (' ' .. sq.phase) or '')
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
        -- a-life-03: raid squads print their claim line (raid_rules.describeRaid)
        sqs[#sqs + 1] = sq.goal == raidRules.GOAL and raidRules.describeRaid(ctx, sq) or squadLine(sq)
    end
    table.sort(sqs)
    for _, s in ipairs(sqs) do parts[#parts + 1] = s end
    parts[#parts + 1] = raidRules.describeLoot(state) -- a-life-03 C2c: loot ledger stacks per camp
    -- Ambush nodes per region (rules.describeAmbush prints "<region>: no ambush nodes" for a region with none).
    local rids = {}
    for _, camp in pairs(ctx.camps) do rids[camp.region] = true end
    for rid in pairs(ctx.graph.ambushByRegion) do rids[rid] = true end
    local ordered = {}
    for rid in pairs(rids) do ordered[#ordered + 1] = rid end
    table.sort(ordered)
    for _, rid in ipairs(ordered) do parts[#parts + 1] = rules.describeAmbush(ctx, state, rid) end
    return table.concat(parts, ' | ')
end

lib.addCommand('alife', {
    help = 'A-Life camp sim: /alife (status) | /alife tick [n] | /alife raid <plotId>',
    restricted = 'group.admin',
}, function(src, args, raw)
    local a = split(raw)
    if a[1] == 'tick' then
        local n = tonumber(a[2])
        if not n or n < 1 then n = 1 end
        n = math.min(math.floor(n), 1000)
        local total = 0
        for _ = 1, n do total = total + step() end -- one step at a time: the raid step runs after every tick
        save()
        return reply(src, ('Advanced A-Life %d tick(s) -> %d effect(s).'):format(n, total))
    end
    if a[1] == 'raid' then
        if not FhAlifeServer.raidCommand then return reply(src, 'A-Life raids are not loaded.') end
        return reply(src, FhAlifeServer.raidCommand(a[2]))
    end
    reply(src, 'A-Life: ' .. statusLine())
end)

load()

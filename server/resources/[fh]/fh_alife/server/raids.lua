-- fh_alife server/raids.lua (plan a-life-03 C2): wilderness-claim raids, server side of shared/raid_rules.lua.
-- main.lua step() calls FhAlifeServer.raidStep right after FhAlifeRules.tick(ctx, state, 1): it builds the world
-- (fh_homestead claimedPlots + plotInfo through server/homestead.lua, online citizenids, owner-at-claim within
-- claimRaids.raidRadius), runs FhAlifeRaidRules.tick and applies its effects:
--   raid_warned / raid_fight / raid_withdrew / raid_cancelled -> a chat notice to the claim owner;
--   raid_fight -> squads.lua materialises the squad at the claim (FhAlifeServer.raidCenter / raidOwnerOnline);
--   raid_steal -> chest 1 -> the raiding camp's loot ledger (state.raidLoot, saved to KVP; C2c). Chest access ONLY
--     through the fh_core container API (snapshot, removeItem); an entry is recorded only after a confirmed remove, so
--     nothing is duplicated. Itemised notice to the owner listing exactly what was recorded.
--   fh:zones:camp_cleared (main.lua handler -> raidLootDeliver): the camp's ledger is taken (emptied) and each entry
--     added to the camp stash fh:camp:<campId> (fh_core addItem); each refused entry goes into its own drop bag at the
--     camp's loot coords; any stack whose bag call fails goes back into the ledger. Never destroyed, never delivered twice.
--   Why not the stash at steal time: fh_zones wipes camp stashes on restart/boot (twice-daily restart windows).
-- Death-watch repels (fh:alife:raid_repelled) are emitted by squads.lua; raidNotify tells the owner.
-- Natives: GetPlayers, GetPlayerPed, GetEntityCoords, GetResourceState, TriggerClientEvent (unverified in game).
-- Implemented A-Life — Thanks to S.T.A.L.K.E.R. A-Life by GSC Game World.
local R = FhAlifeRaidRules
local server = FhAlifeServer
local H = FhAlifeHomestead
local ctx = server.ctx

local function log(fmt, ...) print(('[fh_alife] ' .. fmt):format(...)) end

local function knob(k, d)
    local c = FhAlifeConfig and FhAlifeConfig.claimRaids
    local v = type(c) == 'table' and tonumber(c[k]) or nil
    return v or d
end
local RAID_RADIUS = knob('raidRadius', 60.0)
local BOOT_GRACE = math.max(0, math.floor(knob('bootGraceTicks', 3)))
local TICK_SECONDS = tonumber(FhAlifeConfig and FhAlifeConfig.tickSeconds) or 60

local function rng(lo, hi) return (server.rng or math.random)(lo, hi) end

-- ---------------------------------------------------------------- players

local function citizenidOf(src)
    local ok, cid = pcall(function()
        local c = exports['rsg-core']:GetCoreObject()
        local p = c and c.Functions.GetPlayer(src)
        return p and p.PlayerData.citizenid or nil
    end)
    return ok and cid or nil
end

---Online characters: { [citizenid] = true }, { [citizenid] = src }, { [citizenid] = ped coords }.
local function onlinePlayers()
    local online, srcOf, pos = {}, {}, {}
    for _, s in ipairs(GetPlayers()) do
        local src = tonumber(s)
        local cid = src and citizenidOf(src)
        if cid then
            online[cid], srcOf[cid] = true, src
            local ped = GetPlayerPed(src)
            if ped and ped ~= 0 then
                local c = GetEntityCoords(ped)
                if c and c.x then pos[cid] = c end
            end
        end
    end
    return online, srcOf, pos
end

-- Caches for squads.lua's 1 s sweep (refreshed every raid step): owner online + claim coords. playerDropped clears
-- the dropped character at once, so a raid squad despawns within a second of its owner logging off; the next raid
-- step then cancels the raid in state (raid_rules.tick: owner_offline).
local onlineNow, srcNow = {}, {}
local plotCoords = {}

local function notifyOwner(cid, msg)
    if type(cid) ~= 'string' then return end
    local src = srcNow[cid]
    if not src then
        local _, s = onlinePlayers()
        src = s[cid]
    end
    log('raid notice -> %s: %s', cid, msg)
    if src then TriggerClientEvent('chat:addMessage', src, { args = { 'fh', msg } }) end
end

---Build the raid_rules world. @return table world, table|nil plots, integer claims
local function buildWorld()
    local plots, claims = H.plots()
    local online, srcOf, pos = onlinePlayers()
    local home = {}
    for pid, p in pairs(plots or {}) do
        if type(p.coords) == 'table' then plotCoords[pid] = p.coords end
        local at = type(p.owner) == 'string' and pos[p.owner] or nil
        local d = at and p.coords and FhPlotRules.dist(at, p.coords) or nil
        if d and d <= RAID_RADIUS then home[pid] = true end
    end
    onlineNow, srcNow = online, srcOf
    return { plots = plots or {}, online = online, home = home }, plots, claims
end

-- ---------------------------------------------------------------- steal (TIER A: chest 1 -> camp stash)
-- Every inventory touch is an fh_core container export (pcall: a stopped fh_core is a refusal, never a throw).

local function coreSnapshot(ref)
    local ok, items, why = pcall(function() return exports.fh_core:snapshot(ref) end)
    if not ok then return nil, 'fh_core_error' end
    return items, why
end
local function coreRemove(ref, name, amount)
    local ok, done, why = pcall(function() return exports.fh_core:removeItem(ref, name, amount) end)
    if not ok then return false, 'fh_core_error: ' .. tostring(done) end
    return done == true, why
end
local function coreAdd(ref, name, amount, info)
    local ok, done, why = pcall(function() return exports.fh_core:addItem(ref, name, amount, info) end)
    if not ok then return false, 'fh_core_error: ' .. tostring(done) end
    return done == true, why
end
local function coreDropBag(coords, items, opts)
    local ok, id, why = pcall(function() return exports.fh_core:createDropBag(coords, items, opts) end)
    if not ok then return nil, 'fh_core_error: ' .. tostring(id) end
    return id, why
end

---The snapshot entry of a picked slot (fh_inventory may key slots as numbers or numeric strings).
local function slotItem(items, slot)
    local it = items[slot] or items[tostring(slot)]
    if type(it) == 'table' then return it end
    for _, v in pairs(items) do
        if type(v) == 'table' and v.slot == slot then return v end
    end
    return nil
end

---Put a removed-but-unrecorded pick back (the ledger refused it): chest 1 first, else a drop bag at the claim.
local function restorePick(chest, pick, info, e, why)
    local back, backWhy = coreAdd(chest, pick.name, pick.amount, info)
    if back then
        log('^1raid %s steal: ledger refused %dx %s (%s); returned to %s^7', tostring(e.squad_id), pick.amount,
            pick.name, tostring(why), chest.id)
        return
    end
    local coords = plotCoords[e.plot_id] or (H.plotInfo(e.plot_id) or {}).coords
    local bag, bagWhy = coreDropBag(coords, { { name = pick.name, amount = pick.amount, info = info } },
        { owner = e.citizenid, label = 'Dropped by raiders' })
    log('^1raid %s steal: ledger refused %dx %s (%s) AND %s refused it back (%s); drop bag %s (%s) at %s^7',
        tostring(e.squad_id), pick.amount, pick.name, tostring(why), chest.id, tostring(backWhy), tostring(bag),
        tostring(bagWhy), tostring(e.plot_id))
end

---Move one pick: removeItem from chest 1, then (only on a confirmed remove) append it to the camp's loot ledger.
---@return boolean moved, string|nil reason
local function movePick(chest, pick, info, e)
    local removed, remWhy = coreRemove(chest, pick.name, pick.amount)
    if not removed then return false, 'remove_refused:' .. tostring(remWhy) end
    local ok, err, dropped = R.lootAdd(ctx, server.getState(), e.camp_id,
        { name = pick.name, amount = pick.amount, info = info })
    if not ok then
        restorePick(chest, pick, info, e, err)
        return false, 'ledger_refused:' .. tostring(err)
    end
    for _, d in ipairs(dropped) do
        log('^1raid loot ledger %s full (%d stacks): dropped oldest %dx %s^7', tostring(e.camp_id),
            R.lootCount(server.getState(), e.camp_id), d.amount, d.name)
    end
    return true
end

local function itemList(moved)
    local parts = {}
    for _, m in ipairs(moved) do parts[#parts + 1] = ('%dx %s'):format(m.amount, m.name) end
    return table.concat(parts, ', ')
end

---raid_steal: read chest 1 through fh_core, pick with R.pickSteal, move each pick into the camp's loot ledger, save.
---The owner notice lists exactly the recorded picks (idea-961: never claims items that were not taken).
---@return table moved  { { name, amount } }
local function steal(e)
    local chest = H.chestRef(e.plot_id)
    local who = e.camp_label or tostring(e.camp_id)
    local items, why = coreSnapshot(chest)
    if type(items) ~= 'table' then
        log('raid %s steal skipped: chest %s unreadable (%s)', tostring(e.squad_id), chest.id, tostring(why))
        notifyOwner(e.citizenid, ('Riders from %s reached your claim while you were away but rode off empty-handed.')
            :format(who))
        return {}
    end
    local picks = R.pickSteal(ctx, items, rng)
    local moved = {}
    for _, pick in ipairs(picks) do
        local it = slotItem(items, pick.slot)
        local info = it and type(it.info) == 'table' and it.info or nil
        local ok, reason = movePick(chest, pick, info, e)
        if ok then moved[#moved + 1] = { name = pick.name, amount = pick.amount }
        else log('raid %s steal: %dx %s not taken (%s)', tostring(e.squad_id), pick.amount, pick.name, tostring(reason)) end
    end
    log('raid %s stole from %s -> loot ledger %s: %s', tostring(e.squad_id), chest.id, tostring(e.camp_id),
        #moved > 0 and itemList(moved) or 'nothing')
    if #moved > 0 then
        local saveOk, saveErr = pcall(server.save) -- persist now; a failed save must not block notifyOwner
        if not saveOk then log('^1raid %s steal: save error: %s^7', tostring(e.squad_id), tostring(saveErr)) end
        notifyOwner(e.citizenid, ('Riders from %s raided your claim while you were away and took from your chest: %s. '
            .. 'Clear their camp to get it back.'):format(who, itemList(moved)))
    elseif #picks == 0 then
        notifyOwner(e.citizenid, ('Riders from %s raided your claim while you were away but found nothing to take.')
            :format(who))
    else
        notifyOwner(e.citizenid, ('Riders from %s raided your claim while you were away but left without taking anything.')
            :format(who))
    end
    return moved
end

-- ---------------------------------------------------------------- loot delivery (fh:zones:camp_cleared)

local function campLootCoords(campId)
    local camp = ctx.camps and ctx.camps[campId]
    if type(camp) ~= 'table' then return nil end
    return (type(camp.loot) == 'table' and camp.loot.coords) or camp.center
end

---Deliver a cleared camp's loot ledger into its stash (main.lua's fh:zones:camp_cleared handler calls this after
---fh_zones' rollIntoStash; the caller saves). The ledger is emptied BEFORE any add (lootTake), so a second clear or a
---re-entry delivers nothing. Each refused add gets its own drop bag at the camp's loot coords (one stack per call so a
---partial bag accept cannot lose leftovers); any stack whose bag call fails goes back into the ledger for the next
---clear. @return integer delivered, integer bagged, integer kept
function server.raidLootDeliver(campId)
    if type(campId) ~= 'string' then return 0, 0, 0 end
    local state = server.getState()
    local entries = R.lootTake(state, campId)
    if #entries == 0 then return 0, 0, 0 end
    local stash = { type = 'chest', id = FhCampRules.stashId(campId) }
    local delivered, failed = {}, {}
    for _, it in ipairs(entries) do
        local ok, why = coreAdd(stash, it.name, it.amount, it.info)
        if ok then delivered[#delivered + 1] = it
        else
            log('^1raid loot %s: add %dx %s to %s refused (%s); to the drop bag^7', campId, it.amount, it.name,
                stash.id, tostring(why))
            failed[#failed + 1] = it
        end
    end
    local bagged, kept = {}, {}
    if #failed > 0 then
        local coords = campLootCoords(campId)
        for _, it in ipairs(failed) do
            -- One stack per bag call: fh_core:createDropBag drops Fh.CreateDropBag's leftovers on partial accepts.
            local bag, bagWhy = coreDropBag(coords, { { name = it.name, amount = it.amount, info = it.info } },
                { label = 'Raiders\' plunder' })
            if bag then
                bagged[#bagged + 1] = it
                log('^1raid loot %s: refused stack %dx %s in drop bag %s at the camp^7', campId, it.amount, it.name,
                    tostring(bag))
            else
                kept[#kept + 1] = it
                log('^1raid loot %s: drop bag refused for %dx %s (%s); keeping in the ledger^7', campId, it.amount,
                    it.name, tostring(bagWhy))
            end
        end
        if #kept > 0 then
            for _, d in ipairs(R.lootRestore(ctx, state, campId, kept)) do
                log('^1raid loot ledger %s full: dropped oldest %dx %s^7', campId, d.amount, d.name)
            end
            log('^1raid loot %s: %d stack(s) kept in the ledger for the next clear: %s^7',
                campId, #kept, itemList(kept))
        end
    end
    log('raid loot %s delivered to %s: %s', campId, stash.id, #delivered > 0 and itemList(delivered) or 'nothing')
    return #delivered, #bagged, #kept
end

-- ---------------------------------------------------------------- effects

local CANCEL_TEXT = {
    owner_offline = 'you left', plot_gone = 'the claim is gone', not_raidable = 'the claim is no longer open land',
    owner_changed = 'the claim changed hands', camp_lost = 'their camp fell',
}

local function applyEffect(e)
    local t = e.type
    if t == 'raid_warned' then
        local mins = math.max(1, math.floor((tonumber(e.warn_ticks) or 1) * TICK_SECONDS / 60 + 0.5))
        notifyOwner(e.citizenid, ('Riders from %s are heading for your claim (~%d min).'):format(
            tostring(e.camp_label or e.camp_id), mins))
    elseif t == 'raid_fight' then
        log('raid %s fight at %s (x%d)', tostring(e.squad_id), tostring(e.plot_id), e.strength or 0)
        notifyOwner(e.citizenid, 'The raiders are at your claim! Drive them off.')
    elseif t == 'raid_steal' then
        steal(e)
    elseif t == 'raid_withdrew' then
        notifyOwner(e.citizenid, 'The raiders pulled back from your claim.')
    elseif t == 'raid_cancelled' then
        -- an offline owner gets no chat line (notifyOwner finds no src); the log keeps it
        notifyOwner(e.citizenid, ('The riders heading for your claim turned back (%s).'):format(
            CANCEL_TEXT[e.reason] or tostring(e.reason)))
    elseif t == 'raid_returned' then
        log('raid %s back at %s (%s%s)', tostring(e.squad_id), tostring(e.camp_id), tostring(e.mode),
            e.cancelled and (', cancelled: ' .. tostring(e.cancelled)) or '')
    end
end

local function applyEffects(effects)
    for _, e in ipairs(effects or {}) do
        local ok, err = pcall(applyEffect, e)
        if not ok then log('raid effect %s error: %s', tostring(e.type), tostring(err)) end
    end
end

-- ---------------------------------------------------------------- step / command / hooks

local steps = 0 -- raid steps since this resource started (boot grace for the homestead claim load)

---One raid step at the current state.tick (main.lua step(), right after FhAlifeRules.tick). Skipped while the claim
---cache looks unloaded (fh_homestead down or 0 claims) during the first bootGraceTicks steps, so live raids loaded
---from KVP are not cancelled at boot. After the grace a missing homestead means no plots: no new raids, live ones
---cancel. @return integer effects
function server.raidStep()
    steps = steps + 1
    local world, plots, claims = buildWorld()
    if (plots == nil or claims == 0) and steps <= BOOT_GRACE then return 0 end
    local effects = R.tick(ctx, server.getState(), world, rng)
    applyEffects(effects)
    return #effects
end

---/alife raid <plotId> (admin; main.lua's /alife command carries the group.admin restriction). @return string reply
function server.raidCommand(plotId)
    if type(plotId) ~= 'string' or plotId == '' then return 'Usage: /alife raid <plotId>' end
    local plot = H.plotInfo(plotId)
    if not plot then return ('No such claim: %s (fh_homestead running?)'):format(plotId) end
    local online, srcOf = onlinePlayers()
    onlineNow, srcNow = online, srcOf
    if type(plot.coords) == 'table' then plotCoords[plotId] = plot.coords end
    local sq, res = R.forceRaid(ctx, server.getState(), plotId, plot, online, rng)
    if not sq then return ('Raid on %s refused: %s'):format(plotId, tostring(res)) end
    applyEffects(res)
    server.save()
    return 'Raid started: ' .. R.describeRaid(ctx, sq)
end

---squads.lua death watch: a raid squad was wiped (raid_repelled effect).
function server.raidNotify(e)
    log('raid %s repelled at %s', tostring(e.squad_id), tostring(e.plot_id))
    notifyOwner(e.citizenid, 'You drove the raiders off your claim.')
end

function server.raidOwnerOnline(cid) return type(cid) == 'string' and onlineNow[cid] == true end

function server.raidCenter(sq)
    local c = plotCoords[sq.plot]
    if not c then
        local info = H.plotInfo(sq.plot)
        c = info and info.coords or nil
        plotCoords[sq.plot] = c
    end
    return c
end

AddEventHandler('playerDropped', function()
    local src = source
    for cid, s in pairs(srcNow) do
        if s == src then onlineNow[cid], srcNow[cid] = nil, nil end
    end
end)

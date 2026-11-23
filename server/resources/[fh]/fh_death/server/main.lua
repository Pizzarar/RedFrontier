-- fh_death server (spec L4 soft death, L16 soft consequences). The server owns all state.
-- On a death confirmed server side: `equipped` stays; backpack (+ saddlebag) move into a
-- new owner-only drop bag (a registered fh stash of type drop_bag) through fh_core.transferAll. The stash is the
-- truth; the prop (B4c requestSpawn) is only visual. Bags persist in fh_death_drops + fh_inventory's `inventories`.
-- Natives: GetPlayerPed, GetEntityCoords, GetEntityHealth (server), GetGameTimer. NOT runtime-tested (no Cfx key).
--
-- No dupe / no loss:
--  * every item move is one fh_inventory MoveBetween step (removed from one container and added to the other in the
--    same Lua call, both rows saved right after); a refused step leaves that item where it was (logged, `kept`);
--  * the fh_death_drops row is written before any move, so a crash mid-drop leaves a tracked bag (cleaned or
--    recovered after restart), never an untracked stash holding items;
--  * a bag is forgotten only after fh_inventory deleted its stash; deletion is refused while anyone has it open.
local cfg = FhDeathConfig
local rules = FhDeathRules

local state = rules.newState()
local bags = {}      -- id -> { id, owner, coords, expiresAt, slots, maxWeight, spawnId?, busy? }
local srcOfCid = {}  -- citizenid -> src, for characters marked dead (alive poll)
local ready = false
local seq = 0
local lastOpen = {}  -- src -> GetGameTimer() of the last open request

local function core() return exports['rsg-core']:GetCoreObject() end

local function citizenidOf(src)
    local p = core().Functions.GetPlayer(src)
    return p and p.PlayerData.citizenid or nil
end

local function log(fmt, ...) print(('[fh_death] ' .. fmt):format(...)) end

local function reply(src, msg)
    if src and src > 0 then TriggerClientEvent('chat:addMessage', src, { args = { 'fh', msg } }) end
end

local function refOf(id) return { type = 'drop_bag', id = id } end

local function serverHealth(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return nil end
    local ok, h = pcall(GetEntityHealth, ped)
    return ok and tonumber(h) or nil
end

local function describe(items)
    local parts = {}
    for _, it in pairs(items or {}) do
        if type(it) == 'table' then parts[#parts + 1] = ('%sx%s'):format(tostring(it.amount), tostring(it.name)) end
    end
    table.sort(parts)
    return #parts > 0 and table.concat(parts, ', ') or 'nothing'
end

local function publicList(src)
    return rules.publicBags(bags, os.time(), src and citizenidOf(src) or nil)
end

-- Per-player: every online player gets the list, each with their own `mine` flags (no owner ids on the wire).
local function broadcast()
    for _, pid in ipairs(GetPlayers()) do
        local src = tonumber(pid)
        if src then TriggerClientEvent('fh:death:bags', src, publicList(src)) end
    end
end

-- ---------------------------------------------------------------- prop (visual only)

local function spawnProp(bag)
    if bag.spawnId then return end
    local id, err = exports.fh_core:requestSpawn({
        kind = 'object', model = cfg.propModel,
        coords = vector4(bag.coords.x, bag.coords.y, bag.coords.z, 0.0),
        owner = { kind = 'drop_bag', id = bag.id }, tag = 'fh_death:' .. bag.id,
    }, {
        near = bag.coords,
        onFailed = function(reason)
            log('prop for %s failed (%s); the bag is still openable at its coords', bag.id, tostring(reason))
            if bags[bag.id] == bag then bag.spawnId = nil end
        end,
    })
    if not id then
        log('prop request for %s refused (%s); the bag is still openable at its coords', bag.id, tostring(err))
        return
    end
    bag.spawnId = id
end

local function despawnProp(bag)
    if not bag.spawnId then return end
    pcall(function() exports.fh_core:despawn(bag.spawnId) end)
    bag.spawnId = nil
end

-- ---------------------------------------------------------------- bag lifecycle

local function registerBag(bag)
    local ok, why = exports.fh_core:registerContainer(refOf(bag.id), {
        coords = bag.coords, label = cfg.label, slots = bag.slots, maxWeight = bag.maxWeight,
    })
    if not ok then log('register %s failed: %s', bag.id, tostring(why)) end
    return ok, why
end

---Delete the stash, then the row, then forget the bag. Any failure keeps the bag tracked (the sweep retries).
---The bag is busy for the whole call (it yields on MySQL): the sweep, the open handler and an fh_core restart leave
---it alone, so nothing re-registers or re-props a container that is being deleted (review rn-eb74b5c695bb).
---@return boolean ok, table|string itemsOrReason
local function removeBag(bag)
    bag.busy = true
    local ok, items = exports.fh_core:deleteContainer(refOf(bag.id))
    if not ok then
        -- fh_inventory restarted and lost the registration: register again and retry on the next sweep
        if items == 'fh_unknown_container' then registerBag(bag) end
        bag.busy = nil
        return false, items
    end
    local rowOk = pcall(MySQL.update.await, 'DELETE FROM fh_death_drops WHERE id = ?', { bag.id })
    if not rowOk then log('stash %s deleted but its row was not (cleaned on next start)', bag.id) end
    despawnProp(bag)
    bags[bag.id] = nil
    broadcast()
    return true, items or {}
end

---Death of `src` (life `life` of `cid`) confirmed server side: move the carried containers into a new bag.
local function dropFor(src, cid, life)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return log('%s died but has no ped; nothing moved', cid) end
    local c = GetEntityCoords(ped)
    local coords = vector3(c.x, c.y, c.z)

    local okS, saddle = pcall(cfg.saddlebagOf, src, cid)
    local sources, snaps = {}, {}
    for _, ref in ipairs(rules.sources(src, okS and saddle or nil)) do
        local items, why = exports.fh_core:snapshot(ref)
        if items then
            sources[#sources + 1], snaps[#snaps + 1] = ref, items
        else
            log('%s: cannot read %s (%s); it stays where it is', cid, ref.type, tostring(why))
        end
    end
    if rules.isEmpty(snaps) then return log('%s died with nothing to drop; no bag', cid) end

    seq = seq + 1
    local id = rules.bagId(os.time(), seq)
    while bags[id] do seq = seq + 1; id = rules.bagId(os.time(), seq) end
    local size = rules.bagSize(cfg.bagDefaults, snaps)
    local bag = { id = id, owner = cid, coords = coords, expiresAt = rules.expiresAt(os.time(), cfg.despawnMinutes),
        slots = size.slots, maxWeight = size.maxWeight, busy = true }

    -- 1) the row first (PK clash or DB down: abort, nothing has moved)
    local rowOk = pcall(MySQL.insert.await,
        'INSERT INTO fh_death_drops (id, citizenid, x, y, z, slots, max_weight, expires_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
        { id, cid, coords.x, coords.y, coords.z, bag.slots, bag.maxWeight, bag.expiresAt })
    if not rowOk then return log('%s: bag row insert failed; nothing moved, items stay on the character', cid) end
    bags[id] = bag -- busy: the sweep leaves it alone until the moves are done

    -- 2) the container
    if not registerBag(bag) then
        bags[id] = nil
        pcall(MySQL.update.await, 'DELETE FROM fh_death_drops WHERE id = ?', { id })
        return log('%s: bag register failed; nothing moved, items stay on the character', cid)
    end

    -- 3) the moves, one MoveBetween per step; refused steps stay in their source
    local movedSteps, kept = 0, {}
    for _, ref in ipairs(sources) do
        local ok, moved, left = exports.fh_core:transferAll(ref, refOf(id), src)
        if not ok then
            log('%s: %s -> %s failed (%s); its items stay where they are', cid, ref.type, id, tostring(moved))
            kept[#kept + 1] = { from = ref.type, reason = tostring(moved) }
        else
            movedSteps = movedSteps + #moved
            for _, l in ipairs(left or {}) do
                log('%s: kept %sx %s in %s (%s)', cid, tostring(l.amount), tostring(l.name), ref.type, tostring(l.reason))
                kept[#kept + 1] = { from = ref.type, name = l.name, amount = l.amount, reason = l.reason }
            end
        end
    end
    if movedSteps == 0 then
        -- empty bag, no prop. Still busy here: removeBag keeps it busy until it is gone, or clears busy on failure so
        -- the sweep removes it once it can.
        local ok, why = removeBag(bag)
        if not ok then log('%s: empty bag %s not removed yet (%s)', cid, id, tostring(why)) end
        return
    end
    bag.busy = nil
    spawnProp(bag)
    broadcast()
    log('%s life %d: bag %s at %.1f %.1f %.1f, %d stack(s) moved, %d kept', cid, life, id, coords.x, coords.y, coords.z,
        movedSteps, #kept)
    TriggerEvent('fh:death:dropped', { src = src, citizenid = cid, container_id = id, coords = coords, life = life,
        expires_at = bag.expiresAt, moved = movedSteps, kept = kept })
end

-- ---------------------------------------------------------------- death / life detection

-- rsg-core server/death.lua: a server-only event fired after the victim's client report (rate-limited there).
-- The report alone is not trusted: the server must read the ped as dead (GetEntityHealth <= 0).
AddEventHandler('RSGCore:Server:OnPlayerDeath', function(src)
    CreateThread(function()
        if not ready then return log('death of %s before load; nothing moved', tostring(src)) end
        local cid = citizenidOf(src)
        if not cid or rules.isDead(state, cid) then return end
        local health
        for i = 1, cfg.deathCheckTries do
            health = serverHealth(src)
            if health and health <= 0 then break end
            if i < cfg.deathCheckTries then Wait(cfg.deathCheckIntervalMs) end
        end
        -- synchronous transition: a duplicate event that also got here is refused (fh_already_dead)
        local ok, life = rules.onDeath(state, cid, health, os.time())
        if not ok then
            if life ~= 'fh_already_dead' then log('death report for %s ignored: %s (health %s)', cid, life, tostring(health)) end
            return
        end
        srcOfCid[cid] = src
        dropFor(src, cid, life)
    end)
end)

CreateThread(function()
    while true do
        Wait(cfg.aliveCheckMs)
        for cid, src in pairs(srcOfCid) do
            if rules.onAlive(state, cid, serverHealth(src), os.time(), cfg.minDeadSeconds) then srcOfCid[cid] = nil end
        end
    end
end)

AddEventHandler('playerDropped', function()
    local src = source
    lastOpen[src] = nil
    for cid, s in pairs(srcOfCid) do
        if s == src then
            srcOfCid[cid] = nil
            rules.forget(state, cid)
        end
    end
end)

-- ---------------------------------------------------------------- sweep: emptied -> recovered, expired -> deleted

local function sweep()
    local now = os.time()
    local list = {} -- removeBag yields (MySQL) and a death may add a bag meanwhile: never traverse `bags` across it
    for _, bag in pairs(bags) do list[#list + 1] = bag end
    for _, bag in ipairs(list) do
        if not bag.busy and bags[bag.id] == bag then
            if rules.isExpired(bag, now) then
                local ok, items = removeBag(bag)
                if ok then
                    log('bag %s of %s expired; lost: %s', bag.id, bag.owner, describe(items))
                    TriggerEvent('fh:death:expired', { src = 0, citizenid = bag.owner, container_id = bag.id,
                        coords = bag.coords, lost = items })
                end
            else
                local items, why = exports.fh_core:snapshot(refOf(bag.id))
                if items and next(items) == nil then
                    if removeBag(bag) then
                        log('bag %s recovered by %s', bag.id, bag.owner)
                        TriggerEvent('fh:death:recovered', { src = 0, citizenid = bag.owner, container_id = bag.id })
                    end
                elseif not items and why == 'fh_unknown_container' then
                    registerBag(bag)
                end
            end
        end
    end
end

-- ---------------------------------------------------------------- load / restart

local function loadBags()
    local rows = MySQL.query.await('SELECT id, citizenid, x, y, z, slots, max_weight, expires_at FROM fh_death_drops') or {}
    for _, r in ipairs(rows) do
        local bag = { id = r.id, owner = r.citizenid, coords = vector3(r.x + 0.0, r.y + 0.0, r.z + 0.0),
            slots = tonumber(r.slots), maxWeight = tonumber(r.max_weight), expiresAt = tonumber(r.expires_at) }
        bags[bag.id] = bag
        registerBag(bag) -- expired ones too: fh_inventory must know the stash to delete it
        if rules.isLive(bag, os.time()) then spawnProp(bag) end
    end
    log('%d bag(s) loaded', #rows)
    local okSweep, errSweep = pcall(sweep) -- expired rows go now, not after the first sweepMs
    if not okSweep then log('sweep error: %s', tostring(errSweep)) end
    ready = true
    broadcast()
    while true do
        Wait(cfg.sweepMs)
        local ok, err = pcall(sweep)
        if not ok then log('sweep error: %s', tostring(err)) end
    end
end

CreateThread(loadBags)

-- fh_core restart: its registered-container table and every spawn request are gone. Register and re-request.
AddEventHandler('onResourceStart', function(res)
    if res ~= 'fh_core' or not ready then return end
    local now = os.time()
    for _, bag in pairs(bags) do
        bag.spawnId = nil
        -- a busy bag is mid-drop (dropFor registers it itself) or mid-delete: leave it alone
        if not bag.busy then
            registerBag(bag)
            if rules.isLive(bag, now) then spawnProp(bag) end
        end
    end
end)

-- ---------------------------------------------------------------- recover (open)

-- Client prompt -> request. Owner + reach checked here from the server ped; fh_core.open and fh_inventory re-check
-- reach before opening.
RegisterNetEvent('fh:death:open', function(payload)
    local src = source
    if not ready or type(payload) ~= 'table' or type(payload.id) ~= 'string' then return end
    local now = GetGameTimer()
    if lastOpen[src] and now - lastOpen[src] < 500 then return end
    lastOpen[src] = now
    local bag = bags[payload.id]
    if not bag then return end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return end
    -- refuses busy and expired bags too (an expired bag is only ever deleted by the sweep)
    local ok, why = rules.canOpen(bag, citizenidOf(src), GetEntityCoords(ped), cfg.reach, os.time())
    if not ok then return reply(src, 'bag: ' .. why) end
    ok, why = exports.fh_core:open(src, refOf(bag.id))
    if not ok then reply(src, 'bag: ' .. tostring(why or 'fh_refused')) end
end)

lib.callback.register('fh:death:bags', function(src) return publicList(src) end)

---Live bags (copies): { id, owner, coords, expiresAt }. For admin tools / the insurance block (L4).
exports('getBags', function()
    local out = {}
    for id, b in pairs(bags) do out[#out + 1] = { id = id, owner = b.owner, coords = b.coords, expiresAt = b.expiresAt } end
    return out
end)

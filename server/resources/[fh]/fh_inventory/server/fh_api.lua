-- FH: the API fh_core drives fh_inventory through. Every export refuses any caller except fh_core:
-- game resources call fh_core's exports, which apply the rules and then call these.
--
-- Containers are addressed by fh_core refs { type = <fh container type>, id = <id> }:
--   equipped / backpack : id = player server id (number); the ref is that section of the player inventory
--   every other type    : id = the stash/drop id string; the container's fhType must equal ref.type
-- Every mutation re-plans with FhRules under this resource's own state (MoveBetween -> FhCheckMove, AddTo ->
-- FhPickRange): fh_core's own pre-check is advisory only.

local FH_CORE = 'fh_core'

local function FromCore()
    return GetInvokingResource() == FH_CORE
end

-- world ref -> id string | nil
local function WorldId(ref)
    if type(ref) ~= 'table' or not FhContainers.isType(ref.type) or FhContainers.CARRIED[ref.type] then return nil end
    if type(ref.id) ~= 'string' or ref.id == '' or ref.id == 'newdrop' then return nil end
    return ref.id
end

-- ref -> container, id, view | nil, reason. Never creates a container: an unknown id, a shop, 'newdrop', a
-- non-fh stash or a type mismatch is refused (fail closed).
local function Resolve(ref)
    if type(ref) ~= 'table' or not FhContainers.isType(ref.type) then return nil, 'fh_unknown_container' end
    local c, id
    if FhContainers.CARRIED[ref.type] then
        if type(ref.id) ~= 'number' then return nil, 'fh_unknown_container' end
        id = ref.id
        c = InvCore.GetContainer(id)
    else
        id = WorldId(ref)
        if not id then return nil, 'fh_unknown_container' end
        -- registered fh stashes may be unloaded: GetContainer reloads them with their FhMeta caps
        c = InvCore.FhMeta[id] and InvCore.GetContainer(id) or InvCore.Inventories[id]
        if c and c.type == 'shop' then c = nil end
    end
    if not c then return nil, 'fh_unknown_container' end
    for _, v in ipairs(InvCore.FhViews(c) or {}) do
        if v.type == ref.type then return c, id, v end
    end
    return nil, 'fh_unknown_container'
end

local function InView(view, slot)
    local first, last = 1, view.slots
    if view.slotRange then first, last = view.slotRange[1], view.slotRange[2] end
    return type(slot) == 'number' and slot >= first and slot <= last
end

local Fh = {}

--- FhRegisterContainer(ref, { coords, label, slots, maxWeight }) -> true | false, reason
--- fh_core refuses world containers without coords before it gets here; this stores what it is given.
function Fh.RegisterContainer(ref, opts)
    if not FromCore() then return false, 'not_fh_core' end
    local id = WorldId(ref)
    if not id or type(opts) ~= 'table' then return false, 'fh_bad_ref' end
    local inv = InvCore.API.RegisterStash(id, {
        fhType = ref.type, coords = opts.coords, -- nil keeps the coords it has
        label = opts.label, slots = opts.slots, maxWeight = opts.maxWeight,
    })
    return inv ~= nil, inv == nil and 'fh_bad_ref' or nil
end

-- ref -> id, kind ('stash' | 'drop') | nil: a registered fh stash (FhMeta) or a live drop bag, whose fh type
-- must equal ref.type. Drop bags (FhCreateDropBag / any ground pile) have no FhMeta: they are Inventories entries.
local function WorldTarget(ref)
    local id = WorldId(ref)
    if not id then return nil end
    local meta = InvCore.FhMeta[id]
    if meta then
        if meta.fhType ~= ref.type then return nil end
        return id, 'stash'
    end
    local inv = InvCore.Inventories[id]
    if inv and inv.type == 'drop' and inv.fhType == ref.type then return id, 'drop' end
    return nil
end

--- FhSetCoords(ref, coords|nil): moves a container (wagons, drop bags). nil = nobody can open a stash until it
--- has coords again; a drop bag always keeps a position, so nil / bad coords are refused for it.
function Fh.SetCoords(ref, coords)
    if not FromCore() then return false, 'not_fh_core' end
    local id, kind = WorldTarget(ref)
    if not id then return false, 'fh_unknown_container' end
    if kind == 'drop' then return InvCore.MoveDrop(id, coords) end
    local meta = InvCore.FhMeta[id]
    meta.coords = InvCore.ToVec3(coords)
    local inv = InvCore.Inventories[id]
    if inv then inv.coords = meta.coords end
    return true
end

--- FhOpen(src, ref): opens a registered world container or a drop bag for a player (coords + reach are checked
--- by OpenFor). Carried refs (another player's inventory) are refused: searching players is not an fh_core API yet.
function Fh.Open(src, ref)
    if not FromCore() then return false, 'not_fh_core' end
    src = tonumber(src)
    local id, kind = WorldTarget(ref)
    if not src or not id then return false, 'fh_unknown_container' end
    if kind == 'stash' and not InvCore.API.RegisterStash(id) then return false, 'fh_unknown_container' end
    return InvCore.OpenFor(src, id)
end

--- FhOpenRef(src) -> { type, id } | nil, reason: the fh container `src` currently has open next to their own
--- inventory (a registered stash, or a drop bag with an fh type). Read-only; lets fh_core act on "the open pane"
--- without trusting a client-named container.
function Fh.OpenRef(src)
    if not FromCore() then return nil, 'not_fh_core' end
    local id = InvCore.OpenInv[tonumber(src)]
    if type(id) ~= 'string' then return nil, 'fh_nothing_open' end
    local meta = InvCore.FhMeta[id]
    local inv = InvCore.Inventories[id]
    local t = (meta and meta.fhType) or (inv and inv.type == 'drop' and inv.fhType) or nil
    if not t then return nil, 'fh_nothing_open' end
    return { type = t, id = id }
end

--- FhCreateDropBag(coords, items?, opts?) -> id, leftovers
--- items = { { name, amount, info? }, ... }; anything the bag refuses (AddTo veto) comes back in leftovers.
--- opts (owner, label) is accepted for fh_core's signature and not used yet.
function Fh.CreateDropBag(coords, items)
    if not FromCore() then return nil, 'not_fh_core' end
    coords = InvCore.ToVec3(coords)
    if not coords then return nil, 'fh_no_coords' end
    local id = InvCore.API.CreateDrop(coords, {})
    local bag = InvCore.Inventories[id]
    local leftovers = {}
    for _, it in ipairs(type(items) == 'table' and items or {}) do
        if type(it) ~= 'table' or not InvCore.AddTo(bag, it.name, it.amount, it.info) then
            leftovers[#leftovers + 1] = it
        end
    end
    InvCore.Commit(bag)
    InvCore.CleanupDropIfEmpty(id)
    if not InvCore.Inventories[id] then return nil, leftovers end
    InvCore.Refresh(id)
    return id, leftovers
end

--- FhDeleteContainer(ref) -> true, items | false, reason
--- Deletes a registered fh stash (death bags on expiry / when emptied): memory, FhMeta and its `inventories` row.
--- items = what it still held (slot -> item, deep copy) so the caller can log any loss. Refused while anyone has it
--- open (fh_in_use: the caller retries later), so no open UI can move items into a container that is gone.
--- Drops (ground piles) and carried refs are refused.
function Fh.DeleteContainer(ref)
    if not FromCore() then return false, 'not_fh_core' end
    local id, kind = WorldTarget(ref)
    if not id or kind ~= 'stash' then return false, 'fh_unknown_container' end
    if InvCore.IsOpenByAnyone(id) then return false, 'fh_in_use' end
    local c = InvCore.GetContainer(id) -- may load it from the database (awaits)
    if InvCore.IsOpenByAnyone(id) then return false, 'fh_in_use' end
    if not c or InvCore.FhMeta[id] == nil then return false, 'fh_unknown_container' end
    local items = InvCore.DeepClone(c.items or {})
    InvCore.Inventories[id] = nil
    InvCore.FhMeta[id] = nil
    MySQL.prepare('DELETE FROM inventories WHERE identifier = ?', { id })
    InvCore.Log('DeleteContainer', ('fh_core deleted %s (%s)'):format(id, ref.type))
    return true, items
end

--- FhView(ref) -> view | nil, reason. The FhRules view of the container (a player section for carried refs).
function Fh.View(ref)
    if not FromCore() then return nil, 'not_fh_core' end
    local c, _, view = Resolve(ref)
    if not c then return nil, _ end
    return InvCore.DeepClone(view)
end

--- FhSnapshot(ref) -> items (slot -> item, deep copy) | nil, reason. Carried refs: that section's slots only.
function Fh.Snapshot(ref)
    if not FromCore() then return nil, 'not_fh_core' end
    local c, _, view = Resolve(ref)
    if not c then return nil, _ end
    return InvCore.DeepClone(view.items)
end

--- FhMove(fromRef, toRef, fromSlot, toSlot, amount?) -> true | false, reason
--- Slots are the container's own slot numbers; each must lie inside its ref's section. Re-planned by MoveBetween.
function Fh.Move(fromRef, toRef, fromSlot, toSlot, amount)
    if not FromCore() then return false, 'not_fh_core' end
    local from, fromId, fromView = Resolve(fromRef)
    if not from then return false, fromId end
    local to, toId, toView = Resolve(toRef)
    if not to then return false, toId end
    fromSlot, toSlot = math.tointeger(tonumber(fromSlot)), math.tointeger(tonumber(toSlot))
    if not InView(fromView, fromSlot) or not InView(toView, toSlot) then return false, 'fh_bad_slot' end
    return InvCore.MoveBetween(nil, from, fromId, toId, fromSlot, toSlot, amount)
end

--- FhTransferAll(fromRef, toRef) -> true, moved, leftovers | false, reason
--- Plans with FhRules.planTransferAll, then applies each step through MoveBetween (which re-checks it).
--- moved = the plan steps that were applied; leftovers = planner leftovers + steps refused on apply.
function Fh.TransferAll(fromRef, toRef)
    if not FromCore() then return false, 'not_fh_core' end
    local from, fromId, fromView = Resolve(fromRef)
    if not from then return false, fromId end
    local to, toId, toView = Resolve(toRef)
    if not to then return false, toId end
    if toId == fromId then -- equipped <-> backpack of one player: sibling views of one split share a group
        for _, v in ipairs(InvCore.FhViews(from)) do
            if v.type == toRef.type then toView = v elseif v.type == fromRef.type then fromView = v end
        end
    end
    local plan, leftovers = FhRules.planTransferAll(fromView, toView)
    local moved = {}
    for _, step in ipairs(plan) do
        -- fresh container each step: the previous one was committed (players are rebuilt from PlayerData)
        local src = InvCore.GetContainer(fromId)
        local ok, why = false, 'fh_no_item'
        if src then ok, why = InvCore.MoveBetween(nil, src, fromId, toId, step.fromSlot, step.toSlot, step.amount) end
        if ok then
            moved[#moved + 1] = step
        else
            leftovers[#leftovers + 1] = { slot = step.fromSlot, name = step.name, amount = step.amount,
                reason = why or 'fh_refused' }
        end
    end
    return true, moved, leftovers
end

-- carried ref -> player container, src, view | nil, reason. World refs are refused: they go through AddItem /
-- RemoveItem on the stash id (fh_core checks they are registered).
local function Carried(ref)
    if type(ref) ~= 'table' or not FhContainers.CARRIED[ref.type] then return nil, 'fh_unknown_container' end
    return Resolve(ref)
end

--- FhAddItem(ref, name, amount, info?, reason?) -> true | false, reason   (carried refs only)
--- Adds into that one section of the player inventory (equipped = hotbar, backpack = the rest), never the other:
--- the FhRules veto runs against that section only (bulky never enters the backpack). Nothing is added on refusal.
function Fh.AddItem(ref, name, amount, info, reason)
    if not FromCore() then return false, 'not_fh_core' end
    local c, src = Carried(ref)
    if not c then return false, src end
    amount = type(amount) == 'number' and math.tointeger(amount) or nil
    if not amount or amount < 1 then return false, 'fh_bad_amount' end
    if not InvCore.SharedItem(name) then return false, 'fh_unknown_item' end
    local ok, why = InvCore.AddTo(c, name, amount, info, nil, ref.type)
    if not ok then return false, why end
    InvCore.Commit(c)
    InvCore.Refresh(src)
    TriggerClientEvent('rsg-inventory:client:ItemBox', src, InvCore.SharedItem(name), 'add', amount)
    InvCore.Log('AddItem', ('%s received %sx %s in %s (%s) [fh_core]'):format(GetPlayerName(src), amount, name,
        ref.type, tostring(reason or 'unknown')))
    return true
end

--- FhRemoveItem(ref, name, amount, reason?) -> true | false, reason   (carried refs only)
--- Takes exactly `amount` of `name` from that one section, lowest slot first, all-or-nothing: the section is counted
--- and emptied with no yield in between, so a short section is never partly emptied (fh_not_enough).
function Fh.RemoveItem(ref, name, amount, reason)
    if not FromCore() then return false, 'not_fh_core' end
    local c, src, view = Carried(ref)
    if not c then return false, src end
    amount = type(amount) == 'number' and math.tointeger(amount) or nil
    if not amount or amount < 1 then return false, 'fh_bad_amount' end
    if type(name) ~= 'string' or name == '' then return false, 'fh_bad_item_name' end
    name = name:lower()
    local first, last = view.slotRange[1], view.slotRange[2]
    local have = 0
    for slot = first, last do
        local it = c.items[slot]
        if it and it.name == name then have = have + it.amount end
    end
    if have < amount then return false, 'fh_not_enough' end
    local left, taken = amount, nil
    for slot = first, last do
        local it = c.items[slot]
        if left <= 0 then break end
        if it and it.name == name then
            local take = math.min(it.amount, left)
            it.amount = it.amount - take
            if it.amount <= 0 then c.items[slot] = nil end
            left = left - take
            taken = taken or it
        end
    end
    InvCore.Commit(c)
    InvCore.Refresh(src)
    if InvCore.CountIn(c, name) == 0 then InvCore.CheckWeapon(src, taken) end
    TriggerClientEvent('rsg-inventory:client:ItemBox', src, InvCore.SharedItem(name), 'remove', amount)
    InvCore.Log('RemoveItem', ('%s lost %sx %s from %s (%s) [fh_core]'):format(GetPlayerName(src), amount, name,
        ref.type, tostring(reason or 'unknown')))
    return true
end

for name, fn in pairs(Fh) do exports('Fh' .. name, fn) end
InvCore.Fh = Fh

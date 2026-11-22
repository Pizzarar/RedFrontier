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

for name, fn in pairs(Fh) do exports('Fh' .. name, fn) end
InvCore.Fh = Fh

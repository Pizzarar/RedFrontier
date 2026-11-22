-- FH: the API fh_core drives fh_inventory through. Every export refuses any caller except fh_core:
-- game resources call fh_core's exports, which apply the rules and then call these.

local FH_CORE = 'fh_core'

local function FromCore()
    return GetInvokingResource() == FH_CORE
end

local Fh = {}

--- FhRegisterContainer(id, { fhType, coords, label, slots, maxWeight }) -> true | false, reason
--- fh_core refuses world containers without coords before it gets here; this stores what it is given.
function Fh.RegisterContainer(id, opts)
    if not FromCore() then return false, 'not_fh_core' end
    if type(id) ~= 'string' or type(opts) ~= 'table' or type(opts.fhType) ~= 'string' then return false, 'bad_args' end
    local inv = InvCore.API.RegisterStash(id, {
        fhType = opts.fhType, coords = opts.coords, -- nil keeps the coords it has
        label = opts.label, slots = opts.slots, maxWeight = opts.maxWeight,
    })
    return inv ~= nil, inv == nil and 'bad_id' or nil
end

--- FhSetCoords(id, coords|nil): moves a container (wagons). nil = nobody can open it until it has coords again.
function Fh.SetCoords(id, coords)
    if not FromCore() then return false, 'not_fh_core' end
    local meta = type(id) == 'string' and InvCore.FhMeta[id]
    if not meta then return false, 'unknown_container' end
    meta.coords = InvCore.ToVec3(coords)
    local inv = InvCore.Inventories[id]
    if inv then inv.coords = meta.coords end
    return true
end

--- FhOpen(src, id): opens a registered container for a player (coords + reach are checked by OpenFor)
function Fh.Open(src, id)
    if not FromCore() then return false, 'not_fh_core' end
    src = tonumber(src)
    if not src or type(id) ~= 'string' or not InvCore.FhMeta[id] then return false, 'unknown_container' end
    if not InvCore.API.RegisterStash(id) then return false, 'unknown_container' end
    return InvCore.OpenFor(src, id)
end

--- FhCreateDropBag(coords, items?) -> id, leftovers
--- items = { { name, amount, info? }, ... }; anything the bag refuses comes back in leftovers.
function Fh.CreateDropBag(coords, items)
    if not FromCore() then return nil, 'not_fh_core' end
    coords = InvCore.ToVec3(coords)
    if not coords then return nil, 'no_coords' end
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

-- FH: FhView, FhSnapshot, FhMove and FhTransferAll are added with the FhRules wiring (B4a2 step 4).

for name, fn in pairs(Fh) do exports('Fh' .. name, fn) end
InvCore.Fh = Fh

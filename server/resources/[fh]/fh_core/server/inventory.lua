-- fh_core server container API (spec §4.2). The one inventory API other lanes use:
--   exports.fh_core:move / canFit / getWeight / snapshot / transferAll
--   exports.fh_core:registerContainer / setContainerCoords / open / createDropBag / deleteContainer / registerItems
--   exports.fh_core:addItem / removeItem (registered world containers and carried refs of an online player)
--   exports.fh_core:clearContainer (registered world containers only)
-- fh_core never reads or writes inventory tables. Everything goes through fh_inventory's Fh* exports, which re-check
-- with FhRules under their own state before mutating anything.
--
-- A container ref is { type = <container type>, id = <id> }:
--   equipped / backpack : id = player server id (number)
--   every other type    : id = the fh_inventory stash/drop id string (e.g. 'fh:chest:<homestead>:<n>')
-- Natives used here: GetPlayerPed, GetEntityCoords (see docs/natives.md).

local INV = 'fh_inventory'

local registered = {}   -- key -> { ref, opts } : re-sent when fh_inventory (re)starts
local RSGCore

local function core()
    if not RSGCore and GetResourceState('rsg-core') == 'started' then
        RSGCore = exports['rsg-core']:GetCoreObject()
    end
    return RSGCore
end

-- Base RSG items (bread, ...) live only in RSGCore.Shared.Items: let FhItems.resolve see them in this Lua state too.
FhItems.sharedLookup = function(name)
    local c = core()
    local item = c and c.Shared.Items[name]
    return type(item) == 'table' and item or nil
end

AddEventHandler('RSGCore:Server:UpdateObject', function()
    if GetResourceState('rsg-core') == 'started' then RSGCore = exports['rsg-core']:GetCoreObject() end
end)

local function refKey(ref) return tostring(ref.type) .. '|' .. tostring(ref.id) end

local function validRef(ref)
    if type(ref) ~= 'table' or not FhContainers.isType(ref.type) then return false, 'fh_unknown_container' end
    if FhContainers.CARRIED[ref.type] then
        if type(ref.id) ~= 'number' then return false, 'fh_bad_ref' end
    elseif type(ref.id) ~= 'string' or ref.id == '' then
        return false, 'fh_bad_ref'
    end
    return true
end

---Call an fh_inventory export. Returns false, 'fh_inventory_down' when it isn't running or the call throws.
local function inv(fn, ...)
    if GetResourceState(INV) ~= 'started' then return false, 'fh_inventory_down' end
    local res = table.pack(pcall(exports[INV][fn], exports[INV], ...))
    if not res[1] then
        print(('^1[fh_core] %s.%s failed: %s^7'):format(INV, fn, tostring(res[2])))
        return false, 'fh_inventory_error'
    end
    return table.unpack(res, 2, res.n)
end

local function citizenidOf(src)
    local c = type(src) == 'number' and core()
    local p = c and c.Functions.GetPlayer(src)
    return p and p.PlayerData.citizenid or nil
end

-- An online player with a loaded character (rsg-core only has a Player once a character is selected).
local function onlinePlayer(src)
    return type(src) == 'number' and GetPlayerPed(src) ~= 0 and citizenidOf(src) ~= nil
end

-- amount argument -> integer >= 1 | nil. nil means 1; 2.0 is fine; 2.5, NaN, inf, '2', 0, -1 are refused.
local function countOf(amount)
    if amount == nil then return 1 end
    amount = type(amount) == 'number' and math.tointeger(amount) or nil
    if not amount or amount < 1 then return nil end
    return amount
end

-- fh_inventory's log line for an add/remove: which resource asked, through which export
local function callerTag(fn)
    return ('%s via fh_core.%s'):format(GetInvokingResource() or GetCurrentResourceName(), fn)
end

local function actorOf(fromRef, toRef, src)
    if type(src) == 'number' then return src end
    if FhContainers.CARRIED[fromRef.type] then return fromRef.id end
    if FhContainers.CARRIED[toRef.type] then return toRef.id end
    return nil
end

-- Payloads follow fh_core/docs/events.md: one table, src first, additive fields only.
local function emit(name, src, fields)
    local payload = { src = src, citizenid = citizenidOf(src) }
    for k, v in pairs(fields) do payload[k] = v end
    TriggerEvent(name, payload)
end

local function view(ref)
    local ok, reason = validRef(ref)
    if not ok then return nil, reason end
    local v, err = inv('FhView', ref)
    if type(v) ~= 'table' then return nil, err or 'fh_no_container' end
    return v
end

-- ---------------------------------------------------------------- queries

---@param item table|string runtime item, or an item name (looked up in RSGCore.Shared.Items, then fh definitions)
---@return boolean ok, string|nil reason
local function canFit(ref, item, amount, opts)
    local v, reason = view(ref)
    if not v then return false, reason end
    if type(item) == 'string' then
        local c = core()
        local s = c and c.Shared.Items[item]
        if s then item = { name = item, weight = s.weight, unique = s.unique, info = {} } end
    end
    local ok, why = FhRules.canFit(v, item, amount, opts)
    return ok, why
end

---@return number|nil grams, string|nil reason
local function getWeight(ref)
    local v, reason = view(ref)
    if not v then return nil, reason end
    return FhRules.getWeight(v)
end

---Deep copy of the container's items (slot -> item), safe to keep.
---@return table|nil items, string|nil reason
local function snapshot(ref)
    local ok, reason = validRef(ref)
    if not ok then return nil, reason end
    local items, err = inv('FhSnapshot', ref)
    if type(items) ~= 'table' then return nil, err or 'fh_no_container' end
    return items
end

-- ---------------------------------------------------------------- mutations

---Move `amount` (nil = whole stack) from fromRef[fromSlot] to toRef[toSlot]. fh_inventory re-plans and applies.
---@param src number|nil acting player for events (defaults to the player side of the move)
---@return boolean ok, string|nil reason
local function move(fromRef, toRef, fromSlot, toSlot, amount, src)
    local ok, reason = validRef(fromRef)
    if ok then ok, reason = validRef(toRef) end
    local actor = ok and actorOf(fromRef, toRef, src) or src
    local item, count
    if ok then
        local fromView, toView
        fromView, reason = view(fromRef)
        if fromView then toView, reason = view(toRef) end
        ok = fromView ~= nil and toView ~= nil
        if ok and fromRef.id == toRef.id and FhContainers.CARRIED[fromRef.type] and FhContainers.CARRIED[toRef.type] then
            -- equipped + backpack of one player are sibling views of one split. They came back from two FhView
            -- calls (msgpack'd), so their group tokens are distinct tables: share one again so planMove credits
            -- the grams leaving the sibling section (siblingFreed), as fh_inventory's own re-check does.
            local group = {}
            fromView.group, toView.group = group, group
        end
        if ok then
            local plan
            plan, reason = FhRules.planMove(fromView, toView, fromSlot, toSlot, amount)
            ok = plan ~= nil
            if plan then item, count = plan.name, plan.amount end
        end
    end
    if ok then ok, reason = inv('FhMove', fromRef, toRef, fromSlot, toSlot, amount) end
    if ok then
        emit('fh:inventory:moved', actor, { from = fromRef, to = toRef, item = item, count = count })
        return true
    end
    emit('fh:inventory:refused', actor,
        { from = fromRef, to = toRef, item = item, count = count or amount, reason = reason or 'fh_refused' })
    return false, reason or 'fh_refused'
end

---Move everything that fits from fromRef to toRef (stackables partially).
---@return boolean ok, table|string movedOrReason, table|nil leftovers
--- moved/leftovers: arrays as FhRules.planTransferAll returns them, as actually applied by fh_inventory
local function transferAll(fromRef, toRef, src)
    local ok, reason = validRef(fromRef)
    if ok then ok, reason = validRef(toRef) end
    if not ok then return false, reason end
    local moved, leftovers
    ok, moved, leftovers = inv('FhTransferAll', fromRef, toRef)
    if not ok then return false, moved or 'fh_refused' end
    moved, leftovers = moved or {}, leftovers or {}
    emit('fh:inventory:transferred', actorOf(fromRef, toRef, src),
        { from = fromRef, to = toRef, moved = moved, leftovers = leftovers })
    return true, moved, leftovers
end

-- ---------------------------------------------------------------- containers

---Register a world container. opts = { coords (required), slots?, maxWeight?, label? }. Defaults from FhConfig.
---Carried types (equipped/backpack) are not registrable. A world container without valid coords is refused.
---Stored and re-sent to fh_inventory whenever it (re)starts.
---@return boolean ok, string|nil reason
local function registerContainer(ref, opts)
    local ok, reason = validRef(ref)
    if not ok then return false, reason end
    if FhContainers.CARRIED[ref.type] then return false, 'fh_not_registrable' end
    opts = opts or {}
    if not FhContainers.validCoords(opts.coords) then return false, 'fh_no_coords' end
    local d = FhContainers.defaults(ref.type) or {}
    local entry = {
        slots = tonumber(opts.slots) or d.slots,
        maxWeight = tonumber(opts.maxWeight) or d.maxWeight,
        coords = opts.coords,
        label = opts.label,
    }
    registered[refKey(ref)] = { ref = { type = ref.type, id = ref.id }, opts = entry }
    if GetResourceState(INV) ~= 'started' then return true end -- applied on fh_inventory start
    return inv('FhRegisterContainer', ref, entry)
end

---@return boolean ok, string|nil reason
local function setContainerCoords(ref, coords)
    local ok, reason = validRef(ref)
    if not ok then return false, reason end
    if FhContainers.CARRIED[ref.type] then return false, 'fh_not_registrable' end
    if not FhContainers.validCoords(coords) then return false, 'fh_no_coords' end
    local reg = registered[refKey(ref)]
    if reg then reg.opts.coords = coords end
    return inv('FhSetCoords', ref, coords)
end

---Open a container's UI for player `src`. Reach is checked here from the server-side ped position and again by
---fh_inventory (FhOpen) before it opens.
---@return boolean ok, string|nil reason
local function open(src, ref)
    local ok, reason = validRef(ref)
    if not ok then return false, reason end
    if type(src) ~= 'number' or GetPlayerPed(src) == 0 then return false, 'fh_no_player' end
    if not FhContainers.CARRIED[ref.type] then
        local v
        v, reason = view(ref)
        if not v then return false, reason end
        local ped = GetPlayerPed(src)
        ok, reason = FhContainers.canReach(ref.type, v.coords, GetEntityCoords(ped))
        if not ok then return false, reason end
    end
    return inv('FhOpen', src, ref)
end

---Put `amount` (default 1) of an item (with optional info) into a registered world container, or into one section
---of an online player's inventory (carried ref { type = 'equipped'|'backpack', id = src }). All or nothing: the
---container rules veto runs first and nothing is added on a refusal. A carried add lands in that section only
---(bulky never enters the backpack). For server-side loot (camps), rewards, crafting output.
---@return boolean ok, string|nil reason  fh_player_offline: carried ref whose src has no loaded character
local function addItem(ref, name, amount, info)
    local ok, reason = validRef(ref)
    if not ok then return false, reason end
    local carried = FhContainers.CARRIED[ref.type]
    if carried then
        if not onlinePlayer(ref.id) then return false, 'fh_player_offline' end
    elseif not registered[refKey(ref)] then
        return false, 'fh_unknown_container'
    end
    if type(name) ~= 'string' or name == '' then return false, 'fh_bad_item_name' end
    amount = countOf(amount)
    if not amount then return false, 'fh_bad_amount' end
    if info ~= nil and type(info) ~= 'table' then return false, 'fh_bad_info' end
    local done, err
    if carried then
        done, err = inv('FhAddItem', ref, name, amount, info, callerTag('addItem'))
    else
        done, err = inv('AddItem', ref.id, name, amount, info, nil, callerTag('addItem'))
    end
    if done == true then return true end
    return false, type(err) == 'string' and err or 'fh_refused'
end

---Take exactly `amount` (default 1) of item `name` out of a registered world container (B7) or out of one section
---of an online player's inventory (carried ref, C3a), all-or-nothing. fh_inventory's RemoveItem without a slot
---(world) and FhRemoveItem (carried: that section only) count first and remove only when the count covers
---`amount`, with no yield in between, so a short container is never partly emptied.
---@return boolean ok, string|nil reason  fh_not_enough when the container holds fewer (nothing removed);
---  fh_player_offline: carried ref whose src has no loaded character
local function removeItem(ref, name, amount)
    local ok, reason = validRef(ref)
    if not ok then return false, reason end
    local carried = FhContainers.CARRIED[ref.type]
    if carried then
        if not onlinePlayer(ref.id) then return false, 'fh_player_offline' end
    elseif not registered[refKey(ref)] then
        return false, 'fh_unknown_container'
    end
    if type(name) ~= 'string' or name == '' then return false, 'fh_bad_item_name' end
    amount = countOf(amount)
    if not amount then return false, 'fh_bad_amount' end
    if carried then
        local done, err = inv('FhRemoveItem', ref, name, amount, callerTag('removeItem'))
        if done == true then return true end
        return false, type(err) == 'string' and err or 'fh_refused'
    end
    local have, why = inv('GetItemCount', ref.id, name)
    if type(have) ~= 'number' then return false, type(why) == 'string' and why or 'fh_inventory_error' end
    if have < amount then return false, 'fh_not_enough' end
    local done, err = inv('RemoveItem', ref.id, name, amount, nil, callerTag('removeItem'))
    if done == true then return true end
    if err == 'fh_inventory_down' or err == 'fh_inventory_error' then return false, err end
    have = inv('GetItemCount', ref.id, name)
    if type(have) == 'number' and have < amount then return false, 'fh_not_enough' end
    return false, 'fh_refused'
end

---Empty a registered world container (fh_inventory only lets fh_core wipe an fh_core container).
---@return boolean ok, string|nil reason
local function clearContainer(ref)
    local ok, reason = validRef(ref)
    if not ok then return false, reason end
    if FhContainers.CARRIED[ref.type] then return false, 'fh_not_registrable' end
    if not registered[refKey(ref)] then return false, 'fh_unknown_container' end
    local r, err = inv('ClearStash', ref.id)
    if r == false then return false, err end
    return true
end

---Create a drop bag (death / spill) at coords holding `items` (array of {name, amount, info}).
---opts = { owner = citizenid?, label? }.
---@return string|nil id, string|nil reason
local function createDropBag(coords, items, opts)
    if not FhContainers.validCoords(coords) then return nil, 'fh_no_coords' end
    local id, reason = inv('FhCreateDropBag', coords, items or {}, opts or {})
    if type(id) ~= 'string' then
        -- FhCreateDropBag returns nil, leftovers (a table) when every item was refused: that is not a reason code.
        return nil, type(reason) == 'string' and reason or 'fh_refused'
    end
    return id
end

---Delete a registered world container (death bags). Refused while anyone has it open (fh_in_use: retry later).
---Also forgets it here so it is not re-sent when fh_inventory restarts.
---@return boolean ok, table|string itemsOrReason items = what it still held (slot -> item), for loss logging
local function deleteContainer(ref)
    local ok, reason = validRef(ref)
    if not ok then return false, reason end
    if FhContainers.CARRIED[ref.type] then return false, 'fh_not_registrable' end
    local items
    ok, items = inv('FhDeleteContainer', ref)
    if not ok then return false, items or 'fh_refused' end
    registered[refKey(ref)] = nil
    return true, items or {}
end

-- ---------------------------------------------------------------- items

-- Push fh definitions and ItemOverrides into RSGCore.Shared.Items (one SetItems broadcast). Entries built from a full
-- fh definition carry `fh_defined = true`, so registerItems can tell them from base rsg items after an fh_core restart.
local function pushItems(names)
    local c = core()
    if not c then return false, 'rsg_core_down' end
    local shared = c.Shared.Items
    local batch = {}
    local defs = FhItems.all()
    if names then
        for _, n in ipairs(names) do batch[n] = FhItems.toRsg(n, defs[n], shared[n]); batch[n].fh_defined = true end
    else
        for n, def in pairs(defs) do batch[n] = FhItems.toRsg(n, def, shared[n]); batch[n].fh_defined = true end
        for n, over in pairs(FhConfig.ItemOverrides or {}) do
            if shared[n] and not batch[n] then batch[n] = FhItems.toRsg(n, over, shared[n]) end
        end
    end
    if next(batch) == nil then return true end
    local ok, err = exports['rsg-core']:SetItems(batch)
    if ok then return true end
    return false, type(err) == 'string' and err or 'rsg_setitems_failed'
end

-- A base rsg item: in RSGCore.Shared.Items but not built from an fh definition.
local function isBaseItem(name)
    local c = core()
    local item = c and c.Shared.Items[name]
    return type(item) == 'table' and not item.fh_defined
end

---Define items at runtime from any resource: defs = { name = { label, weight, size_class, stackable, value_base,
---illicit, ... } } (full §4.1 definitions). The whole batch is checked first (FhItems.checkRegister: schema, name,
---no duplicate of a config item, a base rsg item or another resource's item) and nothing is applied on a refusal.
---The calling resource may re-register its own names (e.g. after it restarts).
---@return boolean ok, string|nil err, string|nil badName
local function registerItems(defs)
    local owner = GetInvokingResource() or GetCurrentResourceName()
    local ok, err, names = FhItems.register(defs, owner, isBaseItem)
    if not ok then return false, err, names end
    return pushItems(names)
end

-- ---------------------------------------------------------------- lifecycle

local function validateConfigItems()
    for name, def in pairs(FhConfig.Items or {}) do
        local ok, err = FhItems.validate(def)
        if not ok then print(('^1[fh_core] FhConfig.Items.%s invalid: %s^7'):format(name, err)) end
    end
    for name, over in pairs(FhConfig.ItemOverrides or {}) do
        local ok, err = FhItems.validate(over, true)
        if not ok then print(('^1[fh_core] FhConfig.ItemOverrides.%s invalid: %s^7'):format(name, err)) end
    end
end

local function resendContainers()
    for _, reg in pairs(registered) do inv('FhRegisterContainer', reg.ref, reg.opts) end
end

AddEventHandler('onResourceStart', function(res)
    if res == GetCurrentResourceName() then
        validateConfigItems()
        pushItems()
    elseif res == 'rsg-core' then
        RSGCore = nil
        pushItems()
    elseif res == INV then
        resendContainers()
    end
end)

exports('move', move)
exports('canFit', canFit)
exports('getWeight', getWeight)
exports('snapshot', snapshot)
-- B6e: read-only view of a container ({ items, slots, coords, ... }) and the pane the player has open
exports('view', function(ref) return view(ref) end)
exports('openRef', function(src)
    if type(src) ~= 'number' then return nil, 'fh_no_player' end
    local ref, why = inv('FhOpenRef', src)
    if type(ref) ~= 'table' then return nil, why or 'fh_nothing_open' end
    return ref
end)
exports('transferAll', transferAll)
exports('registerContainer', registerContainer)
exports('setContainerCoords', setContainerCoords)
exports('open', open)
exports('createDropBag', createDropBag)
exports('addItem', addItem)
exports('removeItem', removeItem)
exports('clearContainer', clearContainer)
exports('deleteContainer', deleteContainer)
exports('registerItems', registerItems)

-- fh_core container veto + move planning (spec §4.2). Pure Lua: no natives, so busted can load it.
-- fh_inventory calls these before it mutates anything; fh_core's server API calls them through fh_inventory's exports.
--
-- view = {
--   type      = container type (see shared/containers.lua),
--   items     = slot -> item map (rsg runtime items: name, amount, weight (per unit), unique, info, slot),
--   slots     = slot count,
--   maxWeight = grams,
--   slotRange = {first, last} | nil   (nil means 1..slots),
--   coords    = vector3 | nil,
--   -- optional, set by playerViews (callers building their own views can leave them out):
--   ownMaxWeight = the section's own cap (maxWeight may be lower because a sibling section holds weight),
--   group        = shared token for views carved from one container (equipped + backpack),
--   id           = container id; two views with the same id and slotRange count as the same view,
-- }
-- Only items inside the view's slot range count, so a caller may pass the whole player map with a slotRange.
--
-- Reasons are locale keys (fh_*): fh_unknown_container, fh_unknown_item, fh_bad_size_class, fh_size_class,
-- fh_bad_amount, fh_bad_slot, fh_too_heavy, fh_slot_taken, fh_no_slot, fh_no_item, fh_same_slot.
local M = {}

local function cfg() return FhConfig or require('config') end
local function items() return FhItems or require('items') end
local function containers() return FhContainers or require('containers') end

local function range(view)
    if view.slotRange then return view.slotRange[1], view.slotRange[2] end
    return 1, view.slots or 0
end

local function inRange(view, slot)
    if type(slot) ~= 'number' or slot % 1 ~= 0 then return false end
    local first, last = range(view)
    return slot >= first and slot <= last
end

local function isCount(n) return type(n) == 'number' and n % 1 == 0 and n > 0 end

local function deepEqual(a, b)
    if a == b then return true end
    if a == nil then a = {} end
    if b == nil then b = {} end
    if type(a) ~= 'table' or type(b) ~= 'table' then return false end
    for k, v in pairs(a) do if not deepEqual(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end

---Resolve an item's definition (item may be a name string).
local function defOf(item)
    if type(item) == 'string' then return items().resolve(item, nil) end
    if type(item) ~= 'table' then return nil, 'fh_unknown_item' end
    return items().resolve(item.name, item)
end

---Per-unit weight: the runtime item's weight (what rsg-inventory counts), else the definition's.
function M.unitWeight(item)
    if type(item) == 'table' and tonumber(item.weight) then return tonumber(item.weight) end
    local def = defOf(item)
    return def and def.weight or 0
end

---Total weight of the items inside the view's slot range.
function M.getWeight(view)
    local total = 0
    for slot, item in pairs(view.items or {}) do
        if inRange(view, slot) then total = total + M.unitWeight(item) * (tonumber(item.amount) or 1) end
    end
    return total
end

---Same name, stackable, and equal info (deep). Mirrors rsg-inventory's CanStack.
function M.canStack(a, b)
    if type(a) ~= 'table' or type(b) ~= 'table' or a.name ~= b.name then return false end
    local def = defOf(a)
    if not def or not def.stackable then return false end
    return deepEqual(a.info, b.info)
end

local function sameView(a, b)
    if rawequal(a, b) then return true end
    if a.id == nil or a.id ~= b.id then return false end
    local af, al = range(a)
    local bf, bl = range(b)
    return af == bf and al == bl
end

local function limitOf(view, siblingFreed)
    local limit = (view.maxWeight or math.huge) + (siblingFreed or 0)
    if view.ownMaxWeight and view.ownMaxWeight < limit then limit = view.ownMaxWeight end
    return limit
end

---Can `amount` of `item` go into `view`?
---@param item table|string runtime item or item name
---@param amount integer|nil defaults to item.amount, then 1
---@param opts table|nil {
---   slot = target slot (nil: any stack or free slot in range),
---   replacing = item table leaving the view in the same operation (its slot counts as free, its weight is removed),
---   freed = extra grams leaving this view in the same operation,
---   siblingFreed = grams leaving a sibling view of the same group (raises maxWeight up to ownMaxWeight) }
---@return boolean ok, string|nil reason, integer|nil slot  (slot: the target or the first stack/free slot found)
function M.canFit(view, item, amount, opts)
    opts = opts or {}
    if type(view) ~= 'table' or not containers().isType(view.type) then return false, 'fh_unknown_container' end
    local def, err = defOf(item)
    if not def then return false, err end
    if type(item) == 'string' then item = { name = item } end
    amount = amount or item.amount or 1
    if not isCount(amount) then return false, 'fh_bad_amount' end
    if not def.stackable and opts.slot ~= nil and amount > 1 then return false, 'fh_bad_amount' end

    local ok, reason = containers().accepts(view.type, def.size_class)
    if not ok then return false, reason end

    local replacing = opts.replacing
    local used = M.getWeight(view) - (opts.freed or 0)
    if replacing then used = used - M.unitWeight(replacing) * (tonumber(replacing.amount) or 1) end
    local unit = tonumber(item.weight) or def.weight
    if used + unit * amount > limitOf(view, opts.siblingFreed) then return false, 'fh_too_heavy' end

    local function freeAt(slot)
        local occ = view.items[slot]
        return occ == nil or (replacing ~= nil and rawequal(occ, replacing))
    end

    if opts.slot ~= nil then
        if not inRange(view, opts.slot) then return false, 'fh_bad_slot' end
        if freeAt(opts.slot) then return true, nil, opts.slot end
        if def.stackable and M.canStack(view.items[opts.slot], item) then return true, nil, opts.slot end
        return false, 'fh_slot_taken'
    end

    local first, last = range(view)
    if def.stackable then
        for s = first, last do
            local occ = view.items[s]
            if occ and not freeAt(s) and M.canStack(occ, item) then return true, nil, s end
        end
    end
    local need = def.stackable and 1 or amount
    local firstFree
    for s = first, last do
        if freeAt(s) then
            firstFree = firstFree or s
            need = need - 1
            if need == 0 then return true, nil, firstFree end
        end
    end
    return false, 'fh_no_slot'
end

---Split the player inventory into the equipped (first N slots) and backpack (rest) views.
---Each section's cap = min(own cap, totalCap - the other section's weight). Backpack has no own cap unless
---FhConfig.Containers.backpack.maxWeight is set.
---@param playerItems table slot -> item
---@param totalCap number player's total carry weight (rsg-inventory); defaults to FhConfig.Player.MaxWeight
---@param totalSlots integer|nil player's slot count incl. capacity bonus; defaults to FhConfig.Player.Slots
---@return table equippedView, table backpackView
function M.playerViews(playerItems, totalCap, totalSlots)
    local c = cfg()
    local eqCfg = (c.Containers or {}).equipped or {}
    local bpCfg = (c.Containers or {}).backpack or {}
    totalCap = totalCap or c.Player.MaxWeight
    totalSlots = totalSlots or c.Player.Slots
    local hot = math.min(eqCfg.slots or 5, totalSlots)

    local group = {}
    local eq = { type = 'equipped', items = {}, slots = hot, slotRange = { 1, hot }, group = group }
    local bp = { type = 'backpack', items = {}, slots = totalSlots - hot, slotRange = { hot + 1, totalSlots },
        group = group }
    for slot, item in pairs(playerItems or {}) do
        if inRange(eq, slot) then eq.items[slot] = item elseif inRange(bp, slot) then bp.items[slot] = item end
    end
    local eqW, bpW = M.getWeight(eq), M.getWeight(bp)
    eq.ownMaxWeight = math.min(eqCfg.maxWeight or totalCap, totalCap)
    bp.ownMaxWeight = math.min(bpCfg.maxWeight or totalCap, totalCap)
    eq.maxWeight = math.max(0, math.min(eq.ownMaxWeight, totalCap - bpW))
    bp.maxWeight = math.max(0, math.min(bp.ownMaxWeight, totalCap - eqW))
    return eq, bp
end

---Plan a drag from fromView[fromSlot] to toView[toSlot]. Nothing is mutated.
---@return table|nil plan, string|nil reason
--- plan = { kind = 'move'|'stack'|'swap', name, fromSlot, toSlot, amount, fromType, toType,
---          swapName, swapAmount (swap only: the destination stack that goes back to fromSlot) }
--- A swap needs the whole source stack (amount == item.amount), as in rsg-inventory.
function M.planMove(fromView, toView, fromSlot, toSlot, amount)
    if type(fromView) ~= 'table' or type(toView) ~= 'table' then return nil, 'fh_unknown_container' end
    if not inRange(fromView, fromSlot) then return nil, 'fh_bad_slot' end
    local item = fromView.items[fromSlot]
    if not item then return nil, 'fh_no_item' end
    local have = tonumber(item.amount) or 1
    amount = amount or have
    if not isCount(amount) or amount > have then return nil, 'fh_bad_amount' end
    if not inRange(toView, toSlot) then return nil, 'fh_bad_slot' end

    local same = sameView(fromView, toView)
    if same and fromSlot == toSlot then return nil, 'fh_same_slot' end
    local grouped = not same and fromView.group ~= nil and rawequal(fromView.group, toView.group)

    -- grams that leave the *other* side of the move, credited to the side being checked
    local function credit(o, grams)
        if same then o.freed = grams elseif grouped then o.siblingFreed = grams end
        return o
    end

    local w = M.unitWeight(item) * amount
    local plan = { name = item.name, fromSlot = fromSlot, toSlot = toSlot, amount = amount,
        fromType = fromView.type, toType = toView.type }
    local dest = toView.items[toSlot]

    if dest == nil or (M.canStack(dest, item)) then
        local ok, reason = M.canFit(toView, item, amount, credit({ slot = toSlot }, w))
        if not ok then return nil, reason end
        plan.kind = dest and 'stack' or 'move'
        return plan
    end

    if amount ~= have then return nil, 'fh_slot_taken' end
    local destAmount = tonumber(dest.amount) or 1
    local dw = M.unitWeight(dest) * destAmount
    local ok, reason = M.canFit(toView, item, amount, credit({ slot = toSlot, replacing = dest }, w))
    if not ok then return nil, reason end
    ok, reason = M.canFit(fromView, dest, destAmount, credit({ slot = fromSlot, replacing = item }, dw))
    if not ok then return nil, reason end
    plan.kind = 'swap'
    plan.swapName = dest.name
    plan.swapAmount = destAmount
    return plan
end

---Plan moving everything from fromView into toView, stacking first, then first free slot. Stackable items move
---partially when only part fits the weight; non-stackable items move whole or not at all. Nothing is mutated.
---@return table plan, table leftovers
--- plan      = array of { kind = 'move'|'stack', name, fromSlot, toSlot, amount, fromType, toType }
--- leftovers = array of { slot, name, amount, reason }
function M.planTransferAll(fromView, toView)
    local plan, leftovers = {}, {}
    if type(fromView) ~= 'table' or type(toView) ~= 'table' or sameView(fromView, toView) then
        return plan, leftovers
    end
    local grouped = fromView.group ~= nil and rawequal(fromView.group, toView.group)

    local simItems = {}
    for slot, it in pairs(toView.items or {}) do
        simItems[slot] = { name = it.name, amount = it.amount, weight = it.weight, unique = it.unique, info = it.info }
    end
    local sim = { type = toView.type, items = simItems, slots = toView.slots, slotRange = toView.slotRange,
        maxWeight = toView.maxWeight, ownMaxWeight = toView.ownMaxWeight }
    local freed = 0

    local fromSlots = {}
    for slot in pairs(fromView.items or {}) do
        if inRange(fromView, slot) then fromSlots[#fromSlots + 1] = slot end
    end
    table.sort(fromSlots)

    for _, slot in ipairs(fromSlots) do
        local item = fromView.items[slot]
        local amount = tonumber(item.amount) or 1
        local function left(n, reason)
            leftovers[#leftovers + 1] = { slot = slot, name = item.name, amount = n, reason = reason }
        end
        local def, err = defOf(item)
        local ok, reason = false, err
        if def then ok, reason = containers().accepts(sim.type, def.size_class) end
        if not ok then
            left(amount, reason)
        else
            local unit = M.unitWeight(item)
            local room = limitOf(sim, grouped and freed or 0) - M.getWeight(sim)
            local n = amount
            if unit > 0 then n = math.min(amount, math.floor(room / unit)) end
            if not def.stackable and n < amount then n = 0 end
            if n <= 0 then
                left(amount, 'fh_too_heavy')
            else
                local fits, why, target = M.canFit(sim, item, n, { siblingFreed = grouped and freed or nil })
                if not fits then
                    left(amount, why)
                else
                    local kind = simItems[target] and 'stack' or 'move'
                    if kind == 'stack' then
                        simItems[target].amount = simItems[target].amount + n
                    else
                        simItems[target] = { name = item.name, amount = n, weight = item.weight, unique = item.unique,
                            info = item.info }
                    end
                    plan[#plan + 1] = { kind = kind, name = item.name, fromSlot = slot, toSlot = target, amount = n,
                        fromType = fromView.type, toType = toView.type }
                    if grouped then freed = freed + unit * n end
                    if n < amount then left(amount - n, 'fh_too_heavy') end
                end
            end
        end
    end
    return plan, leftovers
end

if GetCurrentResourceName then
    FhRules = M
else
    return M
end

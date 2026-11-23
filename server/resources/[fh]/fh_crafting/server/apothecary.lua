-- Apothecary (C4): usable-item handlers for tonic_vigor / tonic_steady (fh_buffs.apply, consume only on success).
-- The decision logic (M.use) is pure and takes its collaborators as `deps`, so spec/crafting_apothecary_spec.lua
-- runs it without natives. The thin FiveM wiring is at the bottom (guarded by GetCurrentResourceName).
--
-- Order: validate tonic -> removal available? -> item held? -> fh_buffs.apply -> remove.
--  * apply fails (e.g. buff id not in fh_buffs caps until @core idea-612 lands): the tonic is KEPT, player told.
--  * remove fails AFTER apply succeeded: fh_buffs has no revoke, so the buff stays; we return ok=true,
--    consumed=false, reason='remove_failed' and the caller logs it loudly. Bounded abuse: fh_buffs refreshes a
--    same-id buff instead of stacking, so a repeat only renews the same magnitude. 'no_remove' is checked BEFORE
--    apply so a missing remover never grants a free buff.
local M = {}

M.MESSAGES = {
    unknown_tonic = 'That is not a tonic.',
    no_remove     = 'You cannot drink that right now.',
    missing_item  = 'You do not have that tonic.',
    buff_failed   = 'The tonic has no effect right now. You keep it.',
    remove_failed = 'You drink the tonic, but something went wrong handling the bottle.',
    busy          = 'Slow down.',
    ok            = 'You drink the tonic.',
}

---@class FhApothecaryDeps
---@field tonicFor fun(item:string):table|nil   -> { buff_id, magnitude, duration_s }
---@field apply fun(src:integer, buff_id:string, magnitude:number, duration:number):boolean|nil, any  fh_buffs.apply
---@field remove fun(src:integer, item:string, amount:integer):boolean, string|nil  nil = removal unavailable
---@field count? fun(src:integer, item:string):integer  optional held-count check

---@return table result { ok, consumed, reason?, detail?, buff? }
function M.use(deps, src, itemName)
    local tonic = type(itemName) == 'string' and deps.tonicFor(itemName) or nil
    if not tonic or not tonic.duration_s then return { ok = false, consumed = false, reason = 'unknown_tonic' } end
    if type(deps.remove) ~= 'function' then return { ok = false, consumed = false, reason = 'no_remove' } end
    if deps.count and (tonumber(deps.count(src, itemName)) or 0) < 1 then
        return { ok = false, consumed = false, reason = 'missing_item' }
    end

    local called, applied, res = pcall(deps.apply, src, tonic.buff_id, tonic.magnitude, tonic.duration_s)
    if not called then return { ok = false, consumed = false, reason = 'buff_failed', detail = tostring(applied) } end
    if applied ~= true then
        return { ok = false, consumed = false, reason = 'buff_failed', detail = tostring(res) }
    end

    local rcalled, removed, why = pcall(deps.remove, src, itemName, 1)
    if not rcalled or removed ~= true then
        return { ok = true, consumed = false, reason = 'remove_failed', buff = res,
            detail = tostring(rcalled and why or removed) }
    end
    return { ok = true, consumed = true, buff = res }
end

---Player-facing text for a result.
function M.message(result)
    if result.ok and result.consumed then return M.MESSAGES.ok, 'success' end
    return M.MESSAGES[result.reason] or 'Something went wrong.', result.ok and 'warning' or 'error'
end

if not GetCurrentResourceName then return M end
FhCraftApothecary = M

-- ---------------------------------------------------------------- FiveM wiring
local busy = {}

local function removeFn()
    if GetResourceState('fh_core') ~= 'started' then return nil end
    local ok, fn = pcall(function() return exports.fh_core.removeItem end)
    if not ok or type(fn) ~= 'function' then return nil end
    -- NOTE: B7 removeItem refuses carried refs (fh_not_registrable) today, so this fails cleanly as remove_failed
    -- until @core accepts carried refs or C5 swaps in the inventory adapter. Documented in the C4 report.
    return function(src, item, amount) return exports.fh_core:removeItem({ type = 'backpack', id = src }, item, amount) end
end

local function deps()
    return {
        tonicFor = function(item) return FhCraftRules.tonicFor(item) end,
        apply = function(src, id, mag, dur) return exports.fh_buffs:apply(src, id, mag, dur) end,
        remove = removeFn(),
    }
end

local function notify(src, text, kind)
    pcall(function() exports['rsg-core']:Notify(src, text, kind) end)
end

local function onUse(src, item)
    if busy[src] then return notify(src, M.MESSAGES.busy, 'error') end
    busy[src] = true
    local ok, res = pcall(M.use, deps(), src, item and item.name)
    busy[src] = nil
    if not ok then print(('^1[fh_crafting] tonic use errored: %s^7'):format(tostring(res))) return end
    if res.reason and res.reason ~= 'unknown_tonic' then
        print(('^3[fh_crafting] tonic %s src=%s: %s (%s)^7'):format(tostring(item and item.name), tostring(src),
            res.reason, tostring(res.detail)))
    end
    notify(src, M.message(res))
end

local function registerUsable()
    if GetResourceState('rsg-core') ~= 'started' then return end
    for name in pairs({ tonic_vigor = true, tonic_steady = true }) do
        exports['rsg-core']:CreateUseableItem(name, onUse)
    end
end

AddEventHandler('onResourceStart', function(res)
    if res == GetCurrentResourceName() or res == 'rsg-core' then registerUsable() end
end)
AddEventHandler('playerDropped', function() busy[source] = nil end)

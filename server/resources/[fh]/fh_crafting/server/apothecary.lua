-- Apothecary (C4): usable-item handlers for tonic_vigor / tonic_steady (fh_buffs.apply, consume only on success).
-- The decision logic (M.use) is pure and takes its collaborators as `deps`, so spec/crafting_apothecary_spec.lua
-- runs it without natives. The thin FiveM wiring is at the bottom (guarded by GetCurrentResourceName).
--
-- Order (remove first, so no failure can leave a reusable tonic):
--   1. tonic known? remover present? giver present? player holds one?  (refuse, nothing touched)
--   2. remove one tonic. Fails -> 'remove_failed', NOTHING applied.
--   3. fh_buffs.apply. Fails or throws (e.g. an unknown buff id; tonic caps landed with @core idea-612) -> give the
--      tonic back through the injected giver and tell the player ('buff_failed').
--   4. Give-back fails -> 'refund_failed', logged at error level by the wiring, no buff. A lost tonic is accepted;
--      a duplicated buff is not.
local M = {}

M.MESSAGES = {
    unknown_tonic = 'That is not a tonic.',
    no_remove     = 'You cannot drink that right now.',
    missing_item  = 'You do not have that tonic.',
    buff_failed   = 'The tonic has no effect right now. It was returned to you.',
    remove_failed = 'You cannot drink that right now.',
    refund_failed = 'The tonic had no effect and was lost.',
    busy          = 'Slow down.',
    ok            = 'You drink the tonic.',
}

---@class FhApothecaryDeps
---@field tonicFor fun(item:string):table|nil   -> { buff_id, magnitude, duration_s }
---@field apply fun(src:integer, buff_id:string, magnitude:number, duration:number):boolean|nil, any  fh_buffs.apply
---@field remove fun(src:integer, item:string, amount:integer):boolean, string|nil  nil = removal unavailable
---@field give fun(src:integer, item:string, amount:integer):boolean, string|nil  refund; nil = unavailable
---@field count? fun(src:integer, item:string):integer  optional held-count check

---@return table result { ok, consumed, reason?, detail?, buff? }
function M.use(deps, src, itemName)
    local tonic = type(itemName) == 'string' and deps.tonicFor(itemName) or nil
    if not tonic or not tonic.duration_s then return { ok = false, consumed = false, reason = 'unknown_tonic' } end
    if type(deps.remove) ~= 'function' or type(deps.give) ~= 'function' then
        return { ok = false, consumed = false, reason = 'no_remove' }
    end
    if deps.count and (tonumber(deps.count(src, itemName)) or 0) < 1 then
        return { ok = false, consumed = false, reason = 'missing_item' }
    end

    local rcalled, removed, why = pcall(deps.remove, src, itemName, 1)
    if not rcalled or removed ~= true then
        return { ok = false, consumed = false, reason = 'remove_failed', detail = tostring(rcalled and why or removed) }
    end

    local called, applied, res = pcall(deps.apply, src, tonic.buff_id, tonic.magnitude, tonic.duration_s)
    if called and applied == true then return { ok = true, consumed = true, buff = res } end

    local detail = called and tostring(res) or tostring(applied)
    local gcalled, given, gwhy = pcall(deps.give, src, itemName, 1)
    if gcalled and given == true then
        return { ok = false, consumed = false, reason = 'buff_failed', detail = detail }
    end
    return { ok = false, consumed = true, reason = 'refund_failed',
        detail = detail .. '; refund: ' .. tostring(gcalled and gwhy or given) }
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
    -- until @core accepts carried refs (idea-615) or C5 swaps in the inventory adapter. Refused removal applies nothing.
    return function(src, item, amount) return exports.fh_core:removeItem({ type = 'backpack', id = src }, item, amount) end
end

local function giveFn()
    if GetResourceState('fh_core') ~= 'started' then return nil end
    local ok, fn = pcall(function() return exports.fh_core.addItem end)
    if not ok or type(fn) ~= 'function' then return nil end
    -- Same carried-ref caveat as removeItem (idea-615): fails cleanly -> refund_failed.
    return function(src, item, amount) return exports.fh_core:addItem({ type = 'backpack', id = src }, item, amount) end
end

local function deps()
    return {
        tonicFor = function(item) return FhCraftRules.tonicFor(item) end,
        apply = function(src, id, mag, dur) return exports.fh_buffs:apply(src, id, mag, dur) end,
        remove = removeFn(),
        give = giveFn(),
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
    if res.reason == 'refund_failed' then
        print(('^1[fh_crafting] ERROR tonic lost (refund failed) %s src=%s: %s^7'):format(tostring(item and item.name),
            tostring(src), tostring(res.detail)))
    elseif res.reason and res.reason ~= 'unknown_tonic' then
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

-- fh_core item registry (spec §4.1). Pure Lua: no natives, so busted can load it.
--
-- A resolved definition (what FhItems.resolve returns):
--   { name, label, weight, size_class, stackable, value_base, illicit, fast_travel }
--   weight is per unit, in grams. stackable is the inverse of rsg's `unique`.
-- Per-instance data lives in item.info (rsg-inventory persists only {name, amount, info, slot}):
--   info.condition  nullable 0-100
--   info.stars      nullable 1-3 (spec calls it "quality"; info.quality is already rsg's 0-100 freshness, so not reused)
-- Items saved before these fields existed simply lack them: read them through FhItems.condition/stars, never reject.
local M = {}

M.SIZE_CLASSES = { pocket = true, bulky = true, cargo = true }
-- cargo never fast-travels (spec §4.1 table).
M.FAST_TRAVEL = { pocket = true, bulky = true, cargo = false }

local registry = {} -- name -> validated definition added via M.define

local function cfg()
    return FhConfig or require('config')
end

local function pick(a, b, c)
    if a ~= nil then return a end
    if b ~= nil then return b end
    return c
end

local function trim(s) return (s:gsub('^%s+', ''):gsub('%s+$', '')) end

---Check a definition's fh fields. `partial` skips fields that may come from the rsg item (label, weight).
---@return boolean ok, string|nil err
function M.validate(def, partial)
    if type(def) ~= 'table' then return false, 'fh_item_not_table' end
    if def.size_class ~= nil and not M.SIZE_CLASSES[def.size_class] then return false, 'fh_bad_size_class' end
    if def.value_base ~= nil and (type(def.value_base) ~= 'number' or def.value_base < 0) then
        return false, 'fh_bad_value_base'
    end
    if def.illicit ~= nil and type(def.illicit) ~= 'boolean' then return false, 'fh_bad_illicit' end
    if def.stackable ~= nil and type(def.stackable) ~= 'boolean' then return false, 'fh_bad_stackable' end
    if not partial then
        if type(def.label) ~= 'string' or trim(def.label) == '' then return false, 'fh_bad_label' end
        if type(def.weight) ~= 'number' or def.weight < 0 then return false, 'fh_bad_weight' end
    elseif def.weight ~= nil and (type(def.weight) ~= 'number' or def.weight < 0) then
        return false, 'fh_bad_weight'
    end
    return true
end

---Register (or replace) a full fh item definition at runtime. Does not touch rsg-core; the server side pushes it.
---@return boolean ok, string|nil err
function M.define(name, def)
    if type(name) ~= 'string' or name == '' then return false, 'fh_bad_item_name' end
    local ok, err = M.validate(def)
    if not ok then return false, err end
    local copy = {}
    for k, v in pairs(def) do copy[k] = v end
    copy.name = name
    registry[name] = copy
    return true
end

---Drop runtime definitions (tests).
function M._reset() registry = {} end

---Full definition source for `name`: runtime registry, then FhConfig.Items.
function M.definition(name)
    return registry[name] or (cfg().Items or {})[name]
end

---All full definitions (config + runtime), name -> def.
function M.all()
    local out = {}
    for name, def in pairs(cfg().Items or {}) do out[name] = def end
    for name, def in pairs(registry) do out[name] = def end
    return out
end

---Resolve the effective definition of an item.
---@param name string item name
---@param sharedItem table|nil rsg item (RSGCore.Shared.Items entry or a runtime inventory item): weight, label, unique
---@return table|nil def, string|nil err
function M.resolve(name, sharedItem)
    if type(name) ~= 'string' then return nil, 'fh_bad_item_name' end
    local c = cfg()
    local full = M.definition(name)
    local over = (c.ItemOverrides or {})[name]
    if not full and not sharedItem then return nil, 'fh_unknown_item' end

    local base = full or sharedItem
    local src = over or {}
    local stackable = src.stackable
    if stackable == nil and full then stackable = full.stackable end
    if stackable == nil then stackable = not (sharedItem and sharedItem.unique) end

    local def = {
        name = name,
        label = base.label or name,
        weight = tonumber(base.weight) or 0,
        size_class = pick(src.size_class, full and full.size_class, c.DefaultSizeClass or 'pocket'),
        stackable = stackable and true or false,
        value_base = pick(src.value_base, full and full.value_base, 0),
        illicit = pick(src.illicit, full and full.illicit, false),
    }
    if not M.SIZE_CLASSES[def.size_class] then return nil, 'fh_bad_size_class' end
    def.fast_travel = M.FAST_TRAVEL[def.size_class]
    return def
end

---Instance condition (0-100) or nil when the item has none. Out-of-range values are clamped, junk reads as nil.
function M.condition(item)
    local v = item and item.info and tonumber(item.info.condition)
    if not v then return nil end
    if v < 0 then return 0 elseif v > 100 then return 100 end
    return v
end

---Instance stars (1-3 integer) or nil.
function M.stars(item)
    local v = item and item.info and tonumber(item.info.stars)
    if not v then return nil end
    v = math.floor(v + 0.5)
    if v < 1 then return 1 elseif v > 3 then return 3 end
    return v
end

---Build an RSGCore.Shared.Items entry from a full fh definition (for exports['rsg-core']:SetItems).
---If `existing` (the current rsg entry) is given, its non-fh keys are kept and only fh keys are layered on.
function M.toRsg(name, def, existing)
    local out = {}
    for k, v in pairs(existing or {}) do out[k] = v end
    out.name = name
    out.label = def.label or out.label or name
    out.weight = def.weight or out.weight or 0
    out.type = def.type or out.type or 'item'
    out.image = def.image or out.image or (name .. '.png')
    if def.stackable ~= nil then out.unique = not def.stackable elseif out.unique == nil then out.unique = false end
    if def.useable ~= nil then out.useable = def.useable elseif out.useable == nil then out.useable = false end
    if out.shouldClose == nil then out.shouldClose = true end
    out.description = def.description or out.description or ''
    out.size_class = def.size_class or out.size_class
    out.value_base = def.value_base or out.value_base
    if def.illicit ~= nil then out.illicit = def.illicit end
    return out
end

if GetCurrentResourceName then
    FhItems = M
else
    return M
end

-- fh_crafting pure rules (plan crafting-01 C1). No natives; loadable from other resources via
-- '@fh_crafting/shared/craft_rules.lua' (global FhCraftRules).
local M = {}

M.STATION_TYPES = { gunsmith = true, reload = true, apothecary = true }
M.PART_VALUE = 20                       -- condition restored per gun_parts
M.STAR_CAPS = { [1] = 60, [2] = 80, [3] = 100 }

local function posInt(n) return type(n) == 'number' and n > 0 and n == math.floor(n) end

---counts = { item = n }. Returns ok, missing = list of { item, need, have }.
function M.canCraft(counts, recipe)
    counts = counts or {}
    local missing = {}
    for _, inp in ipairs(recipe.inputs or {}) do
        local have = tonumber(counts[inp.item]) or 0
        if have < inp.amount then missing[#missing + 1] = { item = inp.item, need = inp.amount, have = have } end
    end
    return #missing == 0, missing
end

local function validateList(list, id, what, errs)
    if type(list) ~= 'table' or #list == 0 then errs[#errs + 1] = ('%s: %s empty'):format(id, what); return end
    for i, e in ipairs(list) do
        if type(e) ~= 'table' or type(e.item) ~= 'string' or e.item == '' then
            errs[#errs + 1] = ('%s: %s[%d] bad item'):format(id, what, i)
        elseif not posInt(e.amount) then
            errs[#errs + 1] = ('%s: %s[%d] %s amount must be a positive integer'):format(id, what, i, e.item)
        end
    end
end

---One recipe -> ok, errors (list of strings).
function M.validateRecipe(r)
    local errs = {}
    if type(r) ~= 'table' then return false, { 'recipe is not a table' } end
    local id = (type(r.id) == 'string' and r.id ~= '') and r.id or '?'
    if id == '?' then errs[#errs + 1] = 'recipe without id' end
    if not M.STATION_TYPES[r.station_type] then errs[#errs + 1] = ('%s: bad station_type %s'):format(id, tostring(r.station_type)) end
    validateList(r.inputs, id, 'inputs', errs)
    validateList(r.outputs, id, 'outputs', errs)
    return #errs == 0, errs
end

---List of recipes -> ok, errors. Also rejects duplicate ids.
function M.validateRecipes(list)
    local errs, seen = {}, {}
    for _, r in ipairs(list or {}) do
        local _, e = M.validateRecipe(r)
        for _, m in ipairs(e) do errs[#errs + 1] = m end
        if type(r) == 'table' and type(r.id) == 'string' then
            if seen[r.id] then errs[#errs + 1] = ('%s: duplicate id'):format(r.id) end
            seen[r.id] = true
        end
    end
    return #errs == 0, errs
end

---Max condition for a star rating: 60/80/100. nil or invalid stars = 1 star.
function M.restoreCap(stars)
    local s = tonumber(stars)
    if not s then return M.STAR_CAPS[1] end
    s = math.floor(s + 0.5)
    if s < 1 then s = 1 elseif s > 3 then s = 3 end
    return M.STAR_CAPS[s]
end

---Returns newCondition, partsUsed, reason. reason: nil on success, 'no_condition', 'at_cap', 'no_parts'.
---Each part = +20, never past the cap; uses the fewest parts that reach the cap, or all available.
function M.restore(condition, stars, partsAvailable)
    local cond = tonumber(condition)
    if not cond then return nil, 0, 'no_condition' end
    local cap = M.restoreCap(stars)
    if cond >= cap then return cond, 0, 'at_cap' end
    local parts = math.floor(tonumber(partsAvailable) or 0)
    if parts <= 0 then return cond, 0, 'no_parts' end
    local need = math.ceil((cap - cond) / M.PART_VALUE)
    local used = math.min(need, parts)
    return math.min(cap, cond + used * M.PART_VALUE), used, nil
end

local TONICS = { tonic_vigor = 1.15, tonic_steady = 1.10 }

---Tonic item -> { buff_id, magnitude, duration_s } | nil. cfg defaults to the global FhCraftingConfig.
function M.tonicFor(itemName, cfg)
    local mag = TONICS[itemName]
    if not mag then return nil end
    cfg = cfg or FhCraftingConfig
    local dur = cfg and cfg.TonicDurations and cfg.TonicDurations[itemName]
    return { buff_id = itemName, magnitude = mag, duration_s = dur }
end

if GetCurrentResourceName then FhCraftRules = M else return M end

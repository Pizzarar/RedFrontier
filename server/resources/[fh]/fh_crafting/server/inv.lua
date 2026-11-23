-- Player carried-inventory adapter (plan crafting-01 C2; C5 swaps the bodies, not the signatures).
-- Raw ops mirror fh_core exactly:  removeItem(ref, item, amount) (@core B7)  /  addItem(ref, item, amount, info).
-- A player's carried inventory = two fh_core refs: { type = 'equipped', id = src } and { type = 'backpack', id = src }.
-- removeItem is used only when fh_core is started and has the export; otherwise every take refuses with 'no_remove'
-- (and a give with 'no_add'), so nothing is half-done. Counting and slot reads use fh_core snapshot.
-- KNOWN GAP (reported to @core via lead): B7 removeItem/addItem refuse carried refs ('fh_not_registrable'), so
-- crafting refuses cleanly until @core adds a carried contract; C5 swaps to it.
FhCraftInv = {}

local flow = FhCraftFlow
local CORE = 'fh_core'

local function sections(src)
    return { { type = 'equipped', id = src }, { type = 'backpack', id = src } }
end

---Call an fh_core export. Returns called, results... ; called = false + reason when fh_core is down ('no_export'),
---the export is missing ('no_export') or it threw ('fh_core_error'). The lookup sits inside the pcall: cfx raises
---'No such export' when indexing a missing export.
local function core(fn, ...)
    if GetResourceState(CORE) ~= 'started' then return false, 'no_export' end
    local res = table.pack(pcall(function(...) return exports[CORE][fn](exports[CORE], ...) end, ...))
    if not res[1] then
        if tostring(res[2]):find('No such export', 1, true) then return false, 'no_export' end
        print(('^1[fh_crafting] fh_core.%s failed: %s^7'):format(fn, tostring(res[2])))
        return false, 'fh_core_error'
    end
    return true, table.unpack(res, 2, res.n)
end

---Mirrors exports.fh_core:removeItem (B7): exactly `amount` from one container, all-or-nothing.
---@return boolean ok
---@return string|nil reason 'no_remove' when fh_core lacks the export; else fh_core's reason
function FhCraftInv.removeItem(ref, item, amount)
    local called, res, reason = core('removeItem', ref, item, amount)
    if not called then return false, res == 'no_export' and 'no_remove' or res end
    if res == true then return true end
    return false, reason or 'fh_refused'
end

---Mirrors exports.fh_core:addItem(ref, name, amount?, info?).
---@return boolean ok
---@return string|nil reason 'no_add' when fh_core lacks the export; else fh_core's reason
function FhCraftInv.addItem(ref, item, amount, info)
    local called, res, reason = core('addItem', ref, item, amount, info)
    if not called then return false, res == 'no_export' and 'no_add' or res end
    if res == true then return true end
    return false, reason or 'fh_refused'
end

---Items of one carried section (slot -> item), {} when unavailable.
local function snapshot(ref)
    local called, items = core('snapshot', ref)
    return called and type(items) == 'table' and items or {}
end

local function countIn(items, item)
    local n = 0
    for _, it in pairs(items) do
        if type(it) == 'table' and it.name == item then n = n + (tonumber(it.amount) or 0) end
    end
    return n
end

---@return integer carried count of item (equipped + backpack)
function FhCraftInv.count(src, item)
    if type(item) ~= 'string' then return 0 end
    local n = 0
    for _, ref in ipairs(sections(src)) do n = n + countIn(snapshot(ref), item) end
    return n
end

local function applyStep(s)
    if s.op == 'remove' then return FhCraftInv.removeItem(s.ref, s.item, s.amount) end
    return FhCraftInv.addItem(s.ref, s.item, s.amount)
end

---All-or-nothing for that item across the carried sections (equipped first). A failed section take puts back what
---earlier sections gave (without item info: inputs are plain stackables).
---@return boolean ok
---@return string|nil reason 'bad_amount' | 'not_enough' | 'no_remove' | fh_core reason
---@return table|nil info transact info on a step failure (rollbackFailed lists anything not put back)
function FhCraftInv.take(src, item, amount)
    if type(item) ~= 'string' or item == '' then return false, 'bad_item' end
    local haves = {}
    for _, ref in ipairs(sections(src)) do haves[#haves + 1] = { ref = ref, have = countIn(snapshot(ref), item) } end
    local steps, why = flow.planTake(haves, item, amount)
    if not steps then return false, why end
    local ok, reason, info = flow.transact(steps, applyStep, function(s) return applyStep(flow.inverse(s)) end)
    if ok then return true end
    return false, reason, info
end

---Add to the first carried section that accepts the whole amount (equipped, then backpack).
---@param info table|nil item info (e.g. stars, condition)
---@return boolean ok
---@return string|nil reason 'no_add' | fh_core reason of the last section tried
function FhCraftInv.give(src, item, amount, info)
    local reason
    for _, ref in ipairs(sections(src)) do
        local ok, why = FhCraftInv.addItem(ref, item, amount, info)
        if ok then return true end
        reason = why
        if why == 'no_add' then break end
    end
    return false, reason or 'no_room'
end

---@return table|nil item table in that slot (copy from fh_core snapshot)
function FhCraftInv.slot(src, slot)
    if type(slot) ~= 'number' then return nil end
    for _, ref in ipairs(sections(src)) do
        local it = snapshot(ref)[slot]
        if type(it) == 'table' then return it end
    end
    return nil
end

---No fh_core contract sets item info on a carried slot yet (reported to @core via lead): refuses.
---@return boolean ok
---@return string|nil reason 'no_set_info'
function FhCraftInv.setInfo(src, slot, info)
    return false, 'no_set_info'
end

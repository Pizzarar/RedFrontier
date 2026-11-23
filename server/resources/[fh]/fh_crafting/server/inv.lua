-- Player carried-inventory adapter (C1 stub; C2 fills it, C5 swaps).
-- fh_core's addItem/removeItem refuse carried refs, so this wraps fh_inventory's rsg-compat exports for a player src
-- until @core offers a carried contract.
FhCraftInv = {}

---@return integer
function FhCraftInv.count(src, item) return 0 end

---All-or-nothing for that item.
---@return boolean ok
---@return string|nil reason 'not_enough'
function FhCraftInv.take(src, item, amount) return false, 'not_implemented' end

---@param info table|nil item info (e.g. stars, condition)
---@return boolean ok
---@return string|nil reason 'no_room' etc.
function FhCraftInv.give(src, item, amount, info) return false, 'not_implemented' end

---@return table|nil item table in that slot
function FhCraftInv.slot(src, slot) return nil end

---@return boolean ok
---@return string|nil reason
function FhCraftInv.setInfo(src, slot, info) return false, 'not_implemented' end

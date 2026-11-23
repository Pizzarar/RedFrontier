-- Saddlebag rules (spec §4.1 bulky containers; B6e). Pure: no natives, specced in spec/saddlebag_rules_spec.lua.
-- One saddlebag per character (stash id fh:saddle:<citizenid>). It may be used only while the player is on a horse
-- or within reach of one. There is no horse ownership yet, so ANY horse works.
-- TODO(horse milestone): bind the bag to the character's own horse (fh:saddle:<horse_id>) and check ownership here.
local M = {}

local function finite(n) return type(n) == 'number' and n == n and n > -math.huge and n < math.huge end
local function rules() return FhRules or require('rules') end

local function xyz(v)
    local ok, x, y, z = pcall(function() return v.x, v.y, v.z end)
    if ok and finite(x) and finite(y) and finite(z) then return x, y, z end
end

local function dist(a, b)
    local ax, ay, az = xyz(a)
    local bx, by, bz = xyz(b)
    if not ax or not bx then return nil end
    return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2 + (az - bz) ^ 2)
end

---Stash id (the fh_inventory / fh_core container id) of a character's saddlebag.
---@return string|nil
function M.stashId(citizenid)
    if type(citizenid) ~= 'string' or citizenid == '' then return nil end
    return 'fh:saddle:' .. citizenid
end

---Model (signed or unsigned integer, as GetEntityModel may return) -> unsigned 32-bit, or nil.
function M.u32(model)
    local i = math.type(model) == 'integer' and model or (finite(model) and math.tointeger(model)) or nil
    if not i or i < -2147483648 or i > 4294967295 then return nil end
    return i & 0xFFFFFFFF
end

---Allowlist set { [u32 hash] = true } from names/hashes. hashFn(name|number) -> u32 (FhSpawnRules.modelHash).
function M.horseSet(models, hashFn)
    local set = {}
    for _, m in ipairs(type(models) == 'table' and models or {}) do
        local h = hashFn(m)
        if h and h ~= 0 then set[h] = true end
    end
    return set
end

---Server-side decision. All inputs are server-read; the client only supplied the netId that located the entity.
---  citizenid    : the character
---  horse        : nil (entity lookup failed) or { exists, entityType (GetEntityType, 1 = ped), isPlayer, model (raw
---                 GetEntityModel), coords }
---  playerCoords : server-side ped coords
---  reach        : metres (FhContainers.interactDistance('saddlebag'))
---  horseSet     : M.horseSet(FhConfig.Saddlebag.HorseModels, ...)
---@return boolean ok, string|nil reason
function M.canAccess(citizenid, horse, playerCoords, reach, horses)
    if M.stashId(citizenid) == nil then return false, 'fh_no_character' end
    if type(horse) ~= 'table' or horse.exists ~= true then return false, 'fh_no_horse' end
    if horse.entityType ~= 1 or horse.isPlayer == true then return false, 'fh_not_a_horse' end
    local h = M.u32(horse.model)
    if not h or type(horses) ~= 'table' or horses[h] ~= true then return false, 'fh_not_a_horse' end
    local d, hd = dist(horse.coords, playerCoords), nil
    if d == nil then return false, 'fh_no_player_coords' end
    hd = finite(reach) and reach or nil
    if not hd or d > hd then return false, 'fh_out_of_reach' end
    return true
end

local function posInt(n)
    local i = math.type(n) == 'integer' and n or (finite(n) and math.tointeger(n)) or nil
    return i and i >= 1 and i or nil
end

---Destination slot for `item` in a view: the first stack FhRules.canStack would accept a merge into (same name,
---stackable, equal info), else the first free slot, else nil. Reuses rules.lua's stack check instead of name-only
---matching, so a transfer never targets a same-name stack whose info differs (the move would be refused/swap there).
function M.pickSlot(view, item)
    local slots = posInt(view and view.slots)
    if not slots then return nil end
    local items = view.items or {}
    local R = rules()
    for s = 1, slots do
        local it = items[s]
        if it and R.canStack(it, item) then return s end
    end
    for s = 1, slots do
        if not items[s] then return s end
    end
    return nil
end

---Container-to-container transfer between the container the player has open and their saddlebag.
---  a.dir    : 'in' (open container -> saddlebag) | 'out' (saddlebag -> open container)
---  a.slot   : slot in the SOURCE container; a.amount: nil (whole stack) or positive integer
---  a.open   : { type, id, coords, slots, items, reach } of the pane the SERVER says is open (never client-named)
---  a.bag    : { slots, items } of the saddlebag
---  plus canAccess inputs (citizenid, horse, playerCoords, reach, horses).
---Both containers are reach-checked here (bag via the horse rule, open container from its own coords + reach).
---Returns { fromSlot, toSlot, amount, dir } for ONE fh_core.move (rules veto: size class, weight, slot), else false, reason.
function M.planTransfer(a)
    local ok, why = M.canAccess(a.citizenid, a.horse, a.playerCoords, a.reach, a.horses)
    if not ok then return false, why end
    if a.dir ~= 'in' and a.dir ~= 'out' then return false, 'fh_bad_dir' end
    local open = a.open
    if type(open) ~= 'table' or type(open.type) ~= 'string' then return false, 'fh_nothing_open' end
    if open.type == 'saddlebag' then return false, 'fh_same_container' end
    local od = dist(open.coords, a.playerCoords)
    if od == nil then return false, 'fh_no_coords' end
    if not finite(open.reach) or od > open.reach then return false, 'fh_out_of_reach' end
    local slot = posInt(a.slot)
    if not slot then return false, 'fh_bad_slot' end
    local amount = a.amount
    if amount ~= nil then
        amount = posInt(amount)
        if not amount then return false, 'fh_bad_amount' end
    end
    local src, dst = a.bag, open
    if a.dir == 'in' then src, dst = open, a.bag end
    local item = type(src) == 'table' and type(src.items) == 'table' and src.items[slot]
    if type(item) ~= 'table' then return false, 'fh_no_item' end
    local toSlot = M.pickSlot(dst, item)
    if not toSlot then return false, 'fh_no_slot' end
    return { dir = a.dir, fromSlot = slot, toSlot = toSlot, amount = amount }
end

if GetCurrentResourceName then
    FhSaddlebagRules = M
else
    return M
end

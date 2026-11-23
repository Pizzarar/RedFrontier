-- Pure arg parsing/validation for fh_core admin commands (server/admin.lua). No natives, no ox_lib: specced under busted.
-- Every parser takes the raw args array (strings) and returns a table on success, or nil, '<error code>'.
local M = {}

M.MAX_GIVE = 1000

local function int(s)
    local n = tonumber(s)
    if n and n == math.floor(n) and n == n then return math.floor(n) end
end

local function finite(n) return type(n) == 'number' and n == n and n > -math.huge and n < math.huge end

---@param hasItem fun(name:string):boolean|nil registry lookup (FhItems.definition); omit to skip the check
function M.parseGive(args, hasItem)
    local target, item = int(args[1]), args[2]
    if not target or target <= 0 then return nil, 'fh_bad_target' end
    if type(item) ~= 'string' or item == '' then return nil, 'fh_bad_item' end
    local count = 1
    if args[3] ~= nil then
        count = int(args[3])
        if not count or count < 1 or count > M.MAX_GIVE then return nil, 'fh_bad_count' end
    end
    if hasItem and not hasItem(item) then return nil, 'fh_unknown_item' end
    return { target = target, item = item, count = count }
end

---`fh_heat <id> <value>` or `fh_heat <id> <faction> <value>`. The faction is only shape-checked here
---(letters, digits, underscore); fh_heat itself rejects unknown factions (fh_unknown_faction).
function M.parseHeat(args)
    local target = int(args[1])
    if not target or target <= 0 then return nil, 'fh_bad_target' end
    local faction, rawValue = nil, args[2]
    if args[3] ~= nil then
        faction, rawValue = args[2], args[3]
        if type(faction) ~= 'string' or not faction:match('^[%w_]+$') then return nil, 'fh_bad_faction' end
        if args[4] ~= nil then return nil, 'fh_bad_value' end
    end
    local value = tonumber(rawValue)
    if not finite(value) or value < 0 or value > 100 then return nil, 'fh_bad_value' end
    return { target = target, faction = faction, value = value }
end

---`fh_tp <x> <y> <z>` or `fh_tp <id>`
function M.parseTp(args)
    if args[3] ~= nil then
        local x, y, z = tonumber(args[1]), tonumber(args[2]), tonumber(args[3])
        if not (finite(x) and finite(y) and finite(z)) then return nil, 'fh_bad_coords' end
        return { coords = { x = x + 0.0, y = y + 0.0, z = z + 0.0 } }
    end
    if args[2] ~= nil then return nil, 'fh_bad_coords' end
    local target = int(args[1])
    if not target or target <= 0 then return nil, 'fh_bad_target' end
    return { target = target }
end

---`fh_dump <containerType> <id>`: carried types need a numeric id, others a string id (see fh_core server/inventory.lua)
---@param containers table FhContainers-like { isType, CARRIED }
function M.parseDump(args, containers)
    local ctype, id = args[1], args[2]
    if type(ctype) ~= 'string' or not containers.isType(ctype) then return nil, 'fh_unknown_container' end
    if id == nil or id == '' then return nil, 'fh_bad_ref' end
    if containers.CARRIED[ctype] then
        id = int(id)
        if not id or id <= 0 then return nil, 'fh_bad_ref' end
    end
    return { ref = { type = ctype, id = id } }
end

-- Default models for fh_spawn_horse / fh_spawn_ped. GUESSES, unverified in-game (ped model copied from spk_camp).
M.DEFAULT_MODELS = { horse = 'a_c_horse_morgan_bay', ped = 'g_m_m_unibanditos_01' }

---`fh_spawn_horse [model]` / `fh_spawn_ped [model]`: model is a name ([%w_], max 64) or a numeric hash
function M.parseSpawn(args, kind)
    local model = args[1] or M.DEFAULT_MODELS[kind]
    if args[2] ~= nil then return nil, 'fh_bad_model' end
    if type(model) ~= 'string' or #model > 64 or not model:match('^%-?[%w_]+$') then return nil, 'fh_bad_model' end
    local n = tonumber(model)
    if model:sub(1, 1) == '-' and not n then return nil, 'fh_bad_model' end
    return { model = model }
end

---`fh_despawn <requestId>`
function M.parseDespawn(args)
    local id = int(args[1])
    if not id or id <= 0 or args[2] ~= nil then return nil, 'fh_bad_request' end
    return { requestId = id }
end

if GetCurrentResourceName then
    FhAdminArgs = M
else
    return M
end

-- fh_core container rules (spec §4.2). Pure Lua: no natives, so busted can load it.
-- Capacity defaults live in config.lua (FhConfig.Containers); this file is the contract: which size classes each
-- container type accepts, which types are world containers (must have coords), and the reach check.
local M = {}

M.TYPES = { 'equipped', 'backpack', 'saddlebag', 'wagon', 'chest', 'drop_bag', 'fence_stash' }

-- size_class allow-list per container type (spec §4.1 table). drop_bag and fence_stash are not in the spec table:
-- they take pocket + bulky, never cargo (B4a design choice).
M.ACCEPTS = {
    equipped    = { pocket = true },
    backpack    = { pocket = true },
    saddlebag   = { pocket = true, bulky = true },
    wagon       = { pocket = true, bulky = true, cargo = true },
    chest       = { pocket = true, bulky = true, cargo = true },
    drop_bag    = { pocket = true, bulky = true },
    fence_stash = { pocket = true, bulky = true },
}

-- Carried by the player: no coords, no reach check. Every other type sits in the world and must have coords;
-- a world container without coords is refused (closes rsg-inventory's "no coords = reachable anywhere" gap).
M.CARRIED = { equipped = true, backpack = true }

local function cfg()
    return FhConfig or require('config')
end

function M.isType(t) return M.ACCEPTS[t] ~= nil end

---@return boolean ok, string|nil reason
function M.accepts(containerType, sizeClass)
    local rule = M.ACCEPTS[containerType]
    if not rule then return false, 'fh_unknown_container' end
    if not rule[sizeClass] then return false, 'fh_size_class' end
    return true
end

function M.requiresCoords(containerType)
    return M.ACCEPTS[containerType] ~= nil and not M.CARRIED[containerType]
end

---Default {slots, maxWeight} for a type, from FhConfig.Containers.
function M.defaults(containerType)
    local c = (cfg().Containers or {})[containerType]
    if not c then return nil end
    return { slots = c.slots, maxWeight = c.maxWeight }
end

---Reach distance in metres for a type (per-type override, else Access.InteractDistance).
function M.interactDistance(containerType)
    local c = cfg()
    local per = (c.Containers or {})[containerType]
    if per and per.interactDistance then return per.interactDistance end
    return (c.Access and c.Access.InteractDistance) or 3.5
end

---Accepts vector3 or {x=,y=,z=}. Returns nil when the value has no numeric x/y/z.
local function xyz(v)
    if v == nil then return nil end
    local ok, x, y, z = pcall(function() return v.x, v.y, v.z end)
    if not ok or type(x) ~= 'number' or type(y) ~= 'number' or type(z) ~= 'number' then return nil end
    return x, y, z
end

function M.validCoords(v) return xyz(v) ~= nil end

---Can a player at `playerCoords` use a container of `containerType` at `containerCoords`?
---Carried types always pass. World types fail without coords (fh_no_coords) or beyond reach (fh_out_of_reach).
---@return boolean ok, string|nil reason
function M.canReach(containerType, containerCoords, playerCoords)
    if not M.ACCEPTS[containerType] then return false, 'fh_unknown_container' end
    if M.CARRIED[containerType] then return true end
    local cx, cy, cz = xyz(containerCoords)
    if not cx then return false, 'fh_no_coords' end
    local px, py, pz = xyz(playerCoords)
    if not px then return false, 'fh_no_player_coords' end
    local dx, dy, dz = cx - px, cy - py, cz - pz
    local reach = M.interactDistance(containerType)
    if dx * dx + dy * dy + dz * dz > reach * reach then return false, 'fh_out_of_reach' end
    return true
end

if GetCurrentResourceName then
    FhContainers = M
else
    return M
end

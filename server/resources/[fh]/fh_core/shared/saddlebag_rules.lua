-- Saddlebag access rule (spec §4.1 bulky containers; B6e). Pure: no natives, specced in spec/saddlebag_rules_spec.lua.
-- One saddlebag per character (stash id fh:saddle:<citizenid>). It may be opened only while the player is on a horse
-- or within reach of one. There is no horse ownership yet, so ANY horse works.
-- TODO(horse milestone): bind the bag to the character's own horse (fh:saddle:<horse_id>) and check ownership here.
local M = {}

local function finite(n) return type(n) == 'number' and n == n and n > -math.huge and n < math.huge end

local function xyz(v)
    local ok, x, y, z = pcall(function() return v.x, v.y, v.z end)
    if ok and finite(x) and finite(y) and finite(z) then return x, y, z end
end

---Stash id (the fh_inventory / fh_core container id) of a character's saddlebag.
---@return string|nil
function M.stashId(citizenid)
    if type(citizenid) ~= 'string' or citizenid == '' then return nil end
    return 'fh:saddle:' .. citizenid
end

---Server-side decision. All inputs are server-read, never client-claimed except the netId that located the entity.
---  citizenid : the character
---  horse     : { exists = bool, isHorse = bool, coords = {x,y,z} } or nil (entity lookup failed)
---  playerCoords : server-side ped coords
---  reach     : metres (FhContainers.interactDistance('saddlebag'))
---@return boolean ok, string|nil reason
function M.canAccess(citizenid, horse, playerCoords, reach)
    if M.stashId(citizenid) == nil then return false, 'fh_no_character' end
    if type(horse) ~= 'table' or horse.exists ~= true then return false, 'fh_no_horse' end
    if horse.isHorse ~= true then return false, 'fh_not_a_horse' end
    local hx, hy, hz = xyz(horse.coords)
    local px, py, pz = xyz(playerCoords)
    if not hx or not px then return false, 'fh_no_player_coords' end
    if not finite(reach) then return false, 'fh_out_of_reach' end
    local dx, dy, dz = hx - px, hy - py, hz - pz
    if dx * dx + dy * dy + dz * dz > reach * reach then return false, 'fh_out_of_reach' end
    return true
end

if GetCurrentResourceName then
    FhSaddlebagRules = M
else
    return M
end

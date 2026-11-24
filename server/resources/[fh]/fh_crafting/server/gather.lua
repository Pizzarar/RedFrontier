-- fh_crafting herb gathering server (plan crafting-02 C9b). The server decides everything: the player's position
-- comes from GetPlayerPed + GetEntityCoords (never coords sent by the client), reach/regrowth are the pure rules
-- (shared/gather_rules.lua), the grant goes through the fh_core carried addItem on a backpack ref, and the shared
-- per-patch cooldown is stamped only after a successful add. One pick in flight per src (busy).
FhGather = {}

local busy = {}       -- src -> true while a pick runs (one pick in flight per src)
local lastPicked = {} -- patchId -> timestamp (shared per-patch cooldown, server memory, cleared on restart)

---Pure orchestration; deps inject every side effect so the spec can test it.
--- deps:
---   patch(patchId) -> patch | nil
---   playerCoords(src) -> coords | nil          server ped coords (GetPlayerPed + GetEntityCoords)
---   canPick(patch, coords, now, lastPicked) -> ok, reason
---   rollYield(patch) -> amount
---   addItem(ref, herb, amount) -> ok, reason   ref = { type = 'backpack', id = src }
---   stamp(patchId, now)                         record the cooldown (reached only on a successful add)
---   now() -> seconds
---   lastPicked(patchId) -> timestamp | nil
---@return boolean ok
---@return string|nil reason 'fh_unknown_patch' | 'fh_too_far' | 'fh_regrowing' | addItem reason
---@return table|nil info { herb, amount }
function FhGather.pick(deps, src, patchId)
    local patch = deps.patch(patchId)
    if not patch then return false, 'fh_unknown_patch' end
    local coords = deps.playerCoords(src)
    local ok, reason = deps.canPick(patch, coords, deps.now(), deps.lastPicked(patchId))
    if not ok then return false, reason end
    local amount = deps.rollYield(patch)
    local okAdd, why = deps.addItem({ type = 'backpack', id = src }, patch.herb, amount)
    if not okAdd then return false, why or 'fh_refused' end
    deps.stamp(patchId, deps.now())
    return true, nil, { herb = patch.herb, amount = amount }
end

-- The fh_crafting globals (FhGatherRules, FhCraftingConfig, FhCraftInv) are referenced lazily inside these builders
-- (not at load time) so the pure FhGather.pick stays loadable in a spec.
local function patchById(patchId)
    for _, p in ipairs(FhCraftingConfig.herbPatches or {}) do
        if p.id == patchId then return p end
    end
    return nil
end

local function playerCoords(src)
    local ped = GetPlayerPed(src)
    if ped == 0 then return nil end
    return GetEntityCoords(ped)
end

local function deps()
    return {
        patch = patchById,
        playerCoords = playerCoords,
        canPick = FhGatherRules.canPick,
        rollYield = function(p) return FhGatherRules.rollYield(p) end,
        addItem = function(ref, herb, amount) return FhCraftInv.addItem(ref, herb, amount) end,
        stamp = function(patchId, now) lastPicked[patchId] = now end,
        now = function() return os.time() end,
        lastPicked = function(patchId) return lastPicked[patchId] end,
    }
end

---@return boolean ok
---@return string|nil reason no_player | busy | error | FhGather.pick reasons
---@return table|nil info
function FhGather.gather(src, patchId)
    if type(src) ~= 'number' or not (src > 0) then return false, 'no_player' end -- NaN fails src > 0
    if busy[src] then return false, 'busy' end
    busy[src] = true
    local called, ok, reason, info = pcall(FhGather.pick, deps(), src, patchId)
    busy[src] = nil
    if not called then
        print(('^1[fh_crafting] gather error src=%s patch=%s: %s^7'):format(tostring(src), tostring(patchId), tostring(ok)))
        return false, 'error'
    end
    return ok, reason, info
end

if GetCurrentResourceName then
    local function herbLabel(herb)
        local name = tostring(herb):gsub('^herb_', ''):gsub('_', ' ')
        return (name:gsub('(%a)([%w]*)', function(a, b) return a:upper() .. b end))
    end

    local MESSAGES = {
        busy = 'You are already picking.',
        fh_regrowing = 'That patch is still regrowing.',
        fh_too_far = 'You are too far from that patch.',
        fh_unknown_patch = 'No herb patch there.',
    }
    local function tell(src, msg)
        TriggerClientEvent('chat:addMessage', src, { args = { 'Crafting', msg } })
    end

    RegisterNetEvent('fh:crafting:gather', function(patchId)
        local src = source
        local ok, reason, info = FhGather.gather(src, patchId)
        if ok then
            tell(src, ('Picked %d %s.'):format(info.amount, herbLabel(info.herb)))
        else
            tell(src, MESSAGES[reason] or ('Gathering failed: ' .. tostring(reason)))
        end
    end)

    AddEventHandler('playerDropped', function() busy[source] = nil end)
end

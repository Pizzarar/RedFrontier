-- fh_crafting pure craft transaction (plan crafting-01 C2). No natives: every station and inventory call is
-- injected, so the all-or-nothing order and the rollback are specced under lupa (spec/crafting_flow_spec.lua).
-- Global FhCraftFlow in-game; `return M` under specs.
--
-- Craft order: station check -> canCraft on live counts -> remove every input -> add every output.
-- Any failed step undoes every step already applied, newest first (remove <-> add), so a craft either fully
-- happens or leaves the inventory as it was. Undo failures are returned (never swallowed) for loud logging.
local M = {}

local function posInt(n) return type(n) == 'number' and n > 0 and n == math.floor(n) end

local function finite(n) return type(n) == 'number' and n == n and n > -math.huge and n < math.huge end

local function copyStep(s)
    local c = {}
    for k, v in pairs(s) do c[k] = v end
    return c
end

---Apply steps in order, all-or-nothing. On the first failure (false/nil result or a thrown error) undo every applied
---step in reverse order. apply(step) / undo(step) -> ok, reason; undo receives the step as it was applied.
---@return boolean ok
---@return string|nil reason first failure reason ('step_error' when apply threw)
---@return table info ok: { applied = n }; failure: { index = i, step = failedStep, rollbackFailed = { { step, reason } } }
function M.transact(steps, apply, undo)
    local done = {}
    for i, step in ipairs(steps) do
        local called, ok, reason = pcall(apply, step)
        if not called then ok, reason = false, 'step_error' end
        if ok ~= true then
            local failedUndo = {}
            for j = #done, 1, -1 do
                local s = done[j]
                local uCalled, uOk, uReason = pcall(undo, s)
                if not uCalled then uOk, uReason = false, 'undo_error' end
                if uOk ~= true then failedUndo[#failedUndo + 1] = { step = s, reason = uReason or 'undo_failed' } end
            end
            return false, reason or 'step_failed', { index = i, step = step, rollbackFailed = failedUndo }
        end
        done[#done + 1] = step
    end
    return true, nil, { applied = #done }
end

---Recipe -> steps: every input as { op = 'remove' }, then every output as { op = 'add' } (copies, never the recipe's).
function M.craftSteps(recipe)
    local steps = {}
    for _, e in ipairs(recipe.inputs or {}) do steps[#steps + 1] = { op = 'remove', item = e.item, amount = e.amount } end
    for _, e in ipairs(recipe.outputs or {}) do steps[#steps + 1] = { op = 'add', item = e.item, amount = e.amount } end
    return steps
end

---Total needed per input item (a recipe listing one item twice needs the sum).
function M.inputTotals(recipe)
    local totals = {}
    for _, e in ipairs(recipe.inputs or {}) do totals[e.item] = (totals[e.item] or 0) + e.amount end
    return totals
end

---Craft one recipe for src. deps (all required):
---  near(src, stationType) -> ok, reason        station adapter (FhCraftStations.isNearStation)
---  count(src, item) -> integer                 carried count (FhCraftInv.count)
---  take(src, item, amount) -> ok, reason       all-or-nothing per item (FhCraftInv.take)
---  give(src, item, amount) -> ok, reason       (FhCraftInv.give)
---  canCraft(counts, recipe) -> ok, missing     FhCraftRules.canCraft
---@return boolean ok
---@return string|nil reason unknown_recipe | <near reason, default no_station> | missing_inputs | <take/give reason>
---@return table|nil info ok: { recipe, outputs }; missing_inputs: { missing }; step failure: transact info
function M.craft(src, recipe, deps)
    if type(recipe) ~= 'table' or type(recipe.inputs) ~= 'table' or type(recipe.outputs) ~= 'table' then
        return false, 'unknown_recipe'
    end
    local near, why = deps.near(src, recipe.station_type)
    if near ~= true then return false, why or 'no_station' end

    local totals, counts = M.inputTotals(recipe), {}
    for item in pairs(totals) do counts[item] = tonumber(deps.count(src, item)) or 0 end
    -- canCraft checks per input line; an item listed on two lines is caught by the totals check after it.
    local ok, missing = deps.canCraft(counts, recipe)
    if ok then
        missing = {}
        for item, need in pairs(totals) do
            if counts[item] < need then missing[#missing + 1] = { item = item, need = need, have = counts[item] } end
        end
        ok = #missing == 0
    end
    if not ok then return false, 'missing_inputs', { missing = missing } end

    local function apply(s)
        if s.op == 'remove' then return deps.take(src, s.item, s.amount) end
        return deps.give(src, s.item, s.amount)
    end
    local function undo(s)
        if s.op == 'remove' then return deps.give(src, s.item, s.amount) end
        return deps.take(src, s.item, s.amount)
    end
    local done, reason, info = M.transact(M.craftSteps(recipe), apply, undo)
    if not done then return false, reason, info end
    return true, nil, { recipe = recipe.id, outputs = recipe.outputs }
end

---Split a take of `amount` over carried sections in order. haves = array of { ref = <fh_core ref>, have = n }.
---@return table|nil steps array of { op = 'remove', ref, item, amount }; nil + 'bad_amount' | 'not_enough'
---@return string|nil reason
function M.planTake(haves, item, amount)
    if not posInt(amount) then return nil, 'bad_amount' end
    local steps, left = {}, amount
    for _, h in ipairs(haves or {}) do
        if left == 0 then break end
        local have = math.floor(tonumber(h.have) or 0)
        if have > 0 then
            local n = math.min(have, left)
            steps[#steps + 1] = { op = 'remove', ref = h.ref, item = item, amount = n }
            left = left - n
        end
    end
    if left > 0 then return nil, 'not_enough' end
    return steps
end

---The step that reverses `step` (remove <-> add), same ref/item/amount.
function M.inverse(step)
    local c = copyStep(step)
    c.op = step.op == 'remove' and 'add' or 'remove'
    return c
end

local function validCoords(c)
    local ok, x, y, z = pcall(function() return c.x, c.y, c.z end)
    return ok and finite(x) and finite(y) and finite(z)
end

---Nearest dev station within maxDist of coords. devStations = { [stationType] = {x,y,z} }; stationType nil = any.
---@return string|nil stationType
---@return number|nil dist
function M.nearestDev(devStations, coords, maxDist, stationType)
    if type(devStations) ~= 'table' or not validCoords(coords) or not finite(maxDist) or maxDist < 0 then return nil end
    local bestType, bestDist
    for t, c in pairs(devStations) do
        if (stationType == nil or t == stationType) and validCoords(c) then
            local dx, dy, dz = coords.x - c.x, coords.y - c.y, coords.z - c.z
            local d = math.sqrt(dx * dx + dy * dy + dz * dz)
            if d <= maxDist and (not bestDist or d < bestDist) then bestType, bestDist = t, d end
        end
    end
    return bestType, bestDist
end

if GetCurrentResourceName then FhCraftFlow = M else return M end

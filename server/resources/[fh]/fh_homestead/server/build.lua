-- fh_homestead H2: build flow (server). `/fh_build <slot>` -> FhHomesteadBuild.build(src, slotId).
-- Contract (core B7): fh_core.removeItem(ref, item, n) all-or-nothing (fh_not_enough); fh_economy.charge(src, amount,
-- reason, region) debit (fh_insufficient_funds, ledger_failed, removemoney_refused, no_player, player_changed,
-- fh_charge_busy); credits ONLY through fh_core.addItem (items) and fh_economy.pay (money). No other debit path.
--
-- Order (tier A: no dupes, no free builds, no lost items):
--   0. ready gate (fh_not_ready), character, own plot, standing inside it, H1 rules (owner-only, next tier, prereqs)
--   1. take the materials from the plot's main chest (fh:chest:<plot>:1), one removeItem per item, sorted by name
--   2. charge the money (skipped when the tier costs $0)
--   3. FhHomesteadSlots.setTier (writes only while fh_plots still says we own it)
--   Any failure after step 1 refunds exactly what was taken: items back into the same chest (addItem), money through
--   fh_economy.pay to the same character. Each refund runs at most once and is checked; a failed refund is logged as
--   `ITEM LOST` / `MONEY LOST` with citizenid, item/amount and the reason, and the call returns fh_build_refund_failed.
-- Lock: one build per plot AND per character at a time (busyPlot/busyCid), held across every await and released on
--   every path, including a Lua error (pcall; the error path refunds what the flow state says was taken, unless our
--   tier is already in the slot cache: setTier saved it and then threw in an event handler, so the build stands).
-- Ownership: gen[plotId] moves on every unclaim; after each await the flow checks the same character still owns the
--   same plot (no unclaim in between, also not unclaim + re-claim). If not: no build, full refund (items go back to the
--   chest they came from; it stays registered after an unclaim, see README Open: spill-on-unclaim gap).
-- Also here: build materials registered with fh_core (from this resource only), extra chests (chest_2/chest_3 slots)
-- registered as fh_core `chest` containers when built and on load, and the client prop feed (client-local props).
local cfg = FhHomesteadConfig
local rules = FhBuildRules
local plotRules = FhPlotRules

FhHomesteadBuild = {}
local B = FhHomesteadBuild

local busyPlot, busyCid = {}, {} -- in-flight build locks
local gen = {}                   -- plotId -> unclaim counter

local REASON = 'homestead build'
local REFUND_REASON = 'homestead build refund'

local function log(level, msg) print(('%s[fh_homestead] %s^7'):format(level == 'error' and '^1' or '^3', msg)) end

local function slots() return FhHomesteadSlots end
local function claims() return FhHomesteadClaims end
local function genOf(plotId) return gen[plotId] or 0 end

local function citizenidOf(src)
    if type(src) ~= 'number' or src <= 0 then return nil end
    local ok, p = pcall(function() return exports['rsg-core']:GetCoreObject().Functions.GetPlayer(src) end)
    return ok and p and p.PlayerData and p.PlayerData.citizenid or nil
end

local function chestRef(plotId, n) return { type = 'chest', id = plotRules.chestStashId(plotId, n or 1) } end

-- Same character, same plot, no unclaim since generation g was read.
local function stillOwns(cid, plotId, g)
    local c = claims()
    return genOf(plotId) == g and c ~= nil and c.plotOf(cid) == plotId and c.ownerOf(plotId) == cid
end

local function vec(c)
    if vector3 then return vector3(c.x, c.y, c.z) end
    return { x = c.x, y = c.y, z = c.z }
end

-- ---------------------------------------------------------------- refunds (each checked, each at most once)

---Put every taken item back into the chest it came from. st.taken is cleared first so nothing is refunded twice.
local function refundItems(st, why)
    local taken = st.taken
    st.taken = {}
    local all = true
    for i = #taken, 1, -1 do
        local it = taken[i]
        local ok, res, rwhy = pcall(function() return exports.fh_core:addItem(chestRef(st.plotId, 1), it.item, it.amount) end)
        if not ok or res ~= true then
            all = false
            log('error', ('ITEM LOST: build refund failed: citizenid=%s plot=%s slot=%s item=%s amount=%d stash=%s refund_error=%s build_error=%s')
                :format(st.cid, st.plotId, st.slotId, it.item, it.amount, plotRules.chestStashId(st.plotId, 1),
                    tostring(ok and rwhy or res), tostring(why)))
        end
    end
    return all
end

---Pay back a successful charge to the SAME character. If that character is no longer loaded on src, pay() would credit
---someone else (or nobody): log it instead. st.charged is cleared first so it is never paid twice.
local function refundMoney(st, why)
    local amount = st.charged
    st.charged = 0
    if amount <= 0 then return true end
    local now = citizenidOf(st.src)
    if now ~= st.cid then
        log('error', ('MONEY LOST: build refund of $%d to citizenid=%s not paid: character not loaded on src %s (now %s); plot=%s slot=%s build_error=%s')
            :format(amount, st.cid, tostring(st.src), tostring(now), st.plotId, st.slotId, tostring(why)))
        return false
    end
    local ok, paid, perr = pcall(function() return exports.fh_economy:pay(st.src, amount, REFUND_REASON, st.region) end)
    if not ok or paid ~= true then
        log('error', ('MONEY LOST: build refund of $%d to citizenid=%s failed: %s; plot=%s slot=%s build_error=%s')
            :format(amount, st.cid, tostring(ok and perr or paid), st.plotId, st.slotId, tostring(why)))
        return false
    end
    return true
end

---Undo everything taken so far and fail with `why` (or fh_build_refund_failed when a refund did not go through).
local function abort(st, why, detail)
    local itemsBack = refundItems(st, why)
    local moneyBack = refundMoney(st, why)
    if not (itemsBack and moneyBack) then return false, 'fh_build_refund_failed' end
    return false, why, detail
end

-- ---------------------------------------------------------------- extra chests

---Register chest_<n> of a plot as an fh_core `chest` at the slot's prop position. No-op for non-chest slots.
local function registerSlotChest(plotId, slotId)
    local plot = cfg.plots[plotId]
    local slot = plot and plot.slots and plot.slots[slotId]
    local n = rules.chestNumber(slotId, slot)
    if not n then return true end
    local place = rules.slotPlacement(plot, slot, cfg.verifiedProps)
    if not place then
        log('error', ('chest %s/%s has no usable prop position; not registered'):format(plotId, slotId))
        return false, 'fh_no_coords'
    end
    local ok, res, why = pcall(function()
        return exports.fh_core:registerContainer(chestRef(plotId, n), { coords = vec(place.coords), label = 'Homestead chest ' .. n })
    end)
    if not ok or not res then
        log('error', ('chest register failed for %s: %s'):format(plotRules.chestStashId(plotId, n), tostring(ok and why or res)))
        return false, 'fh_chest_register_failed'
    end
    return true
end

---Register the built extra chests of every claimed plot (boot and fh_core restart).
local function registerAllChests()
    local S, C = slots(), claims()
    if not (S and S.isReady()) then return end
    for plotId, plot in pairs(cfg.plots) do
        if C.ownerOf(plotId) then
            local tiers = S.getTiers(plotId)
            for slotId in pairs(plot.slots or {}) do
                if (tiers[slotId] or 0) >= 1 then registerSlotChest(plotId, slotId) end
            end
        end
    end
end

-- ---------------------------------------------------------------- build

local function buildLocked(st, plot, slotId)
    local S, C = slots(), claims()
    local plotId, cid = st.plotId, st.cid
    local g = genOf(plotId)
    local tiers, twhy = S.getTiers(plotId)
    if twhy then return false, twhy end
    local ok, why = rules.canBuild(plot, slotId, tiers, cid, C.ownerOf(plotId))
    if not ok then return false, why end
    local slot = plot.slots[slotId]
    local tier = rules.nextTier(slot, tiers[slotId] or 0)
    local cost, cwhy = rules.costList(rules.costFor(slot, tier))
    if not cost then
        log('error', ('bad cost in config for %s tier %s: %s'):format(slotId, tostring(tier), tostring(cwhy)))
        return false, cwhy
    end

    -- 1. materials from the plot chest (all-or-nothing per item; earlier items are refunded on a later shortfall)
    for _, it in ipairs(cost.items) do
        if not stillOwns(cid, plotId, g) then return abort(st, 'fh_no_plot') end
        local okc, res, rwhy = pcall(function() return exports.fh_core:removeItem(chestRef(plotId, 1), it.item, it.amount) end)
        if not okc then
            log('warn', 'fh_core:removeItem failed: ' .. tostring(res))
            return abort(st, 'fh_removeitem_unavailable')
        end
        if res ~= true then return abort(st, type(rwhy) == 'string' and rwhy or 'fh_removeitem_failed', it.item) end
        st.taken[#st.taken + 1] = it
    end
    if not stillOwns(cid, plotId, g) then return abort(st, 'fh_no_plot') end

    -- 2. money. Checked right before the call (no await in between): charge debits whoever is loaded on src.
    if cost.money > 0 then
        if citizenidOf(st.src) ~= cid then return abort(st, 'player_changed') end
        local okc, paid, perr = pcall(function() return exports.fh_economy:charge(st.src, cost.money, REASON, st.region) end)
        if not okc then
            log('warn', 'fh_economy:charge failed: ' .. tostring(paid))
            return abort(st, 'fh_charge_unavailable')
        end
        if paid ~= true then return abort(st, type(perr) == 'string' and perr or 'fh_charge_failed') end
        st.charged = cost.money
        if not stillOwns(cid, plotId, g) then return abort(st, 'fh_no_plot') end
    end

    -- 3. the tier itself
    st.tier, st.cost = tier, cost
    local set, swhy = S.setTier(plotId, slotId, tier)
    if not set then
        log('warn', ('setTier %s/%s -> %d failed after the cost was taken (%s); refunding citizenid=%s $%d + %d item stacks')
            :format(plotId, slotId, tier, tostring(swhy), cid, st.charged, #st.taken))
        return abort(st, swhy or 'fh_slot_save_failed')
    end
    st.done = true
    registerSlotChest(plotId, slotId) -- a failure is logged; the chest registers again on the next boot / fh_core restart
    return true, tier, cost
end

---Build the next tier of `slotId` on the caller's own plot. Returns true, tier, cost | false, reason, detail.
function B.build(src, slotId)
    local S = slots()
    if not (S and S.isReady()) then return false, 'fh_not_ready' end
    if type(slotId) ~= 'string' or slotId == '' then return false, 'fh_unknown_slot' end
    local cid = citizenidOf(src)
    if not cid then return false, 'fh_no_character' end
    local plotId = S.plotOf(cid)
    local plot = plotId and cfg.plots[plotId]
    if not plot then return false, 'fh_no_plot' end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false, 'fh_no_player' end
    if not plotRules.inRadius(plot, GetEntityCoords(ped)) then return false, 'fh_not_in_plot' end
    if busyPlot[plotId] or busyCid[cid] then return false, 'fh_build_busy' end
    busyPlot[plotId], busyCid[cid] = true, true
    local st = { src = src, cid = cid, plotId = plotId, slotId = slotId, region = plot.region, taken = {}, charged = 0, done = false }
    local r = table.pack(pcall(buildLocked, st, plot, slotId))
    local out
    if r[1] then
        out = table.pack(table.unpack(r, 2, r.n))
    else
        -- The error path is guarded too: an error in here must not skip the lock release below.
        local okE, o = pcall(function()
            log('error', ('build %s/%s for %s errored: %s'):format(plotId, slotId, cid, tostring(r[2])))
            -- setTier writes the DB and the cache, THEN raises events (slot_changed -> prop push, station_built); an error
            -- in there throws out of setTier after the tier was saved. Only build.lua calls setTier, under this plot
            -- lock, so our tier in the cache means our write landed: it is built, and a refund would be a free build.
            if not st.done and st.tier and S.getTiers(plotId)[slotId] == st.tier then
                st.done = true
                log('error', ('build %s/%s for %s: tier %d was saved before the error; kept, nothing refunded')
                    :format(plotId, slotId, cid, st.tier))
            end
            if st.done then return table.pack(true, st.tier, st.cost) end
            return table.pack(abort(st, 'fh_build_failed'))
        end)
        if okE then
            out = o
        elseif st.done then
            out = table.pack(true, st.tier, st.cost)
        else
            -- the refund itself errored part-way; st.taken/st.charged were cleared before each refund, so nothing is
            -- refunded twice, but we cannot tell what landed: report it as a failed refund
            out = table.pack(false, 'fh_build_refund_failed')
        end
    end
    busyPlot[plotId], busyCid[cid] = nil, nil
    return table.unpack(out, 1, out.n)
end

---Status lines for `/fh_build` with no argument: every slot, its tier, and the next tier's cost.
function B.status(src)
    local S = slots()
    if not (S and S.isReady()) then return nil, 'fh_not_ready' end
    local cid = citizenidOf(src)
    local plotId = cid and S.plotOf(cid)
    local plot = plotId and cfg.plots[plotId]
    if not plot then return nil, 'fh_no_plot' end
    local tiers = S.getTiers(plotId)
    local ids = {}
    for id in pairs(plot.slots or {}) do ids[#ids + 1] = id end
    table.sort(ids)
    local lines = {}
    for _, id in ipairs(ids) do
        local slot, tier = plot.slots[id], tiers[id] or 0
        local nxt = rules.nextTier(slot, tier)
        local cost = nxt and rules.costList(rules.costFor(slot, nxt))
        local parts = {}
        for _, it in ipairs(cost and cost.items or {}) do parts[#parts + 1] = it.amount .. ' ' .. it.item end
        lines[#lines + 1] = ('%s %d/%d%s'):format(id, tier, slot.maxTier or 0,
            cost and (' next: $' .. cost.money .. (#parts > 0 and (', ' .. table.concat(parts, ', ')) or '')) or ' (max)')
    end
    return lines, plotId
end

-- ---------------------------------------------------------------- props feed (client-local, non-networked)

local function propsOf(plotId)
    local S = slots()
    if not (S and S.isReady()) then return {} end
    return rules.slotProps(cfg.plots[plotId], S.getTiers(plotId), cfg.verifiedProps)
end

local function pushPlot(plotId)
    if cfg.plots[plotId] then TriggerClientEvent('fh:homestead:slot_props', -1, plotId, propsOf(plotId)) end
end

-- Join: the client asks once (retries while this returns nil = not loaded yet). { [plotId] = props } of claimed plots.
lib.callback.register('fh:homestead:slot_props', function()
    local S, C = slots(), claims()
    if not (S and S.isReady()) then return nil end
    local out = {}
    for plotId in pairs(cfg.plots) do
        if C.ownerOf(plotId) then out[plotId] = propsOf(plotId) end
    end
    return out
end)

AddEventHandler('fh:homestead:slot_changed', function(plotId) pushPlot(plotId) end)
AddEventHandler('fh:homestead:claimed', function(data)
    if type(data) == 'table' then pushPlot(data.plot_id) end
end)
AddEventHandler('fh:homestead:unclaimed', function(data)
    if type(data) ~= 'table' or type(data.plot_id) ~= 'string' then return end
    gen[data.plot_id] = genOf(data.plot_id) + 1 -- any build suspended mid-await on this plot aborts and refunds
    TriggerClientEvent('fh:homestead:slot_props', -1, data.plot_id, {})
end)

-- ---------------------------------------------------------------- startup: items + extra chests

local function registerItems()
    local ok, res, err, bad = pcall(function() return exports.fh_core:registerItems(cfg.buildItems or {}) end)
    if not ok or not res then
        log('error', ('build materials not registered: %s (%s)'):format(tostring(ok and err or res), tostring(bad)))
        return false
    end
    return true
end

CreateThread(function()
    while GetResourceState('fh_core') ~= 'started' do Wait(500) end
    registerItems()
    local S = slots()
    while not (S and S.isReady()) do Wait(1000) end
    registerAllChests()
end)

-- fh_core restarted: its item and container registries are gone; register ours again (claim chests: server/main.lua).
AddEventHandler('onResourceStart', function(res)
    if res ~= 'fh_core' then return end
    registerItems()
    registerAllChests()
end)

-- ---------------------------------------------------------------- commands

local function reply(src, msg)
    if src == 0 then print('[fh_homestead] ' .. msg) else TriggerClientEvent('chat:addMessage', src, { args = { 'fh', msg } }) end
end

local HINT = {
    fh_not_enough = 'not enough %s in your plot chest (materials are taken from the chest)',
    fh_charge_busy = 'another payment is in progress, try again in a moment',
    fh_build_busy = 'a build is already in progress, try again in a moment',
    fh_insufficient_funds = 'not enough cash',
    fh_build_refund_failed = 'build failed and a refund did not go through; tell an admin (server log: LOST)',
}

local function describe(why, detail)
    local h = HINT[why]
    return h and (why .. ' (' .. h:format(tostring(detail)) .. ')') or tostring(why)
end

lib.addCommand('fh_build', { help = 'Build the next tier of a homestead slot (no argument: list slots and costs)',
    params = { { name = 'slot', type = 'string', help = 'cabin, fence, station_1..3, trophy_wall, chest_2, chest_3', optional = true } } },
    function(src, args)
        local slotId = args and args.slot
        if not slotId then
            local lines, plotOrWhy = B.status(src)
            if not lines then return reply(src, 'fh_build: ' .. tostring(plotOrWhy)) end
            reply(src, 'fh_build: plot ' .. plotOrWhy .. ': ' .. table.concat(lines, '; '))
            return
        end
        local ok, res, detail = B.build(src, slotId)
        if not ok then return reply(src, 'fh_build: ' .. describe(res, detail)) end
        local parts = {}
        for _, it in ipairs(detail and detail.items or {}) do parts[#parts + 1] = it.amount .. ' ' .. it.item end
        reply(src, ('fh_build: built %s tier %d ($%d%s)'):format(slotId, res, detail and detail.money or 0,
            #parts > 0 and (', ' .. table.concat(parts, ', ')) or ''))
    end)

-- Trophy wall commands (H4 exports; owner-only, items via the plot chest).
lib.addCommand('fh_trophy', { help = 'fh_trophy place <item> | fh_trophy remove <trophy_id>',
    params = { { name = 'action', type = 'string' }, { name = 'id', type = 'string' } } },
    function(src, args)
        local action, id = args and args.action, args and args.id
        local ok, res
        if action == 'place' then ok, res = exports[GetCurrentResourceName()]:placeTrophy(src, id)
        elseif action == 'remove' then ok, res = exports[GetCurrentResourceName()]:unplaceTrophy(src, id)
        else return reply(src, 'fh_trophy: use place <item> or remove <trophy_id>') end
        reply(src, ok and ('fh_trophy: ' .. action .. ' ok' .. (type(res) == 'string' and (' ' .. res) or '')) or ('fh_trophy: ' .. tostring(res)))
    end)

-- Read-only: is a built station of this type within reach on your own plot (what @crafting asks via isNearStation).
lib.addCommand('fh_station', { help = 'fh_station <workbench|campfire|tanning_rack>: is that station within reach on your plot',
    params = { { name = 'type', type = 'string' } } },
    function(src, args)
        local t = args and args.type
        reply(src, ('fh_station: %s near=%s'):format(tostring(t), tostring(exports[GetCurrentResourceName()]:isNearStation(src, t) == true)))
    end)

-- Read-only: your comfort value (what @survival reads).
lib.addCommand('fh_comfort', { help = 'Show your homestead comfort' }, function(src)
    local cid = citizenidOf(src)
    if not cid then return reply(src, 'fh_comfort: fh_no_character') end
    reply(src, 'fh_comfort: ' .. tostring(exports[GetCurrentResourceName()]:getComfort(cid)))
end)

-- Treasure lead dig (progression-02 G2). `fh:fence:dig` spends one held fh_treasure_lead at its spot for one loot
-- roll. The dig core (M.new) is pure Lua: every FiveM / export call comes in through `deps`, so the spec drives this
-- real file with yielding fakes (spec/fence_leads_spec.lua). The FXServer glue at the bottom only runs in game.
--
-- Invariants (Tier A):
--  1. One dig per citizenid at a time (lock taken before the first yield, released on every path; a second dig gets
--     'dig_busy'). A lock whose dig never resumes is reclaimed after cfg.leads.lockStaleSeconds.
--  2. The client sends nothing but the request: position = server-side ped coords, lead = the player's own carried
--     inventory (equipped, then backpack), target = the spot the lead's item info names. Item info holds only an
--     opaque spot id ({ lead = '<id>' }, written by the fence at purchase); the id is resolved here against the
--     server-only spot table (FhFenceLeadSpots, server/config_leads.lua). A pre-G2b lead whose info still carries a
--     server-written { target, hint } is accepted as that target (read server-side only), so it digs exactly once.
--  3. Order: pick lead (distance) -> region + loot roll -> canFit the loot -> removeItem(lead, 1) -> pay out. Every
--     refusal before removeItem leaves the lead and pays nothing. removeItem is fh_core's all-or-nothing count check,
--     so N leads can be spent at most N times: one payout per removed lead, even if a stale lock were reclaimed.
--  4. After the lead is removed it is never given back (that would allow a second dig). A failed pay / addItem is
--     logged as a WARNING with citizenid, target, region and the exact amounts owed, for an admin to pay by hand.
--  5. The character is re-checked (citizenOf(src) == the dig's citizenid, no yield in between) right before every
--     side effect (removeItem, pay, addItem) and right after removeItem. A switch before removal refuses the dig
--     ('player_changed', nothing taken); a switch after it pays nothing more to anyone and logs a WARNING with both
--     citizenids, the target and what is owed.
--  6. The client never gets an exact target: lead views carry the grid-rounded offset area, keyed by that area. No
--     client-visible data (shared config, item info, menu stock) holds a spot's coords or hint.
local M = {}

local CARRIED = { 'equipped', 'backpack' } -- lead search order

---deps (all may yield unless noted): citizenOf(src) (no yield), pedCoords(src) -> {x,y,z}|nil, snapshot(ref),
---canFit(ref, item, qty), removeItem(ref, item, qty) (all-or-nothing), addItem(ref, item, qty, info),
---pay(src, amount, reason, region_id), knownRegion(id) -> bool, rng(m, n), now() -> seconds, log(msg),
---label(item) -> string|nil. Failures are returned (false/nil, reason), not thrown; a throw is still caught.
---spots: the server-only spot table, id -> { coords = {x,y,z}, hint } (FhFenceLeadSpots).
function M.new(cfg, logic, deps, spots)
    local L = cfg.leads
    local function log(fmt, ...) deps.log(fmt:format(...)) end
    local held, last = {}, {} -- citizenid -> lock token; citizenid -> last attempt time
    local D = {}

    local function acquire(cid, src)
        local cur = held[cid]
        if cur then
            if deps.now() - cur.at < (L.lockStaleSeconds or 120) then return nil end
            log('WARNING reclaimed a stale dig lock: citizenid=%s src=%s', tostring(cur.cid), tostring(cur.src))
        end
        local tok = { cid = cid, src = src, at = deps.now() }
        held[cid] = tok
        return tok
    end
    local function release(tok) if held[tok.cid] == tok then held[tok.cid] = nil end end
    function D.busy(cid) return held[cid] ~= nil end

    ---Server log only: exact target + spot id ('legacy' = a pre-G2b lead whose target matches no spot).
    local function where(t, id) return ('%.1f,%.1f,%.1f lead=%s'):format(t.x, t.y, t.z, tostring(id or 'legacy')) end

    local function carried(src)
        local sections = {}
        for _, kind in ipairs(CARRIED) do
            local ref = { type = kind, id = src }
            local items, err = deps.snapshot(ref)
            if type(items) ~= 'table' then return nil, err or 'fh_unavailable' end
            sections[#sections + 1] = { ref = ref, items = items }
        end
        return sections
    end

    -- clean refusals from fh_core removeItem: nothing was removed
    local CLEAN = { fh_not_enough = true, fh_player_offline = true, fh_bad_item_name = true, fh_bad_amount = true }

    local function body(cid, src, state)
        local now = deps.now()
        if last[cid] and now - last[cid] < (L.cooldownSeconds or 0) then return false, 'dig_cooldown' end
        last[cid] = now

        local function same() return deps.citizenOf(src) == cid end -- no yield: valid up to the next dep call
        local pos = deps.pedCoords(src)
        if not pos then return false, 'no_player' end
        local sections, serr = carried(src)
        if not sections then return false, serr end
        local pick, why = logic.pick(sections, pos, L.digRadius, L.item, spots)
        if not pick then return false, why end

        local region = logic.regionFor(cfg, pick.id)
        if not (region and deps.knownRegion(region)) then
            log('ERROR lead dig: no known pay region for target %s (%s): nothing taken', where(pick.target, pick.id),
                tostring(region))
            return false, 'lead_bad_config'
        end
        local loot, lwhy = logic.roll(L.loot, deps.rng)
        if not loot then
            log('ERROR lead dig: loot table refused (%s): nothing taken', tostring(lwhy))
            return false, 'lead_bad_config'
        end

        local backpack = { type = 'backpack', id = src }
        if loot.item then
            local fits, fwhy = deps.canFit(backpack, loot.item, loot.qty)
            if not fits then
                local infra = fwhy == 'fh_unavailable' or fwhy == 'fh_inventory_down'
                return false, infra and fwhy or 'no_room'
            end
        end

        -- the one-shot step: from here on the lead is spent and the roll is owed
        if not same() then return false, 'player_changed' end
        local ok, err = deps.removeItem(pick.ref, L.item, 1)
        if not ok then
            if not CLEAN[err] then
                log('WARNING lead dig: removeItem failed (%s): citizenid=%s src=%s target=%s section=%s; lead state '
                    .. 'unknown, nothing paid', tostring(err), tostring(cid), tostring(src), where(pick.target, pick.id),
                    pick.ref.type)
            end
            return false, err == 'fh_not_enough' and 'no_lead' or (err or 'fh_refused')
        end
        state.removed = { target = pick.target, id = pick.id, region = region, loot = loot }

        local res, owed = { money = 0, qty = 0 }, nil
        ---Character switched after the lead was taken: nothing more is handed to anyone on this src.
        local function switched(step)
            owed = owed or {}
            if loot.money > 0 and res.money == 0 and not owed.money then owed.money, owed.payErr = loot.money, 'player_changed' end
            if loot.item and not res.item then owed.item, owed.qty, owed.addErr = loot.item, loot.qty, 'player_changed' end
            log('WARNING lead dig: character switched %s, pay by hand: citizenid=%s (dig owner) now=%s src=%s '
                .. 'target=%s section=%s region=%s roll=%d paid_money=%d owed_money=%d owed_item=%s x%d; the lead '
                .. 'came from whichever character held src during removeItem', step, tostring(cid),
                tostring(deps.citizenOf(src)), tostring(src), where(pick.target, pick.id), pick.ref.type, region, loot.index,
                res.money, owed.money or 0, owed.item or '-', owed.qty or 0)
            return false, 'dig_player_changed'
        end
        if not same() then return switched('during removeItem') end

        if loot.money > 0 then
            if not same() then return switched('before pay') end
            local pok, perr = deps.pay(src, loot.money, 'fence_lead_dig', region)
            if pok then res.money = loot.money
            else owed = { money = loot.money, payErr = tostring(perr or 'pay_failed') } end
        end
        if loot.item then
            if not same() then return switched('before addItem') end
            local aok, aerr = deps.addItem(backpack, loot.item, loot.qty)
            if aok then
                res.item, res.qty, res.label = loot.item, loot.qty, deps.label and deps.label(loot.item) or nil
            else
                owed = owed or {}
                owed.item, owed.qty, owed.addErr = loot.item, loot.qty, tostring(aerr or 'add_failed')
            end
        end
        if owed then
            res.owed = owed
            log('WARNING lead dig: lead taken but payout incomplete, pay by hand: citizenid=%s src=%s target=%s '
                .. 'region=%s owed_money=%d (%s) owed_item=%s x%d (%s)', tostring(cid), tostring(src),
                where(pick.target, pick.id), region, owed.money or 0, owed.payErr or '-', owed.item or '-', owed.qty or 0,
                owed.addErr or '-')
        end
        log('lead dug: citizenid=%s target=%s roll=%d money=%d item=%s x%d', tostring(cid), where(pick.target, pick.id),
            loot.index, res.money, tostring(res.item or '-'), res.qty)
        return true, res
    end

    ---@return boolean ok, table|string resultOrCode  result = { money, item, qty, label, owed? } (what was handed over)
    function D.dig(src)
        if not logic.validSrc(src) then return false, 'no_player' end
        local cid = deps.citizenOf(src)
        if not cid then return false, 'no_player' end
        local tok = acquire(cid, src) -- no yield between the lookup and here
        if not tok then return false, 'dig_busy' end
        local state = {}
        local r = table.pack(pcall(body, cid, src, state))
        release(tok)
        if r[1] then return table.unpack(r, 2, r.n) end
        local s = state.removed
        if s then
            log('WARNING lead dig: error after the lead was taken, pay by hand: citizenid=%s src=%s target=%s '
                .. 'region=%s roll=%d money=%d item=%s x%d: %s', tostring(cid), tostring(src), where(s.target, s.id),
                s.region, s.loot.index, s.loot.money, tostring(s.loot.item or '-'), s.loot.qty, tostring(r[2]))
            return false, 'dig_error_taken'
        end
        log('ERROR lead dig: citizenid=%s: %s (nothing taken)', tostring(cid), tostring(r[2]))
        return false, 'dig_error'
    end

    ---Client view of one lead's item info: { key, area, radius, hint } or nil. No exact target anywhere: area is the
    ---grid-rounded offset circle and key is derived from that area only. The target (and the hint) are resolved from
    ---the spot id server-side; the spot id itself is not sent either.
    function D.leadView(info)
        local t, id = logic.targetOf(info, spots)
        if not t then return nil end
        local a = logic.area(t, L.areaRadius)
        return { key = ('%d:%d'):format(a.x, a.y), area = a, radius = L.areaRadius, hint = logic.hintOf(info, spots, id) }
    end

    ---Map areas + hints for the leads the player carries (one per area).
    function D.leadsFor(src)
        if not logic.validSrc(src) then return {} end
        local sections = carried(src)
        local out, seen = {}, {}
        for _, sec in ipairs(sections or {}) do
            for _, it in pairs(sec.items) do
                local v = type(it) == 'table' and it.name == L.item and D.leadView(it.info)
                if v and not seen[v.key] then
                    seen[v.key] = true
                    out[#out + 1] = v
                end
            end
        end
        table.sort(out, function(a, b) return a.key < b.key end)
        return out
    end

    return D
end

-- ---------------------------------------------------------------- FXServer glue (not run by the specs)

if _G.GetCurrentResourceName and _G.lib then
    local cfg, logic = FhFenceConfig, FhFenceLeadsLogic
    local function log(msg) print('[fh_fence] ' .. msg) end

    local function guarded(fail, fn)
        return function(...)
            local r = table.pack(pcall(fn, ...))
            if not r[1] then
                log('leads: export call failed: ' .. tostring(r[2]))
                return false, fail
            end
            return table.unpack(r, 2, r.n)
        end
    end
    local function core(name)
        return guarded('fh_unavailable', function(...) return exports.fh_core[name](exports.fh_core, ...) end)
    end

    local ok, why = logic.validLoot(cfg.leads.loot)
    if not ok then log('ERROR leads loot table invalid (' .. tostring(why) .. '): every dig is refused') end
    local spots = FhFenceLeadSpots -- server/config_leads.lua (server only)
    local missing = logic.missingSpots(cfg, spots)
    if #missing > 0 then
        log('ERROR lead spot ids missing from server/config_leads.lua (not sold): ' .. table.concat(missing, ', '))
    end

    local function citizenOf(src)
        local okp, P = pcall(function() return exports['rsg-core']:GetPlayer(src) end)
        return okp and P and P.PlayerData and P.PlayerData.citizenid or nil
    end

    local digger = M.new(cfg, logic, {
        citizenOf = citizenOf,
        pedCoords = function(src)
            local ped = GetPlayerPed(src)
            if not ped or ped == 0 then return nil end
            local p = GetEntityCoords(ped)
            return { x = p.x + 0.0, y = p.y + 0.0, z = p.z + 0.0 }
        end,
        snapshot = core('snapshot'),
        canFit = core('canFit'),
        removeItem = core('removeItem'),
        addItem = core('addItem'),
        pay = guarded('pay_unavailable', function(...) return exports.fh_economy:pay(...) end),
        knownRegion = function(id) return FhRegions.isKnownRegion(id) end,
        rng = math.random,
        now = os.time,
        log = log,
        label = function(item) return cfg.items[item] and cfg.items[item].label or nil end,
    }, spots)

    lib.callback.register('fh:fence:dig', function(src) return digger.dig(src) end)
    lib.callback.register('fh:fence:leads', function(src) return digger.leadsFor(src) end)

    -- Using the lead item shows its hint + area on that client (rsg-core usable item; info = the lead's item info).
    -- src must be one loaded player: a bad src (e.g. -1 = every client) or a non-table item does nothing.
    local function onUse(src, item)
        if not logic.validSrc(src) or not citizenOf(src) or type(item) ~= 'table' then return end
        local v = digger.leadView(item.info)
        if v then TriggerClientEvent('fh:fence:lead_used', src, v) end
    end
    -- Re-registered when rsg-core restarts (its usable-item table is rebuilt), like fh_crafting/server/apothecary.lua.
    local function registerUsable()
        if GetResourceState('rsg-core') ~= 'started' then return end
        local rok, err = pcall(function() exports['rsg-core']:CreateUseableItem(cfg.leads.item, onUse) end)
        if not rok then log('CreateUseableItem ' .. cfg.leads.item .. ' failed: ' .. tostring(err)) end
    end
    AddEventHandler('onResourceStart', function(res)
        if res == GetCurrentResourceName() or res == 'rsg-core' then registerUsable() end
    end)
end

if _G.GetCurrentResourceName then _G.FhFenceLeads = M end
return M

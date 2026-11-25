-- fh_hunting trapper sale (spec L8, H3). Pure Lua: the decision, with natives and exports injected as deps.
-- The server is authoritative: it re-reads position, container and item, removes the item BEFORE paying and puts it
-- back if the payout fails, so a pelt is paid at most once. One sale per player at a time.
local M = {}

-- The shared position reader lives in shared/wagon.lua (loaded before this file; specs set FhHuntingWagon first).
-- It accepts vector3 values whose type() is 'vector3' (CfxLua 5.4) as well as { x, y, z } tables.
local xyz = assert(FhHuntingWagon and FhHuntingWagon.xyz, 'fh_hunting: load shared/wagon.lua before shared/sell.lua')
M.xyz = xyz

local function distance(a, b)
    local ax, ay, az = xyz(a)
    local bx, by, bz = xyz(b)
    if not ax or not bx then return nil end
    local dx, dy, dz = ax - bx, ay - by, az - bz
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end
M.distance = distance

local MESSAGES = {
    fh_no_player = 'No character loaded.',
    fh_too_far = 'Go to the trapper to sell.',
    fh_region_closed = 'The trapper here is not buying yet.',
    fh_bad_request = 'That sale is not valid.',
    fh_no_container = 'You need your saddlebag or a wagon nearby.',
    fh_no_item = 'That pelt is no longer there.',
    fh_not_pelt = 'The trapper does not buy that.',
    fh_bad_quality = 'The trapper cannot grade that pelt.',
    fh_bad_price = 'The trapper will not pay for that.',
    fh_busy = 'One sale at a time.',
    fh_remove_failed = 'Could not take the pelt from the container.',
    fh_pay_failed = 'The trapper could not pay you; your pelt was returned.',
}
function M.message(reason) return MESSAGES[reason] or ('Could not sell: ' .. tostring(reason)) end

local CONTAINERS = { saddlebag = true, wagon = true }

local function intIn(v, lo, hi)
    if type(v) ~= 'number' or v ~= v or v % 1 ~= 0 or v < lo or v > hi then return nil end
    return math.tointeger(v) or v
end

---Normalise a client sale request. Returns nil, err.
function M.parseRequest(payload)
    if type(payload) ~= 'table' then return nil, 'fh_bad_request' end
    if type(payload.container) ~= 'string' or not CONTAINERS[payload.container] then return nil, 'fh_bad_request' end
    local slot = intIn(payload.slot, 1, 4096)
    if not slot then return nil, 'fh_bad_request' end
    if type(payload.item) ~= 'string' or #payload.item > 64 or not payload.item:match('^[%w_]+$') then
        return nil, 'fh_bad_request'
    end
    return { container = payload.container, slot = slot, item = payload.item }
end

-- fh_ui `trapper` screen (T2): pure builders for the screen data and the inline sale notice, so the specs cover them.
-- server/main.lua only wires the relay event into these; nothing here reads the client beyond what parseRequest allows.
function M.soldNotice(res)
    return ('Sold %s (%d star%s) for $%d.'):format(res.label, res.stars, res.stars == 1 and '' or 's', res.price)
end

---The trapper list: { region_id, label, coords } for every registry entry with a `trapper` (data/legendaries/<region>.lua),
---in registry order, plus the config Trapper as the heartlands fallback when heartlands has none. Pure; enabling is
---checked by the caller (T.trappers / the client), never here.
function M.trappers(cfg, registry)
    local out, seen = {}, {}
    for _, e in ipairs(registry and registry.list or {}) do
        if type(e.trapper) == 'table' and not seen[e.region_id] then
            seen[e.region_id] = true
            out[#out + 1] = { region_id = e.region_id, label = e.trapper.label, coords = e.trapper.coords }
        end
    end
    local t = cfg and cfg.Trapper
    if t and t.region_id and not seen[t.region_id] then
        out[#out + 1] = { region_id = t.region_id, label = t.label or 'Trapper', coords = t.coords }
    end
    return out
end

---Build the fh:ui open/update data for the trapper screen. rows = T.list's output (nil on a refusal, e.g. walked out
---of range, so the screen keeps its last rows and only the notice changes); notice/notice_kind are the inline sale
---result and are only included when non-nil.
---@return table { title, rows?, notice?, notice_kind? }
function M.screenData(cfg, rows, notice, notice_kind, title)
    local data = { title = title or (cfg.Trapper and cfg.Trapper.label) or 'Trapper' }
    if rows ~= nil then data.rows = rows end
    if notice ~= nil then
        data.notice = notice
        if notice_kind ~= nil then data.notice_kind = notice_kind end
    end
    return data
end

---Build a trapper. opts = { cfg, animals, price (FhHuntingPrice), deps = {
---  citizenid(src)            -> string|nil
---  playerCoords(src)         -> coords|nil
---  refFor(kind, src, coords) -> container ref|nil   (kind 'saddlebag' | 'wagon'; wagon via the fh_cargo adapter)
---  snapshot(ref)             -> items (slot -> { name, amount, info })|nil, err
---  removeItem(ref, name, n, slot) -> ok, removed?  (removed = { slot, info? }: the pelt actually taken, if it differs)
---  addItem(ref, name, n, info)    -> ok, err        (refund path)
---  pay(src, amount, reason, region_id) -> ok, err
---  emit(name, payload)       -> server-only TriggerEvent
---  log(msg)                  -> optional
---}, trappers? = list (M.trappers; default { cfg.Trapper }), isEnabled? = fn(region_id) -> boolean (default: all enabled) }
function M.new(opts)
    local cfg, animals, price, deps = opts.cfg, opts.animals, opts.price, opts.deps
    local T = { busy = {} }
    local trappers = opts.trappers or M.trappers(cfg, nil)
    local isEnabled = opts.isEnabled or function() return true end

    -- A pelt row's stars: legendary pelts are fixed; otherwise info.stars must be 1..3.
    local function starsOf(animal, item)
        if animal.fixedStars then return animal.fixedStars end
        local s = type(item.info) == 'table' and item.info.stars or nil
        s = intIn(s, 1, 3)
        return s
    end

    ---The trapper the player stands at: the nearest one in SellRange whose region is enabled. A disabled-region
    ---trapper in range (and no enabled one) refuses fh_region_closed; nothing in range is fh_too_far.
    ---@return table|nil pc, table|string trapperOrReason
    local function near(src)
        local pc = deps.playerCoords(src)
        if not pc then return nil, 'fh_too_far' end
        local range = cfg.Trapper and cfg.Trapper.SellRange or 4.0
        local best, bestD, closed
        for _, t in ipairs(trappers) do
            local d = distance(pc, t.coords)
            if d and d <= range then
                if isEnabled(t.region_id) then
                    if not bestD or d < bestD then best, bestD = t, d end
                else
                    closed = true
                end
            end
        end
        if best then return pc, best end
        return nil, closed and 'fh_region_closed' or 'fh_too_far'
    end

    ---The enabled trapper the player stands at (its label titles the UI screen), or nil.
    function T.at(src)
        local pc, t = near(src)
        return pc and t or nil
    end

    ---Sellable pelts in the player's saddlebag and a nearby wagon, for the UI. Never trusted by sell().
    ---@return table|nil rows, string|nil err  rows = { { container, slot, item, animal, stars, price } }
    function T.list(src)
        if not deps.citizenid(src) then return nil, 'fh_no_player' end
        local pc, trapper = near(src)
        if not pc then return nil, trapper end
        local rows = {}
        for _, kind in ipairs({ 'saddlebag', 'wagon' }) do
            local ref = deps.refFor(kind, src, pc)
            local items = ref and deps.snapshot(ref)
            if type(items) == 'table' then
                for slot, it in pairs(items) do
                    local a = type(it) == 'table' and animals.byPelt[it.name]
                    local stars = a and starsOf(a, it)
                    local amount = a and price.price(a.value, stars, a.legendary == true, cfg)
                    if a and stars and amount and amount >= 1 then
                        rows[#rows + 1] = { container = kind, slot = slot, item = it.name, animal = a.key,
                            label = a.label, stars = stars, price = amount, legendary = a.legendary == true }
                    end
                end
            end
        end
        table.sort(rows, function(x, y)
            if x.container ~= y.container then return x.container < y.container end
            return x.slot < y.slot
        end)
        return rows
    end

    local function sellOne(src, payload)
        local cid = deps.citizenid(src)
        if not cid then return false, 'fh_no_player' end
        local req, perr = M.parseRequest(payload)
        if not req then return false, perr end
        local pc, trapper = near(src)
        if not pc then return false, trapper end
        local ref = deps.refFor(req.container, src, pc)
        if not ref then return false, 'fh_no_container' end
        local items = deps.snapshot(ref)
        local item = type(items) == 'table' and items[req.slot] or nil
        if type(item) ~= 'table' or item.name ~= req.item then return false, 'fh_no_item' end
        local animal = animals.byPelt[item.name]
        if not animal then return false, 'fh_not_pelt' end
        local stars = starsOf(animal, item)
        if not stars then return false, 'fh_bad_quality' end
        local amount = price.price(animal.value, stars, animal.legendary == true, cfg)
        if not amount or amount < 1 then return false, 'fh_bad_price' end

        -- Take the pelt first; pay only after it is gone.
        local removed, took = deps.removeItem(ref, item.name, 1, req.slot)
        if removed ~= true then return false, 'fh_remove_failed' end
        if type(took) == 'table' and took.slot ~= req.slot then
            -- the container took another slot's pelt (removal is by name): pay for what really left, refund if unpriceable
            item = { name = item.name, info = took.info }
            stars = starsOf(animal, item)
            amount = stars and price.price(animal.value, stars, animal.legendary == true, cfg)
            if not amount or amount < 1 then
                local back = deps.addItem(ref, item.name, 1, item.info)
                if back ~= true and deps.log then
                    deps.log(('REFUND FAILED: %s lost 1x %s (unpriceable) unpaid, container %s'):format(cid, item.name, req.container))
                end
                return false, 'fh_bad_price'
            end
        end
        local paid = deps.pay(src, amount, 'hunting:pelt', trapper.region_id)
        if paid ~= true then
            local back = deps.addItem(ref, item.name, 1, item.info)
            if back ~= true and deps.log then
                deps.log(('REFUND FAILED: %s lost 1x %s (stars %s) unpaid, container %s'):format(cid, item.name, stars, req.container))
            end
            return false, 'fh_pay_failed'
        end
        deps.emit('fh:hunting:pelt_sold', {
            citizenid = cid, item_id = item.name, animal = animal.key, size_class = animal.size_class,
            quality = stars, price = amount, region_id = trapper.region_id,
        })
        return true, { price = amount, stars = stars, item = item.name, label = animal.label }
    end

    ---@return boolean ok, table|string res  (ok: { price, stars, item, label }; else a reason code)
    function T.sell(src, payload)
        if T.busy[src] then return false, 'fh_busy' end
        T.busy[src] = true
        local ok, a, b = pcall(sellOne, src, payload)
        T.busy[src] = nil
        if not ok then
            if deps.log then deps.log('sell threw: ' .. tostring(a)) end
            return false, 'fh_error'
        end
        return a, b
    end

    return T
end

if GetCurrentResourceName then
    FhHuntingSell = M
else
    return M
end

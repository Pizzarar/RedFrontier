-- Survival items + action rules (plan survival-01, block S3). Pure Lua: no natives, no FiveM globals.
-- Items are registered with exports.fh_core:registerItems (B7) from server/actions.lua.
-- Canteen charges live in item.info.charges. A canteen with no `charges` key is fresh and counts as full.
local I = {}

local DEFAULT_MAX = 5 -- mirrors FhSurvivalNeeds.DEFAULT_CANTEEN_MAX (kept local: this file loads standalone)
I.DEFAULT_WASH_COOLDOWN = 300
I.DEFAULT_HEAT_RADIUS = 4.0
I.DEFAULT_WATER_RADIUS = 6.0
I.BEDROLL = 'bedroll' -- S4 rest item; used by server/rest.lua, not part of I.USE (no buff-on-use path here)

-- fh_core registerItems definitions (spec 4.1). weight is grams per unit.
I.ITEMS = {
    fh_jerky   = { label = 'Beef Jerky',    weight = 150, size_class = 'pocket', stackable = true,  value_base = 2, illicit = false },
    fh_biscuit = { label = 'Hardtack',      weight = 120, size_class = 'pocket', stackable = true,  value_base = 1, illicit = false },
    fh_stew    = { label = 'Tin of Stew',   weight = 400, size_class = 'pocket', stackable = true,  value_base = 4, illicit = false },
    fh_canteen = { label = 'Canteen',       weight = 500, size_class = 'pocket', stackable = false, value_base = 6, illicit = false },
    -- S4: rested 1.0 anywhere (server/rest.lua). Same registerItems path as the rest.
    bedroll    = { label = 'Bedroll',       weight = 2500, size_class = 'bulky', stackable = false, value_base = 12, illicit = false, useable = true },
}

-- Item -> effect. kind 'food' is consumed (remove 1); 'canteen' spends one charge. `scale` multiplies the
-- configured duration (a fraction 0..1 on the fh_jerky/fh_biscuit/fh_stew scale) and `magnitude` is the buff
-- magnitude (1.0 normal, >1 is a bonus, as on fh_stew).
--
-- The rsg-core/loot foods and drinks below are base items (rsg-core/shared/items.lua): fh_survival only
-- registers their useable callback (CreateUseableItem); fh_core registerItems does NOT define them (see
-- `isForeign`). Fractions on the jerky/biscuit/stew scale, justified per row:
--   bread 0.35      = a plain bun, a snack like hardtack (rsg: "not very filling more of a snack")
--   canned_beans 0.6 = a staple legume/protein can, more filling than bread
--   canned_apricots 0.4 = fruit in syrup, light
--   canned_salmon 0.6  = protein-rich fish
--   cooked_meat 0.5    = "a light meat snack", same as jerky
--   stew 1.0           = "warm and hearty... vegetables and meat", a full meal (no magnitude bonus vs fh_stew)
--   stew_veg 0.85      = "all the veg, none of the meats", hearty but short of a meat stew
--   jerky_meat 0.5     = "trail food, keeps forever", same as fh_jerky
--   (hydrated) water 1.0 = a full bottle, one canteen charge's worth; coffee 0.6 = a smaller cup
I.USE = {
    fh_jerky       = { kind = 'food',    buff = 'well_fed', magnitude = 1.0,  scale = 0.5 },
    fh_biscuit     = { kind = 'food',    buff = 'well_fed', magnitude = 1.0,  scale = 0.35 },
    fh_stew        = { kind = 'food',    buff = 'well_fed', magnitude = 1.15, scale = 1.0 },
    fh_canteen     = { kind = 'canteen', buff = 'hydrated', magnitude = 1.0,  scale = 1.0 },
    -- rsg-core/loot food -> well_fed (consumed like food, remove 1)
    bread          = { kind = 'food',    buff = 'well_fed', magnitude = 1.0,  scale = 0.35 },
    canned_beans   = { kind = 'food',    buff = 'well_fed', magnitude = 1.0,  scale = 0.6 },
    canned_apricots = { kind = 'food',   buff = 'well_fed', magnitude = 1.0,  scale = 0.4 },
    canned_salmon  = { kind = 'food',    buff = 'well_fed', magnitude = 1.0,  scale = 0.6 },
    cooked_meat    = { kind = 'food',    buff = 'well_fed', magnitude = 1.0,  scale = 0.5 },
    stew           = { kind = 'food',    buff = 'well_fed', magnitude = 1.0,  scale = 1.0 },
    stew_veg       = { kind = 'food',    buff = 'well_fed', magnitude = 1.0,  scale = 0.85 },
    jerky_meat     = { kind = 'food',    buff = 'well_fed', magnitude = 1.0,  scale = 0.5 },
    -- rsg-core drinks -> hydrated (still consumed like food: remove 1, not a canteen charge)
    coffee         = { kind = 'food',    buff = 'hydrated', magnitude = 1.0,  scale = 0.6 },
    water          = { kind = 'food',    buff = 'hydrated', magnitude = 1.0,  scale = 1.0 },
}

local function isNum(v) return type(v) == 'number' and v == v and v ~= math.huge and v ~= -math.huge end

local BASE_DURATION = { well_fed = 3600, hydrated = 2700, clean = 5400, warm = 1200 }

---@param name string item name
---@param durations table? configured durations by buff id (bad/missing entries fall back to defaults)
---@return table|nil { kind, buff_id, magnitude, duration } or nil for an item that is not ours
function I.effectOf(name, durations)
    local u = type(name) == 'string' and I.USE[name] or nil
    if not u then return nil end
    local d = type(durations) == 'table' and durations[u.buff]
    if not (isNum(d) and d > 0) then d = BASE_DURATION[u.buff] end
    return { kind = u.kind, buff_id = u.buff, magnitude = u.magnitude, duration = d * u.scale }
end

---True when `name` is a base rsg-core item (in I.USE but not one of our I.ITEMS). fh_survival only registers
---these as useable (CreateUseableItem); fh_core registerItems does not define them. A @crafting/@hunting item
---added later is one row here, skipped silently until its item exists in the live registry.
function I.isForeign(name) return I.USE[name] ~= nil and I.ITEMS[name] == nil end

---Partition I.USE rows for useable registration. `exists(name)` reports whether a foreign item is present in the
---live item registry (RSGCore.Shared.Items). Our I.ITEMS rows always register; a foreign row registers only when
---it exists, otherwise it is skipped (the caller logs one line). Returns two sorted name arrays.
function I.usableRows(exists)
    local register, skipped = {}, {}
    for name in pairs(I.USE) do
        if I.isForeign(name) then
            if type(exists) == 'function' and exists(name) then register[#register + 1] = name
            else skipped[#skipped + 1] = name end
        else
            register[#register + 1] = name
        end
    end
    table.sort(register)
    table.sort(skipped)
    return register, skipped
end

---Consume-attempt outcome (S3 "consume first, grant after" invariant, pure). The caller removes the item, then
---applies the buff only if the remove succeeded, then:
---  removed ~= true             -> 'blocked' (nothing removed, nothing granted)
---  removed and applied ~= true -> 'refund'  (buff refused by fh_buffs caps; caller re-adds the item)
---  both true                   -> 'granted'
function I.consumeOutcome(removed, applied)
    if removed ~= true then return 'blocked' end
    if applied ~= true then return 'refund' end
    return 'granted'
end

local function validMax(max)
    if max == nil then return DEFAULT_MAX end
    if isNum(max) and max == math.floor(max) and max >= 1 then return max end
    return nil
end

local function copyInfo(info)
    local out = {}
    if type(info) == 'table' then for k, v in pairs(info) do out[k] = v end end
    return out
end

---Charges in a canteen's info. Missing `charges` = fresh canteen = full. @return integer|nil (nil = corrupt)
function I.charges(info, max)
    max = validMax(max)
    if not max then return nil end
    local c = type(info) == 'table' and info.charges or nil
    if c == nil then return max end
    if not isNum(c) or c ~= math.floor(c) or c < 0 or c > max then return nil end
    return c
end

---Drink once. @return boolean ok, table|string newInfo (a copy; other keys kept) or error code ('empty', 'invalid_charges')
function I.useCanteen(info, max)
    local c = I.charges(info, max)
    if c == nil then return false, 'invalid_charges' end
    if c == 0 then return false, 'empty' end
    local out = copyInfo(info)
    out.charges = c - 1
    return true, out
end

---Refill to max. @return boolean ok, table|string newInfo or error code ('full', 'invalid_charges', 'invalid_max')
function I.refillCanteen(info, max)
    local m = validMax(max)
    if not m then return false, 'invalid_max' end
    local c = I.charges(info, m)
    if c == nil then return false, 'invalid_charges' end
    if c == m then return false, 'full' end
    local out = copyInfo(info)
    out.charges = m
    return true, out
end

---Wash cooldown. lastAt nil = never washed. A clock that went backwards counts as still cooling down.
---@return boolean ok, number|nil remainingSeconds
function I.washReady(lastAt, now, cooldown)
    if not isNum(now) then return false, nil end
    if not (isNum(cooldown) and cooldown >= 0) then cooldown = I.DEFAULT_WASH_COOLDOWN end
    if lastAt == nil then return true end
    if not isNum(lastAt) then return false, cooldown end
    local rem = lastAt + cooldown - now
    if rem > 0 then return false, rem end
    return true
end

---Water-check mode. Only the exact string 'native' selects the unverified native path; everything else is 'zones'.
function I.waterMode(v)
    if v == 'native' then return 'native' end
    return 'zones'
end

---Is `pos` ({x,y[,z]}) within a zone? zone = { x, y, z?, radius? } or { vec-like with x/y }. Distance is 3D only when both
---have z; otherwise 2D. Malformed zones are skipped.
function I.nearAny(pos, zones, defaultRadius)
    if type(pos) ~= 'table' or not isNum(pos.x) or not isNum(pos.y) or type(zones) ~= 'table' then return false end
    for _, z in ipairs(zones) do
        if type(z) == 'table' and isNum(z.x) and isNum(z.y) then
            local r = (isNum(z.radius) and z.radius > 0) and z.radius or defaultRadius
            if isNum(r) and r > 0 then
                local dx, dy = pos.x - z.x, pos.y - z.y
                local d2 = dx * dx + dy * dy
                if isNum(pos.z) and isNum(z.z) then local dz = pos.z - z.z; d2 = d2 + dz * dz end
                if d2 <= r * r then return true end
            end
        end
    end
    return false
end

---Standing in water per the config zone list.
function I.inWaterZone(pos, zones) return I.nearAny(pos, zones, I.DEFAULT_WATER_RADIUS) end

---Within a heat source (campfire) radius. `sources` is an array of { x, y, z?, radius? }.
function I.nearHeat(pos, sources, defaultRadius)
    return I.nearAny(pos, sources, (isNum(defaultRadius) and defaultRadius > 0) and defaultRadius or I.DEFAULT_HEAT_RADIUS)
end

if _G.GetCurrentResourceName then _G.FhSurvivalItems = I end
return I

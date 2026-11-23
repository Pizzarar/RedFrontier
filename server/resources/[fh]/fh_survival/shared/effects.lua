-- Sluggish effect params (plan survival-01, block S5). Pure Lua: no natives, no health values (never lethal).
-- level (0-3) + mode ('notify'|'native') + config -> what the client should show/apply.
local E = {}

E.DEFAULT_TEXT = {
    [0] = '',
    'You feel a little sluggish.',
    'You are sluggish and worn down.',
    'You are exhausted. Eat, drink, rest and wash.',
}
-- Native multipliers per level (1.0 = normal). Only used when mode == 'native'.
E.DEFAULT_REGEN = { [0] = 1.0, 0.85, 0.7, 0.5 }
E.CLIPSET_LEVEL = 3

local function isNum(v) return type(v) == 'number' and v == v and v ~= math.huge and v ~= -math.huge end

local function level(v)
    if not isNum(v) then return 0 end
    return math.max(0, math.min(3, math.floor(v)))
end

local function pick(tbl, lvl, default)
    local v = type(tbl) == 'table' and tbl[lvl] or nil
    return v ~= nil and v or default[lvl]
end

---@param lvl any sluggish level (clamped 0..3, junk = 0)
---@param mode any 'native' enables natives; anything else (nil, typo) is the safe 'notify' path
---@param cfg table? { Text = {[1..3]=string}, Regen = {[0..3]=number}, Clipset = string|nil }
---@return table { level, notify = string|nil, native = boolean, staminaRegen, deadeyeRegen, clipset }
function E.params(lvl, mode, cfg)
    lvl = level(lvl)
    cfg = type(cfg) == 'table' and cfg or {}
    local text = pick(cfg.Text, lvl, E.DEFAULT_TEXT)
    local out = { level = lvl, native = false, staminaRegen = 1.0, deadeyeRegen = 1.0, clipset = nil }
    out.notify = (lvl > 0 and type(text) == 'string' and text ~= '') and ('%s (level %d/3)'):format(text, lvl) or nil
    if mode ~= 'native' then return out end
    out.native = true
    local r = pick(cfg.Regen, lvl, E.DEFAULT_REGEN)
    if not isNum(r) or r < 0.1 then r = 1.0 end -- never stop regen entirely; junk = normal
    if r > 1.0 then r = 1.0 end
    out.staminaRegen, out.deadeyeRegen = r, r
    if lvl >= E.CLIPSET_LEVEL and type(cfg.Clipset) == 'string' and cfg.Clipset ~= '' then out.clipset = cfg.Clipset end
    return out
end

---Whether the client needs to notify: only when the level changed and moved to a different non-zero level (reaching 0 is silent).
---@return boolean
function E.shouldNotify(prevLevel, newLevel)
    return level(prevLevel) ~= level(newLevel) and level(newLevel) > 0
end

-- FXServer loads shared scripts as plain chunks; expose a global there, module under specs.
if _G.GetCurrentResourceName then _G.FhSurvivalEffects = E end
return E

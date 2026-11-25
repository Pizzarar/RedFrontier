-- Pure relay rules for fh_ui (spec L10): no natives, specced under busted (spec/ui_relay_spec.lua).
-- fh_ui holds NO game authority: it only checks that a NUI action is well formed, rate-limited and aimed at a known
-- screen, then re-emits it to the owning lane as a server event. The lane revalidates everything.
local M = {}

-- THE whitelist: screen -> owning lane (lane = event domain, spec 4.3). Add a screen here when its block lands.
M.screens = {
    placeholder = 'ui',        -- U1 router smoke screen; owner is fh_ui itself (nothing listens)
    buffs       = 'buffs',     -- buff HUD (passive)
    heat        = 'heat',      -- heat indicator (passive)
    bags        = 'death',     -- own drop-bag countdown (passive, U2)
    insurance   = 'death',     -- tracker insurance dialog (L4 Death & Insurance)
    jobs        = 'quests',    -- jobs board: contracts, bounties, hunts (@quests lane)
    journal     = 'quests',    -- quest journal: active quests + history, abandon (@quests lane)
    dialogue    = 'quests',    -- giver dialogue: pages + quest offer (@quests lane)
    station     = 'homestead', -- station menus (L1 stations; L5 crafting may take over later)
    fence       = 'fence',     -- fence shop (fh_fence owns it)
    survival    = 'survival',  -- survival needs HUD (passive, fh_survival state; idea-854)
    tradepost   = 'trade',     -- trade post (fh_trade owns it)
    fieldguide  = 'tutorial',  -- field guide help pages (read-only, @guide lane owns content)
    trapper     = 'hunting',   -- trapper sell screen (fh_hunting owns it)
    tailor      = 'tailor',    -- tailor / general-store clothing catalog (fh_tailor owns it)
    wardrobe    = 'tailor',    -- owned outfits, worn look, saved slots (fh_tailor owns it)
    wagonyard   = 'cargo',     -- trade-post wagon yard: buy / call / stow (fh_cargo owns it)
}

-- Passive HUD widgets never take NUI focus. Everything else is interactive.
M.passive = { buffs = true, heat = true, bags = true, survival = true }

-- Optional per-screen action allowlist. A screen listed here may only send the actions named in its set
-- (fieldguide is read-only and only ever closes). Screens not listed here stay unguarded: the owning lane
-- revalidates ev.screen itself. Keep this small; add an entry only when a screen must not send other actions.
M.actions = {
    fieldguide = { close = true },
    trapper    = { sell = true, close = true },
    tailor     = { buy = true, close = true },
    wardrobe   = { equip = true, save = true, wear = true, close = true },
    wagonyard  = { buy = true, call = true, stow = true, close = true },
}

-- Screens that may ask for a client-local mirror preview (fh_tailor owns the apply). No server round trip, no authority.
M.previewable = { tailor = true, wardrobe = true }

local MAX_LOOK_ID, MAX_LOOK_ITEMS = 64, 16

local function lookId(v) return type(v) == 'string' and #v >= 1 and #v <= MAX_LOOK_ID end

-- Pure shape check of a NUI preview request { screen, look = { outfit = id, items = { id, ... } } }.
-- Returns true, screen, look(clean copy) | false, reason. The catalog check (unknown / wrong kind) is fh_tailor's.
function M.checkPreview(msg)
    if type(msg) ~= 'table' then return false, 'bad_message' end
    if type(msg.screen) ~= 'string' or not M.previewable[msg.screen] then return false, 'unknown_screen' end
    local look = msg.look
    if type(look) ~= 'table' or not lookId(look.outfit) then return false, 'bad_look' end
    local items = {}
    if look.items ~= nil then
        if type(look.items) ~= 'table' or #look.items > MAX_LOOK_ITEMS then return false, 'bad_look' end
        for k in pairs(look.items) do
            if type(k) ~= 'number' or k < 1 or k > #look.items then return false, 'bad_look' end
        end
        for i = 1, #look.items do
            if not lookId(look.items[i]) then return false, 'bad_look' end
            items[i] = look.items[i]
        end
    end
    return true, msg.screen, { outfit = look.outfit, items = items }
end

M.limits = {
    actionPattern = '^[a-z_]+$', -- Lua has no {n,m}; length 1..maxAction is checked separately
    maxAction = 32,
    maxBytes = 2048,   -- serialized payload estimate
    maxDepth = 4,      -- payload itself is depth 1
    rate = 5,          -- tokens per second
    burst = 10,
}

local function finite(n) return type(n) == 'number' and n == n and n > -math.huge and n < math.huge end

-- Estimated serialized size of a payload; returns bytes or nil, reason. Plain data only.
local function measure(v, depth)
    local t = type(v)
    if t == 'string' then return #v + 2 end
    if t == 'boolean' then return 5 end
    if t == 'number' then
        if not finite(v) then return nil, 'bad_number' end
        return 8
    end
    if t ~= 'table' then return nil, 'bad_type' end
    if depth > M.limits.maxDepth then return nil, 'too_deep' end
    local n = 2
    for k, x in pairs(v) do
        local kt = type(k)
        if kt == 'string' then n = n + #k + 3
        elseif kt == 'number' and finite(k) then n = n + 4
        else return nil, 'bad_key' end
        local s, why = measure(x, depth + 1)
        if not s then return nil, why end
        n = n + s
        if n > M.limits.maxBytes then return nil, 'too_big' end
    end
    return n
end
function M.measure(v) return measure(v, 1) end

function M.eventName(lane, action) return ('fh:%s:ui_%s'):format(lane, action) end

-- Token bucket per player. Time is injected (seconds) so specs can fake it.
function M.newLimiter(rate, burst)
    return { rate = rate or M.limits.rate, burst = burst or M.limits.burst, by = {} }
end

function M.take(lim, key, now)
    local b = lim.by[key]
    if not b then
        b = { tokens = lim.burst, at = now }
        lim.by[key] = b
    end
    local dt = now - b.at
    if dt > 0 then
        b.tokens = math.min(lim.burst, b.tokens + dt * lim.rate)
        b.at = now
    end
    if b.tokens >= 1 then
        b.tokens = b.tokens - 1
        return true
    end
    return false
end

function M.forget(lim, key) lim.by[key] = nil end

-- Pure shape check. Returns true, lane, action, payload | false, reason.
function M.validate(msg)
    if type(msg) ~= 'table' then return false, 'bad_message' end
    local screen, action, payload = msg.screen, msg.action, msg.payload
    if type(screen) ~= 'string' then return false, 'bad_screen' end
    local lane = M.screens[screen]
    if not lane then return false, 'unknown_screen' end
    if type(action) ~= 'string' or not action:match(M.limits.actionPattern) or #action > M.limits.maxAction then return false, 'bad_action' end
    local allowed = M.actions[screen]
    if allowed and not allowed[action] then return false, 'bad_action' end
    if payload == nil then payload = {} end
    if type(payload) ~= 'table' then return false, 'bad_payload' end
    local size, why = M.measure(payload)
    if not size then return false, why end
    return true, lane, action, payload
end

-- Full relay decision: rate limit first (counts bad traffic too), then validate.
-- Returns true, eventName, eventPayload | false, reason. eventPayload = { src, screen, action, payload } (events.md: one table, src first).
function M.relay(lim, src, msg, now)
    if not M.take(lim, src, now) then return false, 'rate_limited' end
    local ok, lane, action, payload = M.validate(msg)
    if not ok then return false, lane end
    return true, M.eventName(lane, action), { src = src, screen = msg.screen, action = action, payload = payload }
end

if GetCurrentResourceName then
    FhUiRelay = M
else
    return M
end

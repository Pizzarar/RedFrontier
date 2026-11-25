-- Pure fh_anim decisions (no natives): key lookup, guard verdict, "is our anim still the active one".
local M = {}

-- Entry for `key`, or nil when the flag is off, the table/key is missing or the entry is malformed.
function M.lookup(tbl, enabled, key)
    if not enabled or type(tbl) ~= 'table' or type(key) ~= 'string' then return nil end
    local e = tbl[key]
    if type(e) ~= 'table' then return nil end
    if e.scenario then
        if type(e.scenario) ~= 'string' then return nil end
    elseif type(e.dict) ~= 'string' or type(e.clip) ~= 'string' then
        return nil
    end
    return e
end

-- st = { mounted, inVehicle, swimming, dead, ragdoll, inScenario } booleans. -> ok, reason
local ORDER = { 'dead', 'ragdoll', 'swimming', 'mounted', 'inVehicle', 'inScenario' }
function M.guard(st)
    st = st or {}
    for _, k in ipairs(ORDER) do
        if st[k] then return false, k end
    end
    return true
end

-- Is `token` still the anim we started? `active` is the module-held record { key, id }.
function M.isOurs(active, token)
    return active ~= nil and token ~= nil and active.id == token.id and active.key == token.key
end

-- stop(key) decision: only when something of ours is active, for that key (or any key when key is nil).
function M.shouldClear(active, key, stillPlaying)
    if active == nil or not stillPlaying then return false end
    return key == nil or active.key == key
end

-- Sequence state across the requestAnimDict yield: S = M.newState(). Every claim/invalidate bumps seq, so an
-- older begin() that resumes after a newer start or a stop sees it is stale and must not play.
function M.newState() return { seq = 0, key = nil } end

function M.claim(S, key)
    S.seq = S.seq + 1
    S.key = key
    return { key = key, id = S.seq }
end

function M.isCurrent(S, token) return token ~= nil and S.seq == token.id and S.key == token.key end

-- Invalidate the latest claim. key=nil matches any. Returns true only if something (pending or playing) matched.
function M.invalidate(S, key)
    if S.key == nil or (key ~= nil and S.key ~= key) then return false end
    S.seq = S.seq + 1
    S.key = nil
    return true
end

if GetCurrentResourceName then
    FhAnimLogic = M
else
    return M
end

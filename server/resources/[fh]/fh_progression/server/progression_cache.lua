-- Per-player rep cache for fh_progression. Pure Lua: the rep read, player lookup and event emit are injected, so
-- specs drive it with coroutines. deps.read may yield (the getRep export awaits the DB), so every write after a read is guarded:
--  * loadAll commits only if no newer load, rep_changed, unload or drop for that src happened while it read
--    (loadGen[src] still holds its token) and src still has the same character.
--  * a rep_changed re-read (value = nil) applies only if its entry is still the cached one and no newer rep_changed
--    for the same region arrived (per-region seq token): it never overwrites a fresher value or emits a stale crossing.
local M = {}

---@param deps { cfg: table, logic: table, read: fun(citizenid: string, region_id: string): number|nil, citizenOf: fun(src: integer): string|nil, emit: fun(payload: table) }
function M.new(deps)
    local cfg, logic = deps.cfg, deps.logic
    -- [src] = { citizenid = string, rep = { [region_id] = number }, complete = boolean, seq = { [region_id] = token } }
    -- `complete` is false when any region read failed; entry() reloads it on the next access.
    local cache = {}
    local loadGen = {} -- [src] = token of the one in-flight load still allowed to commit; nil = none
    local counter = 0
    local function token()
        counter = counter + 1
        return counter
    end

    local self = {}

    ---Cached entry without loading (specs / diagnostics).
    function self.peek(src) return cache[src] end

    ---Unload / drop: forget src and stop any in-flight load or re-read from committing.
    function self.invalidate(src)
        cache[src] = nil
        loadGen[src] = nil
    end

    ---Reads EVERY configured region. Never emits: with no prior values there is no crossing to report.
    ---Returns the snapshot it read (committed or superseded) while src still has that character, else nil.
    function self.loadAll(src, citizenid)
        local g = token()
        loadGen[src] = g
        local e = { citizenid = citizenid, rep = {}, complete = true, seq = {} }
        for region_id in pairs(cfg.tiers) do
            local v = deps.read(citizenid, region_id)
            if v == nil then e.complete = false else e.rep[region_id] = v end
        end
        local mine = loadGen[src] == g
        if mine then loadGen[src] = nil end
        if deps.citizenOf(src) ~= citizenid then return nil end -- character changed while reading
        if mine then cache[src] = e end
        return e
    end

    ---Cached entry for src, reloaded when missing, incomplete, or belonging to a different character.
    function self.entry(src)
        if type(src) ~= 'number' then return nil end
        local cid = deps.citizenOf(src)
        if not cid then return nil end
        local e = cache[src]
        if e and e.citizenid == cid and e.complete then return e end
        return self.loadAll(src, cid)
    end

    function self.onRepChanged(src, citizenid, region_id, value)
        loadGen[src] = nil -- an in-flight load may have read this region before the change: it must not commit
        local e = cache[src]
        if not e or e.citizenid ~= citizenid or not e.complete then
            self.loadAll(src, citizenid) -- cold/stale: the read already includes this change, so no crossing is knowable
            return
        end
        local s = token()
        e.seq[region_id] = s
        if type(value) ~= 'number' or value ~= value then
            local v = deps.read(citizenid, region_id)
            if cache[src] ~= e or e.seq[region_id] ~= s then return end -- dropped/reloaded or a newer change won
            if v == nil then
                e.complete = false -- the old value is now known stale: keep it, emit nothing, reload on next access
                return
            end
            value = v
        end
        local old = e.rep[region_id]
        e.rep[region_id] = value
        local changed, oldTier, newTier = logic.crossing(cfg, region_id, old, value)
        if changed then
            deps.emit({ src = src, citizenid = citizenid, region_id = region_id, old = oldTier, new = newTier })
        end
    end

    function self.getRep(src, region_id)
        local e = self.entry(src)
        return e and e.rep[region_id] or 0
    end

    function self.getTier(src, region_id)
        local e = self.entry(src)
        return (logic.tierForRep(cfg, region_id, e and e.rep[region_id] or 0))
    end

    ---@return boolean ok, string? reason
    function self.canUnlock(src, unlock_id)
        local e = self.entry(src)
        if not e then return false, 'no_player' end
        return logic.canUnlock(cfg, e.rep, unlock_id)
    end

    return self
end

if _G.GetCurrentResourceName then _G.FhProgressionCache = M end
return M

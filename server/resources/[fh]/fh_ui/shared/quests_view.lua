-- Pure mapping from the fh_quests `fh:quests:sync` v1 snapshot to fh_ui screen data (no natives; specced in
-- spec/ui_quests_view_spec.lua). One feed per screen; the client adapter (client/adapter.lua) calls them.
local M = {}

local function asTable(x) return type(x) == 'table' and x or {} end

local function rewards(r)
    r = asTable(r)
    local out = {}
    if type(r.money) == 'number' then out.money = r.money end
    if type(r.rep) == 'table' then out.rep = { region_id = r.rep.region_id, delta = r.rep.delta } end
    if type(r.items) == 'table' then
        out.items = {}
        for _, it in ipairs(r.items) do
            if type(it) == 'table' and type(it.name) == 'string' then
                out.items[#out.items + 1] = { name = it.name, amount = tonumber(it.amount) or 1 }
            end
        end
    end
    return out
end

---Jobs screen data from a sync snapshot. Returns nil when the snapshot carries no board (nothing to show).
---`now` (unix seconds) is optional; with it, an expired board comes back with no offers and expired = true.
function M.jobs(snap, now)
    local board = type(snap) == 'table' and snap.board or nil
    if type(board) ~= 'table' then return nil end
    local expires = tonumber(board.expires_at)
    local expired = (now ~= nil and expires ~= nil and now >= expires) or false
    local offers = {}
    if not expired then
        for _, o in ipairs(asTable(board.offers)) do
            if type(o) == 'table' and type(o.id) == 'string' then
                offers[#offers + 1] = {
                    id = o.id, job_type = tostring(o.job_type or ''), title = tostring(o.title or o.id),
                    text = type(o.text) == 'string' and o.text or '', rewards = rewards(o.rewards),
                    accepted = o.accepted == true,
                }
            end
        end
    end
    return { region_id = tostring(board.region_id or ''), expires_at = expires or 0, expired = expired, offers = offers }
end

local function str(x) return type(x) == 'string' and x or nil end
local function num(x) return type(x) == 'number' and x == x and x or nil end

---Journal screen data from a sync snapshot (`journal[]`, README sync v1; fields are not invented). Returns nil when the
---snapshot has no journal table. Active quests first, then history newest first; malformed rows are skipped.
function M.journal(snap)
    local j = type(snap) == 'table' and snap.journal or nil
    if type(j) ~= 'table' then return nil end
    local rows = {}
    for i, e in ipairs(j) do
        if type(e) == 'table' and type(e.quest_id) == 'string' then
            rows[#rows + 1] = { i = i, e = {
                quest_id = e.quest_id, kind = tostring(e.kind or ''), title = tostring(e.title or e.quest_id),
                giver = str(e.giver), region_id = str(e.region_id), status = tostring(e.status or ''),
                step = num(e.step), steps_total = num(e.steps_total), step_text = str(e.step_text) or '',
                count = num(e.count), need = num(e.need), rewards = rewards(e.rewards),
                cooldown_until = num(e.cooldown_until), updated_at = num(e.updated_at) or 0,
            } }
        end
    end
    table.sort(rows, function(a, b)
        local aa, ba = a.e.status == 'active', b.e.status == 'active'
        if aa ~= ba then return aa end
        if a.e.updated_at ~= b.e.updated_at then return a.e.updated_at > b.e.updated_at end
        return a.i < b.i
    end)
    local entries = {}
    for k, r in ipairs(rows) do entries[k] = r.e end
    return { entries = entries }
end

---Data to seed a freshly opened screen from the cached sync, or nil to leave the open payload alone. Only the journal is
---seeded (jobs opens with its own board). An open payload carrying a notice (server error) or real entries is never
---overwritten; a missing snapshot (e.g. after a character unload) seeds nothing.
function M.seedFor(screen, openData, snap)
    if screen ~= 'journal' or type(snap) ~= 'table' then return nil end
    if type(openData) == 'table' then
        if openData.notice ~= nil then return nil end
        if type(openData.entries) == 'table' and next(openData.entries) ~= nil then return nil end
    end
    return M.journal(snap)
end

-- screen -> feed(snapshot, now) -> data | nil
M.feeds = { jobs = M.jobs, journal = M.journal }

if GetCurrentResourceName then
    FhUiQuestsView = M
else
    return M
end

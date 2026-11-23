-- Pure mapping from the fh_quests `fh:quests:sync` v1 snapshot to fh_ui screen data (no natives; specced in
-- spec/ui_quests_view_spec.lua). One feed per screen; the client adapter (client/adapter.lua) calls them.
-- W3 (journal) adds M.feeds.journal here.
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

-- screen -> feed(snapshot, now) -> data | nil
M.feeds = { jobs = M.jobs }

if GetCurrentResourceName then
    FhUiQuestsView = M
else
    return M
end

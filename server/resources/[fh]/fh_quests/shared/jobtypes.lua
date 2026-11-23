-- fh_quests built-in job types (Q3): hunt_request, camp_clear, bounty. Pure Lua, no natives.
-- This is the data + the decisions. server/jobtypes.lua registers them through the same registerJobType export
-- every other lane uses, and does the bounty I/O (spawn, death watch). Region templates live in M.DATA.
--
-- Every offer carries the fields registerJobType documents (key/title/text/on/where/count/rewards); the job types
-- decide their own verdicts in M.verdict (used as hooks.onEvent), reading the accepted-offer snapshot that
-- the server stored in state.progress.job. ALL coordinates/models below are guesses: TODO-verify-in-game.
local M = {}

local function match() return FhQuestsMatch or require('match') end

M.TYPES = { 'hunt_request', 'camp_clear', 'bounty' }
M.BOUNTY_EVENT = 'fh:quests:bounty_down' -- local server event fired by the bounty death watcher: { citizenid, offer_key, region_id }
M.BOUNTY_TAG_PREFIX = 'fh_quests:bounty:'

M.DATA = {
    heartlands = {
        hunt = { -- { animal, stars, money }: deliver an N-star pelt of that animal (sold at the fh_hunting buyer)
            { 'deer', 1, 6 }, { 'deer', 2, 10 }, { 'wolf', 2, 16 }, { 'wolf', 3, 24 }, { 'bear', 2, 34 }, { 'bear', 3, 50 },
        },
        camps = { -- fh_zones camp ids (fh_zones/config.lua)
            { id = 'heartlands_t1_01', label = 'Heartlands outlaw camp', money = 40, rep = 3 },
        },
        bounties = { -- wanted NPCs (model/coords TODO-verify-in-game)
            { key = 'silas_crow', name = 'Silas Crow', model = 'g_m_m_unibanditos_01',
                coords = { x = -128.0, y = 826.0, z = 117.0 }, heading = 140.0, money = 30, rep = 2 },
            { key = 'mabel_teague', name = 'Mabel Teague', model = 'g_m_m_unibanditos_01',
                coords = { x = -170.0, y = 860.0, z = 118.0 }, heading = 20.0, money = 36, rep = 2 },
        },
    },
}

local function rewards(region_id, money, rep)
    return { money = money, rep = { region_id = region_id, delta = rep } }
end

local function huntOffers(region_id, d)
    local out = {}
    for _, h in ipairs(d.hunt or {}) do
        local animal, stars, money = h[1], h[2], h[3]
        out[#out + 1] = {
            key = ('%s_%dstar'):format(animal, stars),
            title = ('Pelt wanted: %d-star %s'):format(stars, animal),
            text = ('Sell a %d-star or better %s pelt.'):format(stars, animal),
            on = 'fh:hunting:pelt_sold',
            -- `animal` is optional until the pelt_sold payload carries it (Q0b / Hunting H3): quality alone decides now.
            where = { quality = { min = stars }, animal = { optional = true, eq = animal } },
            rewards = rewards(region_id, money, 1), region_id = region_id, animal = animal, stars = stars,
        }
    end
    return out
end

local function campOffers(region_id, d)
    local out = {}
    for _, c in ipairs(d.camps or {}) do
        out[#out + 1] = {
            key = 'camp_' .. c.id, title = 'Clear out: ' .. c.label,
            text = 'Wipe out the outlaws at the ' .. c.label .. '.',
            on = 'fh:zones:camp_cleared', where = { camp_id = c.id },
            rewards = rewards(region_id, c.money, c.rep), region_id = region_id, camp_id = c.id,
        }
    end
    return out
end

local function bountyOffers(region_id, d)
    local out = {}
    for _, b in ipairs(d.bounties or {}) do
        out[#out + 1] = {
            key = 'bounty_' .. b.key, title = 'Wanted: ' .. b.name,
            text = b.name .. ' is holed up near here. Bring them down.',
            on = M.BOUNTY_EVENT, rewards = rewards(region_id, b.money, b.rep), region_id = region_id,
            -- the rest rides along to accept only (spawn setup)
            name = b.name, model = b.model, coords = b.coords, heading = b.heading,
        }
    end
    return out
end

local BUILDERS = { hunt_request = huntOffers, camp_clear = campOffers, bounty = bountyOffers }

---Offer templates of one job type for a region (hooks.offers). Fresh tables every call; unknown region = {}.
function M.offers(job_type, region_id)
    local build, d = BUILDERS[job_type], M.DATA[region_id]
    if not build or not d then return {} end
    return build(region_id, d)
end

---Tag of a bounty's spawn request (fh_core requestSpawn spec.tag). One live bounty per region + offer key.
function M.bountyTag(region_id, key) return M.BOUNTY_TAG_PREFIX .. region_id .. ':' .. key end

---The bounty offer of a region by offer key (the spawn setup is not stored in the job snapshot, so a re-arm after a
---restart or a relog rebuilds it from the template). nil when the template is gone.
function M.bountyOffer(region_id, key)
    for _, o in ipairs(M.offers('bounty', region_id)) do
        if o.key == key then return o end
    end
    return nil
end

---Watched bounties whose ped is dead, as a sorted snapshot list. Taken before anything yields, so the caller can
---fire events and mutate `watch` afterwards without invalidating a traversal. isDead(w) -> boolean (may throw: that
---entry is skipped).
function M.collectDead(watch, isDead)
    local out = {}
    for _, w in pairs(watch) do
        local ok, dead = pcall(isDead, w)
        if ok and dead then out[#out + 1] = w end
    end
    table.sort(out, function(a, b) return a.tag < b.tag end)
    return out
end

---Watched bounties owned by player `src` (they left: despawn these, credit nobody). Snapshot list, sorted.
function M.ownedBy(watch, src)
    local out = {}
    for _, w in pairs(watch) do
        if w.src == src then out[#out + 1] = w end
    end
    table.sort(out, function(a, b) return a.tag < b.tag end)
    return out
end

-- The accepted-offer snapshot is the source of truth for what a job needs (it survives rotation and restarts).
local function snapOf(job_type, state)
    local snap = type(state) == 'table' and type(state.progress) == 'table' and state.progress.job or nil
    if type(snap) ~= 'table' or snap.job_type ~= job_type then return nil end
    return snap
end

---hooks.onEvent decision for a built-in job type. Called by intake.feed only for events that already credit
---state.citizenid (payload.citizenid or a listed participant) and are not quota echoes.
---  hunt_request / camp_clear: the offer's own event + where predicates, one progress per matching event.
---    camp_clear credit therefore comes from payload.participants (core idea-614) and from nothing else.
---  bounty: only the bounty watcher's event, naming the acceptor as payload.citizenid and this offer's key.
---    participants are ignored: nobody but the acceptor is paid.
---@return string|nil verdict
function M.verdict(job_type, eventName, payload, state)
    local snap = snapOf(job_type, state)
    if not snap or type(payload) ~= 'table' then return nil end
    if job_type == 'bounty' then
        if eventName ~= M.BOUNTY_EVENT then return nil end
        if payload.citizenid ~= state.citizenid or payload.offer_key ~= snap.key then return nil end
        return 'complete'
    end
    if eventName ~= snap.on then return nil end
    if not match().where(snap.where, payload) then return nil end
    return 'progress'
end

if GetCurrentResourceName then
    FhQuestsJobTypes = M
else
    return M
end

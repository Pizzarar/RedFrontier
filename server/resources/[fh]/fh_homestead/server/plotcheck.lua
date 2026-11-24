-- fh_homestead /fh_plotcheck [plotId|all] (homestead-03 H16): admin-only report that lets the owner verify every placeholder
-- plot/lot coordinate in one sitting. Round trip: the admin runs the command -> the server picks the plots and asks THAT
-- client to probe them (ground z through the world-01 D probe FhSnap.groundZAt, water at the centre) -> the client reports
-- back with a one-shot token -> the server adds the pure checks (overlap at max radius, nearest town) and prints the report.
-- Math, classification and formatting live in shared/plotcheck.lua (FhPlotCheck, specced). This file only owns the session:
-- one pending check per admin, a missing ped is refused up front, and a client that never answers times out with a message.
-- Read-only: nothing here writes the DB or touches claims. Own file on purpose (server/main.lua is shared with other blocks).
local cfg = FhHomesteadConfig
local pc = FhPlotCheck

local pending = {} -- src -> { token, ids = {...}, expires = ms }
local seq = 0

local function say(src, msg)
    if src == 0 then print('[fh_homestead] ' .. msg) else TriggerClientEvent('chat:addMessage', src, { args = { 'fh', msg } }) end
end

local function sayAndLog(src, msg)
    say(src, msg)
    if src ~= 0 then print('[fh_homestead] plotcheck: ' .. msg) end
end

local SUMMARY_MAX = 8 -- problem plot ids named in the in-game chat summary of a multi-plot run

local function regionsTable() return FhRegions and FhRegions.regions or nil end

local function begin(src, arg)
    if src == 0 then return false, 'run it in game: the probe needs your client (stand near the plots for best results)' end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false, 'no player ped yet (finish spawning, then retry)' end
    if pending[src] then return false, 'a plot check is already running for you' end
    local ids, err = pc.targets(cfg.plots, arg)
    if not ids then return false, err == 'unknown_plot' and ('unknown plot id: ' .. tostring(arg)) or tostring(err) end
    if #ids == 0 then return false, 'no plots configured' end
    seq = seq + 1
    local token = ('%d:%d'):format(seq, GetGameTimer())
    local list = {}
    for _, id in ipairs(ids) do
        local p = cfg.plots[id]
        list[#list + 1] = { id = id, x = p.center.x + 0.0, y = p.center.y + 0.0, z = p.center.z + 0.0, class = p.class, verified = p.verified }
    end
    local session = { token = token, ids = ids }
    pending[src] = session
    local budget = pc.TIMEOUT_BASE_MS + pc.PER_PLOT_MS * #ids
    SetTimeout(budget, function()
        if pending[src] == session then
            pending[src] = nil
            sayAndLog(src, ('fh_plotcheck: no report from your client after %d s (left the server, or the probe stalled); run it again'):format(budget // 1000))
        end
    end)
    TriggerClientEvent('fh:homestead:plotcheck:probe', src, token, list)
    return true, #ids
end

lib.addCommand('fh_plotcheck', {
    help = 'Admin: check plot/lot coords (ground z, water, overlap, nearest town): /fh_plotcheck [plotId|all]',
    restricted = 'group.admin',
}, function(src, args, raw)
    local arg = tostring(raw or ''):match('^%S+%s+(%S+)') or 'all'
    local ok, res = begin(src, arg)
    if ok then
        say(src, ('fh_plotcheck: probing %d plot(s), up to %d s (an unstreamed plot waits the full 2 s probe); the report follows (the probe only sees ground near you)'):format(res, pc.etaSeconds(res)))
    else
        say(src, 'fh_plotcheck: ' .. tostring(res))
    end
end)

RegisterNetEvent('fh:homestead:plotcheck:result', function(token, raw)
    local src = source
    local session = pending[src]
    if not session or type(token) ~= 'string' or token ~= session.token then return end -- not asked / stale / forged
    pending[src] = nil
    local results = pc.cleanResults(cfg.plots, raw)
    local opts = { baseSafeRadius = cfg.baseSafeRadius, regions = regionsTable() }
    local reports = {}
    for _, id in ipairs(session.ids) do reports[#reports + 1] = pc.report(cfg.plots, id, results[id], opts) end
    local multi = #reports > 1
    -- A single plot prints in full in chat (and the console). A multi-plot run prints the full blocks to the console
    -- only (one chat:addMessage per line would flood the admin's chat: ~5 lines x 65 plots) and sends a capped summary
    -- to chat, as fh_dump does (fh_core/server/admin.lua).
    for _, r in ipairs(reports) do
        local head = r.head .. (r.flags > 0 and (' - ' .. r.flags .. ' issue(s)') or ' - OK')
        if multi then
            print('[fh_homestead] plotcheck: ' .. head)
            for _, line in ipairs(r.lines) do print('[fh_homestead] plotcheck:    ' .. line) end
        else
            sayAndLog(src, head)
            for _, line in ipairs(r.lines) do sayAndLog(src, '   ' .. line) end
        end
    end
    if multi then
        for _, line in ipairs(pc.summary(reports, SUMMARY_MAX)) do say(src, line) end
        say(src, 'fh_plotcheck: full per-plot report in the server console (lines starting "[fh_homestead] plotcheck:")')
    end
end)

AddEventHandler('playerDropped', function() pending[source] = nil end)

-- Pure rules for private-server access (server/access.lua): first-joiner auto-admin and the friend allowlist.
-- No natives, no ox_lib: specced in spec/access_rules_spec.lua. The server file only wires natives/io into onConnect.
--
-- Principals (server.cfg wires them; rsg-core reads the ace through RSGConfig.Server.WhitelistPermission):
--   group.admin       owner; admins.cfg holds `add_principal identifier.license:<hash> group.admin`
--   group.fh_allowlist  friends; allowlist.cfg holds `add_principal identifier.<license|discord>:<x> group.fh_allowlist`
--   ace fh.allowlist    granted to group.fh_allowlist; group.admin inherits group.fh_allowlist
local M = {}

M.ADMIN_GROUP = 'group.admin'
M.ALLOW_GROUP = 'group.fh_allowlist'
M.ALLOW_ACE = 'fh.allowlist'
M.REJECT_MESSAGE = 'This is a private server and you are not on its allowlist. Ask the owner to add you: they can see your ID in the server console.'

-- Convar truthiness: '1' or 'true' (case-insensitive). Anything else, including nil, is off.
function M.flag(v)
    v = tostring(v or ''):lower()
    return v == '1' or v == 'true'
end

-- Normalises an identifier for add_principal. Accepts `license:<hex>`, a bare hex hash (taken as a license) or
-- `discord:<digits>`. The strict charset is the security boundary: the result is pasted into ExecuteCommand.
-- Returns 'license:<lowercase hex>' / 'discord:<digits>', or nil, '<error code>'.
function M.parseIdentifier(s)
    if type(s) ~= 'string' then return nil, 'fh_bad_identifier' end
    s = s:match('^%s*(.-)%s*$')
    local kind, value = s:match('^(%a+):(.*)$')
    if not kind then kind, value = 'license', s end
    kind = kind:lower()
    if kind == 'license' then
        if #value >= 32 and #value <= 64 and value:match('^%x+$') then return 'license:' .. value:lower() end
    elseif kind == 'discord' then
        if #value >= 15 and #value <= 22 and value:match('^%d+$') then return 'discord:' .. value end
    end
    return nil, 'fh_bad_identifier'
end

function M.principalLine(identifier, group)
    return ('add_principal identifier.%s %s'):format(identifier, group)
end

local function lines(text)
    local out = {}
    for l in (tostring(text or '') .. '\n'):gmatch('([^\n]*)\n') do out[#out + 1] = (l:gsub('\r$', '')) end
    return out
end

-- Is this exact principal line present as an active (non-comment) line? Whitespace-insensitive.
function M.hasLine(text, line)
    local want = line:gsub('%s+', ' ')
    for _, l in ipairs(lines(text)) do
        local norm = l:match('^%s*(.-)%s*$'):gsub('%s+', ' ')
        if norm == want then return true end
    end
    return false
end

-- Does an admins.cfg text grant group.admin to anyone? Comments (# or //) do not count.
function M.hasAdminLine(text)
    for _, l in ipairs(lines(text)) do
        if l:match('^%s*add_principal%s+identifier%.%S+%s+group%.admin%s*$') then return true end
    end
    return false
end

-- What to write to append `line` to a file whose current text is `text` (idempotent: nil when already present).
function M.appendText(text, line)
    if M.hasLine(text, line) then return nil end
    text = tostring(text or '')
    local sep = (text ~= '' and not text:match('\n$')) and '\n' or ''
    return sep .. line .. '\n'
end

-- Player names are client-controlled: strip control characters (no forged console lines) and cap the length.
function M.safeName(name)
    local s = tostring(name or ''):gsub('%c', ' '):gsub('%s+', ' '):match('^%s*(.-)%s*$')
    if #s > 32 then s = s:sub(1, 32) end
    return s ~= '' and s or '?'
end

-- The single console line for a rejected connect. ids = { license = 'license:..', discord = 'discord:..' }.
function M.rejectLine(name, ids)
    local parts = { 'allowlist: rejected', M.safeName(name) }
    parts[#parts + 1] = ids.license or 'license:none'
    if ids.discord then parts[#parts + 1] = ids.discord end
    return table.concat(parts, ' ')
end

function M.grantLine(license)
    return 'granted group.admin to ' .. license
end

-- Auto-admin state: { locked = bool (an admin line is persisted), pending = 'license:..' or nil (granted live,
-- not yet persisted) }. Only a persisted grant locks; until then the same license is retried and nobody else is
-- granted (so a friend joining after a failed write never becomes admin).
-- Returns the license to grant/persist now, or nil.
function M.grantTarget(state, convars, license)
    if not (M.flag(convars.fh_dev) and M.flag(convars.fh_dev_autoadmin)) then return nil end
    if state.locked then return nil end
    if state.pending then return state.pending end
    return license
end

-- io: { execute(cmd), persist(line) -> bool (write verified), isAllowed() -> bool (rsg-core's whitelist ace),
--       log(msg) }.  ctx: { license, discord, name, whitelistOn }.  Mutates state.
-- Order: grant (execute + persist) runs to completion BEFORE the allowlist check, so the first joiner passes it.
-- Returns { allowed = bool, granted = license|nil, line = reject console line|nil }.
function M.onConnect(state, convars, ctx, io)
    local result = { allowed = true }
    local license = ctx.license and M.parseIdentifier(ctx.license)
    if license and not license:match('^license:') then license = nil end
    local target = license and M.grantTarget(state, convars, license)
    if target then
        local line = M.principalLine(target, M.ADMIN_GROUP)
        if target == license then io.execute(line) end
        if io.persist(line) then
            state.locked, state.pending = true, nil
            if target == license then result.granted = target end
            io.log(M.grantLine(target)) -- printed once: only when the lock engages
        else
            state.pending = target
            if target == license then result.granted = target end
            io.log('autoadmin: could not write admins.cfg; ' .. target .. ' is admin until restart, retrying on next join')
        end
    end
    if ctx.whitelistOn and not io.isAllowed() then
        local discord = ctx.discord and M.parseIdentifier(ctx.discord)
        result.allowed = false
        result.line = M.rejectLine(ctx.name, { license = license, discord = discord })
        io.log(result.line)
    end
    return result
end

if GetCurrentResourceName then
    FhAccessRules = M
else
    return M
end

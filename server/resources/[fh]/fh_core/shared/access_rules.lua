-- Pure rules for private-server access (server/access.lua): first-joiner auto-admin and the friend allowlist.
-- No natives, no ox_lib: specced in spec/access_rules_spec.lua. The server file only wires natives/io into onConnect.
--
-- Principals (server.cfg wires them; rsg-core reads the ace through RSGConfig.Server.WhitelistPermission):
--   group.admin       owner; admins.cfg holds `add_principal identifier.license:<hash> group.admin`
--   group.fh_allowlist  friends; allowlist.cfg holds `add_principal identifier.<license|discord>:<x> group.fh_allowlist`
--   ace fh.allowlist    granted to group.fh_allowlist; group.admin inherits group.fh_allowlist
--
-- Durable store: fh_core/access.txt (gitignored), read/written with LoadResourceFile/SaveResourceFile, NOT Lua io
-- (io on the server dir failed live on Windows). One entry per line, `admin license:<hex>` / `allow <identifier>`,
-- `#` comments. Every entry passes parseIdentifier before it can reach ExecuteCommand. admins.cfg / allowlist.cfg
-- stay owner-editable overrides (server.cfg execs them); fh_core only best-effort appends to them.
local M = {}

M.STORE_FILE = 'access.txt'
M.ADMIN_ACE = 'command' -- server.cfg: add_ace group.admin command allow (held by admins only)

M.ADMIN_GROUP = 'group.admin'
M.ALLOW_GROUP = 'group.fh_allowlist'
M.ALLOW_ACE = 'fh.allowlist'

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

-- The active part of a cfg line: a `#` or `//` comment (whole-line or trailing) is dropped, whitespace collapsed.
-- Identifiers here are hex/digits only, so neither marker can occur inside a principal line.
local function active(l)
    l = l:gsub('#.*$', ''):gsub('//.*$', '')
    return (l:match('^%s*(.-)%s*$'):gsub('%s+', ' '))
end

-- Is this exact principal line present as an active (non-comment) line? Whitespace- and trailing-comment-insensitive.
function M.hasLine(text, line)
    local want = active(line)
    for _, l in ipairs(lines(text)) do
        if active(l) == want then return true end
    end
    return false
end

-- Does an admins.cfg text grant group.admin to anyone? Comments (# or //, whole-line or trailing) do not count.
function M.hasAdminLine(text)
    for _, l in ipairs(lines(text)) do
        if active(l):match('^add_principal identifier%.%S+ group%.admin$') then return true end
    end
    return false
end

-- Post-write verification: `after` is the file re-read after the append (nil = could not read it back). Only a
-- successful re-read that contains the line counts as persisted.
function M.persistVerified(after, line)
    return after ~= nil and M.hasLine(after, line)
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

local STORE_HEADER = '# fh_core access store (gitignored; written by fh_core). One entry per line:\n'
    .. '#   admin license:<hash>   owner (group.admin), re-granted at every start\n'
    .. '#   allow license:<hash>   friend (group.fh_allowlist); also allow discord:<id>\n'
    .. '# Delete a line and restart to revoke (also delete it from admins.cfg / allowlist.cfg if it is there).\n'

-- Parses the store text (nil = missing -> empty store). Returns { admins = {ids}, allow = {ids}, bad = {{line=n,
-- kind='admin'|'allow'|'?'}} }. Admin entries must be licenses. Invalid entries never reach `admins`/`allow`.
function M.parseStore(text)
    local store = { admins = {}, allow = {}, bad = {} }
    local seen = {}
    for n, l in ipairs(lines(text)) do
        local a = active(l)
        if a ~= '' then
            local kind, raw = a:match('^(%a+) (%S+)$')
            local id = raw and M.parseIdentifier(raw)
            if kind == 'admin' and id and id:match('^license:') then
                if not seen['admin ' .. id] then store.admins[#store.admins + 1] = id end
                seen['admin ' .. id] = true
            elseif kind == 'allow' and id then
                if not seen['allow ' .. id] then store.allow[#store.allow + 1] = id end
                seen['allow ' .. id] = true
            else
                local k = (kind == 'admin' or kind == 'allow') and kind or (a:match('^admin') and 'admin') or '?'
                store.bad[#store.bad + 1] = { line = n, kind = k }
            end
        end
    end
    return store
end

-- Adds a validated entry. kind 'admin' (license only) or 'allow'. Returns true when added, false when already there,
-- nil + error code when the identifier is invalid.
function M.storeAdd(store, kind, identifier)
    local id = M.parseIdentifier(identifier)
    if not id or (kind == 'admin' and not id:match('^license:')) or (kind ~= 'admin' and kind ~= 'allow') then
        return nil, 'fh_bad_identifier'
    end
    local list = kind == 'admin' and store.admins or store.allow
    for _, x in ipairs(list) do if x == id then return false end end
    list[#list + 1] = id
    return true
end

function M.storeHas(store, kind, identifier)
    local id = M.parseIdentifier(identifier)
    for _, x in ipairs((kind == 'admin' and store.admins) or (kind == 'allow' and store.allow) or {}) do
        if x == id then return true end
    end
    return false
end

-- Serialises the valid entries (bad lines are dropped on the next write; they were already logged at boot).
function M.storeText(store)
    local out = { STORE_HEADER }
    for _, id in ipairs(store.admins) do out[#out + 1] = 'admin ' .. id .. '\n' end
    for _, id in ipairs(store.allow) do out[#out + 1] = 'allow ' .. id .. '\n' end
    return table.concat(out)
end

-- The add_principal lines to execute at resource start. Identifiers are re-validated here (defence in depth).
function M.bootLines(store)
    local out = {}
    for _, id in ipairs(store.admins) do
        local v = M.parseIdentifier(id)
        if v and v:match('^license:') then out[#out + 1] = M.principalLine(v, M.ADMIN_GROUP) end
    end
    for _, id in ipairs(store.allow) do
        local v = M.parseIdentifier(id)
        if v then out[#out + 1] = M.principalLine(v, M.ALLOW_GROUP) end
    end
    return out
end

-- Boot state. content = admins.cfg text (nil = missing/unreadable); store = parseStore(access.txt) or nil.
-- Lock rule: claimed = the store has an owner, OR the store has a malformed `admin` line (fail closed), OR admins.cfg
-- is readable and has an active admin line. An unreadable admins.cfg alone FAILS CLOSED (store == nil); with a store
-- passed, the store decides (no owner there -> unlocked, guarded at connect by onConnect's adminExists evidence).
-- Returns state, console line|nil.
function M.initialState(content, store)
    if store then
        for _, b in ipairs(store.bad) do
            if b.kind == 'admin' then
                return { locked = true, pending = nil, badStore = true },
                    'autoadmin: ERROR fh_core/' .. M.STORE_FILE .. ' line ' .. b.line .. ' is a malformed admin entry; '
                    .. 'auto-admin is OFF. Fix the line (admin license:<hash>) and restart the server.'
            end
        end
        if #store.admins > 0 then return { locked = true, pending = nil }, nil end
        if content == nil then
            return { locked = false, pending = nil, unreadable = true },
                'autoadmin: admins.cfg unreadable; using fh_core/' .. M.STORE_FILE .. ' (no owner yet: the first joiner '
                .. 'becomes admin unless an admin is already connected).'
        end
        return { locked = M.hasAdminLine(content), pending = nil }, nil
    end
    if content == nil then
        return { locked = true, pending = nil, unreadable = true },
            'autoadmin: ERROR cannot read admins.cfg; auto-admin is OFF, nobody will be granted group.admin. '
            .. "Run tools/start-server.ps1 (or the first-run) to create it, or fix the file's permissions, then restart the server."
    end
    return { locked = M.hasAdminLine(content), pending = nil }, nil
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

-- io: { execute(cmd), persist(line, license) -> bool (write verified), isAllowed() -> bool (rsg-core's whitelist ace),
--       log(msg), adminExists() -> bool (optional: the joiner or an online player already holds M.ADMIN_ACE) }.
--       ctx: { license, discord, name, whitelistOn }.  Mutates state.
-- adminExists is evidence of an earlier claim (e.g. the store was lost but admins.cfg was exec'd): it locks instead
-- of granting a new first joiner. Not checked while a grant is pending (that admin is our own live grant).
-- Order: grant (execute + persist) runs to completion BEFORE the allowlist check, so the first joiner passes it.
-- Returns { allowed = bool, granted = license|nil, line = reject console line|nil }.
function M.onConnect(state, convars, ctx, io)
    local result = { allowed = true }
    local license = ctx.license and M.parseIdentifier(ctx.license)
    if license and not license:match('^license:') then license = nil end
    local target = license and M.grantTarget(state, convars, license)
    if target and not state.pending and io.adminExists and io.adminExists() then
        state.locked, target = true, nil
        io.log('autoadmin: an existing admin is connected; auto-admin locked, nobody granted')
    end
    if target then
        local line = M.principalLine(target, M.ADMIN_GROUP)
        if target == license then io.execute(line) end
        if io.persist(line, target) then
            state.locked, state.pending = true, nil
            if target == license then result.granted = target end
            io.log(M.grantLine(target)) -- printed once: only when the lock engages
        else
            state.pending = target
            if target == license then result.granted = target end
            io.log('autoadmin: could not save the admin claim (fh_core/' .. M.STORE_FILE .. '); ' .. target
                .. ' is admin until restart, retrying on next join')
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

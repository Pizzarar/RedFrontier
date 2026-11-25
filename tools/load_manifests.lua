-- load_manifests.lua — the Lua half of the G5 "load-all manifests" gate.
--
-- The Python driver (tools/load_manifests.py) walks server/server.cfg, parses every fxmanifest.lua,
-- expands globs and @resource/file includes, and hands this module a plan. This module then loads every
-- server+shared file (and every client+shared file, in a separate client-side state) of each resource in
-- server.cfg order, with the chunk argument `...` passed as a NUMBER (what FXServer does, and what the
-- old specs got wrong — nil), stubbing natives/MySQL/json and enforcing STRICT exports.
--
-- It does not run handlers and does not invoke cross-resource exports: it only answers "does every file
-- load the way FXServer loads it, and does every load-time export reference resolve to a registered or
-- declared export?". Findings are returned to Python, which applies the known-findings allowlist.

local M = {}

-- Synthetic module source returned by LoadResourceFile for system resources (ox_lib/oxmysql). Their real
-- imports use CfxLua `?.`/`+=` that stock Lua 5.4 cannot parse, so instead of loading them we hand back an
-- autovivifying stub: `lib.callback` / `lib.notify` / … resolve to a table whose fields are callable no-ops.
local STUB_MODULE = [[
local function _s()
    return setmetatable({}, {
        __index = function(_, k) return _s() end,
        __call = function() return nil end,
    })
end
return _s()
]]

-- A value that is simultaneously a callable function and an indexable table. Used for every native /
-- API we do not need to model: reading it yields another stub, calling it yields nil.
local function stub()
    return setmetatable({}, {
        __index = function(_, k)
            return stub()
        end,
        __call = function()
            return nil
        end,
    })
end

-- Minimal but real JSON encoder (the decoder below is pure Lua too).
local ESC = {
    ['\\'] = '\\\\', ['"'] = '\\"', ['\b'] = '\\b', ['\f'] = '\\f',
    ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t',
}
local function json_encode(v)
    local t = type(v)
    if v == nil then return 'null' end
    if t == 'boolean' then return v and 'true' or 'false' end
    if t == 'number' then
        if v ~= v or v == math.huge or v == -math.huge then return 'null' end
        if math.type(v) == 'integer' then return tostring(v) end
        return string.format('%.14g', v)
    end
    if t == 'string' then
        return '"' .. v:gsub('[%z\1-\31\\"]', function(c)
            return ESC[c] or string.format('\\u%04x', c:byte())
        end) .. '"'
    end
    if t == 'table' then
        local isArr, max, n = true, 0, 0
        for k in pairs(v) do
            if type(k) ~= 'number' then isArr = false break end
            if k > max then max = k end
            n = n + 1
        end
        if isArr and max == n then
            local parts = {}
            for i = 1, n do parts[i] = json_encode(v[i]) end
            return '[' .. table.concat(parts, ',') .. ']'
        end
        local keys, parts = {}, {}
        for k in pairs(v) do keys[#keys + 1] = tostring(k) end
        table.sort(keys)
        for _, k in ipairs(keys) do parts[#parts + 1] = json_encode(k) .. ':' .. json_encode(v[k]) end
        return '{' .. table.concat(parts, ',') .. '}'
    end
    return 'null'
end

-- Minimal but real JSON decoder (returns real Lua tables, so resource scripts that json.decode() get a
-- usable value rather than lupa's opaque Python-object wrapper).
local function json_decode(s)
    s = tostring(s or 'null')
    local pos = 1
    local function ws() while pos <= #s and s:sub(pos, pos):match('%s') do pos = pos + 1 end end
    local parseObject, parseArray, parseString, parseValue
    parseString = function()
        pos = pos + 1
        local out = {}
        while true do
            local c = s:sub(pos, pos)
            if c == '"' then pos = pos + 1 break end
            if c == '\\' then
                pos = pos + 1
                local e = s:sub(pos, pos)
                if e == 'n' then out[#out + 1] = '\n' elseif e == 't' then out[#out + 1] = '\t'
                elseif e == 'r' then out[#out + 1] = '\r' elseif e == 'b' then out[#out + 1] = '\b'
                elseif e == 'f' then out[#out + 1] = '\f' elseif e == 'u' then
                    out[#out + 1] = utf8.char(tonumber(s:sub(pos + 1, pos + 4), 16)); pos = pos + 4
                else out[#out + 1] = e end
                pos = pos + 1
            else
                out[#out + 1] = c
                pos = pos + 1
            end
        end
        return table.concat(out)
    end
    parseObject = function()
        pos = pos + 1
        local t = {}
        ws()
        if s:sub(pos, pos) == '}' then pos = pos + 1 return t end
        while true do
            ws()
            local k = parseString()
            ws(); assert(s:sub(pos, pos) == ':', 'expected :'); pos = pos + 1
            t[k] = parseValue()
            ws()
            local c = s:sub(pos, pos); pos = pos + 1
            if c == '}' then return t end
            assert(c == ',', 'expected , or }')
        end
    end
    parseArray = function()
        pos = pos + 1
        local t, i = {}, 1
        ws()
        if s:sub(pos, pos) == ']' then pos = pos + 1 return t end
        while true do
            ws()
            t[i] = parseValue(); i = i + 1
            ws()
            local c = s:sub(pos, pos); pos = pos + 1
            if c == ']' then return t end
            assert(c == ',', 'expected , or ]')
        end
    end
    parseValue = function()
        ws()
        local c = s:sub(pos, pos)
        if c == '{' then return parseObject() end
        if c == '[' then return parseArray() end
        if c == '"' then return parseString() end
        if s:sub(pos, pos + 3) == 'true' then pos = pos + 4 return true end
        if s:sub(pos, pos + 4) == 'false' then pos = pos + 5 return false end
        if s:sub(pos, pos + 3) == 'null' then pos = pos + 4 return nil end
        local start = pos
        if s:sub(pos, pos) == '-' then pos = pos + 1 end
        while s:sub(pos, pos):match('[0-9]') do pos = pos + 1 end
        if s:sub(pos, pos) == '.' then
            pos = pos + 1
            while s:sub(pos, pos):match('[0-9]') do pos = pos + 1 end
        end
        if s:sub(pos, pos):match('[eE]') then
            pos = pos + 1
            if s:sub(pos, pos):match('[+-]') then pos = pos + 1 end
            while s:sub(pos, pos):match('[0-9]') do pos = pos + 1 end
        end
        return tonumber(s:sub(start, pos - 1))
    end
    return parseValue()
end

-- Extract the first `:NN:` line number from a Lua error message (load errors and runtime errors both
-- carry `name:line: message` when the chunk has a name).
local function errline(msg)
    if type(msg) ~= 'string' then return nil end
    local n = msg:match(':(%d+):')
    return n and tonumber(n) or nil
end

function M.run(plan)
    local real_G = _G
    local findings = {}
    -- Exports are per side, like FXServer: a client script cannot call a server-only export.
    local registry = { server = {}, client = {} }  -- side -> resName -> { exportName = true }
    local declared = { server = {}, client = {} }  -- side -> resName -> { exportName = true } (manifest)
    local started_res = {}                         -- resName -> true once its load has begun (cfg order)
    local providers = {}  -- alias -> realRes  (from `provide 'x'`)
    local known_res = {}  -- resName -> true (ensured or provided)
    local system_res = {} -- resName -> true (ox_lib/oxmysql: bodies skipped, exports autovivify)
    local current = { file = '?' }

    for _, res in ipairs(plan.resources) do
        known_res[res.name] = true
        for _, p in ipairs(res.provides or {}) do providers[p] = res.name end
        local ds, dc = {}, {}
        for _, e in ipairs(res.server_exports or {}) do ds[e] = true end
        for _, e in ipairs(res.client_exports or {}) do dc[e] = true end
        declared.server[res.name] = ds
        declared.client[res.name] = dc
        if res.system then system_res[res.name] = true end
    end
    for p in pairs(providers) do known_res[p] = true end

    -- resource name -> directory, so LoadResourceFile (used by rsg-core's `require` and locale loading)
    -- can read real file content. System resources (ox_lib/oxmysql) return nil so their imports — which
    -- use CfxLua `?.`/`+=` that stock Lua 5.4 cannot parse — are never pulled in.
    local res_dirs = {}
    for _, res in ipairs(plan.resources) do
        if res.dir then res_dirs[res.name] = res.dir end
    end
    for _, res in ipairs(plan.resources) do
        for _, p in ipairs(res.provides or {}) do res_dirs[p] = res.dir end
    end

    local function add(kind, res, file, line, msg)
        findings[#findings + 1] = { kind = kind, res = res, file = file, line = line, msg = msg }
    end

    -- ---- STRICT exports ----
    local deferred = {} -- declared-but-not-yet-registered export calls, resolved after all resources load

    local function make_call(caller, target, fn, side)
        return function(...)
            if system_res[target] then
                return (fn == 'hasLoaded') and true or stub() -- ox_lib's init.lua requires hasLoaded()==true
            end
            local r = registry[side][target]
            if r and r[fn] ~= nil then return stub() end -- registered: ok; return a stub so callers can keep going
            if known_res[target] and declared[side][target] and declared[side][target][fn] then
                -- Declared in the manifest but not registered yet (a later file in this resource, or a
                -- later resource in cfg order). Resolve after all resources load.
                deferred[#deferred + 1] = { caller = caller, target = target, fn = fn, file = current.file, side = side }
                return stub()
            end
            local info = debug.getinfo(2, 'l')
            add('unresolved_export', caller, current.file,
                info and info.currentline or nil,
                ("exports['%s']:%s has no such %s export (not registered, not declared)"):format(target, fn, side))
            return stub()
        end
    end

    local function make_target(caller, target, side)
        return setmetatable({}, { __index = function(_, fn)
            if type(fn) ~= 'string' then return nil end
            return make_call(caller, target, fn, side)
        end })
    end

    local function make_exports(res_name, side)
        return setmetatable({}, {
            __call = function(_, name, fn)
                local r = registry[side][res_name]
                if not r then r = {} registry[side][res_name] = r end
                r[name] = fn or true
            end,
            __index = function(_, target)
                if type(target) ~= 'string' then return nil end
                return make_target(res_name, providers[target] or target, side)
            end,
        })
    end

    -- ---- realistic env for one resource/side ----
    local function make_env(res_name, side)
        local env = setmetatable({
            exports = make_exports(res_name, side),
            GetCurrentResourceName = function() return res_name end,
            GetInvokingResource = function() return nil end,
            IsDuplicityVersion = function() return side == 'server' end,
            GetGameName = function() return 'rdr3' end,
            GetResourceState = function(name)
                if started_res[name] then return 'started' end -- only resources already loaded (cfg order)
                if known_res[name] then return 'stopped' end   -- ensured later in server.cfg
                return 'missing'
            end,
            GetNumResourceMetadata = function() return 0 end,
            GetResourceMetadata = function() return '' end,
            GetNumResources = function() return 0 end,
            GetResourceByFindIndex = function() return nil end,
            GetInstanceId = function() return 0 end,
            GetGameTimer = function() return 0 end,
            GetConvar = function(_, default) return default or '' end,
            GetConvarInt = function(_, default) return default or 0 end,
            LoadResourceFile = function(res, path)
                if system_res[res] then return STUB_MODULE end
                local dir = res_dirs[res]
                if not dir then return nil end
                local f = io.open(dir .. '/' .. path, 'rb')
                if not f then return nil end
                local c = f:read('*a')
                f:close()
                return c
            end,
            json = { decode = json_decode, encode = json_encode },
            msgpack = { setoption = stub(), pack = stub(), unpack = stub() },
            vector3 = function(x, y, z) return { x = x, y = y, z = z } end,
            vector2 = function(x, y) return { x = x, y = y } end,
            vector4 = function(x, y, z, w) return { x = x, y = y, z = z, w = w } end,
            source = -1,
            print = function() end, -- resources log at load; keep the gate output clean
            lib = stub(),
            MySQL = stub(),
            joaat = function(str)
                local h = 0
                str = tostring(str):lower()
                for i = 1, #str do
                    h = (h + str:byte(i)) & 0xFFFFFFFF
                    h = (h + (h << 10)) & 0xFFFFFFFF
                    h = (h ~ (h >> 6)) & 0xFFFFFFFF
                end
                h = (h + (h << 3)) & 0xFFFFFFFF
                h = (h ~ (h >> 11)) & 0xFFFFFFFF
                h = (h + (h << 15)) & 0xFFFFFFFF
                return h
            end,
            GetHashKey = function(s) return 0 end,
            GetResourcePath = function(name) return '/srv/resources/[x]/' .. tostring(name) end,
        }, { __index = function(_, k)
            local v = real_G[k]
            if v ~= nil then return v end
            -- Fh* module tables (FhQuestsJobTypes, FhRegions, ...) are plain globals set by an earlier file of
            -- the SAME resource; a read before it is set is a manifest-order bug, so yield nil like FXServer.
            if type(k) == 'string' and k:match('^Fh%u') then return nil end
            return stub()
        end })
        env._G = env
        return env
    end

    local function load_file(env, res_name, side, entry)
        local path, display = entry.path, entry.display
        if path == nil then
            add('missing_file', res_name, display, nil, 'path does not resolve (missing @include target or empty glob)')
            return
        end
        local f = io.open(path, 'rb')
        if not f then
            add('missing_file', res_name, display, nil, 'file does not exist on disk')
            return
        end
        local src = f:read('*a')
        f:close()
        src = src:gsub('`[%w_]+`', '0') -- CfxLua compile-time native hash literal -> 0 (as run-specs.py --syntax does)
        -- CfxLua compound assignment (`n += 1` etc.): stock Lua 5.4 has no such operator. The vendored
        -- rsg-core/rsg-target scripts use only the simple `ident` / `ident.field` lvalue form (and only
        -- `+=`), so rewrite `x += y` -> `x = x + y`. (Safe-navigation `?.` is left alone and reported as
        -- a known-skip; other compound operators would surface as their own load_error.)
        src = src:gsub('([%w_][%w_%.]*)%s*%+%s*=', function(lv)
            return lv .. ' = ' .. lv .. ' + '
        end)
        current.file = display
        local chunk, lerr = load(src, '@' .. display, 't', env)
        if not chunk then
            add('load_error', res_name, display, errline(lerr), tostring(lerr))
            return
        end
        local ok, rerr = pcall(chunk, 7) -- ... = 7 (a number, like FXServer; nil would hide the C0 bug)
        if not ok then
            add('top_error', res_name, display, errline(rerr), tostring(rerr))
        end
    end

    -- ---- load everything in cfg order ----
    local n_res, n_files, n_system = 0, 0, 0
    for _, res in ipairs(plan.resources) do
        n_res = n_res + 1
        started_res[res.name] = true
        for _, p in ipairs(res.provides or {}) do started_res[p] = true end
        if res.system then
            n_system = n_system + 1
        else
            local server_env = make_env(res.name, 'server')
            for _, e in ipairs(res.server or {}) do n_files = n_files + 1 load_file(server_env, res.name, 'server', e) end
            local client_env = make_env(res.name, 'client')
            for _, e in ipairs(res.client or {}) do n_files = n_files + 1 load_file(client_env, res.name, 'client', e) end
        end
    end

    -- ---- resolve deferred (declared-but-not-yet-registered) export calls ----
    for _, d in ipairs(deferred) do
        local r = registry[d.side][d.target]
        if not (r and r[d.fn] ~= nil) then
            add('unresolved_export', d.caller, d.file, nil,
                ("exports['%s']:%s was declared in the manifest but never registered by load time"):format(d.target, d.fn))
        end
    end

    return {
        resources = n_res,
        files = n_files,
        system_resources = n_system,
        findings = findings,
    }
end

-- Convenience for the Python driver: run the plan held in the `RF_PLAN` global (a real Lua table the
-- Python driver injects via lua.execute), returning a JSON string (findings + counts) it can json.loads().
function M.run_from_global()
    return json_encode(M.run(RF_PLAN))
end

load_manifests = M -- expose as a global for lupa (which discards a chunk's `return` value)
return M          -- expose as a return value for dofile() callers (the JT-bug spec)

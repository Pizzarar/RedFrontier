#!/usr/bin/env python3
"""G5 "load-all manifests" gate — the Python half.

Walks server/server.cfg `ensure` order, parses every resource's fxmanifest.lua, expands globs and
@resource/file includes, then hands the plan to tools/load_manifests.lua, which loads every server+shared
(and client+shared) script with the chunk argument `...` passed as a NUMBER, stubbing natives/MySQL/json
and enforcing STRICT exports.

Findings (load errors, top-level errors, unresolved exports, missing files) are compared against
tools/manifests-known.txt (kind|resource|file|msg-substring|reason). Known findings are reported but do
not fail the gate; unknown findings fail it. Exit 0 = every finding is known/explained.

Run standalone:
  python tools/load_manifests.py           (uses the RF venv if lupa is missing, like run-specs.py)
"""
import glob as globmod
import json
import os
import re
import sys

VENV_PY = os.path.expanduser('~/.venvs/rf/bin/python')
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RESOURCES_ROOT = os.path.join(ROOT, 'server', 'resources')
CFG_PATH = os.path.join(ROOT, 'server', 'server.cfg')
KNOWN_PATH = os.path.join(ROOT, 'tools', 'manifests-known.txt')

BACKTICK_HASH = re.compile(rb'`[^`\r\n]*`')

# Resources whose own script bodies are skipped (vendored, and/or use CfxLua extensions lupa's stock Lua
# 5.4 cannot parse, e.g. ox_lib's `?.`/`+=`, oxmysql's `dist/build.js` is JS). Their exports are stubbed
# autovivifying, and their `@ox_lib/init.lua` / `@oxmysql/lib/MySQL.lua` includes still load (pure Lua).
SYSTEM_RESOURCES = {'ox_lib', 'oxmysql'}


def _get_lua_mod():
    try:
        from lupa import lua54 as lua_mod
    except ImportError:
        if os.path.exists(VENV_PY) and os.path.abspath(sys.prefix) != os.path.dirname(os.path.dirname(VENV_PY)) \
                and not os.environ.get('RF_SPECS_REEXEC'):
            os.environ['RF_SPECS_REEXEC'] = '1'
            os.execv(VENV_PY, [VENV_PY] + sys.argv)
        sys.exit('load-manifests: needs lupa 2.x (pip install lupa, or use %s)' % VENV_PY)
    return lua_mod


def parse_cfg(cfg_path):
    """Return the ordered list of `ensure <name>` resources from server.cfg."""
    order = []
    with open(cfg_path, 'r', encoding='utf-8', errors='replace') as fh:
        for line in fh:
            line = line.split('#')[0].strip()
            m = re.match(r'^ensure\s+(\S+)', line)
            if m:
                order.append(m.group(1))
    return order


def resolve_resource(name, root=RESOURCES_ROOT):
    """Return the resource directory for `name`, or None."""
    for cat in ('[fh]', '[rsg]', '[spikes]'):
        d = os.path.join(root, cat, name)
        if os.path.isfile(os.path.join(d, 'fxmanifest.lua')):
            return d
    return None


# The manifest DSL is evaluated in a Lua sandbox whose DSL functions are plain LUA functions (not Python
# callables): lupa's Python-call adapter mishandles the `name 'str' { table }` sugar form that oxmysql's
# `convar_category` and rsg-chat's `chat_theme` use, but a Lua function handles it fine.
_MANIFEST_SETUP = """
__data = { shared_scripts={}, server_scripts={}, client_scripts={}, server_exports={}, client_exports={}, provides={} }
local function _cap(key)
    return function(...)
        local n = select('#', ...)
        for i = 1, n do
            local v = select(i, ...)
            if type(v) == 'string' then
                local t = __data[key] t[#t+1] = v
            elseif type(v) == 'table' then
                for j = 1, #v do
                    local e = v[j]
                    if type(e) == 'string' then local t = __data[key] t[#t+1] = e end
                end
            end
        end
    end
end
shared_scripts = _cap('shared_scripts')
server_scripts = _cap('server_scripts')
client_scripts = _cap('client_scripts')
server_exports = _cap('server_exports')
client_exports = _cap('client_exports')
provide = _cap('provides')
shared_script = _cap('shared_scripts')
server_script = _cap('server_scripts')
client_script = _cap('client_scripts')
-- No-ops return a function so the curried `convar_category 'OxMySQL' { ... }` / `chat_theme 'gtao' { ... }`
-- idiom (which parses as (convar_category('OxMySQL'))({...})) chains instead of calling nil.
local function _noop() return _noop end
fx_version = _noop
game = _noop
rdr3_warning = _noop
lua54 = _noop
description = _noop
version = _noop
name = _noop
author = _noop
license = _noop
repository = _noop
dependencies = _noop
ui_page = _noop
files = _noop
loadscreen = _noop
loadscreen_manual_shutdown = _noop
games = _noop
use_experimental_fxv2_oal = _noop
this_is_a_map = _noop
chat_theme = _noop
convar_category = _noop
"""


def parse_manifest(lua_mod, dir_path):
    """Evaluate a resource's fxmanifest.lua in a sandbox and capture its script/export/provide lists."""
    mpath = os.path.join(dir_path, 'fxmanifest.lua')
    with open(mpath, 'rb') as fh:
        src = BACKTICK_HASH.sub(b'0', fh.read()).decode('utf-8', 'replace')
    lua = lua_mod.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(_MANIFEST_SETUP)
    lua.execute(src)
    d = lua.globals().__data
    return {
        'shared_scripts': list(d['shared_scripts'].values()),
        'server_scripts': list(d['server_scripts'].values()),
        'client_scripts': list(d['client_scripts'].values()),
        'server_exports': list(d['server_exports'].values()),
        'client_exports': list(d['client_exports'].values()),
        'provides': list(d['provides'].values()),
    }


def expand_entry(entry, res_dir):
    """Expand one manifest script entry (a literal, a glob, or an @resource/file include).

    Returns a list of {path, display} dicts; path is None when the target/glob resolves to nothing.
    The resource directories live under `[fh]`/`[rsg]`, whose `[` `]` are glob magic chars, so the
    directory prefix is glob.escape()d and only the manifest entry's own pattern is treated as a glob.
    """
    if entry.startswith('@'):
        m = re.match(r'^@([^/\\]+)/(.+)$', entry)
        if not m:
            return []
        if m.group(1) in SYSTEM_RESOURCES:
            return []  # provided by the env as stubs (`lib`, `MySQL`); the real files use CfxLua syntax
        tdir = resolve_resource(m.group(1))
        if tdir is None:
            return [{'path': None, 'display': entry}]
        return _expand(tdir, m.group(2), entry)
    return _expand(res_dir, entry, entry)


def _expand(dirname, rel, display):
    if not globmod.has_magic(rel):
        base = os.path.join(dirname, rel)
        return [{'path': base, 'display': os.path.relpath(base, RESOURCES_ROOT)}]
    pattern = globmod.escape(dirname) + os.sep + rel
    matches = sorted(p for p in globmod.glob(pattern, recursive=True) if os.path.isfile(p))
    if not matches:
        return [{'path': None, 'display': display}]
    return [{'path': p, 'display': os.path.relpath(p, RESOURCES_ROOT)} for p in matches]


def build_plan(lua_mod):
    resources = []
    missing = []
    for name in parse_cfg(CFG_PATH):
        d = resolve_resource(name)
        entry = {
            'name': name,
            'system': name in SYSTEM_RESOURCES,
            'dir': d,
            'server': [], 'client': [],
            'server_exports': [], 'client_exports': [], 'provides': [],
        }
        if d is not None and not entry['system']:
            man = parse_manifest(lua_mod, d)
            entry['server_exports'] = man['server_exports']
            entry['client_exports'] = man['client_exports']
            entry['provides'] = man['provides']
            server_entries = man['shared_scripts'] + man['server_scripts']
            client_entries = man['shared_scripts'] + man['client_scripts']
            for e in server_entries:
                entry['server'].extend(expand_entry(e, d))
            for e in client_entries:
                entry['client'].extend(expand_entry(e, d))
        elif d is not None and entry['system']:
            # capture `provide` aliases (e.g. oxmysql provides mysql-async) so exports resolve
            man = parse_manifest(lua_mod, d)
            entry['provides'] = man['provides']
        else:
            # in server.cfg but no manifest on disk (typo or unvendored): a finding, never a silent system stub
            missing.append(name)
            continue
        resources.append(entry)
    return {'resources': resources, 'missing': missing}


def load_known(path):
    known = []
    if not os.path.exists(path):
        return known
    with open(path, 'r', encoding='utf-8', errors='replace') as fh:
        for line in fh:
            line = line.rstrip('\n')
            if not line.strip() or line.lstrip().startswith('#'):
                continue
            parts = line.split('|')
            if len(parts) < 4:
                continue
            kind, res, f, msgsub = parts[0].strip(), parts[1].strip(), parts[2].strip(), parts[3]
            reason = parts[4].strip() if len(parts) > 4 else ''
            known.append({'kind': kind, 'res': res, 'file': f, 'msgsub': msgsub, 'reason': reason})
    return known


def matches(known, f):
    return (f['kind'] == known['kind'] and f['res'] == known['res'] and f['file'] == known['file']
            and (not known['msgsub'] or known['msgsub'] in (f['msg'] or '')))


def to_lua(v):
    """Serialize a Python value (str/int/float/bool/None/list/dict) as a Lua table literal."""
    if v is None:
        return 'nil'
    if isinstance(v, bool):
        return 'true' if v else 'false'
    if isinstance(v, int):
        return str(v)
    if isinstance(v, float):
        return repr(v)
    if isinstance(v, str):
        return '"' + v.replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n').replace('\r', '\\r') + '"'
    if isinstance(v, (list, tuple)):
        return '{' + ', '.join(to_lua(x) for x in v) + '}'
    if isinstance(v, dict):
        return '{' + ', '.join('[%s] = %s' % (to_lua(k), to_lua(val)) for k, val in v.items()) + '}'
    raise TypeError('cannot serialize %r to Lua' % (v,))


def run_plan(lua_mod, plan):
    """Load a plan in a fresh Lua state; return the raw result dict (findings + counts)."""
    lua = lua_mod.LuaRuntime(unpack_returned_tuples=True)
    with open(os.path.join(ROOT, 'tools', 'load_manifests.lua'), 'r', encoding='utf-8') as fh:
        lua.execute(fh.read())
    lua.execute('RF_PLAN = ' + to_lua(plan))
    result = json.loads(lua.globals().load_manifests.run_from_global())
    for name in plan.get('missing', []):
        result['findings'].append({'kind': 'missing_resource', 'res': name, 'file': 'server/server.cfg', 'line': None,
                                   'msg': "ensure %s: no fxmanifest.lua found under [fh]/[rsg]/[spikes]" % name})
    return result


def run():
    lua_mod = _get_lua_mod()
    result = run_plan(lua_mod, build_plan(lua_mod))

    known = load_known(KNOWN_PATH)
    findings = result.get('findings', [])
    unknown = []
    for f in findings:
        if not any(matches(k, f) for k in known):
            unknown.append(f)

    lines = []
    lines.append('load-manifests: %d resources, %d files loaded, %d system resources skipped'
                 % (result.get('resources', 0), result.get('files', 0), result.get('system_resources', 0)))
    for f in findings:
        loc = f['file'] + ((':' + str(f['line'])) if f.get('line') else '')
        tag = 'known' if any(matches(k, f) for k in known) else 'UNKNOWN'
        reason = next((k['reason'] for k in known if matches(k, f)), '')
        lines.append('  [%s] %s: %s %s  %s%s' % (tag, f['kind'], f['res'], loc, f['msg'],
                                                 ('  (' + reason + ')') if reason else ''))
    lines.append('load-manifests: %d findings (%d known, %d unknown)'
                 % (len(findings), len(findings) - len(unknown), len(unknown)))
    return (0 if not unknown else 1), '\n'.join(lines)


def main():
    code, text = run()
    print(text)
    sys.exit(code)


if __name__ == '__main__':
    main()

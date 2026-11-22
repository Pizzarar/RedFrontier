#!/usr/bin/env python3
"""Run the pure-Lua specs in spec/ under embedded Lua 5.4 (lupa), or syntax-check Lua files.

  python tools/run-specs.py                 run every spec/*_spec.lua (fresh Lua state each)
  python tools/run-specs.py spec/x_spec.lua run the named specs
  python tools/run-specs.py --syntax DIR..  load() (compile only, no execution) every .lua under DIR

Specs stay runner-agnostic: they load spec/support/fh_prelude.lua, which uses busted's describe/it when
present and otherwise a tiny built-in runner that prints "N tests, M failures". Exit code 0 = all green.
Needs: pip install lupa (2.x ships Lua 5.4 as lupa.lua54).
"""
import glob
import os
import re
import sys

try:
    from lupa import lua54 as lupa_mod
except ImportError:
    sys.exit('run-specs: needs lupa 2.x (pip install lupa)')

BACKTICK_HASH = re.compile(rb'`[^`\r\n]*`')
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def run_spec(path):
    lua = lupa_mod.LuaRuntime(unpack_returned_tuples=True)
    out = []
    lua.globals().print = lambda *a: out.append('\t'.join(str(x) for x in a))
    # os.exit would kill this Python process: turn it into a tagged Lua error instead.
    run = lua.eval('''function(path)
        os.exit = function(code) error({ __fh_exit = code }, 0) end
        local ok, err = pcall(dofile, path)
        if ok then return 0, nil end
        if type(err) == 'table' and err.__fh_exit ~= nil then
            local c = err.__fh_exit
            return (c == true or c == 0 or c == nil) and 0 or 1, nil
        end
        return 2, tostring(err)
    end''')
    code, err = run(path.replace(os.sep, '/'))
    text = '\n'.join(out)
    m = re.search(r'(\d+) tests, (\d+) failures', text)
    tests, fails = (int(m.group(1)), int(m.group(2))) if m else (0, 0)
    if err:
        text += ('\n' if text else '') + 'ERROR ' + err
    if not m and not err:
        code, text = 2, text + '\nERROR no "N tests, M failures" summary (spec missing T.finish()?)'
    return code, tests, fails, text


def run_specs(paths):
    paths = paths or sorted(glob.glob(os.path.join(ROOT, 'spec', '*_spec.lua')))
    total = failed = 0
    worst = 0
    for p in paths:
        code, tests, fails, text = run_spec(os.path.abspath(p))
        total += tests
        failed += fails
        worst = max(worst, code)
        status = 'ok  ' if code == 0 else 'FAIL'
        print(f'{status} {os.path.relpath(p, ROOT)}: {tests} tests, {fails} failures')
        if code != 0:
            print('    ' + text.replace('\n', '\n    '))
    print(f'TOTAL {len(paths)} specs, {total} tests, {failed} failures')
    return 0 if worst == 0 and failed == 0 else 1


def syntax(dirs):
    lua = lupa_mod.LuaRuntime(unpack_returned_tuples=True)
    check = lua.eval('function(src, name) local f, e = load(src, "@" .. name, "t") return f ~= nil, e end')
    n = bad = 0
    for d in dirs:
        for p in sorted(glob.glob(os.path.join(glob.escape(d), '**', '*.lua'), recursive=True)):
            n += 1
            with open(p, 'rb') as fh:
                src = fh.read()
            # CfxLua extension: `name` is a compile-time joaat hash literal. Stock Lua 5.4 can't parse it,
            # so swap it for a number of the same shape. (Other CfxLua extensions, e.g. +=, still fail here.)
            src = BACKTICK_HASH.sub(b'0', src)
            ok, err = check(src, os.path.relpath(p, ROOT))
            if not ok:
                bad += 1
                print(f'SYNTAX {err}')
    print(f'syntax: {n} files, {bad} errors')
    return 1 if bad else 0


if __name__ == '__main__':
    args = sys.argv[1:]
    if args and args[0] == '--syntax':
        sys.exit(syntax(args[1:] or [os.path.join(ROOT, 'server', 'resources', '[fh]')]))
    sys.exit(run_specs(args))

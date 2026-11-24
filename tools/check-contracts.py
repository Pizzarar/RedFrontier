#!/usr/bin/env python3
"""Static cross-resource contract lint for server/resources (core-07 L1). Python 3 stdlib only.

Usage: python3 tools/check-contracts.py [--root server/resources] [--cfg server/server.cfg]
                                        [--allowlist tools/contracts-allowlist.txt] [--quiet]
Exit 0 = no non-allowlisted findings, 1 = findings, 2 = bad usage.

Rules
  exports  `exports.<res>:<fn>(`, `exports['<res>']:<fn>(`, `exports["<res>"]:<fn>(` calls in [fh] scripts.
           <res> must exist under <root>/*/ and be ensured/started in server.cfg (directly, or through a bracketed
           category `ensure [fh]`). For [fh] resources and any resource with a manifest, <fn> must be exported
           (`exports('fn', ...)`/`exports["fn"]` in a manifest-listed script, or fxmanifest server_exports/
           client_exports/exports) on the caller's side: a server script needs a server export, a client script a
           client export, a shared script either. Third-party resources (non-[fh]) only get the exists + ensured
           check (their exports are not enumerated). Skipped: dynamic names (`exports[GetCurrentResourceName()]`,
           `exports[var]`), calls inside comments.  Side of a file comes from fxmanifest server_scripts /
           client_scripts / shared_scripts (globs expanded); files in no manifest list are not scanned.
  events   `fh:*` names given as a string literal to TriggerEvent / TriggerServerEvent / TriggerClientEvent /
           TriggerLatentClientEvent (sender) and RegisterNetEvent / RegisterServerEvent / AddEventHandler / onNet
           (listener). Sender with no listener on the receiving side (TriggerEvent: same side; TriggerServerEvent:
           server; TriggerClientEvent: client; shared files count for either side) is a finding. A listener with
           no sender is a finding unless the name also appears as another string literal somewhere (e.g. a
           constant, a table `on = 'fh:x'`, an emit('fh:x') wrapper), which is treated as an indirect sender.
           Also treated as an indirect listener: any quoted 'fh:x' that appears in a `on = '..'` / `events`
           table field (quest/hook consumers). Dynamic names (`'fh:' .. x`) are not seen.
  items    item names in loot/shop/recipe style config rows: `{ name = 'x', chance|amount|... }` rows (a `name=`
           field accompanied by chance/amount/count/price on the same line) and `item = 'x'` / `item='x'` fields in
           any [fh] config.lua or data/*.lua. Must be defined: rsg-core shared/items.lua entries, or any [fh] table
           entry shaped `key = { label = ...` (item definitions: fh_core Items, resource `items = {}`, registerItems
           batches). Item names built dynamically are not seen. Weapons are expected in rsg items too.
  Documented events: a sender with no listener is fine when the event name appears in a *.md in the emitting resource
  (published bus events); `fh:<res>:ui_<action>` handlers count as sent by the fh_ui relay (fh:ui:action).
  Dynamic export loops `for k, fn in pairs(T) do exports(k, fn) end` export every `function T.X`/`T.X =` found in the
  resource. `provide 'x'` aliases (fh_inventory -> rsg-inventory) resolve to the providing resource. Dynamic-key item
  definitions `[cfg.feed.item] = { label = ...` define the value of `item` in any `feed = { ... }` table.
Allowlist: one entry per line `<rule>|<key>  # reason / idea id`. Keys: `exports|res:fn`, `events|fh:name`,
  `items|name`. Unused entries are reported as warnings.
"""
import argparse, glob, os, re, sys
from collections import defaultdict

SIDES = ('server', 'client')

def strip_comments(src):
    """Blank out Lua comments (keeps line count and string contents)."""
    out, i, n = [], 0, len(src)
    while i < n:
        c = src[i]
        if c == '-' and src.startswith('--', i):
            m = re.match(r'--\[(=*)\[', src[i:])
            if m:
                close = ']' + m.group(1) + ']'
                j = src.find(close, i)
                j = n if j < 0 else j + len(close)
                out.append(re.sub(r'[^\n]', ' ', src[i:j])); i = j; continue
            j = src.find('\n', i); j = n if j < 0 else j
            out.append(' ' * (j - i)); i = j; continue
        if c in '\'"':
            j = i + 1
            while j < n and src[j] != c and src[j] != '\n':
                j += 2 if src[j] == '\\' else 1
            out.append(src[i:j + 1]); i = j + 1; continue
        out.append(c); i += 1
    return ''.join(out)

def read(path):
    with open(path, encoding='utf-8', errors='replace') as f:
        return f.read()

def manifest_lists(text):
    """name -> list of quoted entries, for `name { ... }` blocks (comments stripped)."""
    text = strip_comments(text)
    res = defaultdict(list)
    for m in re.finditer(r'\b(\w+)\s*\{([^}]*)\}', text):
        res[m.group(1)] += re.findall(r'[\'"]([^\'"]+)[\'"]', m.group(2))
    for m in re.finditer(r'\b(\w+)\s+[\'"]([^\'"]+)[\'"]', text):
        res[m.group(1)].append(m.group(2))
    return res

class Resource:
    def __init__(self, path):
        self.path, self.name = path, os.path.basename(path)
        self.manifest = None
        for mf in ('fxmanifest.lua', '__resource.lua'):
            if os.path.isfile(os.path.join(path, mf)):
                self.manifest = manifest_lists(read(os.path.join(path, mf))); break
        self.files = {}      # relpath -> set of sides
        self.exports = {'server': set(), 'client': set()}
        if self.manifest is None:
            return
        for key, sides in (('server_scripts', ('server',)), ('client_scripts', ('client',)),
                           ('shared_scripts', SIDES), ('server_script', ('server',)),
                           ('client_script', ('client',)), ('shared_script', SIDES)):
            for pat in self.manifest.get(key, []):
                if pat.startswith('@') or pat.startswith('!'):
                    continue
                hits = glob.glob(os.path.join(glob.escape(path), pat), recursive=True)
                for h in hits:
                    if h.endswith('.lua') and os.path.isfile(h):
                        self.files.setdefault(os.path.relpath(h, path), set()).update(sides)
        for k, sides in (('server_exports', ('server',)), ('server_export', ('server',)),
                         ('client_exports', ('client',)), ('client_export', ('client',)),
                         ('exports', SIDES), ('export', SIDES)):
            for fn in self.manifest.get(k, []):
                for s in sides:
                    self.exports[s].add(fn)

EXPORT_DEF = re.compile(r'\bexports\s*\(\s*[\'"]([\w.]+)[\'"]')
EXPORT_DEF2 = re.compile(r'\bexports\s*\[\s*[\'"]([\w.]+)[\'"]\s*\]\s*=')
CALL = re.compile(r'\bexports(?:\s*\.\s*([A-Za-z_][\w]*)|\s*\[\s*[\'"]([\w-]+)[\'"]\s*\])\s*[:.]\s*([A-Za-z_]\w*)')

def parse_cfg(path):
    ens, cats = set(), set()
    if not os.path.isfile(path):
        return ens, cats
    for line in read(path).splitlines():
        line = line.split('#')[0].strip()
        m = re.match(r'(?:ensure|start|restart)\s+(\S+)', line)
        if m:
            (cats if m.group(1).startswith('[') else ens).add(m.group(1))
    return ens, cats

def lineno(text, pos):
    return text.count('\n', 0, pos) + 1

def run(root, cfg_path):
    findings = []   # (rule, key, location, message)
    resources, category_of = {}, {}
    for cat in sorted(glob.glob(os.path.join(glob.escape(root), '*'))):
        if not os.path.isdir(cat):
            continue
        if os.path.basename(cat).startswith('['):
            for r in sorted(glob.glob(os.path.join(glob.escape(cat), '*'))):
                if os.path.isdir(r):
                    resources[os.path.basename(r)] = Resource(r)
                    category_of[os.path.basename(r)] = os.path.basename(cat)
        else:
            resources[os.path.basename(cat)] = Resource(cat)
            category_of[os.path.basename(cat)] = None
    ens, cats = parse_cfg(cfg_path)
    def ensured(name):
        return name in ens or category_of.get(name) in cats

    texts = {}   # (res, rel) -> stripped text
    for r in resources.values():
        for rel in r.files:
            texts[(r.name, rel)] = strip_comments(read(os.path.join(r.path, rel)))
        for (rn, rel), t in list(texts.items()):
            if rn != r.name:
                continue
            for s in r.files[rel]:
                for m in EXPORT_DEF.finditer(t):
                    r.exports[s].add(m.group(1))
                for m in EXPORT_DEF2.finditer(t):
                    r.exports[s].add(m.group(1))

    # `for name, fn in pairs(T) do exports(name, fn) end`: every `function T.X` / `T.X =` in the resource is an export
    DYN = re.compile(r'pairs\(\s*(\w+)\s*\)\s*do\s*exports\(\s*\w+\s*,')
    for r in resources.values():
        for (rn, rel), t in texts.items():
            if rn != r.name:
                continue
            for m in DYN.finditer(t):
                for (rn2, rel2), t2 in texts.items():
                    if rn2 == r.name:
                        for d in re.finditer(r'(?:function\s+%s\.(\w+)|\b%s\.(\w+)\s*=)' % (m.group(1), m.group(1)), t2):
                            for sd in r.files[rel]:
                                r.exports[sd].add(d.group(1) or d.group(2))
    fh_names = {n for n, c in category_of.items() if c == '[fh]'}
    alias = {}   # `provide 'x'` in a manifest -> real resource (exports['x']:fn is checked against it)
    for r in resources.values():
        for a in (r.manifest or {}).get('provide', []):
            alias.setdefault(a, r.name)
    # ---- rule 1: exports
    ensure_reported = set()
    for (rn, rel), t in sorted(texts.items()):
        if rn not in fh_names:
            continue
        sides = resources[rn].files[rel]
        for m in CALL.finditer(t):
            target, fn = m.group(1) or m.group(2), m.group(3)
            loc = '%s/%s:%d' % (rn, rel, lineno(t, m.start()))
            target = target if target in resources else alias.get(target, target)
            if target not in resources:
                findings.append(('exports', '%s:%s' % (target, fn), loc, 'resource %r not found under %s' % (target, root)))
                continue
            if not ensured(target) and target != rn:
                if target not in ensure_reported:
                    ensure_reported.add(target)
                    findings.append(('exports', '%s:*' % target, loc, 'resource %r is not ensured in server.cfg' % target))
            tr = resources[target]
            if category_of.get(target) != '[fh]' or tr.manifest is None:
                continue
            ok = any(fn in tr.exports[s] for s in sides)
            if not ok:
                other = [s for s in SIDES if s not in sides and fn in tr.exports[s]]
                why = ('exported only on the %s side' % other[0]) if other else 'not exported'
                findings.append(('exports', '%s:%s' % (target, fn), loc,
                                 '%s does not export %r for %s callers (%s)' % (target, fn, '/'.join(sorted(sides)), why)))

    # ---- rule 2: events
    SEND = re.compile(r'\b(TriggerEvent|TriggerServerEvent|TriggerClientEvent|TriggerLatentClientEvent)\s*\(\s*([\'"])(fh:[^\'"]*)\2\s*([,)])?')
    LISTEN = re.compile(r'\b(RegisterNetEvent|RegisterServerEvent|AddEventHandler|onNet)\s*\(\s*([\'"])(fh:[^\'"]*)\2')
    LIT = re.compile(r'([\'"])(fh:[A-Za-z0-9_:.\-]+)\1')
    HOOK = re.compile(r'\b(?:on|events?)\s*=\s*[\'"](fh:[^\'"]*)[\'"]')
    senders, listeners, lits = [], defaultdict(set), defaultdict(list)
    listen_locs = defaultdict(list)
    for (rn, rel), t in sorted(texts.items()):
        if rn not in fh_names:
            continue
        sides = resources[rn].files[rel]
        for m in SEND.finditer(t):
            name = m.group(3)
            if m.group(4) not in (',', ')', None) :
                continue
            kind = m.group(1)
            need = {'TriggerEvent': set(sides), 'TriggerServerEvent': {'server'}}.get(kind, {'client'})
            senders.append((name, kind, need, '%s/%s:%d' % (rn, rel, lineno(t, m.start()))))
        lstart = set()
        for m in LISTEN.finditer(t):
            name = m.group(3)
            for s in sides:
                listeners[name].add(s)
            listen_locs[name].append('%s/%s:%d' % (rn, rel, lineno(t, m.start())))
            lstart.add(m.start(3) - 1)
        for m in HOOK.finditer(t):
            for s in SIDES:
                listeners[m.group(1)].add(s)     # hook consumer: any side
        for m in LIT.finditer(t):
            if m.start() not in lstart:
                lits[m.group(2)].append((rn, rel, m.start()))
    def documented(name, emitter):
        for md in glob.glob(os.path.join(glob.escape(resources[emitter].path), '*.md')):
            if name in read(md):
                return True
        return False
    sent_names = set()
    for name, kind, need, loc in senders:
        sent_names.add(name)
        if not (listeners.get(name, set()) & need):
            if documented(name, loc.split('/')[0]):
                continue   # published bus event, named in the emitter's README: no consumer required
            findings.append(('events', name, loc, '%s %r has no listener on %s side' % (kind, name, '/'.join(sorted(need)))))
    # sender literal counts: any literal occurrence other than registration => indirect sender
    for name, locs in sorted(listen_locs.items()):
        if name in sent_names:
            continue
        if lits.get(name):
            continue
        if re.match(r'fh:\w+:ui_\w+$', name) and 'fh:ui:action' in listen_locs:
            continue   # fh_ui relays fh:ui:action to fh:<res>:ui_<action> with a computed name
        findings.append(('events', name, locs[0], 'handler for %r has no sender' % name))

    # ---- rule 3: items
    defined = set()
    for r in resources.values():
        for p in glob.glob(os.path.join(glob.escape(r.path), '**', '*.lua'), recursive=True):
            t = strip_comments(read(p))
            for m in re.finditer(r"(?:^|[\s,{])(?:\[\s*['\"]([\w-]+)['\"]\s*\]|([A-Za-z_]\w*))\s*=\s*\{\s*(?:name\s*=\s*['\"][^'\"]*['\"]\s*,\s*)?label\s*=", t):
                defined.add(m.group(1) or m.group(2))
            for m in re.finditer(r"(?:^|[\s,{])(?:\[\s*['\"]([\w-]+)['\"]\s*\]|([A-Za-z_]\w*))\s*=\s*\{\s*name\s*=\s*['\"](\w+)['\"]", t):
                if (m.group(1) or m.group(2)) == m.group(3):
                    defined.add(m.group(3))
    dyn = set()   # `[a.b.c] = { label = ...` registers whatever `c` holds inside a table `b = { ... }` in config
    for r in resources.values():
        for p in glob.glob(os.path.join(glob.escape(r.path), '**', '*.lua'), recursive=True):
            for m in re.finditer(r"\[\s*(?:\w+\.)*?(\w+)\.(\w+)\s*\]\s*=\s*\{\s*label\s*=", strip_comments(read(p))):
                dyn.add((m.group(1), m.group(2)))
    for r in resources.values():
        for p in glob.glob(os.path.join(glob.escape(r.path), '**', '*.lua'), recursive=True):
            t = strip_comments(read(p))
            for tbl, fld in dyn:
                for m in re.finditer(r"\b%s\s*=\s*\{" % re.escape(tbl), t):
                    depth, i = 1, m.end()
                    while i < len(t) and depth:
                        depth += {'{': 1, '}': -1}.get(t[i], 0); i += 1
                    for v in re.finditer(r"\b%s\s*=\s*['\"]([\w-]+)['\"]" % re.escape(fld), t[m.end():i]):
                        defined.add(v.group(1))
    NAMEROW = re.compile(r"\{\s*name\s*=\s*['\"]([\w-]+)['\"]\s*,[^\n}]*\b(?:chance|amount|count|price|qty|weight)\b")
    ITEMFLD = re.compile(r"(?<![\w.])item\s*=\s*['\"]([\w-]+)['\"]")
    for rn in sorted(fh_names):
        r = resources[rn]
        g = glob.escape(r.path)
        paths = sorted(set(glob.glob(os.path.join(g, 'config.lua')) + glob.glob(os.path.join(g, 'config', '*.lua')) +
                           glob.glob(os.path.join(g, 'data', '**', '*.lua'), recursive=True)))
        for p in paths:
            t = strip_comments(read(p))
            rel = os.path.relpath(p, r.path)
            for rx in (NAMEROW, ITEMFLD):
                for m in rx.finditer(t):
                    if m.group(1) not in defined:
                        findings.append(('items', m.group(1), '%s/%s:%d' % (rn, rel, lineno(t, m.start())),
                                         'item %r is not defined (no rsg item / fh item definition)' % m.group(1)))
    return findings

def load_allow(path):
    out = {}
    if os.path.isfile(path):
        for i, line in enumerate(read(path).splitlines(), 1):
            body = line.split('#')[0].strip()
            if body:
                out[body] = (i, line.partition('#')[2].strip())
    return out

def main(argv=None):
    here = os.path.dirname(os.path.abspath(__file__))
    repo = os.path.dirname(here)
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('--root', default=os.path.join(repo, 'server', 'resources'))
    ap.add_argument('--cfg', default=None)
    ap.add_argument('--allowlist', default=os.path.join(here, 'contracts-allowlist.txt'))
    a = ap.parse_args(argv)
    cfg = a.cfg or os.path.join(os.path.dirname(a.root.rstrip('/')), 'server.cfg')
    findings = run(a.root, cfg)
    allow = load_allow(a.allowlist)
    used, bad = set(), []
    for f in findings:
        k = '%s|%s' % (f[0], f[1])
        if k in allow:
            used.add(k)
        else:
            bad.append(f)
    for rule in ('exports', 'events', 'items'):
        grp = [f for f in bad if f[0] == rule]
        if grp:
            print('== %s (%d)' % (rule, len(grp)))
            for _, key, loc, msg in sorted(grp, key=lambda x: x[2]):
                print('  %s  %s' % (loc, msg))
    for k, (ln, _) in allow.items():
        if k not in used:
            print('warning: stale allowlist entry %r (line %d)' % (k, ln))
    print('contracts: %d finding(s), %d allowlisted' % (len(bad), len(findings) - len(bad)))
    return 1 if bad else 0

if __name__ == '__main__':
    sys.exit(main())

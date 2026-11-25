#!/usr/bin/env python3
"""Static cross-resource contract lint for server/resources (core-07 L1). Python 3 stdlib only.

Usage: python3 tools/check-contracts.py [--root server/resources] [--cfg server/server.cfg]
                                        [--allowlist tools/contracts-allowlist.txt]
Exit 0 = no non-allowlisted findings, 1 = findings, 2 = bad usage.

Rules
  exports  `exports.<res>:<fn>(`, `exports['<res>']:<fn>(`, `exports["<res>"]:<fn>(` calls in [fh] scripts.
           <res> must exist under <root>/*/ and be ensured/started in server.cfg (directly, or through a bracketed
           category `ensure [fh]`). For [fh] resources and any resource with a manifest, <fn> must be exported
           (`exports('fn', ...)`/`exports["fn"]` in a manifest-listed script, or fxmanifest server_exports/
           client_exports/exports; manifest `exports` is client-side) on the caller's side: a server script needs a server export, a client script a
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
           any [fh] config.lua or data/*.lua. Must be defined: rsg-core shared/items.lua entries, any [fh] table
           entry shaped `key = { label = ...` (item definitions: fh_core Items, resource `items = {}`, registerItems
           batches), or any table literal containing both `item = '<x>'` and `label =` at the same brace depth (in
           either order, single- or multi-line). Item names built dynamically are not seen. Weapons are expected in
           rsg items too.
  Documented events: a sender with no listener is fine when the event name appears in a *.md in the emitting resource
  (published bus events); `fh:<res>:ui_<action>` handlers count as sent by the fh_ui relay (fh:ui:action).
  Dynamic export loops `for k, fn in pairs(T) do exports([prefix ..] k, fn) end` export (with the prefix) every `function T.X`/`T.X =` found in files of
  the same side. `provide 'x'` aliases (fh_inventory -> rsg-inventory) resolve to the providing resource. Dynamic-key item
  definitions `[cfg.feed.item] = { label = ...` define the value of `item` in any `feed = { ... }` table.
Allowlist: one entry per line `<rule>|<key>  # reason / idea id`. Keys: `exports|res:fn`, `events|fh:name`,
  `items|name`, `useable|item`, `event-target|event`, `manifest|res:glob`, `clothes|gender:category`.
  Unused entries are reported as warnings. Warning-tier findings (`dead`, `icon`) never fail the gate.
"""
import argparse, glob, os, re, sys
from collections import defaultdict

SIDES = ('server', 'client')

# Warning-tier findings (printed, but they never fail the gate). Populated by run(), read by main().
WARNINGS = []


def braced(text, open_pos):
    """Return text[open_pos:..] from the '{' at open_pos through its matching '}' (inclusive)."""
    depth = 0
    for i in range(open_pos, len(text)):
        c = text[i]
        if c == '{':
            depth += 1
        elif c == '}':
            depth -= 1
            if depth == 0:
                return text[open_pos:i + 1]
    return text[open_pos:]


def top_keys(body):
    """Top-level identifier keys of a table body (text between the outer braces)."""
    keys = set()
    for m in re.finditer(r'([A-Za-z_]\w*)\s*=', body):
        if body[:m.start()].count('{') == body[:m.start()].count('}'):
            keys.add(m.group(1))
    return keys


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
                         ('exports', ('client',)), ('export', ('client',))):
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
    WARNINGS[:] = []   # (rule, key, location, message) -- printed but never fail the gate
    _strip_cache = {}

    def strip_file(p):
        if p not in _strip_cache:
            _strip_cache[p] = strip_comments(read(p))
        return _strip_cache[p]

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
    DYN = re.compile(r'pairs\(\s*(\w+)\s*\)\s*do\s*exports\(\s*(?:[\'"](\w*)[\'"]\s*\.\.\s*)?\w+\s*,')
    for r in resources.values():
        for (rn, rel), t in texts.items():
            if rn != r.name:
                continue
            for m in DYN.finditer(t):
                for (rn2, rel2), t2 in texts.items():
                    if rn2 == r.name:
                        for d in re.finditer(r'(?:function\s+%s\.(\w+)|\b%s\.(\w+)\s*=)' % (m.group(1), m.group(1)), t2):
                            for sd in r.files[rel] & r.files[rel2]:
                                r.exports[sd].add((m.group(2) or '') + (d.group(1) or d.group(2)))
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
    SEND = re.compile(r'\b(TriggerEvent|TriggerServerEvent|TriggerClientEvent|TriggerLatentClientEvent)\s*\(\s*([\'"])(fh:[^\'"]*)\2\s*[,)]')
    LISTEN = re.compile(r'\b(RegisterNetEvent|RegisterServerEvent|AddEventHandler|onNet)\s*\(\s*([\'"])(fh:[^\'"]*)\2')
    LIT = re.compile(r'([\'"])(fh:[A-Za-z0-9_:.\-]+)\1')
    HOOK = re.compile(r'\b(?:on|events?)\s*=\s*[\'"](fh:[^\'"]*)[\'"]')
    HOOKCONST = re.compile(r'\b(?:on|events?)\s*=\s*([A-Za-z_]\w*(?:\.[A-Za-z_]\w*)?)')
    # module-constant event names: `M.SQUAD_EVENT = 'fh:...'` / `local E = 'fh:...'` -> `on = M.SQUAD_EVENT` is a listener
    CONST_ASSIGN = re.compile(r'\b(?:local\s+)?([A-Za-z_]\w*(?:\.[A-Za-z_]\w*)?)\s*=\s*([\'"])(fh:[A-Za-z0-9_:.\-]+)\2')
    const_map = {}
    for (rn, rel), t in texts.items():
        for m in CONST_ASSIGN.finditer(t):
            const_map[m.group(1)] = m.group(3)
            const_map[m.group(1).split('.')[-1]] = m.group(3)
    senders, listeners, lits = [], defaultdict(set), defaultdict(list)
    listen_locs = defaultdict(list)
    for (rn, rel), t in sorted(texts.items()):
        if rn not in fh_names:
            continue
        sides = resources[rn].files[rel]
        for m in SEND.finditer(t):
            name = m.group(3)
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
        for m in HOOKCONST.finditer(t):
            name = const_map.get(m.group(1))
            if name:
                for s in SIDES:
                    listeners[name].add(s)       # hook via a module constant (G1c)
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

    # ---- rule: event-target exists (G1b) ----
    # Any Trigger*Event whose namespace looks like a resource (`rsg-*` / `fh_*`) must resolve to a resource on
    # disk (or a `provide` alias) AND have a listener on the target side. Catches e.g. rsg-weapons / rsg-log.
    SEND_ANY = re.compile(r'\b(TriggerEvent|TriggerServerEvent|TriggerClientEvent|TriggerLatentClientEvent)\s*\(\s*([\'"])([A-Za-z0-9_:.\-]+)\2')
    LISTEN_ANY = re.compile(r'\b(RegisterNetEvent|RegisterServerEvent|AddEventHandler|onNet)\s*\(\s*([\'"])([A-Za-z0-9_:.\-]+)\2')
    EVENTVAL = re.compile(r"['\"]((?:rsg-[A-Za-z0-9_-]+|fh_[A-Za-z0-9_]+):[A-Za-z0-9_:.\-]+)['\"]")
    MAP_SEND = re.compile(r'\b(TriggerEvent|TriggerServerEvent|TriggerClientEvent|TriggerLatentClientEvent)\s*\(\s*([A-Za-z_]\w*)\s*[\[.]')
    table_events = defaultdict(set)   # table name -> event names it maps to (event-map sender)
    any_senders = defaultdict(list)   # event name -> [(kind, need, loc)]
    any_listeners = defaultdict(set)  # event name -> set(sides)
    for (rn, rel), t in sorted(texts.items()):
        sides = resources[rn].files[rel]
        for m in re.finditer(r"\b([A-Za-z_]\w*)\s*=\s*\{", t):
            body = braced(t, t.find('{', m.start()))
            for v in EVENTVAL.finditer(body):
                table_events[m.group(1)].add(v.group(1))
        for m in SEND_ANY.finditer(t):
            any_senders[m.group(3)].append(
                (m.group(1), {'TriggerEvent': set(sides), 'TriggerServerEvent': {'server'}}.get(m.group(1), {'client'}),
                 '%s/%s:%d' % (rn, rel, lineno(t, m.start()))))
        for m in MAP_SEND.finditer(t):
            for name in table_events.get(m.group(2), ()):
                any_senders[name].append(
                    (m.group(1), {'TriggerEvent': set(sides), 'TriggerServerEvent': {'server'}}.get(m.group(1), {'client'}),
                     '%s/%s:%d' % (rn, rel, lineno(t, m.start()))))
        for m in LISTEN_ANY.finditer(t):
            for s in sides:
                any_listeners[m.group(3)].add(s)
    for name in sorted(any_senders):
        ns = name.split(':')[0]
        if not (ns.startswith('rsg-') or ns.startswith('fh_')):
            continue
        if alias.get(ns, ns) in resources:
            continue   # namespace resource exists on disk (or is provided)
        for kind, need, loc in any_senders[name]:
            if not (any_listeners.get(name, set()) & need):
                findings.append(('event-target', name, loc,
                                 '%s %r: namespace resource %r is not on disk and has no listener on %s side'
                                 % (kind, name, ns, '/'.join(sorted(need)))))

    # ---- rule 3: items
    NAMEROW = re.compile(r"\{\s*name\s*=\s*['\"]([\w-]+)['\"]\s*,[^\n}]*\b(?:chance|amount|count|price|qty|weight)\b")
    ITEMFLD = re.compile(r"(?<![\w.])item\s*=\s*['\"]([\w-]+)['\"]")
    LABELFLD = re.compile(r"(?<![\w.])label\s*=(?!=)")

    def table_item_defs(t):
        out, stack, i, n = set(), [], 0, len(t)
        while i < n:
            c = t[i]
            if c in '\'"':
                j = i + 1
                while j < n and t[j] != c and t[j] != '\n':
                    j += 2 if t[j] == '\\' else 1
                if stack:
                    stack[-1].append(t[i:j + 1])
                i = j + 1
                continue
            if c == '{':
                if stack:
                    stack[-1].append(' ')
                stack.append([])
            elif c == '}':
                if stack:
                    body = ''.join(stack.pop())
                    if LABELFLD.search(body):
                        for m in ITEMFLD.finditer(body):
                            out.add(m.group(1))
            elif stack:
                stack[-1].append(c)
            i += 1
        return out

    defined = set()
    for r in resources.values():
        for p in glob.glob(os.path.join(glob.escape(r.path), '**', '*.lua'), recursive=True):
            t = strip_file(p)
            for m in re.finditer(r"(?:^|[\s,{])(?:\[\s*['\"]([\w-]+)['\"]\s*\]|([A-Za-z_]\w*))\s*=\s*\{\s*(?:name\s*=\s*['\"][^'\"]*['\"]\s*,\s*)?label\s*=", t):
                defined.add(m.group(1) or m.group(2))
            for m in re.finditer(r"(?:^|[\s,{])(?:\[\s*['\"]([\w-]+)['\"]\s*\]|([A-Za-z_]\w*))\s*=\s*\{\s*name\s*=\s*['\"](\w+)['\"]", t):
                if (m.group(1) or m.group(2)) == m.group(3):
                    defined.add(m.group(3))
            defined.update(table_item_defs(t))
    dyn = set()   # `[a.b.c] = { label = ...` registers whatever `c` holds inside a table `b = { ... }` in config
    for r in resources.values():
        for p in glob.glob(os.path.join(glob.escape(r.path), '**', '*.lua'), recursive=True):
            for m in re.finditer(r"\[\s*(?:\w+\.)*?(\w+)\.(\w+)\s*\]\s*=\s*\{\s*label\s*=", strip_file(p)):
                dyn.add((m.group(1), m.group(2)))
    for r in resources.values():
        for p in glob.glob(os.path.join(glob.escape(r.path), '**', '*.lua'), recursive=True):
            t = strip_file(p)
            for tbl, fld in dyn:
                for m in re.finditer(r"\b%s\s*=\s*\{" % re.escape(tbl), t):
                    depth, i = 1, m.end()
                    while i < len(t) and depth:
                        depth += {'{': 1, '}': -1}.get(t[i], 0); i += 1
                    for v in re.finditer(r"\b%s\s*=\s*['\"]([\w-]+)['\"]" % re.escape(fld), t[m.end():i]):
                        defined.add(v.group(1))
    ADDITEM = re.compile(r"\b(?:AddItem|FhAddItem|addItem)\s*\(\s*[^,\n)]*,\s*['\"]([a-z_][a-z0-9_]*)['\"]")
    # granted items: every config/data/shared grant row across all resources (fh + rsg), plus AddItem literals.
    granted = defaultdict(list)   # item -> [(rn, rel, line)]
    for r in resources.values():
        g = glob.escape(r.path)
        paths = sorted(set(
            glob.glob(os.path.join(g, 'config.lua')) +
            glob.glob(os.path.join(g, 'config', '*.lua')) +
            glob.glob(os.path.join(g, 'data', '**', '*.lua'), recursive=True) +
            glob.glob(os.path.join(g, 'shared', 'config.lua')) +
            glob.glob(os.path.join(g, 'shared', 'main.lua')) +
            glob.glob(os.path.join(g, 'shared', 'recipes.lua'))))
        for p in paths:
            t = strip_file(p)
            rel = os.path.relpath(p, r.path)
            for rx in (NAMEROW, ITEMFLD, ADDITEM):
                for m in rx.finditer(t):
                    granted[m.group(1)].append((r.name, rel, lineno(t, m.start())))
    # AddItem/FhAddItem literals anywhere in code (not only config files)
    for r in resources.values():
        for p in glob.glob(os.path.join(glob.escape(r.path), '**', '*.lua'), recursive=True):
            t = strip_file(p)
            rel = os.path.relpath(p, r.path)
            for m in ADDITEM.finditer(t):
                loc = (r.name, rel, lineno(t, m.start()))
                if loc not in granted[m.group(1)]:
                    granted[m.group(1)].append(loc)
    for item in sorted(granted):
        if item not in defined:
            rn, rel, ln = granted[item][0]
            findings.append(('items', item, '%s/%s:%d' % (rn, rel, ln),
                             'item %r is not defined (no rsg item / fh item definition)' % item))

    # ---- rule: useable items with no handler (G1a) ----
    # useable=true flags come from rsg-core/shared/items.lua and fh item definitions (flat `key = { ..., useable = true }`).
    USEABLE_DEF = re.compile(r"\b([a-z][a-z0-9_]*)\s*=\s*\{[^{}]*\buseable\s*=\s*true")
    useable_true = set()
    for r in resources.values():
        for p in glob.glob(os.path.join(glob.escape(r.path), '**', '*.lua'), recursive=True):
            for m in USEABLE_DEF.finditer(strip_file(p)):
                useable_true.add(m.group(1))
    # use handlers: resolve CreateUseableItem arguments (literal, inline pairs loop, `.USE` table, const, `*.item` field).
    CREATEUSE = re.compile(r"\bCreateUseableItem\s*\(\s*([A-Za-z_]\w*(?:\.[A-Za-z_]\w*)?)\s*[,)]")
    CREATEUSE_LIT = re.compile(r"\bCreateUseableItem\s*\(\s*['\"]([a-z_][a-z0-9_]*)['\"]\s*[,)]")
    USE_TABLE = re.compile(r"\b([A-Za-z_]\w*)(?:\.USE|\[['\"]USE['\"]\])\s*=\s*\{")
    INLINE_PAIRS = re.compile(r"\bfor\s+\w+\s*(?:,\s*\w+\s*)?in\s+pairs\s*\(\s*\{([^}]*)\}")
    FIELD_ITEM = re.compile(r"\b(\w+)\s*=\s*\{[^{}]*\bitem\s*=\s*['\"]([a-z_][a-z0-9_]*)['\"]")
    CONST_STR = re.compile(r"\b(?:local\s+)?([A-Za-z_]\w*(?:\.[A-Za-z_]\w*)?)\s*=\s*['\"]([a-z_][a-z0-9_]*)['\"]")
    ALIAS = re.compile(r"\b(?:local\s+)?([A-Za-z_]\w*)\s*=\s*([A-Za-z_]\w*(?:\.[A-Za-z_]\w*)?)\s*[\n,]")
    use_handlers = set()
    field_items = set()   # `item = 'x'` in a named table (e.g. fence leads.item) -> a consumed/delivered item
    for r in resources.values():
        for p in glob.glob(os.path.join(glob.escape(r.path), '**', '*.lua'), recursive=True):
            for m in FIELD_ITEM.finditer(strip_file(p)):
                field_items.add(m.group(2))
    for r in resources.values():
        joined = []
        for p in glob.glob(os.path.join(glob.escape(r.path), '**', '*.lua'), recursive=True):
            joined.append(strip_file(p))
        jt = '\n'.join(joined)
        if not CREATEUSE.search(jt) and not CREATEUSE_LIT.search(jt):
            continue
        for m in CREATEUSE_LIT.finditer(jt):
            use_handlers.add(m.group(1))
        has_dyn = bool(CREATEUSE.search(jt))
        if has_dyn:
            for m in USE_TABLE.finditer(jt):
                body = braced(jt, jt.find('{', m.end() - 1))
                for k in top_keys(body[1:-1]):
                    if re.fullmatch(r'[a-z_][a-z0-9_]*', k):
                        use_handlers.add(k)
            for m in INLINE_PAIRS.finditer(jt):
                for k in top_keys(m.group(1)):
                    if re.fullmatch(r'[a-z_][a-z0-9_]*', k):
                        use_handlers.add(k)
        strconst, aliases = {}, {}
        for m in CONST_STR.finditer(jt):
            strconst[m.group(1)] = m.group(2)
            strconst[m.group(1).split('.')[-1]] = m.group(2)
        for m in ALIAS.finditer(jt):
            aliases[m.group(1)] = m.group(2)
        field_item = {m.group(1): m.group(2) for m in FIELD_ITEM.finditer(jt)}
        for m in CREATEUSE.finditer(jt):
            arg = m.group(1)
            if arg in strconst:
                use_handlers.add(strconst[arg]); continue
            # resolve dotted path with one-hop aliases (e.g. cfg.leads.item, BEDROLL via FhSurvivalItems.BEDROLL)
            cur, seen = arg, set()
            while '.' in cur and cur not in strconst:
                head, _, tail = cur.partition('.')
                if head in aliases and tail:
                    cur = aliases[head] + '.' + tail
                    if cur in seen: break
                    seen.add(cur)
                    continue
                break
            if cur in strconst:
                use_handlers.add(strconst[cur]); continue
            if cur.endswith('.item') and cur.rsplit('.', 1)[0].split('.')[-1] in field_item:
                use_handlers.add(field_item[cur.rsplit('.', 1)[0].split('.')[-1]])
    for item in sorted(granted):
        if item in useable_true and item not in use_handlers:
            rn, rel, ln = granted[item][0]
            findings.append(('useable', item, '%s/%s:%d' % (rn, rel, ln),
                             'item %r is useable=true but has no use handler' % item))

    # ---- rule: granted item nothing consumes (G1a warning tier) ----
    money_items = {'dollar', 'cent', 'blood_dollar', 'blood_cent', 'gold'}
    crafting_inputs = set()
    buy_items = set()
    for r in resources.values():
        for p in glob.glob(os.path.join(glob.escape(r.path), '**', '*.lua'), recursive=True):
            t = strip_file(p)
            if 'fh_crafting' in resources and p == os.path.join(resources['fh_crafting'].path, 'shared', 'recipes.lua'):
                for m in re.finditer(r"\binputs\s*=\s*\{([^{}]*)\}", t):
                    for v in re.finditer(r"\bitem\s*=\s*['\"]([a-z_][a-z0-9_]*)['\"]", m.group(1)):
                        crafting_inputs.add(v.group(1))
            for m in re.finditer(r"\b(?:buys|goods|supplies)\s*=\s*\{([^{}]*)\}", t):
                for v in re.finditer(r"\b([a-z_][a-z0-9_]*)\s*=", m.group(1)):
                    buy_items.add(v.group(1))
    consumers = use_handlers | money_items | crafting_inputs | field_items | buy_items
    for item in sorted(granted):
        if item not in consumers:
            rn, rel, ln = granted[item][0]
            WARNINGS.append(('dead', item, '%s/%s:%d' % (rn, rel, ln),
                             'item %r is granted but nothing consumes it' % item))

    # ---- rule: default-clothes hashes valid (G3) ----
    if 'rsg-character' in resources:
        rc = resources['rsg-character']
        cfg_p = os.path.join(rc.path, 'shared', 'config.lua')
        cloth_p = os.path.join(rc.path, 'data', 'clothing.lua')
        if os.path.isfile(cfg_p) and os.path.isfile(cloth_p):
            cfg_t = strip_file(cfg_p)
            cloth_t = strip_file(cloth_p)
            dc = re.search(r'\bDefaultClothes\s*=\s*\{', cfg_t)
            if dc:
                dc_body = braced(cfg_t, cfg_t.find('{', dc.start()))
                for g in re.finditer(r"\b(male|female)\s*=\s*\{", dc_body):
                    gbody = braced(dc_body, dc_body.find('{', g.end() - 1))
                    gname = g.group(1)
                    for c in re.finditer(r"\b(\w+)\s*=\s*\{\s*hash\s*=\s*(\d+)\s*\}", gbody):
                        cat, hv = c.group(1), int(c.group(2))
                        gb = re.search(r"\[\s*['\"]%s['\"]\s*\]\s*=\s*\{" % re.escape(gname), cloth_t)
                        valid = False
                        if gb:
                            gbody2 = braced(cloth_t, cloth_t.find('{', gb.start()))
                            cb = re.search(r"\[\s*['\"]%s['\"]\s*\]\s*=\s*\{" % re.escape(cat), gbody2)
                            if cb:
                                cbody = braced(gbody2, gbody2.find('{', cb.start()))
                                valid = bool(re.search(r"\[\s*['\"]hash['\"]\s*\]\s*=\s*%d\b" % hv, cbody))
                        if not valid:
                            findings.append(('clothes', '%s:%s' % (gname, cat),
                                             '%s/shared/config.lua' % rc.name,
                                             'DefaultClothes %s.%s hash %d is not in clothing.lua' % (gname, cat, hv)))

    # ---- rule: fh item icons (G3, warning tier) ----
    imgdir = os.path.join(resources['fh_inventory'].path, 'html', 'images') if 'fh_inventory' in resources else None
    defined_fh = set()
    for r in resources.values():
        if category_of.get(r.name) != '[fh]':
            continue
        for p in glob.glob(os.path.join(glob.escape(r.path), '**', '*.lua'), recursive=True):
            t = strip_file(p)
            for m in re.finditer(r"(?:^|[\s,{])(?:\[\s*['\"]([\w-]+)['\"]\s*\]|([A-Za-z_]\w*))\s*=\s*\{\s*(?:name\s*=\s*['\"][^'\"]*['\"]\s*,\s*)?label\s*=", t):
                defined_fh.add(m.group(1) or m.group(2))
    if imgdir:
        for item in sorted(defined_fh):
            if not os.path.isfile(os.path.join(imgdir, item + '.png')):
                WARNINGS.append(('icon', item, 'fh_inventory/html/images', 'fh item %r has no icon (%s.png)' % (item, item)))

    # ---- rule: manifest globs/literals exist (G3) ----
    FILE_KEYS = ('server_scripts', 'client_scripts', 'shared_scripts', 'server_script', 'client_script',
                 'shared_script', 'files', 'file', 'ui_page', 'loadscreen')
    for r in resources.values():
        if r.manifest is None:
            continue
        for key in FILE_KEYS:
            for pat in r.manifest.get(key, []):
                if pat.startswith('@') or pat.startswith('!'):
                    continue
                hits = glob.glob(os.path.join(glob.escape(r.path), pat), recursive=True)
                if any(ch in pat for ch in '*?['):
                    if not hits:
                        findings.append(('manifest', '%s:%s' % (r.name, pat), '%s/fxmanifest.lua' % r.name,
                                         'manifest glob %r matches no files' % pat))
                elif not hits:
                    findings.append(('manifest', '%s:%s' % (r.name, pat), '%s/fxmanifest.lua' % r.name,
                                     'manifest entry %r does not exist' % pat))
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
    for rule in ('exports', 'events', 'event-target', 'items', 'useable', 'manifest', 'clothes'):
        grp = [f for f in bad if f[0] == rule]
        if grp:
            print('== %s (%d)' % (rule, len(grp)))
            for _, key, loc, msg in sorted(grp, key=lambda x: x[2]):
                print('  %s  %s' % (loc, msg))
    for rule in ('dead', 'icon'):
        grp = [w for w in WARNINGS if w[0] == rule]
        if grp:
            print('== warning: %s (%d)' % (rule, len(grp)))
            for _, key, loc, msg in sorted(grp, key=lambda x: x[2]):
                print('  %s  %s' % (loc, msg))
    for k, (ln, _) in allow.items():
        if k not in used:
            print('warning: stale allowlist entry %r (line %d)' % (k, ln))
    print('contracts: %d finding(s), %d allowlisted, %d warning(s)' % (len(bad), len(findings) - len(bad), len(WARNINGS)))
    return 1 if bad else 0

if __name__ == '__main__':
    sys.exit(main())

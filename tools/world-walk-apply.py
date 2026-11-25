#!/usr/bin/env python3
"""world-04 L: apply the owner's walk verdicts (world_walk.json, written by fh_mark) to the region data files.

  python3 tools/world-walk-apply.py            # dry run: prints a diff + report
  python3 tools/world-walk-apply.py --apply    # writes the files, then runs the readiness + spacing specs

Rules (last verdict per id wins; ids and names are never touched):
  ok                      -> verified = true
  bad + standing coords   -> x/y/z replaced with where the owner stood, verified = true
  bad, no usable coords   -> printed TODO list (nothing edited)
  unknown id              -> reported, nothing edited
Edits are id-anchored line patches (no Lua parsing). Plain python3, no lupa.
"""
import argparse, difflib, json, math, os, re, subprocess, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FH = os.path.join(ROOT, 'server', 'resources', '[fh]')
DEFAULT_WALK = os.path.join(FH, 'fh_core', 'world_walk.json')
DEFAULT_FILES = [  # coords live here (world-02 F: single source); zones camps derive coords from territories
    os.path.join(FH, 'fh_core', 'shared', 'regions.lua'),
    os.path.join(FH, 'fh_homestead', 'config.lua'),
    os.path.join(FH, 'fh_zones', 'config.lua'),
]
SPEC_FILTER = ['world_readiness_spec.lua', 'world_spacing_spec.lua', 'homestead_sites_spec.lua', 'world_coords_spec.lua']


def fnum(v):
    return isinstance(v, (int, float)) and not isinstance(v, bool) and math.isfinite(v)


def fmt(v):
    s = ('%.2f' % v).rstrip('0')
    return s + '0' if s.endswith('.') else s


def load_walk(path):
    """Return {id: record} with the last verdict per id, plus a list of notes. Missing/empty file -> {}."""
    notes = []
    if not os.path.exists(path):
        return {}, ['no walk file at %s (nothing to do)' % path]
    with open(path, encoding='utf-8') as f:
        raw = f.read().strip()
    if not raw:
        return {}, notes
    data = json.loads(raw)
    if isinstance(data, dict):
        data = [data]
    if not isinstance(data, list):
        raise ValueError('walk file must be a JSON list of marks')
    last, dup = {}, {}
    for i, rec in enumerate(data):
        if not isinstance(rec, dict) or not isinstance(rec.get('id'), str) or rec.get('verdict') not in ('ok', 'bad'):
            notes.append('skipped malformed entry #%d: %s' % (i + 1, json.dumps(rec)[:80]))
            continue
        dup[rec['id']] = dup.get(rec['id'], 0) + 1
        last[rec['id']] = rec
    for pid, n in dup.items():
        if n > 1:
            notes.append('%s: %d verdicts, last wins (%s)' % (pid, n, last[pid]['verdict']))
    return last, notes


def indent_of(line):
    return len(line) - len(line.lstrip(' \t'))


def find_anchor(lines, pid):
    rx = re.compile(r"\bid\s*=\s*'%s'" % re.escape(pid))
    for i, l in enumerate(lines):
        if rx.search(l):
            return i
    return None


COORD_ONE = {k: re.compile(r'(\b%s\s*=\s*)(-?\d+(?:\.\d+)?)' % k) for k in 'xyz'}
VERIFIED_RX = re.compile(r'(\bverified\s*=\s*)(true|false)')
CENTER_V = re.compile(r'(\bcenter\s*=\s*V\()\s*(-?[\d.]+)\s*,\s*(-?[\d.]+)\s*,\s*(-?[\d.]+)\s*(\))')
CENTER_T = re.compile(r'(\bcenter\s*=\s*\{)[^}]*(\})')


def is_oneliner(line):
    s = line.strip()
    return '{' in s and s.rstrip(',').endswith('}') and re.search(r'\bx\s*=', s) is not None


def patch_one(lines, i, coords, verified):
    """One-liner entry `{ id = .., x = .., y = .., z = .., verified = .. }`. Returns True when it had coords to edit."""
    l = lines[i]
    if coords:
        for k, v in zip('xyz', coords):
            if v is not None:
                l = COORD_ONE[k].sub(lambda m: m.group(1) + fmt(v), l, count=1)
    if verified:
        if VERIFIED_RX.search(l):
            l = VERIFIED_RX.sub(lambda m: m.group(1) + 'true', l, count=1)
        else:
            l = re.sub(r'\s*\}(,?)\s*$', lambda m: ', verified = true }' + m.group(1), l, count=1)
    lines[i] = l


def block_range(lines, i):
    ind = indent_of(lines[i])
    end = i
    for j in range(i + 1, len(lines)):
        if lines[j].strip() == '':
            continue
        if indent_of(lines[j]) < ind:
            break
        end = j
    return end


def patch_block(lines, i, coords, verified):
    """Multi-line entry. Edits the first same-level `center` and `verified`; returns False if coords have no field."""
    end = block_range(lines, i)
    ind = indent_of(lines[i])
    ok = True
    if coords:
        done = False
        for j in range(i, end + 1):
            if indent_of(lines[j]) != ind and j != i:
                continue
            l = lines[j]
            if CENTER_V.search(l):
                z0 = float(CENTER_V.search(l).group(4))
                x, y, z = coords[0], coords[1], coords[2] if coords[2] is not None else z0
                lines[j] = CENTER_V.sub(lambda m: '%s%s, %s, %s%s' % (m.group(1), fmt(x), fmt(y), fmt(z), m.group(5)), l, count=1)
                done = True
            elif CENTER_T.search(l):
                zm = re.search(r'\bz\s*=\s*(-?[\d.]+)', l)
                z = coords[2] if coords[2] is not None else (float(zm.group(1)) if zm else 0.0)
                lines[j] = CENTER_T.sub(lambda m: '%s x = %s, y = %s, z = %s %s' % (m.group(1), fmt(coords[0]), fmt(coords[1]), fmt(z), m.group(2)), l, count=1)
                done = True
            elif is_oneliner(l) or (j == i and re.search(r'\bx\s*=', l)):
                patch_one(lines, j, coords, False)
                done = done or True
            if done:
                break
        ok = done
    if verified and (ok or not coords):
        for j in range(i, end + 1):
            if (indent_of(lines[j]) == ind or j == i) and VERIFIED_RX.search(lines[j]):
                lines[j] = VERIFIED_RX.sub(lambda m: m.group(1) + 'true', lines[j], count=1)
                break
        else:
            pad = ' ' * ind if lines[i].strip().startswith('id') else ' ' * ind
            lines.insert(i + 1, pad + 'verified = true,')
    return ok


def apply_marks(files, marks):
    """files = {path: text}. Returns (new_texts, report dict)."""
    lines = {p: t.split('\n') for p, t in files.items()}
    rep = {'verified': [], 'moved': [], 'todo': [], 'unknown': [], 'unchanged': []}
    for pid in sorted(marks):
        rec = marks[pid]
        coords = None
        if rec['verdict'] == 'bad':
            if not (fnum(rec.get('x')) and fnum(rec.get('y'))):
                rep['todo'].append('%s: bad, no usable coords — note: %s' % (pid, rec.get('note') or '(none)'))
                continue
            coords = (rec['x'], rec['y'], rec['z'] if fnum(rec.get('z')) else None)
        target = None
        for p, ls in lines.items():
            i = find_anchor(ls, pid)
            if i is not None:
                target = (p, i)
                break
        if not target:
            rep['unknown'].append(pid)
            continue
        p, i = target
        ls = lines[p]
        if is_oneliner(ls[i]):
            patch_one(ls, i, coords, True)
            good = True
        else:
            good = patch_block(ls, i, coords, True)
        if not good:
            rep['todo'].append('%s: bad with coords but the entry has no coordinate field (derived from territory?) — note: %s'
                               % (pid, rec.get('note') or '(none)'))
        elif coords:
            rep['moved'].append('%s -> %s, %s%s' % (pid, fmt(coords[0]), fmt(coords[1]), ', ' + fmt(coords[2]) if coords[2] is not None else ''))
        else:
            rep['verified'].append(pid)
    return {p: '\n'.join(ls) for p, ls in lines.items()}, rep


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--apply', action='store_true', help='write the files (default: dry run, print a diff)')
    ap.add_argument('--walk', default=DEFAULT_WALK, help='world_walk.json path')
    ap.add_argument('--file', action='append', help='data file to patch (repeatable; default regions.lua, homestead + zones config)')
    ap.add_argument('--no-specs', action='store_true', help='skip the post-apply spec run')
    a = ap.parse_args(argv)

    try:
        marks, notes = load_walk(a.walk)
    except (ValueError, json.JSONDecodeError) as e:
        print('world-walk-apply: bad walk file: %s' % e, file=sys.stderr)
        return 2
    for n in notes:
        print('note: ' + n)
    paths = a.file or DEFAULT_FILES
    old = {}
    for p in paths:
        if os.path.exists(p):
            with open(p, encoding='utf-8', newline='') as f:
                old[p] = f.read()
    new, rep = apply_marks({p: t.replace('\r\n', '\n') for p, t in old.items()}, marks)
    changed = [p for p in old if new[p] != old[p].replace('\r\n', '\n')]

    for p in changed:
        sys.stdout.writelines(difflib.unified_diff(old[p].replace('\r\n', '\n').splitlines(True), new[p].splitlines(True),
                                                   'a/' + os.path.relpath(p, ROOT), 'b/' + os.path.relpath(p, ROOT)))
    print('\nverified: %d  moved: %d  todo: %d  unknown ids: %d' % (len(rep['verified']), len(rep['moved']), len(rep['todo']), len(rep['unknown'])))
    for m in rep['moved']:
        print('  moved   ' + m)
    for t in rep['todo']:
        print('  TODO    ' + t)
    for u in rep['unknown']:
        print('  UNKNOWN ' + u)
    if not marks:
        print('empty walk: no-op')
    if not a.apply:
        print('dry run (use --apply to write)' if changed else 'no changes')
        return 0
    for p in changed:
        with open(p, 'w', encoding='utf-8', newline='') as f:
            f.write(new[p])
    print('wrote %d file(s)' % len(changed))
    if a.no_specs or not changed:
        return 0
    specs = [os.path.join(ROOT, 'spec', s) for s in SPEC_FILTER]
    py = os.path.expanduser('~/.venvs/rf/bin/python')
    if not os.path.exists(py):
        py = sys.executable
    print('running readiness + spacing specs…')
    r = subprocess.call([py, os.path.join(ROOT, 'tools', 'run-specs.py')] + [s for s in specs if os.path.exists(s)])
    if r:
        print('SPEC VIOLATIONS after apply (a moved claim may be too close to a town/camp) — see above')
    return r


if __name__ == '__main__':
    sys.exit(main())

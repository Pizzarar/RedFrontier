#!/usr/bin/env python3
"""Lint docs/wiki: Sources sections, README linkage, dead relative links, and field_guide.lua coverage.

Usage: python tools/check-wiki.py [--root DIR]
Exit 0 if clean, 1 otherwise.
"""
import argparse
import re
import sys
from pathlib import Path

SRC_HEAD = re.compile(r"^(#+\s+)?Sources:?\s*$", re.I)
SRC_INLINE = re.compile(r"^Sources:", re.I)
LINK = re.compile(r"(?<!!)\[[^\]]*\]\(([^)\s]+)(?:\s+\"[^\"]*\")?\)")
BULLET = re.compile(r"^\s*[-*]\s+(.+?)\s*$")
FIELD_GUIDE_REL = Path("server/resources/[fh]/fh_tutorial/shared/field_guide.lua")


def clean_path(raw):
    p = raw.strip().strip("`").strip()
    p = p.split("#", 1)[0]
    p = re.sub(r":\d+(-\d+)?$", "", p)
    return p.strip("`").strip()


def strip_code(text):
    return re.sub(r"```.*?```", "", text, flags=re.S)


def _tokenize_lua(text):
    tokens = []
    i, n = 0, len(text)
    while i < n:
        c = text[i]
        if c in " \t\r\n":
            i += 1
        elif c == "-" and i + 1 < n and text[i + 1] == "-":
            j = text.find("\n", i + 2)
            i = n if j < 0 else j + 1
        elif c in "{}=,;":
            tokens.append(("SYM", c))
            i += 1
        elif c in "'\"":
            quote = c
            i += 1
            buf = []
            while i < n and text[i] != quote:
                if text[i] == "\\" and i + 1 < n:
                    nxt = text[i + 1]
                    buf.append({"n": "\n", "t": "\t", "r": "\r", "\\": "\\", "'": "'", '"': '"'}.get(nxt, nxt))
                    i += 2
                else:
                    buf.append(text[i])
                    i += 1
            if i >= n:
                raise ValueError("unterminated string literal")
            i += 1
            tokens.append(("STR", "".join(buf)))
        elif c.isalpha() or c == "_":
            j = i + 1
            while j < n and (text[j].isalnum() or text[j] == "_"):
                j += 1
            tokens.append(("ID", text[i:j]))
            i = j
        elif c.isdigit():
            j = i + 1
            while j < n and (text[j].isdigit() or text[j] == "."):
                j += 1
            tokens.append(("NUM", text[i:j]))
            i = j
        else:
            raise ValueError("unexpected character %r at offset %d" % (c, i))
    return tokens


def _parse_lua_table(tokens, pos):
    if pos >= len(tokens) or tokens[pos] != ("SYM", "{"):
        raise ValueError("expected '{'")
    pos += 1
    items = []
    mapping = {}
    while pos < len(tokens) and tokens[pos] != ("SYM", "}"):
        if (tokens[pos][0] == "ID"
                and pos + 1 < len(tokens)
                and tokens[pos + 1] == ("SYM", "=")):
            key = tokens[pos][1]
            val, pos = _parse_lua_value(tokens, pos + 2)
            mapping[key] = val
        else:
            val, pos = _parse_lua_value(tokens, pos)
            items.append(val)
        if pos < len(tokens) and tokens[pos] in (("SYM", ","), ("SYM", ";")):
            pos += 1
    if pos >= len(tokens) or tokens[pos] != ("SYM", "}"):
        raise ValueError("expected '}'")
    pos += 1
    if mapping and items:
        raise ValueError("mixed list and map table not supported")
    return (mapping if mapping else items), pos


def _parse_lua_value(tokens, pos):
    if pos >= len(tokens):
        raise ValueError("unexpected EOF")
    kind, val = tokens[pos]
    if kind == "SYM" and val == "{":
        return _parse_lua_table(tokens, pos)
    if kind == "STR":
        return val, pos + 1
    if kind == "NUM":
        return float(val) if "." in val else int(val), pos + 1
    if kind == "ID":
        if val == "true":
            return True, pos + 1
        if val == "false":
            return False, pos + 1
        if val == "nil":
            return None, pos + 1
        return val, pos + 1
    raise ValueError("unexpected token %r" % (tokens[pos],))


def parse_field_guide(path):
    tokens = _tokenize_lua(path.read_text(encoding="utf-8"))
    for i in range(len(tokens) - 2):
        if tokens[i] == ("ID", "FhFieldGuide") and tokens[i + 1] == ("SYM", "="):
            tbl, _ = _parse_lua_table(tokens, i + 2)
            return tbl
    raise ValueError("FhFieldGuide table not found")


def check_field_guide(root, wiki, problems):
    systems_dir = wiki / "systems"
    if not systems_dir.is_dir():
        return 0
    sys_pages = sorted(systems_dir.glob("*.md"))
    fg = root / FIELD_GUIDE_REL
    fg_label = FIELD_GUIDE_REL.as_posix()

    def fg_fail(why):
        problems.append("FAIL %s: %s" % (fg_label, why))

    if not fg.is_file():
        if sys_pages:
            fg_fail("missing field_guide.lua for %d docs/wiki/systems pages" % len(sys_pages))
        return 0

    try:
        data = parse_field_guide(fg)
    except Exception as exc:
        fg_fail("parse error: %s" % exc)
        return 0

    entries = data.get("entries") if isinstance(data, dict) else None
    if not isinstance(entries, list):
        fg_fail("FhFieldGuide.entries must be a list")
        return 0

    seen_ids = set()
    covered = set()
    for idx, entry in enumerate(entries, 1):
        if not isinstance(entry, dict):
            fg_fail("entry #%d is not a table" % idx)
            continue
        eid = entry.get("id")
        if not isinstance(eid, str) or not eid.strip():
            fg_fail("entry #%d missing id" % idx)
            eid = "#%d" % idx
        elif eid in seen_ids:
            fg_fail("duplicate id: %s" % eid)
        else:
            seen_ids.add(eid)

        lines = entry.get("lines")
        if not isinstance(lines, list) or not all(isinstance(s, str) and s.strip() for s in lines):
            fg_fail("entry '%s': lines must be a list of non-empty strings" % eid)
        elif not (3 <= len(lines) <= 5):
            fg_fail("entry '%s': lines count %d outside 3-5" % (eid, len(lines)))

        wpath = entry.get("wiki_path")
        if not isinstance(wpath, str) or not wpath.strip():
            fg_fail("entry '%s': missing wiki_path" % eid)
        else:
            target = (root / wpath).resolve()
            if not target.is_file():
                fg_fail("entry '%s': dead wiki_path: %s" % (eid, wpath))
            else:
                covered.add(target)

    for page in sys_pages:
        if page.resolve() not in covered:
            fg_fail("no field_guide entry for %s" % page.relative_to(root).as_posix())

    return len(entries)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=str(Path(__file__).resolve().parent.parent))
    root = Path(ap.parse_args().root).resolve()
    wiki = root / "docs" / "wiki"
    if not wiki.is_dir():
        print("check-wiki: docs/wiki does not exist")
        return 1
    pages = sorted(wiki.rglob("*.md"))
    problems = []

    def fail(f, why):
        problems.append("FAIL %s: %s" % (f.relative_to(root).as_posix(), why))

    readme = wiki / "README.md"
    linked = set()

    for f in pages:
        text = f.read_text(encoding="utf-8")
        lines = text.splitlines()
        # 1. Sources
        idx = None
        for i, ln in enumerate(lines):
            if SRC_HEAD.match(ln) or SRC_INLINE.match(ln):
                idx = i
        if idx is None:
            fail(f, "no Sources: section")
        else:
            paths = []
            first = lines[idx]
            if SRC_INLINE.match(first) and not SRC_HEAD.match(first):
                rest = first.split(":", 1)[1].strip()
                if rest:
                    paths.append(rest)
            for ln in lines[idx + 1:]:
                m = BULLET.match(ln)
                if m:
                    paths.append(m.group(1))
            if not paths:
                fail(f, "Sources: section has no bullet entries")
            for raw in paths:
                p = clean_path(raw)
                if p and not (root / p).exists():
                    fail(f, "Sources path missing: %s" % p)
        # 3. links
        for m in LINK.finditer(strip_code(text)):
            tgt = m.group(1)
            if re.match(r"^(https?:|mailto:|#)", tgt, re.I):
                continue
            rel = tgt.split("#", 1)[0]
            if not rel:
                continue
            dest = (f.parent / rel).resolve()
            if not dest.exists():
                fail(f, "dead link: %s" % tgt)
            elif f == readme:
                linked.add(dest)

    # 2. README linkage
    if not readme.exists():
        problems.append("FAIL docs/wiki/README.md: missing")
    else:
        for f in pages:
            if f != readme and f.resolve() not in linked:
                fail(f, "not linked from docs/wiki/README.md")

    fg_entries = check_field_guide(root, wiki, problems)

    for p in problems:
        print(p)
    print("check-wiki: %d pages, %d field_guide entries, %d problems" % (len(pages), fg_entries, len(problems)))
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())

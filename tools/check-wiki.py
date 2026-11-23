#!/usr/bin/env python3
"""Lint docs/wiki: Sources sections, README linkage, dead relative links.

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


def clean_path(raw):
    p = raw.strip().strip("`").strip()
    p = p.split("#", 1)[0]
    p = re.sub(r":\d+(-\d+)?$", "", p)
    return p.strip("`").strip()


def strip_code(text):
    return re.sub(r"```.*?```", "", text, flags=re.S)


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

    for p in problems:
        print(p)
    print("check-wiki: %d pages, %d problems" % (len(pages), len(problems)))
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())

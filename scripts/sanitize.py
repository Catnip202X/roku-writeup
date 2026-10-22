#!/usr/bin/env python3
"""
sanitize.py — replace device identifiers with stable placeholders, then prove it.

Two modes:

    python3 scripts/sanitize.py --scan       # report what is still in the tree
    python3 scripts/sanitize.py --apply      # rewrite files in place, then scan

The identifier table is deliberately NOT in this repository. It lives in
redactions.local.txt next to this repo (git-ignored) so a published repo cannot
be mined for the very strings it exists to hide. Format, one rule per line:

    <literal><TAB><PLACEHOLDER>
    regex:<python-regex><TAB><PLACEHOLDER>

Longest literals are applied first, so a full MAC is replaced before the bare OUI
prefix it starts with. `redactions.example.txt` shows the shape with fake values.

Exit status is non-zero when --scan finds anything, which makes it usable as a
pre-push gate:

    python3 scripts/sanitize.py --scan || exit 1
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TABLE = ROOT / "redactions.local.txt"

SKIP_DIRS = {".git", "__pycache__", "node_modules"}
SKIP_SUFFIX = {".png", ".jpg", ".jpeg", ".gif", ".webp", ".otf", ".ttf", ".zip",
               ".bplist", ".pyc", ".so", ".dylib", ".ico"}
# the table itself must never be scanned or shipped
SKIP_FILES = {"redactions.local.txt", "sanitize.py"}

# Structural patterns that hold regardless of which device this came from.
STRUCTURAL = [
    # RFC1918 addresses, any private range
    (re.compile(r"\b192\.168\.\d{1,3}\.\d{1,3}\b"), "LAN_IP"),
    (re.compile(r"\b10\.\d{1,3}\.\d{1,3}\.\d{1,3}\b"), "LAN_IP"),
    (re.compile(r"\b172\.(?:1[6-9]|2\d|3[01])\.\d{1,3}\.\d{1,3}\b"), "LAN_IP"),
    # any MAC address in either case
    (re.compile(r"\b(?:[0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}\b"), "MAC_ADDR"),
    # /Users/<name> absolute paths
    (re.compile(r"/Users/[^/\s\"'`)]+"), "/Users/USER"),
    # Bilibili device fingerprints in captured URLs
    (re.compile(r"buvid=[A-Za-z0-9]+"), "buvid=BUVID"),
    (re.compile(r"[?&]mid=\d+"), "mid=UID"),
    (re.compile(r"[?&]upsig=[0-9a-f]+"), "upsig=SIG"),
    (re.compile(r"[?&]trid=[0-9a-zA-Z]+"), "trid=SESSION"),
    (re.compile(r"hmac=[0-9a-f]{16,}"), "hmac=SIG"),
    (re.compile(r"[?&]oi=\d+"), "oi=OBJECT_ID"),
    (re.compile(r"[?&]deadline=\d+"), "deadline=EXPIRY"),
]


def load_table() -> list[tuple[str, object, str]]:
    """Return [(kind, matcher, placeholder)] with literals sorted longest-first."""
    literal: list[tuple[str, str]] = []
    regex: list[tuple[re.Pattern, str]] = []
    if TABLE.exists():
        for raw in TABLE.read_text(encoding="utf-8").splitlines():
            line = raw.strip()
            if not line or line.startswith("#") or "\t" not in line:
                continue
            pat, rep = line.split("\t", 1)
            pat, rep = pat.strip(), rep.strip()
            if not pat or not rep:
                continue
            if pat.startswith("regex:"):
                regex.append((re.compile(pat[6:]), rep))
            else:
                literal.append((pat, rep))
    literal.sort(key=lambda kv: len(kv[0]), reverse=True)
    out: list[tuple[str, object, str]] = [("lit", p, r) for p, r in literal]
    out += [("re", p, r) for p, r in regex]
    out += [("re", p, r) for p, r in STRUCTURAL]
    return out


def scrub(text: str, table) -> str:
    for kind, pat, rep in table:
        text = text.replace(pat, rep) if kind == "lit" else pat.sub(rep, text)
    return text


def walk():
    for path in ROOT.rglob("*"):
        if not path.is_file():
            continue
        if any(part in SKIP_DIRS for part in path.parts):
            continue
        if path.name in SKIP_FILES or path.suffix.lower() in SKIP_SUFFIX:
            continue
        yield path


def scan(table, apply: bool) -> int:
    hits: dict[str, set[str]] = {}
    changed = 0
    for path in walk():
        try:
            body = path.read_text(encoding="utf-8", errors="strict")
        except (UnicodeDecodeError, OSError):
            continue
        new = scrub(body, table)
        if new == body:
            continue
        rel = str(path.relative_to(ROOT))
        changed += 1
        if apply:
            path.write_text(new, encoding="utf-8")
            continue
        # report which placeholders had to fire, without echoing the secret
        for kind, pat, rep in table:
            found = (pat in body) if kind == "lit" else pat.search(body)
            if found:
                hits.setdefault(rel, set()).add(rep)

    if apply:
        print(f"sanitize: rewrote {changed} file(s)")
        # a second pass proves the rewrite converged
        leftover = 0
        for path in walk():
            try:
                body = path.read_text(encoding="utf-8", errors="strict")
            except (UnicodeDecodeError, OSError):
                continue
            if scrub(body, table) != body:
                leftover += 1
                print(f"  STILL DIRTY: {path.relative_to(ROOT)}", file=sys.stderr)
        print("scan: clean" if leftover == 0 else f"scan: {leftover} dirty file(s)")
        return 0 if leftover == 0 else 1

    if hits:
        print(f"scan: {len(hits)} file(s) with replaceable identifiers", file=sys.stderr)
        for rel in sorted(hits):
            print(f"  {rel}: {', '.join(sorted(hits[rel]))}", file=sys.stderr)
        return 1
    print(f"scan: clean ({sum(1 for _ in walk())} files)")
    return 0


def main() -> int:
    apply = "--apply" in sys.argv
    if not TABLE.exists():
        # Expected in a fresh clone: the literal table is git-ignored on purpose
        # (a public repo must not contain the strings it exists to hide). The
        # structural patterns still run. See SANITISATION.md.
        print(f"note: {TABLE.name} absent — literal table skipped, structural "
              f"patterns still applied (expected in a clone)", file=sys.stderr)
    return scan(load_table(), apply)


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""verify_raw_inputs.py -- check the user's raw input files against 01_raw/RAW_MANIFEST.sha256.

  python3 tools/verify_raw_inputs.py [--root PACKAGE_ROOT] [--group 01_raw/05_Mobility]

The manifest lists every raw file the reported results were computed from (SHA-256, path relative to the package
root; `shasum -a 256 -c 01_raw/RAW_MANIFEST.sha256` run from the package root performs the same check).
Output: one line per source folder (files expected / present / matching), then every missing or changed file.
Exit 0 = every file present and identical; 1 = something is missing or differs (the run stops: README.md and
01_raw/<source>/README.md explain how to obtain each file). Files not in the manifest are ignored.
"""
import argparse
import hashlib
import sys
from collections import OrderedDict
from pathlib import Path

GROUP_DEPTH = {"01_raw/02_UN_Comtrade": 3, "01_raw/05_Mobility": 3}


def sha256(p):
    h = hashlib.sha256()
    with open(p, "rb") as fh:
        for block in iter(lambda: fh.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def group_of(rel):
    parts = rel.split("/")
    depth = GROUP_DEPTH.get("/".join(parts[:2]), 2)
    return "/".join(parts[:min(depth, len(parts) - 1)])


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=str(Path(__file__).resolve().parents[1]))
    ap.add_argument("--group", default="", help="check only paths that start with this prefix")
    ap.add_argument("--optional", action="append", default=[], help="a manifest path that may be absent (reported, not a failure)")
    a = ap.parse_args()
    root = Path(a.root)
    rows = []
    for line in (root / "01_raw" / "RAW_MANIFEST.sha256").read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        h, rel = line.split("  ", 1)
        if rel.startswith(a.group):
            rows.append((h, rel))
    stats = OrderedDict()
    missing, changed, absent_ok = [], [], []
    for h, rel in rows:
        g = stats.setdefault(group_of(rel), [0, 0, 0])
        g[0] += 1
        p = root / rel
        if not p.is_file():
            (absent_ok if rel in a.optional else missing).append(rel)
            continue
        g[1] += 1
        if sha256(p) == h:
            g[2] += 1
        else:
            changed.append(rel)
    print(f"{'source folder':70s} expected present identical")
    for g, (n, pr, ok) in stats.items():
        print(f"{g:70s} {n:8d} {pr:7d} {ok:9d}")
    for rel in missing:
        print("MISSING", rel)
    for rel in changed:
        print("CHANGED (sha256 differs from the manifest)", rel)
    for rel in absent_ok:
        print("ABSENT (optional; run_all.py rebuilds its content from other inputs)", rel)
    ok = not missing and not changed
    print(f"RAW_INPUTS {'PASS' if ok else 'FAIL'}: {len(rows)} files in the manifest, {len(missing)} missing, {len(changed)} changed"
          + (f", {len(absent_ok)} optional absent" if absent_ok else ""))
    if not ok:
        print("See 01_raw/README.md and the README.md in each 01_raw subfolder for how to obtain the files.")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()

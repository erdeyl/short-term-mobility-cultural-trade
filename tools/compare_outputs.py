#!/usr/bin/env python3
"""compare_outputs.py -- compare produced table / figure-data CSV files with reference copies, cell by cell.

  python3 tools/compare_outputs.py REFERENCE_DIR PRODUCED_DIR [--rel-tol 1e-6] [--report report.md]

Every *.csv under REFERENCE_DIR is matched by relative path under PRODUCED_DIR. Cells are compared as text after
extracting their numbers: the non-numeric text must be identical, the count of numbers must agree, integers written
with thousands separators (N) must be equal exactly, and other numbers must agree within the relative tolerance
(|a - b| <= tol * max(1, |b|)). Exit 0 = every file matches.
"""
import argparse
import csv
import re
import sys
from pathlib import Path

NUM = re.compile(r"[−-]?\d[\d,]*(?:\.\d+)?(?:[eE][−+-]?\d+)?")


def split(cell):
    nums = NUM.findall(cell)
    return NUM.sub("#", cell), nums


def val(s):
    return float(s.replace("−", "-").replace(",", ""))


def cmp_cell(a, b, tol):
    ta, na = split(a)
    tb, nb = split(b)
    if ta != tb or len(na) != len(nb):
        return False
    for x, y in zip(na, nb):
        if ("." not in x and "e" not in x.lower()) or ("." not in y and "e" not in y.lower()):
            if val(x) != val(y):
                return False
        elif abs(val(x) - val(y)) > tol * max(1.0, abs(val(y))):
            return False
    return True


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("reference")
    ap.add_argument("produced")
    ap.add_argument("--rel-tol", type=float, default=1e-6)
    ap.add_argument("--report", default="")
    a = ap.parse_args()
    ref, pro = Path(a.reference), Path(a.produced)
    rows, bad = [], 0
    for f in sorted(ref.rglob("*.csv")):
        rel = f.relative_to(ref)
        g = pro / rel
        if not g.is_file():
            rows.append((str(rel), "MISSING", "", "")); bad += 1
            continue
        A = list(csv.reader(open(f, encoding="utf-8", newline="")))
        B = list(csv.reader(open(g, encoding="utf-8", newline="")))
        if len(A) != len(B) or any(len(x) != len(y) for x, y in zip(A, B)):
            rows.append((str(rel), "SHAPE DIFFERS", f"{len(A)} rows", f"{len(B)} rows")); bad += 1
            continue
        diff = [(i, j, x, y) for i, (ra, rb) in enumerate(zip(A, B)) for j, (x, y) in enumerate(zip(ra, rb)) if x != y and not cmp_cell(x, y, a.rel_tol)]
        same = sum(1 for ra, rb in zip(A, B) for x, y in zip(ra, rb) if x == y)
        cells = sum(len(r) for r in A)
        status = "IDENTICAL" if same == cells else ("MATCH (within tolerance)" if not diff else "DIFFERS")
        if diff:
            bad += 1
        rows.append((str(rel), status, f"{cells} cells, {same} identical", f"{len(diff)} beyond tolerance" + (f"; first: row {diff[0][0]} col {diff[0][1]}: {diff[0][2]!r} vs {diff[0][3]!r}" if diff else "")))
    out = ["| file | result | cells | differences |", "|---|---|---|---|"] + [f"| {r[0]} | {r[1]} | {r[2]} | {r[3]} |" for r in rows]
    print("\n".join(out))
    print(f"COMPARE {'PASS' if bad == 0 else 'FAIL'}: {len(rows)} files, {bad} not matching (relative tolerance {a.rel_tol:g}; integers exact)")
    if a.report:
        Path(a.report).write_text("\n".join(out) + "\n", encoding="utf-8")
    sys.exit(0 if bad == 0 else 1)


if __name__ == "__main__":
    main()

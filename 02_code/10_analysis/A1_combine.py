"""A1_combine.py -- assemble out/<vintage>/results/A1.csv from results/A1_parts/A1_0*.csv (analysis block A1).

Columns: row_id + the the shared analysis conventions schema (vintage, block, item, spec, sample, mobility, term, b, se,
p, ci_lo, ci_hi, N, N_full, n_singletons, n_separated, n_clusters, cluster_var, note). Tests carry the
statistic in b, df in se and p in p. Values are copied as text (lossless %24.17g from Stata).
Checks: identical header in every part, unique row_id within a vintage file.
Superseded rows are kept with the reason prefixed to `note` (audit check, 2026-11-03):
  - A1.5 spec r2_* (candidate-year one-basis definition) -> superseded by r2all_* (R1-01);
  - the preserved float-storage A1.10 part A1_05_float_superseded.csv.keep -> superseded by the
    double-storage rerun A1.10.dmdyn2_* (R1-02).
Usage: python3 -I A1_combine.py <out_root> [vintage ...]   (default: submitted corrected)
"""
import csv
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
cols = ["row_id", "vintage", "block", "item", "spec", "sample", "mobility", "term", "b", "se", "p",
        "ci_lo", "ci_hi", "N", "N_full", "n_singletons", "n_separated", "n_clusters", "cluster_var", "note"]
for v in (sys.argv[2:] or ("submitted", "corrected")):  # rerun C2: optional vintage list, default unchanged
    parts = sorted((root / v / "results" / "A1_parts").glob("A1_0*.csv"))
    sup = root / v / "results" / "A1_parts" / "A1_05_float_superseded.csv.keep"
    if sup.exists():
        parts.append(sup)
    R101 = "SUPERSEDED (audit R1-01: candidate-year definition; use r2all): "
    R102 = "SUPERSEDED (audit R1-02: run under default float storage; classifier counts were rounding artifacts; use dmdyn2_*): "
    rows, seen = [], set()
    for p in parts:
        with open(p, encoding="utf-8") as fh:
            rd = csv.DictReader(fh)
            assert rd.fieldnames == cols, (p, rd.fieldnames)
            for r in rd:
                if p == sup:
                    r["note"] = R102 + r["note"]
                elif r["item"] == "A1.5" and r["spec"].startswith("r2_") and not r["note"].startswith("SUPERSEDED"):
                    r["note"] = R101 + r["note"]
                assert r["row_id"] not in seen, (p, r["row_id"])
                seen.add(r["row_id"])
                r["_part"] = p.name
                rows.append(r)
    out = root / v / "results" / "A1.csv"
    with open(out, "w", newline="", encoding="utf-8") as fh:
        w = csv.writer(fh)
        w.writerow(cols)
        for r in rows:
            w.writerow([r[c] for c in cols])
    print(f"A1_COMBINE {v}: {len(rows)} rows from {len(parts)} parts -> {out}")

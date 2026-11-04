#!/usr/bin/env python3
"""C2_supplement.py -- rerun C2, author addition (4), reviewer point R2-4a: economies and years in
each final estimation sample (vintage corrected2x unless another vintage is given).

Samples = e(sample) flags of prepared.dta (01_prep.do section F): s_base_vis, s_base_tour (Table 2 cols 1/5),
s_cs_exact (exact visitor-tourist common support), s_dyn_vis, s_dyn_tour (Table 3), s_cd_vis, s_cd_tour
(Table 5 cols 3/4). One row per economy and role (exporter = iso3_o, importer = iso3_d) per sample:
directed pair-years, partners, years present (ranges). Names: 05_output/10_analysis/A1_un_names.csv (UN source
designations; TWN = "Taiwan Province of China (TWN)"); "economies" is used for counts.
Outputs: 06_results/tables/final/supplement/TableS_sample_economies.csv (long), TableS_sample_economies_wide.csv
(one row per economy: years as exporter and as importer in each sample), TableS_sample_economies.md (formatted).
Controls: rows per sample = prepared flag counts; every ISO3 has a UN designation.
Usage: python3 C2_supplement.py [vintage]
"""
import os, sys
import pandas as pd

W = os.environ.get("PKG_ROOT") or os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))  # package root
V = sys.argv[1] if len(sys.argv) > 1 else "corrected2x"
OUT = W + ("/06_results/tables/final/supplement" if V == "corrected2x" else f"/06_results/tables/{V}/supplement")
os.makedirs(OUT, exist_ok=True)
# reader-facing sample names (panel item 3.1): no table/column references of the submitted numbering
S = {"s_base_vis": "Baseline sample, bilateral visitors", "s_base_tour": "Baseline sample, bilateral tourists",
     "s_cs_exact": "Exact visitor–tourist common support", "s_dyn_vis": "Dynamic model sample, visitors",
     "s_dyn_tour": "Dynamic model sample, tourists", "s_cd_vis": "Cultural-distance model sample, visitors",
     "s_cd_tour": "Cultural-distance model sample, tourists"}
cols = ["year", "iso3_o", "iso3_d"] + list(S)
it = pd.read_stata(f"{W}/05_output/10_analysis/{V}/prepared.dta", columns=cols, iterator=True, chunksize=200000,
                   convert_categoricals=False, convert_dates=False)
d = pd.concat(list(it), ignore_index=True)
d["year"] = pd.to_numeric(d.year).astype(int)
names = pd.read_csv(W + "/05_output/10_analysis/A1_un_names.csv").set_index("iso3").name_un.to_dict()


def ranges(ys):
    ys = sorted(set(int(y) for y in ys))
    out, s = [], None
    for i, y in enumerate(ys):
        if s is None:
            s = y
        if i == len(ys) - 1 or ys[i + 1] != y + 1:
            out.append(f"{s}" if s == y else f"{s}-{y}")
            s = None
    return ", ".join(out)


long = []
for s, lab in S.items():
    x = d[d[s] == 1]
    n = len(x)
    for role, a, b in (("exporter", "iso3_o", "iso3_d"), ("importer", "iso3_d", "iso3_o")):
        for iso, g in x.groupby(a):
            long.append({"vintage": V, "sample": s, "sample_label": lab, "sample_rows": n, "iso3": iso,
                         "economy": names.get(iso, ""), "role": role, "pair_years": len(g), "partners": g[b].nunique(),
                         "years_present": ranges(g.year), "n_years": g.year.nunique()})
L = pd.DataFrame(long)
miss = sorted(set(L.loc[L.economy == "", "iso3"]))
assert not miss, f"ISO3 without UN designation: {miss}"
for s in S:
    a = L[(L["sample"] == s) & (L.role == "exporter")].pair_years.sum()
    assert a == int((d[s] == 1).sum()), (s, a)
L = L.sort_values(["sample", "economy", "role"])
L.to_csv(OUT + "/TableS_sample_economies.csv", index=False)
wide = L.pivot_table(index=["iso3", "economy"], columns=["sample", "role"], values="years_present", aggfunc="first").reset_index()
wide.columns = ["iso3", "economy"] + [f"{s}__{r}" for s, r in wide.columns[2:]]
wide = wide.sort_values("economy")
wide.insert(0, "vintage", V)
wide.to_csv(OUT + "/TableS_sample_economies_wide.csv", index=False)
VL = "final data" if V == "corrected2x" else f"vintage {V}"
md = [f"# Table S. Reporting and partner areas and years in each estimation sample ({VL})", "",
      "Each estimation sample is the realized e(sample) of the PPML model (exporter-year, importer-year and directed-pair fixed effects). "
      "Rows: one economy per role (exporter = origin of the cultural-goods flow; importer = reporting destination). "
      "Designations follow the UN sources (UN Comtrade reference areas). "
      "Years are calendar years 2007-2021 in which the economy has at least one directed pair-year in the sample.", ""]
for s, lab in S.items():
    x = L[L["sample"] == s]
    ne = x.iso3.nunique()
    md += [f"## {lab}", "", f"Directed pair-years: {int(x[x.role == 'exporter'].pair_years.sum()):,}; economies: {ne} "
           f"({x[x.role == 'exporter'].iso3.nunique()} as exporter, {x[x.role == 'importer'].iso3.nunique()} as importer).", "",
           "| Economy | ISO3 | Role | Pair-years | Partners | Years present |", "|---|---|---|---|---|---|"]
    for r in x.itertuples():
        md.append(f"| {r.economy} | {r.iso3} | {r.role} | {r.pair_years:,} | {r.partners} | {r.years_present} |")
    md.append("")
open(OUT + "/TableS_sample_economies.md", "w", encoding="utf-8").write("\n".join(md))
print("SUPPLEMENT_DONE", V, len(L), "rows;", {s: int((d[s] == 1).sum()) for s in S})

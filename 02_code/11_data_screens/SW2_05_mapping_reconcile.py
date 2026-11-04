"""SW2_05: M6 partner mapping and full reconciliation of the analysis data with the raw workbooks.
(1) Which UN Tourism area codes (reporter and partner) can merge into the CEPII backbone? The master merges
    tourism on year + iso3num_o + iso3num_d (PKG 05_master/01_build_master_panel.py:193-200), CEPII rows with
    country_exists==1 (:31-36). An aggregate reaches the analysis data only if its code equals a CEPII iso3num
    in that year.
(2) Reconcile: rebuild every selected cell from the raw workbooks with the build rule (residence-first, cell
    level; PKG 01_build_UN_Tourism.do:592-598) and C12 (corrected vintage), map codes to ISO3 via CEPII, and
    compare with prepared.dta (corrected): rev_*_raw on row (o=reporter, d=partner) must equal value*1000.
Outputs: M6_code_mapping.csv, M6_aggregates_reaching_analysis.csv, M6_reconcile_summary.csv, M6_reconcile_diffs.csv.
"""
import numpy as np
import pandas as pd
from pathlib import Path

# package paths: ROOT = package root; screens write to 05_output/11_data_screens (not run by run_all.py)
ROOT = Path(__file__).resolve().parents[2]
W = ROOT
OUT = ROOT / "05_output/11_data_screens"


def ptype(c):
    if 10000 <= c <= 70000:
        return "region_total"
    if c == 999:
        return "world"
    if c == 998:
        return "nationals_abroad"
    if 991 <= c <= 997:
        return "other_area"
    return "country"


d = pd.read_csv(OUT / "tourism_long.csv.gz", low_memory=False)
d["ptype"] = d.partner_area_code.map(ptype)
cep = pd.read_csv(OUT / "work/cepii_codes_by_year.csv")
cep = cep[cep.country_exists_o == 1]
cmap = cep.set_index(["year", "iso3num_o"]).iso3_o
win = d[d.year.between(2007, 2021)].copy()

rows = []
for role, code, label in [("partner", "partner_area_code", "partner_area_label"),
                          ("reporter", "reporter_area_code", "reporter_area_label")]:
    g = win.groupby([code, label, "year"]).agg(n=("value", "size"), v=("value", "sum")).reset_index()
    g["iso3"] = [cmap.get((y, c), None) for y, c in zip(g.year, g[code])]
    g = g.groupby([code, label]).agg(years=("year", lambda s: f"{s.min()}-{s.max()}"), n=("n", "sum"), v=("v", "sum"),
                                     years_matched=("iso3", lambda s: int(s.notna().sum())),
                                     n_years=("year", "size"),
                                     iso3=("iso3", lambda s: ";".join(sorted(set(s.dropna()))))).reset_index()
    g = g.rename(columns={code: "code", label: "label"})
    g["role"] = role
    g["ptype"] = g.code.map(ptype) if role == "partner" else "reporter"
    rows.append(g)
m = pd.concat(rows, ignore_index=True)
m.to_csv(OUT / "M6_code_mapping.csv", index=False)
agg_reach = m[(m.role == "partner") & (m.ptype != "country") & (m.years_matched > 0)]
agg_reach.to_csv(OUT / "M6_aggregates_reaching_analysis.csv", index=False)
print("aggregate partner codes in window:", int(((m.role == "partner") & (m.ptype != "country")).sum()),
      "-> matching a CEPII iso3num in some year:", len(agg_reach))
unm = m[(m.ptype.isin(["country", "reporter"])) & (m.years_matched < m.n_years)]
print("country-level codes not matched in every year present (mapping loss):")
print(unm[["role", "code", "label", "years", "n", "v", "years_matched", "n_years", "iso3"]].sort_values("v", ascending=False).to_string())

# ---------------------------------------------------------------- (2) reconciliation
sel = pd.read_csv(OUT / "work/selected_c12.csv.gz")
sel = sel[sel.year.between(2007, 2021)].copy()
sel["iso3_o"] = [cmap.get((y, c), None) for y, c in zip(sel.year, sel.reporter_area_code)]
sel["iso3_d"] = [cmap.get((y, c), None) for y, c in zip(sel.year, sel.partner_area_code)]
mapped = sel[sel.iso3_o.notna() & sel.iso3_d.notna() & (sel.iso3_o != sel.iso3_d)].copy()
mapped["fam"] = mapped.family.map({"TOUR": "tour", "VSTR": "vis"})
wide = mapped.pivot_table(index=["year", "iso3_o", "iso3_d"], columns="fam", values="sel", aggfunc="first").reset_index()
wide.columns.name = None
p = pd.read_csv(OUT / "work/prepared_corrected_slim.csv.gz", low_memory=False)
p["year"] = p.year.astype(str).str[:4].astype(int)  # read_stata converted the %ty-formatted year to a date
x = p[["year", "iso3_o", "iso3_d", "rev_tour_raw", "rev_vis_raw", "basis_rev_tour", "basis_rev_vis"]].merge(
    wide, on=["year", "iso3_o", "iso3_d"], how="outer", indicator=True)
summ = []
diffs = []
for fam in ["tour", "vis"]:
    a = x[f"rev_{fam}_raw"]
    b = x[fam] * 1000
    both = a.notna() & b.notna()
    only_prep = a.notna() & b.isna()
    only_raw = a.isna() & b.notna()
    dif = both & ((a - b).abs() > 1e-6 * np.maximum(1, b.abs()))
    summ.append({"family": fam, "prepared_nonmissing": int(a.notna().sum()), "raw_selected_mapped": int(b.notna().sum()),
                 "both": int(both.sum()), "equal": int((both & ~dif).sum()), "value_diff": int(dif.sum()),
                 "only_prepared": int(only_prep.sum()), "only_raw": int(only_raw.sum()),
                 "raw_rows_outside_prepared_keys": int((only_raw & (x._merge == "right_only")).sum())})
    dd = x[dif | only_prep | only_raw].copy()
    dd["family"] = fam
    dd["issue"] = np.where(dif[dd.index], "value_diff", np.where(only_prep[dd.index], "only_prepared", "only_raw"))
    diffs.append(dd)
s = pd.DataFrame(summ)
print(s.to_string())
s.to_csv(OUT / "M6_reconcile_summary.csv", index=False)
dd = pd.concat(diffs)
dd.to_csv(OUT / "M6_reconcile_diffs.csv", index=False)
print(dd.groupby(["family", "issue", "_merge"]).size())
print(dd.head(30).to_string())

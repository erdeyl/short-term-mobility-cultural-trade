"""SW2_06: consolidate mobility flags M1-M5, M8 (years 2005-2022), attach rule-based evidence (published-total
movement for the same years), and count affected baseline rows in the corrected prepared.dta.
Affected rows (family F in {tour, vis}, reporter economy R, years Y, basis B or any):
  s_base_F==1 & year in Y & ((iso3_o==R & basis_rev_F==B) | (iso3_d==R & basis_same_F==B))
  (reverse flow is reported by the exporter economy as destination; same-direction flow by the importer;
   FLAGS_CODEBOOK.md section 1). Value share = sum v_ttl_k over affected rows / sum over s_base_F==1.
Positive control: PAK 2020-2021 any basis -> 193 tourist / 152 visitor baseline rows (authors' working notes).
Output: 05_output/11_data_screens/MOBILITY_FLAGS.csv
"""
import numpy as np
import pandas as pd
from pathlib import Path

# package paths: ROOT = package root; screens write to 05_output/11_data_screens (not run by run_all.py)
ROOT = Path(__file__).resolve().parents[2]
W = ROOT
OUT = ROOT / "05_output/11_data_screens"
BASIS = {"RES": "residence", "NAT": "nationality"}

cep = pd.read_csv(OUT / "work/cepii_codes_by_year.csv")
cep = cep[cep.country_exists_o == 1]
iso_of = cep.groupby("iso3num_o").iso3_o.agg(lambda s: ";".join(sorted(set(s))))
p = pd.read_csv(OUT / "work/prepared_corrected_slim.csv.gz", low_memory=False)
p["year"] = p.year.astype(str).str[:4].astype(int)
TOT = {"tour": p.loc[p.s_base_tour == 1, "v_ttl_k"].sum(), "vis": p.loc[p.s_base_vis == 1, "v_ttl_k"].sum()}
N = {"tour": int(p.s_base_tour.sum()), "vis": int(p.s_base_vis.sum())}


def count(rep_code, fam, years, basis=None):
    isos = str(iso_of.get(rep_code, "")).split(";")
    s = p[(p[f"s_base_{fam}"] == 1) & p.year.isin(years)]
    rev = s.iso3_o.isin(isos)
    same = s.iso3_d.isin(isos)
    if basis:
        rev &= s[f"basis_rev_{fam}"].eq(BASIS[basis])
        same &= s[f"basis_same_{fam}"].eq(BASIS[basis])
    m = rev | same
    return int(m.sum()), float(s.loc[m, "v_ttl_k"].sum() / TOT[fam]), int(rev.sum()), int(same.sum())


# positive control for the counter
n_t, sh_t, _, _ = count(586, "tour", [2020, 2021])
n_v, sh_v, _, _ = count(586, "vis", [2020, 2021])
print(f"PC count PAK 2020-21: tour {n_t} (exp 193) vis {n_v} (exp 152) -> {'PASS' if (n_t, n_v) == (193, 152) else 'FAIL'}; shares {sh_t:.5f} {sh_v:.5f}")
pd.DataFrame([{"screen": "COUNT", "control": "PAK 2020-2021 baseline rows", "expected": "193 tour / 152 vis (authors' working notes)",
               "observed": f"{n_t} / {n_v}", "result": "PASS" if (n_t, n_v) == (193, 152) else "FAIL"}]).to_csv(
    OUT / "SW2_06_positive_controls.csv", index=False)

lab = pd.read_csv(OUT / "series_year_totals.csv")[["reporter_area_code", "reporter"]].drop_duplicates("reporter_area_code").set_index("reporter_area_code").reporter
pubt = pd.read_csv(OUT / "M1_partner_sum_vs_published.csv")
P = {}
for r in pubt.itertuples():
    P[("TOUR", r.reporter_area_code, r.year)] = r.P_TOTL_TOUR
    P[("VSTR", r.reporter_area_code, r.year)] = r.P_TOTL_VSTR
def pr(fam, rep, y0, y1):
    a, b = P.get((fam, rep, y0), np.nan), P.get((fam, rep, y1), np.nan)
    return b / a if (a == a and b == b and a > 0) else np.nan

rows = []
# ---- M1
a = pubt[pubt.M1_flag & pubt.year.between(2005, 2022)]
for r in a.itertuples():
    rows.append(dict(screen="M1", flag_type=r.M1_type, family=r.family, basis=r.basis, reporter_area_code=r.reporter_area_code,
                     year=r.year, year_prev=np.nan, metric=f"partner-sum/published={r.r_cty:.4g} (regional-total/published={r.r_reg:.4g}; n_partners={int(r.n_cty)}; P={r.P_ind}={r.P})",
                     ratio=r.r_cty, ratio_aux=r.r_reg, pub_ratio=np.nan))
# ---- M2
t2 = pd.read_csv(OUT / "M2_res_vs_nat.csv")
for r in t2[t2.M2_flag & t2.year.between(2005, 2022)].itertuples():
    rows.append(dict(screen="M2", flag_type="TOTAL" if r.f_total else "CELLS", family=r.family, basis="RES/NAT",
                     reporter_area_code=r.reporter_area_code, year=r.year, year_prev=np.nan,
                     metric=f"res/nat common partners={r.r_common:.4g} (n={r.n_common}); cells>1k outside [0.1,10]: {int(r.n_cells_flag or 0)} of {int(r.n_cells_big or 0)}",
                     ratio=r.r_common, ratio_aux=r.r_all, pub_ratio=np.nan))
# ---- M3 (raw selection = submitted; c12 = corrected rule)
for tag in ["raw", "c12"]:
    t3 = pd.read_csv(OUT / f"M3_basis_switch_{tag}.csv")
    t3 = t3[t3.M3_flag & (t3.year.between(2005, 2022) | t3.year_prev.between(2005, 2022))]
    for r in t3.itertuples():
        rows.append(dict(screen=f"M3_{tag}", flag_type="SWITCH", family=r.family, basis=f"{r.label_prev}->{r.label}",
                         reporter_area_code=r.reporter_area_code, year=r.year, year_prev=r.year_prev,
                         metric=f"selected total {r.year_prev}->{r.year}: {r.ratio_total:.4g} (common partners {r.ratio_common:.4g}, n={r.n_common})",
                         ratio=r.ratio_total, ratio_aux=r.ratio_common, pub_ratio=pr(r.family, r.reporter_area_code, r.year_prev, r.year)))
# ---- M4
a4 = pd.read_csv(OUT / "M4_within_series_yoy.csv")
for r in a4[a4.M4_flag & a4.year.between(2005, 2022)].itertuples():
    rows.append(dict(screen="M4", flag_type="YOY", family=r.family, basis=r.basis, reporter_area_code=r.reporter_area_code,
                     year=r.year, year_prev=r.year_prev,
                     metric=f"{int(r.year_prev)}->{r.year}: {r.ratio:.4g} (common partners {r.ratio_common:.4g}; partners {int(r.n_prev)}->{int(r.n_cty)})",
                     ratio=r.ratio, ratio_aux=r.ratio_common, pub_ratio=pr(r.family, r.reporter_area_code, int(r.year_prev), r.year)))
# ---- M5
t5 = pd.read_csv(OUT / "M5_visitors_vs_tourists.csv")
for r in t5[t5.year.between(2005, 2022) & (t5.f_total_lt | (t5.f_substitute & ~t5.documented_substitute) |
                                          ((t5.share_eq >= 0.75) & (t5.note_share.fillna(0) < t5.share_eq - 0.05)))].itertuples():
    ft = "V<T_TOTAL" if r.f_total_lt else ("UNDOCUMENTED_SUBSTITUTE" if r.f_substitute else "PARTLY_UNDOCUMENTED_EQUALITY")
    rows.append(dict(screen="M5", flag_type=ft, family="VSTR", basis=r.basis, reporter_area_code=r.reporter_area_code, year=r.year,
                     year_prev=np.nan, metric=f"V/T={r.r_VT:.4g}; share cells V==T={r.share_eq:.3f}; share with C11b note={r.note_share:.3f}; n={r.n_common}",
                     ratio=r.r_VT, ratio_aux=r.share_eq, pub_ratio=np.nan))
documented = t5[t5.year.between(2005, 2022) & t5.documented_substitute]
# ---- M8
r8 = pd.read_csv(OUT / "M8_reporter_years.csv")
for r in r8[r8.year.between(2005, 2022) & (r8.n_orig >= 2)].itertuples():
    rows.append(dict(screen="M8", flag_type="CELLS>ORIGIN_DEPARTURES", family=r.family, basis="selected", reporter_area_code=r.reporter_area_code,
                     year=r.year, year_prev=np.nan, metric=f"{r.n_orig} origins whose total departures are below this one destination's arrivals (max ratio {r.maxr:.3g}): {r.pars}",
                     ratio=r.maxr, ratio_aux=r.n_orig, pub_ratio=np.nan))

F = pd.DataFrame(rows)
F["reporter"] = F.reporter_area_code.map(lab)
F["iso3"] = F.reporter_area_code.map(iso_of)
out = []
for r in F.itertuples():
    fam = "tour" if r.family == "TOUR" else "vis"
    b = r.basis if r.basis in BASIS else None
    yrs = [int(r.year)] if not (r.year_prev == r.year_prev) or r.screen in ("M1", "M2", "M5", "M8") else [int(r.year)]
    n, sh, nr, ns = count(r.reporter_area_code, fam, yrs, b)
    out.append((n, sh, nr, ns))
F["base_rows"], F["base_value_share"], F["rows_rev"], F["rows_same"] = zip(*out)
F["in_window"] = F.year.between(2007, 2021)
F.to_csv(OUT / "MOBILITY_FLAGS.csv", index=False)
print(F.groupby(["screen", "flag_type"]).agg(n=("year", "size"), rows=("base_rows", "sum")).to_string())
print("documented substitutes (C11b, known):", len(documented), "reporter-years")

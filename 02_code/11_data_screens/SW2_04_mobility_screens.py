"""SW2_04: mobility screens M1-M8 on the 344 UN Tourism workbooks (read-only).
Inputs: 05_output/11_data_screens/tourism_long.csv.gz (SW2_01), the saved UN Tourism bulk files
(sources/datacheck_tourism/bulk_2026_05/x/Bulk/02_Inbound/..., sources/datacheck_sweep2/bulk_extract/Bulk/03_Outbound/...).
Outputs: 05_output/11_data_screens/M*_*.csv and SW2_04_positive_controls.csv. No data value is altered.

Partner classes (codes seen in the workbooks, work/partner_codes_labels.csv):
  region_total 10000-70000 ('... (UNWTO total)', 70000 = 'Other not classified'), world 999,
  nationals_abroad 998, other_area 991-997 ('Other areas of ...'); every other code = country-level leaf.
Build selection (PKG 01_build_UN_Tourism.do:592-598): cell level, residence if present else nationality.
C12 (README section 6): the two PRY residence workbooks, years 2020-2022, set missing.
"""
import sys
from pathlib import Path
import numpy as np
import pandas as pd
sys.path.insert(0, str(Path(__file__).resolve().parent))
from SW2_xlsx import read_sheet

# package paths: ROOT = package root; screens write to 05_output/11_data_screens (not run by run_all.py)
ROOT = Path(__file__).resolve().parents[2]
W = ROOT
OUT = ROOT / "05_output/11_data_screens"
BULK_IN = ROOT / "01_raw/09_UN_Tourism_bulk/Bulk/02_Inbound"
BULK_OUT = ROOT / "01_raw/09_UN_Tourism_bulk/Bulk/03_Outbound/01_Total_departures"
C11B_NOTE = "Value represents overnight visitors (tourists) only"
PRY_RES_FILES = {"0600011220202024202512.xlsx", "0600012220202024202512.xlsx"}
PCS = []


def pc(screen, name, expected, observed, ok):
    PCS.append({"screen": screen, "control": name, "expected": expected, "observed": observed,
                "result": "PASS" if ok else "FAIL"})
    print(f"PC {screen} {name}: {'PASS' if ok else 'FAIL'} | exp {expected} | obs {observed}")


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


def load_long():
    d = pd.read_csv(OUT / "tourism_long.csv.gz", low_memory=False)
    d["ptype"] = d.partner_area_code.map(ptype)
    d["series"] = d.family + "_" + d.basis
    return d


def load_pub():
    parts = []
    for f in [BULK_IN / "01_Total_arrivals/UN_Tourism_inbound_arrivals_12_2025.xlsx",
              BULK_IN / "03_Total_arrivals_by_region/UN_Tourism_inbound_arrivals_by_region_12_2025.xlsx",
              BULK_OUT / "UN_Tourism_outbound_departures_12_2025.xlsx"]:
        rows = read_sheet(f, "Data")
        df = pd.DataFrame(rows[1:], columns=rows[0])
        df["src"] = f.name
        parts.append(df)
    p = pd.concat(parts, ignore_index=True)
    for c in ["reporter_area_code", "partner_area_code", "year", "value"]:
        p[c] = pd.to_numeric(p[c], errors="coerce")
    return p


def series_year_agg(d):
    g = d.groupby(["series", "family", "basis", "reporter_area_code", "year"])
    cty = d[d.ptype == "country"]
    a = cty.groupby(["series", "family", "basis", "reporter_area_code", "year"]).agg(
        n_cty=("value", "count"), S_cty=("value", "sum"), max_cell=("value", "max"))
    reg = d[d.ptype == "region_total"].groupby(["series", "family", "basis", "reporter_area_code", "year"]).agg(
        S_reg=("value", "sum"), n_reg=("value", "count"))
    oth = d[d.ptype.isin(["other_area", "nationals_abroad"])].groupby(
        ["series", "family", "basis", "reporter_area_code", "year"]).agg(S_other=("value", "sum"))
    lab = g.agg(reporter=("reporter_area_label", "first"), file=("file", "first"))
    out = lab.join(a, how="left").join(reg, how="left").join(oth, how="left").reset_index()
    out[["n_cty", "S_cty", "S_reg", "n_reg", "S_other"]] = out[["n_cty", "S_cty", "S_reg", "n_reg", "S_other"]].fillna(0)
    return out


# ------------------------------------------------------------------------------------------ M1
def m1(agg, pub):
    tot = pub[(pub.partner_area_code == 999)]
    def get(ind):
        x = tot[tot.indicator_code == ind][["reporter_area_code", "year", "value"]]
        x = x.groupby(["reporter_area_code", "year"]).value.first()
        return x
    P_TT, P_TV, P_AT = get("INBD_TRIP_TOTL_TOTL_TOUR"), get("INBD_TRIP_TOTL_TOTL_VSTR"), get("INBD_TRIP_AREA_TOTL_TOUR")
    a = agg.copy()
    k = list(zip(a.reporter_area_code, a.year))
    a["P_TOTL_TOUR"] = [P_TT.get(x, np.nan) for x in k]
    a["P_TOTL_VSTR"] = [P_TV.get(x, np.nan) for x in k]
    a["P_AREA_TOUR"] = [P_AT.get(x, np.nan) for x in k]
    # primary comparator for the same indicator: tourists-residence -> AREA_TOTL_TOUR (by residence), else TOTL_TOTL_TOUR;
    # tourists-nationality -> TOTL_TOTL_TOUR; visitors (both bases) -> TOTL_TOTL_VSTR (no basis-specific visitor total is published)
    a["P_ind"] = np.where(a.family == "VSTR", "INBD_TRIP_TOTL_TOTL_VSTR",
                          np.where((a.basis == "RES") & a.P_AREA_TOUR.notna(), "INBD_TRIP_AREA_TOTL_TOUR",
                                   "INBD_TRIP_TOTL_TOTL_TOUR"))
    a["P"] = np.where(a.family == "VSTR", a.P_TOTL_VSTR,
                      np.where((a.basis == "RES") & a.P_AREA_TOUR.notna(), a.P_AREA_TOUR, a.P_TOTL_TOUR))
    a["r_cty"] = np.where((a.P > 0), a.S_cty / a.P, np.nan)
    a["r_reg"] = np.where((a.P > 0) & (a.S_reg > 0), a.S_reg / a.P, np.nan)
    unit = lambda r: ((r >= 500) & (r <= 2000)) | ((r >= 1 / 2000) & (r <= 1 / 500))
    a["f_unit"] = unit(a.r_cty) | unit(a.r_reg)
    a["f_high"] = a.r_cty > 1.05
    a["f_low"] = a.r_cty < 0.2
    a["M1_flag"] = a.f_unit | a.f_high | a.f_low
    a["M1_type"] = np.select([a.f_unit, a.f_high, a.f_low], ["UNIT1000", "HIGH", "LOW"], "")
    a["benchmark"] = np.where(a.P.notna() & (a.P > 0), "published_total", "NO_PUBLISHED_TOTAL")
    a.to_csv(OUT / "M1_partner_sum_vs_published.csv", index=False)
    return a


# ------------------------------------------------------------------------------------------ M2
def m2(d):
    c = d[d.ptype == "country"]
    piv = c.pivot_table(index=["family", "reporter_area_code", "partner_area_code", "year"], columns="basis",
                        values="value", aggfunc="first").reset_index()
    both = piv.dropna(subset=["RES", "NAT"]).copy()
    both["ratio"] = np.where(both.NAT > 0, both.RES / both.NAT, np.where(both.RES > 0, np.inf, np.nan))
    big = both[np.maximum(both.RES, both.NAT) >= 1.0]  # cells above 1,000 trips (values in thousand trips)
    big = big.assign(cell_flag=(big.ratio < 0.1) | (big.ratio > 10))
    cells = big[big.cell_flag].copy()
    cells.to_csv(OUT / "M2_cells_flagged.csv", index=False)
    tot = both.groupby(["family", "reporter_area_code", "year"]).agg(
        n_common=("RES", "size"), S_res_common=("RES", "sum"), S_nat_common=("NAT", "sum")).reset_index()
    tot["r_common"] = tot.S_res_common / tot.S_nat_common.replace(0, np.nan)
    fullt = c.groupby(["family", "basis", "reporter_area_code", "year"]).value.sum().unstack("basis").reset_index()
    fullt = fullt.rename(columns={"RES": "S_res_all", "NAT": "S_nat_all"})
    tot = tot.merge(fullt, on=["family", "reporter_area_code", "year"], how="left")
    tot["r_all"] = tot.S_res_all / tot.S_nat_all.replace(0, np.nan)
    cf = big.groupby(["family", "reporter_area_code", "year"]).agg(
        n_cells_big=("ratio", "size"), n_cells_flag=("cell_flag", "sum"),
        med_cell_ratio=("ratio", lambda s: float(np.nanmedian(s[np.isfinite(s)])) if np.isfinite(s).any() else np.nan)
    ).reset_index()
    tot = tot.merge(cf, on=["family", "reporter_area_code", "year"], how="left")
    tot["f_total"] = (tot.r_common < 0.5) | (tot.r_common > 2)
    tot["f_cells"] = tot.n_cells_flag.fillna(0) > 0
    tot["M2_flag"] = tot.f_total | tot.f_cells
    tot.to_csv(OUT / "M2_res_vs_nat.csv", index=False)
    return tot, cells


# ------------------------------------------------------------------------------------------ selection (build rule)
def selected(d, c12):
    c = d[d.ptype == "country"].copy()
    if c12:
        q = c.file.isin(PRY_RES_FILES) & c.year.between(2020, 2022)
        c = c[~q]
    piv = c.pivot_table(index=["family", "reporter_area_code", "partner_area_code", "year"], columns="basis",
                        values="value", aggfunc="first").reset_index()
    piv["sel"] = piv.RES.where(piv.RES.notna(), piv.NAT)
    piv["sel_basis"] = np.where(piv.RES.notna(), "RES", np.where(piv.NAT.notna(), "NAT", ""))
    return piv[piv.sel.notna()]


# ------------------------------------------------------------------------------------------ M3
def m3(sel, tag):
    g = sel.groupby(["family", "reporter_area_code", "year"])
    ry = g.agg(S_sel=("sel", "sum"), n=("sel", "size"),
               n_res=("sel_basis", lambda s: int((s == "RES").sum()))).reset_index()
    ry["share_res_cells"] = ry.n_res / ry.n
    ry["dom"] = np.where(ry.share_res_cells >= 0.5, "RES", "NAT")
    ry["label"] = np.where(ry.share_res_cells == 1, "RES", np.where(ry.share_res_cells == 0, "NAT", "MIX"))
    ry = ry[ry.S_sel > 0].sort_values(["family", "reporter_area_code", "year"])
    rows = []
    selk = sel.set_index(["family", "reporter_area_code", "year", "partner_area_code"]).sel
    for (fam, rep), grp in ry.groupby(["family", "reporter_area_code"]):
        grp = grp.reset_index(drop=True)
        for i in range(1, len(grp)):
            p, q = grp.iloc[i - 1], grp.iloc[i]
            if p.dom == q.dom and p.label == q.label:
                continue
            a = selk.loc[(fam, rep, int(p.year))]
            b = selk.loc[(fam, rep, int(q.year))]
            com = a.index.intersection(b.index)
            rc = b.loc[com].sum() / a.loc[com].sum() if len(com) and a.loc[com].sum() > 0 else np.nan
            rows.append({"vintage_rule": tag, "family": fam, "reporter_area_code": rep, "year_prev": int(p.year),
                         "year": int(q.year), "gap": int(q.year - p.year), "label_prev": p.label, "label": q.label,
                         "dom_prev": p.dom, "dom": q.dom, "S_prev": p.S_sel, "S": q.S_sel,
                         "ratio_total": q.S_sel / p.S_sel, "n_common": len(com), "ratio_common": rc})
    t = pd.DataFrame(rows)
    t["dom_switch"] = t.dom_prev != t.dom
    t["M3_flag"] = (t.ratio_total < 1 / 3) | (t.ratio_total > 3) | (t.ratio_common < 1 / 3) | (t.ratio_common > 3)
    t.to_csv(OUT / f"M3_basis_switch_{tag}.csv", index=False)
    return t, ry


# ------------------------------------------------------------------------------------------ M4
def m4(agg):
    a = agg[agg.S_cty > 0].sort_values(["series", "reporter_area_code", "year"]).copy()
    a["year_prev"] = a.groupby(["series", "reporter_area_code"]).year.shift()
    a["S_prev"] = a.groupby(["series", "reporter_area_code"]).S_cty.shift()
    a["n_prev"] = a.groupby(["series", "reporter_area_code"]).n_cty.shift()
    a = a[a.year_prev.notna() & (a.year - a.year_prev == 1)].copy()
    a["ratio"] = a.S_cty / a.S_prev
    is20 = a.year == 2020
    a["M4_flag"] = np.where(is20, (a.ratio < 0.02) | (a.ratio > 2), (a.ratio > 5) | (a.ratio < 0.2))
    return a


def m4_common(d, flags):
    """common-partner ratio for flagged M4 rows (separates coverage from level)."""
    c = d[d.ptype == "country"].set_index(["series", "reporter_area_code", "year", "partner_area_code"]).value
    out = []
    for r in flags.itertuples():
        try:
            a = c.loc[(r.series, r.reporter_area_code, int(r.year_prev))]
            b = c.loc[(r.series, r.reporter_area_code, int(r.year))]
        except KeyError:
            out.append(np.nan)
            continue
        com = a.index.intersection(b.index)
        out.append(b.loc[com].sum() / a.loc[com].sum() if len(com) and a.loc[com].sum() > 0 else np.nan)
    return out


# ------------------------------------------------------------------------------------------ M5
def m5(d):
    c = d[d.ptype == "country"]
    piv = c.pivot_table(index=["basis", "reporter_area_code", "partner_area_code", "year"], columns="family",
                        values="value", aggfunc="first").reset_index()
    note = c[c.family == "VSTR"].assign(has_note=c.notes.fillna("").str.contains(C11B_NOTE, regex=False))
    note = note.groupby(["basis", "reporter_area_code", "year"]).has_note.mean().rename("note_share").reset_index()
    both = piv.dropna(subset=["TOUR", "VSTR"]).copy()
    both["eq"] = (both.VSTR - both.TOUR).abs() < 1e-9
    both["lt"] = both.VSTR < both.TOUR - 1e-9
    big = both[both.TOUR >= 1.0]
    t = both.groupby(["basis", "reporter_area_code", "year"]).agg(
        n_common=("TOUR", "size"), S_T=("TOUR", "sum"), S_V=("VSTR", "sum"), share_eq=("eq", "mean")).reset_index()
    lt = big.groupby(["basis", "reporter_area_code", "year"]).agg(n_big=("lt", "size"), n_lt_big=("lt", "sum")).reset_index()
    t = t.merge(lt, on=["basis", "reporter_area_code", "year"], how="left").merge(
        note, on=["basis", "reporter_area_code", "year"], how="left")
    t["r_VT"] = t.S_V / t.S_T.replace(0, np.nan)
    t["f_total_lt"] = t.r_VT < 1 - 1e-9
    t["f_substitute"] = (t.share_eq == 1) & (t.n_common >= 3)
    t["documented_substitute"] = t.f_substitute & (t.note_share.fillna(0) == 1)
    t["f_cells_lt"] = t.n_lt_big.fillna(0) > 0
    t["M5_flag"] = t.f_total_lt | t.f_substitute
    t.to_csv(OUT / "M5_visitors_vs_tourists.csv", index=False)
    return t


# ------------------------------------------------------------------------------------------ M7
def m7(d):
    nonnum = d[d.value.isna() & d.value_raw.notna()]
    neg = d[d.value < 0]
    zero = d[d.value == 0]
    rows = pd.concat([nonnum.assign(issue="non_numeric"), neg.assign(issue="negative")])
    rows.to_csv(OUT / "M7_value_issues.csv", index=False)
    vc = d.value.round(6).value_counts()
    common = vc[vc.index >= 100].head(10)
    summ = {"rows": len(d), "value_missing_raw_missing": int((d.value.isna() & d.value_raw.isna()).sum()),
            "non_numeric": len(nonnum), "negative": len(neg), "zero": len(zero),
            "flag_codes": d.flag.fillna("").value_counts().to_dict(),
            "most_frequent_values_ge_100": common.to_dict()}
    return summ, zero


# ------------------------------------------------------------------------------------------ M8 (added)
def m8(sel, pub, d):
    """Cell vs origin's outbound departures: arrivals of origin j at destination i (one destination)
    should not exceed j's total outbound departures in that year. Flag cells >= 10 thousand with ratio > 1.
    Origin departures: bulk OUTB_TRIP_TOTL_TOTL_* (overnight tourists if present, else visitors)."""
    dep = pub[pub.src.str.contains("outbound_departures")]
    inds = dep.groupby(["indicator_code", "indicator_label"]).size()
    print("M8 departure indicators:\n", inds.to_string())
    # prefer total departures (all visitors) as the upper bound
    dv = dep[dep.indicator_code.str.endswith("VSTR")].groupby(["reporter_area_code", "year"]).value.first()
    dt = dep[dep.indicator_code.str.endswith("TOUR")].groupby(["reporter_area_code", "year"]).value.first()
    s = sel.copy()
    k = list(zip(s.partner_area_code, s.year))
    s["dep_vstr"] = [dv.get(x, np.nan) for x in k]
    s["dep_tour"] = [dt.get(x, np.nan) for x in k]
    s["dep"] = s[["dep_vstr", "dep_tour"]].max(axis=1)
    s["r_dep"] = s.sel / s.dep
    f = s[(s.sel >= 10) & (s.r_dep > 1)].copy()
    f.to_csv(OUT / "M8_cell_vs_origin_departures.csv", index=False)
    return s, f


def main():
    d = load_long()
    pub = load_pub()
    agg = series_year_agg(d)
    agg.to_csv(OUT / "series_year_totals.csv", index=False)

    a1 = m1(agg, pub)
    x = a1[(a1.reporter_area_code == 600) & (a1.series == "TOUR_RES") & a1.year.between(2020, 2022)]
    pc("M1", "PRY TOUR_RES 2020-2022 flagged UNIT1000", "3 of 3", f"{int(x.f_unit.sum())} of {len(x)}; r_cty={x.r_cty.round(1).tolist()}", x.f_unit.sum() == 3)
    x = a1[(a1.reporter_area_code == 586) & (a1.series == "TOUR_RES") & a1.year.between(2020, 2021)]
    pc("M1", "PAK TOUR_RES 2020-2021 (applicability)", "no published total -> NOT APPLICABLE, listed as NO_PUBLISHED_TOTAL",
       f"benchmark={x.benchmark.tolist()}", (x.benchmark == "NO_PUBLISHED_TOTAL").all())

    t2, cells2 = m2(d)
    x = t2[(t2.reporter_area_code == 600) & (t2.family == "TOUR") & t2.year.between(2020, 2022)]
    pc("M2", "PRY TOUR 2020-2022 res/nat total flagged", "3 of 3, ratio ~1000", f"{int(x.f_total.sum())} of {len(x)}; r={x.r_common.round(1).tolist()}", x.f_total.sum() == 3)
    x = t2[(t2.reporter_area_code == 586) & t2.year.between(2020, 2021)]
    pc("M2", "PAK 2020-2021 (applicability)", "no overlapping nationality series -> NOT APPLICABLE", f"rows={len(x)}", len(x) == 0)

    sel_raw = selected(d, c12=False)
    sel_c12 = selected(d, c12=True)
    t3r, ry_raw = m3(sel_raw, "raw")
    t3c, ry_c12 = m3(sel_c12, "c12")
    x = t3r[(t3r.reporter_area_code == 600) & (t3r.family == "TOUR") & (t3r.year == 2020)]
    pc("M3", "PRY TOUR 2019->2020 switch flagged (raw selection)", "flag, ratio ~200", f"{x[['label_prev','label','ratio_total','ratio_common','M3_flag']].to_dict('records')}", bool(len(x)) and bool(x.M3_flag.all()))
    x = t3r[(t3r.reporter_area_code == 586) & (t3r.family == "TOUR") & (t3r.year == 2020)]
    pc("M3", "PAK TOUR 2012->2020 switch flagged", "flag, ratio ~7", f"{x[['year_prev','label_prev','label','ratio_total','ratio_common','M3_flag']].to_dict('records')}", bool(len(x)) and bool(x.M3_flag.all()))
    x = t3r[(t3r.reporter_area_code == 586) & (t3r.family == "VSTR") & (t3r.year == 2020)]
    pc("M3", "PAK VSTR first residence year 2020 (no earlier visitor series)", "no transition row (no prior visitor year) -> NOT APPLICABLE",
       f"rows={len(x)}", len(x) == 0)

    a4 = m4(agg)
    fl4 = a4[a4.M4_flag].copy()
    fl4["ratio_common"] = m4_common(d, fl4)
    a4.loc[fl4.index, "ratio_common"] = fl4.ratio_common
    a4.to_csv(OUT / "M4_within_series_yoy.csv", index=False)
    x = a4[(a4.reporter_area_code.isin([600, 586])) & (a4.series == "TOUR_RES") & a4.year.between(2020, 2022)]
    pc("M4", "PRY/PAK TOUR_RES 2020-2022 inside the series (applicability)",
       "NOT APPLICABLE: the x1000 factor is constant inside the series, so no ratio near 1000 (documented blind spot; PRY 2022/2021=6.11 equals the official 579.471/94.846)",
       f"ratios={x[['reporter_area_code','year','ratio']].round(2).values.tolist()}", not ((x.ratio > 500) | (x.ratio < 1/500)).any())

    t5 = m5(d)
    x = t5[(t5.reporter_area_code.isin([600, 586])) & (t5.basis == "RES") & t5.year.between(2020, 2021)]
    pc("M5", "PRY/PAK RES 2020-2021 visitors==tourists (documented substitute)", "4 of 4 f_substitute & documented",
       f"{int((x.f_substitute & x.documented_substitute).sum())} of {len(x)}", int((x.f_substitute & x.documented_substitute).sum()) == 4)

    summ7, zero7 = m7(d)
    print("M7", summ7)
    pd.Series(summ7, dtype=object).to_csv(OUT / "M7_summary.csv")

    s8, f8 = m8(sel_raw, pub, d)
    x = f8[(f8.reporter_area_code == 586) & (f8.family == "TOUR") & f8.year.between(2020, 2021)]
    pc("M8", "PAK TOUR 2020-2021 cells above origin departures", ">=1 cell", f"{len(x)} cells; top={x.sort_values('sel').tail(3)[['partner_area_code','year','sel','dep','r_dep']].round(1).values.tolist()}", len(x) >= 1)
    x = f8[(f8.reporter_area_code == 600) & (f8.family == "TOUR") & f8.year.between(2020, 2022)]
    pc("M8", "PRY TOUR 2020-2022 cells above origin departures (raw)", ">=1 cell", f"{len(x)} cells; top={x.sort_values('sel').tail(3)[['partner_area_code','year','sel','dep','r_dep']].round(1).values.tolist()}", len(x) >= 1)

    # synthetic injection controls (copy only; raw untouched): x1000 on one clean series-year
    syn = d[(d.reporter_area_code == 724) & (d.series == "TOUR_RES")].copy()  # Spain residence tourists
    if len(syn):
        yr = 2015
        syn.loc[syn.year == yr, "value"] *= 1000
        dd = pd.concat([d[~((d.reporter_area_code == 724) & (d.series == "TOUR_RES"))], syn])
        ag = series_year_agg(dd)
        s1 = m1(ag, pub)
        s1 = s1[(s1.reporter_area_code == 724) & (s1.series == "TOUR_RES") & (s1.year == yr)]
        s4 = m4(ag)
        s4 = s4[(s4.reporter_area_code == 724) & (s4.series == "TOUR_RES") & s4.year.isin([yr, yr + 1])]
        s2, _ = m2(dd)
        s2 = s2[(s2.reporter_area_code == 724) & (s2.family == "TOUR") & (s2.year == yr)]
        pc("M1", "synthetic ESP TOUR_RES 2015 x1000", "UNIT1000", f"{s1.M1_type.tolist()} r={s1.r_cty.round(1).tolist()}", bool(s1.f_unit.all()) and len(s1) == 1)
        pc("M4", "synthetic ESP TOUR_RES 2015 x1000", "2015 and 2016 flagged", f"{s4[['year','ratio','M4_flag']].round(3).values.tolist()}", bool(s4.M4_flag.all()) and len(s4) == 2)
        pc("M2", "synthetic ESP TOUR 2015 x1000 vs nationality (if overlap)", "flag if overlap exists", f"rows={len(s2)} {s2[['r_common','M2_flag']].values.tolist()}", (len(s2) == 0) or bool(s2.M2_flag.all()))
    # restore and re-run M1 to be sure outputs are from the real data
    m1(agg, pub)
    pd.DataFrame(PCS).to_csv(OUT / "SW2_04_positive_controls.csv", index=False)
    sel_raw.to_csv(OUT / "work/selected_raw.csv.gz", index=False, compression="gzip")
    sel_c12.to_csv(OUT / "work/selected_c12.csv.gz", index=False, compression="gzip")
    print("done")


if __name__ == "__main__":
    main()

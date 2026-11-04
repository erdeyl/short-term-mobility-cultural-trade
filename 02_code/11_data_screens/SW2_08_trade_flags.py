"""SW2_08: consolidate trade flags T1-T3 with affected baseline rows/value share (corrected prepared.dta),
local mirror evidence (exporter-reported exports of the same HS6 lines to the same importer) and
unit values (primaryValue / netWgt) from the raw API files. Output: 05_output/11_data_screens/TRADE_FLAGS.csv and
TRADE_FLOW_EVIDENCE.csv (HS6-level, for pair-year flags)."""
from pathlib import Path
import numpy as np
import pandas as pd

# package paths: ROOT = package root; screens write to 05_output/11_data_screens (not run by run_all.py)
ROOT = Path(__file__).resolve().parents[2]
W = ROOT
PKG = ROOT
COPY = ROOT
CT = COPY / "03_intermediate/00_common/01_UN_Comtrade"
OUT = ROOT / "05_output/11_data_screens"

p = pd.read_csv(OUT / "work/prepared_corrected_slim.csv.gz", low_memory=False,
                usecols=["year", "iso3_o", "iso3_d", "s_base_vis", "s_base_tour", "v_ttl_k"])
p["year"] = p.year.astype(str).str[:4].astype(int)
TV = p.loc[p.s_base_vis == 1, "v_ttl_k"].sum()
TT = p.loc[p.s_base_tour == 1, "v_ttl_k"].sum()
p["inbase"] = (p.s_base_vis == 1) | (p.s_base_tour == 1)

rows = []
ry = pd.read_csv(OUT / "T1_reporter_year_totals.csv")
for r in ry[ry.T1a_flag | ry.T1b_flag].itertuples():
    s = p[(p.iso3_d == r.iso3) & (p.year == r.year)]
    rows.append(dict(screen="T1a" if r.T1a_flag else "T1b", flag=("YOY " if r.T1a_flag else "") + ("IMP_vs_MIRROR" if r.T1b_flag else ""),
                     year=r.year, iso3_o="*", iso3_d=r.iso3,
                     metric=f"importer total {r.imp_k:,.0f}k; prev {r.imp_prev if r.imp_prev == r.imp_prev else float('nan'):,.0f}k (yoy {r.yoy:.3g}); mirror {r.mir_k:,.0f}k from {r.n_exporters:.0f} exporters (imp/mir {r.imp_mir:.3g})",
                     value_k=r.imp_k, rows_vis=int(s.s_base_vis.sum()), rows_tour=int(s.s_base_tour.sum()),
                     share_vis=float(s.loc[s.s_base_vis == 1, "v_ttl_k"].sum() / TV), share_tour=float(s.loc[s.s_base_tour == 1, "v_ttl_k"].sum() / TT)))
t2 = pd.read_csv(OUT / "T2_pair_year_outliers.csv")
t3 = pd.read_csv(OUT / "T3_share_of_total_imports.csv")
for tag, t, met in [("T2", t2, lambda r: f"{r.lb_k:,.0f}k = {r.x_median:,.0f} x pair median ({r.med:,.1f}k, {r.n_pos} positive years); {r.hs6_top}"),
                    ("T3", t3, lambda r: f"{r.v_ttl_k:,.0f}k = {100*r.share:.1f}% of CEPII total imports {r.tradeflow_comtrade_d:,.0f}k; {r.hs6_top}")]:
    for r in t.itertuples():
        s = p[(p.iso3_o == r.iso3_o) & (p.iso3_d == r.iso3_d) & (p.year == r.year)]
        v = float(s.v_ttl_k.sum())
        rows.append(dict(screen=tag, flag="PAIR_OUTLIER" if tag == "T2" else "SHARE>20%", year=r.year, iso3_o=r.iso3_o, iso3_d=r.iso3_d,
                         metric=met(r), value_k=v, rows_vis=int(s.s_base_vis.sum()), rows_tour=int(s.s_base_tour.sum()),
                         share_vis=float(s.loc[s.s_base_vis == 1, "v_ttl_k"].sum() / TV), share_tour=float(s.loc[s.s_base_tour == 1, "v_ttl_k"].sum() / TT),
                         top_hs6=str(r.hs6_top).split(":")[0]))
F = pd.DataFrame(rows)
F["base_share_max"] = F[["share_vis", "share_tour"]].max(axis=1)
F = F.sort_values(["base_share_max", "value_k"], ascending=False)
F.to_csv(OUT / "TRADE_FLAGS.csv", index=False)
print(F.groupby("screen").agg(n=("year", "size"), in_vis=("rows_vis", "sum"), in_tour=("rows_tour", "sum"),
                              share_vis=("share_vis", "sum"), share_tour=("share_tour", "sum")).to_string())

# ---------------------------------------------------------------- HS6-level evidence for pair-year flags in a baseline
cand = F[(F.screen.isin(["T2", "T3"])) & ((F.rows_vis + F.rows_tour) > 0)].drop_duplicates(["year", "iso3_o", "iso3_d"])
mapping = pd.read_csv(CT / "concordance/reported_HS_to_H3_concordance.csv", dtype={"source_code": "string"})
mapping["source_code"] = mapping["source_code"].str.zfill(6)
avail = pd.read_csv(CT / "classification_availability/reported_classification_availability_2007_2021.csv")
pref = pd.read_csv(CT / "reference/partner_reference.csv")
iso2rep = avail.groupby("reporterISO").reporterCode.first().to_dict()
iso2rep["TWN"] = 490
iso2par = pref.dropna(subset=["partnerISO"]).groupby("partnerISO").partnerCode.apply(list).to_dict()
iso2par["TWN"] = [490]
need = ["refYear", "reporterCode", "partnerCode", "classificationCode", "cmdCode", "primaryValue", "netWgt", "qty", "qtyUnitCode", "cifvalue", "fobvalue"]


def readall(folder):
    parts = []
    for f in sorted(folder.glob("*.csv")):
        if f.stat().st_size == 0:
            continue
        try:
            d = pd.read_csv(f, usecols=need, dtype={"classificationCode": str, "cmdCode": str}, low_memory=False)
        except pd.errors.EmptyDataError:
            continue
        parts.append(d)
    d = pd.concat(parts, ignore_index=True)
    d["cmdCode"] = d.cmdCode.astype(str).str.replace(r"\.0$", "", regex=True).str.zfill(6)
    return d


imp = readall(PKG / "01_raw/02_UN_Comtrade/trade_api/reported_HS")
mir = readall(PKG / "01_raw/02_UN_Comtrade/mirror_exporter_reported/trade_api/reported_HS")
ev = []
for r in cand.itertuples():
    rc_imp = iso2rep.get(r.iso3_d)
    pcs_exp = iso2par.get(r.iso3_o, [])
    rc_exp = iso2rep.get(r.iso3_o)
    pcs_imp = iso2par.get(r.iso3_d, [])
    a = imp[(imp.refYear == r.year) & (imp.reporterCode == rc_imp) & imp.partnerCode.isin(pcs_exp)]
    b = mir[(mir.refYear == r.year) & (mir.reporterCode == rc_exp) & mir.partnerCode.isin(pcs_imp)] if rc_exp is not None else mir.iloc[0:0]
    top = a.sort_values("primaryValue", ascending=False).head(3)
    for t in top.itertuples():
        bb = b[b.cmdCode == t.cmdCode]
        ev.append(dict(year=r.year, iso3_o=r.iso3_o, iso3_d=r.iso3_d, screen=r.screen, rows_vis=r.rows_vis, rows_tour=r.rows_tour,
                       share_vis=r.share_vis, share_tour=r.share_tour, cls=t.classificationCode, cmd=t.cmdCode,
                       imp_usd=t.primaryValue, imp_netwgt_kg=t.netWgt, imp_usd_per_kg=(t.primaryValue / t.netWgt) if t.netWgt and t.netWgt > 0 else np.nan,
                       imp_qty=t.qty, mirror_usd=float(bb.primaryValue.sum()) if len(bb) else np.nan,
                       mirror_netwgt_kg=float(bb.netWgt.sum()) if len(bb) else np.nan,
                       mirror_reported=bool(len(b)), reporter_code=rc_imp, partner_codes=";".join(map(str, pcs_exp)), exporter_code=rc_exp))
E = pd.DataFrame(ev)
E["imp_over_mirror"] = E.imp_usd / E.mirror_usd
E.to_csv(OUT / "TRADE_FLOW_EVIDENCE.csv", index=False)
pd.set_option("display.width", 250)
print(E.sort_values("imp_usd", ascending=False).head(40)[["year", "iso3_o", "iso3_d", "cmd", "imp_usd", "imp_netwgt_kg", "imp_usd_per_kg", "mirror_usd", "imp_over_mirror", "rows_vis", "rows_tour"]].to_string())

"""SW2_07: trade screens T1-T4 on the raw UN Comtrade API files (read-only).
Basket as built (LB): SAFE concordance rows only (AMBIGUOUS_POOL_v_8523 excluded), primaryValue/1000
(STUDENT/COPY 05_build_cultural_trade.py; rules restated in 02_code/10_analysis/01a_hs6_products.py:1-20);
reporter ISO from reporter-year availability, partner ISO from partner reference; corrected vintage C02
(code 490 -> TWN, COPY config/special_area_crosswalk.csv); country table = valid ISO3, 2007-2021, non-domestic.
Mirror = exporter-reported exports (flowCode X) with the same concordance/references
(PKG 06_UN_Comtrade_mirror/03_build_exporter_reported_cultural_trade.py:21-24, 108-121).
Outputs: 05_output/11_data_screens/T*.csv, SW2_07_positive_controls.csv. No value is altered.
"""
import re
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
PCS = []


def pc(screen, name, expected, observed, ok):
    PCS.append({"screen": screen, "control": name, "expected": expected, "observed": observed, "result": "PASS" if ok else "FAIL"})
    print(f"PC {screen} {name}: {'PASS' if ok else 'FAIL'} | exp {expected} | obs {observed}")


mapping = pd.read_csv(CT / "concordance/reported_HS_to_H3_concordance.csv", dtype={"source_code": "string"})
mapping["source_code"] = mapping["source_code"].str.zfill(6)
safe = mapping.mapping_status.eq("SAFE_CATEGORY_MAPPING")
mapping["h3"] = np.where(safe, mapping.canonical_H3_codes_touched.astype(str), "AMB")
avail = pd.read_csv(CT / "classification_availability/reported_classification_availability_2007_2021.csv")
pref = pd.read_csv(CT / "reference/partner_reference.csv")
xw = pd.read_csv(COPY / "02_code/00_common/01_UN_Comtrade/config/special_area_crosswalk.csv")


def load(folder, pat, cols):
    parts = []
    for p in sorted(folder.glob("*.csv")):
        if p.stat().st_size == 0:
            continue
        try:
            d = pd.read_csv(p, usecols=cols, dtype={"classificationCode": str, "cmdCode": str}, low_memory=False)
        except pd.errors.EmptyDataError:
            continue
        d["file"] = p.name
        parts.append(d)
    raw = pd.concat(parts, ignore_index=True)
    raw["cmdCode"] = raw.cmdCode.astype(str).str.replace(r"\.0$", "", regex=True).str.zfill(6)
    raw["primaryValue"] = pd.to_numeric(raw.primaryValue, errors="raise")
    raw = raw.merge(mapping[["source_version", "source_code", "h3", "pipeline_treatment"]],
                    left_on=["classificationCode", "cmdCode"], right_on=["source_version", "source_code"], how="left")
    rmap = avail[["_query_year", "reporterCode", "reporterISO"]].rename(columns={"_query_year": "refYear"})
    raw = raw.merge(rmap, on=["refYear", "reporterCode"], how="left")
    raw = raw.merge(pref[["partnerCode", "partnerISO"]], on="partnerCode", how="left")
    for role, code, iso in [("reporter", "reporterCode", "reporterISO"), ("partner", "partnerCode", "partnerISO")]:
        mp = xw.loc[xw.applies_to.eq(role)].set_index("comtrade_code").iso3
        raw[iso] = raw[code].map(mp).fillna(raw[iso])
    raw["reporterISO"] = raw.reporterISO.fillna("").astype(str)
    raw["partnerISO"] = raw.partnerISO.fillna("").astype(str)
    return raw


cols = ["refYear", "reporterCode", "partnerCode", "classificationCode", "cmdCode", "primaryValue", "isReported"]
imp = load(PKG / "01_raw/02_UN_Comtrade/trade_api/reported_HS", None, cols)
pc("T0", "importer raw rows", "1,611,818 (frozen_snapshot_expectations, 01a_hs6_products.py:85)", f"{len(imp):,}", len(imp) == 1611818)
assert imp.pipeline_treatment.notna().all() and (imp.reporterISO != "").all()
mir = load(PKG / "01_raw/02_UN_Comtrade/mirror_exporter_reported/trade_api/reported_HS", None,
           cols + ["flowCode"])
print("mirror rows", len(mir), "unmapped concordance", int(mir.pipeline_treatment.isna().sum()), "flows", mir.flowCode.unique())

# ------------------------------------------------------------ T4 (raw level)
t4 = []
ed = imp.groupby(["refYear", "reporterCode", "reporterISO"]).classificationCode.agg(lambda s: ";".join(sorted(set(s)))).reset_index()
two = ed[ed.classificationCode.str.contains(";")]
t4.append(("importer reporter-years with records in >1 HS edition", len(two), two.to_dict("records")[:20]))
dupk = ["refYear", "reporterCode", "partnerCode", "cmdCode"]
dup = imp[imp.duplicated(dupk, keep=False)]
t4.append(("importer duplicate (year, reporter, partner, cmdCode) across files/editions", len(dup), dup.head(20).to_dict("records")))
dup5 = imp[imp.duplicated(dupk + ["classificationCode"], keep=False)]
t4.append(("importer exact duplicate keys incl. edition", len(dup5), []))
# same flow counted twice through two partner codes mapping to one ISO in one reporter-year
cty = imp[imp.partnerISO.str.fullmatch(r"[A-Z]{3}") & imp.reporterISO.str.fullmatch(r"[A-Z]{3}")]
pc2 = cty.groupby(["refYear", "reporterCode", "partnerISO", "cmdCode"]).partnerCode.nunique()
multi = pc2[pc2 > 1].reset_index()
mm = cty.merge(multi[["refYear", "reporterCode", "partnerISO", "cmdCode"]], on=["refYear", "reporterCode", "partnerISO", "cmdCode"])
t4.append(("importer: one (year, reporter, partner ISO, cmd) fed by >1 partner code", len(multi),
           mm.groupby(["partnerISO", "partnerCode"]).agg(rows=("primaryValue", "size"), usd=("primaryValue", "sum")).reset_index().to_dict("records")))
rc2 = cty.groupby(["refYear", "reporterISO"]).reporterCode.nunique()
t4.append(("importer: one (year, reporter ISO) fed by >1 reporter code", int((rc2 > 1).sum()), rc2[rc2 > 1].reset_index().to_dict("records")))
edm = mir.groupby(["refYear", "reporterCode"]).classificationCode.nunique()
t4.append(("mirror reporter-years with >1 HS edition", int((edm > 1).sum()), []))
dupm = mir[mir.duplicated(dupk, keep=False)]
t4.append(("mirror duplicate (year, reporter, partner, cmdCode)", len(dupm), dupm.head(10).to_dict("records")))
T4 = pd.DataFrame(t4, columns=["check", "count", "examples"])
T4.to_csv(OUT / "T4_classification_duplicates.csv", index=False)
print(T4[["check", "count"]].to_string())

# ------------------------------------------------------------ basket as built (LB) at dyad-year
lb = imp[imp.pipeline_treatment != "AMBIGUOUS_POOL_v_8523"]
valid = lb.reporterISO.str.fullmatch(r"[A-Z]{3}") & lb.partnerISO.str.fullmatch(r"[A-Z]{3}") & lb.refYear.between(2007, 2021) & (lb.reporterISO != lb.partnerISO)
lbc = lb[valid].copy()
dy = lbc.groupby(["refYear", "partnerISO", "reporterISO"]).primaryValue.sum().div(1000).rename("lb_k").reset_index()
dy = dy.rename(columns={"refYear": "year", "partnerISO": "iso3_o", "reporterISO": "iso3_d"})
comp = lbc.groupby(["refYear", "partnerISO", "reporterISO", "h3"]).primaryValue.sum().div(1000).reset_index()
comp = comp.rename(columns={"refYear": "year", "partnerISO": "iso3_o", "reporterISO": "iso3_d"})

p = pd.read_csv(OUT / "work/prepared_corrected_slim.csv.gz", low_memory=False)
p["year"] = p.year.astype(str).str[:4].astype(int)
x = p[["year", "iso3_o", "iso3_d", "v_ttl_k", "comtrade_reporting_available"]].merge(dy, on=["year", "iso3_o", "iso3_d"], how="left")
both = x.lb_k.notna()
diff = (x.loc[both, "lb_k"] - x.loc[both, "v_ttl_k"]).abs().max()
zero_ok = ((x.lb_k.isna()) & (x.comtrade_reporting_available == 1)).sum()
zero_eq = ((x.lb_k.isna()) & (x.comtrade_reporting_available == 1) & (x.v_ttl_k == 0)).sum()
pc("T0", "rebuilt LB basket = prepared v_ttl_k (corrected)", "max |diff| < 1e-6 on raw dyad-years; zero on available importer-years without rows",
   f"rows {int(both.sum()):,}, max|diff| {diff:.2e}; zeros {zero_eq:,} of {zero_ok:,}", diff < 1e-6 and zero_eq == zero_ok)

# ------------------------------------------------------------ T1 reporter-year totals and mirror
ry = lbc.groupby(["refYear", "reporterISO"]).primaryValue.sum().div(1000).rename("imp_k").reset_index()
ry = ry.rename(columns={"refYear": "year", "reporterISO": "iso3"})
av = avail[["_query_year", "reporterISO"]].rename(columns={"_query_year": "year", "reporterISO": "iso3"})
av["iso3"] = av.iso3.replace({"S19": "TWN"})
ry = av.merge(ry, on=["year", "iso3"], how="left")
ry["imp_k"] = ry.imp_k.fillna(0.0)
ry = ry.sort_values(["iso3", "year"])
ry["year_prev"] = ry.groupby("iso3").year.shift()
ry["imp_prev"] = ry.groupby("iso3").imp_k.shift()
c1 = ry.year - ry.year_prev == 1
ry["yoy"] = np.where(c1 & (ry.imp_prev > 0), ry.imp_k / ry.imp_prev, np.nan)
ry["T1a_flag"] = (ry.yoy > 10) | (ry.yoy < 0.1)
mlb = mir[(mir.pipeline_treatment.notna()) & (mir.pipeline_treatment != "AMBIGUOUS_POOL_v_8523")]
mlb = mlb[mlb.reporterISO.str.fullmatch(r"[A-Z]{3}") & mlb.partnerISO.str.fullmatch(r"[A-Z]{3}") & mlb.refYear.between(2007, 2021) & (mlb.reporterISO != mlb.partnerISO)]
mt = mlb.groupby(["refYear", "partnerISO"]).agg(mir_k=("primaryValue", "sum"), n_exporters=("reporterISO", "nunique")).reset_index()
mt["mir_k"] /= 1000
mt = mt.rename(columns={"refYear": "year", "partnerISO": "iso3"})
ry = ry.merge(mt, on=["year", "iso3"], how="left")
ry["imp_mir"] = np.where(ry.mir_k > 0, ry.imp_k / ry.mir_k, np.nan)
ry["T1b_flag"] = (ry.imp_mir > 10) | (ry.imp_mir < 0.1) | ((ry.imp_k == 0) & (ry.mir_k > 1000))
ry.to_csv(OUT / "T1_reporter_year_totals.csv", index=False)
x = ry[(ry.iso3 == "AFG") & ry.year.between(2009, 2017)]
pc("T1", "C09 AFG 2009-2017 (available, no basket rows) flagged by importer-vs-mirror", ">=1 year flagged (imp 0, mirror > 1,000)",
   f"{int(x.T1b_flag.sum())} of {len(x)}; mirror_k={x.mir_k.round(0).tolist()}", x.T1b_flag.sum() >= 1)

# ------------------------------------------------------------ T2 pair-year outliers
pos = dy[dy.lb_k > 0]
st = pos.groupby(["iso3_o", "iso3_d"]).lb_k.agg(n_pos="size", med="median").reset_index()
pos = pos.merge(st, on=["iso3_o", "iso3_d"])
t2 = pos[(pos.n_pos >= 5) & (pos.lb_k > 100 * pos.med)].copy()
t2["x_median"] = t2.lb_k / t2.med
compw = comp.pivot_table(index=["year", "iso3_o", "iso3_d"], columns="h3", values="primaryValue", aggfunc="sum").fillna(0)
def topcodes(r):
    row = compw.loc[(r.year, r.iso3_o, r.iso3_d)]
    row = row[row > 0].sort_values(ascending=False)
    return "; ".join(f"{k}:{v:,.0f}" for k, v in row.head(4).items())
t2["hs6_top"] = [topcodes(r) for r in t2.itertuples()]
t2 = t2.sort_values("lb_k", ascending=False)
t2.to_csv(OUT / "T2_pair_year_outliers.csv", index=False)
print("T2 flags", len(t2))

# ------------------------------------------------------------ T3 share of CEPII total imports
t3 = p[(p.tradeflow_comtrade_d > 1000) & (p.v_ttl_k > 0.2 * p.tradeflow_comtrade_d)].copy()
t3["share"] = t3.v_ttl_k / t3.tradeflow_comtrade_d
t3 = t3.sort_values("v_ttl_k", ascending=False)
t3["hs6_top"] = [topcodes(r) if (r.year, r.iso3_o, r.iso3_d) in compw.index else "" for r in t3.itertuples()]
t3[["year", "iso3_o", "iso3_d", "v_ttl_k", "tradeflow_comtrade_d", "share", "s_base_vis", "s_base_tour", "hs6_top"]].to_csv(OUT / "T3_share_of_total_imports.csv", index=False)
print("T3 flags", len(t3))
pd.DataFrame(PCS).to_csv(OUT / "SW2_07_positive_controls.csv", index=False)
comp.to_csv(OUT / "work/hs6_comp_lb.csv.gz", index=False, compression="gzip")
dy.to_csv(OUT / "work/dyad_lb.csv.gz", index=False, compression="gzip")

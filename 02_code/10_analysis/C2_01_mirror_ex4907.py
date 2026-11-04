"""C2_01_mirror_ex4907.py -- rerun C2: exporter-reported mirror input for vintage corrected2x.

Purpose: in corrected2x the outcome is the 30-code basket (31-code LB basket minus HS 490700) on the
importer side; the reporting-side checks (A1.9 A4, A2.3 T4) compare it with exporter-reported trade, so the
exporter side must be the same 30-code basket. COPY's mirror_analysis_ready.dta carries only the 31-code
exporter LB total (v_ttl_exporter_lb_k), so the exporter-reported HS6 rows are rebuilt from the raw mirror
files with the original rules and the 490700 lines are removed.

Rules (source): COPY 02_code/03_Mobility/01_database_preparation/04_UN_Comtrade_mirror/
03_build_exporter_reported_cultural_trade.py -- raw stacking of DOWNLOADED_OK manifest files (lines 40-82),
concordance merge (108-119), reporter ISO from the frozen reporter-year availability (121-127), partner ISO
from the partner reference (129-134), C02-M crosswalk code 490 -> TWN (135-136; rule file
02_code/00_common/01_UN_Comtrade/config/special_area_crosswalk.csv, as 01a_hs6_products.py), LB = v_3706 +
v_49 + v_8523(id) + v_97 (213-221; ambiguous 8523 pool excluded); 02_sensitivity/
04_build_mirror_analysis_input.py -- valid ISO3 keys (57-61), zero where export reporting is available and no
sparse row, missing where not available (106-112). Values primaryValue / 1000 (thousand current USD).
Positive control (fail closed): the rebuilt 31-code exporter LB equals COPY's v_ttl_exporter_lb_k on every
master row (sparse rows: |diff| <= 1e-6 + 1e-9|v|; other available rows: 0; unavailable: missing).
Importer side: v_ttl_k of out/corrected2x/prepared.dta (= v_ttl_ex4907), asserted equal to v_ttl_ex4907.
No data value is altered. Writes only out/corrected2x/mirror_analysis_ready_ex4907.dta and
out/corrected2x/mirror_ex4907_controls.csv.
Usage: python3 -I C2_01_mirror_ex4907.py
"""
import json
import re
import sys
from pathlib import Path

import numpy as np
import pandas as pd

import os
ROOT = Path(os.environ.get("PKG_ROOT") or Path(__file__).resolve().parents[2])  # package root
COPY = ROOT  # corrected chapter build of this package
CT = COPY / "03_intermediate/00_common/01_UN_Comtrade"
RAW = COPY / "01_raw/02_UN_Comtrade/mirror_exporter_reported"
# the analysis run read the corrected chapter files from a frozen snapshot with the same subfolder names
SNAP = ROOT
MIRROR = SNAP / "03_intermediate/03_Mobility/sensitivity/04_mirror_trade/mirror_analysis_ready.dta"
XW = COPY / "02_code/00_common/01_UN_Comtrade/config/special_area_crosswalk.csv"
OUT = ROOT / "05_output/10_analysis/corrected2x"
PREP = OUT / "prepared.dta"
controls = []


def pc(name, expected, observed, ok):
    controls.append({"control": name, "expected": expected, "observed": observed, "result": "PASS" if ok else "FAIL"})
    print(f"PC {name}: {'PASS' if ok else 'FAIL'} | expected {expected} | observed {observed}")


mapping = pd.read_csv(CT / "concordance/reported_HS_to_H3_concordance.csv", dtype={"source_code": "string"})
mapping["source_code"] = mapping["source_code"].str.zfill(6)
safe = mapping.mapping_status.eq("SAFE_CATEGORY_MAPPING")
assert (mapping.loc[~safe, "pipeline_treatment"] == "AMBIGUOUS_POOL_v_8523").all()
assert ((mapping.canonical_H3_codes_touched.astype(str).str.count(";") + 1)[safe] == 1).all()
mapping["h3"] = np.where(safe, mapping.canonical_H3_codes_touched.astype(str), "AMB")
avail = pd.read_csv(CT / "classification_availability/reported_classification_availability_2007_2021.csv")
pref = pd.read_csv(CT / "reference/partner_reference.csv")
pref["partnerCode"] = pd.to_numeric(pref["partnerCode"], errors="coerce")
xw = pd.read_csv(XW)
assert list(xw) == ["comtrade_code", "iso3", "applies_to", "source_url", "quote"]

man = pd.read_csv(RAW / "acquisition_metadata/exporter_trade_download_manifest.csv")
man = man.loc[man.status == "DOWNLOADED_OK"]
cols = ["refYear", "reporterCode", "partnerCode", "classificationCode", "cmdCode", "primaryValue", "flowCode"]
parts, empty = [], 0
for fn in man.filename.astype(str).unique():
    p = RAW / "trade_api/reported_HS" / fn
    assert p.exists(), p
    if p.stat().st_size == 0:
        empty += 1
        continue
    try:
        d = pd.read_csv(p, usecols=cols, dtype={"classificationCode": str, "cmdCode": str}, low_memory=False)
    except pd.errors.EmptyDataError:
        empty += 1
        continue
    parts.append(d)
raw = pd.concat(parts, ignore_index=True)
assert (raw.flowCode.astype(str) == "X").all()
raw["cmdCode"] = raw.cmdCode.astype(str).str.replace(r"\.0$", "", regex=True).str.zfill(6)
raw["primaryValue"] = pd.to_numeric(raw.primaryValue, errors="raise")
assert raw.primaryValue.notna().all() and (raw.primaryValue >= 0).all()
assert not raw.duplicated(["refYear", "reporterCode", "partnerCode", "classificationCode", "cmdCode"]).any()
raw = raw.merge(mapping[["source_version", "source_code", "h3", "pipeline_treatment"]],
                left_on=["classificationCode", "cmdCode"], right_on=["source_version", "source_code"], how="left", validate="m:1")
assert raw.pipeline_treatment.notna().all()
rmap = avail[["_query_year", "reporterCode", "reporterISO", "classificationCode"]].rename(
    columns={"_query_year": "refYear", "classificationCode": "avail_cls"})
raw = raw.merge(rmap, on=["refYear", "reporterCode"], how="left", validate="m:1")
assert raw.reporterISO.notna().all() and (raw.classificationCode == raw.avail_cls).all()
raw = raw.merge(pref[["partnerCode", "partnerISO"]], on="partnerCode", how="left", validate="m:1")
assert raw.partnerCode.isin(pref.partnerCode).all()
for role, code, iso in [("reporter", "reporterCode", "reporterISO"), ("partner", "partnerCode", "partnerISO")]:
    mp = xw.loc[xw.applies_to.eq(role)].set_index("comtrade_code").iso3
    raw[iso] = raw[code].map(mp).fillna(raw[iso])
raw["reporterISO"] = raw.reporterISO.fillna("").astype(str)
raw["partnerISO"] = raw.partnerISO.fillna("").astype(str)
print("raw mirror rows", len(raw), "files", len(parts), "empty", empty)

lb = raw[raw.pipeline_treatment != "AMBIGUOUS_POOL_v_8523"]
ok = (lb.reporterISO.str.fullmatch(r"[A-Z]{3}") & lb.partnerISO.str.fullmatch(r"[A-Z]{3}")
      & lb.refYear.between(2007, 2021) & (lb.reporterISO != lb.partnerISO))
lb = lb[ok].copy()
lb["is4907"] = lb.h3.eq("490700")
g = lb.groupby(["refYear", "reporterISO", "partnerISO"])
dy = pd.DataFrame({
    "lb31_usd": g.primaryValue.sum(),
    "x4907_usd": lb[lb.is4907].groupby(["refYear", "reporterISO", "partnerISO"]).primaryValue.sum(),
    "lb30_usd": lb[~lb.is4907].groupby(["refYear", "reporterISO", "partnerISO"]).primaryValue.sum(),
}).reset_index()
dy[["x4907_usd", "lb30_usd"]] = dy[["x4907_usd", "lb30_usd"]].fillna(0.0)
dy = dy.rename(columns={"refYear": "year", "reporterISO": "iso3_o", "partnerISO": "iso3_d"})
for c in ["lb31", "x4907", "lb30"]:
    dy[c + "_k"] = dy[c + "_usd"] / 1000.0
assert not dy.duplicated(["year", "iso3_o", "iso3_d"]).any()

mir = pd.read_stata(MIRROR, columns=["year", "iso3_o", "iso3_d", "v_ttl_k", "v_ttl_exporter_lb_k",
                                     "export_trade_reporting_available"], convert_categoricals=False, convert_dates=False)
mir["year"] = pd.to_numeric(mir.year).astype(int)
assert len(mir) == 823446 and not mir.duplicated(["year", "iso3_o", "iso3_d"]).any()
x = mir.merge(dy[["year", "iso3_o", "iso3_d", "lb31_k", "x4907_k", "lb30_k"]], on=["year", "iso3_o", "iso3_d"],
              how="left", indicator=True, validate="1:1")
outside = len(dy) - int((x._merge == "both").sum())
present = x._merge.eq("both")
avl = x.export_trade_reporting_available.eq(1)
d = (x.loc[present, "lb31_k"] - x.loc[present, "v_ttl_exporter_lb_k"]).abs()
tol = 1e-6 + 1e-9 * x.loc[present, "v_ttl_exporter_lb_k"].abs()
pc("rebuilt exporter 31-code LB = COPY v_ttl_exporter_lb_k on sparse rows", "0 rows beyond 1e-6+1e-9|v|",
   f"{int((d > tol).sum())} of {int(present.sum())} (max |diff| {d.max():.3e})", int((d > tol).sum()) == 0)
pc("sparse rows only where export reporting is available", "0", int((present & ~avl).sum()), int((present & ~avl).sum()) == 0)
z = avl & ~present
pc("available, no sparse row -> COPY value 0", "all 0", f"{int((x.loc[z, 'v_ttl_exporter_lb_k'] == 0).sum())} of {int(z.sum())}",
   bool((x.loc[z, "v_ttl_exporter_lb_k"] == 0).all()))
pc("not available -> COPY value missing", "all missing", f"{int(x.loc[~avl, 'v_ttl_exporter_lb_k'].isna().sum())} of {int((~avl).sum())}",
   bool(x.loc[~avl, "v_ttl_exporter_lb_k"].isna().all()))
print("rebuilt dyad-years outside the master universe (dropped, as the original merge):", outside)

x["v_ttl_exporter_lb31_k"] = x.v_ttl_exporter_lb_k
x["x4907_exporter_k"] = np.where(present, x.x4907_k, np.where(avl, 0.0, np.nan))
x["v_ttl_exporter_ex4907_k"] = np.where(present, x.lb30_k, np.where(avl, 0.0, np.nan))
dd = (x.v_ttl_exporter_lb31_k - x.v_ttl_exporter_ex4907_k - x.x4907_exporter_k).abs()
pc("exporter: 31-code LB - 30-code = exporter HS 490700 (all rows)", "max |diff| <= 1e-6",
   f"max {np.nanmax(dd.to_numpy()):.3e}; missingness equal {bool((x.v_ttl_exporter_lb31_k.isna() == x.v_ttl_exporter_ex4907_k.isna()).all())}",
   bool(np.nanmax(dd.to_numpy()) <= 1e-6) and bool((x.v_ttl_exporter_lb31_k.isna() == x.v_ttl_exporter_ex4907_k.isna()).all()))

prep = pd.read_stata(PREP, columns=["year", "iso3_o", "iso3_d", "v_ttl_k", "v_ttl_ex4907", "v_ttl31_k"], convert_categoricals=False, convert_dates=False)
prep["year"] = pd.to_numeric(prep.year).astype(int)
y = x.merge(prep, on=["year", "iso3_o", "iso3_d"], how="inner", suffixes=("_mirror31", ""), validate="1:1")
assert len(y) == 823446
eq31 = ((y.v_ttl_k_mirror31 == y.v_ttl31_k) | (y.v_ttl_k_mirror31.isna() & y.v_ttl31_k.isna())).all()
pc("COPY mirror importer v_ttl_k = corrected2x v_ttl31_k (31-code)", "all rows", bool(eq31), bool(eq31))
eqx = ((y.v_ttl_k == y.v_ttl_ex4907) | (y.v_ttl_k.isna() & y.v_ttl_ex4907.isna())).all()
pc("corrected2x v_ttl_k = v_ttl_ex4907", "all rows", bool(eqx), bool(eqx))

res = y[["year", "iso3_o", "iso3_d", "v_ttl_k", "export_trade_reporting_available"]].copy()
res["v_ttl_exporter_lb_k"] = y.v_ttl_exporter_ex4907_k
res["v_ttl_exporter_lb31_k"] = y.v_ttl_exporter_lb31_k
res["x4907_exporter_k"] = y.x4907_exporter_k
res["year"] = res.year.astype("int16")
res = res.sort_values(["year", "iso3_o", "iso3_d"]).reset_index(drop=True)
labels = {"v_ttl_k": "Importer-reported 30-code LB basket (corrected2x outcome), 1000 USD",
          "v_ttl_exporter_lb_k": "Exporter-reported 30-code LB basket (31-code LB minus HS 490700), 1000 USD",
          "v_ttl_exporter_lb31_k": "Exporter-reported 31-code LB basket (COPY mirror_analysis_ready.dta), 1000 USD",
          "x4907_exporter_k": "Exporter-reported HS 490700 (rebuilt from raw mirror files), 1000 USD",
          "export_trade_reporting_available": "Exporter-year export reporting available (COPY)"}
failed = [c for c in controls if c["result"] != "PASS"]
pd.DataFrame(controls).to_csv(OUT / "mirror_ex4907_controls.csv", index=False)
if failed:
    print("MIRROR_EX4907=FAIL", json.dumps(failed, indent=1))
    sys.exit(1)
res.to_stata(OUT / "mirror_analysis_ready_ex4907.dta", write_index=False, version=118, variable_labels=labels)
print("MIRROR_EX4907=PASS rows", len(res), "exporter 490700 total k", float(res.x4907_exporter_k.sum()))

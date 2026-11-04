import re
import numpy as np
import pandas as pd
from _mirror_paths import *
import importlib.util as _rescue_importlib  # RESCUE C02-M
_rescue_switch_path = ROOT / "02_code/99_rescue/rescue_switch.py"  # RESCUE C02-M
_rescue_c02m = False  # RESCUE C02-M
if _rescue_switch_path.is_file():  # RESCUE C02-M: old launcher without rescue helpers remains baseline.
    _rescue_spec = _rescue_importlib.spec_from_file_location("rescue_switch", _rescue_switch_path)  # RESCUE C02-M
    _rescue_switch = _rescue_importlib.module_from_spec(_rescue_spec)  # RESCUE C02-M
    _rescue_spec.loader.exec_module(_rescue_switch)  # RESCUE C02-M
    _rescue_c02m = _rescue_switch.enabled("C02-M")  # RESCUE C02-M
if _rescue_c02m:  # RESCUE C02-M
    _rescue_spec = _rescue_importlib.spec_from_file_location("mirror_crosswalk", ROOT / "02_code/99_rescue/I-M2/mirror_crosswalk.py")  # RESCUE C02-M
    _rescue_area = _rescue_importlib.module_from_spec(_rescue_spec)  # RESCUE C02-M
    _rescue_spec.loader.exec_module(_rescue_area)  # RESCUE C02-M
    _rescue_rules = _rescue_area.load_crosswalk(MAIN_CT_CODE / "config/special_area_crosswalk.csv")  # RESCUE C02-M

ensure_dirs()

needed=[
    MAIN_AVAIL, MAIN_CONCORD, MAIN_PREF,
    RAW_META/"export_flow_availability_manifest.csv",
    RAW_META/"exporter_trade_download_manifest.csv",
]
missing=[str(p) for p in needed if not p.exists()]
if missing:
    print("MIRROR_EXPORTER_BUILD=FAIL")
    print("Missing completed download/shared inputs:")
    for p in missing:
        print(" -",p)
    raise SystemExit(1)

avail=pd.read_csv(MAIN_AVAIL)
mapping=pd.read_csv(MAIN_CONCORD,dtype={"source_code":"string"})
mapping["source_code"]=mapping["source_code"].str.zfill(6)
pref=pd.read_csv(MAIN_PREF)
pref["partnerCode"]=pd.to_numeric(pref["partnerCode"],errors="coerce")

trade_manifest=pd.read_csv(RAW_META/"exporter_trade_download_manifest.csv")
trade_manifest=trade_manifest.loc[trade_manifest["status"]=="DOWNLOADED_OK"].copy()

raw_files=[RAW_TRADE/f for f in trade_manifest["filename"].astype(str).unique()]
for p in raw_files:
    if not p.exists():
        raise RuntimeError(f"Manifest raw file missing: {p}")

usecols=[
    "refYear","reporterCode","partnerCode","classificationCode",
    "classificationSearchCode","isOriginalClassification","cmdCode","flowCode",
    "partner2Code","customsCode","motCode","primaryValue","cifvalue","fobvalue",
    "legacyEstimationFlag","isReported","isAggregate"
]

parts=[]
empty_files=[]
for p in raw_files:
    try:
        if p.stat().st_size==0:
            raise pd.errors.EmptyDataError
        header=list(pd.read_csv(p,nrows=0).columns)
        if len(header)==0:
            raise pd.errors.EmptyDataError
        miss=[c for c in usecols if c not in header]
        if miss:
            raise RuntimeError(f"Raw schema mismatch {p.name}: missing {miss}")
        df=pd.read_csv(p,usecols=usecols,low_memory=False)
    except pd.errors.EmptyDataError:
        mr=trade_manifest.loc[trade_manifest["filename"].astype(str)==p.name]
        if len(mr)!=1 or int(pd.to_numeric(mr.iloc[0]["data_rows"],errors="coerce"))!=0:
            raise RuntimeError(f"Unexpected empty raw CSV: {p.name}")
        empty_files.append(p.name)
        continue

    if len(df):
        df["_source_file"]=p.name
        parts.append(df)

if not parts:
    raise RuntimeError("No non-empty exporter-reported trade files.")

raw=pd.concat(parts,ignore_index=True)

# Query provenance
assert (raw["classificationSearchCode"].astype(str)=="HS").all()
assert (raw["flowCode"].astype(str)=="X").all()
assert (pd.to_numeric(raw["partner2Code"],errors="coerce")==0).all()
assert (raw["customsCode"].astype(str)=="C00").all()
assert (pd.to_numeric(raw["motCode"],errors="coerce")==0).all()

orig=raw["isOriginalClassification"].astype(str).str.lower()
assert orig.isin(["true","1"]).all()

raw["cmdCode"]=(
    raw["cmdCode"].astype(str)
    .str.replace(r"\.0$","",regex=True).str.zfill(6)
)
core_key=["refYear","reporterCode","partnerCode","classificationCode","cmdCode"]
dup_n=int(raw.duplicated(core_key,keep=False).sum())
if dup_n:
    raise RuntimeError(f"Duplicate exporter raw core keys: {dup_n}")

for c in ["primaryValue","cifvalue","fobvalue"]:
    raw[c]=pd.to_numeric(raw[c],errors="coerce")
assert raw["primaryValue"].notna().all()
assert (raw["primaryValue"]>=0).all()

# Concordance treatment
mapcols=[
    "source_version","source_code","mapping_status","pipeline_treatment",
    "canonical_H3_codes_touched","non_target_H3_codes"
]
raw=raw.merge(
    mapping[mapcols],
    left_on=["classificationCode","cmdCode"],
    right_on=["source_version","source_code"],
    how="left",validate="m:1"
)
assert raw["pipeline_treatment"].notna().all()

# Reporter ISO from same frozen reporter-year availability used in main build.
rmap=avail[
    ["_query_year","reporterCode","reporterISO","reporterDesc","classificationCode"]
].rename(columns={"_query_year":"refYear","classificationCode":"availability_classification"})
raw=raw.merge(rmap,on=["refYear","reporterCode"],how="left",validate="m:1")
assert raw["reporterISO"].notna().all()
assert (raw["classificationCode"]==raw["availability_classification"]).all()

# Partner/destination ISO from same frozen partner reference.
raw=raw.merge(
    pref[["partnerCode","partnerISO","partnerDesc","entryEffectiveDate","entryExpiredDate","isGroup"]],
    on="partnerCode",how="left",validate="m:1"
)
assert raw["partnerDesc"].notna().all()
if _rescue_c02m:  # RESCUE C02-M: numeric joins completed; map before grouping and later ISO panel merges.
    raw = _rescue_area.trade(raw, _rescue_rules)  # RESCUE C02-M

# Valuation audit. For exports UN methodology recommends FOB-type value.
pv=raw["primaryValue"].to_numpy(dtype=float)
cif=raw["cifvalue"].to_numpy(dtype=float)
fob=raw["fobvalue"].to_numpy(dtype=float)
eq_cif=np.isclose(pv,cif,rtol=0,atol=1e-9,equal_nan=False)
eq_fob=np.isclose(pv,fob,rtol=0,atol=1e-9,equal_nan=False)
neither=~(eq_cif|eq_fob)
if int(neither.sum())!=0:
    raise RuntimeError(
        f"{int(neither.sum())} exporter rows have primaryValue equal to neither CIF nor FOB."
    )

pd.DataFrame([{
    "raw_rows":len(raw),
    "primary_value_zero":int((raw["primaryValue"]==0).sum()),
    "primary_equals_fob":int(eq_fob.sum()),
    "primary_equals_cif":int(eq_cif.sum()),
    "primary_equals_neither":int(neither.sum()),
    "currency":"current USD",
    "analysis_scaling":"divide primaryValue by 1000",
    "flow":"X / exporter-reported exports",
    "partner_interpretation":"destination",
}]).to_csv(DIAG_BUILD/"exporter_valuation_audit.csv",index=False,encoding="utf-8-sig")

# Aggregate to categories using the same pipeline treatment as importer build.
isrep=raw["isReported"].astype(str).str.lower().isin(["true","1"])
raw["_unreported_or_estimated"]=(~isrep).astype("int8")

grp=(
    raw.groupby(
        ["refYear","reporterCode","reporterISO","partnerCode","partnerISO",
         "classificationCode","pipeline_treatment"],
        dropna=False
    )
    .agg(
        value_usd=("primaryValue","sum"),
        n_source_rows=("primaryValue","size"),
        n_unreported_rows=("_unreported_or_estimated","sum")
    )
    .reset_index()
)

idx=["refYear","reporterCode","reporterISO","partnerCode","partnerISO","classificationCode"]
val=grp.pivot_table(
    index=idx,columns="pipeline_treatment",values="value_usd",
    aggfunc="sum",fill_value=0
).reset_index()
val.columns.name=None
cnt=grp.groupby(idx,dropna=False).agg(
    n_source_rows=("n_source_rows","sum"),
    n_unreported_rows=("n_unreported_rows","sum")
).reset_index()
out=val.merge(cnt,on=idx,how="left",validate="1:1")
if _rescue_c02m:  # RESCUE C02-M: preserve the source codes/ISO and residual-territory caveat.
    out = out.merge(_rescue_area.sparse_provenance(raw), on=["refYear", "reporterCode", "partnerCode", "classificationCode"], how="left", validate="1:1")  # RESCUE C02-M

for c in ["v_3706","v_49","v_8523","v_97","AMBIGUOUS_POOL_v_8523"]:
    if c not in out.columns:
        out[c]=0.0
    out[c]=pd.to_numeric(out[c],errors="coerce").fillna(0.0)

out=out.rename(columns={
    "refYear":"year",
    "reporterCode":"reporter_code",
    "reporterISO":"reporter_iso",
    "partnerCode":"partner_code",
    "partnerISO":"partner_iso",
    "classificationCode":"hs_version",
    "v_3706":"v_3706_exporter_usd",
    "v_49":"v_49_exporter_usd",
    "v_8523":"v_8523_exporter_id_usd",
    "v_97":"v_97_exporter_usd",
    "AMBIGUOUS_POOL_v_8523":"v_8523_exporter_amb_usd",
})

out["v_8523_exporter_lb_usd"]=out["v_8523_exporter_id_usd"]
out["v_8523_exporter_ub_usd"]=(
    out["v_8523_exporter_id_usd"]+out["v_8523_exporter_amb_usd"]
)
out["v_8523_exporter_exact"]=(out["v_8523_exporter_amb_usd"]==0).astype("int8")
out["v_ttl_exporter_lb_usd"]=(
    out["v_3706_exporter_usd"]+out["v_49_exporter_usd"]+
    out["v_8523_exporter_lb_usd"]+out["v_97_exporter_usd"]
)
out["v_ttl_exporter_ub_usd"]=(
    out["v_3706_exporter_usd"]+out["v_49_exporter_usd"]+
    out["v_8523_exporter_ub_usd"]+out["v_97_exporter_usd"]
)
out["any_unreported_exporter"]=(out["n_unreported_rows"]>0).astype("int8")

for c in [
    "v_3706_exporter_usd","v_49_exporter_usd",
    "v_8523_exporter_id_usd","v_8523_exporter_amb_usd",
    "v_8523_exporter_lb_usd","v_8523_exporter_ub_usd",
    "v_97_exporter_usd","v_ttl_exporter_lb_usd","v_ttl_exporter_ub_usd"
]:
    out[c.replace("_usd","_k")]=out[c]/1000.0

assert np.allclose(
    out["v_ttl_exporter_lb_usd"],
    out["v_3706_exporter_usd"]+out["v_49_exporter_usd"]+
    out["v_8523_exporter_lb_usd"]+out["v_97_exporter_usd"],
    rtol=0,atol=1e-7
)
assert np.allclose(
    out["v_ttl_exporter_ub_usd"],
    out["v_3706_exporter_usd"]+out["v_49_exporter_usd"]+
    out["v_8523_exporter_ub_usd"]+out["v_97_exporter_usd"],
    rtol=0,atol=1e-7
)

# ISO-level key must be unique for direct merge to the directed-pair panel.
iso_check=out.loc[
    out["reporter_iso"].fillna("").astype(str).str.fullmatch(r"[A-Z]{3}") &
    out["partner_iso"].fillna("").astype(str).str.fullmatch(r"[A-Z]{3}")
].copy()
if _rescue_c02m:  # RESCUE C02-M: common-base country universe excludes groups97/975 and domestic.
    iso_check = iso_check.loc[iso_check["comtrade_country_eligible"].eq(1)].copy()  # RESCUE C02-M
if iso_check.duplicated(["year","reporter_iso","partner_iso"]).any():
    bad=iso_check.loc[
        iso_check.duplicated(["year","reporter_iso","partner_iso"],keep=False),
        ["year","reporter_code","reporter_iso","partner_code","partner_iso"]
    ]
    bad.to_csv(DIAG_BUILD/"duplicate_iso_merge_keys.csv",index=False,encoding="utf-8-sig")
    raise RuntimeError("Exporter sparse table has duplicate ISO merge keys.")

out=out.sort_values(["year","reporter_code","partner_code"]).reset_index(drop=True)
out.to_csv(FINAL_EXPORT_CSV,index=False,encoding="utf-8-sig")

stata=out.copy()
for c in ["reporter_iso","partner_iso","hs_version"]:
    stata[c]=stata[c].fillna("").astype(str)
stata.to_stata(FINAL_EXPORT,write_index=False,version=118)

# ---------------------------------------------------------------
# Export-flow reporter-year availability from TOTAL exports to World.
# ---------------------------------------------------------------
fa_manifest=pd.read_csv(RAW_META/"export_flow_availability_manifest.csv")
fa_manifest=fa_manifest.loc[fa_manifest["status"]=="DOWNLOADED_OK"].copy()

parts=[]
for fn in fa_manifest["filename"].astype(str).unique():
    p=RAW_FLOW_AVAIL/fn
    if not p.exists():
        raise RuntimeError(f"Export-flow availability file missing: {p}")
    try:
        if p.stat().st_size==0:
            continue
        df=pd.read_csv(p,low_memory=False)
    except pd.errors.EmptyDataError:
        continue
    if len(df):
        parts.append(df)

returned=set()
total_value={}
if parts:
    faraw=pd.concat(parts,ignore_index=True)
    if "flowCode" in faraw.columns:
        assert (faraw["flowCode"].astype(str)=="X").all()
    for _,r in faraw.iterrows():
        y=int(pd.to_numeric(r.get("refYear"),errors="coerce"))
        rep=int(pd.to_numeric(r.get("reporterCode"),errors="coerce"))
        returned.add((y,rep))
        val=pd.to_numeric(r.get("primaryValue"),errors="coerce")
        if pd.notna(val):
            total_value[(y,rep)]=float(val)

a=avail.rename(columns={
    "_query_year":"year",
    "reporterCode":"reporter_code",
    "reporterISO":"reporter_iso",
    "reporterDesc":"reporter_desc",
    "classificationCode":"hs_version"
})[["year","reporter_code","reporter_iso","reporter_desc","hs_version"]].copy()
if _rescue_c02m:  # RESCUE C02-M: same shared numeric-code convention for exporter-year support.
    a = _rescue_area.availability(a, _rescue_rules)  # RESCUE C02-M
a["export_trade_reporting_available"]=[
    1 if (int(y),int(r)) in returned else 0
    for y,r in zip(a["year"],a["reporter_code"])
]
a["world_export_primary_value_usd"]=[
    total_value.get((int(y),int(r)),np.nan)
    for y,r in zip(a["year"],a["reporter_code"])
]

a.to_csv(FINAL_EXPORT_AVAIL_CSV,index=False,encoding="utf-8-sig")
astata=a.copy()
for c in ["reporter_iso","reporter_desc","hs_version"]:
    astata[c]=astata[c].fillna("").astype(str)
astata.to_stata(FINAL_EXPORT_AVAIL,write_index=False,version=118)

summary=pd.DataFrame([{
    "raw_trade_files":len(raw_files),
    "raw_trade_rows":len(raw),
    "legitimate_zero_row_files":len(empty_files),
    "sparse_exporter_dyad_year_rows":len(out),
    "exporter_reporter_years_total":len(a),
    "exporter_reporter_years_available":int(a["export_trade_reporting_available"].sum()),
    "exporter_reporter_years_unavailable":int((a["export_trade_reporting_available"]==0).sum()),
    "positive_ambiguous_pool_dyads":int((out["v_8523_exporter_amb_usd"]>0).sum()),
    "flow":"X_exports",
    "reporter_interpretation":"trade exporter/origin iso3_o",
    "partner_interpretation":"trade importer/destination iso3_d",
    "baseline_mirror_outcome":"v_ttl_exporter_lb_k",
}])
summary.to_csv(DIAG_BUILD/"exporter_build_summary.csv",index=False,encoding="utf-8-sig")

(DIAG_BUILD/"EXPORTER_REPORTED_CULTURAL_TRADE_BUILD_COMPLETE.txt").write_text(
    "EXPORTER_REPORTED_CULTURAL_TRADE_BUILD_COMPLETE=yes\n"
    "flow=X_exports\n"
    "reporter_maps_to=iso3_o\n"
    "partner_maps_to=iso3_d\n"
    "baseline_mirror_outcome=v_ttl_exporter_lb_k\n",
    encoding="utf-8"
)

print("EXPORTER_REPORTED_CULTURAL_TRADE_BUILD_COMPLETE=yes")
print("Sparse exporter dyad-years:",len(out))
print("Exporter reporter-years available:",int(a["export_trade_reporting_available"].sum()))
print("Final source table:",FINAL_EXPORT)

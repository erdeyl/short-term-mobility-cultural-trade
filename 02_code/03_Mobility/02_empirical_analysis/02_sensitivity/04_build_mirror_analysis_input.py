import pandas as pd
from _mirror_paths import *

ensure_dirs()

required=[PREPARED_LB,FINAL_EXPORT,FINAL_EXPORT_AVAIL]
missing=[str(p) for p in required if not p.exists()]
if missing:
    print("MIRROR_ANALYSIS_INPUT_BUILD=FAIL")
    for p in missing:
        print(" -",p)
    raise SystemExit(1)

def normalize_year(df, name):
    """Normalize Stata/Pandas year representations to integer calendar years."""
    df = df.copy()
    if "year" not in df.columns:
        raise RuntimeError(f"{name} has no year variable.")

    if pd.api.types.is_datetime64_any_dtype(df["year"]):
        df["year"] = df["year"].dt.year
    else:
        df["year"] = pd.to_numeric(df["year"], errors="coerce")

    if df["year"].isna().any():
        raise RuntimeError(f"{name} contains non-convertible/missing year values.")

    if not df["year"].between(2007, 2021).all():
        bad = sorted(df.loc[~df["year"].between(2007, 2021), "year"].unique().tolist())
        raise RuntimeError(f"{name} contains years outside 2007-2021: {bad[:20]}")

    df["year"] = df["year"].astype("int32")
    return df

base=pd.read_stata(PREPARED_LB,convert_categoricals=False)
base=normalize_year(base,"prepared LB data")
if base.duplicated(["year","iso3_o","iso3_d"]).any():
    raise RuntimeError("Prepared LB data key is not unique.")

trade=pd.read_stata(FINAL_EXPORT,convert_categoricals=False)
trade=normalize_year(trade,"exporter-reported trade")
trade=trade.rename(columns={
    "reporter_iso":"iso3_o",
    "partner_iso":"iso3_d"
})

keep=[
    "year","iso3_o","iso3_d",
    "v_3706_exporter_k","v_49_exporter_k",
    "v_8523_exporter_lb_k","v_8523_exporter_ub_k",
    "v_8523_exporter_amb_k","v_97_exporter_k",
    "v_ttl_exporter_lb_k","v_ttl_exporter_ub_k",
    "v_8523_exporter_exact","hs_version"
]
trade=trade[keep].copy()

# Only rows with usable country ISO3 keys can merge to the directed-pair panel.
trade=trade.loc[
    trade["iso3_o"].fillna("").astype(str).str.fullmatch(r"[A-Z]{3}") &
    trade["iso3_d"].fillna("").astype(str).str.fullmatch(r"[A-Z]{3}")
].copy()
if trade.duplicated(["year","iso3_o","iso3_d"]).any():
    raise RuntimeError("Exporter trade ISO merge key is duplicated.")

avail=pd.read_stata(FINAL_EXPORT_AVAIL,convert_categoricals=False)
avail=normalize_year(avail,"exporter-year availability")
avail=avail.rename(columns={"reporter_iso":"iso3_o"})
avail=avail[["year","iso3_o","export_trade_reporting_available"]].copy()
if avail.duplicated(["year","iso3_o"]).any():
    raise RuntimeError("Exporter availability merge key is duplicated.")

out=base.merge(
    trade,on=["year","iso3_o","iso3_d"],how="left",
    validate="1:1",indicator="_merge_export_sparse"
)
out["exporter_sparse_row_present"]=(out["_merge_export_sparse"]=="both").astype("int8")
out=out.drop(columns=["_merge_export_sparse"])

out=out.merge(
    avail,on=["year","iso3_o"],how="left",
    validate="m:1"
)

# A sparse exporter cultural record may exist only when the reporter-year was
# verified to have exporter-flow reporting.
bad=out.loc[
    (out["exporter_sparse_row_present"]==1) &
    (out["export_trade_reporting_available"]!=1)
]
if len(bad):
    bad[["year","iso3_o","iso3_d","export_trade_reporting_available"]].to_csv(
        SENS_DIAG/"export_sparse_without_export_reporting.csv",
        index=False,encoding="utf-8-sig"
    )
    raise RuntimeError(
        f"{len(bad)} exporter sparse rows lack verified export-flow reporting availability."
    )

mirror_vars=[
    "v_3706_exporter_k","v_49_exporter_k",
    "v_8523_exporter_lb_k","v_8523_exporter_ub_k",
    "v_8523_exporter_amb_k","v_97_exporter_k",
    "v_ttl_exporter_lb_k","v_ttl_exporter_ub_k"
]

for v in mirror_vars:
    out.loc[
        (out["export_trade_reporting_available"]==1) & out[v].isna(),v
    ]=0.0
    out.loc[
        out["export_trade_reporting_available"]!=1,v
    ]=float("nan")

out["exporter_zero_fill_sparse"]=(
    (out["export_trade_reporting_available"]==1) &
    (out["exporter_sparse_row_present"]==0)
).astype("int8")

# Mechanical checks
for v in mirror_vars:
    if out.loc[out["export_trade_reporting_available"]!=1,v].notna().any():
        raise RuntimeError(f"{v} is nonmissing outside verified exporter reporting support.")

out_path=SENS_DATA/"mirror_analysis_ready.dta"
out.to_stata(out_path,write_index=False,version=118)

coverage=pd.DataFrame([{
    "prepared_rows":len(out),
    "rows_export_reporting_available":int((out["export_trade_reporting_available"]==1).sum()),
    "rows_export_sparse_present":int((out["exporter_sparse_row_present"]==1).sum()),
    "rows_export_zero_filled":int(out["exporter_zero_fill_sparse"].sum()),
    "mirror_total_lb_nonmissing":int(out["v_ttl_exporter_lb_k"].notna().sum()),
    "importer_total_lb_nonmissing":int(out["v_ttl_k"].notna().sum()),
    "visitor_mobility_nonmissing":int(out["mob_bilat_vis"].notna().sum()),
    "tourist_mobility_nonmissing":int(out["mob_bilat_tour"].notna().sum()),
}])
coverage.to_csv(SENS_DIAG/"mirror_analysis_coverage.csv",index=False,encoding="utf-8-sig")

(SENS_DIAG/"04_MIRROR_ANALYSIS_INPUT_COMPLETE.txt").write_text(
    "MIRROR_ANALYSIS_INPUT_BUILD=PASS\n"
    f"rows={len(out)}\n"
    "mirror_baseline=v_ttl_exporter_lb_k\n",
    encoding="utf-8"
)

print("MIRROR_ANALYSIS_INPUT_BUILD=PASS")
print("Saved:",out_path)
print(coverage.to_string(index=False))

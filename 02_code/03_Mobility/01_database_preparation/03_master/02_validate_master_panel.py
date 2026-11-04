import pandas as pd
import numpy as np
from _paths import *
from data_checks import assert_base_preserved

ensure_dirs()
SRC = CHAPTER_MERGED
if not SRC.exists():
    raise SystemExit("Run 01_build_master_panel.py first.")

df = pd.read_stata(SRC, convert_categoricals=False)
assert_base_preserved(df)

# Overall merge/coverage summary.
summary_metrics = [
    ("master_rows", len(df)),
    ("unique_years", df["year"].nunique()),
    ("unique_exporters_iso3_o", df["iso3_o"].nunique()),
    ("unique_importers_iso3_d", df["iso3_d"].nunique()),
    ("domestic_rows", int((df["iso3_o"]==df["iso3_d"]).sum())),
    ("comtrade_reporting_rows", int(df["comtrade_reporting_available"].eq(1).sum())),
    ("comtrade_sparse_rows", int(df["comtrade_sparse_row_present"].eq(1).sum())),
    ("comtrade_zero_filled_rows", int(df["comtrade_zero_fill_sparse"].eq(1).sum())),
    ("tourism_pair_rows", int(df["tourism_pair_row_present"].eq(1).sum())),
    ("tourists_nonmissing", int(df["tourists_k"].notna().sum())),
    ("visitors_nonmissing", int(df["visitors_k"].notna().sum())),
    ("hofstede_pair_rows", int(df["hofstede_pair_present"].eq(1).sum())),
]
for cd in ["cd6_ge4","cd6_strict","cd4_ks"]:
    if cd in df.columns:
        summary_metrics.append((f"{cd}_nonmissing", int(df[cd].notna().sum())))

pd.DataFrame(summary_metrics, columns=["metric","value"]).to_csv(
    MASTER_DIAG/"master_build_summary.csv",
    index=False, encoding="utf-8-sig"
)

# Year-by-year coverage.
annual = []
for year, g in df.groupby("year"):
    annual.append({
        "year":int(year),
        "master_rows":len(g),
        "trade_reporting_rows":int(g["comtrade_reporting_available"].eq(1).sum()),
        "trade_sparse_rows":int(g["comtrade_sparse_row_present"].eq(1).sum()),
        "trade_zero_filled_rows":int(g["comtrade_zero_fill_sparse"].eq(1).sum()),
        "tourism_pair_rows":int(g["tourism_pair_row_present"].eq(1).sum()),
        "tourists_nonmissing":int(g["tourists_k"].notna().sum()),
        "visitors_nonmissing":int(g["visitors_k"].notna().sum()),
        "hofstede_cd6_ge4_nonmissing":int(g["cd6_ge4"].notna().sum()) if "cd6_ge4" in g else np.nan,
        "hofstede_cd6_strict_nonmissing":int(g["cd6_strict"].notna().sum()) if "cd6_strict" in g else np.nan,
    })
pd.DataFrame(annual).to_csv(
    MASTER_DIAG/"master_coverage_by_year.csv",
    index=False, encoding="utf-8-sig"
)

# Sample flags.
sample_cols = [c for c in df.columns if c.startswith("sample_")]
pd.DataFrame([
    {"sample_flag":c, "rows":int(pd.to_numeric(df[c], errors="coerce").eq(1).sum())}
    for c in sample_cols
]).to_csv(
    MASTER_DIAG/"estimation_sample_flag_counts.csv",
    index=False, encoding="utf-8-sig"
)

# Tourism basis/method coverage.
for var, outname in [
    ("tourists_basis","tourists_basis_distribution.csv"),
    ("visitors_basis","visitors_basis_distribution.csv"),
]:
    if var in df.columns:
        (
            df[var].fillna("").astype(str)
            .value_counts(dropna=False)
            .rename_axis(var).reset_index(name="rows")
            .to_csv(MASTER_DIAG/outname, index=False, encoding="utf-8-sig")
        )

# Comtrade zero/missing audit.
trade_vars = [
    "v_3706_k","v_49_k","v_8523_lb_k","v_8523_ub_k",
    "v_8523_amb_k","v_97_k","v_ttl_lb_k","v_ttl_ub_k"
]
trade_vars = [v for v in trade_vars if v in df.columns]

zero_rows = []
for v in trade_vars:
    available = df["comtrade_reporting_available"].eq(1)
    unavailable = ~available
    zero_rows.append({
        "variable":v,
        "reporting_rows":int(available.sum()),
        "nonmissing_on_reporting_rows":int(df.loc[available,v].notna().sum()),
        "zero_on_reporting_rows":int(df.loc[available,v].eq(0).sum()),
        "nonmissing_on_nonreporting_rows":int(df.loc[unavailable,v].notna().sum()),
    })
pd.DataFrame(zero_rows).to_csv(
    MASTER_DIAG/"comtrade_zero_missing_validation.csv",
    index=False, encoding="utf-8-sig"
)

if any(r["nonmissing_on_nonreporting_rows"] != 0 for r in zero_rows):
    raise RuntimeError("Comtrade zero/missing validation failed.")

# Key audit.
key_dups = int(df.duplicated(["year","iso3_o","iso3_d"], keep=False).sum())
pd.DataFrame([{
    "key":"year + iso3_o + iso3_d",
    "rows":len(df),
    "duplicate_rows":key_dups,
    "is_unique":int(key_dups==0)
}]).to_csv(MASTER_DIAG/"master_key_audit.csv", index=False, encoding="utf-8-sig")

if key_dups:
    raise RuntimeError("Final master key is not unique.")
if (df["iso3_o"]==df["iso3_d"]).any():
    raise RuntimeError("Domestic dyads remain in international master.")

print("MASTER_PANEL_DIAGNOSTICS=PASS")
print("Rows:", len(df))
print("Key duplicates:", key_dups)

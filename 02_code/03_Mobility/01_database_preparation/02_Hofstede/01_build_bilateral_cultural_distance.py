import json
import numpy as np
import pandas as pd
from _paths import *

ensure_dirs()
cfg = json.loads((CONFIG/"construction_specification.json").read_text(encoding="utf-8"))
dims = cfg["dimensions"]
four = cfg["original_ks_dimensions"]

SRC = INTERMEDIATE / "hofstede_country_scores_2015.csv"
if not SRC.exists():
    raise SystemExit("Run 00_extract_and_audit_hofstede_source.py first.")

c = pd.read_csv(SRC, dtype={"iso3":"string"})
c["iso3"] = c["iso3"].str.upper().str.strip()

if c["iso3"].duplicated().any():
    raise RuntimeError("Country-score table is not unique by ISO3.")

# ------------------------------------------------------------------
# Variance denominator: sample variance across nonmissing country rows,
# computed separately for each dimension.
# ------------------------------------------------------------------
variances = {d: float(c[d].var(ddof=1)) for d in dims}
if any((not np.isfinite(v) or v <= 0) for v in variances.values()):
    raise RuntimeError(f"Invalid dimension variance(s): {variances}")

pd.DataFrame([
    {
        "dimension": d,
        "sample_variance": variances[d],
        "nonmissing_country_scores": int(c[d].notna().sum())
    }
    for d in dims
]).to_csv(DIAG/"dimension_variance_denominators.csv", index=False, encoding="utf-8-sig")

# ------------------------------------------------------------------
# Full ordered bilateral cross join, excluding domestic pairs.
# Cultural distance is symmetric, but ordered dyads are convenient for master merge.
# ------------------------------------------------------------------
o = c.rename(columns={
    "country":"country_o",
    "iso3":"iso3_o",
    "iso3num":"iso3num_o",
    "available_dim_count":"available_dim_count_o",
    "regional_proxy_group":"regional_proxy_group_o",
    "regional_proxy_flag":"regional_proxy_flag_o",
    **{d:f"{d}_o" for d in dims}
}).copy()

d = c.rename(columns={
    "country":"country_d",
    "iso3":"iso3_d",
    "iso3num":"iso3num_d",
    "available_dim_count":"available_dim_count_d",
    "regional_proxy_group":"regional_proxy_group_d",
    "regional_proxy_flag":"regional_proxy_flag_d",
    **{x:f"{x}_d" for x in dims}
}).copy()

o["_cross"] = 1
d["_cross"] = 1
pairs = o.merge(d, on="_cross", how="inner").drop(columns="_cross")
pairs = pairs[pairs["iso3_o"] != pairs["iso3_d"]].copy()

dist_cols = []
for dim in dims:
    col = f"ndiff2_{dim}"
    pairs[col] = ((pairs[f"{dim}_d"] - pairs[f"{dim}_o"]) ** 2) / variances[dim]
    dist_cols.append(col)

pairs["common_dim_count6"] = pairs[dist_cols].notna().sum(axis=1).astype("int8")

# ------------------------------------------------------------------
# Three explicit measures. No silent choice is made here.
#
# cd6_ge4:
#   Reproduces the old construction logic:
#   mean over the available standardized squared differences,
#   retained only when >=4 dimensions are common.
#
# cd6_strict:
#   Fixed six-dimensional extension of the Kogut-Singh structure:
#   all six dimensions must be observed, denominator is always six.
#
# cd4_ks:
#   Original four-dimension Kogut-Singh construction (PDI, IDV, MAS, UAI).
# ------------------------------------------------------------------
pairs["cd6_ge4"] = pairs[dist_cols].mean(axis=1, skipna=True)
pairs.loc[pairs["common_dim_count6"] < 4, "cd6_ge4"] = np.nan

pairs["cd6_strict"] = pairs[dist_cols].mean(axis=1, skipna=False)

four_cols = [f"ndiff2_{x}" for x in four]
pairs["cd4_ks"] = pairs[four_cols].mean(axis=1, skipna=False)

# Regional proxy flags are retained, not filtered.
pairs["any_regional_proxy"] = (
    pairs["regional_proxy_flag_o"].fillna(0).astype(int).eq(1)
    | pairs["regional_proxy_flag_d"].fillna(0).astype(int).eq(1)
).astype("int8")

# ------------------------------------------------------------------
# Key, symmetry, coverage and additivity diagnostics.
# ------------------------------------------------------------------
if pairs.duplicated(["iso3_o","iso3_d"]).any():
    raise RuntimeError("Bilateral Hofstede table has duplicate ordered ISO3 dyads.")

rev = pairs[["iso3_o","iso3_d","cd6_ge4","cd6_strict","cd4_ks"]].rename(columns={
    "iso3_o":"iso3_d",
    "iso3_d":"iso3_o",
    "cd6_ge4":"cd6_ge4_rev",
    "cd6_strict":"cd6_strict_rev",
    "cd4_ks":"cd4_ks_rev",
})
sym = pairs[["iso3_o","iso3_d","cd6_ge4","cd6_strict","cd4_ks"]].merge(
    rev, on=["iso3_o","iso3_d"], how="left", validate="1:1"
)

sym_rows = []
for v in ["cd6_ge4","cd6_strict","cd4_ks"]:
    a = sym[v].to_numpy(dtype=float)
    b = sym[f"{v}_rev"].to_numpy(dtype=float)
    mask = np.isfinite(a) & np.isfinite(b)
    maxdiff = float(np.max(np.abs(a[mask]-b[mask]))) if mask.any() else np.nan
    sym_rows.append({
        "measure":v,
        "comparable_reverse_pairs":int(mask.sum()),
        "max_abs_forward_reverse_difference":maxdiff
    })
    if np.isfinite(maxdiff) and maxdiff > 1e-10:
        raise RuntimeError(f"Symmetry validation failed for {v}: max difference {maxdiff}")

pd.DataFrame(sym_rows).to_csv(
    DIAG/"bilateral_symmetry_audit.csv", index=False, encoding="utf-8-sig"
)

coverage = pd.DataFrame([
    {
        "measure":"cd6_ge4",
        "definition":"Mean standardized squared difference over common dimensions; minimum 4 common dimensions.",
        "nonmissing_ordered_dyads":int(pairs["cd6_ge4"].notna().sum()),
        "missing_ordered_dyads":int(pairs["cd6_ge4"].isna().sum())
    },
    {
        "measure":"cd6_strict",
        "definition":"Six-dimensional mean; all six dimensions required.",
        "nonmissing_ordered_dyads":int(pairs["cd6_strict"].notna().sum()),
        "missing_ordered_dyads":int(pairs["cd6_strict"].isna().sum())
    },
    {
        "measure":"cd4_ks",
        "definition":"Original four-dimension Kogut-Singh structure; PDI/IDV/MAS/UAI all required.",
        "nonmissing_ordered_dyads":int(pairs["cd4_ks"].notna().sum()),
        "missing_ordered_dyads":int(pairs["cd4_ks"].isna().sum())
    },
])
coverage.to_csv(DIAG/"bilateral_measure_coverage.csv", index=False, encoding="utf-8-sig")

pairs["common_dim_count6"].value_counts().sort_index().rename_axis(
    "common_dim_count6"
).reset_index(name="ordered_dyad_count").to_csv(
    DIAG/"bilateral_common_dimension_distribution.csv", index=False, encoding="utf-8-sig"
)

# Snapshot integrity based on the archived source supplied for the paper.
if len(pairs) != 18632:
    raise RuntimeError(f"Expected 18,632 ordered non-domestic dyads; found {len(pairs)}.")
if int(pairs["cd6_ge4"].notna().sum()) != 14042:
    raise RuntimeError(
        "Archived-source snapshot check failed: cd6_ge4 should have 14,042 nonmissing ordered dyads."
    )
if int(pairs["cd6_strict"].notna().sum()) != 12210:
    raise RuntimeError(
        "Archived-source snapshot check failed: cd6_strict should have 12,210 nonmissing ordered dyads."
    )

# ------------------------------------------------------------------
# Save final source table.
# ------------------------------------------------------------------
keep = [
    "country_o","iso3_o","iso3num_o",
    "country_d","iso3_d","iso3num_d",
    "cd6_ge4","cd6_strict","cd4_ks","common_dim_count6",
    "regional_proxy_flag_o","regional_proxy_flag_d",
    "regional_proxy_group_o","regional_proxy_group_d","any_regional_proxy"
]
out = pairs[keep].sort_values(["iso3_o","iso3_d"]).reset_index(drop=True)

out.to_csv(
    FINAL/"hofstede_bilateral_cultural_distance.csv",
    index=False, encoding="utf-8-sig"
)

stata = out.copy()
for col in ["country_o","iso3_o","country_d","iso3_d",
            "regional_proxy_group_o","regional_proxy_group_d"]:
    stata[col] = stata[col].fillna("").astype(str)
stata.to_stata(
    FINAL/"hofstede_bilateral_cultural_distance.dta",
    write_index=False, version=118
)

summary = pd.DataFrame([{
    "country_rows":len(c),
    "ordered_non_domestic_dyads":len(out),
    "cd6_ge4_nonmissing":int(out["cd6_ge4"].notna().sum()),
    "cd6_strict_nonmissing":int(out["cd6_strict"].notna().sum()),
    "cd4_ks_nonmissing":int(out["cd4_ks"].notna().sum()),
    "dyads_with_any_regional_proxy":int(out["any_regional_proxy"].sum()),
    "time_varying":0,
    "self_pairs_included":0
}])
summary.to_csv(DIAG/"build_validation_summary.csv", index=False, encoding="utf-8-sig")

print("HOFSTEDE_BILATERAL_DISTANCE_BUILD=PASS")
print("Ordered non-domestic dyads:", len(out))
print("cd6_ge4 nonmissing:", int(out["cd6_ge4"].notna().sum()))
print("cd6_strict nonmissing:", int(out["cd6_strict"].notna().sum()))
print("cd4_ks nonmissing:", int(out["cd4_ks"].notna().sum()))

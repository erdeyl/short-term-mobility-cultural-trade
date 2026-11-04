import json
import numpy as np
import pandas as pd
from pandas.io.stata import StataReader
from _paths import *  # RESCUE C03; RESCUE C05
import sys as _rescue_sys  # RESCUE C03; RESCUE C05
from pathlib import Path as _RescuePath  # RESCUE C03; RESCUE C05
_RESCUE = next(p for p in _RescuePath(__file__).resolve().parents if p.name == '02_code') / '99_rescue'  # RESCUE C03; RESCUE C05
_rescue_sys.path.insert(0, str(_RESCUE))  # RESCUE C03; RESCUE C05
import rescue_switch  # RESCUE C03; RESCUE C05
import ia_common  # RESCUE C03; RESCUE C05

ensure_dirs()
cfg = json.loads((CONFIG/"variables_and_provenance.json").read_text(encoding="utf-8"))
START, END = cfg["years"]
CHUNK = 200_000

# Discover exact source schema.
with StataReader(GRAVITY, convert_categoricals=False) as r:
    labels = r.variable_labels()
available = set(labels.keys())

required = cfg["required_core"]
missing = [v for v in required if v not in available]
if missing:
    raise RuntimeError("Required CEPII variables missing: " + ", ".join(missing))

keep = required + [v for v in cfg["optional_keep"] if v in available]
keep = list(dict.fromkeys(keep))

# Read only selected columns; filter 2007-2021 in chunks.
reader = pd.read_stata(
    GRAVITY,
    columns=keep,
    convert_categoricals=False,
    iterator=True,
    chunksize=CHUNK,
    preserve_dtypes=True
)

parts = []
year_counts_all = {}
total_source_rows = 0
min_year = None
max_year = None

for i, chunk in enumerate(reader, start=1):
    total_source_rows += len(chunk)
    yr = pd.to_numeric(chunk["year"], errors="coerce")
    if len(yr.dropna()):
        mn, mx = int(yr.min()), int(yr.max())
        min_year = mn if min_year is None else min(min_year, mn)
        max_year = mx if max_year is None else max(max_year, mx)

    vc = yr.value_counts(dropna=False)
    for k, v in vc.items():
        if pd.notna(k):
            year_counts_all[int(k)] = year_counts_all.get(int(k), 0) + int(v)

    sub = chunk[(yr >= START) & (yr <= END)].copy()
    if len(sub):
        sub["year"] = pd.to_numeric(sub["year"], errors="raise").astype("int16")
        parts.append(sub)

    if i % 5 == 0:
        print(f"Read {total_source_rows:,} CEPII source rows")

if not parts:
    raise RuntimeError(f"No CEPII observations found for {START}-{END}.")

panel = pd.concat(parts, ignore_index=True)

if max_year is None or max_year < 2021:
    raise RuntimeError(
        f"Source file does not contain 2021. Observed source max year = {max_year}"
    )

# The source is squared and includes non-existing territorial configurations.
# Keep both an audit count and an analysis-relevant existing-country subset.
for c in ["country_exists_o","country_exists_d"]:
    panel[c] = pd.to_numeric(panel[c], errors="coerce")

existing = panel[
    panel["country_exists_o"].eq(1) & panel["country_exists_d"].eq(1)
].copy()

# -----------------------------
# Key audits
# -----------------------------
key_country_id = ["country_id_o","country_id_d","year"]
dup_country_id = int(panel.duplicated(key_country_id, keep=False).sum())

key_iso = ["iso3_o","iso3_d","year"]
dup_iso_existing = int(existing.duplicated(key_iso, keep=False).sum())

key_audit = pd.DataFrame([
    {
        "universe":"all CEPII rows, 2007-2021",
        "key":"country_id_o + country_id_d + year",
        "rows":len(panel),
        "duplicate_rows":dup_country_id,
        "is_unique":int(dup_country_id==0)
    },
    {
        "universe":"country_exists_o=1 and country_exists_d=1, 2007-2021",
        "key":"iso3_o + iso3_d + year",
        "rows":len(existing),
        "duplicate_rows":dup_iso_existing,
        "is_unique":int(dup_iso_existing==0)
    }
])
key_audit.to_csv(DIAG/"key_uniqueness_audit.csv", index=False, encoding="utf-8-sig")

if dup_country_id != 0:
    panel.loc[
        panel.duplicated(key_country_id, keep=False)
    ].sort_values(key_country_id).to_csv(
        DIAG/"country_id_key_duplicates.csv", index=False, encoding="utf-8-sig"
    )
    raise RuntimeError("CEPII country_id origin-destination-year key is not unique.")

if dup_iso_existing != 0:
    existing.loc[
        existing.duplicated(key_iso, keep=False)
    ].sort_values(key_iso).to_csv(
        DIAG/"existing_iso3_key_duplicates.csv", index=False, encoding="utf-8-sig"
    )
    raise RuntimeError(
        "ISO3 origin-destination-year is not unique after restricting to existing countries."
    )

# -----------------------------
# 2021 and RTA/FTA audit
# -----------------------------
y2021 = existing[existing["year"] == 2021].copy()
if y2021.empty:
    raise RuntimeError("No 2021 observations in existing-country sample.")

rta_summary_rows = []
for v in ["fta_wto","fta_wto_raw","rta_coverage","rta_type"]:
    s = y2021[v]
    rta_summary_rows.append({
        "variable":v,
        "rows_2021":len(s),
        "nonmissing_2021":int(s.notna().sum()),
        "missing_2021":int(s.isna().sum()),
        "unique_nonmissing_values_2021":int(s.dropna().nunique())
    })
pd.DataFrame(rta_summary_rows).to_csv(
    DIAG/"rta_2021_nonmissing_audit.csv", index=False, encoding="utf-8-sig"
)

# Value distributions, retaining raw Stata codes.
dist_rows = []
for v in ["fta_wto","fta_wto_raw","rta_coverage","rta_type"]:
    vc = y2021[v].value_counts(dropna=False)
    for value, n in vc.items():
        dist_rows.append({
            "year":2021,
            "variable":v,
            "value":value,
            "count":int(n)
        })
pd.DataFrame(dist_rows).to_csv(
    DIAG/"rta_2021_value_distribution.csv", index=False, encoding="utf-8-sig"
)

# Annual availability / RTA prevalence.
annual = []
for year, g in existing.groupby("year"):
    row = {
        "year":int(year),
        "existing_pair_rows":len(g),
        "fta_wto_nonmissing":int(g["fta_wto"].notna().sum()),
        "fta_wto_one":int((pd.to_numeric(g["fta_wto"], errors="coerce")==1).sum()),
        "fta_wto_raw_nonmissing":int(g["fta_wto_raw"].notna().sum()),
        "rta_coverage_nonmissing":int(g["rta_coverage"].notna().sum()),
        "rta_type_nonmissing":int(g["rta_type"].notna().sum()),
    }
    annual.append(row)
pd.DataFrame(annual).to_csv(
    DIAG/"annual_rta_coverage_audit_2007_2021.csv", index=False, encoding="utf-8-sig"
)

# -----------------------------
# Countries reference audit
# -----------------------------
countries = pd.read_stata(COUNTRIES, convert_categoricals=False)
country_key = "country_id" if "country_id" in countries.columns else None
countries_dup = (
    int(countries.duplicated([country_key], keep=False).sum())
    if country_key else np.nan
)
gravity_ids = set(existing["country_id_o"].dropna().astype(str)) | set(existing["country_id_d"].dropna().astype(str))
country_ref_ids = set(countries[country_key].dropna().astype(str)) if country_key else set()
missing_ref_ids = sorted(gravity_ids - country_ref_ids) if country_key else []

pd.DataFrame([{
    "countries_rows":len(countries),
    "country_id_variable_present":int(country_key is not None),
    "country_id_duplicate_rows":countries_dup,
    "gravity_existing_country_ids":len(gravity_ids),
    "gravity_country_ids_missing_from_Countries":len(missing_ref_ids)
}]).to_csv(DIAG/"countries_reference_audit.csv", index=False, encoding="utf-8-sig")

if missing_ref_ids:
    pd.DataFrame({"country_id_missing_from_Countries":missing_ref_ids}).to_csv(
        DIAG/"gravity_country_ids_missing_from_Countries.csv",
        index=False, encoding="utf-8-sig"
    )

# -----------------------------
# Overall audit summary
# -----------------------------
summary = pd.DataFrame([
    {"metric":"source_rows_total","value":total_source_rows},
    {"metric":"source_min_year","value":min_year},
    {"metric":"source_max_year","value":max_year},
    {"metric":"rows_2007_2021_all_cepii_configurations","value":len(panel)},
    {"metric":"rows_2007_2021_existing_country_pairs","value":len(existing)},
    {"metric":"rows_2021_existing_country_pairs","value":len(y2021)},
    {"metric":"country_id_pair_year_duplicate_rows","value":dup_country_id},
    {"metric":"existing_iso3_pair_year_duplicate_rows","value":dup_iso_existing},
    {"metric":"2021_is_directly_present_in_source","value":1},
    {"metric":"manual_2021_extension_performed","value":0},
    {"metric":"source_release","value":"V202211"},
])
summary.to_csv(DIAG/"cepii_audit_summary.csv", index=False, encoding="utf-8-sig")

pd.DataFrame(
    [{"year":y, "source_rows":year_counts_all[y]} for y in sorted(year_counts_all)]
).to_csv(DIAG/"source_year_row_counts.csv", index=False, encoding="utf-8-sig")

# -----------------------------
# Save final CEPII source table
# -----------------------------
# We retain official CEPII variable names. No historical database is used.
if rescue_switch.enabled("C05"):  # RESCUE C03; RESCUE C05
    ia_common.export_fta_discordance(existing, DIAG)  # RESCUE C03; RESCUE C05
if rescue_switch.enabled("C03"):  # RESCUE C03; RESCUE C05
    existing = ia_common.apply_rta_overrides(existing, CONFIG, DIAG)  # RESCUE C03; RESCUE C05
existing = existing.sort_values(["year","iso3_o","iso3_d"]).reset_index(drop=True)  # RESCUE C03; RESCUE C05

# CSV is optional but useful for portability; DTA is the main project format.
existing.to_csv(
    FINAL/"cepii_gravity_rta_2007_2021.csv",
    index=False, encoding="utf-8-sig"
)
existing.to_stata(
    FINAL/"cepii_gravity_rta_2007_2021.dta",
    write_index=False, version=118
)

# Store the full selected 2007-2021 CEPII universe only as an intermediate DTA.
# This preserves country_exists flags and territorial configurations for auditability.
panel = panel.sort_values(["year","country_id_o","country_id_d"]).reset_index(drop=True)
panel.to_stata(
    INTERMEDIATE/"cepii_selected_all_configurations_2007_2021.dta",
    write_index=False, version=118
)

print("CEPII_V202211_AUDIT_AND_EXTRACTION=PASS")
print("Source min/max year:", min_year, max_year)
print("Rows 2007-2021, all CEPII configurations:", len(panel))
print("Rows 2007-2021, existing-country pairs:", len(existing))
print("Rows in 2021 existing-country pairs:", len(y2021))
print("2021 is read directly from Gravity_V202211.dta; no extension was performed.")

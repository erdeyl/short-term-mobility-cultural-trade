"""UN Comtrade cultural-trade clean build from archived replication sources."""
import pandas as pd
import numpy as np
import re, json
from _paths import *  # RESCUE C02; RESCUE C10
import sys as _rescue_sys  # RESCUE C02; RESCUE C10
from pathlib import Path as _RescuePath  # RESCUE C02; RESCUE C10
_RESCUE = next(p for p in _RescuePath(__file__).resolve().parents if p.name == '02_code') / '99_rescue'  # RESCUE C02; RESCUE C10
_rescue_sys.path.insert(0, str(_RESCUE))  # RESCUE C02; RESCUE C10
import rescue_switch  # RESCUE C02; RESCUE C10
import ia_common  # RESCUE C02; RESCUE C10
ensure_dirs()
E=json.loads((CONFIG/'frozen_snapshot_expectations.json').read_text(encoding='utf-8'))
EXPECTED_RAW_FILES=int(E['raw_trade_csv_files']); EXPECTED_RAW_ROWS=int(E['raw_trade_rows']); EXPECTED_MANIFEST_ROWS=int(E['trade_download_manifest_rows']); EXPECTED_REPORTER_YEARS=int(E['reporter_years']); EXPECTED_CONCORDANCE_ROWS=int(E['concordance_rows']); EXPECTED_AMBIGUOUS_MAP_ROWS=int(E['ambiguous_mapping_rows']); EXPECTED_SPARSE_ROWS=int(E['sparse_dyad_year_rows']); EXPECTED_POS_AMBIG_DYADS=int(E['positive_ambiguous_pool_dyads'])
AVAIL=INT_AVAIL/'reported_classification_availability_2007_2021.csv'; TARGETS=INT_CONC/'reported_HS_download_targets_by_version.csv'; CONCORD=INT_CONC/'reported_HS_to_H3_concordance.csv'; RREF=INT_REF/'reporter_reference.csv'; PREF=INT_REF/'partner_reference.csv'; MANIFEST=RAW_META/'download_manifest.csv'
required=[AVAIL,TARGETS,CONCORD,RREF,PREF,MANIFEST]; missing=[str(p) for p in required if not p.exists()]
if missing:
    print('MISSING REQUIRED DERIVED INPUTS:');[print(' -',p) for p in missing];raise SystemExit('Run 00, 01, 02 and 04 first.')
avail=pd.read_csv(AVAIL);targets=pd.read_csv(TARGETS,dtype={'source_code':'string'});mapping=pd.read_csv(CONCORD,dtype={'source_code':'string'});manifest=pd.read_csv(MANIFEST);rref=pd.read_csv(RREF);pref=pd.read_csv(PREF)
targets['source_code']=targets['source_code'].str.zfill(6);mapping['source_code']=mapping['source_code'].str.zfill(6)
RAW=RAW_TRADE;DIAG=DIAG_BUILD;FINAL=FINAL_CT;STRICT=True

# ------------------------------------------------------------------
# LAYER 1: Download completeness
# ------------------------------------------------------------------
raw_files = sorted(RAW.glob("*.csv"))

assert len(manifest) == EXPECTED_MANIFEST_ROWS
assert (manifest["status"] == "DOWNLOADED_OK").all()
assert manifest["data_rows"].sum() == EXPECTED_RAW_ROWS
assert len(raw_files) == EXPECTED_RAW_FILES

if manifest['filename'].duplicated().any():
    raise RuntimeError('Duplicate filenames in acquisition manifest.')
if set(manifest['filename']) != {p.name for p in raw_files}:
    raise RuntimeError('Raw filenames do not exactly match acquisition manifest.')
for _, row in manifest.iterrows():
    expected_n = pd.to_numeric(row['data_rows'], errors='coerce')
    if pd.isna(expected_n) or expected_n < 0 or expected_n != int(expected_n):
        raise RuntimeError('Invalid per-file data_rows in acquisition manifest.')

# Every reporter-year in data availability must appear in exactly the expected version batches.
queried = set()
for _, row in manifest.iterrows():
    for rep in str(row["reporter_batch"]).split(","):
        queried.add((int(row["year"]), str(row["classification"]), int(rep)))

expected_ry = set(
    (int(r["_query_year"]), str(r["classificationCode"]), int(r["reporterCode"]))
    for _, r in avail.iterrows()
)
assert queried == expected_ry
assert len(expected_ry) == EXPECTED_REPORTER_YEARS

# For every year/version, union of queried codes must equal the concordance download list.
for (year, version), sub in manifest.groupby(["year","classification"]):
    got = set()
    for x in sub["code_batch"]:
        got.update(str(x).split(","))
    want = set(
        targets.loc[targets["source_version"] == version, "source_code"].dropna()
    )
    assert got == want, f"Code-batch coverage mismatch: year={year}, version={version}"

print("VALIDATION_LAYER_1_DOWNLOAD_COMPLETENESS=PASS")

# ------------------------------------------------------------------
# LAYER 2: Stack raw API responses and prove query provenance
# ------------------------------------------------------------------
# Source-field names below are the exact UN Comtrade API names.
# In particular, `legacyEstimationFlag` is an official source metadata field;
# it is NOT an analysis label and must not be renamed.
usecols = [
    "refYear","reporterCode","partnerCode","classificationCode",
    "classificationSearchCode","isOriginalClassification","cmdCode","flowCode",
    "partner2Code","customsCode","motCode","primaryValue","cifvalue","fobvalue",
    "legacyEstimationFlag","isReported","isAggregate"
]

# Mechanical source-schema preflight using the first non-empty API CSV.
first_nonempty = next((p for p in raw_files if p.stat().st_size > 0), None)
if first_nonempty is None:
    raise RuntimeError("All raw Comtrade CSV files are empty.")

header_cols = list(pd.read_csv(first_nonempty, nrows=0).columns)
missing_source_fields = [c for c in usecols if c not in header_cols]
if missing_source_fields:
    raise RuntimeError(
        "RAW SCHEMA MISMATCH. Missing source fields: "
        + ", ".join(missing_source_fields)
        + "\nFirst non-empty file: " + str(first_nonempty)
        + "\nAvailable fields: " + ", ".join(header_cols)
    )

if "legacyEstimationFlag" not in header_cols:
    raise RuntimeError("Expected UN Comtrade field `legacyEstimationFlag` was not found.")

print("RAW_SOURCE_SCHEMA_PREFLIGHT=PASS")

parts = []
empty_files = []

filename_re = re.compile(r"^HS_(\d{4})_(H\d)_R[0-9a-f]+_C[0-9a-f]+\.csv$")

# Manifest lookup lets us distinguish a legitimate zero-row API response
# from a damaged/truncated raw file.
manifest_by_file = manifest.set_index("filename", drop=False)

for i, p in enumerate(raw_files, start=1):
    # Some legitimate zero-row API responses were saved as truly empty files,
    # while others may contain only a UTF-8 BOM/newline. Handle both cases.
    try:
        if p.stat().st_size == 0:
            raise pd.errors.EmptyDataError("zero-byte raw CSV")
        df = pd.read_csv(p, usecols=usecols, low_memory=False)
    except pd.errors.EmptyDataError:
        if p.name not in manifest_by_file.index:
            raise RuntimeError(
                f"Headerless/empty raw CSV is absent from the download manifest: {p.name}"
            )

        mr = manifest_by_file.loc[p.name]
        # There should be exactly one manifest row per output file.
        if isinstance(mr, pd.DataFrame):
            if len(mr) != 1:
                raise RuntimeError(
                    f"Multiple manifest rows found for empty raw CSV: {p.name}"
                )
            mr = mr.iloc[0]

        status = str(mr["status"])
        expected_rows = pd.to_numeric(mr["data_rows"], errors="coerce")

        if status != "DOWNLOADED_OK" or pd.isna(expected_rows) or int(expected_rows) != 0:
            raise RuntimeError(
                "Unexpected empty raw CSV. It is not documented as a successful "
                f"zero-row API response in the manifest: {p.name}; "
                f"status={status}; manifest_data_rows={expected_rows}"
            )

        empty_files.append(p.name)
        print(f"LEGITIMATE_ZERO_ROW_FILE=PASS: {p.name}")
        continue

    mr = manifest_by_file.loc[p.name]
    if len(df) != int(mr['data_rows']):
        raise RuntimeError(f"Per-file row count mismatch: {p.name}")
    query_reporters = {int(x) for x in str(mr['reporter_batch']).split(',')}
    query_codes = {str(x).strip().zfill(6) for x in str(mr['code_batch']).split(',')}
    if not set(pd.to_numeric(df['reporterCode'], errors='raise').astype(int)).issubset(query_reporters):
        raise RuntimeError(f'Reporter outside its query batch: {p.name}')
    row_codes = df['cmdCode'].astype(str).str.replace(r'\.0$', '', regex=True).str.zfill(6)
    if not set(row_codes).issubset(query_codes):
        raise RuntimeError(f'HS code outside its query batch: {p.name}')

    m = filename_re.match(p.name)
    if not m:
        raise RuntimeError(f"Unexpected raw filename: {p.name}")
    fy, fv = int(m.group(1)), m.group(2)
    if fy != int(mr['year']) or fv != str(mr['classification']):
        raise RuntimeError(f'Filename disagrees with manifest: {p.name}')

    if len(df):
        if not (df["refYear"] == fy).all():
            raise RuntimeError(f"Year mismatch in {p.name}")
        if not (df["classificationCode"].astype(str) == fv).all():
            raise RuntimeError(f"Classification mismatch in {p.name}")

    df["_source_file"] = p.name
    parts.append(df)

    if i % 50 == 0:
        print(f"Read {i}/{len(raw_files)} raw CSV files")

if not parts:
    raise RuntimeError("No non-empty Comtrade raw files were available to stack.")

raw = pd.concat(parts, ignore_index=True)

if STRICT:
    assert len(raw) == EXPECTED_RAW_ROWS

print(f"LEGITIMATE_ZERO_ROW_FILES={len(empty_files)}")

assert (raw["classificationSearchCode"].astype(str) == "HS").all()
assert (raw["flowCode"].astype(str) == "M").all()
assert (pd.to_numeric(raw["partner2Code"], errors="coerce") == 0).all()
assert (raw["customsCode"].astype(str) == "C00").all()
assert (pd.to_numeric(raw["motCode"], errors="coerce") == 0).all()

# Bool fields can arrive either as bools or strings.
orig = raw["isOriginalClassification"].astype(str).str.lower()
assert orig.isin(["true","1"]).all()

# One record per source HS6 x reporter x partner x year because other dimensions are fixed at totals.
raw["cmdCode"] = (
    raw["cmdCode"].astype(str).str.replace(r"\.0$", "", regex=True).str.zfill(6)
)
core_key = ["refYear","reporterCode","partnerCode","classificationCode","cmdCode"]
dup_n = int(raw.duplicated(core_key, keep=False).sum())
assert dup_n == 0

raw["primaryValue"] = pd.to_numeric(raw["primaryValue"], errors="coerce")
raw["cifvalue"] = pd.to_numeric(raw["cifvalue"], errors="coerce")
raw["fobvalue"] = pd.to_numeric(raw["fobvalue"], errors="coerce")

assert raw["primaryValue"].notna().all()
assert (raw["primaryValue"] >= 0).all()

print("VALIDATION_LAYER_2_RAW_QUERY_PROVENANCE=PASS")

# ------------------------------------------------------------------
# LAYER 3: Official concordance and category treatment
# ------------------------------------------------------------------
assert len(mapping) == EXPECTED_CONCORDANCE_ROWS
assert mapping.duplicated(["source_version","source_code"]).sum() == 0
assert (mapping["mapping_status"] == "AMBIGUOUS_PARTIAL_MAPPING").sum() == EXPECTED_AMBIGUOUS_MAP_ROWS

mapcols = [
    "source_version","source_code","mapping_status","pipeline_treatment",
    "canonical_H3_codes_touched","non_target_H3_codes"
]
raw = raw.merge(
    mapping[mapcols],
    left_on=["classificationCode","cmdCode"],
    right_on=["source_version","source_code"],
    how="left",
    validate="m:1"
)
assert raw["pipeline_treatment"].notna().all()

# Every reporter code/year must map back to the availability dataset and its ISO alpha-3.
rmap = avail[
    ["_query_year","reporterCode","reporterISO","reporterDesc","classificationCode"]
].rename(columns={"_query_year":"refYear","classificationCode":"availability_classification"})

raw = raw.merge(
    rmap,
    on=["refYear","reporterCode"],
    how="left",
    validate="m:1"
)
assert raw["reporterISO"].notna().all()
assert (raw["classificationCode"] == raw["availability_classification"]).all()

# Official partner reference.
pref["partnerCode"] = pd.to_numeric(pref["partnerCode"], errors="coerce")
raw = raw.merge(
    pref[["partnerCode","partnerISO","partnerDesc","entryEffectiveDate",
          "entryExpiredDate","isGroup"]].rename(columns={
        "entryEffectiveDate":"partner_entry_effective",
        "entryExpiredDate":"partner_entry_expired",
        "isGroup":"partner_is_group"
    }),
    on="partnerCode",
    how="left",
    validate="m:1"
)
assert raw["partnerDesc"].notna().all(), "Some Comtrade partner codes are absent from partner reference."

print("VALIDATION_LAYER_3_OFFICIAL_CONCORDANCE=PASS")

# ------------------------------------------------------------------
# LAYER 4: Valuation audit
# primaryValue for imports should resolve to CIF where used, otherwise FOB.
# We audit the actual downloaded rows instead of assuming.
# ------------------------------------------------------------------
pv = raw["primaryValue"].to_numpy(dtype=float)
cif = raw["cifvalue"].to_numpy(dtype=float)
fob = raw["fobvalue"].to_numpy(dtype=float)

eq_cif = np.isclose(pv, cif, rtol=0, atol=1e-9, equal_nan=False)
eq_fob = np.isclose(pv, fob, rtol=0, atol=1e-9, equal_nan=False)
neither = ~(eq_cif | eq_fob)

valuation = pd.DataFrame([{
    "raw_rows": len(raw),
    "primary_value_missing": int(raw["primaryValue"].isna().sum()),
    "primary_value_zero": int((raw["primaryValue"] == 0).sum()),
    "primary_value_negative": int((raw["primaryValue"] < 0).sum()),
    "cif_missing": int(raw["cifvalue"].isna().sum()),
    "fob_missing": int(raw["fobvalue"].isna().sum()),
    "primary_equals_cif": int(eq_cif.sum()),
    "primary_equals_fob": int(eq_fob.sum()),
    "primary_equals_neither": int(neither.sum()),
    "currency": "current USD",
    "analysis_scaling": "divide primaryValue by 1000 -> thousand current USD"
}])
assert int(neither.sum()) == 0
valuation.to_csv(DIAG/"valuation_audit.csv", index=False, encoding="utf-8-sig")

# Raw source explicit-zero audit.
raw.loc[raw["primaryValue"] == 0, [
    "refYear","reporterCode","reporterISO","partnerCode","partnerISO",
    "classificationCode","cmdCode","pipeline_treatment","primaryValue","_source_file"
]].to_csv(DIAG/"explicit_zero_source_rows.csv", index=False, encoding="utf-8-sig")

print("VALIDATION_LAYER_4_VALUATION=PASS")

# ------------------------------------------------------------------
# LAYER 5: Aggregate source HS6 -> analysis cultural categories
# IMPORTANT: ambiguous old-version recorded-media codes are NOT silently allocated.
# ------------------------------------------------------------------
# Normalize isReported into an integer diagnostic.
isrep = raw["isReported"].astype(str).str.lower().isin(["true","1"])
raw["_unreported_or_estimated"] = (~isrep).astype("int8")

grp = (
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

idx = ["refYear","reporterCode","reporterISO","partnerCode","partnerISO","classificationCode"]

val = grp.pivot_table(
    index=idx, columns="pipeline_treatment", values="value_usd",
    aggfunc="sum", fill_value=0
).reset_index()
val.columns.name = None

cnt = grp.groupby(idx, dropna=False).agg(
    n_source_rows=("n_source_rows","sum"),
    n_unreported_rows=("n_unreported_rows","sum")
).reset_index()

out = val.merge(cnt, on=idx, how="left", validate="1:1")  # RESCUE C10
if rescue_switch.enabled("C10"):  # RESCUE C10
    out = ia_common.add_product_variants(out, raw, idx)  # RESCUE C10

needed = ["v_3706","v_49","v_8523","v_97","AMBIGUOUS_POOL_v_8523"]
for c in needed:
    if c not in out.columns:
        out[c] = 0.0
    out[c] = pd.to_numeric(out[c], errors="coerce").fillna(0.0)

if rescue_switch.enabled("C02"):  # RESCUE C02
    out = ia_common.crosswalk(out)  # RESCUE C02
out = out.rename(columns={  # RESCUE C02
    "refYear":"year",
    "reporterCode":"reporter_code",
    "reporterISO":"reporter_iso",
    "partnerCode":"partner_code",
    "partnerISO":"partner_iso",
    "classificationCode":"hs_version",
    "v_3706":"v_3706_usd",
    "v_49":"v_49_usd",
    "v_8523":"v_8523_id_usd",
    "v_97":"v_97_usd",
    "AMBIGUOUS_POOL_v_8523":"v_8523_amb_usd",
})

# Lower/upper bounds are provenance devices, not an empirical choice.
# When ambiguous pool = 0, the recorded-media value is exact even for a pre-H3 reporter.
out["v_8523_lb_usd"] = out["v_8523_id_usd"]
out["v_8523_ub_usd"] = out["v_8523_id_usd"] + out["v_8523_amb_usd"]
out["v_8523_exact"] = (out["v_8523_amb_usd"] == 0).astype("int8")

out["v_ttl_lb_usd"] = (
    out["v_3706_usd"] + out["v_49_usd"] +
    out["v_8523_lb_usd"] + out["v_97_usd"]
)
out["v_ttl_ub_usd"] = (
    out["v_3706_usd"] + out["v_49_usd"] +
    out["v_8523_ub_usd"] + out["v_97_usd"]
)

out["any_unreported"] = (out["n_unreported_rows"] > 0).astype("int8")

# Scaling used by the manuscript.
for c in [
    "v_3706_usd","v_49_usd","v_8523_id_usd","v_8523_amb_usd",
    "v_8523_lb_usd","v_8523_ub_usd","v_97_usd",
    "v_ttl_lb_usd","v_ttl_ub_usd"
]:
    out[c.replace("_usd","_k")] = out[c] / 1000.0

if rescue_switch.enabled("C10"):  # RESCUE C10
    out = ia_common.finish_product_variants(out, DIAG)  # RESCUE C10

# Mechanical additivity.  # RESCUE C10
assert np.allclose(
    out["v_ttl_lb_usd"],
    out["v_3706_usd"] + out["v_49_usd"] + out["v_8523_lb_usd"] + out["v_97_usd"],
    rtol=0, atol=1e-7
)
assert np.allclose(
    out["v_ttl_ub_usd"],
    out["v_3706_usd"] + out["v_49_usd"] + out["v_8523_ub_usd"] + out["v_97_usd"],
    rtol=0, atol=1e-7
)

assert not out.duplicated(["year","reporter_code","partner_code"]).any()

if STRICT:
    assert len(out) == EXPECTED_SPARSE_ROWS
    assert int((out["v_8523_amb_usd"] > 0).sum()) == EXPECTED_POS_AMBIG_DYADS

print("VALIDATION_LAYER_5_CATEGORY_AGGREGATION=PASS")

# ------------------------------------------------------------------
# LAYER 6: Save sparse database + audit outputs
# ------------------------------------------------------------------
out = out.sort_values(["year","reporter_code","partner_code"]).reset_index(drop=True)

# Full source-area sparse database.
out.to_csv(FINAL/"cultural_trade_sparse_2007_2021.csv",
           index=False, encoding="utf-8-sig")

# Stata-friendly copy.
stata = out.copy()
# Keep variable names <=32 chars and plain numeric/string dtypes.
for c in ["reporter_iso","partner_iso","hs_version"]:
    stata[c] = stata[c].fillna("").astype(str)
stata.to_stata(
    FINAL/"cultural_trade_sparse_2007_2021.dta",
    write_index=False, version=118
)

# Reporter-year availability is the source of truth for later zero/missing treatment.
availability_out = avail.rename(columns={
    "_query_year":"year",
    "reporterCode":"reporter_code",
    "reporterISO":"reporter_iso",
    "reporterDesc":"reporter_desc",
    "classificationCode":"hs_version"
})[
    ["year","reporter_code","reporter_iso","reporter_desc","hs_version"]
].copy()
availability_out["trade_reporting_available"] = 1  # RESCUE C02
if rescue_switch.enabled("C02"):  # RESCUE C02
    availability_out = ia_common.crosswalk(availability_out, availability=True)  # RESCUE C02
availability_out.to_csv(
    FINAL/"reporter_year_availability_2007_2021.csv",
    index=False, encoding="utf-8-sig"
)
availability_stata = availability_out.copy()
for c in ["reporter_iso","reporter_desc","hs_version"]:
    availability_stata[c] = availability_stata[c].fillna("").astype(str)
availability_stata.to_stata(
    FINAL/"reporter_year_availability_2007_2021.dta",
    write_index=False, version=118
)

# Ambiguous recorded-media pool cases.
out.loc[out["v_8523_amb_usd"] > 0].to_csv(
    DIAG/"ambiguous_8523_positive_dyads.csv",
    index=False, encoding="utf-8-sig"
)

# Partner-area inventory used by the sparse source data.
partner_inventory = (
    raw[["partnerCode","partnerISO","partnerDesc","partner_is_group",
         "partner_entry_effective","partner_entry_expired"]]
    .drop_duplicates()
    .sort_values("partnerCode")
)
partner_inventory["looks_like_alpha3"] = (
    partner_inventory["partnerISO"].fillna("").astype(str)
    .str.fullmatch(r"[A-Z]{3}")
)
partner_inventory.to_csv(
    DIAG/"partner_area_inventory.csv",
    index=False, encoding="utf-8-sig"
)

# Concordance usage.
(
    raw.groupby(["classificationCode","pipeline_treatment","mapping_status"])
    .size().rename("raw_rows").reset_index()
    .to_csv(DIAG/"concordance_usage_raw_rows.csv", index=False, encoding="utf-8-sig")
)

# Category totals by year.
totcols = [
    "v_3706_usd","v_49_usd","v_8523_id_usd","v_8523_amb_usd",
    "v_97_usd","v_ttl_lb_usd","v_ttl_ub_usd"
]
out.groupby("year")[totcols].sum().reset_index().to_csv(
    DIAG/"category_totals_by_year.csv",
    index=False, encoding="utf-8-sig"
)

# Download/build validation summary.
summary = pd.DataFrame([{
    "raw_csv_files": len(raw_files),
    "raw_rows": len(raw),
    "legitimate_zero_row_raw_files": len(empty_files),
    "download_manifest_rows": len(manifest),
    "download_failures": int((manifest["status"] != "DOWNLOADED_OK").sum()),
    "reporter_years_queried": len(expected_ry),
    "raw_core_key_duplicates": dup_n,
    "explicit_primary_zeros": int((raw["primaryValue"] == 0).sum()),
    "primary_missing": int(raw["primaryValue"].isna().sum()),
    "primary_negative": int((raw["primaryValue"] < 0).sum()),
    "concordance_rows": len(mapping),
    "ambiguous_mapping_rows": int((mapping["mapping_status"] == "AMBIGUOUS_PARTIAL_MAPPING").sum()),
    "sparse_dyad_year_rows": len(out),
    "positive_ambiguous_pool_dyads": int((out["v_8523_amb_usd"] > 0).sum()),
    "all_primary_equals_cif_or_fob": int(neither.sum() == 0),
    "source_unit": "current USD",
    "analysis_unit": "thousand current USD",
    "flow": "M / imports",
    "classification_query": "HS / as reported",
    "mirror_reconciliation": "none"
}])
summary.to_csv(DIAG/"build_validation_summary.csv", index=False, encoding="utf-8-sig")

# Human-readable policy note.
(DIAG/"ZERO_MISSING_RULE.txt").write_text(
    "ZERO/MISSING RULE FOR MASTER MERGE\n"
    "1. Preserve explicit source zeros as zero.\n"
    "2. UN Comtrade product-partner records are sparse.\n"
    "3. After merging the sparse trade table into the master country-dyad-year universe,\n"
    "   set absent category values to zero ONLY when trade_reporting_available == 1\n"
    "   for that importer/reporter-year.\n"
    "4. If trade_reporting_available is missing/0, leave trade outcomes missing; do NOT\n"
    "   manufacture a zero for a non-reporting reporter-year.\n"
    "5. No exporter-side mirror replacement or reconciliation is used in the baseline pipeline.\n",
    encoding="utf-8"
)

(DIAG/"COMTRADE_CLEAN_BUILD_COMPLETE.txt").write_text(
    "COMTRADE_CLEAN_REBUILD_COMPLETE=yes\n"
    "classification_query=HS_as_reported\n"
    "canonical_reference=H3_HS2007\n"
    "flow=M_imports\n"
    "valuation=PrimaryValue_current_USD\n"
    "scaling=divide_by_1000\n"
    "mirror_reconciliation=none\n",
    encoding="utf-8"
)

print("VALIDATION_LAYER_6_OUTPUT_ARCHIVE=PASS")
print("COMTRADE_CLEAN_REBUILD_COMPLETE=yes")
print("Final sparse rows:", len(out))
print("Positive ambiguous v_8523 pool dyads:", int((out["v_8523_amb_usd"] > 0).sum()))
print("Output folder:", FINAL)

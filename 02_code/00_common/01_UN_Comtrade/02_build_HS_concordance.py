"""Build the frozen H0-H5 to H3/HS2007 concordance from archived UNSD inputs."""
import pandas as pd
from datetime import date
from _paths import *
ensure_dirs()

EXPECTED_TARGET_CODES = 31
EXPECTED_CONCORDANCE_ROWS = 219
EXPECTED_AMBIGUOUS_ROWS = 8

PRODUCT_DEF = CONFIG / 'product_definition_H3.csv'
WORKBOOK = RAW_REF / 'HS-SITC-BEC_Correlations_2022.xlsx'
OUT = INT_CONC
OUT.mkdir(parents=True, exist_ok=True)

for p in [PRODUCT_DEF, WORKBOOK]:
    if not p.exists():
        raise SystemExit(f"Required input not found: {p}")

# ---------------------------------------------------------------------
# Load and validate frozen H3/HS2007 target definition.
# ---------------------------------------------------------------------
products = pd.read_csv(PRODUCT_DEF, dtype={"canonical_H3_code": "string"})
required_cols = {
    "canonical_version", "canonical_nomenclature",
    "canonical_H3_code", "analysis_category", "product_rule"
}
missing = required_cols.difference(products.columns)
if missing:
    raise RuntimeError(f"Product definition is missing columns: {sorted(missing)}")

products["canonical_H3_code"] = products["canonical_H3_code"].str.strip().str.zfill(6)

if len(products) != EXPECTED_TARGET_CODES:
    raise RuntimeError(
        f"Frozen product definition should contain {EXPECTED_TARGET_CODES} rows; found {len(products)}."
    )
if products["canonical_H3_code"].duplicated().any():
    raise RuntimeError("Duplicate H3 codes in product definition.")
if set(products["canonical_version"]) != {"H3"}:
    raise RuntimeError("Canonical version must be H3.")
if set(products["canonical_nomenclature"]) != {"HS2007"}:
    raise RuntimeError("Canonical nomenclature must be HS2007.")

target_codes = set(products["canonical_H3_code"])
category_by_h3 = dict(zip(products["canonical_H3_code"], products["analysis_category"]))

# ---------------------------------------------------------------------
# Load official UNSD complete correlation workbook.
# ---------------------------------------------------------------------
sheet = "HS SITC BEC"
raw = pd.read_excel(
    WORKBOOK,
    sheet_name=sheet,
    dtype=str,
    usecols=["HS92", "HS96", "HS02", "HS07", "HS12", "HS17"]
).rename(columns={
    "HS92": "H0",
    "HS96": "H1",
    "HS02": "H2",
    "HS07": "H3",
    "HS12": "H4",
    "HS17": "H5",
})

for c in raw.columns:
    raw[c] = raw[c].astype("string").str.strip()
    raw.loc[raw[c].isin(["", "nan", "None", "<NA>"]), c] = pd.NA
    raw[c] = raw[c].str.zfill(6)

version_map = pd.DataFrame([
    ["H0", "HS1992", "HS 1988/1992 family in UN Comtrade code H0"],
    ["H1", "HS1996", "HS 1996"],
    ["H2", "HS2002", "HS 2002"],
    ["H3", "HS2007", "HS 2007; canonical target vintage"],
    ["H4", "HS2012", "HS 2012"],
    ["H5", "HS2017", "HS 2017"],
], columns=["classificationCode", "HS_vintage", "note"])

# ---------------------------------------------------------------------
# Construct source-edition -> canonical-H3 mapping.
# ---------------------------------------------------------------------
records = []

for source_version in ["H0", "H1", "H2", "H3", "H4", "H5"]:
    if source_version == "H3":
        # Identity mapping for canonical H3 codes present in the official table.
        available_h3 = sorted(set(raw["H3"].dropna()))
        source_to_h3 = {code: [code] for code in available_h3}
    else:
        pairs = raw[[source_version, "H3"]].dropna().drop_duplicates()
        source_to_h3 = (
            pairs.groupby(source_version)["H3"]
            .agg(lambda s: sorted(set(s)))
            .to_dict()
        )

    for source_code, all_h3_codes in source_to_h3.items():
        touched_target = [c for c in all_h3_codes if c in target_codes]
        if not touched_target:
            continue

        non_target = [c for c in all_h3_codes if c not in target_codes]
        categories = sorted({category_by_h3[c] for c in touched_target})

        if len(non_target) == 0 and len(categories) == 1:
            mapping_status = "SAFE_CATEGORY_MAPPING"
            pipeline_treatment = categories[0]
        elif len(non_target) == 0 and len(categories) > 1:
            mapping_status = "SAFE_BUT_CROSSES_ANALYSIS_CATEGORIES"
            pipeline_treatment = "REVIEW"
        else:
            mapping_status = "AMBIGUOUS_PARTIAL_MAPPING"
            if categories:
                pipeline_treatment = "AMBIGUOUS_POOL_" + "_".join(categories)
            else:
                pipeline_treatment = "AMBIGUOUS_POOL_UNKNOWN"

        records.append({
            "source_version": source_version,
            "source_code": source_code,
            "canonical_H3_codes_touched": ";".join(touched_target),
            "analysis_categories_touched": ";".join(categories),
            "all_H3_codes_from_official_correlation": ";".join(all_h3_codes),
            "non_target_H3_codes": ";".join(non_target),
            "n_all_H3_codes": len(all_h3_codes),
            "n_target_H3_codes": len(touched_target),
            "n_non_target_H3_codes": len(non_target),
            "mapping_status": mapping_status,
            "pipeline_treatment": pipeline_treatment,
            "download_this_source_code": 1,
        })

concordance = pd.DataFrame(records).sort_values(
    ["source_version", "mapping_status", "source_code"]
).reset_index(drop=True)

if concordance.duplicated(["source_version", "source_code"]).any():
    raise RuntimeError("Concordance has duplicate source_version × source_code rows.")

if len(concordance) != EXPECTED_CONCORDANCE_ROWS:
    raise RuntimeError(
        f"Frozen concordance should have {EXPECTED_CONCORDANCE_ROWS} rows; found {len(concordance)}."
    )

ambiguous = concordance[
    concordance["mapping_status"] == "AMBIGUOUS_PARTIAL_MAPPING"
].copy()

if len(ambiguous) != EXPECTED_AMBIGUOUS_ROWS:
    raise RuntimeError(
        f"Frozen concordance should have {EXPECTED_AMBIGUOUS_ROWS} ambiguous rows; found {len(ambiguous)}."
    )

download_targets = (
    concordance[
        [
            "source_version", "source_code", "mapping_status", "pipeline_treatment",
            "canonical_H3_codes_touched", "analysis_categories_touched"
        ]
    ]
    .drop_duplicates()
    .sort_values(["source_version", "source_code"])
    .reset_index(drop=True)
)

mapping_summary = (
    concordance.groupby(["source_version", "mapping_status"])
    .size()
    .rename("source_code_count")
    .reset_index()
)

# ---------------------------------------------------------------------
# Save reproducible outputs.
# ---------------------------------------------------------------------
version_map.to_csv(
    OUT / "classification_version_map.csv",
    index=False, encoding="utf-8-sig"
)
concordance.to_csv(
    OUT / "reported_HS_to_H3_concordance.csv",
    index=False, encoding="utf-8-sig"
)
download_targets.to_csv(
    OUT / "reported_HS_download_targets_by_version.csv",
    index=False, encoding="utf-8-sig"
)
mapping_summary.to_csv(
    DIAG_CONC / "concordance_mapping_status_summary.csv",
    index=False, encoding="utf-8-sig"
)
ambiguous.to_csv(
    DIAG_CONC / "ambiguous_preH3_8523_mappings.csv",
    index=False, encoding="utf-8-sig"
)

# Source/output audit.

audit = pd.DataFrame([{
    "canonical_version": "H3",
    "canonical_nomenclature": "HS2007",
    "target_H3_codes": len(products),
    "concordance_rows": len(concordance),
    "ambiguous_rows": len(ambiguous),
    "source_versions": "H0;H1;H2;H3;H4;H5",
    "official_workbook": WORKBOOK.name,
    "official_workbook_bytes": WORKBOOK.stat().st_size,
    "product_definition": PRODUCT_DEF.name,
    "workbook_sheet": sheet,
    "build_date": str(date.today()),
}])
audit.to_csv(
    DIAG_CONC / "concordance_build_audit.csv",
    index=False, encoding="utf-8-sig"
)

print("HS_CONCORDANCE_BUILD=PASS")
print("Canonical target codes:", len(products))
print("Concordance rows:", len(concordance))
print("Ambiguous rows:", len(ambiguous))
print("Output folder:", OUT)

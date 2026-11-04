from pathlib import Path
import json
import math
import re
import numpy as np
import pandas as pd
import xlrd
from _paths import *

ensure_dirs()
cfg = json.loads((CONFIG/"construction_specification.json").read_text(encoding="utf-8"))

# ------------------------------------------------------------------
# Locate exactly one archived .xls source.
# Raw filenames are preserved; no renaming is required.
# ------------------------------------------------------------------
candidates = sorted(RAW.glob("6-dimensions-for-website-2015-08-16*.xls"))
# replication package: without the workbook, read its first sheet as rebuilt from the official file by
# tools/rebuild_hofstede_inputs.py (same cell types and values; path in PKG_HOFSTEDE_SHEET_JSON)
import os
_rebuilt = os.environ.get("PKG_HOFSTEDE_SHEET_JSON", "")
if not candidates and _rebuilt and Path(_rebuilt).is_file():
    candidates = [Path(_rebuilt)]
if len(candidates) != 1:
    raise SystemExit(
        f"Expected exactly one Hofstede XLS matching the archived filename pattern in {RAW}; "
        f"found {len(candidates)}."
    )
SOURCE = candidates[0]

def norm_text(x):
    s = "" if x is None else str(x)
    s = s.replace("\n", " ").replace("\r", " ").strip().lower()
    return re.sub(r"[^a-z0-9]+", "", s)

def cell_value(sheet, r, c):
    cell = sheet.cell(r, c)
    if cell.ctype in (xlrd.XL_CELL_EMPTY, xlrd.XL_CELL_BLANK):
        return None
    if cell.ctype == xlrd.XL_CELL_ERROR:
        return None
    v = cell.value
    if isinstance(v, str):
        t = v.strip()
        if t == "" or t.upper() in {"#NULL!", "#N/A", "NA", "N/A", ".", ".."}:
            return None
        return t
    return v

def as_number(x):
    if x is None:
        return np.nan
    if isinstance(x, (int, float, np.integer, np.floating)):
        return float(x)
    s = str(x).strip()
    if s == "" or s.upper() in {"#NULL!", "#N/A", "NA", "N/A", ".", ".."}:
        return np.nan
    try:
        return float(s)
    except Exception:
        return np.nan

class _RebuiltSheet:
    def __init__(self, d):
        self.name, self._c = d["sheet_name"], d["cells"]
        self.nrows, self.ncols = len(self._c), len(self._c[0])
    def cell(self, r, c):
        t, v = self._c[r][c]
        return xlrd.sheet.Cell(t, v)
class _RebuiltBook:
    def __init__(self, p):
        self._s = _RebuiltSheet(json.loads(Path(p).read_text(encoding="utf-8")))
    def sheet_names(self):
        return [self._s.name]
    def sheet_by_name(self, n):
        return self._s
    def sheet_by_index(self, i):
        return self._s
wb = _RebuiltBook(SOURCE) if SOURCE.suffix == ".json" else xlrd.open_workbook(SOURCE, on_demand=True)
sheet_names = wb.sheet_names()

# Prefer the expected sheet; otherwise choose the first sheet whose early rows contain dimension headers.
preferred = [s for s in sheet_names if "6 dimensions" in s.lower()]
sheet = wb.sheet_by_name(preferred[0]) if preferred else wb.sheet_by_index(0)

# ------------------------------------------------------------------
# Detect header row and columns robustly.
# ------------------------------------------------------------------
header_row = None
header_norm = None
for r in range(min(sheet.nrows, 30)):
    vals = [norm_text(cell_value(sheet, r, c)) for c in range(sheet.ncols)]
    tokens = set(vals)
    must = {"country", "pdi", "idv", "mas", "uai", "ivr"}
    if must.issubset(tokens) and ("ltowvs" in tokens or "lto" in tokens):
        header_row = r
        header_norm = vals
        break

if header_row is None:
    raise RuntimeError(
        "Could not detect the Hofstede header row. Expected country, PDI, IDV, MAS, UAI, LTO/LTOWVS and IVR."
    )

def find_col(predicate):
    hits = [i for i, h in enumerate(header_norm) if predicate(h)]
    return hits[0] if hits else None

cols = {
    "country": find_col(lambda h: h == "country"),
    "pdi": find_col(lambda h: h == "pdi"),
    "idv": find_col(lambda h: h == "idv"),
    "mas": find_col(lambda h: h == "mas"),
    "uai": find_col(lambda h: h == "uai"),
    "lto": find_col(lambda h: h in {"lto", "ltowvs"}),
    "ivr": find_col(lambda h: h == "ivr"),
    "iso3": find_col(lambda h: ("iso3" in h and ("alpha3" in h or "alpha" in h))),
    "iso3num": find_col(lambda h: ("iso3" in h and ("numeric" in h or "number" in h))),
}

required_cols = ["country","pdi","idv","mas","uai","lto","ivr","iso3","iso3num"]
missing_cols = [k for k in required_cols if cols[k] is None]
if missing_cols:
    raise RuntimeError(
        "The archived XLS does not contain all fields needed for the current reconstruction: "
        + ", ".join(missing_cols)
        + ". This matters because the archived file appears to include an author-added ISO crosswalk."
    )

rows = []
for r in range(header_row + 1, sheet.nrows):
    country = cell_value(sheet, r, cols["country"])
    if country is None:
        continue
    country = str(country).strip()
    if country == "":
        continue

    iso3_raw = cell_value(sheet, r, cols["iso3"])
    iso3 = "" if iso3_raw is None else str(iso3_raw).strip().upper()
    # Remove stray whitespace/tab characters around three-letter codes.
    iso3 = re.sub(r"\s+", "", iso3)

    iso3num_raw = as_number(cell_value(sheet, r, cols["iso3num"]))
    iso3num = int(round(iso3num_raw)) if pd.notna(iso3num_raw) else np.nan

    rec = {
        "source_row": r + 1,  # Excel-style 1-based row number
        "country": country,
        "iso3": iso3,
        "iso3num": iso3num,
    }
    for d in cfg["dimensions"]:
        rec[d] = as_number(cell_value(sheet, r, cols[d]))
    rows.append(rec)

all_rows = pd.DataFrame(rows)
if all_rows.empty:
    raise RuntimeError("No nonblank rows were extracted from the Hofstede XLS.")

# ------------------------------------------------------------------
# Separate ISO country rows from regional benchmark/non-country rows.
# ------------------------------------------------------------------
is_iso3 = all_rows["iso3"].str.fullmatch(r"[A-Z]{3}", na=False)
countries = all_rows[is_iso3].copy()
non_country = all_rows[~is_iso3].copy()

if countries["iso3"].duplicated().any():
    dup = countries[countries["iso3"].duplicated(keep=False)].sort_values("iso3")
    dup.to_csv(DIAG/"duplicate_iso3_country_rows.csv", index=False, encoding="utf-8-sig")
    raise RuntimeError("Duplicate ISO3 country rows found in archived Hofstede XLS.")

countries["iso3num"] = pd.to_numeric(countries["iso3num"], errors="coerce")
if countries["iso3num"].isna().any():
    raise RuntimeError("At least one ISO3 country row has missing ISO numeric code.")

countries["iso3num"] = countries["iso3num"].astype("int32")
countries["available_dim_count"] = countries[cfg["dimensions"]].notna().sum(axis=1).astype("int8")

# ------------------------------------------------------------------
# Detect regional benchmark rows and country rows that exactly reuse their first four dimensions.
# This is an audit flag, not an exclusion rule.
# ------------------------------------------------------------------
bench_names = {norm_text(x): x for x in cfg["regional_benchmark_names"]}
bench = non_country[
    non_country["country"].map(norm_text).isin(bench_names)
].copy()

if len(bench):
    bench["regional_benchmark_name"] = bench["country"].map(
        lambda x: bench_names.get(norm_text(x), x)
    )
else:
    bench["regional_benchmark_name"] = pd.Series(dtype="object")

countries["regional_proxy_group"] = ""
four = cfg["original_ks_dimensions"]

for _, b in bench.iterrows():
    if b[four].isna().any():
        continue
    mask = pd.Series(True, index=countries.index)
    for d in four:
        mask &= np.isclose(countries[d], b[d], rtol=0, atol=1e-12, equal_nan=False)
    countries.loc[mask, "regional_proxy_group"] = b["regional_benchmark_name"]

countries["regional_proxy_flag"] = (countries["regional_proxy_group"] != "").astype("int8")

# ------------------------------------------------------------------
# Diagnostics on missingness and stored numeric precision.
# ------------------------------------------------------------------
coverage_rows = []
for d in cfg["dimensions"]:
    coverage_rows.append({
        "dimension": d,
        "country_rows": len(countries),
        "nonmissing": int(countries[d].notna().sum()),
        "missing": int(countries[d].isna().sum()),
        "sample_variance": float(countries[d].var(ddof=1)),
        "max_abs_fractional_part": float(
            (countries[d].dropna() - countries[d].dropna().round()).abs().max()
        ) if countries[d].notna().any() else np.nan
    })
pd.DataFrame(coverage_rows).to_csv(
    DIAG/"dimension_coverage_and_precision.csv", index=False, encoding="utf-8-sig"
)

countries["available_dim_count"].value_counts().sort_index().rename_axis(
    "available_dim_count"
).reset_index(name="country_count").to_csv(
    DIAG/"country_dimension_count_distribution.csv", index=False, encoding="utf-8-sig"
)

countries.loc[countries["regional_proxy_flag"]==1].to_csv(
    DIAG/"regional_proxy_country_flags.csv", index=False, encoding="utf-8-sig"
)
bench.to_csv(
    DIAG/"regional_benchmark_rows.csv", index=False, encoding="utf-8-sig"
)
non_country.to_csv(
    DIAG/"non_country_rows_from_source.xls.csv", index=False, encoding="utf-8-sig"
)

# ------------------------------------------------------------------
# Save extracted source representation.
# ------------------------------------------------------------------
all_rows.to_csv(
    INTERMEDIATE/"hofstede_matrix_extracted_all_nonblank_rows.csv",
    index=False, encoding="utf-8-sig"
)
countries.to_csv(
    INTERMEDIATE/"hofstede_country_scores_2015.csv",
    index=False, encoding="utf-8-sig"
)

stata_countries = countries.copy()
for c in ["country","iso3","regional_proxy_group"]:
    stata_countries[c] = stata_countries[c].fillna("").astype(str)
stata_countries.to_stata(
    INTERMEDIATE/"hofstede_country_scores_2015.dta",
    write_index=False, version=118
)

# Source manifest.
manifest = pd.DataFrame([{
    "source_file": SOURCE.name,
    "relative_path": SOURCE.relative_to(ROOT).as_posix(),
    "bytes": SOURCE.stat().st_size,
    "sheet_used": sheet.name,
    "header_excel_row": header_row + 1,
    "source_nonblank_rows": len(all_rows),
    "iso3_country_rows": len(countries),
    "non_country_rows": len(non_country),
    "regional_benchmark_rows_detected": len(bench),
    "official_source_page": cfg["official_source_page"],
    "historical_file_url": cfg["historical_file_url"],
    "provenance_note": (
        "Archived working source. The uploaded workbook has author/workbook edits such as ISO code columns; "
        "do not describe this physical file as a pristine untouched official download."
    )
}])
manifest.to_csv(DIAG/"source_manifest.csv", index=False, encoding="utf-8-sig")

# Snapshot-level structural checks based on the archived working file supplied for this paper.
if len(countries) != 137:
    raise RuntimeError(
        f"Archived working source was expected to contain 137 ISO3 country rows; found {len(countries)}."
    )

print("HOFSTEDE_SOURCE_EXTRACTION_AND_AUDIT=PASS")
print("Source:", SOURCE.name)
print("Country rows:", len(countries))
print("Countries with >=4 dimensions:", int((countries["available_dim_count"]>=4).sum()))
print("Countries with all 6 dimensions:", int((countries["available_dim_count"]==6).sum()))
print("Regional-proxy flagged countries:", int(countries["regional_proxy_flag"].sum()))

"""A2_00_hofstede.py -- Hofstede cultural distance rebuilt twice (block A2, item A2.5).

(1) PACKAGE rebuild: from the LibreOffice CSV export of the package workbook
    PKG/01_raw/04_Hofstede/6-dimensions-for-website-2015-08-16 (1).xls
    (derived_package_xls_sheet_via_libreoffice.csv, written by A2_00a_hofstede_sheets.py),
    with the package rule, to serve as a positive control against prepared.dta cul_dist.
(2) OFFICIAL-ONLY rebuild: from the LibreOffice CSV export of the official workbook
    (derived_official_0816_sheet_via_libreoffice.csv, written by A2_00a_hofstede_sheets.py;
    source xls sha256 e0be0407...), regional rows (AFE, AFW, ARA) excluded, same formula.

Formula, verbatim from PKG/02_code/01_database_preparation/04_Hofstede/
01_build_bilateral_cultural_distance.py:
  :25  variances = {d: float(c[d].var(ddof=1)) for d in dims}
  :70  pairs[col] = ((pairs[f"{dim}_d"] - pairs[f"{dim}_o"]) ** 2) / variances[dim]
  :73  pairs["common_dim_count6"] = pairs[dist_cols].notna().sum(axis=1).astype("int8")
  :90  pairs["cd6_ge4"] = pairs[dist_cols].mean(axis=1, skipna=True)
  :91  pairs.loc[pairs["common_dim_count6"] < 4, "cd6_ge4"] = np.nan
  :93  pairs["cd6_strict"] = pairs[dist_cols].mean(axis=1, skipna=False)
Country table = rows with a three-letter ISO3 code (00_extract_and_audit_hofstede_source.py:153-154);
missing tokens "#NULL!" etc. are NaN (00_extract...py:50, 61).
Mapping Hofstede ctr -> ISO3: the package workbook's own ISO-3 column for the same ctr row.

Usage: python3 A2_00_hofstede.py <src_dir> <out_dir>   (src_dir holds the two CSV sheets; writes out_dir/*)
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

import numpy as np
import pandas as pd

SRC = Path(sys.argv[1])
OUT = Path(sys.argv[2])
OUT.mkdir(parents=True, exist_ok=True)
DIMS = ["pdi", "idv", "mas", "uai", "lto", "ivr"]
FOUR = ["pdi", "idv", "mas", "uai"]
REGIONAL_CTR = {"AFE", "AFW", "ARA"}
NULLS = {"#NULL!", "#N/A", "NA", "N/A", ".", ".."}


def num(s: pd.Series) -> pd.Series:
    t = s.astype("string").str.strip()
    t = t.mask(t.isin(NULLS) | (t == ""))
    return pd.to_numeric(t.str.replace(",", ".", regex=False), errors="coerce")


def read(path: Path, package: bool) -> pd.DataFrame:
    d = pd.read_csv(path, sep=";", dtype=str, keep_default_na=False)
    cols = ["ctr", "country", "pdi", "idv", "mas", "uai", "lto", "ivr"]
    if package:
        cols += ["iso3", "iso3num"]
    d.columns = cols
    d["ctr"] = d["ctr"].str.strip()
    for c in DIMS:
        d[c] = num(d[c])
    return d


def bilateral(c: pd.DataFrame, label: str) -> tuple[pd.DataFrame, dict]:
    assert not c["iso3"].duplicated().any(), f"{label}: duplicated ISO3"
    var = {d: float(c[d].var(ddof=1)) for d in DIMS}
    o = c[["iso3"] + DIMS].rename(columns={"iso3": "iso3_o", **{d: f"{d}_o" for d in DIMS}})
    dd = c[["iso3"] + DIMS].rename(columns={"iso3": "iso3_d", **{d: f"{d}_d" for d in DIMS}})
    p = o.merge(dd, how="cross")
    p = p[p.iso3_o != p.iso3_d].copy()
    cols = []
    for d in DIMS:
        p[f"nd2_{d}"] = ((p[f"{d}_d"] - p[f"{d}_o"]) ** 2) / var[d]
        cols.append(f"nd2_{d}")
    p["cdim"] = p[cols].notna().sum(axis=1).astype("int8")
    p["cd_ge4"] = p[cols].mean(axis=1, skipna=True)
    p.loc[p["cdim"] < 4, "cd_ge4"] = np.nan
    p["cd_strict"] = p[cols].mean(axis=1, skipna=False)
    info = {
        "label": label,
        "country_rows": int(len(c)),
        "ordered_dyads": int(len(p)),
        "cd_ge4_nonmissing": int(p.cd_ge4.notna().sum()),
        "cd_strict_nonmissing": int(p.cd_strict.notna().sum()),
        "variances": var,
        "nonmissing_scores": {d: int(c[d].notna().sum()) for d in DIMS},
    }
    return p[["iso3_o", "iso3_d", "cd_ge4", "cd_strict", "cdim"]], info


pkg = read(SRC / "derived_package_xls_sheet_via_libreoffice.csv", package=True)
off = read(SRC / "derived_official_0816_sheet_via_libreoffice.csv", package=False)

# ---- (1) package rebuild: ISO3 country rows of the package workbook
pkg["iso3"] = pkg["iso3"].str.replace(r"\s+", "", regex=True).str.upper()
pkg_c = pkg[pkg["iso3"].str.fullmatch(r"[A-Z]{3}")].copy()
pkg_pairs, pkg_info = bilateral(pkg_c, "package_rebuild")

# ---- (2) official-only rebuild with ctr -> ISO3 from the package workbook rows that carry a ctr code
map_rows = pkg[(pkg["ctr"] != "") & pkg["iso3"].str.fullmatch(r"[A-Z]{3}")][["ctr", "iso3", "country"]]
assert not map_rows["ctr"].duplicated().any(), "ctr not unique in package workbook"
assert not map_rows["iso3"].duplicated().any(), "ISO3 not unique in ctr mapping"
off_reg = off[off["ctr"].isin(REGIONAL_CTR)]
off_nonreg = off[~off["ctr"].isin(REGIONAL_CTR)].merge(
    map_rows.rename(columns={"country": "country_pkg"}), on="ctr", how="left", validate="1:1")
unmapped = off_nonreg[off_nonreg["iso3"].isna()][["ctr", "country"]]
off_c = off_nonreg[off_nonreg["iso3"].notna()].copy()
off_pairs, off_info = bilateral(off_c, "official_only")

# ---- audit: package vs official values on the mapped rows
cmp = off_c[["ctr", "iso3"] + DIMS].merge(pkg_c[["iso3"] + DIMS], on="iso3", suffixes=("_off", "_pkg"))
diff_rows = []
for _, r in cmp.iterrows():
    for d in DIMS:
        a, b = r[f"{d}_off"], r[f"{d}_pkg"]
        same = (pd.isna(a) and pd.isna(b)) or (pd.notna(a) and pd.notna(b) and abs(a - b) <= 1e-9)
        if not same:
            diff_rows.append({"ctr": r.ctr, "iso3": r.iso3, "dimension": d, "official": a, "package": b})
diffs = pd.DataFrame(diff_rows)
added = pkg_c[(pkg_c["ctr"] == "")][["iso3", "country"]]

out = pkg_pairs.rename(columns={"cd_ge4": "cd_pkg_rebuilt", "cd_strict": "cd_pkg_strict_rebuilt",
                                "cdim": "cdim_pkg_rebuilt"}).merge(
    off_pairs.rename(columns={"cd_ge4": "cd_off", "cd_strict": "cd_off_strict", "cdim": "cdim_off"}),
    on=["iso3_o", "iso3_d"], how="outer", validate="1:1")
out.to_csv(OUT / "A2_hofstede_cd.csv", index=False, float_format="%.17g")
diffs.to_csv(OUT / "A2_hofstede_pkg_vs_official_diffs.csv", index=False)
map_rows.to_csv(OUT / "A2_hofstede_ctr_iso3_map.csv", index=False)
added.to_csv(OUT / "A2_hofstede_package_added_rows.csv", index=False)
unmapped.to_csv(OUT / "A2_hofstede_official_unmapped_rows.csv", index=False)
summary = {
    "package": pkg_info, "official": off_info,
    "official_regional_rows_excluded": off_reg["ctr"].tolist(),
    "official_nonregional_rows_without_iso3_in_package_map": unmapped.to_dict("records"),
    "mapped_official_rows": int(len(off_c)),
    "ctr_iso3_mapping_one_to_one": bool((not map_rows.ctr.duplicated().any()) and (not map_rows.iso3.duplicated().any())),
    "package_rows_without_ctr_added": int(len(added)),
    "mapped_rows_with_any_value_difference": int(diffs["iso3"].nunique()) if len(diffs) else 0,
    "value_differences_by_dimension": diffs.groupby("dimension").size().to_dict() if len(diffs) else {},
    "official_cell_missing_package_filled": int((diffs["official"].isna() & diffs["package"].notna()).sum()) if len(diffs) else 0,
    "both_present_but_different": int((diffs["official"].notna() & diffs["package"].notna()).sum()) if len(diffs) else 0,
}
(OUT / "A2_hofstede_summary.json").write_text(json.dumps(summary, indent=2, default=float) + "\n")
print(json.dumps({k: summary[k] for k in ["mapped_official_rows", "ctr_iso3_mapping_one_to_one",
      "package_rows_without_ctr_added", "mapped_rows_with_any_value_difference",
      "official_cell_missing_package_filled", "both_present_but_different"]}))
print("package", pkg_info["country_rows"], pkg_info["ordered_dyads"], pkg_info["cd_ge4_nonmissing"], pkg_info["cd_strict_nonmissing"])
print("official", off_info["country_rows"], off_info["ordered_dyads"], off_info["cd_ge4_nonmissing"], off_info["cd_strict_nonmissing"])
print("A2_HOFSTEDE=PASS")

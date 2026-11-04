import pandas as pd
from _paths import *

ensure_dirs()
SRC = FINAL / "hofstede_bilateral_cultural_distance.dta"
if not SRC.exists():
    raise SystemExit("Run 01_build_bilateral_cultural_distance.py first.")

df = pd.read_stata(SRC, convert_categoricals=False)

keep = [
    "iso3_o","iso3_d",
    "cd6_ge4","cd6_strict","cd4_ks","common_dim_count6",
    "regional_proxy_flag_o","regional_proxy_flag_d","any_regional_proxy"
]
out = df[keep].copy()

if out.duplicated(["iso3_o","iso3_d"]).any():
    raise RuntimeError("Hofstede master-merge input is not unique by iso3_o + iso3_d.")

out.to_stata(
    MASTER_INT/"hofstede_cultural_distance_for_master_merge.dta",
    write_index=False, version=118
)
out.to_csv(
    MASTER_INT/"hofstede_cultural_distance_for_master_merge.csv",
    index=False, encoding="utf-8-sig"
)

note = """HOFSTEDE CULTURAL-DISTANCE MASTER-MERGE NOTE

Merge key:
    iso3_o + iso3_d

The measure is time-invariant; do NOT merge on year.

Measures retained:
1. cd6_ge4
   Reproduces the previous construction rule:
   pair-specific mean across available standardized squared dimension differences,
   requiring at least 4 common dimensions.

2. cd6_strict
   Fixed six-dimensional index:
   all six Hofstede dimensions are required and the denominator is always 6.

3. cd4_ks
   Original four-dimension Kogut-Singh structure:
   PDI, IDV, MAS and UAI all required.

No baseline choice is made in the upstream pipeline.
Regional-proxy flags are retained so any later treatment is explicit.
"""
(MASTER_INT/"HOFSTEDE_MEASURE_SELECTION_NOTE.txt").write_text(note, encoding="utf-8")

print("HOFSTEDE_MASTER_MERGE_INPUT=PASS")
print("Rows:", len(out))
print("Key: iso3_o + iso3_d")

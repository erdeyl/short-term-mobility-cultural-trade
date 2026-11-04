"""SW2_02: read-only extract from CEPII Gravity V202211: the set of (year, iso3, iso3num) with country_exists==1
(origin side), years 2005-2021, used to test which UN Tourism area codes can merge (master merge key
year+iso3num_o+iso3num_d, PKG 05_master/01_build_master_panel.py:193-200)."""
import pandas as pd
from pathlib import Path
# package paths: ROOT = package root; screens write to 05_output/11_data_screens (not run by run_all.py)
ROOT = Path(__file__).resolve().parents[2]
P = ROOT / "01_raw/01_Gravity/Gravity_V202211.dta"
OUT = ROOT / "05_output/11_data_screens/work/cepii_codes_by_year.csv"
it = pd.read_stata(P, columns=["year", "iso3_o", "iso3num_o", "country_exists_o"], iterator=True, chunksize=500000)
parts = []
for ch in it:
    ch = ch[(ch["year"] >= 2005) & (ch["year"] <= 2021)]
    parts.append(ch.drop_duplicates())
d = pd.concat(parts).drop_duplicates()
d.to_csv(OUT, index=False)
print(len(d), d["year"].min(), d["year"].max())

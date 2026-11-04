"""SW2_03: read-only slim extract of 05_output/10_analysis/<vintage>/prepared.dta (variables needed to count
affected baseline rows). Writes 05_output/11_data_screens/work/prepared_<vintage>_slim.csv.gz."""
import sys
import pandas as pd
v = sys.argv[1]
from pathlib import Path
# package paths: ROOT = package root; screens write to 05_output/11_data_screens (not run by run_all.py)
ROOT = Path(__file__).resolve().parents[2]
W = str(ROOT)
cols = ["year", "iso3_o", "iso3_d", "tourists", "visitors", "v_ttl_k", "rev_tour_raw", "rev_vis_raw",
        "same_tour_raw", "same_vis_raw", "has_both_tour", "has_both_vis", "basis_rev_tour", "basis_rev_vis",
        "basis_same_tour", "basis_same_vis", "tour_file_rev", "vis_file_rev", "tour_file_same", "vis_file_same",
        "s_base_vis", "s_base_tour", "comtrade_reporting_available", "tradeflow_comtrade_d", "pair_id"]
it = pd.read_stata(f"{W}/05_output/10_analysis/{v}/prepared.dta", columns=cols, iterator=True, chunksize=200000,
                   convert_categoricals=False)
d = pd.concat(list(it), ignore_index=True)
d.to_csv(f"{W}/05_output/11_data_screens/work/prepared_{v}_slim.csv.gz", index=False, compression="gzip")
print(v, len(d), int(d.s_base_vis.sum()), int(d.s_base_tour.sum()))

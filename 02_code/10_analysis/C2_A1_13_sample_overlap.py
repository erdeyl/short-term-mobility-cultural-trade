"""C2_A1_13_sample_overlap.py -- economies in the visitor and tourist baseline samples and their overlap.

Usage: python3 C2_A1_13_sample_overlap.py <core OUT folder>   (W: analysis/out/corrected2x)
Reads tables/A1_A1.2_economy_lists.csv (A1_01, one row per sample and economy) and writes
tables/sample_overlap.csv: stat,value for the baseline samples s_base_vis and s_base_tour
(economies in each, in both, in either, in one only). Exit 1 if a sample is missing.
"""
import sys
from pathlib import Path
import pandas as pd

out = Path(sys.argv[1])
d = pd.read_csv(out / "tables" / "A1_A1.2_economy_lists.csv", dtype=str, keep_default_na=False)
v = set(d.loc[d["sample"] == "s_base_vis", "iso3"])
t = set(d.loc[d["sample"] == "s_base_tour", "iso3"])
if not v or not t:
    sys.exit("baseline sample missing in A1_A1.2_economy_lists.csv")
rows = [("economies_vis", len(v)), ("economies_tour", len(t)), ("economies_both", len(v & t)),
        ("economies_either", len(v | t)), ("economies_vis_only", len(v - t)), ("economies_tour_only", len(t - v))]
pd.DataFrame(rows, columns=["stat", "value"]).to_csv(out / "tables" / "sample_overlap.csv", index=False)
print(dict(rows))

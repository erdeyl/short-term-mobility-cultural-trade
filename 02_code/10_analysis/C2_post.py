#!/usr/bin/env python3
"""C2_post.py -- rerun C2 post-processing of the corrected2 / corrected2x result files (no estimation).

(1) The A1/A2/FIG/TAB posting programs store the vintage label as str10 (A1_00_programs.do:27,
    A2_00_programs.do:19,132, TAB_01.do tab_open), which truncates "corrected2x" to "corrected2". Every
    CSV under out/corrected2x/ whose column `vintage` reads "corrected2" is relabelled "corrected2x"
    (the folder is the vintage). No other cell is touched.
(2) Appends the HS 490700 value-share rows (C2_03_extras.do, tables/A2_A2.6_hs490700_share.csv) to
    tables/A2_A2.6.csv as table "value_share_hs490700" (idempotent: earlier appended rows are replaced).
Usage: python3 C2_post.py
"""
import glob, os
import pandas as pd

O = (os.environ.get("PKG_ROOT") or os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))) + "/05_output/10_analysis"
n = 0
# audit check: the unordered-pair sandbox corrected2x_upair (C2_A1_12_make_upair.py) holds the same vintage
for p in sorted(glob.glob(O + "/corrected2x/**/*.csv", recursive=True) + glob.glob(O + "/corrected2x_upair/**/*.csv", recursive=True)):
    try:
        d = pd.read_csv(p, dtype=str, keep_default_na=False)
    except Exception:
        continue
    if "vintage" in d.columns and (d.vintage == "corrected2").any():
        d.loc[d.vintage == "corrected2", "vintage"] = "corrected2x"
        d.to_csv(p, index=False)
        n += 1
print("relabelled files:", n)
for v in ("corrected2", "corrected2x"):
    a = O + f"/{v}/tables/A2_A2.6.csv"
    s = O + f"/{v}/tables/A2_A2.6_hs490700_share.csv"
    if not (os.path.exists(a) and os.path.exists(s)):
        print("skip", v)
        continue
    A = pd.read_csv(a, dtype=str, keep_default_na=False)
    B = pd.read_csv(s, dtype=str, keep_default_na=False)
    B.columns = [c if c != "n" else "N" for c in B.columns]
    B = B.rename(columns={c: c for c in B.columns})
    assert set(B.columns) <= set(A.columns) | {"N"}, (list(A.columns), list(B.columns))
    A = A[A["table"] != "value_share_hs490700"]
    B = B.reindex(columns=A.columns, fill_value="")
    pd.concat([A, B], ignore_index=True).to_csv(a, index=False)
    print("A2.6 hs490700 rows appended:", v, len(B))
# (3) TAB_results.csv: mobility column (author decision 2026-11-04) so that rows that differ only by file order
#     (T5 strict6_interaction, term strict_x) can be selected by content. Rule: "vis"/"tour" from the term or
#     the sample; strict_x takes the mobility of the strict6_mobility row posted immediately before it
#     (TAB_01.do posts mobility then interaction per measure); mob_day rows = "vis_minus_tour".
for v in ("corrected", "corrected2", "corrected2x"):
    p = O + f"/{v}/TAB_results.csv"
    if not os.path.exists(p):  # replication package: vintage not run (default run = corrected2x only)
        print("skip", v)
        continue
    T = pd.read_csv(p, dtype=str, keep_default_na=False)
    mob = []
    for i, r in T.iterrows():
        txt = r["term"] + " " + r["sample"]
        if r["term"] == "strict_x":
            prev = T.iloc[i - 1]
            assert prev["spec"] == "strict6_mobility", (v, i)
            mob.append("vis" if "vis" in prev["term"] else "tour")
        elif r["term"] == "mob_day":
            mob.append("vis_minus_tour")
        elif "vis" in txt and "tour" not in txt:
            mob.append("vis")
        elif "tour" in txt and "vis" not in txt:
            mob.append("tour")
        else:
            mob.append("vis" if "vis" in r["term"] else "tour" if "tour" in r["term"] else "")
    if "mobility" in T.columns:
        T = T.drop(columns=["mobility"])
    T.insert(T.columns.get_loc("term") + 1, "mobility", mob)
    assert not T.duplicated(["item", "spec", "term", "mobility"]).any(), v
    T.to_csv(p, index=False)
    print("TAB_results mobility column:", v, T.mobility.value_counts().to_dict())

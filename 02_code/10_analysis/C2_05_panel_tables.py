#!/usr/bin/env python3
"""C2_05_panel_tables.py -- rerun C2, revision round 1 items; final data.
No estimation: reads stored outputs of corrected2x and writes three tables to out/corrected2x/tables/.
(2) A2_A2.6_recmedia_exact_N.csv: why N falls by 348 / 820 when the exact recorded-media restriction removes
    277 / 667 rows (A2.csv rows A2.6 recmedia_table4 and recmedia_exact_tableA5: N, N_full, e(num_singletons),
    e(num_separated); A2_A2.6.csv rows rows_v8523_exact_0 and rows_exact_but_dropped_by_refit).
(3) clustering_pvalues.csv: every reported test (Wald tests, lincom differences, Holm-adjusted p) computed with
    both directed-pair and unordered-pair clusters in A1.csv / A2.csv: test id, description, p_directed,
    p_unordered, |delta p|; last row = the maximum.
(4) hs_concordance_print.csv: target HS2007 code -> source codes by HS edition as used (the concordance that
    01a_hs6_products.py reads, COPY 03_intermediate/00_common/01_UN_Comtrade/concordance/
    reported_HS_to_H3_concordance.csv; editions used = reporter-year availability file), with the LB/UB flag
    and membership of the final 30-code basket.
Usage: python3 C2_05_panel_tables.py
"""
import re
import numpy as np
import pandas as pd

import os
W = os.environ.get("PKG_ROOT") or os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))  # package root
O = W + "/05_output/10_analysis/corrected2x"
T = O + "/tables"
COPY = W  # common base built by this package
CT = COPY + "/03_intermediate/00_common/01_UN_Comtrade"

# ---------------------------------------------------------------- (2) exact recorded media N accounting
A2 = pd.read_csv(O + "/results/A2.csv")
A26 = pd.read_csv(T + "/A2_A2.6.csv")
rows = []
for mob in ("visitors", "tourists"):
    t4 = A2[(A2["item"] == "A2.6") & (A2.spec == "recmedia_table4") & (A2.mobility == mob)].iloc[0]
    ex = A2[(A2["item"] == "A2.6") & (A2.spec == "recmedia_exact_tableA5") & (A2.mobility == mob)].iloc[0]
    rem = float(A26[(A26.mobility == mob) & (A26.stat == "rows_v8523_exact_0")].value.iloc[0])
    lost = float(A26[(A26.mobility == mob) & (A26.stat == "rows_exact_but_dropped_by_refit")].value.iloc[0])
    nfull_removed = t4.N_full - ex.N_full
    removed_singletons_before = nfull_removed - rem
    new_singletons = ex.n_singletons - (t4.n_singletons - removed_singletons_before)
    assert t4.N - ex.N == rem + lost, (mob, t4.N - ex.N, rem, lost)
    assert new_singletons == lost and ex.n_separated == 0 and t4.n_separated == 0, mob
    for k, v, note in [
        ("N_recorded_media_all_rows (Table 4 sample)", t4.N, "A2.csv A2.6 recmedia_table4"),
        ("N_full / singletons / separated (Table 4 sample)", f"{int(t4.N_full)} / {int(t4.n_singletons)} / {int(t4.n_separated)}", ""),
        ("N_exact_rows (Table A5 exact sample)", ex.N, "A2.csv A2.6 recmedia_exact_tableA5"),
        ("N_full / singletons / separated (exact sample)", f"{int(ex.N_full)} / {int(ex.n_singletons)} / {int(ex.n_separated)}", ""),
        ("fall in N", t4.N - ex.N, ""),
        ("rows of the Table 4 sample with an ambiguous pool (v_8523_exact==0), removed", rem, "A2_A2.6.csv rows_v8523_exact_0"),
        ("candidate rows removed in total (N_full difference)", nfull_removed, "includes rows that were already singletons"),
        ("removed rows that were already singletons in the Table 4 fit", removed_singletons_before, ""),
        ("exact rows that become singletons after the restriction", new_singletons, "= rows_exact_but_dropped_by_refit; separated rows: 0 in both fits"),
    ]:
        rows.append({"vintage": "corrected2x", "mobility": mob, "item": k, "value": v, "note": note})
pd.DataFrame(rows).to_csv(T + "/A2_A2.6_recmedia_exact_N.csv", index=False)
print("(2) written")

# ---------------------------------------------------------------- (3) clustering p values
out = []
A1 = pd.read_csv(O + "/results/A1.csv")
for _, r in A1.iterrows():
    sp = str(r.spec)
    if "_unordered_pair_id" in sp and (sp.endswith("_test") or sp.endswith("_diff")):
        sd = sp.replace("_unordered_pair_id", "_pair_id")
        rid_d = f"{r['item']}.{sd}.{r.mobility}.{r.term}"
        d = A1[A1.row_id == rid_d]
        if len(d) == 1:
            out.append({"test_id": rid_d.replace("_pair_id", "_{pair_id|unordered_pair_id}"), "source": "A1.csv",
                        "description": f"{r['item']} {sd.replace('_pair_id', '')} {r.mobility} {r.term} ({'Wald test' if sp.endswith('_test') else 'lincom difference'})",
                        "p_directed": float(d.p.iloc[0]), "p_unordered": float(r.p), "row_directed": rid_d, "row_unordered": r.row_id})
A2["_line"] = A2.index + 2
for _, r in A2.iterrows():
    sp = str(r.spec)
    if "unordered_pair_id" not in sp:
        continue
    istest = str(r.note).startswith("Wald test") or " - " in str(r.term) or sp.endswith("_holm") or str(r.term).startswith("holm")
    if not istest:
        continue
    sd = sp.replace("unordered_pair_id", "pair_id")
    d = A2[(A2["item"] == r["item"]) & (A2.spec == sd) & (A2.mobility == r.mobility) & (A2.term == r.term) & (A2["sample"] == r["sample"])]
    if len(d) == 1:
        out.append({"test_id": f"{r['item']}|{sd.replace('pair_id', '{pair_id|unordered_pair_id}')}|{r['sample']}|{r.mobility}|{r.term}", "source": "A2.csv",
                    "description": f"{r['item']} {sd.replace('_pair_id', '')} {r.mobility}, sample {r['sample']}: {r.term}",
                    "p_directed": float(d.p.iloc[0]), "p_unordered": float(r.p),
                    "row_directed": f"A2.csv line {int(d._line.iloc[0])}", "row_unordered": f"A2.csv line {int(r._line)}"})
P = pd.DataFrame(out)
assert not P.test_id.duplicated().any()
P["abs_delta_p"] = (P.p_directed - P.p_unordered).abs()
P = P.sort_values("abs_delta_p", ascending=False).reset_index(drop=True)
i = P.abs_delta_p.idxmax()
mx = P.loc[i]
P = pd.concat([P, pd.DataFrame([{"test_id": "MAXIMUM", "source": "", "description": f"maximum |delta p| over {len(P)} tests: {mx.test_id}",
                                 "p_directed": mx.p_directed, "p_unordered": mx.p_unordered, "abs_delta_p": mx.abs_delta_p,
                                 "row_directed": mx.row_directed, "row_unordered": mx.row_unordered}])], ignore_index=True)
P.insert(0, "vintage", "corrected2x")
P.to_csv(T + "/clustering_pvalues.csv", index=False, float_format="%.6g")
print("(3) tests:", len(P) - 1, "max |dp|", round(mx.abs_delta_p, 6), mx.test_id)

# ---------------------------------------------------------------- (4) HS concordance, printable
m = pd.read_csv(CT + "/concordance/reported_HS_to_H3_concordance.csv", dtype=str, encoding="utf-8-sig")
m["source_code"] = m.source_code.str.zfill(6)
av = pd.read_csv(CT + "/classification_availability/reported_classification_availability_2007_2021.csv", dtype=str)
used = av.classificationCode.value_counts().to_dict()
ED = [("H0", "HS1992"), ("H1", "HS1996"), ("H2", "HS2002"), ("H3", "HS2007"), ("H4", "HS2012"), ("H5", "HS2017"), ("H6", "HS2022")]
ED = [(c, n) for c, n in ED if c in used or c in set(m.source_version)]
safe = m.mapping_status.eq("SAFE_CATEGORY_MAPPING")
assert (m.loc[safe, "canonical_H3_codes_touched"].str.count(";") == 0).all()
cat = {"v_3706": "Cinematographic film (HS 3706)", "v_49": "Publications (HS 49)", "v_8523": "Recorded media (HS 8523)", "v_97": "Artworks and antiques (HS 97)"}
recs = []
for h3, g in m[safe].groupby("canonical_H3_codes_touched"):
    r = {"target_HS2007": h3, "category": cat.get(g.pipeline_treatment.iloc[0], g.pipeline_treatment.iloc[0]),
         "basket": "LB and UB", "in_final_30code_basket": "no (HS 490700 excluded)" if h3 == "490700" else "yes"}
    for c, n in ED:
        r[f"{n} ({c}) source codes"] = "; ".join(sorted(g.loc[g.source_version == c, "source_code"]))
    recs.append(r)
amb = m[~safe]
r = {"target_HS2007": "ambiguous pre-HS2007 recorded-media pool (targets: " + "; ".join(sorted(set(";".join(amb.canonical_H3_codes_touched).split(";")))) + ")",
     "category": cat["v_8523"], "basket": "UB only (ambiguous pool; excluded from LB)", "in_final_30code_basket": "no (UB only)"}
for c, n in ED:
    r[f"{n} ({c}) source codes"] = "; ".join(sorted(amb.loc[amb.source_version == c, "source_code"]))
recs.append(r)
H = pd.DataFrame(recs)
assert len(H) == 32 and (H.basket == "LB and UB").sum() == 31
H.to_csv(T + "/hs_concordance_print.csv", index=False)
note = pd.DataFrame([{"edition": f"{n} ({c})", "reporter_years_2007_2021": int(used.get(c, 0)),
                      "source_codes_in_concordance": int((m.source_version == c).sum())} for c, n in ED])
note.to_csv(T + "/hs_concordance_print_editions.csv", index=False)
print("(4) rows:", len(H), "editions:", note.to_dict("records"))

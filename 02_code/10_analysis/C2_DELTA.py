#!/usr/bin/env python3
"""C2_DELTA.py -- rerun C2 step 4 / addendum 3 (e): result-by-result comparison of the vintages
corrected, corrected2 (31 codes + PAK/BLR-LIE quarantine) and corrected2x (final: 30 codes).

Inputs (read only): out/<v>/results/A1.csv, A2.csv (incl. A2.7b), FIG_new_checks.csv, TAB_results.csv,
figures/Figure_coefplot*_data.csv, tables_revised/RECONCILIATION.csv. Rows are matched by their ids
(A1 row_id; A2 item|spec|sample|mobility|term; FIG check|mobility; TAB item|spec|term|row order).
For each step (corrected -> corrected2, corrected2 -> corrected2x, corrected -> corrected2x) a row is
flagged when |delta b| > 0.005 or p crosses 0.10, 0.05 or 0.01 (p of tests included). Writes
06_results/reconciliation/DELTA_corrected2.csv (every row) and the generated part of 06_results/reconciliation/DELTA_corrected2.md
between the markers <!-- GENERATED START --> and <!-- GENERATED END -->.
"""
import math, os, re
import numpy as np
import pandas as pd

W = os.environ.get("PKG_ROOT") or os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))  # package root
O = W + "/05_output/10_analysis"
REC = W + "/06_results/reconciliation"
os.makedirs(REC, exist_ok=True)
VS = ["corrected", "corrected2", "corrected2x"]
LAB = {"corrected": "corrected", "corrected2": "corrected2", "corrected2x": "final (corrected2x)"}


def load(v):
    parts = []
    a1 = pd.read_csv(f"{O}/{v}/results/A1.csv", dtype={"row_id": str})
    a1["block"] = "A1"; a1["key"] = a1.row_id
    parts.append(a1)
    a2 = pd.read_csv(f"{O}/{v}/results/A2.csv")
    a2["block"] = "A2"
    # terms such as "slope at p50 of cul_dist = 2.324224" carry a sample-specific value: matched without it
    a2["key"] = a2["item"].astype(str) + "|" + a2.spec.astype(str) + "|" + a2["sample"].astype(str) + "|" + a2.mobility.astype(str) + "|" + a2.term.astype(str).str.replace(r" = -?[0-9.]+$", "", regex=True)
    a2["key"] = a2.key + a2.groupby("key").cumcount().map(lambda k: "" if k == 0 else f"#{k+1}")
    parts.append(a2)
    fg = pd.read_csv(f"{O}/{v}/FIG_new_checks.csv")
    fg["block"] = "FIG"; fg["item"] = "FIG"; fg["key"] = "FIG|" + fg.check.astype(str) + "|" + fg.mobility.astype(str)
    fg["spec"] = fg.check; fg["term"] = "mob_bilat_" + fg.mobility.astype(str)
    parts.append(fg)
    tb = pd.read_csv(f"{O}/{v}/TAB_results.csv")
    tb["block"] = "TAB"
    assert "mobility" in tb.columns, "run C2_post.py first (mobility column)"
    tb["key"] = "TAB|" + tb["item"].astype(str) + "|" + tb.spec.astype(str) + "|" + tb.term.astype(str) + "|" + tb.mobility.astype(str)
    parts.append(tb)
    d = pd.concat(parts, ignore_index=True, sort=False)
    keep = ["block", "key", "item", "spec", "mobility", "term", "b", "se", "p", "N", "note"]
    d = d[[c for c in keep if c in d.columns]].copy()
    assert not d.key.duplicated().any(), (v, d.key[d.key.duplicated()].head())
    return d.set_index("key")


def thr(p):
    if p is None or (isinstance(p, float) and math.isnan(p)):
        return None
    return 3 if p < 0.01 else 2 if p < 0.05 else 1 if p < 0.10 else 0


D = {v: load(v) for v in VS}
keys = list(dict.fromkeys(list(D["corrected"].index) + list(D["corrected2"].index) + list(D["corrected2x"].index)))
rows = []
for k in keys:
    base = next(D[v].loc[k] for v in VS if k in D[v].index)
    r = {"key": k, "block": base.block, "item": base.get("item"), "spec": base.get("spec"), "mobility": base.get("mobility"), "term": base.get("term")}
    for v in VS:
        if k in D[v].index:
            x = D[v].loc[k]
            r[f"b_{v}"], r[f"se_{v}"], r[f"p_{v}"], r[f"N_{v}"] = x.b, x.se, x.p, x.N
        else:
            r[f"b_{v}"] = r[f"se_{v}"] = r[f"p_{v}"] = r[f"N_{v}"] = np.nan
    for a, b, tag in (("corrected", "corrected2", "c_c2"), ("corrected2", "corrected2x", "c2_c2x"), ("corrected", "corrected2x", "c_c2x")):
        db = r[f"b_{b}"] - r[f"b_{a}"]
        r[f"db_{tag}"] = db
        ta, tb_ = thr(r[f"p_{a}"]), thr(r[f"p_{b}"])
        cross = (ta is not None and tb_ is not None and ta != tb_)
        r[f"pcross_{tag}"] = (f"{['n.s.','<.10','<.05','<.01'][ta]} -> {['n.s.','<.10','<.05','<.01'][tb_]}" if cross else "")
        istest = isinstance(r["term"], str) and ("test" in str(r["spec"]) or "eq" in str(r["term"]) or "joint" in str(r["term"]))
        r[f"flag_{tag}"] = bool((not pd.isna(db) and abs(db) > 0.005 and not istest) or cross)
        r[f"missing_{tag}"] = bool(pd.isna(r[f"b_{a}"]) != pd.isna(r[f"b_{b}"]))
    rows.append(r)
R = pd.DataFrame(rows)
R.to_csv(REC + "/DELTA_corrected2.csv", index=False, float_format="%.10g")

# headline rows (manuscript Tables 2, 3, 7 and the benchmark contrasts)
HEAD = [
    ("Baseline visitors (Table 2 col 1)", "A1.1.baseline.vis.mob_bilat_vis"),
    ("Baseline tourists (Table 2 col 5)", "A1.1.baseline.tour.mob_bilat_tour"),
    ("Directional rev, visitors (T2 col 4)", "A1.9.dir_full_pair_id.vis.mob_rev_vis"),
    ("Directional same, visitors (T2 col 4)", "A1.9.dir_full_pair_id.vis.mob_same_vis"),
    ("Directional test rev=same, visitors, pair clusters", "A1.9.dir_full_pair_id_test.vis.rev_eq_same"),
    ("Directional test rev=same, visitors, unordered clusters", "A1.9.dir_full_unordered_pair_id_test.vis.rev_eq_same"),
    ("Directional rev, tourists (T2 col 8)", "A1.9.dir_full_pair_id.tour.mob_rev_tour"),
    ("Directional same, tourists (T2 col 8)", "A1.9.dir_full_pair_id.tour.mob_same_tour"),
    ("Directional test rev=same, tourists, pair clusters", "A1.9.dir_full_pair_id_test.tour.rev_eq_same"),
    ("Exact common support visitors", "A1.1.cs_iter2.vis.mob_bilat_vis"),
    ("Exact common support tourists", "A1.1.cs_iter2.tour.mob_bilat_tour"),
    ("Pair linear trends (separation mu), visitors", "A1.6.bilat_pairtrend_sepmu.vis.mob_bilat_vis"),
    ("Pair linear trends (separation mu), tourists", "A1.6.bilat_pairtrend_sepmu.tour.mob_bilat_tour"),
    ("Lead, pair trends (mu), visitors", "A1.8.T7_pair_sepmu.vis.lead_bilat_vis"),
    ("Lead, pair trends (mu), tourists", "A1.8.T7_pair_sepmu.tour.lead_bilat_tour"),
    ("Clean measurement + SWEEP2 flags, visitors", "A1.5.x_clean_sw2.vis.mob_bilat_vis"),
    ("Clean measurement + SWEEP2 flags, tourists", "A1.5.x_clean_sw2.tour.mob_bilat_tour"),
    ("SWEEP2 definitional flags excluded, visitors", "A1.5.x_sw2defn.vis.mob_bilat_vis"),
    ("SWEEP2 definitional flags excluded, tourists", "A1.5.x_sw2defn.tour.mob_bilat_tour"),
    ("Six unexplained lots + NOR->SAU 2019 excluded, visitors", "A1.5.x_sw2lots.vis.mob_bilat_vis"),
    ("Six unexplained lots + NOR->SAU 2019 excluded, tourists", "A1.5.x_sw2lots.tour.mob_bilat_tour"),
    ("2007-2019, visitors", "A1.6.win_2007_2019.vis.mob_bilat_vis"),
    ("2007-2019, tourists", "A1.6.win_2007_2019.tour.mob_bilat_tour"),
]


def a2key(item, spec, mob, term, sample=None):
    m = R[(R.block == "A2") & (R["item"] == item) & (R.spec == spec) & (R.mobility == mob) & (R.term == term)]
    if sample is not None:
        m = m[m.key.str.contains(re.escape(sample))]
    return m.key.iloc[0] if len(m) else None


for mob in ("visitors", "tourists"):
    HEAD.append((f"Benchmark: cultural - CEPII total, {mob} (A2.7)", a2key("A2.7", "tradeflow_comtrade_d_identical_rows", mob, "cultural - benchmark")))
    HEAD.append((f"Benchmark: cultural, identical rows, {mob} (A2.7)", a2key("A2.7", "tradeflow_comtrade_d_identical_rows", mob, "cultural goods")))
    HEAD.append((f"Benchmark: CEPII total imports, identical rows, {mob} (A2.7)", a2key("A2.7", "tradeflow_comtrade_d_identical_rows", mob, "total imports (CEPII Comtrade)")))
    HEAD.append((f"Benchmark test cultural = total, {mob} (A2.7)", a2key("A2.7", "tradeflow_comtrade_d_identical_rows", mob, "test cultural = benchmark")))
    for y in ("unesco_b", "nomedia"):
        yl = "Narrow-B basket" if y == "unesco_b" else "no recorded media"
        HEAD.append((f"A2.7b {y}: outcome, identical rows, {mob}", a2key("A2.7b", f"A2.7b_{y}_tradeflow_comtrade_d_identical_rows", mob, yl)))
        HEAD.append((f"A2.7b {y}: outcome - CEPII total, {mob}", a2key("A2.7b", f"A2.7b_{y}_tradeflow_comtrade_d_identical_rows", mob, yl + " - benchmark")))
        HEAD.append((f"A2.7b {y}: test outcome = total, {mob}", a2key("A2.7b", f"A2.7b_{y}_tradeflow_comtrade_d_identical_rows", mob, f"test {y} = benchmark")))
    for b in ("v_unesco_a", "v_unesco_b", "v_nomedia"):
        HEAD.append((f"Basket {b} on baseline sample, {mob} (A2.6)", a2key("A2.6", f"{b}_on_baseline_sample", mob, b)))
    HEAD.append((f"Exporter-reported trade, {mob} (A2.3 T4)", a2key("A2.3", "T4_reporting_pair_id", mob, "exporter")))
    HEAD.append((f"Importer - exporter, {mob} (A2.3 T4)", a2key("A2.3", "T4_reporting_pair_id", mob, "importer - exporter")))


def f(x, d=4):
    return "" if pd.isna(x) else (f"{x:.{d}f}" if abs(x) < 1e5 else f"{x:.4g}")


def fN(x):
    return "" if pd.isna(x) else f"{int(x):,}"


def tab(df, steps, title, cols_v=VS):
    out = [f"| row | " + " | ".join(f"{LAB[v]} b (SE), p, N" for v in cols_v) + " | " + " | ".join(f"delta b {s}" for s in steps) + " | p crossing |",
           "|---|" + "---|" * (len(cols_v) + len(steps) + 1)]
    for _, r in df.iterrows():
        cells = []
        for v in cols_v:
            cells.append("" if pd.isna(r[f"b_{v}"]) else f"{f(r[f'b_{v}'])} ({f(r[f'se_{v}'])}), p {f(r[f'p_{v}'], 3)}, N {fN(r[f'N_{v}'])}")
        ds = [f(r[f"db_{s}"]) for s in steps]
        pcs = "; ".join(x for x in (r[f"pcross_{s}"] for s in steps) if isinstance(x, str) and x)
        out.append(f"| {r['_label']} | " + " | ".join(cells) + " | " + " | ".join(ds) + f" | {pcs} |")
    return "\n".join(out)


md = []
H = []
for lab, k in HEAD:
    if k is None or k not in set(R.key):
        H.append({"_label": lab + " (row not found)", **{c: np.nan for c in R.columns if c not in ("key",)}})
        continue
    x = R[R.key == k].iloc[0].to_dict(); x["_label"] = f"{lab} [`{k}`]"; H.append(x)
HD = pd.DataFrame(H)
for c in R.columns:
    if c not in HD.columns:
        HD[c] = np.nan
md.append("## G1. corrected -> final (corrected2x): every headline row\n")
md.append(tab(HD, ["c_c2", "c2_c2x", "c_c2x"], "headline"))
for tag, title in (("c_c2", "corrected -> corrected2 (PAK and BLR-LIE quarantine; 31 codes)"),
                   ("c2_c2x", "corrected2 -> corrected2x (31 -> 30 codes, HS 490700 removed)"),
                   ("c_c2x", "corrected -> final (corrected2x), all flagged rows")):
    F = R[R[f"flag_{tag}"]].copy()
    F["_label"] = F.key.map(lambda s: f"`{s}`")
    a, b = {"c_c2": ("corrected", "corrected2"), "c2_c2x": ("corrected2", "corrected2x"), "c_c2x": ("corrected", "corrected2x")}[tag]
    md.append(f"\n## G-{tag}. {title}: rows with |delta b| > 0.005 (estimates, not test statistics) or a p crossing 0.10/0.05/0.01 ({len(F)} of {int((~R[f'b_{a}'].isna() & ~R[f'b_{b}'].isna()).sum())} rows present in both)\n")
    md.append(tab(F, [tag], title, cols_v=[a, b]))
    M = R[R[f"missing_{tag}"]]
    if len(M):
        md.append(f"\nRows estimated in only one of the two vintages ({len(M)}): " + "; ".join(f"`{k}`" for k in M.key))
md.append("\n## G-all. Every result row (A1, A2, FIG, TAB): values in all three vintages and the differences\n")
for blk in ("A1", "A2", "FIG", "TAB"):
    B = R[R.block == blk].copy()
    B["_label"] = B.key.map(lambda s: f"`{s}`")
    md.append(f"\n### {blk} ({len(B)} rows)\n")
    md.append(tab(B, ["c_c2", "c2_c2x"], blk))
txt = "\n".join(md)
p = REC + "/DELTA_corrected2.md"
S, E = "<!-- GENERATED START -->", "<!-- GENERATED END -->"
old = open(p, encoding="utf-8").read() if os.path.exists(p) else f"{S}\n{E}\n"
if S not in old:
    old += f"\n{S}\n{E}\n"
new = old[: old.index(S) + len(S)] + "\n" + txt + "\n" + old[old.index(E):]
open(p, "w", encoding="utf-8").write(new)
for tag in ("c_c2", "c2_c2x", "c_c2x"):
    print(tag, "flagged", int(R[f"flag_{tag}"].sum()), "of", len(R))

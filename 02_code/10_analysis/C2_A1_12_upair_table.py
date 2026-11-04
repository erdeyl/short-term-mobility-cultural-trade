"""C2_A1_12_upair_table.py -- pair directed-pair and unordered-pair results of the stacked-test producers.

Usage:  python3 C2_A1_12_upair_table.py <core OUT folder> <upair OUT folder>
        (W: analysis/out/corrected2x  analysis/out/corrected2x_upair)

Reads results/{A2_5,A2_6,A2_7,A2_7b,A2_7c}.csv and results/A1_parts/{A1_02,A1_08,A1_09}.csv from both folders
(the upair folder is written by the UP_*.do copies of C2_A1_12_make_upair.py). Keeps the rows that carry a
cross-model or within-model test: Wald tests, differences, and moderator interaction terms. For every kept row
it asserts that the directed row exists, that both rows have the same N, that the directed row is clustered on
pair_id and the unordered row on unordered_pair_id, and that the estimate is identical (a difference or an
interaction coefficient does not depend on the cluster variable; tolerance 1e-9 relative). A test row stores
chi2 in b and df in se; the df must be identical. A full-packet guard first applies the same checks (plus N_full,
singleton and separation counts) to every posted row of each file, including slopes and lincom rows that the
table does not list. Equal counts and identical code and inputs are the evidence of identical supports; the
observation masks themselves are not compared. N is the number of observations of the comparison (n_obs);
N_posted is the N column of the source row as posted (A2: unique pair-years; A1: stacked e(N)).
Writes <core OUT>/tables/clustering_pvalues_extra.csv (one row per test) and prints a summary.
Exit 1 on any failed assertion.
"""
import sys
from pathlib import Path
import pandas as pd

A2 = ["A2_5", "A2_6", "A2_7", "A2_7b", "A2_7c"]
A1 = ["A1_02", "A1_08", "A1_09"]
KEY2 = ["item", "spec", "sample", "mobility", "term"]


def kind_a2(term):
    t = str(term)
    if t.startswith("test ") or t.startswith("joint"):
        return "test"
    if " - " in t:
        return "diff"
    if t.startswith("mobility x "):
        return "interaction"
    return None


def kind_a1(spec):
    s = str(spec)
    return "test" if s.endswith("_test") else "diff" if s.endswith("_diff") else None


def close(a, b):
    if pd.isna(a) and pd.isna(b):
        return True
    return abs(a - b) <= 1e-9 * max(1.0, abs(a), abs(b))


MOB = {"visitors": "visitors", "tourists": "tourists", "both": "visitors and tourists", "vis": "visitors", "tour": "tourists"}
MOD = {"cd": "cultural distance", "cdnp": "cultural distance, pairs without regional proxy scores",
       "cdoff": "cultural distance from the official Hofstede file only", "col": "common official language",
       "eth": "common ethnic language (CEPII)", "cnl": "common native language (Melitz–Toubal)",
       "csl": "common spoken language (Melitz–Toubal)"}
BSK = {"unesco_a": "Narrow-A", "unesco_b": "Narrow-B", "nomedia": "the basket without heading 8523"}
RESTR = {"r1": "same basis in both directions", "r2all": "one basis for the pair in all observed years",
         "r3": "no tourists-only values in the visitor series", "r4": "no basis switch in either series"}


def describe(r):
    """Readable test label for Supplementary Table S5.2 (no internal ids)."""
    src, spec, term, mob = r.source, str(r.spec), str(r.term), MOB.get(str(r.mobility), str(r.mobility))
    kind = " (Wald test)" if r.kind == "test" else ""
    bm = "non-cultural imports" if "v_noncult_k" in spec else "total merchandise imports"
    if src == "A2_7":
        return f"Table 7, Panel A, {mob}: reference basket minus {bm}{kind}"
    if src in ("A2_7b", "A2_7c"):
        b = next(v for k, v in BSK.items() if f"_{k}_" in spec)
        return f"Table 7, Panel A, {mob}: {b} minus {bm}{kind}"
    if src == "A2_6":
        b = next(v for k, v in BSK.items() if spec.startswith(f"v_{k}_") or spec.startswith(f"{k}_"))
        return f"Table 7, Panel B, {mob}: reference basket minus {b}, identical observations{kind}"
    if src == "A1_02":
        return f"Table 8, Panel A, {mob}: restricted minus complement, {RESTR[spec.split('_')[0]]}{kind}"
    if src == "A1_08":
        return f"Table S3.3, Panel A, {mob}: residence-based minus nationality-based slope, identical observations{kind}"
    if src == "A1_09":
        where = "pair-years with the same basis under both rules" if "_r1_" in spec else "identical observations"
        return f"Table S3.3, Panel A, {mob}: baseline rule minus nationality-first rule, {where}{kind}"
    if src == "A2_5":
        m, scope = spec.split("_")[0], spec.split("_")[1]
        lab = MOD[m]
        if spec.endswith("_stack"):
            t = (term.replace("interaction: visitors - tourists", "difference of interactions, visitors minus tourists")
                 .replace("test (i) equal interaction coefficients", "Wald test (i), equal interactions")
                 .replace("slope at common mean: visitors - tourists", "difference of slopes at the common mean, visitors minus tourists")
                 .replace("test (ii) equal slopes at the common mean", "Wald test (ii), equal slopes at the common mean")
                 .replace("test (i)+(ii) jointly", "Wald test (i) and (ii) jointly"))
            for v, w in (("0", "without"), ("1", "with")):
                for c in ("comlang_off", "comlang_ethno"):
                    t = t.replace(f"slope at {c} = {v}: visitors - tourists", f"difference of slopes {w} a common language, visitors minus tourists")
            return f"Table 6, Panel B, {lab}, common sample: {t}"
        t = "joint test that mobility and interaction coefficients are zero" if term.startswith("joint") else "mobility × moderator interaction"
        return f"Table 6, Panel {'A' if scope == 'own' else 'B'}, {lab}, {mob}, {'own' if scope == 'own' else 'common'} sample: {t}"
    return f"{src} {spec} {mob} {term}"


def num(x, se=False):
    """Display rounding (ROUND_HALF_UP, U+2212 minus): three decimals at |x| >= 0.01, four below; below 0.00005 an SE
    prints '< 0.0001' and an estimate '0.0000' (fill_keys.py refuses cells with five or more decimals)."""
    from decimal import Decimal, ROUND_HALF_UP
    d = Decimal(repr(float(x)))
    if abs(d) >= Decimal("0.01"):
        s = str(d.quantize(Decimal("0.001"), rounding=ROUND_HALF_UP))
    elif abs(d) >= Decimal("0.00005"):
        s = str(d.quantize(Decimal("0.0001"), rounding=ROUND_HALF_UP))
    else:
        return "< 0.0001" if se else "0.0000"
    return s.replace("-", "−")


def n_obs(stem, n):
    """Observations of a comparison. A1_stack posts the stacked e(N); for the identical-observation designs of A1_08 and
    A1_09 both blocks hold the same rows, so the comparison has e(N)/2 observations (asserted even). A1_02 compares
    disjoint parts, and the A2 programs already post unique pair-years."""
    n = int(n)
    if stem in ("A1_08", "A1_09"):
        assert n % 2 == 0, (stem, n)
        return n // 2
    return n


def holm(p):
    """Holm step-down adjustment; port of a2_holm_m() in A2_00_programs.do (order, min(1,(m-i+1)p), running max)."""
    m = len(p)
    o = sorted(range(m), key=lambda i: p[i])
    adj = [min(1.0, (m - k) * p[o[k]]) for k in range(m)]
    for k in range(1, m):
        adj[k] = max(adj[k], adj[k - 1])
    out = [0.0] * m
    for k, i in enumerate(o):
        out[i] = adj[k]
    return out


def holm_control(core):
    """Positive control: reproduce the Holm p values that A2_3.do posts for the six category differences."""
    d = pd.read_csv(core / "results" / "A2_3.csv")
    n = 0
    for cl in ("pair_id", "unordered_pair_id"):
        for mob in ("visitors", "tourists"):
            raw = d[(d.spec == f"T2_sepsupport_{cl}") & (d.mobility == mob) & d.term.str.contains(" - ", regex=False)]
            ref = d[(d.spec == f"T2_sepsupport_{cl}_holm") & (d.mobility == mob)]
            if len(raw) != 6 or len(ref) != 6:
                raise SystemExit(f"Holm control: expected 6 rows, got {len(raw)} / {len(ref)} ({cl}, {mob})")
            h = dict(zip(raw.term, holm(list(raw.p))))
            for _, r in ref.iterrows():
                t = r.term.replace("holm: ", "")
                if abs(h[t] - r.p) > 1e-12:
                    raise SystemExit(f"Holm control FAIL {cl} {mob} {t}: {h[t]} vs {r.p}")
                n += 1
    return n


BASKETS = [  # (source, spec template, term, basket label); bm = tradeflow_comtrade_d | v_noncult_k
    ("A2_7", "{bm}_identical_rows", "cultural - benchmark", "reference basket"),
    ("A2_7b", "A2.7b_unesco_b_{bm}_identical_rows", "Narrow-B basket - benchmark", "Narrow-B"),
    ("A2_7b", "A2.7b_nomedia_{bm}_identical_rows", "no recorded media - benchmark", "without heading 8523"),
    ("A2_7c", "A2.7c_unesco_a_{bm}_identical_rows", "Narrow-A basket - benchmark", "Narrow-A"),
]


def basket_family(out):
    """Holm within the family of the four basket-minus-benchmark differences, per measure, benchmark, clustering."""
    rows = []
    for mob in ("visitors", "tourists"):
        for bm in ("tradeflow_comtrade_d", "v_noncult_k"):
            fam = []
            for src, spec, term, lab in BASKETS:
                r = out[(out.source == src) & (out.spec == spec.format(bm=bm)) & (out.mobility == mob) & (out.term == term)]
                if len(r) != 1:
                    raise SystemExit(f"basket family: {len(r)} rows for {src} {spec.format(bm=bm)} {mob}")
                fam.append((lab, r.iloc[0]))
            hd = holm([r.p_directed for _, r in fam])
            hu = holm([r.p_unordered for _, r in fam])
            for (lab, r), a, b in zip(fam, hd, hu):
                rows.append({"mobility": mob, "benchmark": bm, "basket": lab, "N": r.N, "b": r.b,
                             "se_directed": r.se_directed, "p_directed": r.p_directed, "holm_directed": a,
                             "se_unordered": r.se_unordered, "p_unordered": r.p_unordered, "holm_unordered": b})
    out_f = pd.DataFrame(rows)
    # sensitivity (audit check): one family of eight differences per measure and clustering, pooling both benchmarks
    for mob in ("visitors", "tourists"):
        m = out_f.mobility == mob
        out_f.loc[m, "holm8_directed"] = holm(list(out_f.loc[m, "p_directed"]))
        out_f.loc[m, "holm8_unordered"] = holm(list(out_f.loc[m, "p_unordered"]))
    return out_f


def main():
    core, up = Path(sys.argv[1]), Path(sys.argv[2])
    print(f"Holm positive control: {holm_control(core)} of 24 Holm p values reproduced (A2_3, six category differences)")
    rows, bad, nfull = [], [], {}
    for stem in A2 + A1:
        sub = "results" if stem in A2 else "results/A1_parts"
        d = pd.read_csv(core / sub / f"{stem}.csv")
        u = pd.read_csv(up / sub / f"{stem}.csv")
        if stem in A2:
            d["kind"] = d.term.map(kind_a2)
            u["kind"] = u.term.map(kind_a2)
            key = KEY2
        else:
            d["kind"] = d.spec.map(kind_a1)
            u["kind"] = u.spec.map(kind_a1)
            key = ["row_id"]
        for c in key:
            d[c] = d[c].fillna("")
            u[c] = u[c].fillna("")
        # full-packet guard (audit check): every posted row, not only the tests kept below, must exist under both
        # clusterings with the same N, N_full, singleton and separation counts and the same estimate (Wald rows: same df)
        full = u.merge(d, on=key, how="outer", suffixes=("_up", "_dir"), indicator=True)
        if (full["_merge"] != "both").any():
            bad.append(f"{stem}: {(full['_merge'] != 'both').sum()} rows present under one clustering only")
        for _, r in full[full["_merge"] == "both"].iterrows():
            tag = f"{stem} full {' | '.join(str(r[c]) for c in key)}"
            for c in ("N", "N_full", "n_singletons", "n_separated"):
                if not close(r[f"{c}_up"], r[f"{c}_dir"]):
                    bad.append(f"{tag}: {c} {r[f'{c}_dir']} vs {r[f'{c}_up']}")
            is_test = (r.kind_up == "test") if stem in A1 else str(r[key[-1]]).startswith(("test ", "joint"))
            if is_test and not close(r.se_up, r.se_dir):
                bad.append(f"{tag}: df {r.se_dir} vs {r.se_up}")
            if not is_test and not close(r.b_up, r.b_dir):
                bad.append(f"{tag}: b {r.b_dir!r} vs {r.b_up!r}")
            if not (pd.isna(r.p_up) and pd.isna(r.p_dir)) and (r.cluster_var_dir != "pair_id" or r.cluster_var_up != "unordered_pair_id"):
                bad.append(f"{tag}: cluster vars {r.cluster_var_dir} / {r.cluster_var_up}")
            nfull[stem] = nfull.get(stem, 0) + 1
        u = u[u.kind.notna()]
        if d.duplicated(subset=key).any() or u.duplicated(subset=key).any():
            bad.append(f"{stem}: duplicate keys")
            continue
        m = u.merge(d, on=key, how="left", suffixes=("_up", "_dir"), indicator=True)
        for _, r in m.iterrows():
            tag = f"{stem} {' | '.join(str(r[c]) for c in key)}"
            if r["_merge"] != "both":
                bad.append(f"{tag}: no directed row")
                continue
            if pd.isna(r.p_up) and pd.isna(r.p_dir):
                continue  # not identified under either clustering (e.g. the tourist overlap slope)
            if r.N_up != r.N_dir:
                bad.append(f"{tag}: N {r.N_dir} vs {r.N_up}")
            if r.cluster_var_dir != "pair_id" or r.cluster_var_up != "unordered_pair_id":
                bad.append(f"{tag}: cluster vars {r.cluster_var_dir} / {r.cluster_var_up}")
            if r.kind_up in ("diff", "interaction") and not close(r.b_dir, r.b_up):
                bad.append(f"{tag}: b {r.b_dir!r} vs {r.b_up!r}")
            if r.kind_up == "test" and not close(r.se_dir, r.se_up):
                bad.append(f"{tag}: df {r.se_dir} vs {r.se_up}")
            rows.append({
                "source": stem, "item": r.get("item_dir", r.get("item", "")), "spec": r.get("spec_dir", r.get("spec", "")),
                "sample": r.get("sample_dir", r.get("sample", "")), "mobility": r.get("mobility_dir", r.get("mobility", "")),
                "term": r.get("term_dir", r.get("term", "")), "row_id": r.get("row_id", ""), "kind": r.kind_up,
                "N": n_obs(stem, r.N_dir), "N_posted": int(r.N_dir), "b": r.b_dir, "se_directed": r.se_dir if r.kind_up != "test" else float("nan"),
                "se_unordered": r.se_up if r.kind_up != "test" else float("nan"),
                "stat_directed": r.b_dir if r.kind_up == "test" else float("nan"),
                "stat_unordered": r.b_up if r.kind_up == "test" else float("nan"),
                "df": r.se_dir if r.kind_up == "test" else float("nan"),
                "p_directed": r.p_dir, "p_unordered": r.p_up, "abs_dp": abs(r.p_dir - r.p_up),
                "n_clusters_directed": r.n_clusters_dir, "n_clusters_unordered": r.n_clusters_up})
    if bad:
        print("FAIL")
        for b in bad:
            print("  " + b)
        sys.exit(1)
    out = pd.DataFrame(rows)
    # not reported anywhere: the superseded restriction r2 (replaced by r2all, A1_02_measurement.do:315-329) and the
    # moderator rows centred at the realized-sample mean, whose tests repeat the "_orig" rows exactly
    out = out[~out.spec.isin(["r2_test", "r2_diff"]) & ~out.spec.str.endswith("_real")].reset_index(drop=True)
    out.insert(0, "description", [describe(r) for _, r in out.iterrows()])
    (core / "tables").mkdir(exist_ok=True)
    out.to_csv(core / "tables" / "clustering_pvalues_extra.csv", index=False)
    fam = basket_family(out)
    fam.to_csv(core / "tables" / "benchmark_basket_family.csv", index=False)
    # display tables for Supplementary Tables S5.2 and S5.3 (readable labels, no internal ids). Estimates and SEs are
    # rounded here (three decimals, or three significant digits below 0.001, U+2212 minus); p values stay numeric.
    disp = pd.DataFrame({
        "Test": out.description, "N": out.N,
        "Estimate": [num(b) if k != "test" else "–" for b, k in zip(out.b, out.kind)],
        "SE, directed-pair clusters": [num(s, True) if k != "test" else "–" for s, k in zip(out.se_directed, out.kind)],
        "SE, unordered-pair clusters": [num(s, True) if k != "test" else "–" for s, k in zip(out.se_unordered, out.kind)],
        "p, directed-pair clusters": out.p_directed, "p, unordered-pair clusters": out.p_unordered})
    disp.to_csv(core / "tables" / "S5_2_unordered_pair_tests.csv", index=False)
    bml = {"tradeflow_comtrade_d": "total merchandise imports", "v_noncult_k": "non-cultural imports"}
    pd.DataFrame({
        "Mobility": fam.mobility, "Benchmark": fam.benchmark.map(bml), "Basket": fam.basket, "N": fam.N,
        "Difference": fam.b.map(num), "SE, directed": fam.se_directed.map(lambda v: num(v, True)), "p, directed": fam.p_directed,
        "Holm p, directed": fam.holm_directed, "SE, unordered": fam.se_unordered.map(lambda v: num(v, True)), "p, unordered": fam.p_unordered,
        "Holm p, unordered": fam.holm_unordered,
    }).to_csv(core / "tables" / "S5_3_benchmark_family.csv", index=False)
    print(fam.to_string(max_colwidth=22))
    cross = out[((out.p_directed < 0.05) != (out.p_unordered < 0.05)) | ((out.p_directed < 0.10) != (out.p_unordered < 0.10))]
    pd.DataFrame([
        {"stat": "rows", "value": len(out)},
        {"stat": "rows_tests", "value": int((out.kind == "test").sum())},
        {"stat": "rows_differences", "value": int((out.kind == "diff").sum())},
        {"stat": "rows_interactions", "value": int((out.kind == "interaction").sum())},
        {"stat": "max_abs_dp", "value": out.abs_dp.max()},
        {"stat": "rows_crossing_05", "value": int(((out.p_directed < 0.05) != (out.p_unordered < 0.05)).sum())},
        {"stat": "rows_crossing_10", "value": int(((out.p_directed < 0.10) != (out.p_unordered < 0.10)).sum())},
    ]).to_csv(core / "tables" / "clustering_pvalues_extra_summary.csv", index=False)
    print(f"full-packet guard: {sum(nfull.values())} posted rows checked under both clusterings {nfull}")
    print(f"PASS rows={len(out)} by source: {out.source.value_counts().to_dict()}")
    print(f"max |dp| = {out.abs_dp.max():.4f}; rows crossing 0.05 or 0.10: {len(cross)}")
    print(cross[["source", "spec", "mobility", "term", "row_id", "p_directed", "p_unordered"]].to_string(max_colwidth=50))


if __name__ == "__main__":
    main()

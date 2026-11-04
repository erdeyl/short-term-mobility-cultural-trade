#!/usr/bin/env python3
"""C2_A1_11_check.py -- controls for C2_A1_11_leadpower_mu.do (rerun C2, revision round 2 item 3.3).
(1) the mu dynamic fit of the new rows reproduces results/A1.csv rows A1.8.T7_pair_sepmu (lead b/se, current b, N);
(2) the default-separation rows recomputed by the do-file reproduce every trend = pair row of
    tables/A1_A1.7_lead_power.csv, and their static reference reproduces A1.7.static_on_dyn_pairtrend (b, N);
(3) power and interval ratios of the new rows recomputed here from b_lead, se_lead, b_ref with the formula of
    A1_03_time.do:221-224 (normal power, z = invnormal(1 - alpha/2), 90% interval / reference).
Writes tables/A1_A1.7_lead_power_mu_controls.csv; exit 1 on any FAIL. Read-only otherwise."""
import csv, math, sys
from statistics import NormalDist
import os
W = os.environ.get("PKG_ROOT") or os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))  # package root
O = f"{W}/05_output/10_analysis/corrected2x"
rd = lambda p: list(csv.DictReader(open(p, encoding="utf-8", newline="")))
a1 = {r["row_id"]: r for r in rd(f"{O}/results/A1.csv")}
new = rd(f"{O}/tables/A1_A1.7_lead_power_mu.csv")
chk = rd(f"{O}/tables/A1_A1.7_lead_power_mu_check.csv")
old = [r for r in rd(f"{O}/tables/A1_A1.7_lead_power.csv") if r["trend"] == "pair"]
N = NormalDist()
out, bad = [], 0
def ctl(item, val, ref, tol=1e-9):
    global bad
    d = abs(float(val) - float(ref))
    ok = d <= tol * max(1.0, abs(float(ref)))
    bad += not ok
    out.append({"control": item, "value": repr(float(val)), "reference": repr(float(ref)), "abs_diff": repr(d), "result": "PASS" if ok else "FAIL"})
assert len(new) == 16 and len(chk) == 16 and len(old) == 16, (len(new), len(chk), len(old))
for m in ("vis", "tour"):
    rows = [r for r in new if r["mobility"] == m]
    for r in rows:
        ctl(f"(1) {r['row_id']} b_lead = A1.8.T7_pair_sepmu.{m}.lead_bilat_{m}.b", r["b_lead"], a1[f"A1.8.T7_pair_sepmu.{m}.lead_bilat_{m}"]["b"])
        ctl(f"(1) {r['row_id']} se_lead = A1.8.T7_pair_sepmu.{m}.lead_bilat_{m}.se", r["se_lead"], a1[f"A1.8.T7_pair_sepmu.{m}.lead_bilat_{m}"]["se"])
        ctl(f"(1) {r['row_id']} N = A1.8.T7_pair_sepmu.{m}.lead_bilat_{m}.N", r["N"], a1[f"A1.8.T7_pair_sepmu.{m}.lead_bilat_{m}"]["N"], 0)
        if r["reference"] == "current_in_T3":
            ctl(f"(1) {r['row_id']} b_ref = A1.8.T7_pair_sepmu.{m}.mob_bilat_{m}.b", r["b_ref"], a1[f"A1.8.T7_pair_sepmu.{m}.mob_bilat_{m}"]["b"])
        # (3) formula
        z = N.inv_cdf(1 - float(r["alpha"]) / 2)
        d = abs(float(r["d_share"]) * float(r["b_ref"]))
        se = float(r["se_lead"])
        pw = N.cdf(d / se - z) + N.cdf(-d / se - z)
        lo = float(r["b_lead"]) - N.inv_cdf(0.95) * se
        hi = float(r["b_lead"]) + N.inv_cdf(0.95) * se
        ctl(f"(3) {r['row_id']} power", r["power"], pw, 1e-9)
        ctl(f"(3) {r['row_id']} ci90_lo_share", r["ci90_lo_share"], lo / float(r["b_ref"]), 1e-9)
        ctl(f"(3) {r['row_id']} ci90_hi_share", r["ci90_hi_share"], hi / float(r["b_ref"]), 1e-9)
# (2) default rows reproduce the existing pair rows, in order
key = lambda r: (r["mobility"], r["reference"], float(r["d_share"]), float(r["alpha"]))
om = {key(r): r for r in old}
for r in chk:
    o = om[key(r)]
    for c in ("b_lead", "se_lead", "b_ref", "d", "z", "power", "ci90_lo", "ci90_hi", "ci90_lo_share", "ci90_hi_share", "N"):
        ctl(f"(2) default {r['mobility']} {r['reference']} d{r['d_share']} a{r['alpha']} {c} = A1_A1.7_lead_power.csv pair row", r[c], o[c], 0 if c == "N" else 1e-9)
    if r["reference"] == "static_same_sample":
        s = a1[f"A1.7.static_on_dyn_pairtrend.{r['mobility']}.mob_bilat_{r['mobility']}"]
        ctl(f"(2) default {r['mobility']} static reference b = A1.7.static_on_dyn_pairtrend.b", r["b_ref"], s["b"])
        ctl(f"(2) default {r['mobility']} static reference N_ref = A1.7.static_on_dyn_pairtrend.N", r["N_ref"], s["N"], 0)
p = f"{O}/tables/A1_A1.7_lead_power_mu_controls.csv"
with open(p, "w", encoding="utf-8", newline="") as fh:
    w = csv.DictWriter(fh, fieldnames=list(out[0]))
    w.writeheader(); w.writerows(out)
print(f"controls {len(out)}, FAIL {bad} -> {p}")
sys.exit(1 if bad else 0)

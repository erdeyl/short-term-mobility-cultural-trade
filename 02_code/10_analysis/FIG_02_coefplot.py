#!/usr/bin/env python3
"""FIG_02_coefplot.py -- assemble the coefficient-plot data (R2.14) from stored corrected-vintage
estimates and draw Figure_coefplot.{pdf,png,tif}.  Reads only; writes only 06_results/figures/.
Every b and se is the stored value; CI = b +/- 1.959964*se unless the source stores the interval
(then the stored interval is used and checked against b +/- 1.959964*se)."""
import os, sys, csv, re
import numpy as np, pandas as pd
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.lines import Line2D

W = os.environ.get("PKG_ROOT") or os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))  # package root
# rerun C2: usage  python3 FIG_02_coefplot.py [vintage] [file suffix]   (default: corrected, no suffix)
# corrected2x = revised baseline (main figure, no suffix); corrected2 -> suffix _31codes; corrected -> _corrected.
V = sys.argv[1] if len(sys.argv) > 1 else "corrected"
SUF = sys.argv[2] if len(sys.argv) > 2 else ""
assert V in ("corrected", "corrected2", "corrected2x"), V
C = W + "/05_output/10_analysis/" + V
# input-safety switch (2026-11-03 ~23:55): COPY 05_output/03_Mobility is read from the unchanged snapshot
COPY = W + "/05_output/03_Mobility"
OUTD = W + "/06_results/figures"
Z = 1.959964

A1 = pd.read_csv(C + "/results/A1.csv").set_index("row_id")
A2 = pd.read_csv(C + "/results/A2.csv")
NEW = pd.read_csv(C + "/FIG_new_checks.csv")
PC = pd.read_stata(C + "/pc/rep_full_core.dta").set_index("id")["value"]
PCCS = pd.read_stata(C + "/pc/rep_full_cs.dta").set_index("id")["value"]
if V == "corrected":
    WZ = pd.read_csv(COPY + "/01_diagnostics/sensitivity/03_ppml_bias_correction/ppml_bias_correction_results.csv").set_index("measure")
    WZ_SRC = "COPY (pre-C14 snapshot) 05_output/03_Mobility/01_diagnostics/sensitivity/03_ppml_bias_correction/ppml_bias_correction_results.csv"
    UB = pd.read_csv(COPY + "/01_diagnostics/core/UB/baseline-key-results.csv", skipinitialspace=True)
    UB = {r.result: float(r.value) for r in UB.itertuples()}
    UB_SRC = "COPY (pre-C14 snapshot) 05_output/03_Mobility/01_diagnostics/core/UB/baseline-key-results.csv rows %s_b/%s_se/%s_n (stored full-precision; CI computed)"
else:
    # new estimates: original 03_ppml_bias_correction.do run on this vintage (C2_02_bias.do) and the
    # TAB_02.do upper-bound fits (log lines "TAB_UB <m> b= se= N=")
    WZ = pd.read_csv(C + "/C2_bias_results.csv").set_index("measure")
    WZ_SRC = f"analysis/out/{V}/C2_bias_results.csv (original 03_ppml_bias_correction.do run by C2_02_bias.do)"
    UB = {}
    for line in open(C + f"/TAB_02_{V}.log", encoding="utf-8", errors="replace"):
        m = re.match(r"^TAB_UB (vis|tour) b=\s*(\S+) se=\s*(\S+) N=(\d+)", line)
        if m:
            k = "visitor" if m.group(1) == "vis" else "tourist"
            UB[k + "_b"], UB[k + "_se"], UB[k + "_n"] = float(m.group(2)), float(m.group(3)), float(m.group(4))
    assert len(UB) == 6, UB
    UB_SRC = f"analysis/out/{V}/TAB_02_{V}.log lines TAB_UB (%s_b/%s_se/%s_n; 9 decimals; CI computed)"

rows = []
def add(group, label, mob, b, se, N, source, lo=None, hi=None):
    if lo is None:
        lo, hi = b - Z * se, b + Z * se
    else:
        assert abs(lo - (b - Z * se)) < 2e-5 and abs(hi - (b + Z * se)) < 2e-5, (label, lo, hi)
    rows.append(dict(group=group, label=label, mobility=mob, b=b, se=se, ci_lo=lo, ci_hi=hi, N=int(N), source=source))

def a1(group, label, spec_item, mob):
    rid = spec_item.format(m="vis" if mob == "visitors" else "tour")
    r = A1.loc[rid]
    add(group, label, mob, r.b, r.se, r.N, f"analysis/out/{V}/results/A1.csv row_id=" + rid, r.ci_lo, r.ci_hi)

def a2(group, label, item, spec, term, mob, fname="A2.csv", sample=None):
    d = A2[(A2["item"] == item) & (A2["spec"] == spec) & (A2["term"] == term) & (A2["mobility"] == mob)]
    if sample: d = d[d["sample"] == sample]
    assert len(d) == 1, (item, spec, term, mob, len(d))
    r = d.iloc[0]
    add(group, label, mob, r.b, r.se, r.N, f"analysis/out/{V}/results/A2.csv key=%s|%s|%s|%s" % (item, spec, mob, term), r.ci_lo, r.ci_hi)

def pc(group, label, mob, cid, tag, src):
    m = "Bilateral visitors" if mob == "visitors" else "Bilateral tourists"
    add(group, label, mob, PC["%s.%s.b" % (cid, m)], PC["%s.%s.se" % (cid, m)], PC["%s.N.N" % cid],
        f"analysis/out/{V}/pc/rep_full_core.dta ids %s.* (%s)" % (cid, src))

G1, G2, G3, G4, G5, G6 = ("Inference", "Sample and influence", "Time", "Mobility measurement",
                          "Trade measurement and basket", "Specification")
for mob in ("visitors", "tourists"):
    s = "vis" if mob == "visitors" else "tour"
    c = 1 if mob == "visitors" else 2   # Table 6 column pair index offset
    off = 0 if mob == "visitors" else 1
    # ---------------- Inference
    a1(G1, "Baseline (directed-pair clusters)", "A1.1.baseline.{m}.mob_bilat_" + s, mob)
    n = NEW[(NEW.check == "unordered_pair_clusters") & (NEW.mobility == s)].iloc[0]
    add(G1, "Unordered-pair clusters", mob, n.b, n.se, n.N, f"analysis/out/{V}/FIG_new_checks.csv check=unordered_pair_clusters mobility=%s (new estimate; log out/{V}/logs/FIG_01_new_checks_{V}.log)" % s, n.ci_lo, n.ci_hi)
    pc(G1, "Exporter and importer two-way clusters", mob, "T6.c%d" % (1 + off), "", "Table 6 column %d" % (1 + off))
    w = WZ.loc[mob]
    add(G1, "Weidner-Zylkin bias correction", mob, w.corrected_b, w.corrected_se, w.N,
        WZ_SRC + " row measure=%s" % mob, w.corrected_ci_l, w.corrected_ci_u)
    # ---------------- Sample and influence
    pc(G2, "Excluding the five largest exporters", mob, "T6.c%d" % (3 + off), "", "Table 6 column %d" % (3 + off))
    n = NEW[(NEW.check.str.startswith("trim_top")) & (NEW.mobility == s)].iloc[0]
    add(G2, "Excluding top 0.1% mobility values", mob, n.b, n.se, n.N, f"analysis/out/{V}/FIG_new_checks.csv check=trim_top0.1pct_direction mobility=%s (new estimate)" % s, n.ci_lo, n.ci_hi)
    a2(G2, "Dropping the 10 most influential pairs", "A2.1c", "bilateral_drop_top10", "mob_bilat_" + s, mob)
    a1(G2, "Exact visitor-tourist common support", "A1.1.cs_iter2.{m}.mob_bilat_" + s, mob)
    # ---------------- Time
    a1(G3, "2007-2019", "A1.6.win_2007_2019.{m}.mob_bilat_" + s, mob)
    a1(G3, "Excluding 2009", "A1.6.win_ex2009.{m}.mob_bilat_" + s, mob)
    a1(G3, "Excluding 2008 and 2020", "A1.6.win_ex2008_2020.{m}.mob_bilat_" + s, mob)
    a1(G3, "Excluding 2008-2009 and 2020-2021", "A1.6.win_ex0809_2021.{m}.mob_bilat_" + s, mob)
    # audit check: the stable separation(fe simplex ir mu) run (the default ReLU check stops at its iteration limit)
    a1(G3, "Directed-pair linear trends", "A1.6.bilat_pairtrend_sepmu.{m}.mob_bilat_" + s, mob)
    # ---------------- Mobility measurement
    a1(G4, "Same basis in both directions", "A1.5.r1_sep_restricted.{m}.mob_bilat_" + s, mob)
    # audit check: the all-year one-basis restriction (r2all) replaces the superseded candidate-year r2
    a1(G4, "One basis for the pair throughout", "A1.5.r2all_sep_restricted.{m}.mob_bilat_" + s, mob)
    a1(G4, "No basis switch in either series", "A1.5.r4_sep_restricted.{m}.mob_bilat_" + s, mob)
    # revision: the clean-measurement row includes the SWEEP2 definitional mobility flags
    a1(G4, "Clean measurement (joint data-quality exclusions)", "A1.5.x_clean_sw2.{m}.mob_bilat_" + s, mob)
    # ---------------- Trade measurement and basket
    a2(G5, "Exporter-reported trade", "A2.3", "T4_reporting_pair_id", "exporter", mob)
    a2(G5, "Average of importer and exporter reports", "A2.3", "T4_reporting_pair_id", "average", mob)
    k = "visitor" if mob == "visitors" else "tourist"
    add(G5, "Upper-bound harmonization", mob, UB[k + "_b"], UB[k + "_se"], UB[k + "_n"],
        UB_SRC % (k, k, k))
    a2(G5, "Narrow-B (Narrow-A plus HS 852329/852380)", "A2.6", "v_unesco_b_on_baseline_sample", "v_unesco_b", mob)
    a2(G5, "Narrow-A (FCS core codes, without heading 8523)", "A2.6", "v_unesco_a_on_baseline_sample", "v_unesco_a", mob)
    a2(G5, "Without heading 8523", "A2.6", "v_nomedia_on_baseline_sample", "v_nomedia", mob)
    a2(G5, "Observed-record detail screen", "A2.4", "S1_T9_fully_reported", "mob_bilat_" + s, mob)
    a2(G5, "Positive trade only", "A2.4", "S1_T1_positive_only", "mob_bilat_" + s, mob)
    # ---------------- Specification
    pc(G6, "RTA/FTA control", mob, "T6.c%d" % (7 + off), "", "Table 6 column %d" % (7 + off))
    a2(G6, "ln(trips) instead of IHS", "A2.2", "ln", "ln(bilateral trips), x>0", mob)
    a2(G6, "IHS of thousands of trips", "A2.2", "ak", "asinh(bilateral trips/1000)", mob)
    # the rescaling check that loses significance is plotted too
    a2(G6, "IHS of millions of trips", "A2.2", "am", "asinh(bilateral trips/1e6)", mob)

df = pd.DataFrame(rows)
order = {}
for r in df.itertuples():
    order.setdefault(r.group, [])
    if r.label not in order[r.group]: order[r.group].append(r.label)
df["row_order"] = [sum(len(order[g]) for g in list(order)[:list(order).index(r.group)]) + order[r.group].index(r.label) + 1 for r in df.itertuples()]
df = df.sort_values(["mobility", "row_order"], ascending=[False, True]).reset_index(drop=True)
os.makedirs(OUTD, exist_ok=True)
df.insert(0, "vintage", V)
df[["vintage", "group", "label", "mobility", "b", "se", "ci_lo", "ci_hi", "N", "source"]].to_csv(OUTD + f"/Figure_coefplot{SUF}_data.csv", index=False, float_format="%.9f")
print(df.groupby("mobility").size())
print("x-range", df.ci_lo.min(), df.ci_hi.max())

# ---------------------------------------------------------------- figure
mpl = matplotlib
mpl.rcParams.update({"font.family": "sans-serif", "font.sans-serif": ["Arial", "Helvetica", "DejaVu Sans"],
                     "font.size": 6.5, "pdf.fonttype": 42, "ps.fonttype": 42, "axes.linewidth": 0.5})
GCOL = {G1: "#0072B2", G2: "#D55E00", G3: "#009E73", G4: "#CC79A7", G5: "#E69F00", G6: "#56B4E9"}
GMK = {G1: "o", G2: "s", G3: "^", G4: "D", G5: "v", G6: "P"}
glist = list(order)
# y positions: top to bottom with a gap row for each group header
ypos, ytick, ylab, hdr = {}, [], [], []
y = 0
for g in glist:
    hdr.append((y, g)); y += 1
    for lab in order[g]:
        ypos[(g, lab)] = y; ytick.append(y); ylab.append(lab); y += 1
    y += 0.35
ymax = y
W_CM = 17.0
fig = plt.figure(figsize=(W_CM / 2.54, 15.2 / 2.54))
left, right, top, bot = 0.335, 0.955, 0.955, 0.075
gap = 0.06
pw = (right - left - gap) / 2
axes = []
for i in range(2):
    ax = fig.add_axes([left + i * (pw + gap), bot, pw, top - bot])
    axes.append(ax)
# rerun C2: the x-range widens (in steps of 0.1) when an interval would otherwise be clipped
XL = (min(-0.3, float(np.floor(df.ci_lo.min() * 10) / 10)), max(0.8, float(np.ceil(df.ci_hi.max() * 10) / 10)))
for ax, mob, title in zip(axes, ("visitors", "tourists"), ("A. Bilateral visitors", "B. Bilateral tourists")):
    d = df[df.mobility == mob]
    base = d[d.label.str.startswith("Baseline")].iloc[0]
    for gi, g in enumerate(glist):
        if gi % 2 == 0:
            y0 = hdr[gi][0] - 0.5
            y1 = (hdr[gi + 1][0] - 0.85) if gi + 1 < len(glist) else ymax
            ax.axhspan(y0, y1 + 0.0, color="#F2F2F2", lw=0, zorder=0)
    ax.axvline(0, color="#444444", lw=0.6, ls=(0, (3, 2)), zorder=1)
    ax.axvline(base.b, color="#222222", lw=0.7, zorder=1)
    for r in d.itertuples():
        yy = ypos[(r.group, r.label)]
        col = GCOL[r.group]
        lo, hi = max(r.ci_lo, XL[0] + 0.01), min(r.ci_hi, XL[1] - 0.01)
        ax.plot([lo, hi], [yy, yy], color=col, lw=1.1, solid_capstyle="butt", zorder=3)
        isb = r.label.startswith("Baseline")
        ax.plot(r.b, yy, marker=GMK[r.group], ms=4.3 if not isb else 5.2, mfc="black" if isb else col,
                mec="black", mew=0.4, zorder=4)
        ax.text(1.012, yy, f"{r.N:,}", transform=ax.get_yaxis_transform(), ha="left", va="center", fontsize=5.6)
        if r.ci_lo < XL[0] or r.ci_hi > XL[1]:
            print("CLIPPED", mob, r.label, r.ci_lo, r.ci_hi)
    ax.set_xlim(*XL); ax.set_ylim(ymax - 0.4, -0.7)
    ax.set_xticks(np.round(np.arange(np.ceil(XL[0] / 0.2) * 0.2, XL[1] + 1e-9, 0.2), 1))
    ax.tick_params(axis="x", labelsize=6, width=0.5, length=2.5)
    ax.set_xlabel("PPML coefficient on bilateral mobility (95% CI)", fontsize=6.5)
    ax.set_title(title, fontsize=7.5, fontweight="bold", loc="left", pad=3)
    ax.text(1.012, -0.55, "N", transform=ax.get_yaxis_transform(), ha="left", va="center", fontsize=6, fontweight="bold")
    for s in ("top", "right"): ax.spines[s].set_visible(False)
    ax.set_yticks([])
    ax.spines["left"].set_visible(False)
# shared row labels on the left of panel A
a0 = axes[0]
for (yy, g) in hdr:
    a0.text(-0.03, yy, g, transform=a0.get_yaxis_transform(), ha="right", va="center", fontsize=6.8, fontweight="bold", color="black")
for yy, lab in zip(ytick, ylab):
    a0.text(-0.03, yy, lab, transform=a0.get_yaxis_transform(), ha="right", va="center", fontsize=6.3)
fig.legend(handles=[Line2D([], [], color="#222222", lw=0.7, label="Baseline estimate"),
                    Line2D([], [], color="#444444", lw=0.6, ls=(0, (3, 2)), label="Zero")],
           loc="lower left", bbox_to_anchor=(0.005, 0.0), ncol=2, frameon=False, fontsize=6, handlelength=2.2)
for ext, kw in (("pdf", {}), ("png", {"dpi": 600}), ("tif", {"dpi": 600, "pil_kwargs": {"compression": "tiff_lzw"}})):
    fig.savefig(f"{OUTD}/Figure_coefplot{SUF}.{ext}", **kw)
print("saved; size in cm", fig.get_size_inches() * 2.54)

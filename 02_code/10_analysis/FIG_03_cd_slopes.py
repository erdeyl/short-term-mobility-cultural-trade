#!/usr/bin/env python3
"""FIG_03_cd_slopes.py -- draw manuscript Figure 1 (mobility slopes over the observed range of cultural
distance) from the stored output of FIG_03_cd_slopes.do. No estimation; reads only out/<vintage>/
FIG_cd_slopes_{grid,bins,controls}.csv and writes 06_results/figures/Figure_cd_slopes<suffix>.{pdf,png,tif}
(png/tif 600 dpi) and Figure_cd_slopes<suffix>_data.csv.
Panels: (a) visitors, own estimation sample; (b) tourists, own estimation sample; (c) visitors and tourists
on identical observations. Line = b + g(CD - c) with 95% band (full covariance of b and g); bars =
pair-years in 20 equal-width CD bins (right axis). Palette and fonts as Figure_coefplot (FIG_02_coefplot.py:
Arial/Helvetica sans, 6.5 pt, visitors #0072B2, tourists #D55E00, zero line #444444 dashed).
Usage: python3 FIG_03_cd_slopes.py <corrected2x|corrected2> [suffix]   (corrected2x -> no suffix)
"""
import sys
import numpy as np
import pandas as pd
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.lines import Line2D
from matplotlib.patches import Patch

import os
W = os.environ.get("PKG_ROOT") or os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))  # package root
V = sys.argv[1] if len(sys.argv) > 1 else "corrected2x"
SUF = sys.argv[2] if len(sys.argv) > 2 else ""
assert V in ("corrected2", "corrected2x"), V
O = f"{W}/05_output/10_analysis/{V}"
G = pd.read_csv(O + "/FIG_cd_slopes_grid.csv")
B = pd.read_csv(O + "/FIG_cd_slopes_bins.csv")
K = pd.read_csv(O + "/FIG_cd_slopes_controls.csv")
assert (K.result == "PASS").all() and len(K) == 56, "positive controls of FIG_03_cd_slopes.do must all PASS"
for p, g in B.groupby("panel"):
    assert int(g.pairyears.sum()) == int(g.N.iloc[0]), p
    assert len(g) == 20, p

COL = {"visitors": "#0072B2", "tourists": "#D55E00"}
matplotlib.rcParams.update({"font.family": "sans-serif", "font.sans-serif": ["Arial", "Helvetica", "DejaVu Sans"],
                            "font.size": 6.5, "pdf.fonttype": 42, "ps.fonttype": 42, "axes.linewidth": 0.5})
panels = [("a_own_vis", ["visitors"], "(a) Visitors, own sample"),
          ("b_own_tour", ["tourists"], "(b) Tourists, own sample"),
          ("c_identical", ["visitors", "tourists"], "(c) Identical observations")]
fig, axes = plt.subplots(1, 3, figsize=(17.0 / 2.54, 6.6 / 2.54), sharey=False)
fig.subplots_adjust(left=0.07, right=0.93, top=0.86, bottom=0.30, wspace=0.42)
for ax, (pn, mobs, title) in zip(axes, panels):
    bb = B[B.panel == pn]
    ax2 = ax.twinx()
    ax2.bar((bb.bin_lo + bb.bin_hi) / 2, bb.pairyears, width=(bb.bin_hi - bb.bin_lo) * 0.92, color="#D9D9D9",
            edgecolor="none", zorder=0)
    ax2.set_ylim(0, bb.pairyears.max() * 3.0)
    ax2.tick_params(axis="y", labelsize=5.6, width=0.5, length=2, colors="#666666")
    for s in ("top",):
        ax2.spines[s].set_visible(False)
    ax2.spines["right"].set_linewidth(0.5)
    ax2.spines["right"].set_color("#999999")
    if pn == "c_identical":
        ax2.set_ylabel("Pair-years per bin", fontsize=6, color="#666666")
    ax.set_zorder(ax2.get_zorder() + 1)
    ax.patch.set_visible(False)
    ax.axhline(0, color="#444444", lw=0.6, ls=(0, (3, 2)), zorder=1)
    for mob in mobs:
        g = G[(G.panel == pn) & (G.mobility == mob)].sort_values("cd")
        if pn == "c_identical":
            # two overlapping bands: drawn as dashed boundary lines in the line colour, no fill (keeps them
            # distinct from each other and from the grey bars)
            ls = (0, (4, 2)) if mob == "visitors" else (0, (1.5, 1.5))
            ax.plot(g.cd, g.ci_lo, color=COL[mob], lw=0.8, ls=ls, zorder=2)
            ax.plot(g.cd, g.ci_hi, color=COL[mob], lw=0.8, ls=ls, zorder=2)
        else:
            ax.fill_between(g.cd, g.ci_lo, g.ci_hi, color=COL[mob], alpha=0.18, lw=0, zorder=2)
        ax.plot(g.cd, g.slope, color=COL[mob], lw=1.1, zorder=3)
    n = int(bb.N.iloc[0])
    ax.set_title(f"{title} (N = {n:,})", fontsize=6.8, fontweight="bold", loc="left", pad=3)
    ax.set_xlim(bb.bin_lo.min(), bb.bin_hi.max())
    gg = G[G.panel == pn]
    lo_, hi_ = min(gg.ci_lo.min(), 0) - 0.05, gg.ci_hi.max() + 0.05
    ax.set_ylim(lo_ - 0.55 * (hi_ - lo_), hi_)   # free space below the curves for the bars (right axis)
    ax.set_yticks([t for t in ax.get_yticks() if lo_ - 1e-9 <= t <= hi_ + 1e-9])   # slope ticks only where slopes are drawn
    ax.set_ylim(lo_ - 0.55 * (hi_ - lo_), hi_)
    ax.set_xlabel("Cultural distance", fontsize=6.5)
    ax.tick_params(axis="both", labelsize=6, width=0.5, length=2.5)
    for s in ("top", "right"):
        ax.spines[s].set_visible(False)
axes[0].set_ylabel("Mobility slope (PPML), 95% CI", fontsize=6.5)
# panels have their own y-range (panel c interval is much wider); the zero line is drawn in each
fig.legend(handles=[Line2D([], [], color=COL["visitors"], lw=1.1, label="Bilateral visitors"),
                    Line2D([], [], color=COL["tourists"], lw=1.1, label="Bilateral tourists"),
                    Patch(facecolor=COL["visitors"], alpha=0.18, label="95% band, visitors (a)"),
                    Patch(facecolor=COL["tourists"], alpha=0.18, label="95% band, tourists (b)"),
                    Line2D([], [], color=COL["visitors"], lw=0.8, ls=(0, (4, 2)), label="95% band, visitors (c)"),
                    Line2D([], [], color=COL["tourists"], lw=0.8, ls=(0, (1.5, 1.5)), label="95% band, tourists (c)"),
                    Patch(facecolor="#D9D9D9", label="Pair-years per bin (right axis)"),
                    Line2D([], [], color="#444444", lw=0.6, ls=(0, (3, 2)), label="Zero")],
           loc="lower center", bbox_to_anchor=(0.5, 0.0), ncol=4, frameon=False, fontsize=6, handlelength=2.0)
for ext, kw in (("pdf", {}), ("png", {"dpi": 600}), ("tif", {"dpi": 600, "pil_kwargs": {"compression": "tiff_lzw"}})):
    fig.savefig(f"{W}/06_results/figures/Figure_cd_slopes{SUF}.{ext}", **kw)
g2 = G.assign(type="slope_grid")
b2 = B.assign(type="bin_count")
out = pd.concat([g2, b2], ignore_index=True, sort=False)
out.insert(0, "source", f"analysis/out/{V}/FIG_cd_slopes_grid.csv / FIG_cd_slopes_bins.csv (FIG_03_cd_slopes.do)")
os.makedirs(f"{W}/06_results/figures", exist_ok=True)
out.to_csv(f"{W}/06_results/figures/Figure_cd_slopes{SUF}_data.csv", index=False, float_format="%.9f")
print("FIG_03 saved", V, SUF, {p: int(B[B.panel == p].N.iloc[0]) for p in B.panel.unique()})

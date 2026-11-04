#!/usr/bin/env python3
"""TAB_build.py -- TAB step: regenerate every table of the submitted manuscript (Tables 1-7, A1-A5) cell by cell
from stored estimates, for BOTH vintages with identical code, compare the submitted-vintage regeneration with the
values printed in the submitted manuscript (positive control for every cell), and write
06_results/tables/Table*.csv, RECONCILIATION.csv, TAB_control_report.csv.

No estimation here: all numbers come from files written by PREP/A1/A2/TAB_01.do/TAB_02.do or from the stored
package outputs (PKG for the submitted vintage, COPY for the corrected vintage). Stored values are used as is.
Run:  python3 TAB_build.py            (cwd any; paths below are relative to the package root)
"""
import csv, math, os, re, sys, json
import pandas as pd

W = os.environ.get("PKG_ROOT") or os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))  # package root
OUTD = f"{W}/05_output/10_analysis"
TR = f"{W}/06_results/tables"
# table layout (captions, rows, columns) of the submitted manuscript; only its table blocks are shipped
MS = f"{W}/derived/table_templates/submitted_manuscript_tables.md"
# reconciliation switch only: stored outputs of the first-submission package (submitted vintage)
PKG = os.environ.get("PKG_SUBMITTED_PUBLISHED", "")
# corrected chapter build of this package
COPY = W
MINUS = "−"

# ----------------------------------------------------------------------------- number helpers
def stars(p):
    if p is None or (isinstance(p, float) and math.isnan(p)):
        return ""
    return "***" if p < 0.01 else "**" if p < 0.05 else "*" if p < 0.10 else ""

def f3(x, minus=True, d=3):
    s = f"{x:.{d}f}"
    if s.startswith("-") and float(s) == 0:
        s = s[1:]
    return s.replace("-", MINUS) if minus else s

def fN(n):
    return f"{int(round(n)):,}"

def tonum(s):
    s = s.replace(MINUS, "-").replace(",", "").strip()
    return float(s)

def parse_cell(s):
    """Parse a printed cell into {stat: value} + printed decimals; keys: b, stars, se, N, p, lo, hi, chi2, df."""
    out, dec = {}, {}
    s0 = s.strip()
    if s0 in ("", "—", "-"):
        return out, dec
    t = s0.replace(MINUS, "-")
    m = re.search(r"χ²\((\d+)\) = ([\d.]+), p = ([\d.]+)", t)
    if m:
        out["df"] = float(m.group(1)); out["chi2"] = float(m.group(2)); out["p"] = float(m.group(3))
        dec["chi2"] = len(m.group(2).split(".")[1]); dec["p"] = len(m.group(3).split(".")[1])
        return out, dec
    m = re.search(r"(\d+(?:\.\d+)?) × 10\^?\s?(\d+)", t)
    if m:
        out["b"] = float(m.group(1)) * 10 ** int(m.group(2)); dec["b"] = 3 - int(m.group(2))
        return out, dec
    m = re.search(r"N = ([\d,]+)", t)
    if m:
        out["N"] = tonum(m.group(1)); dec["N"] = 0
        t = t.replace(m.group(0), " ")
    m = re.search(r"p = ([\d.]+)", t)
    if m:
        out["p"] = float(m.group(1)); dec["p"] = len(m.group(1).split(".")[1]) if "." in m.group(1) else 0
        t = t.replace(m.group(0), " ")
    m = re.search(r"\[(-?[\d.]+), (-?[\d.]+)\]", t)
    if m:
        out["lo"] = float(m.group(1)); out["hi"] = float(m.group(2))
        dec["lo"] = dec["hi"] = len(m.group(1).split(".")[1])
        t = t.replace(m.group(0), " ")
    m = re.search(r"\((-?[\d.,]+)\)", t)
    if m:
        out["se"] = tonum(m.group(1)); dec["se"] = len(m.group(1).split(".")[1]) if "." in m.group(1) else 0
        t = t.replace(m.group(0), " ")
    t = t.strip()
    m = re.match(r"^(-?[\d.,]+)(\*{0,3})$", t)
    if m:
        txt = m.group(1)
        if re.match(r"^-?\d{1,3}(,\d{3})+$|^-?\d+$", txt) and "." not in txt:
            out["N"] = tonum(txt); dec["N"] = 0
        else:
            out["b"] = tonum(txt); dec["b"] = len(txt.split(".")[1]) if "." in txt else 0
        if m.group(2):
            out["stars"] = m.group(2)
        else:
            out["stars"] = ""
    return out, dec

# ----------------------------------------------------------------------------- manuscript tables
def read_ms_tables():
    L = open(MS, encoding="utf-8").read().split("\n")
    tabs = {}
    for i, l in enumerate(L):
        m = re.match(r"\*\*Table (A?\d)\.?\*?\*? ?", l)
        if not m:
            continue
        name = m.group(1)
        j = i + 1
        rows = []
        while j < len(L) and (L[j].startswith("|") or L[j].strip() == "") and not (L[j].strip() == "" and rows):
            if L[j].startswith("|") and not re.match(r"^\|[-| ]+\|$", L[j]):
                cells = [c.strip() for c in L[j].strip().strip("|").split("|")]
                rows.append(cells)
            j += 1
        tabs[name] = rows
    return tabs

# ----------------------------------------------------------------------------- stored estimates (per vintage)
class Cell:
    def __init__(self, s, full=None, src=""):
        self.s, self.full, self.src = s, (full or {}), src

def load_pc_table(path):
    rows = []
    for line in open(path, encoding="utf-8"):
        fields = re.findall(r'="((?:[^"]|"")*)"', line.rstrip("\n"))
        rows.append(fields)
    out, last = {}, None
    for f in rows:
        if not f or len(f) < 2:
            continue
        lab, vals = f[0], f[1:]
        if lab == "" and last is not None and any(v.startswith("(") for v in vals):
            out[last]["se"] = vals
        elif lab:
            out[lab] = {"cells": vals}
            last = lab
    return out

class V:
    """All stored inputs for one vintage."""
    def __init__(self, v):
        self.v = v
        d = f"{OUTD}/{v}"
        self.d = d
        self.A1 = pd.read_csv(f"{d}/results/A1.csv")
        self.A2 = pd.read_csv(f"{d}/results/A2.csv")
        self.A2["_row"] = self.A2.index + 2
        self.TAB = pd.read_csv(f"{d}/TAB_results.csv")
        self.TAB["_row"] = self.TAB.index + 2
        self.T1 = pd.read_csv(f"{d}/TAB_table1.csv")
        pc = pd.read_csv(f"{d}/positive_controls.csv")
        self.PC = {r.item: r.reproduced for r in pc.itertuples()}
        self.pct = {n: load_pc_table(f"{d}/pc/tables/{f}") for n, f in {
            "2": "table2_baseline_regression.csv", "3": "table3_dynamic_future_checks.csv",
            "4": "table4_category_heterogeneity.csv", "5": "table5_moderators.csv",
            "6": "table6_robustness.csv", "A1": "tableA1_positive_trade_presence.csv"}.items()}
        self.diag = pd.read_csv(f"{d}/pc/diag/moderator-influence-results.csv").set_index("result")["value"].astype(float)
        base = PKG + "/07_results" if v == "submitted" else COPY + "/05_output/03_Mobility"
        sub = "" if v == "submitted" else ""
        if v == "submitted":
            self.ub = pd.read_csv(f"{PKG}/07_results/01_core/UB/diagnostics/baseline-key-results.csv").set_index("result")["value"].astype(float)
            self.bias = pd.read_csv(f"{PKG}/07_results/02_sensitivity/03_ppml_bias_correction/diagnostics/ppml_bias_correction_results.csv").set_index("measure")
            self.ub_src = "PKG/07_results/01_core/UB/diagnostics/baseline-key-results.csv"
            self.bias_src = "PKG/07_results/02_sensitivity/03_ppml_bias_correction/diagnostics/ppml_bias_correction_results.csv"
        else:
            self.ub = pd.read_csv(f"{COPY}/05_output/03_Mobility/01_diagnostics/core/UB/baseline-key-results.csv").set_index("result")["value"].astype(float)
            self.bias = pd.read_csv(f"{COPY}/05_output/03_Mobility/01_diagnostics/sensitivity/03_ppml_bias_correction/ppml_bias_correction_results.csv").set_index("measure")
            self.ub_src = "COPY/05_output/03_Mobility/01_diagnostics/core/UB/baseline-key-results.csv"
            self.bias_src = "COPY/05_output/03_Mobility/01_diagnostics/sensitivity/03_ppml_bias_correction/ppml_bias_correction_results.csv"

    # ---- row lookups
    def a1(self, rid):
        r = self.A1[self.A1.row_id == rid]
        assert len(r) == 1, (self.v, rid, len(r))
        return r.iloc[0]

    def a1src(self, rid):
        return f"out/{self.v}/results/A1.csv row_id {rid}"

    def a2(self, spec, term, mobility=None, item=None):
        x = self.A2[(self.A2.spec == spec) & (self.A2.term == term)]
        if mobility is not None:
            x = x[x.mobility == mobility]
        if item is not None:
            x = x[x["item"] == item]
        assert len(x) == 1, (self.v, spec, term, mobility, len(x))
        return x.iloc[0]

    def a2src(self, r):
        return f"out/{self.v}/results/A2.csv line {int(r._row)} (item {r['item']}, spec {r.spec}, term {r.term})"

    def tab(self, item, spec, term):
        x = self.TAB[(self.TAB["item"] == item) & (self.TAB.spec == spec) & (self.TAB.term == term)]
        assert len(x) == 1, (self.v, item, spec, term, len(x))
        return x.iloc[0]

    def tabsrc(self, r):
        return f"out/{self.v}/TAB_results.csv line {int(r._row)} (item {r['item']}, spec {r.spec}, term {r.term}); log out/{self.v}/TAB_01_{self.v}.log"

    def t1(self, var):
        x = self.T1[self.T1.variable == var]
        assert len(x) == 1
        return x.iloc[0]

# ----------------------------------------------------------------------------- cell formatters
def cell_bse(b, se, p, N=None, d=3, extra=""):
    s = f"{f3(b, d=d)}{stars(p)} ({f3(se, d=d, minus=False)})"
    if N is not None:
        s += f" N = {fN(N)}"
    return s + extra

def full_bse(r, N=None):
    d = {"b": float(r.b), "se": float(r.se), "p": float(r.p)}
    if N is not None:
        d["N"] = float(N)
    return d

# ----------------------------------------------------------------------------- build one vintage
def build(vv):
    v = vv.v
    C = {}  # (table, rowkey, colidx) -> Cell ; rowkey = md label (A2: "Measure | Spec")
    def put(t, rk, ci, cell):
        C[(t, rk, ci)] = cell

    # ---- Table 1 (TAB_table1.csv)
    t1rows = [("Trade (thousand USD)", "v_ttl_k"), ("Bilateral visitors", "bilat_vis_raw"),
              ("Reverse visitors: importer→exporter", "rev_vis_raw"), ("Same-direction visitors: exporter→importer", "same_vis_raw"),
              ("Bilateral tourists", "bilat_tour_raw"), ("Reverse tourists: importer→exporter", "rev_tour_raw"),
              ("Same-direction tourists: exporter→importer", "same_tour_raw"), ("Common language", "comlang_off"),
              ("Cultural distance", "cul_dist")]
    def f1(x):
        if abs(x) >= 1e8:
            e = int(math.floor(math.log10(abs(x)))); m = x / 10 ** e
            return f"{m:.3f} × 10 {e}"
        return f"{x:,.3f}"
    for lab, var in t1rows:
        r = vv.t1(var)
        src = f"out/{v}/TAB_table1.csv variable {var}; log out/{v}/TAB_01_{v}.log (TAB_T1 {var})"
        put("1", lab, 1, Cell(fN(r.N), {"N": float(r.N)}, src))
        for ci, (k, col) in enumerate([("mean", "mean"), ("sd", "sd"), ("min", "min"), ("max", "max")], start=2):
            put("1", lab, ci, Cell(f1(float(r[col])), {"b": float(r[col])}, src))

    # ---- Tables 2-6, A1 (pc tables = esttab output of the original code, run unmodified on prepared.dta)
    def pcget(tab, plab, k):
        d = vv.pct[tab][plab]
        return d["cells"][k - 1], (d["se"][k - 1] if "se" in d else None)
    def pcfull(prefix, plab, k, stat):
        key = f"{prefix}.c{k}.{plab}.{stat}"
        return vv.PC.get(key)
    def pc_cell(tab, prefix, plab, k):
        b, se = pcget(tab, plab, k)
        fb = pcfull(prefix, plab, k, "b"); fs = pcfull(prefix, plab, k, "se")
        s = f"{b} {se}" if se else b
        full = {}
        if fb is not None: full["b"] = fb
        if fs is not None: full["se"] = fs
        return s, full
    src_pc = lambda f: f"out/{v}/pc/tables/{f}"
    # Table 2
    t2 = {"Bilateral visitors": [1], "Reverse visitors": [2, 4], "Same-direction visitors": [3, 4],
          "Bilateral tourists": [5], "Reverse tourists": [6, 8], "Same-direction tourists": [7, 8]}
    for lab, cols in t2.items():
        for k in cols:
            s, full = pc_cell("2", "T2", lab, k)
            put("2", lab, k, Cell(s, full, src_pc("table2_baseline_regression.csv") + f" row '{lab}' col ({k}); full precision PC item T2.c{k}.{lab}"))
    for k in range(1, 9):
        n = pcget("2", "N", k)[0]
        put("2", "N", k, Cell(n, {"N": pcfull("T2", "N", k, "N")}, src_pc("table2_baseline_regression.csv") + f" row N col ({k})"))
    # Table 3
    t3 = {"Lag bilateral mobility": ("Lag bilateral visitors", "Lag bilateral tourists"),
          "Contemporaneous bilateral mobility": ("Bilateral visitors", "Bilateral tourists"),
          "Future bilateral mobility": ("Future bilateral visitors", "Future bilateral tourists")}
    for lab, (pv, pt) in t3.items():
        for k, pl in ((1, pv), (2, pt)):
            s, full = pc_cell("3", "T3", pl, k)
            put("3", lab, k, Cell(s, full, src_pc("table3_dynamic_future_checks.csv") + f" row '{pl}' col ({k}); PC item T3.c{k}.{pl}"))
    for k in (1, 2):
        pv = pcget("3", "Future-mobility p-value", k)[0]
        put("3", "Future-term p-value", k, Cell(pv, {"p": pcfull("T3", "Future-mobility p-value", k, "p")}, src_pc("table3_dynamic_future_checks.csv") + f" row Future-mobility p-value col ({k})"))
        put("3", "N", k, Cell(pcget("3", "N", k)[0], {"N": pcfull("T3", "N", k, "N")}, src_pc("table3_dynamic_future_checks.csv") + f" row N col ({k})"))
    # Table 4
    for k in range(1, 9):
        pl = "Bilateral visitors" if k % 2 else "Bilateral tourists"
        s, full = pc_cell("4", "T4", pl, k)
        put("4", "Bilateral mobility", k, Cell(s, full, src_pc("table4_category_heterogeneity.csv") + f" row '{pl}' col ({k}); PC item T4.c{k}"))
        put("4", "Observations ( N )", k, Cell(pcget("4", "N", k)[0], {"N": pcfull("T4", "N", k, "N")}, src_pc("table4_category_heterogeneity.csv") + f" row N col ({k})"))
    # Table 5
    t5 = {"Bilateral visitors": ("Bilateral visitors", [1, 3]), "Visitors × common language": ("Visitors x common language", [1]),
          "Bilateral tourists": ("Bilateral tourists", [2, 4]), "Tourists × common language": ("Tourists x common language", [2]),
          "Visitors × cultural distance": ("Visitors x cultural distance", [3]), "Tourists × cultural distance": ("Tourists x cultural distance", [4])}
    for lab, (pl, cols) in t5.items():
        for k in cols:
            s, full = pc_cell("5", "T5", pl, k)
            put("5", lab, k, Cell(s, full, src_pc("table5_moderators.csv") + f" row '{pl}' col ({k}); PC item T5.c{k}.{pl}"))
    for k in range(1, 5):
        put("5", "N", k, Cell(pcget("5", "N", k)[0], {"N": pcfull("T5", "N", k, "N")}, src_pc("table5_moderators.csv") + f" row N col ({k})"))
    # Table 6
    for k in range(1, 9):
        pl = "Bilateral visitors" if k % 2 else "Bilateral tourists"
        s, full = pc_cell("6", "T6", pl, k)
        put("6", "Bilateral mobility", k, Cell(s, full, src_pc("table6_robustness.csv") + f" row '{pl}' col ({k}); PC item T6.c{k}"))
        put("6", "Observations (N)", k, Cell(pcget("6", "N", k)[0], {"N": pcfull("T6", "N", k, "N")}, src_pc("table6_robustness.csv") + f" row N col ({k})"))
        if k in (7, 8):
            s, full = pc_cell("6", "T6", "RTA/FTA indicator", k)
            put("6", "RTA/FTA indicator", k, Cell(s, full, src_pc("table6_robustness.csv") + f" row RTA/FTA indicator col ({k})"))
    # Table A1
    for k in (1, 2):
        pl = "Bilateral visitors" if k == 1 else "Bilateral tourists"
        s, full = pc_cell("A1", "TA1", pl, k)
        put("A1", "Mobility coefficient", k, Cell(s, full, src_pc("tableA1_positive_trade_presence.csv") + f" row '{pl}' col ({k})"))
        put("A1", "Observations (N)", k, Cell(pcget("A1", "N", k)[0], {"N": pcfull("TA1", "N", k, "N")}, src_pc("tableA1_positive_trade_presence.csv") + " row N"))
        put("A1", "Adjusted R²", k, Cell(pcget("A1", "Adjusted R2", k)[0], {"r2": pcfull("TA1", "Adjusted R2", k, "r2")}, src_pc("tableA1_positive_trade_presence.csv") + " row Adjusted R2"))

    # ---- Table 7
    T7 = "7"
    m = {"vis": 1, "tour": 2}
    mn = {"vis": "mob_bilat_vis", "tour": "mob_bilat_tour"}
    for ms_, ci in m.items():
        r = vv.a1(f"A1.1.baseline.{ms_}.{mn[ms_]}")
        put(T7, "Baseline", ci, Cell(cell_bse(r.b, r.se, r.p, r.N), full_bse(r, r.N), vv.a1src(f"A1.1.baseline.{ms_}.{mn[ms_]}") + " (equals Table 2 col 1 / 5)"))
        r = vv.tab("T11", "trim_directional", mn[ms_])
        put(T7, "Excluding top 0.1% directional mobility values", ci, Cell(cell_bse(r.b, r.se, r.p, r.N), full_bse(r, r.N), vv.tabsrc(r)))
        r = vv.tab("T10", "same_basis_source", mn[ms_])
        put(T7, "Same origin classification, stored direction", ci, Cell(cell_bse(r.b, r.se, r.p, r.N), full_bse(r, r.N), vv.tabsrc(r)))
        r = vv.tab("T10", "same_basis_bilateral", mn[ms_])
        put(T7, "Same origin classification, both directions", ci, Cell(cell_bse(r.b, r.se, r.p, r.N), full_bse(r, r.N), vv.tabsrc(r)))
    # Panel B unit-break row (A1.4 rule: > 50x median, union of flagged reporter-years)
    for ms_, ci in m.items():
        rid = f"A1.4.excl_ratio50_union.{ms_}.{mn[ms_]}"
        r = vv.a1(rid)
        put(T7, "Excluding unit-break reporter-years (Paraguay, 2020–2021)", ci, Cell(cell_bse(r.b, r.se, r.p, r.N), full_bse(r, r.N), vv.a1src(rid)))
    # Panel D
    cats = [("Cinematographic film", "film"), ("Publications", "publications"), ("Recorded media", "recorded_media"), ("Artworks", "artworks")]
    for ci, mob in ((1, "visitors"), (2, "tourists")):
        for lab, term in cats:
            r = vv.a2("T3_commonsupport_pair_id", term, mobility=mob)
            put(T7, lab, ci, Cell(cell_bse(r.b, r.se, r.p, r.N), full_bse(r, r.N), vv.a2src(r)))
        r = vv.a2("T3_commonsupport_pair_id", "joint equality of 4 category slopes", mobility=mob)
        put(T7, "Joint equality of category coefficients", ci, Cell(f"χ²(3) = {r.b:.3f}, p = {r.p:.3f}", {"chi2": float(r.b), "p": float(r.p), "N": float(r.N)}, vv.a2src(r)))
    # Panel E
    for lab, spec in (("Artworks: visitor–tourist difference", "T5_vt_artworks_pair_id"), ("Recorded media: visitor–tourist difference", "T5_vt_recorded_media_pair_id")):
        r = vv.a2(spec, "visitors - tourists")
        put(T7, lab, 1, Cell(f"{f3(r.b)} ({f3(r.se, minus=False)}) N = {fN(r.N)} p = {r.p:.3f}", full_bse(r, r.N), vv.a2src(r)))
    # Panel F  (A1.8; default separation, N as in the submitted table; 90% interval = b -/+ z95*se, normal as lincom after ppmlhdfe)
    z90 = 1.6448536269514722
    for ms_, ci in m.items():
        for lab, sp in (("Lead mobility, no pair trends", "T7_none"), ("Lead mobility, pair trends", "T7_pair")):
            rid = f"A1.8.{sp}.{ms_}.lead_bilat_{ms_}"
            r = vv.a1(rid)
            lo, hi = r.b - z90 * r.se, r.b + z90 * r.se
            put(T7, lab, ci, Cell(f"{f3(r.b)}{stars(r.p)} ({f3(r.se, minus=False)}) N = {fN(r.N)} [{f3(lo)}, {f3(hi)}]",
                                 {"b": float(r.b), "se": float(r.se), "p": float(r.p), "N": float(r.N), "lo": float(lo), "hi": float(hi)}, vv.a1src(rid)))

    # ---- Table A2
    def a2row(meas, spec, b, se, N, full, src):
        k = f"{meas} | {spec}"
        put("A2", k, 2, Cell(f3(b, d=3), {"b": float(full[0])}, src))
        put("A2", k, 3, Cell(f3(se, d=3, minus=False), {"b": float(full[1])}, src))
        put("A2", k, 4, Cell(fN(N), {"N": float(N)}, src))
    # LB own support = Table 2 cols 1 and 5 (full precision from PC); UB = stored; exact = PC CS items
    for meas, k2, ub_p, cs in (("Visitors", 1, "visitor", 3), ("Tourists", 5, "tourist", 4)):
        b = vv.PC[f"T2.c{k2}.{'Bilateral visitors' if meas=='Visitors' else 'Bilateral tourists'}.b"]
        se = vv.PC[f"T2.c{k2}.{'Bilateral visitors' if meas=='Visitors' else 'Bilateral tourists'}.se"]
        N = vv.PC[f"T2.c{k2}.N.N"]
        a2row(meas, "LB own support", b, se, N, (b, se), f"out/{v}/positive_controls.csv items T2.c{k2}.* (reproduced, full precision)")
        a2row(meas, "UB own support", vv.ub[f"{ub_p}_b"], vv.ub[f"{ub_p}_se"], vv.ub[f"{ub_p}_n"], (vv.ub[f"{ub_p}_b"], vv.ub[f"{ub_p}_se"]),
              f"{vv.ub_src} ({ub_p}_b/_se/_n); independently re-estimated in TAB_02.do (out/{v}/TAB_02_{v}.log)")
        lab = "Bilateral visitors" if meas == "Visitors" else "Bilateral tourists"
        bb, ss, nn = vv.PC[f"CS.c{cs}.{lab}.b"], vv.PC[f"CS.c{cs}.{lab}.se"], vv.PC[f"CS.c{cs}.N.N"]
        a2row(meas, "Exact visitor–tourist support", bb, ss, nn, (bb, ss), f"out/{v}/positive_controls.csv items CS.c{cs}.* (reproduced, full precision)")
        # cols 0/1 labels unchanged
    # ---- Table A3
    for meas, key in (("Visitors", "visitors"), ("Tourists", "tourists")):
        r = vv.bias.loc[key]
        src = f"{vv.bias_src} row {key}"
        put("A3", meas, 1, Cell(f3(r.original_b, minus=False), {"b": float(r.original_b)}, src))
        put("A3", meas, 2, Cell(f3(r.original_se, minus=False), {"b": float(r.original_se)}, src))
        put("A3", meas, 3, Cell(f3(r.corrected_b, minus=False), {"b": float(r.corrected_b)}, src))
        put("A3", meas, 4, Cell(f3(r.corrected_se, minus=False), {"b": float(r.corrected_se)}, src))
        put("A3", meas, 5, Cell(f"{r.corrected_p:.3f}", {"b": float(r.corrected_p)}, src))
    # ---- Table A4
    for meas, mob, N_ in (("Visitors", "visitors", None), ("Tourists", "tourists", None)):
        ri = vv.a2("T4_reporting_pair_id", "importer", mobility=mob)
        re_ = vv.a2("T4_reporting_pair_id", "exporter", mobility=mob)
        ra = vv.a2("T4_reporting_pair_id", "average", mobility=mob)
        rp = vv.a2("T4_reporting_pair_id", "importer - exporter", mobility=mob)
        r3 = vv.a2("T4_reporting_pair_id", "all three equal", mobility=mob)
        put("A4", meas, 1, Cell(f"{f3(ri.b, minus=False)} ({f3(ri.se, minus=False)})", {"b": float(ri.b), "se": float(ri.se)}, vv.a2src(ri)))
        put("A4", meas, 2, Cell(f"{f3(re_.b, minus=False)} ({f3(re_.se, minus=False)})", {"b": float(re_.b), "se": float(re_.se)}, vv.a2src(re_)))
        put("A4", meas, 3, Cell(f"{f3(ra.b, minus=False)} ({f3(ra.se, minus=False)})", {"b": float(ra.b), "se": float(ra.se)}, vv.a2src(ra)))
        put("A4", meas, 4, Cell(fN(ri.N), {"N": float(ri.N)}, vv.a2src(ri)))
        put("A4", meas, 5, Cell(f"{rp.p:.3f}", {"b": float(rp.p)}, vv.a2src(rp)))
        put("A4", meas, 6, Cell(f"{r3.p:.3f}", {"b": float(r3.p)}, vv.a2src(r3)))
    # ---- Table A5
    A5 = "A5"
    for mob, ci, mm in (("visitors", 1, "mob_bilat_vis"), ("tourists", 2, "mob_bilat_tour")):
        tag = "vis" if mob == "visitors" else "tour"
        for lab, spec in (("Positive trade only", "S1_T1_positive_only"), ("Positive trade in every year 2007–2021", "S1_T1_positive_every_year"),
                          ("Fully reported trade only", "S1_T9_fully_reported")):
            x = vv.A2[(vv.A2.spec == spec) & (vv.A2.term == mm)]
            assert len(x) == 1, (spec, mm)
            r = x.iloc[0]
            put(A5, lab, ci, Cell(cell_bse(r.b, r.se, r.p, r.N), full_bse(r, r.N), vv.a2src(r)))
        r = vv.A2[(vv.A2.spec == "T2_same_sample_ppml") & (vv.A2.mobility == mob) & (vv.A2.term == "100*b: % per IHS unit")].iloc[0]
        put(A5, "Same sample: expected trade, % per IHS unit", ci, Cell(cell_bse(r.b, r.se, r.p, r.N, d=2), full_bse(r, r.N), vv.a2src(r)))
        r = vv.A2[(vv.A2.spec == "T2_same_sample_lpm") & (vv.A2.mobility == mob) & (vv.A2.term == "pp per IHS unit")].iloc[0]
        put(A5, "Same sample: probability of positive trade, percentage points", ci, Cell(cell_bse(r.b, r.se, r.p, r.N, d=2), full_bse(r, r.N), vv.a2src(r)))
        r = vv.tab("T6", "artworks_9701_9703", mm)
        put(A5, "Artworks HS 9701–9703", ci, Cell(cell_bse(r.b, r.se, r.p, r.N), full_bse(r, r.N), vv.tabsrc(r)))
        r = vv.tab("T6", "publications_excl_4907_4908_4911", mm)
        put(A5, "Publications excluding HS 4907/4908/4911", ci, Cell(cell_bse(r.b, r.se, r.p, r.N), full_bse(r, r.N), vv.tabsrc(r)))
        r = vv.A2[(vv.A2.spec == "recmedia_exact_tableA5") & (vv.A2.mobility == mob)].iloc[0]
        put(A5, "Recorded media, exact HS 852329/852340/852380", ci, Cell(cell_bse(r.b, r.se, r.p, r.N), full_bse(r, r.N), vv.a2src(r)))
        # strict_x rows are posted for vis then tour; select by order of the two rows
        rr = vv.TAB[(vv.TAB["item"] == "T5") & (vv.TAB.spec == "strict6_interaction")].reset_index(drop=True)
        r = rr.iloc[0 if mob == "visitors" else 1]
        put(A5, "Cultural distance, all six dimensions: interaction", ci, Cell(cell_bse(r.b, r.se, r.p, r.N), full_bse(r, r.N), vv.tabsrc(r)))
    r = vv.tab("T12", "same_day_only", "mob_day")
    put(A5, "Visitor-minus-tourist difference, alone", 1, Cell(cell_bse(r.b, r.se, r.p, r.N), full_bse(r, r.N), vv.tabsrc(r)))
    r = vv.tab("T12", "same_day_with_overnight", "mob_day")
    put(A5, "Visitor-minus-tourist difference, controlling for tourists", 1, Cell(cell_bse(r.b, r.se, r.p, r.N), full_bse(r, r.N), vv.tabsrc(r)))
    return C

# ----------------------------------------------------------------------------- note cells (numbers quoted in table notes)
def notes(vv):
    v = vv.v
    d = {}
    d[("2 note", "Directed-pair-clustered equality test (rev = same), column (4), p")] = Cell(f"{vv.PC['BKR.visitor_direction_equality_p']:.3f}", {"b": float(vv.PC['BKR.visitor_direction_equality_p'])}, f"out/{v}/positive_controls.csv BKR.visitor_direction_equality_p")
    r = vv.a1("A1.9.dir_full_unordered_pair_id_test.vis.rev_eq_same")
    d[("2 note", "Unordered-pair-clustered equality test, column (4), p")] = Cell(f"{r.p:.3f}", {"b": float(r.p)}, vv.a1src("A1.9.dir_full_unordered_pair_id_test.vis.rev_eq_same"))
    d[("4 note", "Joint equality across four categories, visitors, p")] = Cell(f"{vv.PC['LOG.CATEGORY_EQUALITY.mob_bilat_vis']:.3f}", {"b": float(vv.PC['LOG.CATEGORY_EQUALITY.mob_bilat_vis'])}, f"out/{v}/positive_controls.csv LOG.CATEGORY_EQUALITY.mob_bilat_vis")
    d[("4 note", "Joint equality across four categories, tourists, p")] = Cell(f"{vv.PC['LOG.CATEGORY_EQUALITY.mob_bilat_tour']:.3f}", {"b": float(vv.PC['LOG.CATEGORY_EQUALITY.mob_bilat_tour'])}, f"out/{v}/positive_controls.csv LOG.CATEGORY_EQUALITY.mob_bilat_tour")
    d[("5 note", "Visitor x cultural-distance interaction, full sample")] = Cell(f"{vv.diag['original_culdist_b']:.3f} (p = {vv.diag['original_culdist_p']:.3f})", {"b": float(vv.diag['original_culdist_b']), "p": float(vv.diag['original_culdist_p'])}, f"out/{v}/pc/diag/moderator-influence-results.csv original_culdist_b/_p")
    d[("5 note", "Visitor x cultural-distance interaction, excluding China -> China, Hong Kong SAR")] = Cell(f"{vv.diag['no_china_hk_b']:.3f} (p = {vv.diag['no_china_hk_p']:.3f})", {"b": float(vv.diag['no_china_hk_b']), "p": float(vv.diag['no_china_hk_p'])}, f"out/{v}/pc/diag/moderator-influence-results.csv no_china_hk_b/_p")
    d[("A2 note", "Exact support: visitor minus tourist difference (SE)")] = Cell(f"{vv.PC['FER.difference']:.3f} ({vv.PC['FER.difference_se']:.3f})", {"b": float(vv.PC['FER.difference']), "se": float(vv.PC['FER.difference_se'])}, f"out/{v}/positive_controls.csv FER.difference/_se")
    d[("A2 note", "Exact support: visitor minus tourist difference, p")] = Cell(f"{vv.PC['FER.difference_p']:.3f}", {"b": float(vv.PC['FER.difference_p'])}, f"out/{v}/positive_controls.csv FER.difference_p")
    return d

NOTES_SUB_PRINTED = {
    ("2 note", "Directed-pair-clustered equality test (rev = same), column (4), p"): "0.042",
    ("2 note", "Unordered-pair-clustered equality test, column (4), p"): "borderline at 5% (no number printed; A2 reports 0.0504)",
    ("4 note", "Joint equality across four categories, visitors, p"): "0.161",
    ("4 note", "Joint equality across four categories, tourists, p"): "0.018",
    ("5 note", "Visitor x cultural-distance interaction, full sample"): "0.045 (p = 0.083)",
    ("5 note", "Visitor x cultural-distance interaction, excluding China -> China, Hong Kong SAR"): "0.021 (p = 0.365)",
    ("A2 note", "Exact support: visitor minus tourist difference (SE)"): "0.016 (0.017)",
    ("A2 note", "Exact support: visitor minus tourist difference, p"): "0.350",
}

# ----------------------------------------------------------------------------- main
LABELCOLS = {"A2": 2}
CAPTIONS = {"1": "Table 1", "2": "Table 2", "3": "Table 3", "4": "Table 4", "5": "Table 5", "6": "Table 6", "7": "Table 7",
            "A1": "Table A1", "A2": "Table A2", "A3": "Table A3", "A4": "Table A4", "A5": "Table A5"}
FILES = {"1": "Table1", "2": "Table2", "3": "Table3", "4": "Table4", "5": "Table5", "6": "Table6", "7": "Table7",
         "A1": "TableA1", "A2": "TableA2", "A3": "TableA3", "A4": "TableA4", "A5": "TableA5"}
OBSOLETE = {("7", "Excluding unit-break reporter-years (Paraguay, 2020–2021)")}

def compress_sources(srcs):
    """Group 'path row ... col (k)' references by path to keep the source column readable."""
    groups, order = {}, []
    for x in srcs:
        m = re.match(r"^(.*?\.csv) row (.*)$", x)
        if m:
            if m.group(1) not in groups:
                groups[m.group(1)] = []; order.append(m.group(1))
            groups[m.group(1)].append(m.group(2).split("; ")[0])
        else:
            order.append(x); groups[x] = None
    parts = []
    for k in order:
        parts.append(k if groups[k] is None else f"{k} [{'; '.join(dict.fromkeys(groups[k]))}]")
    return "; ".join(dict.fromkeys(parts))

def rowkey(t, cells):
    n = LABELCOLS.get(t, 1)
    return " | ".join(cells[:n])

def norm_key(t, k):
    return re.sub(r"\s+", " ", k).replace(" ", " ")

def decisions(sub_s, cor_s, stat, sub_full, cor_full, dec):
    """changed beyond rounding? Uses full precision of both when available, otherwise printed values."""
    pass

def main():
    ms = read_ms_tables()
    S, Cr = V("submitted"), V("corrected")
    CS_, CC_ = build(S), build(Cr)
    NS_, NC_ = notes(S), notes(Cr)

    ctrl = []   # control report: regenerated submitted vs manuscript printed
    recon = []
    tableout = {}
    srcrow = {}
    for t in CAPTIONS:
        rows = ms[t]
        header = [h.replace("*", "") for h in rows[0]]
        ncol = len(header)
        nlab = LABELCOLS.get(t, 1)
        outrows = [header + ["source"]]
        for cells in rows[1:]:
            cells = cells + [""] * (ncol - len(cells))
            rk = norm_key(t, rowkey(t, cells))
            newcells = list(cells)
            srcs = []
            for ci in range(nlab, ncol):
                printed = cells[ci]
                if printed == "":
                    continue
                if printed == "\u2014":
                    continue
                key = (t, rk, ci)
                # md keys: normalise multiple spaces in row labels
                found = None
                for kk in (key,):
                    if kk in CC_:
                        found = kk
                if found is None:
                    # try matching with normalised keys
                    alt = [k2 for k2 in CC_ if k2[0] == t and norm_key(t, k2[1]) == rk and k2[2] == ci]
                    found = alt[0] if alt else None
                if (t, rk) in OBSOLETE:
                    # keep in table as explicit placeholder; reconciliation row below
                    sc = CS_[found] if found in CS_ else None
                    newcells[ci] = "n/a (obsolete, see TAB_NOTES)"
                    srcs.append(f"{CC_[found].src} [rule applied to corrected data flags no reporter-year; row obsolete]")
                    corr_s_for_recon = "obsolete"
                    cc = CC_[found]
                else:
                    assert found is not None, ("no corrected cell", key, printed)
                    cc = CC_[found]
                    newcells[ci] = cc.s
                    srcs.append(cc.src)
                    corr_s_for_recon = cc.s
                sc = CS_[found]
                # control: regenerated submitted vs manuscript printed
                pp, pdc = parse_cell(printed)
                ps, _ = parse_cell(sc.s)
                ok = True; why = []
                for kx in set(pp) | set(ps):
                    if kx == "stars":
                        if pp.get(kx, "") != ps.get(kx, ""):
                            ok = False; why.append(f"stars {pp.get(kx,'')!r} vs {ps.get(kx,'')!r}")
                    else:
                        a, b = pp.get(kx), ps.get(kx)
                        if a is None or b is None:
                            ok = False; why.append(f"{kx} missing in {'regenerated' if b is None else 'printed'}")
                        else:
                            if abs(a - b) > 1e-9 * max(1.0, abs(b)):
                                ok = False; why.append(f"{kx}: printed {a} vs regenerated {b}")
                ctrl.append({"table": CAPTIONS[t], "row": rk, "col": header[ci] if ci < len(header) else ci,
                             "printed_manuscript": printed, "regenerated_submitted": sc.s,
                             "control": "PASS" if ok else "FAIL", "detail": "; ".join(why), "source_submitted": sc.src})
                # reconciliation rows
                pc_, dc_ = parse_cell(cc.s) if corr_s_for_recon != "obsolete" else ({}, {})
                _ord = ['b', 'se', 'p', 'chi2', 'df', 'lo', 'hi', 'N', 'stars']
                keys = [k_ for k_ in _ord if k_ in pp or k_ in pc_]
                if corr_s_for_recon == "obsolete":
                    recon.append({"table": CAPTIONS[t], "row": rk, "column": header[ci], "statistic": "cell",
                                  "submitted_as_printed": printed, "corrected_value": "obsolete (not applicable on corrected data)",
                                  "difference": "", "changed_beyond_rounding": "obsolete",
                                  "submitted_regenerated_control": "PASS" if ok else "FAIL", "source_corrected": cc.src})
                    continue
                for kx in keys:
                    a, b = pp.get(kx), pc_.get(kx)
                    dd = pdc.get(kx, dc_.get(kx, 3))
                    if kx == "stars":
                        if not (a or b):
                            continue
                        changed = "yes" if (a or "") != (b or "") else "no"
                        recon.append({"table": CAPTIONS[t], "row": rk, "column": header[ci], "statistic": "significance stars",
                                      "submitted_as_printed": a or "none", "corrected_value": b or "none", "difference": "",
                                      "changed_beyond_rounding": changed, "submitted_regenerated_control": "PASS" if ok else "FAIL", "source_corrected": cc.src})
                        continue
                    statname = {"b": "estimate", "se": "SE", "N": "N", "p": "p", "lo": "interval lower", "hi": "interval upper", "chi2": "chi2", "df": "df"}[kx]
                    if t == "1":
                        statname = "N" if kx == "N" else ["mean", "SD", "min", "max"][ci - 2]
                    elif kx == "b" and ("standard error" in header[ci].lower() or (header[ci].strip().endswith("SE") and "(SE)" not in header[ci] and "\u03b2" not in header[ci].replace("Original","").replace("Corrected",""))):
                        statname = "SE"
                    elif kx == "b" and (re.search(r"p\*?\s?-\s?value", rk.lower()) or re.search(r"p\*?\s?-\s?value", header[ci].lower())):
                        statname = "p"
                    def pr(val, dec_, kx_=kx):
                        if val is None:
                            return ""
                        if t == "1" and statname == "max":
                            return printed if val == a else cc.s
                        if kx_ == "N":
                            return f"{int(val):,}"
                        if t == "1" and abs(val) >= 1e8:
                            return printed if val == a else cc.s.split(" ")[0] + " " + " ".join(cc.s.split(" ")[1:])
                        dec_ = max(dec_, 0)
                        return f"{val:,.{dec_}f}" if t == "1" else f"{val:.{dec_}f}"
                    fk = kx if kx in ("b", "se", "p", "N", "lo", "hi", "chi2") else kx
                    def fget(dct):
                        if fk in dct: return dct[fk]
                        if fk == "b":
                            for alt in ("p", "r2"):
                                if alt in dct: return dct[alt]
                        return None
                    fs_, fc_ = fget(sc.full), fget(cc.full)
                    if a is None or b is None:
                        recon.append({"table": CAPTIONS[t], "row": rk, "column": header[ci], "statistic": statname,
                                      "submitted_as_printed": "" if a is None else pr(a, dd), "corrected_value": "" if b is None else pr(b, dd),
                                      "difference": "", "changed_beyond_rounding": "yes (cell structure differs)",
                                      "submitted_full_precision": "", "corrected_full_precision": "",
                                      "submitted_regenerated_control": "PASS" if ok else "FAIL", "source_corrected": cc.src})
                        continue
                    diff = b - a
                    unit = 10 ** (-dd)
                    if kx == "N":
                        changed = "yes" if diff != 0 else "no"
                    elif fs_ is not None and fc_ is not None:
                        changed = "yes" if abs(fc_ - fs_) >= unit - 1e-12 else "no"
                    else:
                        changed = "yes" if abs(diff) > unit * (1 + 1e-9) else "no"
                    recon.append({"table": CAPTIONS[t], "row": rk, "column": header[ci], "statistic": statname,
                                  "submitted_as_printed": pr(a, dd), "corrected_value": pr(b, dd),
                                  "difference": (f"{diff:.{max(dd,0)}f}" if kx != "N" else f"{int(diff)}"),
                                  "changed_beyond_rounding": changed,
                                  "submitted_full_precision": "" if fs_ is None else repr(float(fs_)),
                                  "corrected_full_precision": "" if fc_ is None else repr(float(fc_)),
                                  "submitted_regenerated_control": "PASS" if ok else "FAIL", "source_corrected": cc.src})
            outrows.append(newcells + [compress_sources(list(dict.fromkeys(srcs)))])
        tableout[t] = outrows

    # note cells
    for k, cc in NC_.items():
        sub_printed = NOTES_SUB_PRINTED[k]
        sc = NS_[k]
        pc_, _ = parse_cell(cc.s)
        recon.append({"table": "Table " + k[0], "row": k[1], "column": "(note)", "statistic": "value",
                      "submitted_as_printed": sub_printed, "corrected_value": cc.s, "difference": "",
                      "changed_beyond_rounding": "yes" if sub_printed != cc.s else "no", "submitted_regenerated_control": "regenerated submitted: " + sc.s, "source_corrected": cc.src})

    # ---- write
    os.makedirs(TR, exist_ok=True)
    for t, rows in tableout.items():
        with open(f"{TR}/{FILES[t]}.csv", "w", newline="", encoding="utf-8") as fh:
            csv.writer(fh).writerows(rows)
    pd.DataFrame(recon).to_csv(f"{TR}/RECONCILIATION.csv", index=False)
    pd.DataFrame(ctrl).to_csv(f"{TR}/TAB_control_report.csv", index=False)
    nfail = sum(1 for c in ctrl if c["control"] == "FAIL")
    print("cells controlled:", len(ctrl), "FAIL:", nfail)
    for c in ctrl:
        if c["control"] == "FAIL":
            print("FAIL", c["table"], c["row"], c["col"], "|", c["printed_manuscript"], "|", c["regenerated_submitted"], "|", c["detail"])
    print("reconciliation rows:", len(recon))

if __name__ == "__main__":
    main()

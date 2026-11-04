#!/usr/bin/env python3
"""C2_TAB_build.py -- rerun C2: tables for corrected, corrected2 (31 codes) and the final baseline
corrected2x (30 codes), with the the authors' table decisions, and a four-column reconciliation.

Reuses TAB_build.py (TAB step) unchanged as a module: its manuscript parser, cell builder and formatting.
No estimation; every number comes from stored outputs of the same code run per vintage.
Decisions applied to corrected, corrected2 and corrected2x (authors' working notes):
  * Table 7 Panel F, directed-pair-trend rows: estimates and N from separation(fe simplex ir mu)
    (A1.8 rows T7_pair_sepmu); the default-run N is kept in the source column.
  * Table 5 cols (3)-(4) main coefficients: cultural distance centred on the realized estimation sample of
    each model (A2.5 cd_own_real "mobility slope at realized-sample mean"); interactions unchanged.
  * Table 7 Panel B: the obsolete Paraguay unit-break row is replaced by the joint data-quality exclusion
    row (A1.5 x_clean_sw2 = "clean measurement" of A1.5 (vi) plus the SWEEP2 definitional flags, addendum 3 d).
The submitted vintage is regenerated exactly as before (control against the printed manuscript, 211 cells).
Input-safety switch (2026-11-03 ~23:55): COPY 05_output/03_Mobility is read from the unchanged snapshot
pre_C14_ref; corrected2/corrected2x upper-bound and Weidner-Zylkin rows come from TAB_02.do / C2_02_bias.do.
Outputs: 06_results/tables/Table*.csv (corrected), corrected2/Table*.csv, final/Table*.csv (corrected2x),
RECONCILIATION.csv (submitted as printed, corrected, corrected2, final), TAB_control_report.csv,
C2_TAB_notes.csv (note texts). The TAB v1 files are moved to tables_revised/archive_TAB_v1/ first.
Usage: python3 C2_TAB_build.py
"""
import importlib.util, os, re, shutil, sys
import pandas as pd

CODE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("TB", os.path.join(CODE, "TAB_build.py"))
TB = importlib.util.module_from_spec(spec)
spec.loader.exec_module(TB)

W, OUTD, TR, PKG = TB.W, TB.OUTD, TB.TR, TB.PKG
# corrected chapter outputs of this package (the analysis run read the same files from a frozen snapshot)
SNAP = TB.COPY
# vintage switch (replication package): default = final tables only (vintage corrected2x); the reconciliation
# (submitted, corrected, corrected2, corrected2x, RECONCILIATION.csv, TAB_control_report.csv) runs with --reconciliation
RECON = "--reconciliation" in sys.argv[1:]
VINTS = ["corrected", "corrected2", "corrected2x"]
VLAB = {"corrected": "corrected", "corrected2": "corrected2", "corrected2x": "final"}
FOLDER = {"corrected": TR, "corrected2": TR + "/corrected2", "corrected2x": TR + "/final"}
T7 = "7"
OLD_B = "Excluding unit-break reporter-years (Paraguay, 2020–2021)"
NEW_B = "Excluding flagged data-quality cells (clean measurement)"
NOTE_TEXT = {
    "7 Panel F": "Directed-pair-trend rows: the default iterated-rectifier separation check stops at its iteration limit in trend models; the mu method removes the separated observations without changing the estimates (N from separation(fe simplex ir mu)).",
    "5": "Cultural distance is centred at its mean over the estimation sample of each model.",
    "7 Panel B": "The data-quality row excludes the accommodation-based tourist series of Slovakia and Slovenia, all pairs with Paraguay, 36 importer-years that report an HS dataset without basket rows, constructed zeros (South Sudan 2011-12; Curaçao, Bonaire and Saint Maarten 2007-10), 15 importer-years re-released after the download, and the definitional mobility series (Section 3.6) (visitors: Rep. of Moldova 2007-15, Kazakhstan residence 2020-21, Saudi Arabia, South Africa and Norway residence, and Bolivia (Plurinational State of) nationality 2020-21; tourists: Belarus 2007-20, Kazakhstan residence 2020-21).",
}


class V2(TB.V):
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
        self.pct = {n: TB.load_pc_table(f"{d}/pc/tables/{f}") for n, f in {
            "2": "table2_baseline_regression.csv", "3": "table3_dynamic_future_checks.csv",
            "4": "table4_category_heterogeneity.csv", "5": "table5_moderators.csv",
            "6": "table6_robustness.csv", "A1": "tableA1_positive_trade_presence.csv"}.items()}
        self.diag = pd.read_csv(f"{d}/pc/diag/moderator-influence-results.csv").set_index("result")["value"].astype(float)
        if v == "submitted":
            self.ub = pd.read_csv(f"{PKG}/07_results/01_core/UB/diagnostics/baseline-key-results.csv").set_index("result")["value"].astype(float)
            self.bias = pd.read_csv(f"{PKG}/07_results/02_sensitivity/03_ppml_bias_correction/diagnostics/ppml_bias_correction_results.csv").set_index("measure")
            self.ub_src = "PKG/07_results/01_core/UB/diagnostics/baseline-key-results.csv"
            self.bias_src = "PKG/07_results/02_sensitivity/03_ppml_bias_correction/diagnostics/ppml_bias_correction_results.csv"
        elif v == "corrected":
            self.ub = pd.read_csv(f"{SNAP}/05_output/03_Mobility/01_diagnostics/core/UB/baseline-key-results.csv").set_index("result")["value"].astype(float)
            self.bias = pd.read_csv(f"{SNAP}/05_output/03_Mobility/01_diagnostics/sensitivity/03_ppml_bias_correction/ppml_bias_correction_results.csv").set_index("measure")
            self.ub_src = "stored output of the corrected build (05_output/03_Mobility/01_diagnostics/core/UB/baseline-key-results.csv)"
            self.bias_src = "stored output of the corrected build (05_output/03_Mobility/01_diagnostics/sensitivity/03_ppml_bias_correction/ppml_bias_correction_results.csv); reproduced by C2_02_bias.do"
        else:
            ub = {}
            for line in open(f"{d}/TAB_02_{v}.log", encoding="utf-8", errors="replace"):
                m = re.match(r"^TAB_UB (vis|tour) b=\s*(\S+) se=\s*(\S+) N=(\d+)", line)
                if m:
                    k = "visitor" if m.group(1) == "vis" else "tourist"
                    ub[k + "_b"], ub[k + "_se"], ub[k + "_n"] = float(m.group(2)), float(m.group(3)), float(m.group(4))
            assert len(ub) == 6, ub
            self.ub = pd.Series(ub)
            self.bias = pd.read_csv(f"{d}/C2_bias_results.csv").set_index("measure")
            self.ub_src = f"out/{v}/TAB_02_{v}.log lines TAB_UB (TAB_02.do on this vintage; 9 decimals)"
            self.bias_src = f"out/{v}/C2_bias_results.csv (original 03_ppml_bias_correction.do run by C2_02_bias.do)"


def build2(vv):
    C = TB.build(vv)
    v = vv.v
    if v == "submitted":
        return C
    mn = {"vis": "mob_bilat_vis", "tour": "mob_bilat_tour"}
    for ms_, ci in (("vis", 1), ("tour", 2)):
        # Panel F pair trends: mu separation
        rid = f"A1.8.T7_pair_sepmu.{ms_}.lead_bilat_{ms_}"
        rd = f"A1.8.T7_pair.{ms_}.lead_bilat_{ms_}"
        r, r0 = vv.a1(rid), vv.a1(rd)
        z90 = 1.6448536269514722
        lo, hi = r.b - z90 * r.se, r.b + z90 * r.se
        C[(T7, "Lead mobility, pair trends", ci)] = TB.Cell(
            f"{TB.f3(r.b)}{TB.stars(r.p)} ({TB.f3(r.se, minus=False)}) N = {TB.fN(r.N)} [{TB.f3(lo)}, {TB.f3(hi)}]",
            {"b": float(r.b), "se": float(r.se), "p": float(r.p), "N": float(r.N), "lo": float(lo), "hi": float(hi)},
            vv.a1src(rid) + f" (separation(fe simplex ir mu)); default-separation run: b {r0.b:.6f}, N = {TB.fN(r0.N)} ({vv.a1src(rd)})")
        # Panel B: joint data-quality exclusion
        rid = f"A1.5.x_clean_sw2.{ms_}.{mn[ms_]}"
        r = vv.a1(rid)
        C[(T7, NEW_B, ci)] = TB.Cell(TB.cell_bse(r.b, r.se, r.p, r.N), TB.full_bse(r, r.N), vv.a1src(rid))
    # audit check: Table 1 values of 1e8 or more printed as integers with comma separators (TAB_build.py f1
    # prints "m × 10 e", which loses the exponent marker); the submitted regeneration keeps TAB_build's format
    for k in list(C):
        if k[0] == "1" and k[2] >= 2 and "b" in C[k].full and abs(C[k].full["b"]) >= 1e8:
            C[k] = TB.Cell(f"{C[k].full['b']:,.0f}", C[k].full, C[k].src)
    # author decision 2026-11-04: Table A1 (linear-probability coefficients) printed with 4 decimals for the
    # coefficient and SE in every cell; full-precision values from positive_controls.csv (TA1.c<k>.*);
    # significance stars kept from the original esttab string (no recomputation)
    for k, lab in ((1, "Bilateral visitors"), (2, "Bilateral tourists")):
        key = ("A1", "Mobility coefficient", k)
        b_ = float(vv.PC[f"TA1.c{k}.{lab}.b"]); se_ = float(vv.PC[f"TA1.c{k}.{lab}.se"])
        st = TB.parse_cell(C[key].s)[0].get("stars", "")
        C[key] = TB.Cell(f"{TB.f3(b_, d=4)}{st} ({TB.f3(se_, d=4, minus=False)})", {"b": b_, "se": se_},
                         C[key].src + f"; printed at 4 decimals from PC items TA1.c{k}.{lab}.b/.se")
    # panel item 3.18: Table A2 coefficients carry stars from the normal p of b/se (two-sided), every row
    from math import erfc, sqrt
    for k in list(C):
        if k[0] == "A2" and k[2] == 2:
            bb = float(C[k].full["b"])
            se_key = (k[0], k[1], 3)
            ss = float(C[se_key].full["b"])
            pz = erfc(abs(bb / ss) / sqrt(2.0))
            C[k] = TB.Cell(f"{TB.f3(bb, d=3)}{TB.stars(pz)}", {"b": bb, "p": pz}, C[k].src + "; stars from the normal p of b/se")
    # Table 5 cols 3-4: realized-sample centring
    for lab, ci, mob in (("Bilateral visitors", 3, "visitors"), ("Bilateral tourists", 4, "tourists")):
        r = vv.a2("cd_own_real", "mobility slope at realized-sample mean", mobility=mob, item="A2.5")
        C[("5", lab, ci)] = TB.Cell(f"{TB.f3(r.b)}{TB.stars(r.p)} ({TB.f3(r.se, minus=False)})", {"b": float(r.b), "se": float(r.se), "p": float(r.p)},
                                    vv.a2src(r) + " (cultural distance centred on the realized estimation sample)")
    return C


def fmt(val, dd, kx, t, statname, cellstr):
    if val is None:
        return ""
    if kx == "N":
        return f"{int(val):,}"
    if t == "1" and (statname == "max" or abs(val) >= 1e8):
        return cellstr
    dd = max(dd, 0)
    return f"{val:,.{dd}f}" if t == "1" else f"{val:.{dd}f}"


def changed(a, b, fa, fb, kx, dd):
    if a is None or b is None:
        return "yes (cell structure differs)"
    if kx == "N":
        return "yes" if b != a else "no"
    unit = 10 ** (-dd)
    if fa is not None and fb is not None:
        return "yes" if abs(fb - fa) >= unit - 1e-12 else "no"
    return "yes" if abs(b - a) > unit * (1 + 1e-9) else "no"


def fget(dct, fk):
    if fk in dct:
        return dct[fk]
    if fk == "b":
        for alt in ("p", "r2"):
            if alt in dct:
                return dct[alt]
    return None


def main():
    ms = TB.read_ms_tables()
    if RECON:
        VV = {"submitted": V2("submitted")}
        for v in VINTS:
            VV[v] = V2(v)
    else:
        # final tables only: every vintage name refers to corrected2x, so the table layout, the cell lookup and the
        # cell builder run unchanged; only the corrected2x tables are written (no control, no reconciliation)
        _final = V2("corrected2x")
        VV = {n: _final for n in ["submitted"] + VINTS}
    CELLS = {v: build2(VV[v]) for v in VV}
    NOTES = {v: TB.notes(VV[v]) for v in VV}
    ctrl, recon, tabout = [], [], {v: {} for v in VINTS}
    for t in TB.CAPTIONS:
        rows = ms[t]
        header = [h.replace("*", "") for h in rows[0]]
        ncol, nlab = len(header), TB.LABELCOLS.get(t, 1)
        outs = {v: [header + ["source"]] for v in VINTS}
        for cells in rows[1:]:
            cells = cells + [""] * (ncol - len(cells))
            rk = TB.norm_key(t, TB.rowkey(t, cells))
            replaced = (t == T7 and rk == OLD_B)
            new = {v: list(cells) for v in VINTS}
            if replaced:
                for v in VINTS:
                    new[v][0] = NEW_B
            srcs = {v: [] for v in VINTS}
            for ci in range(nlab, ncol):
                printed = cells[ci]
                if printed in ("", "—"):
                    continue
                key = (t, rk, ci)
                if key not in CELLS["submitted"]:
                    alt = [k2 for k2 in CELLS["submitted"] if k2[0] == t and TB.norm_key(t, k2[1]) == rk and k2[2] == ci]
                    key = alt[0] if alt else None
                assert key is not None, ("no cell", t, rk, ci)
                sc = CELLS["submitted"][key]
                vkey = (T7, NEW_B, ci) if replaced else key
                vc = {v: CELLS[v][vkey] for v in VINTS}
                for v in VINTS:
                    new[v][ci] = vc[v].s
                    srcs[v].append(vc[v].src)
                # control: regenerated submitted vs printed (unchanged rule of TAB_build.py)
                pp, pdc = TB.parse_cell(printed)
                ps, _ = TB.parse_cell(sc.s)
                ok, why = True, []
                for kx in set(pp) | set(ps):
                    if kx == "stars":
                        if pp.get(kx, "") != ps.get(kx, ""):
                            ok = False; why.append(f"stars {pp.get(kx,'')!r} vs {ps.get(kx,'')!r}")
                    else:
                        a, b = pp.get(kx), ps.get(kx)
                        if a is None or b is None or abs(a - b) > 1e-9 * max(1.0, abs(b)):
                            ok = False; why.append(f"{kx}: printed {a} vs regenerated {b}")
                ctrl.append({"table": TB.CAPTIONS[t], "row": rk, "col": header[ci], "printed_manuscript": printed,
                             "regenerated_submitted": sc.s, "control": "PASS" if ok else "FAIL", "detail": "; ".join(why),
                             "source_submitted": sc.src})
                pv = {v: TB.parse_cell(vc[v].s) for v in VINTS}
                if t == "1" and ci >= 2:
                    # R2-03: an integer with commas parses as N; in Table 1 statistic columns it is a value
                    for v in VINTS:
                        if "N" in pv[v][0] and "b" not in pv[v][0]:
                            pv[v] = ({"b": pv[v][0]["N"]}, {"b": 0})
                order = ['b', 'se', 'p', 'chi2', 'df', 'lo', 'hi', 'N', 'stars']
                keys = [k for k in order if k in pp or any(k in pv[v][0] for v in VINTS)]
                for kx in keys:
                    dd = pdc.get(kx, pv["corrected2x"][1].get(kx, pv["corrected"][1].get(kx, 3)))
                    rowd = {"table": TB.CAPTIONS[t], "row": rk if not replaced else f"{OLD_B} -> replaced by: {NEW_B}",
                            "column": header[ci]}
                    if kx == "stars":
                        a = pp.get("stars", "")
                        vals = {v: pv[v][0].get("stars", "") for v in VINTS}
                        if not (a or any(vals.values())):
                            continue
                        rowd.update({"statistic": "significance stars", "submitted_as_printed": a or "none"})
                        for v in VINTS:
                            rowd[f"{VLAB[v]}_value"] = vals[v] or "none"
                        rowd["changed_corrected_vs_submitted"] = "row replaced" if replaced else ("yes" if (a or "") != vals["corrected"] else "no")
                        rowd["changed_corrected2_vs_corrected"] = "yes" if vals["corrected"] != vals["corrected2"] else "no"
                        rowd["changed_final_vs_corrected2"] = "yes" if vals["corrected2"] != vals["corrected2x"] else "no"
                        rowd["changed_final_vs_corrected"] = "yes" if vals["corrected"] != vals["corrected2x"] else "no"
                    else:
                        statname = {"b": "estimate", "se": "SE", "N": "N", "p": "p", "lo": "interval lower", "hi": "interval upper", "chi2": "chi2", "df": "df"}[kx]
                        if t == "1":
                            statname = "N" if kx == "N" else ["mean", "SD", "min", "max"][ci - 2]
                        elif kx == "b" and ("standard error" in header[ci].lower() or (header[ci].strip().endswith("SE") and "(SE)" not in header[ci] and "β" not in header[ci].replace("Original", "").replace("Corrected", ""))):
                            statname = "SE"
                        elif kx == "b" and (re.search(r"p\*?\s?-\s?value", rk.lower()) or re.search(r"p\*?\s?-\s?value", header[ci].lower())):
                            statname = "p"
                        a = pp.get(kx)
                        fs_ = fget(sc.full, kx)
                        vals = {v: pv[v][0].get(kx) for v in VINTS}
                        fulls = {v: fget(vc[v].full, kx) for v in VINTS}
                        rowd.update({"statistic": statname, "submitted_as_printed": fmt(a, dd, kx, t, statname, printed)})
                        dv = 4 if (t == "A1" and kx in ("b", "se")) else dd   # Table A1 printed at 4 decimals (author decision 2026-11-04)
                        for v in VINTS:
                            rowd[f"{VLAB[v]}_value"] = fmt(vals[v], dv, kx, t, statname, vc[v].s)
                        if a is not None and vals["corrected"] is not None and kx != "N":
                            rowd["difference_corrected_minus_submitted"] = f"{vals['corrected'] - a:.{max(dd,0)}f}"
                        elif a is not None and vals["corrected"] is not None:  # revision: N rows get the count difference too
                            rowd["difference_corrected_minus_submitted"] = f"{int(round(vals['corrected'] - a))}"
                        for (x, y, name) in (("corrected", "corrected2", "difference_corrected2_minus_corrected"),
                                             ("corrected2", "corrected2x", "difference_final_minus_corrected2"),
                                             ("corrected", "corrected2x", "difference_final_minus_corrected")):
                            fx = fulls[x] if fulls[x] is not None else vals[x]
                            fy = fulls[y] if fulls[y] is not None else vals[y]
                            if fx is not None and fy is not None:
                                rowd[name] = repr(float(fy - fx))
                        rowd["changed_corrected_vs_submitted"] = "row replaced" if replaced else changed(a, vals["corrected"], fs_, fulls["corrected"], kx, dd)
                        rowd["changed_corrected2_vs_corrected"] = changed(vals["corrected"], vals["corrected2"], fulls["corrected"], fulls["corrected2"], kx, dv)
                        rowd["changed_final_vs_corrected2"] = changed(vals["corrected2"], vals["corrected2x"], fulls["corrected2"], fulls["corrected2x"], kx, dv)
                        rowd["changed_final_vs_corrected"] = changed(vals["corrected"], vals["corrected2x"], fulls["corrected"], fulls["corrected2x"], kx, dv)
                        rowd["submitted_full_precision"] = "" if fs_ is None else repr(float(fs_))
                        for v in VINTS:
                            rowd[f"{VLAB[v]}_full_precision"] = "" if fulls[v] is None else repr(float(fulls[v]))
                    rowd["submitted_regenerated_control"] = "PASS" if ok else "FAIL"
                    for v in VINTS:
                        rowd[f"source_{VLAB[v]}"] = vc[v].src
                    recon.append(rowd)
            for v in VINTS:
                outs[v].append(new[v] + [TB.compress_sources(list(dict.fromkeys(srcs[v])))])
        for v in VINTS:
            tabout[v][t] = outs[v]
    # audit check: Table A3 gains an N column (N of the Weidner-Zylkin sample = preceding PPML e(N), bias file column N)
    for v in VINTS:
        rows = tabout[v]["A3"]
        hdr = rows[0]
        si = hdr.index("source")
        rows[0] = hdr[:si] + ["Observations (N)"] + hdr[si:]
        for i in range(1, len(rows)):
            meas = rows[i][0].strip().lower()
            if meas in ("visitors", "tourists"):
                n = float(VV[v].bias.loc[meas].N)
                rows[i] = rows[i][:si] + [f"{int(round(n)):,}"] + rows[i][si:]
            else:
                rows[i] = rows[i][:si] + [""] + rows[i][si:]
    for meas in ("Visitors", "Tourists"):
        rowd = {"table": "Table A3", "row": meas, "column": "Observations (N) (new column)", "statistic": "N",
                "submitted_as_printed": "(not printed)",
                "submitted_full_precision": repr(float(VV["submitted"].bias.loc[meas.lower()].N))}
        for v in VINTS:
            n = float(VV[v].bias.loc[meas.lower()].N)
            rowd[f"{VLAB[v]}_value"] = f"{int(round(n)):,}"
            rowd[f"{VLAB[v]}_full_precision"] = repr(n)
            rowd[f"source_{VLAB[v]}"] = VV[v].bias_src + f" row {meas.lower()} column N"
        rowd["changed_corrected2_vs_corrected"] = "yes" if rowd["corrected_value"] != rowd["corrected2_value"] else "no"
        rowd["changed_final_vs_corrected2"] = "yes" if rowd["corrected2_value"] != rowd["final_value"] else "no"
        rowd["changed_final_vs_corrected"] = "yes" if rowd["corrected_value"] != rowd["final_value"] else "no"
        recon.append(rowd)
    # numbers quoted in table notes
    for k in NOTES["corrected"]:
        rowd = {"table": "Table " + k[0], "row": k[1], "column": "(note)", "statistic": "value",
                "submitted_as_printed": TB.NOTES_SUB_PRINTED[k],
                "submitted_regenerated_control": "regenerated submitted: " + NOTES["submitted"][k].s}
        for v in VINTS:
            rowd[f"{VLAB[v]}_value"] = NOTES[v][k].s
            rowd[f"source_{VLAB[v]}"] = NOTES[v][k].src
        rowd["changed_corrected_vs_submitted"] = "yes" if rowd["submitted_as_printed"] != rowd["corrected_value"] else "no"
        rowd["changed_corrected2_vs_corrected"] = "yes" if rowd["corrected_value"] != rowd["corrected2_value"] else "no"
        rowd["changed_final_vs_corrected2"] = "yes" if rowd["corrected2_value"] != rowd["final_value"] else "no"
        rowd["changed_final_vs_corrected"] = "yes" if rowd["corrected_value"] != rowd["final_value"] else "no"
        recon.append(rowd)
    for k, txt in NOTE_TEXT.items():
        recon.append({"table": "Table " + k, "row": "note text (new in the revision)", "column": "(note)", "statistic": "text",
                      "submitted_as_printed": "", "corrected_value": txt, "corrected2_value": txt, "final_value": txt})
    if not RECON:
        os.makedirs(FOLDER["corrected2x"], exist_ok=True)
        for t, rows in tabout["corrected2x"].items():
            pd.DataFrame(rows[1:], columns=rows[0]).to_csv(f"{FOLDER['corrected2x']}/{TB.FILES[t]}.csv", index=False)
        pd.DataFrame([{"table": k, "note": v} for k, v in NOTE_TEXT.items()]).to_csv(f"{TR}/C2_TAB_notes.csv", index=False)
        print("final tables written:", len(tabout["corrected2x"]), "->", FOLDER["corrected2x"])
        return
    # ---- write (archive TAB v1 outputs first)
    arch = TR + "/archive_TAB_v1"
    if not os.path.exists(arch):
        os.makedirs(arch)
        for f in sorted(os.listdir(TR)):
            if f.endswith(".csv"):
                shutil.copy2(f"{TR}/{f}", f"{arch}/{f}")
    for v in VINTS:
        os.makedirs(FOLDER[v], exist_ok=True)
        for t, rows in tabout[v].items():
            pd.DataFrame(rows[1:], columns=rows[0]).to_csv(f"{FOLDER[v]}/{TB.FILES[t]}.csv", index=False)
    cols = ["table", "row", "column", "statistic", "submitted_as_printed", "corrected_value", "corrected2_value", "final_value",
            "difference_corrected_minus_submitted", "difference_corrected2_minus_corrected", "difference_final_minus_corrected2",
            "difference_final_minus_corrected", "changed_corrected_vs_submitted", "changed_corrected2_vs_corrected",
            "changed_final_vs_corrected2", "changed_final_vs_corrected", "submitted_full_precision", "corrected_full_precision",
            "corrected2_full_precision", "final_full_precision", "submitted_regenerated_control", "source_corrected",
            "source_corrected2", "source_final"]
    R = pd.DataFrame(recon).reindex(columns=cols)
    R.to_csv(f"{TR}/RECONCILIATION.csv", index=False)
    pd.DataFrame(ctrl).to_csv(f"{TR}/TAB_control_report.csv", index=False)
    pd.DataFrame([{"table": k, "note": v} for k, v in NOTE_TEXT.items()]).to_csv(f"{TR}/C2_TAB_notes.csv", index=False)
    nfail = sum(1 for c in ctrl if c["control"] == "FAIL")
    print("cells controlled:", len(ctrl), "FAIL:", nfail)
    for c in ctrl:
        if c["control"] == "FAIL":
            print("FAIL", c["table"], c["row"], c["col"], "|", c["printed_manuscript"], "|", c["regenerated_submitted"], "|", c["detail"])
    print("reconciliation rows:", len(R))
    for col in ("changed_corrected_vs_submitted", "changed_corrected2_vs_corrected", "changed_final_vs_corrected2", "changed_final_vs_corrected"):
        print(col, R[col].value_counts(dropna=False).to_dict())


if __name__ == "__main__":
    main()

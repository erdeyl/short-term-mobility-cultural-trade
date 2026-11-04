"""02a_parse_published.py -- tidy register of published numbers for the positive controls.

Called by 02_positive_controls.do (shell) with paths from 00_config.do:
  python3 02a_parse_published.py <out_csv> <PUB_TAB> <PUB_DIAG> <PUB_CS> <PUB_FE> <PUB_LOG> <PUB_CS_TAB> <PUB_FE_TAB> [lenient]
The same parser reads the reproduced outputs (argument "lenient"), so both sides are tidied identically.
Writes one row per published number: id, value, decimals, kind, source (file:line).
esttab CSV cells look like ="0.243***" / ="(0.091)" / ="20,543"; standard-error rows have an
empty label and take the label of the coefficient row above.  Read-only on all inputs.
"""
import csv
import re
import sys
from pathlib import Path

out_csv, tab, diag, cs, fe, log, cs_tab, fe_tab = sys.argv[1:9]
LENIENT = len(sys.argv) > 9 and sys.argv[9] == "lenient"  # reproduced side: absent files/items allowed, no aliases
rows = []
CELL = re.compile(r'="((?:[^"]|"")*)"')


def num(raw):
    s = raw.replace("*", "").replace(",", "").strip()
    se = s.startswith("(") and s.endswith(")")
    s = s.strip("()")
    if s == "":
        return None, None, se
    dec = len(s.split(".")[1]) if "." in s else 0
    return float(s), dec, se


def kind_of(label):
    if label == "N" or label.startswith("Original exact") or label.startswith("Stacked estimation"):
        return "N"
    if "p-value" in label.lower() or label.startswith("P-value"):
        return "p"
    if label.startswith("Adjusted R2"):
        return "r2"
    return "b"


def esttab(path, tname):
    if LENIENT and not Path(path).exists():
        return
    lines = Path(path).read_text(encoding="utf-8-sig").splitlines()
    head = CELL.findall(lines[0])
    cols = {j: int(h.strip("()")) for j, h in enumerate(head) if re.fullmatch(r"\(\d+\)", h)}
    last = None
    for i, line in enumerate(lines[2:], start=3):
        cells = CELL.findall(line)
        if not cells or cells[0].startswith("Standard errors"):
            break
        label = cells[0]
        if label:
            last = label
        for j, raw in enumerate(cells):
            if j not in cols:
                continue
            v, dec, se = num(raw)
            if v is None:
                continue
            lab = last if (se and not label) else label
            k = "se" if se else kind_of(lab)
            rows.append({"id": f"{tname}.c{cols[j]}.{lab}.{k}", "value": repr(v), "decimals": dec, "kind": k,
                         "source": f"{path}:{i}"})


def keyval(path, prefix, keycols, valcol):
    if LENIENT and not Path(path).exists():
        return
    with open(path, encoding="utf-8-sig", newline="") as fh:
        rd = csv.DictReader(fh)
        for i, r in enumerate(rd, start=2):
            for vc in ([valcol] if isinstance(valcol, str) else valcol):
                s = (r.get(vc) or "").strip()
                if s == "" or not re.fullmatch(r"[-+0-9.eE]+", s):
                    continue
                key = ".".join(r[k].strip() for k in keycols)
                name = prefix + (f".{key}" if key else "") + ("" if isinstance(valcol, str) else f".{vc}")
                integer = re.fullmatch(r"[-+]?[0-9]+", s) is not None
                dec = 0 if integer else (len(s.split(".")[1]) if "." in s and "e" not in s.lower() else 16)
                kd = "N" if integer else ("p" if name.endswith("_p") else "b")
                rows.append({"id": name, "value": repr(float(s)), "decimals": dec, "kind": kd, "source": f"{path}:{i}"})


esttab(f"{tab}/table2_baseline_regression.csv", "T2")
esttab(f"{tab}/table3_dynamic_future_checks.csv", "T3")
esttab(f"{tab}/table4_category_heterogeneity.csv", "T4")
esttab(f"{tab}/table5_moderators.csv", "T5")
esttab(f"{tab}/table6_robustness.csv", "T6")
esttab(f"{tab}/tableA1_positive_trade_presence.csv", "TA1")
esttab(cs_tab, "CS")
esttab(fe_tab, "FE")
keyval(f"{diag}/baseline-key-results.csv", "BKR", ["result"], "value")
keyval(f"{diag}/core_validation_summary.csv", "CVS", ["metric"], "value")
keyval(f"{diag}/moderator-influence-results.csv", "MIR", ["result"], "value")
keyval(f"{diag}/support-ledger.csv", "SUP", ["measure"], "N")
keyval(f"{diag}/category-value-shares.csv", "SHR", ["category", "support"], "share_percent")
keyval(f"{cs}/common_support_ledger.csv", "CSL", ["stage"], "N")
keyval(f"{cs}/common_support_key_results.csv", "CSK", ["model", "support"], ["b", "se", "N"])
keyval(f"{fe}/formal_equality_results.csv", "FER", [], ["common_N", "stacked_N", "visitor_b", "visitor_se",
       "tourist_b", "tourist_se", "difference", "difference_se", "difference_p", "equality_chi2", "equality_p"])

pat = {
    "LOG.FUTURE_VISITOR_P": r"^FUTURE_VISITOR_P=\s*([-0-9.]+)",
    "LOG.FUTURE_TOURIST_P": r"^FUTURE_TOURIST_P=\s*([-0-9.]+)",
    "LOG.CATEGORY_EQUALITY.mob_bilat_vis": r"^CATEGORY_EQUALITY mobility=mob_bilat_vis P=\s*([-0-9.]+)",
    "LOG.CATEGORY_EQUALITY.mob_bilat_tour": r"^CATEGORY_EQUALITY mobility=mob_bilat_tour P=\s*([-0-9.]+)",
    "LOG.VISITOR_TOURIST_HIERARCHY_VIOLATIONS": r"^VISITOR_TOURIST_HIERARCHY_VIOLATIONS=\s*([0-9]+)",
}
found = {}
for i, line in enumerate(Path(log).read_text(encoding="utf-8", errors="replace").splitlines(), start=1):
    for k, p in pat.items():
        m = re.match(p, line)
        if m and k not in found:
            s = m.group(1)
            found[k] = 1
            kd = "N" if k.endswith("VIOLATIONS") else "p"
            dec = len(s.split(".")[1]) if "." in s else 0
            rows.append({"id": k, "value": repr(float(s)), "decimals": dec, "kind": kd, "source": f"{log}:{i}"})
missing = sorted(set(pat) - set(found))
assert LENIENT or not missing, f"log items not found: {missing}"

# aliases: sample-flag counts must equal the published N of the model that defines them
alias = {"FLAG.s_base_vis": "T2.c1.N.N", "FLAG.s_base_tour": "T2.c5.N.N", "FLAG.s_dyn_vis": "T3.c1.N.N",
         "FLAG.s_dyn_tour": "T3.c2.N.N", "FLAG.s_lang_vis": "T5.c1.N.N", "FLAG.s_lang_tour": "T5.c2.N.N",
         "FLAG.s_cd_vis": "T5.c3.N.N", "FLAG.s_cd_tour": "T5.c4.N.N", "FLAG.s_cs_exact": "CSL.exact_realized_common_rows"}
byid = {r["id"]: r for r in rows}
assert len(byid) == len(rows), "duplicate published ids"
for a, src in ({} if LENIENT else alias).items():
    r = dict(byid[src])
    r["id"] = a
    rows.append(r)

with open(out_csv, "w", newline="", encoding="utf-8") as fh:
    w = csv.DictWriter(fh, fieldnames=["id", "value", "decimals", "kind", "source"])
    w.writeheader()
    w.writerows(rows)
print(f"PUBLISHED_ITEMS={len(rows)}")

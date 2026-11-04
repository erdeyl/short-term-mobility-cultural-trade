"""A1_names.py -- ISO3 -> UN designation map for author-facing lists (analysis block A1, 2026-11-03).

Source: UN Comtrade reference file partnerAreas.json in the STUDENT raw tree (identical
reference content in COPY per PREP_NOTES.md). For each ISO3 code the non-group record with
the latest entryEffectiveDate is used (e.g. SDN: 729 "Sudan" rather than 736 "Sudan (...2011)").
Terminology overrides (binding): TWN -> "Taiwan Province of China (TWN)";
HKG/MAC/PSE keep the UN Comtrade designations "China, Hong Kong SAR", "China, Macao SAR",
"State of Palestine" (asserted). Output: 05_output/10_analysis/A1_un_names.csv (iso3, name_un, name_source).
Usage: python3 -I A1_names.py <partnerAreas.json> <out.csv>
"""
import csv
import json
import sys

src, out = sys.argv[1], sys.argv[2]
with open(src, encoding="utf-8") as fh:
    d = json.load(fh)
rows = d["results"] if isinstance(d, dict) else d
best = {}
for r in rows:
    iso = r.get("PartnerCodeIsoAlpha3") or ""
    if len(iso) != 3 or not iso.isalpha() or not iso.isupper() or r.get("isGroup"):
        continue
    key = r.get("entryEffectiveDate") or ""
    if iso not in best or key > best[iso][0]:
        best[iso] = (key, r["PartnerDesc"], r["PartnerCode"])
names = {k: (v[1], f"UN Comtrade partnerAreas.json code {v[2]}") for k, v in best.items()}
assert names["HKG"][0] == "China, Hong Kong SAR", names["HKG"]
assert names["MAC"][0] == "China, Macao SAR", names["MAC"]
assert names["PSE"][0] == "State of Palestine", names["PSE"]
names["TWN"] = ("Taiwan Province of China (TWN)", "UNSD designation")
with open(out, "w", newline="", encoding="utf-8") as fh:
    w = csv.writer(fh)
    w.writerow(["iso3", "name_un", "name_source"])
    for k in sorted(names):
        w.writerow([k, names[k][0], names[k][1]])
print(f"A1_NAMES_PASS rows={len(names)}")

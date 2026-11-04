from pathlib import Path
import json
import pandas as pd
from pandas.io.stata import StataReader
from _paths import *

ensure_dirs()
cfg = json.loads((CONFIG/"variables_and_provenance.json").read_text(encoding="utf-8"))

missing = [p for p in [GRAVITY, COUNTRIES] if not p.exists()]
if missing:
    print("MISSING CEPII RAW SOURCE FILES:")
    for p in missing:
        print(" -", p)
    print()
    print("Copy the two ORIGINAL CEPII files into:")
    print(RAW)
    print("Required filenames:")
    print(" - Gravity_V202211.dta")
    print(" - Countries_V202211.dta")
    raise SystemExit(1)

def metadata(path):
    with StataReader(path, convert_categoricals=False) as r:
        labels = r.variable_labels()
        data_label = r.data_label
        value_labels = r.value_labels()
    inv = pd.DataFrame({
        "variable": list(labels.keys()),
        "variable_label": list(labels.values())
    })
    return inv, data_label, value_labels

g_inv, g_label, g_value_labels = metadata(GRAVITY)
c_inv, c_label, c_value_labels = metadata(COUNTRIES)

g_inv.to_csv(DIAG/"gravity_variable_inventory.csv", index=False, encoding="utf-8-sig")
c_inv.to_csv(DIAG/"countries_variable_inventory.csv", index=False, encoding="utf-8-sig")

# Value-label archive (important for rta_type and other labelled categorical fields).
vl_rows = []
for dataset_name, vld in [("Gravity_V202211.dta", g_value_labels),
                           ("Countries_V202211.dta", c_value_labels)]:
    for labelset, mapping in vld.items():
        for code_value, text in mapping.items():
            vl_rows.append({
                "dataset": dataset_name,
                "label_set": labelset,
                "code": code_value,
                "label": text
            })
pd.DataFrame(vl_rows).to_csv(
    DIAG/"stata_value_labels.csv", index=False, encoding="utf-8-sig"
)

required = cfg["required_core"]
available = set(g_inv["variable"])
presence = pd.DataFrame([
    {
        "variable": v,
        "required": 1 if v in required else 0,
        "present": 1 if v in available else 0
    }
    for v in required + cfg["optional_keep"]
])
presence.to_csv(DIAG/"required_variable_presence.csv", index=False, encoding="utf-8-sig")

missing_required = [v for v in required if v not in available]
if missing_required:
    raise RuntimeError(
        "Gravity_V202211.dta is missing required variables: "
        + ", ".join(missing_required)
    )

manifest = pd.DataFrame([
    {
        "source_file": GRAVITY.name,
        "relative_path": GRAVITY.relative_to(ROOT).as_posix(),
        "bytes": GRAVITY.stat().st_size,
        "release": "V202211",
        "source_url": cfg["official_page"],
        "role": "Main CEPII Gravity source dataset"
    },
    {
        "source_file": COUNTRIES.name,
        "relative_path": COUNTRIES.relative_to(ROOT).as_posix(),
        "bytes": COUNTRIES.stat().st_size,
        "release": "V202211",
        "source_url": cfg["official_page"],
        "role": "CEPII territorial-configuration/country reference dataset"
    }
])
manifest.to_csv(DIAG/"source_manifest.csv", index=False, encoding="utf-8-sig")

summary = pd.DataFrame([
    {"item":"gravity_data_label","value":g_label},
    {"item":"countries_data_label","value":c_label},
    {"item":"gravity_variable_count","value":len(g_inv)},
    {"item":"countries_variable_count","value":len(c_inv)},
    {"item":"release","value":"V202211"},
    {"item":"official_page","value":cfg["official_page"]},
    {"item":"documentation","value":cfg["documentation"]},
])
summary.to_csv(DIAG/"source_metadata_summary.csv", index=False, encoding="utf-8-sig")

print("CEPII_SOURCE_ARCHIVE_AND_SCHEMA=PASS")
print("Replication root detected automatically:")
print(ROOT)
print("Gravity variables:", len(g_inv))
print("Countries variables:", len(c_inv))

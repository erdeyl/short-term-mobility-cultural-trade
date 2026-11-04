import json
import pandas as pd
from pandas.io.stata import StataReader
from _paths import *

ensure_dirs()
spec = json.loads((CONFIG/"master_construction_specification.json").read_text(encoding="utf-8"))

sources = {
    "UN_Tourism": TOURISM,
    "Common_base": COMMON_BASE,
    "Hofstede": HOFSTEDE,
}

missing = [str(p) for p in sources.values() if not p.exists()]
if missing:
    print("MISSING FINAL SOURCE TABLES:")
    for p in missing:
        print(" -", p)
    raise SystemExit(1)

def vars_of(path):
    with StataReader(path, convert_categoricals=False) as r:
        return list(r.variable_labels().keys()), r.data_label

requirements = {
    "UN_Tourism": [
        "reporter_area_code","partner_area_code","year",
        "tourists_k","tourists_trips","tourists_basis",
        "visitors_k","visitors_trips","visitors_basis",
        "basis_mismatch","hierarchy_violation","visitors_definition_diff"
    ],
    "Common_base": [
        "year","iso3_o","iso3_d","iso3num_o","iso3num_d",
        "v_ttl_lb_k","v_ttl_ub_k","v_8523_lb_k","v_8523_ub_k",
        "dist","contig","comlang_off","comcol","col45","comrelig","fta_wto",
        "comtrade_reporting_available","comtrade_sparse_row_present","comtrade_zero_fill_sparse"
    ],
    "Hofstede": [
        "iso3_o","iso3_d",
        "cd6_ge4","cd6_strict","cd4_ks","common_dim_count6",
        "regional_proxy_flag_o","regional_proxy_flag_d","any_regional_proxy"
    ],
}

rows = []
for name, path in sources.items():
    vars_, label = vars_of(path)
    missing_vars = [v for v in requirements[name] if v not in vars_]
    rows.append({
        "source": name,
        "relative_path": path.relative_to(ROOT).as_posix(),
        "variable_count": len(vars_),
        "required_variable_count": len(requirements[name]),
        "missing_required_count": len(missing_vars),
        "missing_required_variables": ";".join(missing_vars),
        "stata_data_label": label,
    })
    if missing_vars:
        raise RuntimeError(f"{name} missing required variables: {missing_vars}")

pd.DataFrame(rows).to_csv(
    MASTER_DIAG/"master_source_schema_audit.csv",
    index=False, encoding="utf-8-sig"
)

print("MASTER_SOURCE_TABLE_SCHEMA=PASS")
for name, path in sources.items():
    print(name, "->", path)

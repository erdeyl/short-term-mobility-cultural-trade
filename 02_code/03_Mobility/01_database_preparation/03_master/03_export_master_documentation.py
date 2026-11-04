import json
import pandas as pd
from _paths import *

ensure_dirs()
spec = json.loads((CONFIG/"master_construction_specification.json").read_text(encoding="utf-8"))
src = CHAPTER_MERGED
if not src.exists():
    raise SystemExit("Run master build first.")

df = pd.read_stata(src, convert_categoricals=False)

note = f"""MASTER PANEL CONSTRUCTION NOTE

Backbone:
    {spec['backbone']}

Analysis window:
    {spec['analysis_years'][0]}-{spec['analysis_years'][1]}

Main universe:
    {spec['main_universe']}

Direction:
    iso3_o = exporter/origin economy i
    iso3_d = importer/destination economy j

UN Comtrade:
    reporter = iso3_d
    partner1 = iso3_o
    {spec['comtrade_zero_rule']}

UN Tourism:
    reporter/destination = iso3_o
    partner/origin = iso3_d
    Therefore the merged mobility variable is tourism flow j -> i for trade i -> j.
    {spec['tourism_missing_rule']}

Hofstede:
    {spec['hofstede_time_rule']}

FTA/RTA:
    retained from CEPII Gravity V202211.

Upstream-choice policy:
    {spec['baseline_choice_policy']}

The master construction does not compare against or target any historical manuscript database.
"""
(MASTER_DIAG/"MASTER_CONSTRUCTION_NOTE.txt").write_text(note, encoding="utf-8")

# Compact data dictionary derived from final variables.
rows = []
for c in df.columns:
    source = "master/derived"
    if c in {
        "contig","dist","comlang_off","col_dep_ever","comleg_posttrans",
        "fta_wto","fta_wto_raw","rta_coverage","rta_type",
        "country_id_o","country_id_d","iso3_o","iso3_d","iso3num_o","iso3num_d"
    }:
        source = "CEPII Gravity V202211"
    elif c.startswith("v_") or c.startswith("comtrade_") or c in {
        "trade_reporting_available","hs_version","n_source_rows","n_unreported_rows","any_unreported"
    }:
        source = "UN Comtrade clean rebuild"
    elif c.startswith("tourist") or c.startswith("visitor") or c in {
        "basis_mismatch","same_basis","hierarchy_violation",
        "hierarchy_audit_class","visitors_definition_diff"
    }:
        source = "UN Tourism clean rebuild"
    elif c.startswith("cd") or c.startswith("regional_proxy") or c in {
        "common_dim_count6","any_regional_proxy","hofstede_pair_present"
    }:
        source = "Hofstede clean rebuild"

    rows.append({
        "variable":c,
        "dtype":str(df[c].dtype),
        "source_module":source,
        "nonmissing":int(df[c].notna().sum()),
    })

pd.DataFrame(rows).to_csv(
    MASTER_DIAG/"master_variable_inventory.csv",
    index=False, encoding="utf-8-sig"
)

print("MASTER_DOCUMENTATION_EXPORT=PASS")

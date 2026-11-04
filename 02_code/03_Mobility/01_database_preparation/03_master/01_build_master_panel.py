import re
import numpy as np
import pandas as pd
from _paths import *
from data_checks import assert_base_preserved, save_stata
ensure_dirs()
import importlib.util  # RESCUE C11b C11c C09-M
_rescue_path = ROOT / "02_code/99_rescue/rescue_switch.py"  # RESCUE C11b C11c C09-M
if _rescue_path.is_file():  # RESCUE I-M2 F4
    _rescue_spec = importlib.util.spec_from_file_location("rescue_switch", _rescue_path)  # RESCUE I-M2 F4
    rescue_switch = importlib.util.module_from_spec(_rescue_spec)  # RESCUE I-M2 F4
    _rescue_spec.loader.exec_module(rescue_switch)  # RESCUE I-M2 F4
else:  # RESCUE I-M2 F4
    class _RescueOff:  # RESCUE I-M2 F4
        @staticmethod  # RESCUE I-M2 F4
        def enabled(_identifier):  # RESCUE I-M2 F4
            return False  # RESCUE I-M2 F4
    rescue_switch = _RescueOff()  # RESCUE I-M2 F4
master = pd.read_stata(COMMON_BASE,convert_categoricals=False)
def clean_iso(s):
    return s.fillna('').astype(str).str.upper().str.strip()
def int_code(s):
    return pd.to_numeric(s,errors='coerce').astype('Int64')
for col in ['iso3num_o','iso3num_d']:
    master[col] = int_code(master[col])
# ============================================================
# 4. UN TOURISM
# ============================================================
tour = pd.read_stata(TOURISM, convert_categoricals=False)

# Direction is intentional:
# Tourism reporter = destination of tourism flow = trade exporter/origin i.
# Tourism partner  = origin of tourism flow      = trade importer/destination j.
tour = tour.rename(columns={
    "reporter_area_code":"iso3num_o",
    "partner_area_code":"iso3num_d",
    "reporter_area_label":"tourism_destination_label",
    "partner_area_label":"tourism_origin_label",
})
tour["iso3num_o"] = int_code(tour["iso3num_o"])
tour["iso3num_d"] = int_code(tour["iso3num_d"])
tour["year"] = pd.to_numeric(tour["year"], errors="raise").astype(int)

tour_keep = [
    "year","iso3num_o","iso3num_d",
    "tourism_destination_label","tourism_origin_label",
    "tourists_k","tourists_trips","tourists_basis",
    "visitors_k","visitors_trips","visitors_basis",
    "tourists_res_k","tourists_nat_k","visitors_res_k","visitors_nat_k",
    "basis_mismatch","same_basis","hierarchy_violation",
    "hierarchy_audit_class","visitors_definition_diff",
    "tourists_fractional_trip","visitors_fractional_trip"
]
rescue_tour_fields = []  # RESCUE C11b C11c
if rescue_switch.enabled("C11b"):  # RESCUE C11b
    rescue_tour_fields += ["conf_sub", "visitors_source_file", "visitors_flag", "visitors_flag_label", "visitors_notes", "visitors_release"]  # RESCUE C11b
if rescue_switch.enabled("C11c"):  # RESCUE C11c
    rescue_tour_fields += [f"{m}_{v}" for m in ["tourists", "visitors"] for v in ["source_file", "flag", "flag_label", "notes", "release"]]  # RESCUE C11c
    rescue_tour_fields += [f"{m}_{v}" for m in ["tour", "vis"] for v in ["start", "end", "span2020", "study_switch"]]  # RESCUE C11c
if rescue_switch.enabled("C12"):  # RESCUE C12
    rescue_tour_fields += ["pry_res_quarantine"]  # RESCUE C12
for field in dict.fromkeys(rescue_tour_fields):  # RESCUE C11b C11c
    if field not in tour.columns:  # RESCUE C11b C11c
        raise RuntimeError(f"Required rescue tourism metadata missing: {field}; rebuild UN Tourism.")  # RESCUE C11b C11c
    if field not in tour_keep:  # RESCUE C11b C11c
        tour_keep.append(field)  # RESCUE C11b C11c
tour_keep = [c for c in tour_keep if c in tour.columns]
tour = tour[tour_keep].copy()

if tour.duplicated(["year","iso3num_o","iso3num_d"]).any():
    raise RuntimeError("UN Tourism final table is not unique by reporter-partner-year.")

master = master.merge(
    tour,
    on=["year","iso3num_o","iso3num_d"],
    how="left",
    validate="1:1",
    indicator="_m_tourism"
)
master["tourism_pair_row_present"] = master["_m_tourism"].eq("both").astype("int8")
master["tourists_observed"] = master["tourists_k"].notna().astype("int8")
master["visitors_observed"] = master["visitors_k"].notna().astype("int8")

# CRITICAL: no missing-to-zero conversion for tourism.
# Absence is preserved as missing because the UN Tourism bilateral reporting universe
# is not treated as a complete zero-filled matrix.

if rescue_switch.enabled("C09-M"):  # RESCUE C09-M
    master["france251_component_o"] = master["iso3_o"].isin(["MCO", "GUF"]).astype("int8")  # RESCUE C09-M
    master["france251_component_d"] = master["iso3_d"].isin(["MCO", "GUF"]).astype("int8")  # RESCUE C09-M
    master["france251_component_any"] = (master["france251_component_o"] | master["france251_component_d"]).astype("int8")  # RESCUE C09-M

# ============================================================
# 5. HOFSTEDE CULTURAL DISTANCE
# ============================================================
hof = pd.read_stata(HOFSTEDE, convert_categoricals=False)
hof["iso3_o"] = clean_iso(hof["iso3_o"])
hof["iso3_d"] = clean_iso(hof["iso3_d"])

if hof.duplicated(["iso3_o","iso3_d"]).any():
    raise RuntimeError("Hofstede final table is not unique by ordered ISO3 dyad.")

hof_keep = [
    "iso3_o","iso3_d",
    "cd6_ge4","cd6_strict","cd4_ks","common_dim_count6",
    "regional_proxy_flag_o","regional_proxy_flag_d","any_regional_proxy"
]
hof = hof[[c for c in hof_keep if c in hof.columns]].copy()

master = master.merge(
    hof,
    on=["iso3_o","iso3_d"],
    how="left",
    validate="m:1",
    indicator="_m_hofstede"
)
master["hofstede_pair_present"] = master["_m_hofstede"].eq("both").astype("int8")

# ============================================================
# 6. ANALYSIS ALIASES — preserve source variables too
# ============================================================
aliases = {
    "contiguity":"contig",
    "common_language":"comlang_off",
    "colony_ever":"col_dep_ever",
    "common_legal_origin":"comleg_posttrans",
    "rta_fta":"fta_wto",
}
alias_rows = []
for new, old in aliases.items():
    if old in master.columns:
        master[new] = master[old]
        alias_rows.append({
            "analysis_variable":new,
            "source_variable":old,
            "source":"CEPII Gravity V202211"
        })

pd.DataFrame(alias_rows).to_csv(
    MASTER_DIAG/"analysis_variable_aliases.csv",
    index=False, encoding="utf-8-sig"
)

# ============================================================
# 7. SAMPLE FLAGS — do not drop observations here
# ============================================================
master["sample_trade_reporting"] = master["comtrade_reporting_available"].eq(1).astype("int8")
master["sample_tourists"] = (
    master["sample_trade_reporting"].eq(1)
    & master["tourists_k"].notna()
).astype("int8")
master["sample_visitors"] = (
    master["sample_trade_reporting"].eq(1)
    & master["visitors_k"].notna()
).astype("int8")

for cd in ["cd6_ge4","cd6_strict","cd4_ks"]:
    if cd in master.columns:
        master[f"sample_tourists_{cd}"] = (
            master["sample_tourists"].eq(1) & master[cd].notna()
        ).astype("int8")
        master[f"sample_visitors_{cd}"] = (
            master["sample_visitors"].eq(1) & master[cd].notna()
        ).astype("int8")

# ============================================================
# 8. CLEANUP, KEY CHECK, OUTPUTS
# ============================================================
merge_indicators = [
    "_m_comtrade_availability","_m_comtrade_sparse","_m_tourism","_m_hofstede"
]
for c in merge_indicators:
    if c in master.columns:
        master[c] = master[c].astype(str)

if master.duplicated(["year","iso3_o","iso3_d"]).any():
    raise RuntimeError("Final international master is not unique by dyad-year.")

master = master.sort_values(["year","iso3_o","iso3_d"]).reset_index(drop=True)

# Stata variable-name preflight: prevent silent pandas renaming on .dta export.
bad_stata_names = [
    c for c in master.columns
    if len(str(c)) > 32 or re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", str(c)) is None
]
if bad_stata_names:
    raise RuntimeError(
        "Master contains non-Stata-compatible variable names: "
        + ", ".join(map(str, bad_stata_names))
    )
print("MASTER_STATA_VARIABLE_NAMES=PASS")

assert_base_preserved(master)
save_stata(master, CHAPTER_MERGED, write_index=False,version=118)
print("MASTER_PANEL_BUILD=PASS")
print("International master rows:", len(master))
print("Trade-reporting rows:", int(master["sample_trade_reporting"].sum()))
print("Rows with tourists observed:", int(master["tourists_observed"].sum()))
print("Rows with visitors observed:", int(master["visitors_observed"].sum()))
print("Comtrade zero-filled rows:", int(master["comtrade_zero_fill_sparse"].sum()))

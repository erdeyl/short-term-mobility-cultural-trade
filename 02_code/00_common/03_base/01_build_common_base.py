"""Create the common base only; chapter datasets are built downstream."""
from pathlib import Path
import sys
import json
import pandas as pd
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from project_paths import *
from base_core import build_base, stata_ready, VALUES, PROVENANCE, ALIASES  # RESCUE C02; RESCUE C09; RESCUE C10
import sys as _rescue_sys  # RESCUE C02; RESCUE C09; RESCUE C10
from pathlib import Path as _RescuePath  # RESCUE C02; RESCUE C09; RESCUE C10
_RESCUE = next(p for p in _RescuePath(__file__).resolve().parents if p.name == '02_code') / '99_rescue'  # RESCUE C02; RESCUE C09; RESCUE C10
_rescue_sys.path.insert(0, str(_RESCUE))  # RESCUE C02; RESCUE C09; RESCUE C10
import rescue_switch  # RESCUE C02; RESCUE C09; RESCUE C10
import ia_common  # RESCUE C02; RESCUE C09; RESCUE C10

ensure_common_dirs()
ensure_chapter_dirs()
gravity_path = COMMON_INT / '02_Gravity/source_tables/cepii_gravity_rta_2007_2021.dta'
trade_path = COMMON_INT / '01_UN_Comtrade/source_tables/cultural_trade_sparse_2007_2021.dta'
av_path = COMMON_INT / '01_UN_Comtrade/source_tables/reporter_year_availability_2007_2021.dta'
for path in (gravity_path, trade_path, av_path):
    if not path.is_file():
        raise SystemExit(f'Required derived source table missing: {path}')
base, summary, excluded = build_base(
    pd.read_stata(gravity_path, convert_categoricals=False),
    pd.read_stata(av_path, convert_categoricals=False),
    pd.read_stata(trade_path, convert_categoricals=False))
base = stata_ready(base)  # RESCUE C09
if rescue_switch.enabled('C09'):  # RESCUE C09
    ia_common.write_base_rescue_diagnostics(base, BASE_DIAG)  # RESCUE C09

excluded.to_csv(BASE_DIAG / 'comtrade_rows_not_in_base.csv', index=False, encoding='utf-8-sig')
annual = base.groupby('year').agg(
    rows=('year', 'size'), trade_reporting_rows=('comtrade_reporting_available', 'sum'),
    sparse_rows_matched=('comtrade_sparse_row_present', 'sum'),
    zero_filled_rows=('comtrade_zero_fill_sparse', 'sum'),
    positive_LB_rows=('v_ttl_lb_k', lambda x: x.gt(0).sum()),
    non_reporting_rows=('comtrade_reporting_available', lambda x: x.eq(0).sum()))
annual.reset_index().to_csv(BASE_DIAG / 'base_sample_by_year.csv', index=False, encoding='utf-8-sig')
pd.DataFrame([summary]).to_csv(BASE_DIAG / 'base_build_summary.csv', index=False, encoding='utf-8-sig')
(BASE_DIAG / 'base_build_summary.json').write_text(json.dumps(summary, indent=2), encoding='utf-8')

definitions = {
    'year': 'Calendar year', 'iso3_o': 'Exporter / origin ISO3', 'iso3_d': 'Importer / destination ISO3',
    'comtrade_reporting_available': '1 if importer-year occurs in the archived reporting availability table',
    'trade_reporting_available': 'Source availability value; missing when importer-year not matched',
    'comtrade_sparse_row_present': '1 if an archived sparse trade dyad-year matched the backbone',
    'comtrade_zero_fill_sparse': '1 if reporting importer-year lacked a sparse dyad row and was filled with zero',
    'sample_trade_reporting': 'Alias for reporting flag; no chapter-specific sample filtering',
    'comtrade_hs_version': 'HS edition reported by importer-year',
    'comtrade_sparse_hs_version': 'HS edition on matched sparse dyad; empty if absent',
    'v_3706_k': 'Cinematographic film category', 'v_49_k': 'Publications category',
    'v_97_k': 'Art / collectors items / antiques category',
    'v_8523_id_k': 'Identified recorded-media value', 'v_8523_amb_k': 'Ambiguous recorded-media pool',
    'v_8523_lb_k': 'Recorded media lower bound', 'v_8523_ub_k': 'Recorded media upper bound',
    'v_ttl_lb_k': 'Total cultural trade lower bound', 'v_ttl_ub_k': 'Total cultural trade upper bound',
    'v_8523_exact': '1 if ambiguous recorded-media pool is zero; missing when importer-year unavailable',
    'n_source_rows': 'Count of contributing raw HS6 source rows; zero for constructed-zero dyads',
    'n_unreported_rows': 'Count of source rows whose isReported flag was not true',
    'any_unreported': '1 if at least one contributing source row is not reported',
    'domestic_pair': 'Always 0 in the international base', 'ln_dist': 'Natural log of positive CEPII dist',
}
if rescue_switch.enabled('C10'):  # RESCUE C09; RESCUE C10
    definitions.update({'v_49_k':'Printed matter including stamps and security documents (HS49)', 'v_8523_lb_k':'Selected recording/storage media, recorded or unrecorded; lower mapping bound', 'v_8523_ub_k':'Selected recording/storage media, recorded or unrecorded; upper mapping bound', 'v_4907_k':'HS490700 subcomponent, already included in v_49_k', 'ttl_ex8523_lb_k':'Total excluding selected HS8523, thousand USD; LB', 'ttl_ex8523_ub_k':'Total excluding selected HS8523, thousand USD; UB equals LB', 'ttl_ex8523':'Alias of ttl_ex8523_lb_k'})  # RESCUE C09; RESCUE C10
if rescue_switch.enabled('C09'):  # RESCUE C09; RESCUE C10
    definitions.update({'zero_fill_no_rows':'Available importer-year with zero archived basket rows; true-zero status unknown', 'territory_france_251_o':'FRA exporter customs footprint includes Monaco/overseas departments', 'territory_france_251_d':'FRA importer customs footprint includes Monaco/overseas departments', 'territory_partner_492':'Matched Comtrade492 semantics conflict; no geographic allocation', 'territory_mco_guf_pair':'MCO/GUF endpoint; territorial-alignment sensitivity flag'})  # RESCUE C09; RESCUE C10
if rescue_switch.enabled('C02'):  # RESCUE C02
    definitions.update({'comtrade_reporter_code':'Original numeric Comtrade reporter code retained', 'comtrade_partner_code':'Original numeric Comtrade partner code on a matched sparse row', 'comtrade_reporter_iso_src':'Original reporter ISO before special-area crosswalk', 'comtrade_partner_iso_src':'Original partner ISO before special-area crosswalk', 'comtrade_490_reporter':'Source reporter code490, disseminated as Taiwan Province of China (TWN) with residual-area caveat', 'comtrade_490_partner':'Matched source partner code490, disseminated as Taiwan Province of China (TWN) with residual-area caveat', 'comtrade_special_area_490':'Reporter or partner490; residual unspecified Asian territories cannot be ruled out'})  # RESCUE C02
if rescue_switch.enabled('C03'):  # RESCUE C03
    definitions['fta_wto_source']='Unmodified supplemented CEPII fta_wto before the C03 override'  # RESCUE C03
if rescue_switch.enabled('C10'):  # RESCUE C10
    definitions.update({'v_3706_k':'Cinematographic film, exposed and developed (HS3706)', 'v_8523_id_k':'Identified selected recording/storage media; recorded or unrecorded', 'v_8523_amb_k':'Ambiguous HS mapping pool for selected recording/storage media', 'v_8523_exact':'1 if the ambiguous HS mapping pool is zero; does not certify recorded content'})  # RESCUE C10
labels = {}  # RESCUE C09; RESCUE C10
inventory = DIAGNOSTICS / '02_Gravity/gravity_variable_inventory.csv'
if inventory.exists():
    inv = pd.read_csv(inventory).fillna('')
    labels = dict(zip(inv['variable'], inv['variable_label']))
dictionary = []
for col in base:
    original = ALIASES.get(col, col)
    source = 'UN Comtrade' if original in VALUES + PROVENANCE or 'comtrade' in col or col in ['trade_reporting_available','sample_trade_reporting'] else 'CEPII Gravity V202211'
    if rescue_switch.enabled('C09') and (col=='zero_fill_no_rows' or col.startswith('territory_')):  # RESCUE C09
        source = 'UN Comtrade; CEPII country keys for territory alignment'  # RESCUE C09
    definition = definitions.get(col, labels.get(col, 'Official CEPII field retained without recoding'))
    if col in ALIASES:
        definition = f'Exact alias of {original}; original variable also retained'
    dictionary.append({'variable': col, 'dtype': str(base[col].dtype), 'source': source,
                       'unit': 'thousand current USD' if original in VALUES else '', 'definition': definition})
pd.DataFrame(dictionary).to_csv(BASE_DIAG / 'base_variable_dictionary.csv', index=False, encoding='utf-8-sig')

# Validate first, then replace the result through a temporary file.
temp = BASE_DTA.with_suffix('.pending.dta')
base.to_stata(temp, write_index=False, version=118, data_label='Common cultural trade and gravity base, 2007-2021')
temp.replace(BASE_DTA)
print('COMMON_BASE_BUILD=PASS')
print('Rows:', len(base))
print('Base:', BASE_DTA)
print('Chapter datasets remain a separate downstream step.')

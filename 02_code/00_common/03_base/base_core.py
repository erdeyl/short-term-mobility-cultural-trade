"""Chapter-independent merge, extracted from the existing master builders."""
import re
import numpy as np
import pandas as pd  # RESCUE C02; RESCUE C09; RESCUE C10
import sys as _rescue_sys  # RESCUE C02; RESCUE C09; RESCUE C10
from pathlib import Path as _RescuePath  # RESCUE C02; RESCUE C09; RESCUE C10
_RESCUE = next(p for p in _RescuePath(__file__).resolve().parents if p.name == '02_code') / '99_rescue'  # RESCUE C02; RESCUE C09; RESCUE C10
_rescue_sys.path.insert(0, str(_RESCUE))  # RESCUE C02; RESCUE C09; RESCUE C10
import rescue_switch  # RESCUE C02; RESCUE C09; RESCUE C10
import ia_common  # RESCUE C02; RESCUE C09; RESCUE C10

KEY = ['year', 'iso3_o', 'iso3_d']
VALUES = ['v_3706_k', 'v_49_k', 'v_8523_id_k', 'v_8523_amb_k',
          'v_8523_lb_k', 'v_8523_ub_k', 'v_97_k', 'v_ttl_lb_k', 'v_ttl_ub_k']
if rescue_switch.enabled('C10'):  # RESCUE C10
    VALUES += ['v_4907_k', 'ttl_ex8523_lb_k', 'ttl_ex8523_ub_k', 'ttl_ex8523']  # RESCUE C10
PROVENANCE = ['v_8523_exact', 'n_source_rows', 'n_unreported_rows', 'any_unreported']  # RESCUE C10
ALIASES = {'contiguity': 'contig', 'common_language': 'comlang_off',
           'colony_ever': 'col_dep_ever', 'common_legal_origin': 'comleg_posttrans',
           'rta_fta': 'fta_wto', 'ttl_k': 'v_ttl_lb_k', 'v_8523_k': 'v_8523_lb_k'}

def require_columns(frame, columns, name):
    missing = sorted(set(columns) - set(frame.columns))
    if missing:
        raise ValueError(f'{name}: missing required columns {missing}')

def require_unique(frame, key, name):
    if frame[key].isna().any().any() or frame.duplicated(key).any():
        raise ValueError(f'{name}: missing or duplicate key {key}')

def normalize(frame, iso_columns):
    frame = frame.copy()
    year = pd.to_numeric(frame['year'], errors='raise')
    if year.isna().any() or (year % 1).ne(0).any():
        raise ValueError('Year must contain nonmissing integers.')
    frame['year'] = year.astype('int16')
    for col in iso_columns:
        frame[col] = frame[col].fillna('').astype(str).str.strip().str.upper()
    return frame

def check_values(base):
    """Rules that must hold before and after saving the base."""
    require_unique(base, KEY, 'Common base')
    if base['iso3_o'].eq(base['iso3_d']).any():
        raise ValueError('Domestic rows in international base.')
    for c in ['iso3_o', 'iso3_d']:
        if not base[c].str.fullmatch(r'[A-Z]{3}').all():
            raise ValueError(f'Invalid ISO3 key: {c}')
    available = base['comtrade_reporting_available'].eq(1)
    sparse = base['comtrade_sparse_row_present'].eq(1)
    zero = base['comtrade_zero_fill_sparse'].eq(1)
    if not zero.equals(available & ~sparse):
        raise ValueError('Incorrect sparse zero-fill flag.')
    if (sparse & ~available).any():
        raise ValueError('Sparse source record without reporter-year availability.')
    if base.loc[~available, VALUES].notna().any().any():
        raise ValueError('Non-reporting importer-year has a nonmissing trade outcome.')
    if base.loc[available, VALUES].isna().any().any():
        raise ValueError('Reporting importer-year has an unclassified missing outcome.')
    if base.loc[available, VALUES].lt(0).any().any():
        raise ValueError('Negative trade value.')
    if not base.loc[zero, VALUES].eq(0).all().all():
        raise ValueError('Constructed zero row is nonzero.')
    a = base.loc[available]
    relations = [
        (a['v_8523_lb_k'], a['v_8523_id_k']),
        (a['v_8523_ub_k'], a['v_8523_id_k'] + a['v_8523_amb_k']),
        (a['v_ttl_lb_k'], a['v_3706_k'] + a['v_49_k'] + a['v_8523_lb_k'] + a['v_97_k']),
        (a['v_ttl_ub_k'], a['v_ttl_lb_k'] + a['v_8523_amb_k']),
    ]
    if any(not np.allclose(left, right, rtol=1e-10, atol=1e-7) for left, right in relations):
        raise ValueError('LB/UB or category additivity check failed.')
    if not a['v_8523_exact'].eq(a['v_8523_amb_k'].eq(0).astype(int)).all():
        raise ValueError('Recorded-media exactness flag disagrees with ambiguous pool.')
    if not base.loc[zero, ['n_source_rows', 'n_unreported_rows', 'any_unreported']].eq(0).all().all():
        raise ValueError('Constructed zero has source-row provenance.')
    for alias, source in ALIASES.items():
        if source in base and not base[alias].equals(base[source]):
            raise ValueError(f'Alias differs from source: {alias}')

def build_base(gravity, availability, trade, start=2007, end=2021):
    require_columns(gravity, KEY + ['country_exists_o', 'country_exists_d'], 'Gravity')
    gravity = normalize(gravity, ['iso3_o', 'iso3_d'])
    gravity = gravity.loc[gravity['year'].between(start, end)].copy()
    if gravity.empty:
        raise ValueError('Gravity source table has no rows in the requested window.')
    if not gravity[['country_exists_o', 'country_exists_d']].eq(1).all().all():
        raise ValueError('Use the existing-country Gravity source table.')
    require_unique(gravity, KEY, 'Gravity source table')
    for iso in ['iso3_o', 'iso3_d']:
        if not gravity[iso].str.fullmatch(r'[A-Z]{3}').all():
            raise ValueError('Invalid ISO3 in existing-country Gravity source table.')
    base = gravity.loc[gravity['iso3_o'].ne(gravity['iso3_d'])].copy()
    expected_rows = len(base)
    base['domestic_pair'] = 0

    require_columns(availability, ['year', 'reporter_iso', 'hs_version', 'trade_reporting_available'], 'Availability')
    av = availability.rename(columns={'reporter_iso': 'iso3_d', 'hs_version': 'comtrade_hs_version'})
    av = normalize(av, ['iso3_d'])
    av = av[['year', 'iso3_d', 'trade_reporting_available', 'comtrade_hs_version']].copy()
    if rescue_switch.enabled('C02') or rescue_switch.enabled('C09'):  # RESCUE C02; RESCUE C09
        av = ia_common.base_availability_extra(av, availability)  # RESCUE C02; RESCUE C09
    require_unique(av, ['year', 'iso3_d'], 'Comtrade availability')  # RESCUE C02; RESCUE C09
    if not av['trade_reporting_available'].eq(1).all():
        raise ValueError('Archived availability table contains non-available rows.')
    base = base.merge(av, on=['year', 'iso3_d'], how='left', validate='m:1')
    base['comtrade_reporting_available'] = base['trade_reporting_available'].eq(1).astype('int8')

    require_columns(trade, ['year', 'reporter_iso', 'partner_iso', 'hs_version'] + VALUES + PROVENANCE, 'Sparse Comtrade')
    source = trade.rename(columns={'reporter_iso': 'iso3_d', 'partner_iso': 'iso3_o',
                                   'hs_version': 'comtrade_sparse_hs_version'})
    source = normalize(source, ['iso3_o', 'iso3_d'])
    valid_iso = source['iso3_o'].str.fullmatch(r'[A-Z]{3}') & source['iso3_d'].str.fullmatch(r'[A-Z]{3}')
    in_window = source['year'].between(start, end)
    domestic = source['iso3_o'].eq(source['iso3_d'])
    eligible = valid_iso & in_window & ~domestic
    if rescue_switch.enabled('C02'):  # RESCUE C02
        eligible &= ~source.reporter_code.isin([97,975])  # RESCUE C02
    sparse = source.loc[eligible].copy()  # RESCUE C02
    require_unique(sparse, KEY, 'Sparse Comtrade country table')
    left_out = source.loc[~eligible].copy()
    left_out['exclusion_reason'] = np.select(
        [~in_window.loc[left_out.index], ~valid_iso.loc[left_out.index]],
        ['outside_year_window', 'aggregate_or_non_ISO3_area'], default='domestic_pair')
    if rescue_switch.enabled('C02'):  # RESCUE C02
        group_only = in_window.loc[left_out.index] & valid_iso.loc[left_out.index] & left_out.reporter_code.isin([97,975])  # RESCUE C02
        left_out.loc[group_only, 'exclusion_reason'] = 'group_reporter_97_975'  # RESCUE C02
    membership = sparse.merge(base[KEY], on=KEY, how='left', validate='1:1', indicator=True)
    unmatched = membership.loc[membership['_merge'].eq('left_only')].drop(columns='_merge').copy()
    unmatched['exclusion_reason'] = 'outside_CEPII_existing_country_universe'
    exclusions = pd.concat([left_out, unmatched], ignore_index=True)

    keep = KEY + VALUES + PROVENANCE + ['comtrade_sparse_hs_version']  # RESCUE C02; RESCUE C09
    if rescue_switch.enabled('C02') or rescue_switch.enabled('C09'):  # RESCUE C02; RESCUE C09
        sparse = sparse.rename(columns={'partner_code':'comtrade_partner_code','partner_iso_source':'comtrade_partner_iso_src'})  # RESCUE C02; RESCUE C09
        keep += [c for c in ['comtrade_partner_code','comtrade_partner_iso_src','comtrade_490_partner'] if c in sparse]  # RESCUE C02; RESCUE C09
    base = base.merge(sparse[keep], on=KEY, how='left', validate='1:1', indicator='_merge_trade')
    base['comtrade_sparse_row_present'] = base['_merge_trade'].eq('both').astype('int8')
    base.drop(columns='_merge_trade', inplace=True)
    matched = base['comtrade_sparse_row_present'].eq(1)
    if (matched & base['comtrade_reporting_available'].ne(1)).any():
        raise ValueError('Matched sparse trade exists without importer-year reporting availability.')
    if base.loc[matched, VALUES + PROVENANCE].isna().any().any():
        raise ValueError('Matched sparse source has missing values/provenance; do not fill it with zero.')
    if not base.loc[matched, 'comtrade_sparse_hs_version'].eq(base.loc[matched, 'comtrade_hs_version']).all():
        raise ValueError('Sparse HS edition differs from importer-year availability.')
    zero_fill = base['comtrade_reporting_available'].eq(1) & ~matched
    base['comtrade_zero_fill_sparse'] = zero_fill.astype('int8')
    base.loc[zero_fill, VALUES] = 0.0
    base.loc[zero_fill, ['n_source_rows', 'n_unreported_rows', 'any_unreported']] = 0
    base.loc[zero_fill, 'v_8523_exact'] = 1
    if rescue_switch.enabled('C02'):  # RESCUE C02; RESCUE C09
        for flag in ['comtrade_490_reporter','comtrade_490_partner']:  # RESCUE C02; RESCUE C09
            base[flag] = base[flag].fillna(0).astype('int8')  # RESCUE C02; RESCUE C09
        base['comtrade_special_area_490'] = (base.comtrade_490_reporter.eq(1) | base.comtrade_490_partner.eq(1)).astype('int8')  # RESCUE C02; RESCUE C09
    if rescue_switch.enabled('C09'):  # RESCUE C02; RESCUE C09
        base = ia_common.base_territory_flags(base, availability, trade)  # RESCUE C02; RESCUE C09
    base['sample_trade_reporting'] = base['comtrade_reporting_available']  # RESCUE C02; RESCUE C09
    for alias, original in ALIASES.items():
        if original in base:
            base[alias] = base[original]
    if 'dist' in base:
        base['ln_dist'] = np.log(base['dist'].where(base['dist'].gt(0)))
    base = base.sort_values(KEY).reset_index(drop=True)
    if len(base) != expected_rows or len(exclusions) + int(matched.sum()) != len(source):
        raise ValueError('Merge changed the backbone or failed to account for a source row.')
    check_values(base)
    summary = {
        'rows': len(base), 'year_min': int(base['year'].min()), 'year_max': int(base['year'].max()),
        'exporters': int(base['iso3_o'].nunique()), 'importers': int(base['iso3_d'].nunique()),
        'gravity_existing_rows': len(gravity), 'domestic_rows_excluded': len(gravity) - len(base),
        'sparse_source_rows': len(source), 'sparse_rows_matched': int(matched.sum()),
        'sparse_rows_excluded': len(exclusions),
        'trade_reporting_rows': int(base['comtrade_reporting_available'].sum()),
        'zero_filled_rows': int(zero_fill.sum()),
        'non_reporting_rows': int(base['comtrade_reporting_available'].eq(0).sum()),
        'positive_LB_rows': int(base['v_ttl_lb_k'].gt(0).sum()),
        'observed_zero_LB_rows': int(base['v_ttl_lb_k'].eq(0).sum()),
        'raw_source_direction': 'Comtrade reporter=importer iso3_d; partner=exporter iso3_o',
        'unit': 'thousand current USD', 'canonical_HS': 'H3 / HS2007',
        'baseline': 'LB', 'mirror_reconciliation': 'none',
    }
    return base, summary, exclusions

def stata_ready(frame):
    out = frame.copy()
    bad = [c for c in out if len(c) > 32 or re.fullmatch(r'[A-Za-z_][A-Za-z0-9_]*', c) is None]
    if bad:
        raise ValueError(f'Invalid Stata variable names: {bad}')
    for c in out:
        if isinstance(out[c].dtype, pd.CategoricalDtype):
            out[c] = out[c].astype(str)
        elif str(out[c].dtype).startswith(('Int', 'UInt')):
            out[c] = out[c].astype(float)
        elif str(out[c].dtype) == 'boolean':
            out[c] = out[c].astype(float)
        elif str(out[c].dtype).startswith('string') or out[c].dtype == object:
            out[c] = out[c].fillna('').astype(str)
    return out

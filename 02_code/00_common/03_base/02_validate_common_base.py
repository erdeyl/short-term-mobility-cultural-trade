"""Read back the saved base; verify backbone and original sparse values."""
from pathlib import Path
import sys
import json
import numpy as np
import pandas as pd
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from project_paths import *
from base_core import KEY, VALUES, check_values

base = pd.read_stata(BASE_DTA, convert_categoricals=False)
check_values(base)
g = pd.read_stata(COMMON_INT / '02_Gravity/source_tables/cepii_gravity_rta_2007_2021.dta',
                  columns=KEY, convert_categoricals=False)
g = g.loc[g['year'].between(2007, 2021) & g['iso3_o'].ne(g['iso3_d'])]
expected = g[KEY].sort_values(KEY).reset_index(drop=True)
pd.testing.assert_frame_equal(base[KEY].reset_index(drop=True), expected, check_dtype=False)
source = pd.read_stata(COMMON_INT / '01_UN_Comtrade/source_tables/cultural_trade_sparse_2007_2021.dta',
                       convert_categoricals=False).rename(columns={'reporter_iso':'iso3_d','partner_iso':'iso3_o'})
matched = base.loc[base['comtrade_sparse_row_present'].eq(1), KEY + VALUES]
comparison = matched.merge(source[KEY + VALUES], on=KEY, how='left', suffixes=('_base','_source'), validate='1:1')
for col in VALUES:
    if not np.allclose(comparison[col+'_base'], comparison[col+'_source'], rtol=0, atol=0):
        raise ValueError(f'Source trade values changed: {col}')
summary = json.loads((BASE_DIAG / 'base_build_summary.json').read_text(encoding='utf-8'))
if summary['rows'] != len(base):
    raise ValueError('Saved base row count differs from build summary.')
pd.DataFrame([{'check':'base_readback_and_source_preservation', 'status':'PASS',
               'rows':len(base), 'matched_source_rows_verified':len(comparison)}]).to_csv(
    BASE_DIAG / 'base_validation.csv', index=False, encoding='utf-8-sig')
print('COMMON_BASE_VALIDATION=PASS')
print('Saved base preserves the backbone and all matched source trade values.')

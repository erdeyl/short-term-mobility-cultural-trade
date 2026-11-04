"""Small constructed cases for the consequential merge and missing-value rules."""
import importlib.util
from pathlib import Path
import sys
import unittest
import pandas as pd
import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / '03_base'))
from base_core import build_base, VALUES, stata_ready, check_values

def inputs():
    g = pd.DataFrame([
        {'year': y, 'iso3_o': o, 'iso3_d': d,
         'country_exists_o': 1, 'country_exists_d': 1,
         'dist': 100.0, 'contig': 0, 'comlang_off': 0,
         'col_dep_ever': 0, 'comleg_posttrans': 1, 'fta_wto': 0}
        for y in (2007, 2008) for o in ('AAA','BBB','CCC') for d in ('AAA','BBB','CCC')])
    av = pd.DataFrame([
        {'year':2007,'reporter_iso':'BBB','trade_reporting_available':1,'hs_version':'H3'},
        {'year':2008,'reporter_iso':'BBB','trade_reporting_available':1,'hs_version':'H3'},
        {'year':2008,'reporter_iso':'AAA','trade_reporting_available':1,'hs_version':'H3'},
    ])
    rows = []
    for year, origin, destination, positive in [(2007,'AAA','BBB',True),(2008,'CCC','BBB',False)]:
        row = dict.fromkeys(VALUES, 0.0)
        row.update(year=year, reporter_iso=destination, partner_iso=origin, hs_version='H3',
                   v_8523_exact=1, n_source_rows=1, n_unreported_rows=0, any_unreported=0)
        if positive:
            row.update(v_3706_k=1.,v_49_k=2.,v_8523_id_k=3.,v_8523_amb_k=4.,
                       v_8523_lb_k=3.,v_8523_ub_k=7.,v_97_k=5.,v_ttl_lb_k=11.,
                       v_ttl_ub_k=15.,v_8523_exact=0)
        rows.append(row)
    return g, av, pd.DataFrame(rows)

class BaseRules(unittest.TestCase):
    def setUp(self):
        self.g, self.av, self.t = inputs()

    def build(self):
        return build_base(self.g, self.av, self.t)[0].set_index(['year','iso3_o','iso3_d'])

    def test_direction_and_nonreporting_importer(self):
        b = self.build()
        self.assertEqual(b.loc[(2007,'AAA','BBB'),'v_ttl_lb_k'], 11)
        self.assertTrue(np.isnan(b.loc[(2007,'BBB','AAA'),'v_ttl_lb_k']))

    def test_fill_only_reporting_importer(self):
        b = self.build()
        self.assertEqual(b.loc[(2007,'CCC','BBB'),'comtrade_zero_fill_sparse'], 1)
        self.assertEqual(b.loc[(2007,'CCC','BBB'),'v_ttl_lb_k'], 0)
        self.assertTrue(np.isnan(b.loc[(2007,'AAA','CCC'),'v_ttl_lb_k']))

    def test_explicit_zero_is_not_constructed_zero(self):
        b = self.build()
        r = b.loc[(2008,'CCC','BBB')]
        self.assertEqual(r['v_ttl_lb_k'], 0)
        self.assertEqual(r['comtrade_sparse_row_present'], 1)
        self.assertEqual(r['comtrade_zero_fill_sparse'], 0)
        self.assertEqual(r['n_source_rows'], 1)

    def test_bounds_and_aliases(self):
        b = self.build()
        r = b.loc[(2007,'AAA','BBB')]
        self.assertEqual(r['v_ttl_ub_k'] - r['v_ttl_lb_k'], 4)
        self.assertEqual(r['ttl_k'], 11)
        self.assertEqual(r['v_8523_k'], 3)

    def test_no_chapter_sample_restriction(self):
        base, summary, excluded = build_base(self.g, self.av, self.t)
        self.assertEqual(len(base), 12)
        self.assertEqual(summary['non_reporting_rows'], 6)
        self.assertEqual(len(excluded), 0)

    def test_outside_source_rows_are_audited(self):
        extra = self.t.iloc[[0,0,0]].copy()
        extra['partner_iso'] = ['W00','DDD','BBB']
        self.t = pd.concat([self.t,extra],ignore_index=True)
        base, summary, excluded = build_base(self.g,self.av,self.t)
        self.assertEqual(len(base),12)
        self.assertEqual(len(excluded),3)
        self.assertEqual(set(excluded['exclusion_reason']),
                         {'aggregate_or_non_ISO3_area','outside_CEPII_existing_country_universe','domestic_pair'})

    def test_duplicate_trade_key_stops(self):
        self.t = pd.concat([self.t,self.t.iloc[[0]]],ignore_index=True)
        with self.assertRaisesRegex(ValueError, 'duplicate key'):
            self.build()

    def test_duplicate_availability_stops(self):
        self.av = pd.concat([self.av,self.av.iloc[[0]]],ignore_index=True)
        with self.assertRaisesRegex(ValueError, 'duplicate key'):
            self.build()

    def test_sparse_without_availability_stops(self):
        self.av = self.av.iloc[1:].copy()
        with self.assertRaisesRegex(ValueError, 'without importer-year'):
            self.build()

    def test_mismatched_HS_edition_stops(self):
        self.t.loc[0,'hs_version'] = 'H2'
        with self.assertRaisesRegex(ValueError, 'HS edition'):
            self.build()

    def test_corrupt_sparse_missing_is_not_zero_filled(self):
        self.t.loc[0,'v_49_k'] = np.nan
        with self.assertRaisesRegex(ValueError, 'missing values'):
            self.build()

    def test_saved_dta_preserves_missing_and_rules(self):
        import tempfile
        base = build_base(self.g,self.av,self.t)[0]
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / 'base.dta'
            stata_ready(base).to_stata(path,write_index=False,version=118)
            loaded = pd.read_stata(path,convert_categoricals=False)
            check_values(loaded)
            self.assertEqual(loaded['v_ttl_lb_k'].isna().sum(),6)

if __name__ == '__main__':
    unittest.main(verbosity=2)

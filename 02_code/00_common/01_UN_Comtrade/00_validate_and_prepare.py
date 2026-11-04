"""Check the frozen archive. Raw inputs are read only."""
import json
import pandas as pd
from _paths import *

ensure_dirs()
expect = json.loads((CONFIG / 'frozen_snapshot_expectations.json').read_text(encoding='utf-8'))
required = [RAW_AVAIL / f'getDa_HS_{y}.json' for y in range(2007, 2022)]
required += [RAW_REF / name for name in
             ('HS-SITC-BEC_Correlations_2022.xlsx', 'Reporters.json', 'partnerAreas.json')]
required += [RAW_META / 'download_manifest.csv']
missing = [str(p) for p in required if not p.is_file()]
trade = sorted(RAW_TRADE.glob('*.csv'))
if missing:
    raise SystemExit('Missing archived Comtrade inputs:\n' + '\n'.join(missing))
if len(trade) != expect['raw_trade_csv_files']:
    raise SystemExit(f"Expected {expect['raw_trade_csv_files']} archived trade CSVs; found {len(trade)} in {RAW_TRADE}")
rows = [{'relative_path': p.relative_to(ROOT).as_posix(), 'bytes': p.stat().st_size}
        for p in required + trade]
pd.DataFrame(rows).to_csv(DIAG_CT / 'source_file_inventory.csv', index=False, encoding='utf-8-sig')
print('COMTRADE_STRUCTURE_AND_SOURCE_ARCHIVE=PASS')
print('Archived trade CSV files:', len(trade))
print('Project root:', ROOT)

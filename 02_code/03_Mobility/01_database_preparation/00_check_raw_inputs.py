from pathlib import Path
import sys
for _parent in Path(__file__).resolve().parents:
    if (_parent / 'chapter_paths.py').is_file():
        sys.path.insert(0, str(_parent))
        break
from chapter_paths import *
import pandas as pd
from chapter_runtime import require_common
require_common()
errors=[]
tour_expected={'Tourists Arrivals by Nationality':61,'Tourists Arrivals by Residence':131,
               'Visitors Arrivals by Nationality':45,'Visitors Arrivals by Residence':107}
for folder,n in tour_expected.items():
    found=len(list((RAW/folder).glob('*.xlsx')))
    if found!=n:errors.append(f'{folder}: expected {n} workbooks, found {found}')
import os
_hof_rebuilt=os.environ.get('PKG_HOFSTEDE_SHEET_JSON','')  # replication package: sheet rebuilt from the official file
if len(list(RAW.glob('6-dimensions-for-website-2015-08-16*.xls')))!=1 and not (_hof_rebuilt and Path(_hof_rebuilt).is_file()):
    errors.append('Expected exactly one archived Hofstede XLS in '+str(RAW))
for rel in ['classification_availability/reported_classification_availability_2007_2021.csv',
            'concordance/reported_HS_to_H3_concordance.csv','reference/partner_reference.csv']:
    if not (COMMON_INT/'01_UN_Comtrade'/rel).is_file():errors.append('Missing shared reference: '+rel)
mirror=ROOT/'01_raw/02_UN_Comtrade/mirror_exporter_reported'
for rel in ['acquisition_metadata/export_flow_availability_manifest.csv',
            'acquisition_metadata/exporter_trade_download_manifest.csv']:
    if not (mirror/rel).is_file():errors.append('Missing mirror archive: '+rel)
manifest=mirror/'acquisition_metadata/exporter_trade_download_manifest.csv'
if manifest.is_file():
    df=pd.read_csv(manifest)
    if not {'status','filename'}.issubset(df.columns):
        errors.append('Invalid exporter trade archive manifest schema.')
    else:
        for filename in df.loc[df['status'].eq('DOWNLOADED_OK'),'filename'].dropna().unique():
            if not (mirror/'trade_api/reported_HS'/filename).is_file():
                errors.append('Missing archived mirror CSV: '+filename)
if errors:raise SystemExit('RAW_INPUT_PREFLIGHT=FAIL\n'+'\n'.join(errors))
print('RAW_INPUT_PREFLIGHT=PASS')

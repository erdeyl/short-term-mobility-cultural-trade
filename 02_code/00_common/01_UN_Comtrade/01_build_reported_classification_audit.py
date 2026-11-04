"""Rebuild classification availability from the archived JSON responses."""
import json
import pandas as pd
from _paths import *
ensure_dirs()
YEARS = list(range(2007, 2022))
missing = [RAW_AVAIL / f'getDa_HS_{y}.json' for y in YEARS
           if not (RAW_AVAIL / f'getDa_HS_{y}.json').is_file()]
if missing:
    raise SystemExit('Missing archived availability JSON: ' + ', '.join(map(str, missing)))
rows=[]; man=[]
for y in YEARS:
    p=RAW_AVAIL/f'getDa_HS_{y}.json'; payload=json.loads(p.read_text(encoding='utf-8-sig')); data=payload.get('data',[]); err=payload.get('error')
    if err not in (None,'',[],{}): raise RuntimeError(f'API error in {p.name}: {err}')
    man.append({'year':y,'api_count':payload.get('count'),'data_rows':len(data),'source_file':p.name,'status':'ARCHIVED_SOURCE_OK'})
    for r in data:
        x=dict(r); x['_query_year']=y; rows.append(x)
raw=pd.DataFrame(rows)
raw.to_csv(INT_AVAIL/'reported_classification_availability_raw_2007_2021.csv',index=False,encoding='utf-8-sig')
wanted=['_query_year','reporterCode','reporterISO','reporterDesc','classificationCode','classificationSearchCode','isOriginalClassification']
a=raw[[c for c in wanted if c in raw.columns]].copy()
for c in ['period','refYear','refPeriodId']:
    if c in raw.columns:a[c]=raw[c]
a.to_csv(INT_AVAIL/'reported_classification_availability_2007_2021.csv',index=False,encoding='utf-8-sig')
dist=a.groupby(['_query_year','classificationCode'],dropna=False).size().reset_index(name='dataset_rows').sort_values(['_query_year','classificationCode'])
dist.to_csv(DIAG_AVAIL/'reported_classification_distribution_by_year.csv',index=False,encoding='utf-8-sig')
dup=a.groupby(['_query_year','reporterCode']).size().reset_index(name='n_rows').query('n_rows > 1')
dup.to_csv(DIAG_AVAIL/'reporter_year_multiple_availability_rows.csv',index=False,encoding='utf-8-sig')
pd.DataFrame(man).to_csv(DIAG_AVAIL/'availability_source_manifest.csv',index=False,encoding='utf-8-sig')
vs=a.groupby('classificationCode').size().rename('reporter_years').reset_index();vs['share']=vs.reporter_years/len(a);vs.to_csv(DIAG_AVAIL/'reporter_year_HS_version_summary.csv',index=False,encoding='utf-8-sig')
t=a.assign(pre_H3=a.classificationCode.isin(['H0','H1','H2']));pre=t.groupby('_query_year').agg(reporter_years=('reporterCode','size'),pre_H3_reporter_years=('pre_H3','sum')).reset_index();pre['pre_H3_share']=pre.pre_H3_reporter_years/pre.reporter_years;pre.to_csv(DIAG_AVAIL/'preH3_share_by_year.csv',index=False,encoding='utf-8-sig')
if len(a)!=2660 or len(dup)!=0: raise RuntimeError(f'Frozen Data Availability validation failed: rows={len(a)}, duplicates={len(dup)}')
print('REPORTED_CLASSIFICATION_AUDIT=PASS');print('Reporter-years:',len(a));print('Unique reporters:',a.reporterCode.nunique())

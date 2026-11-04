import json, time, os
from getpass import getpass
import requests, pandas as pd
from _paths import *
ensure_dirs(); YEARS=list(range(2007,2022)); BASE='https://comtradeapi.un.org/data/v1/getDa/C/A/HS'
def key():
    k=os.environ.get('COMTRADE_API_KEY','').strip() or getpass('Paste CURRENT UN Comtrade Primary key (only for missing years): ').strip()
    if not k or any(ch.isspace() for ch in k): raise SystemExit('Invalid/missing API key.')
    return k
def download_missing(years):
    if not years:return
    k=key(); headers={'User-Agent':'academic-replication-pipeline/1.0','Ocp-Apim-Subscription-Key':k}  # key in a header, not in the URL
    for y in years:
        for attempt in range(1,7):
            r=requests.get(BASE,params={'period':str(y),'maxrecords':100000},headers=headers,timeout=180)
            if r.status_code==429: time.sleep(20*attempt); continue
            if r.status_code!=200:
                if attempt==6: raise RuntimeError(f'HTTP {r.status_code}: {r.text[:500]}')
                time.sleep(10*attempt); continue
            (RAW_AVAIL/f'getDa_HS_{y}.json').write_text(json.dumps(r.json(),ensure_ascii=False,indent=2),encoding='utf-8'); break
        time.sleep(2)
missing=[y for y in YEARS if not (RAW_AVAIL/f'getDa_HS_{y}.json').exists()]
if missing: download_missing(missing)
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

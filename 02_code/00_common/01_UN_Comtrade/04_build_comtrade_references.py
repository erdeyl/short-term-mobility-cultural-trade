import json, pandas as pd
from _paths import *
ensure_dirs()
SOURCES={'Reporters.json':'https://comtradeapi.un.org/files/v1/app/reference/Reporters.json','partnerAreas.json':'https://comtradeapi.un.org/files/v1/app/reference/partnerAreas.json'}
def get_any(d,*names):
    lo={str(k).lower():v for k,v in d.items()}
    for n in names:
        if n.lower() in lo:return lo[n.lower()]
    return None
man=[]
for fn,url in SOURCES.items():
    p=RAW_REF/fn
    if not p.is_file():
        raise FileNotFoundError(f'Archived reference missing: {p}')
    b=p.read_bytes();man.append({'filename':fn,'url':url,'bytes':len(b),'source_status':'ARCHIVED_REFERENCE'})
rr=json.loads((RAW_REF/'Reporters.json').read_text(encoding='utf-8-sig'))['results'];rrows=[]
for x in rr:rrows.append({'reporterCode':get_any(x,'reporterCode','id'),'reporterISO':get_any(x,'reporterCodeIsoAlpha3'),'reporterDesc':get_any(x,'reporterDesc','text'),'entryEffectiveDate':get_any(x,'entryEffectiveDate'),'entryExpiredDate':get_any(x,'entryExpiredDate'),'isGroup':get_any(x,'isGroup')})
rdf=pd.DataFrame(rrows);rdf.to_csv(INT_REF/'reporter_reference.csv',index=False,encoding='utf-8-sig')
pp=json.loads((RAW_REF/'partnerAreas.json').read_text(encoding='utf-8-sig'))['results'];prows=[]
for x in pp:prows.append({'partnerCode':get_any(x,'partnerCode','id'),'partnerISO':get_any(x,'partnerCodeIsoAlpha3'),'partnerDesc':get_any(x,'partnerDesc','text'),'entryEffectiveDate':get_any(x,'entryEffectiveDate'),'entryExpiredDate':get_any(x,'entryExpiredDate'),'isGroup':get_any(x,'isGroup')})
pdf=pd.DataFrame(prows);pdf.to_csv(INT_REF/'partner_reference.csv',index=False,encoding='utf-8-sig')
pd.DataFrame(man).to_csv(DIAG_CT/'reference_source_manifest.csv',index=False,encoding='utf-8-sig')
print('COMTRADE_REFERENCE_BUILD=PASS');print('Reporter reference rows:',len(rdf));print('Partner reference rows:',len(pdf))

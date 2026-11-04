from pathlib import Path
import sys
for _parent in Path(__file__).resolve().parents:
    if (_parent / 'chapter_paths.py').is_file():
        sys.path.insert(0, str(_parent))
        break
from chapter_paths import *
import numpy as np
import pandas as pd
ensure_dirs()
key=['year','iso3_o','iso3_d']
master=pd.read_stata(CHAPTER_MERGED,convert_categoricals=False).sort_values(key).reset_index(drop=True)
records=[]
for tag,name in [('LB','mobility_analysis_2007_2021.dta'),('UB','mobility_analysis_UB_2007_2021.dta')]:
    df=pd.read_stata(ANALYSIS/name,convert_categoricals=False).sort_values(key).reset_index(drop=True)
    pd.testing.assert_frame_equal(df[key],master[key],check_dtype=False,check_exact=True)
    pairs={'tourists':'tourists_trips','visitors':'visitors_trips','cul_dist':'cd6_ge4',
           'v_ttl_k':'v_ttl_'+tag.lower()+'_k','v_8523_k':'v_8523_'+tag.lower()+'_k'}
    for new,old in pairs.items():
        if not np.allclose(df[new],master[old],rtol=0,atol=0,equal_nan=True):
            raise RuntimeError(f'{tag} analysis interface changed {old}.')
    records.append({'variant':tag,'rows':len(df),'unique_key':not df.duplicated(key).any(),'validation':'PASS'})
pd.DataFrame(records).to_csv(DIAGNOSTICS/'analysis_inputs/analysis_validation.csv',index=False,encoding='utf-8-sig')
print('MOBILITY_ANALYSIS_INPUT_VALIDATION=PASS')

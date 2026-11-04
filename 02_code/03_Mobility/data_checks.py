"""Check chapter merges against the common base and save portable Stata files."""
import re
import pandas as pd
from chapter_paths import COMMON_BASE

KEY = ['year','iso3_o','iso3_d']

def assert_base_preserved(frame):
    base = pd.read_stata(COMMON_BASE,convert_categoricals=False)
    if frame.duplicated(KEY).any() or len(frame) != len(base):
        raise RuntimeError('Chapter merge changed the common-base row set or duplicated keys.')
    missing = sorted(set(base.columns)-set(frame.columns))
    if missing:
        raise RuntimeError(f'Chapter merge lost common-base columns: {missing}')
    left = base.sort_values(KEY).reset_index(drop=True)
    right = frame.sort_values(KEY).reset_index(drop=True)[base.columns]
    pd.testing.assert_frame_equal(left,right,check_dtype=False,check_exact=True)
    print('COMMON_BASE_FIELDS_PRESERVED=PASS')

def save_stata(frame,path,**kwargs):
    frame = frame.copy()
    # Match the original pandas Stata spelling for Country Name explicitly.
    frame.rename(columns={'Country Name':'Country_Name'},inplace=True)
    bad=[c for c in frame if len(c)>32 or re.fullmatch(r'[A-Za-z_][A-Za-z0-9_]*',c) is None]
    if bad:
        raise RuntimeError(f'Invalid Stata variable names: {bad}')
    for c in frame:
        dt=str(frame[c].dtype)
        if dt.startswith(('Int','UInt')) or dt=='boolean':
            frame[c]=frame[c].astype(float)
        elif frame[c].dtype==object or dt in ('string','str') or dt.startswith('string['):
            frame[c]=frame[c].fillna('').astype(str)
    path.parent.mkdir(parents=True,exist_ok=True)
    temp=path.with_suffix('.pending.dta')
    frame.to_stata(temp,**kwargs)
    temp.replace(path)

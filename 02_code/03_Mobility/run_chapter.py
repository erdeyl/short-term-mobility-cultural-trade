"""Build or estimate the mobility chapter."""
import argparse,sys
from chapter_paths import *
from chapter_runtime import require_common,run_python,find_stata,check_stata_environment,invalidate_completion
p=argparse.ArgumentParser()
p.add_argument('stage',choices=['build','empirical','all'],nargs='?',default='build')
p.add_argument('--check',action='store_true')
a=p.parse_args()
ensure_dirs()
if not a.check:invalidate_completion(a.stage)
require_common()
if a.check:
    import pandas,numpy,openpyxl
    import xlrd,requests
    print('COMMON_BASE:',COMMON_BASE)
    print('ANALYSIS_DESTINATION:',ANALYSIS)
    print('Python dependencies: PASS')
    if 'mobility'=='mobility' or a.stage!='build':check_stata_environment(packages=a.stage!='build')
    raise SystemExit(0)
if a.stage in ['build','all']:run_python(CHAPTER_CODE/'01_database_preparation/run_01_prepare_database.py')
if a.stage in ['empirical','all']:run_python(CHAPTER_CODE/'02_empirical_analysis/run_02_all_empirics.py')

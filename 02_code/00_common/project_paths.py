"""Shared dissertation paths. Moving the project folder requires no edits."""
from pathlib import Path

COMMON_CODE = Path(__file__).resolve().parent
ROOT = COMMON_CODE.parents[1]
RAW_ROOT = ROOT / '01_raw'
COMMON_INT = ROOT / '03_intermediate' / '00_common'
COMMON_OUTPUT = ROOT / '05_output' / '00_common'
DIAGNOSTICS = COMMON_OUTPUT / '01_diagnostics'
LOGS = COMMON_OUTPUT / '03_logs'
BASE_STEM = 'cultural_trade_gravity_base_2007_2021'
BASE_DTA = COMMON_INT / (BASE_STEM + '.dta')
BASE_DIAG = DIAGNOSTICS / '03_base'
CHAPTERS = ('01_BRI', '02_Digitalization', '03_Mobility')

def ensure_common_dirs():
    for path in (COMMON_INT, DIAGNOSTICS, LOGS, BASE_DIAG):
        path.mkdir(parents=True, exist_ok=True)

def ensure_chapter_dirs():
    # Create destinations only; chapter builders will populate them later.
    for chapter in CHAPTERS:
        (ROOT / '03_intermediate' / chapter).mkdir(parents=True, exist_ok=True)
        (ROOT / '04_analysis data' / chapter).mkdir(parents=True, exist_ok=True)

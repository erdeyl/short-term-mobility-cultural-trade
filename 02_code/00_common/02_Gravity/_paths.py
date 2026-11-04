from pathlib import Path
import sys
CODE_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(CODE_DIR.parent))
from project_paths import ROOT, COMMON_INT, DIAGNOSTICS

RAW = ROOT / '01_raw' / '01_Gravity'
INTERMEDIATE = COMMON_INT / '02_Gravity'
FINAL = INTERMEDIATE / 'source_tables'
DIAG = DIAGNOSTICS / '02_Gravity'
CONFIG = CODE_DIR / 'config'
GRAVITY = RAW / 'Gravity_V202211.dta'
COUNTRIES = RAW / 'Countries_V202211.dta'

def ensure_dirs():
    for path in (INTERMEDIATE, FINAL, DIAG):
        path.mkdir(parents=True, exist_ok=True)

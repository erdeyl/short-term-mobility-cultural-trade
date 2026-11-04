from pathlib import Path
import sys
CODE_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(CODE_DIR.parent))
from project_paths import ROOT, COMMON_INT, DIAGNOSTICS

RAW_CT = ROOT / '01_raw' / '02_UN_Comtrade'
RAW_AVAIL = RAW_CT / 'data_availability'
RAW_TRADE = RAW_CT / 'trade_api' / 'reported_HS'
RAW_REF = RAW_CT / 'reference'
RAW_META = RAW_CT / 'acquisition_metadata'
INTERMEDIATE_CT = COMMON_INT / '01_UN_Comtrade'
INT_AVAIL = INTERMEDIATE_CT / 'classification_availability'
INT_CONC = INTERMEDIATE_CT / 'concordance'
INT_REF = INTERMEDIATE_CT / 'reference'
FINAL_CT = INTERMEDIATE_CT / 'source_tables'
DIAG_CT = DIAGNOSTICS / '01_UN_Comtrade'
DIAG_AVAIL = DIAG_CT / 'classification_availability'
DIAG_CONC = DIAG_CT / 'concordance'
DIAG_DOWNLOAD = DIAG_CT / 'trade_download'
DIAG_BUILD = DIAG_CT / 'construction'
CONFIG = CODE_DIR / 'config'

def ensure_dirs():
    for path in (INT_AVAIL, INT_CONC, INT_REF, FINAL_CT,
                 DIAG_AVAIL, DIAG_CONC, DIAG_DOWNLOAD, DIAG_BUILD):
        path.mkdir(parents=True, exist_ok=True)

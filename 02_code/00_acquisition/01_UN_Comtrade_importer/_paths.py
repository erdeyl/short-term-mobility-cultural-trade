from pathlib import Path
CODE_DIR = Path(__file__).resolve().parent
ROOT = CODE_DIR.parents[2]
RAW_CT = ROOT / "01_raw" / "02_UN_Comtrade"
RAW_AVAIL = RAW_CT / "data_availability"
RAW_TRADE = RAW_CT / "trade_api" / "reported_HS"
RAW_REF = RAW_CT / "reference"
RAW_META = RAW_CT / "acquisition_metadata"
INTERMEDIATE_CT = ROOT / "03_intermediate" / "02_UN_Comtrade"
INT_AVAIL = INTERMEDIATE_CT / "classification_availability"
INT_CONC = INTERMEDIATE_CT / "concordance"
INT_REF = INTERMEDIATE_CT / "reference"
FINAL_CT = ROOT / "04_final_source_tables" / "UN_Comtrade"
DIAG_CT = ROOT / "05_diagnostics" / "UN_Comtrade"
DIAG_AVAIL = DIAG_CT / "classification_availability"
DIAG_CONC = DIAG_CT / "concordance"
DIAG_DOWNLOAD = DIAG_CT / "trade_download"
DIAG_BUILD = DIAG_CT / "construction"
MASTER_INT = ROOT / "06_master" / "intermediate"
CONFIG = CODE_DIR / "config"
def ensure_dirs():
    for p in [RAW_AVAIL,RAW_TRADE,RAW_REF,RAW_META,INT_AVAIL,INT_CONC,INT_REF,FINAL_CT,DIAG_AVAIL,DIAG_CONC,DIAG_DOWNLOAD,DIAG_BUILD,MASTER_INT]:
        p.mkdir(parents=True, exist_ok=True)

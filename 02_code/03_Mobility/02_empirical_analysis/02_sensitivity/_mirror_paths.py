from pathlib import Path
import sys
for _parent in Path(__file__).resolve().parents:
    if (_parent / 'chapter_paths.py').is_file():
        sys.path.insert(0, str(_parent))
        break
from chapter_paths import *
CODE_DIR = Path(__file__).resolve().parent
MAIN_CT_CODE = ROOT / '02_code/00_common/01_UN_Comtrade'
MAIN_INT = COMMON_INT / '01_UN_Comtrade'
MAIN_AVAIL = MAIN_INT / 'classification_availability/reported_classification_availability_2007_2021.csv'
MAIN_TARGETS = MAIN_INT / 'concordance/reported_HS_download_targets_by_version.csv'
MAIN_CONCORD = MAIN_INT / 'concordance/reported_HS_to_H3_concordance.csv'
MAIN_PREF = MAIN_INT / 'reference/partner_reference.csv'
RAW_ROOT = ROOT / '01_raw/02_UN_Comtrade/mirror_exporter_reported'
RAW_FLOW_AVAIL = RAW_ROOT / 'export_flow_availability'
RAW_TRADE = RAW_ROOT / 'trade_api/reported_HS'
RAW_META = RAW_ROOT / 'acquisition_metadata'
DIAG_ROOT = DIAGNOSTICS / 'UN_Comtrade_mirror'
DIAG_DOWNLOAD = DIAG_ROOT / 'download'
DIAG_BUILD = DIAG_ROOT / 'construction'
FINAL_CT = SOURCES / 'UN_Comtrade_mirror'
FINAL_EXPORT = FINAL_CT / 'cultural_trade_exporter_reported_2007_2021.dta'
FINAL_EXPORT_CSV = FINAL_EXPORT.with_suffix('.csv')
FINAL_EXPORT_AVAIL = FINAL_CT / 'exporter_year_availability_2007_2021.dta'
FINAL_EXPORT_AVAIL_CSV = FINAL_EXPORT_AVAIL.with_suffix('.csv')
PREPARED_LB = RUNTIME / 'core/LB/analysis_prepared.dta'
SENS_ROOT = EMPIRICAL / '02_sensitivity/04_mirror_trade'
SENS_DATA = INTERMEDIATE / 'sensitivity/04_mirror_trade'
SENS_TABLES = SENS_ROOT / 'tables'
SENS_DIAG = DIAGNOSTICS / 'sensitivity/04_mirror_trade'
SENS_LOGS = LOGS / 'sensitivity/04_mirror_trade'
def ensure_dirs():
    for p in (DIAG_ROOT,DIAG_DOWNLOAD,DIAG_BUILD,FINAL_CT,SENS_ROOT,SENS_DATA,SENS_TABLES,SENS_DIAG,SENS_LOGS):
        p.mkdir(parents=True,exist_ok=True)

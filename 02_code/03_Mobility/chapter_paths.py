"""Paths for the mobility chapter; the project root is detected automatically."""
from pathlib import Path
CHAPTER_ID = 'MOBILITY'
CHAPTER_CODE = Path(__file__).resolve().parent
ROOT = CHAPTER_CODE.parents[1]
RAW = ROOT / '01_raw/05_Mobility'
INTERMEDIATE = ROOT / '03_intermediate/03_Mobility'
SOURCES = INTERMEDIATE / 'source_tables'
ANALYSIS = ROOT / '04_analysis data/03_Mobility'
ANALYSIS_FILE = ANALYSIS / 'mobility_analysis_2007_2021.dta'
OUTPUT = ROOT / '05_output/03_Mobility'
DIAGNOSTICS = OUTPUT / '01_diagnostics'
EMPIRICAL = OUTPUT / '02_empirical_analysis'
LOGS = OUTPUT / '03_logs'
RUNTIME = INTERMEDIATE / 'runtime'
COMMON_INT = ROOT / '03_intermediate/00_common'
COMMON_BASE = COMMON_INT / 'cultural_trade_gravity_base_2007_2021.dta'
COMMON_MARKER = ROOT / '05_output/00_common/01_diagnostics/03_base/COMMON_BASE_BUILD_COMPLETE.txt'
CHAPTER_MERGED = INTERMEDIATE / 'master/mobility_merged_2007_2021.dta'

def ensure_dirs():
    for path in (INTERMEDIATE,SOURCES,ANALYSIS,DIAGNOSTICS,EMPIRICAL,LOGS,RUNTIME,CHAPTER_MERGED.parent):
        path.mkdir(parents=True,exist_ok=True)

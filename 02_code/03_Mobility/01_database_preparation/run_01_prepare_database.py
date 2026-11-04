from pathlib import Path
import sys
for _parent in Path(__file__).resolve().parents:
    if (_parent / 'chapter_paths.py').is_file():
        sys.path.insert(0, str(_parent))
        break
from chapter_paths import *
from chapter_runtime import require_common, find_stata, run_logged, invalidate_completion
ensure_dirs()
invalidate_completion('build')
require_common()
find_stata()
HERE=Path(__file__).resolve().parent
for p in [INTERMEDIATE/'01_UN_Tourism',SOURCES/'UN_Tourism',
          DIAGNOSTICS/'UN_Tourism',DIAGNOSTICS/'analysis_inputs',LOGS/'analysis_inputs']:
    p.mkdir(parents=True,exist_ok=True)
def py(rel):return [sys.executable,'-u',str(HERE/rel)]
def stata(rel,marker):return [sys.executable,'-u',str(CHAPTER_CODE/'chapter_runtime.py'),
                             str(HERE/rel),'--marker',str(marker)]
steps=[
 ('Raw preflight',py('00_check_raw_inputs.py')),
 ('Stata temporary-directory check',[sys.executable,'-u',str(CHAPTER_CODE/'chapter_runtime.py'),'--preflight']),
 ('UN Tourism',stata('01_UN_Tourism/01_build_UN_Tourism.do',DIAGNOSTICS/'UN_Tourism/BUILD_COMPLETE.txt')),
 ('Hofstede extraction',py('02_Hofstede/00_extract_and_audit_hofstede_source.py')),
 ('Hofstede distance',py('02_Hofstede/01_build_bilateral_cultural_distance.py')),
 ('Master source schemas',py('03_master/00_validate_master_sources.py')),
 ('Merge mobility variables',py('03_master/01_build_master_panel.py')),
 ('Validate mobility master',py('03_master/02_validate_master_panel.py')),
 ('Master documentation',py('03_master/03_export_master_documentation.py')),
 ('LB and UB analysis files',stata('04_build_analysis_inputs.do',DIAGNOSTICS/'analysis_inputs/00_DIRECT_INPUT_BUILD_COMPLETE.txt')),
 ('Analysis-file readback',py('05_validate_analysis_inputs.py')),
 ('Archived exporter mirror',py('04_UN_Comtrade_mirror/03_build_exporter_reported_cultural_trade.py')),
]
run_logged(steps,'mobility_database.log',DIAGNOSTICS/'MOBILITY_DATABASE_COMPLETE.txt')

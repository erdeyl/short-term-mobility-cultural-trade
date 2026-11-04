from pathlib import Path
import sys
for _parent in Path(__file__).resolve().parents:
    if (_parent / 'chapter_paths.py').is_file():
        sys.path.insert(0, str(_parent))
        break
from chapter_paths import *
CODE_DIR = Path(__file__).resolve().parent
TOURISM = SOURCES / 'UN_Tourism/tourism_residence_first_2007_2021.dta'
HOFSTEDE = SOURCES / 'Hofstede/hofstede_bilateral_cultural_distance.dta'
MASTER_INT = INTERMEDIATE / 'master'
MASTER_FINAL = MASTER_INT
MASTER_DIAG = DIAGNOSTICS / 'Master'
CONFIG = CODE_DIR / 'config'
def ensure_dirs():
    for p in (MASTER_INT,MASTER_DIAG):
        p.mkdir(parents=True,exist_ok=True)

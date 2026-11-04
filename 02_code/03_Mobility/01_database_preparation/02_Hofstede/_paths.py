from pathlib import Path
import sys
for _parent in Path(__file__).resolve().parents:
    if (_parent / 'chapter_paths.py').is_file():
        sys.path.insert(0, str(_parent))
        break
from chapter_paths import *
CODE_DIR = Path(__file__).resolve().parent
CONFIG = CODE_DIR / 'config'
INTERMEDIATE = INTERMEDIATE / '02_Hofstede'
FINAL = SOURCES / 'Hofstede'
DIAG = DIAGNOSTICS / 'Hofstede'
MASTER_INT = INTERMEDIATE / 'merge_inputs'
def ensure_dirs():
    for p in (INTERMEDIATE,FINAL,DIAG,MASTER_INT):
        p.mkdir(parents=True,exist_ok=True)

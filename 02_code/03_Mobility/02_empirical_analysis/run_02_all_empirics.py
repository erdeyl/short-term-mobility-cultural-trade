from pathlib import Path
import sys
for _parent in Path(__file__).resolve().parents:
    if (_parent / 'chapter_paths.py').is_file():
        sys.path.insert(0, str(_parent))
        break
from chapter_paths import *
from chapter_runtime import find_stata, run_logged, invalidate_completion
ensure_dirs()
invalidate_completion('empirical')
find_stata()
HERE=Path(__file__).resolve().parent
if not (DIAGNOSTICS/'MOBILITY_DATABASE_COMPLETE.txt').is_file():
    raise SystemExit('Run RUN_01_PREPARE_DATABASE.bat successfully before empirical analysis.')
def py(rel,args=()):return [sys.executable,'-u',str(HERE/rel),*args]
def stata(rel,stage,marker):
    for p in [EMPIRICAL/'02_sensitivity'/stage/'tables',DIAGNOSTICS/'sensitivity'/stage,
              LOGS/'sensitivity'/stage,INTERMEDIATE/'sensitivity'/stage]:
        p.mkdir(parents=True,exist_ok=True)
    return [sys.executable,'-u',str(CHAPTER_CODE/'chapter_runtime.py'),str(HERE/rel),
            '--marker',str(DIAGNOSTICS/'sensitivity'/stage/marker)]
steps=[
 ('Stata environment and packages',[sys.executable,'-u',str(CHAPTER_CODE/'chapter_runtime.py'),'--preflight','--packages']),
 ('Core LB',py('01_core/run_core.py',['LB'])),
 ('Core UB',py('01_core/run_core.py',['UB'])),
 ('Common support',stata('02_sensitivity/01_common_support_visitors_tourists.do','01_common_support','01_COMMON_SUPPORT_COMPLETE.txt')),
 ('Formal equality',stata('02_sensitivity/02_formal_equality_visitors_tourists.do','02_formal_equality','02_FORMAL_EQUALITY_COMPLETE.txt')),
 ('PPML bias correction',stata('02_sensitivity/03_ppml_bias_correction.do','03_ppml_bias_correction','03_PPML_BIAS_CORRECTION_COMPLETE.txt')),
 ('Mirror input',py('02_sensitivity/04_build_mirror_analysis_input.py')),
 ('Mirror sensitivity',stata('02_sensitivity/04_run_mirror_sensitivity.do','04_mirror_trade','05_MIRROR_SENSITIVITY_COMPLETE.txt')),
 ('Reconciled trade',stata('02_sensitivity/05_run_reconciled_trade_sensitivity.do','04_mirror_trade/reconciled','06_RECONCILED_TRADE_SENSITIVITY_COMPLETE.txt')),
]
run_logged(steps,'mobility_empirical.log',DIAGNOSTICS/'MOBILITY_ALL_EMPIRICS_COMPLETE.txt')

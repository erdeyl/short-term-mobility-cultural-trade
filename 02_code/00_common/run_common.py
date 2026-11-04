"""Run the archived Comtrade -> Gravity -> common-base build."""
import argparse
import csv
import importlib
import os
from pathlib import Path
import subprocess
import sys
import time
from datetime import datetime, timezone
from project_paths import *  # RESCUE C01
import sys as _rescue_sys  # RESCUE C01
from pathlib import Path as _RescuePath  # RESCUE C01
_RESCUE = next(p for p in _RescuePath(__file__).resolve().parents if p.name == '02_code') / '99_rescue'  # RESCUE C01
_rescue_sys.path.insert(0, str(_RESCUE))  # RESCUE C01
import rescue_switch  # RESCUE C01

STEPS = {
    'comtrade': [
        '01_UN_Comtrade/00_validate_and_prepare.py',
        '01_UN_Comtrade/01_build_reported_classification_audit.py',
        '01_UN_Comtrade/02_build_HS_concordance.py',
        '01_UN_Comtrade/04_build_comtrade_references.py',
        '01_UN_Comtrade/05_build_cultural_trade.py',
    ],
    'gravity': ['02_Gravity/00_validate_cepii_source.py',
                '02_Gravity/01_audit_and_extract_gravity_v202211.py'],
    'base': ['03_base/01_build_common_base.py', '03_base/02_validate_common_base.py'],
}

def required_paths(stage):
    groups = list(STEPS) if stage == 'all' else [stage]
    paths = []
    if 'comtrade' in groups:
        ct = RAW_ROOT / '02_UN_Comtrade'
        paths += [ct / 'data_availability' / f'getDa_HS_{y}.json' for y in range(2007, 2022)]
        paths += [ct / 'reference' / fn for fn in
                  ('HS-SITC-BEC_Correlations_2022.xlsx', 'Reporters.json', 'partnerAreas.json')]
        paths += [ct / 'acquisition_metadata/download_manifest.csv']
        folder = ct / 'trade_api/reported_HS'
        if len(list(folder.glob('*.csv'))) != 330:
            raise ValueError(f'Expected 330 archived Comtrade CSV files in {folder}')
    if 'gravity' in groups:
        paths += [RAW_ROOT / '01_Gravity' / name for name in ('Gravity_V202211.dta', 'Countries_V202211.dta')]
    if stage == 'base':
        paths += [COMMON_INT / name for name in (
            '01_UN_Comtrade/source_tables/cultural_trade_sparse_2007_2021.dta',
            '01_UN_Comtrade/source_tables/reporter_year_availability_2007_2021.dta',
            '02_Gravity/source_tables/cepii_gravity_rta_2007_2021.dta')]
    return paths

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--stage', choices=('all', 'comtrade', 'gravity', 'base'), default='all')
    parser.add_argument('--check', action='store_true', help='Check paths and dependencies only')
    args = parser.parse_args()
    ensure_common_dirs()
    logfile = LOGS / ('common_check.log' if args.check and rescue_switch.enabled('C01') else 'common_latest.log')  # RESCUE C01
    statusfile = LOGS / ('common_check_status.csv' if args.check and rescue_switch.enabled('C01') else 'common_run_status.csv')  # RESCUE C01
    marker = BASE_DIAG / 'COMMON_BASE_BUILD_COMPLETE.txt'
    if not args.check:
        marker.unlink(missing_ok=True)
    status = []

    def save_status():
        with statusfile.open('w', encoding='utf-8-sig', newline='') as out:
            writer = csv.DictWriter(out, fieldnames=['step', 'status', 'seconds'])
            writer.writeheader()
            writer.writerows(status)

    with logfile.open('w', encoding='utf-8') as log:
        def emit(line):
            print(line, flush=True)
            log.write(line + '\n')
            log.flush()
        try:
            emit('COMMON DISSERTATION BASE | ' + datetime.now(timezone.utc).isoformat())
            emit('Project root: ' + str(ROOT))
            emit('Python: ' + sys.version.split()[0])
            emit('Requested stage: ' + args.stage + (' (preflight only)' if args.check else ''))
            if sys.version_info < (3, 10) or not __debug__:
                raise RuntimeError('Use Python 3.10 or later without -O / PYTHONOPTIMIZE.')
            for name in ('pandas', 'numpy', 'openpyxl'):
                try:
                    module = importlib.import_module(name)
                except ImportError:
                    raise RuntimeError(f'Missing {name}. Run INSTALL_REQUIREMENTS.bat in this folder.')
                emit(name + ': ' + module.__version__)
            missing = [str(p) for p in required_paths(args.stage) if not p.is_file()]
            if missing:
                raise FileNotFoundError('Required files missing:\n' + '\n'.join(missing))
            emit('PREFLIGHT=PASS')
            status.append({'step':'preflight', 'status':'PASS', 'seconds':0})
            save_status()
            if args.check:
                emit('PREFLIGHT_ONLY_COMPLETE; no datasets were built.')
                return 0
            ensure_chapter_dirs()
            groups = list(STEPS) if args.stage == 'all' else [args.stage]
            env = os.environ.copy()
            env.update(PYTHONIOENCODING='utf-8', PYTHONUTF8='1')
            for group in groups:
                for relative in STEPS[group]:
                    script = COMMON_CODE / relative
                    emit('\nRunning ' + relative)
                    started = time.monotonic()
                    with subprocess.Popen([sys.executable, '-u', str(script)], cwd=ROOT,
                                          stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                          text=True, encoding='utf-8', errors='replace', env=env) as process:
                        for line in process.stdout:
                            emit(line.rstrip('\n'))
                        code = process.wait()
                    status.append({'step':relative, 'status':'PASS' if code == 0 else 'FAIL',
                                   'seconds':round(time.monotonic()-started, 2)})
                    save_status()
                    if code:
                        raise RuntimeError(f'Step failed (exit {code}): {relative}')
            if args.stage in ('all', 'base'):
                marker.write_text('COMMON_BASE_BUILD_COMPLETE=yes\n'
                                  'base=' + BASE_DTA.relative_to(ROOT).as_posix() + '\n'
                                  'completed_utc=' + datetime.now(timezone.utc).isoformat() + '\n', encoding='utf-8')
                emit('\nCOMMON_BASE_BUILD_COMPLETE=yes')
                emit('Final base: ' + str(BASE_DTA))
            else:
                emit('\nREQUESTED_STAGE_COMPLETE=' + args.stage)
                emit('Rebuild the base after both source stages are current.')
            emit('Log: ' + str(logfile))
            return 0
        except Exception as exc:
            emit('\nSTOPPED: ' + str(exc))
            emit('No common-base completion marker was issued for this run.')
            status.append({'step':'run', 'status':'FAIL', 'seconds':0})
            save_status()
            return 1

if __name__ == '__main__':
    raise SystemExit(main())

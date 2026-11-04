from pathlib import Path
import sys
for _parent in Path(__file__).resolve().parents:
    if (_parent / 'chapter_paths.py').is_file():
        sys.path.insert(0, str(_parent))
        break
from chapter_paths import *
import subprocess
import re
from chapter_runtime import find_stata,stata_command,env_for_stata
HERE=Path(__file__).resolve().parent
MODULES = [
    "01_setup.do",
    "02_prepare_data.do",
    "03_table1_descriptives.do",
    "04_table2_baseline.do",
    "05_table3_dynamic.do",
    "06_table4_categories.do",
    "07_table5_moderators.do",
    "08_table6_robustness.do",
    "09_tableA1_positive_trade.do",
    "10_validation.do",
]

def spath(p):
    return str(p).replace("\\", "/")

def run(tag):
    tag = tag.upper()
    if tag not in {"LB", "UB"}:
        raise SystemExit("Core run tag must be LB or UB.")

    missing = [m for m in MODULES if not (HERE/m).exists()]
    if missing:
        raise SystemExit("CORE_CODE_MISSING:\n  " + "\n  ".join(missing))

    stata = find_stata()
    if not stata:
        raise SystemExit(
            "Stata 18 executable not found. Set STATA_EXE to the full path of "
            "your Stata executable and rerun."
        )

    data = ANALYSIS / ('mobility_analysis_2007_2021.dta' if tag=='LB' else 'mobility_analysis_UB_2007_2021.dta')
    if not data.exists():
        raise SystemExit(
            f"Missing estimation input: {data}\nRun RUN_01_PREPARE_DATABASE.bat."
        )

    run_root = EMPIRICAL/'01_core'/tag
    runtime = RUNTIME/'core'/tag
    core_logs = LOGS/'core'/tag
    core_diag = DIAGNOSTICS/'core'/tag
    for p in (run_root/'tables',runtime,core_logs,core_diag):
        p.mkdir(parents=True,exist_ok=True)
    (core_logs/'00_core_run.log').unlink(missing_ok=True)
    (runtime/'analysis_prepared.dta').unlink(missing_ok=True)

    bootstrap = [
        "clear all",
        "set more off",
        "set linesize 255",
        "version 18.0",
        f'global REPL_CODE "{spath(HERE)}"',
        f'global PROJECT_ROOT "{spath(ROOT)}"',
        f'global DATA_FILE "{spath(data)}"',
        f'global RUN_TAG "{tag}"',
        f'global RUN_ROOT "{spath(run_root)}"',
        'global TABLE_DIR "${RUN_ROOT}/tables"',
        f'global LOG_DIR "{spath(core_logs)}"',
        f'global DIAG_DIR "{spath(core_diag)}"',
        f'global CACHE_DIR "{spath(runtime)}"',
        'capture log close _all',
        'log using "${LOG_DIR}/00_core_run.log", replace text name(master)',
        f'display as result "CORE_{tag}_BEGIN=yes"',
        "local modules ///",
    ]

    for i, m in enumerate(MODULES):
        bootstrap.append(f'    "{m}"' + (" ///" if i < len(MODULES)-1 else ""))

    bootstrap += [
        "foreach module of local modules {",
        '    display as result "MODULE_BEGIN=`module\'"',
        '    capture noisily do "${REPL_CODE}/`module\'"',
        "    local module_rc = _rc",
        "    if `module_rc' != 0 {",
        '        display as error "MODULE_FAILED=`module\' RC=`module_rc\'"',
        "        log close master",
        "        exit `module_rc'",
        "    }",
        '    display as result "MODULE_COMPLETE=`module\'"',
        "}",
        f'display as result "CORE_{tag}=PASS"',
        "log close master",
        "exit 0",
    ]

    boot = runtime/f"00_bootstrap_{tag}.do"
    boot.write_text("\n".join(bootstrap)+"\n", encoding="utf-8")

    subprocess.run(stata_command(stata,boot), cwd=core_logs,env=env_for_stata(),check=True)

    log = core_logs/"00_core_run.log"
    if not log.exists():
        raise SystemExit(f"Core {tag} failed before log creation.")

    text = log.read_text(encoding="utf-8-sig", errors="replace")
    if not re.search(rf"(?m)^\s*CORE_{tag}=PASS\s*$", text):
        print("\nLAST 120 LINES OF CORE LOG:\n")
        print("\n".join(text.splitlines()[-120:]))
        raise SystemExit(f"CORE_{tag}=FAIL. Full log: {log}")

    if not (runtime/"analysis_prepared.dta").exists():
        raise SystemExit(
            f"Core {tag} completed but analysis_prepared.dta is missing."
        )

    print(f"CORE_{tag}=PASS")
    print("Results:", run_root)

if __name__ == "__main__":
    run(sys.argv[1] if len(sys.argv) > 1 else "LB")

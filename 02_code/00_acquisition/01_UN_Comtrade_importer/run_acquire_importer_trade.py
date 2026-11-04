from pathlib import Path
import subprocess, sys
HERE=Path(__file__).resolve().parent
for s in [
    "01_build_reported_classification_audit.py",
    "02_build_HS_concordance.py",
    "03_download_reported_HS_trade.py",
]:
    print("\nRUN:",s)
    r=subprocess.run([sys.executable,str(HERE/s)],cwd=HERE)
    if r.returncode!=0: raise SystemExit(r.returncode)
print("IMPORTER_COMTRADE_ACQUISITION=PASS")

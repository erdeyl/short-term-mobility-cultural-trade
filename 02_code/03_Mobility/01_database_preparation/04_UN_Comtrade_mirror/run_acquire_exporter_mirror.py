from pathlib import Path
import os, sys, subprocess
from getpass import getpass

HERE=Path(__file__).resolve().parent
key=os.environ.get("COMTRADE_API_KEY","").strip()
if not key:
    key=getpass("Paste CURRENT UN Comtrade Primary key: ").strip()
if not key:
    raise SystemExit("No COMTRADE_API_KEY supplied.")
env=os.environ.copy()
env["COMTRADE_API_KEY"]=key
for s in ["01_download_export_flow_availability.py","02_download_exporter_reported_HS_trade.py"]:
    print("\nRUN:",s)
    r=subprocess.run([sys.executable,str(HERE/s)],cwd=HERE,env=env)
    if r.returncode!=0: raise SystemExit(r.returncode)
print("EXPORTER_MIRROR_COMTRADE_ACQUISITION=PASS")

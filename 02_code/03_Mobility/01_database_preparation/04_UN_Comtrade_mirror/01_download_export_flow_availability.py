from pathlib import Path
import os, time, json, hashlib
import pandas as pd
import requests
from _mirror_paths import *

ensure_dirs()
for raw_folder in (RAW_FLOW_AVAIL, RAW_TRADE, RAW_META):
    raw_folder.mkdir(parents=True, exist_ok=True)

API_KEY = os.environ.get("COMTRADE_API_KEY","").strip()
if not API_KEY:
    raise SystemExit("COMTRADE_API_KEY is not set.")

REPORTER_BATCH = int(os.environ.get("COMTRADE_AVAIL_REPORTER_BATCH","50"))
SLEEP_SECONDS = float(os.environ.get("COMTRADE_SLEEP_SECONDS","0.8"))
MAX_NEW_CALLS = int(os.environ.get("COMTRADE_MAX_NEW_CALLS","500"))
MAXROWS = 100000
URL = "https://comtradeapi.un.org/data/v1/get/C/A/HS"

avail = pd.read_csv(MAIN_AVAIL)
manifest_path = RAW_META / "export_flow_availability_manifest.csv"
status_path = DIAG_DOWNLOAD / "EXPORT_FLOW_AVAILABILITY_DOWNLOAD_COMPLETE.txt"

if manifest_path.exists():
    manifest = pd.read_csv(manifest_path)
else:
    manifest = pd.DataFrame(columns=[
        "year","reporter_batch","status","api_count","data_rows","filename","error"
    ])

def save_manifest():
    manifest.to_csv(manifest_path, index=False, encoding="utf-8-sig")

def chunks(items,n):
    items=list(items)
    for i in range(0,len(items),n):
        yield items[i:i+n]

new_calls=0

def upsert_manifest(row):
    global manifest
    fn=row["filename"]
    if len(manifest):
        manifest=manifest.loc[manifest["filename"].astype(str)!=str(fn)].copy()
    manifest.loc[len(manifest)] = row
    save_manifest()

def request_batch(year, reporters):
    global new_calls
    repstr=",".join(str(int(x)) for x in reporters)
    stem=f"X_TOTAL_{year}_R{hashlib.md5(repstr.encode()).hexdigest()[:10]}"
    outfile=RAW_FLOW_AVAIL/f"{stem}.csv"

    if outfile.exists() and len(manifest):
        ok=manifest.loc[
            (manifest["filename"].astype(str)==outfile.name) &
            (manifest["status"].astype(str)=="DOWNLOADED_OK")
        ]
        if len(ok)==1:
            print("SKIP existing:", outfile.name)
            return

    if new_calls>=MAX_NEW_CALLS:
        raise RuntimeError("DAILY_SAFETY_STOP")

    params={
        "period":str(year),
        "reporterCode":repstr,
        "cmdCode":"TOTAL",
        "flowCode":"X",
        "partnerCode":"0",
        "partner2Code":"0",
        "customsCode":"C00",
        "motCode":"0",
        "maxrecords":str(MAXROWS),
    }

    for attempt in range(1,6):
        try:
            print(f"GET export availability year={year} reporters={len(reporters)} attempt={attempt}")
            r=requests.get(
                URL, params=params, timeout=180,
                headers={"User-Agent":"academic-replication-pipeline/1.0", "Ocp-Apim-Subscription-Key":API_KEY}  # key in a header, not in the URL
            )
            new_calls+=1

            if r.status_code==429:
                time.sleep(20*attempt)
                continue
            if r.status_code in (500,502,503,504):
                if len(reporters)>1:
                    mid=len(reporters)//2
                    request_batch(year, reporters[:mid])
                    request_batch(year, reporters[mid:])
                    return
                raise RuntimeError(f"HTTP {r.status_code} on atomic availability query.")
            if r.status_code!=200:
                raise RuntimeError(f"HTTP {r.status_code}: {r.text[:500]}")

            payload=r.json()
            data=payload.get("data",[])
            api_count=payload.get("count")
            if (isinstance(api_count,int) and api_count>MAXROWS) or len(data)>=MAXROWS:
                if len(reporters)>1:
                    mid=len(reporters)//2
                    request_batch(year, reporters[:mid])
                    request_batch(year, reporters[mid:])
                    return
                raise RuntimeError("Atomic availability query exceeds record ceiling.")

            df=pd.DataFrame(data)
            if len(df):
                if "refYear" in df.columns and not (pd.to_numeric(df["refYear"],errors="coerce")==year).all():
                    raise RuntimeError("Availability query returned wrong year.")
                if "flowCode" in df.columns and not (df["flowCode"].astype(str)=="X").all():
                    raise RuntimeError("Availability query returned non-export flow.")
                if "reporterCode" in df.columns:
                    returned=set(pd.to_numeric(df["reporterCode"],errors="coerce").dropna().astype(int))
                    requested=set(int(x) for x in reporters)
                    if not returned.issubset(requested):
                        raise RuntimeError("Availability response contains an unrequested reporter.")

            df.to_csv(outfile,index=False,encoding="utf-8-sig")
            upsert_manifest({
                "year":year,"reporter_batch":repstr,"status":"DOWNLOADED_OK",
                "api_count":api_count,"data_rows":len(df),
                "filename":outfile.name,"error":""
            })
            time.sleep(SLEEP_SECONDS)
            return
        except Exception as e:
            if str(e)=="DAILY_SAFETY_STOP":
                raise
            if attempt==5:
                upsert_manifest({
                    "year":year,"reporter_batch":repstr,"status":"FAILED",
                    "api_count":None,"data_rows":None,
                    "filename":outfile.name,"error":f"{type(e).__name__}: {e}"
                })
                raise
            time.sleep(5*attempt)

planned=[]
for year in sorted(avail["_query_year"].unique()):
    reps=sorted(avail.loc[avail["_query_year"]==year,"reporterCode"].astype(int).unique())
    for batch in chunks(reps,REPORTER_BATCH):
        planned.append((int(year),list(batch)))

try:
    for year,batch in planned:
        request_batch(year,batch)
except RuntimeError as e:
    if str(e)=="DAILY_SAFETY_STOP":
        print("DAILY_SAFETY_STOP=yes")
        print("Re-run RUN_04A_DOWNLOAD_EXPORTER_TRADE.bat later; successful files are resumed.")
        raise SystemExit(2)
    raise

# Validate all planned reporter-year requests are covered by successful manifest batches.
m=pd.read_csv(manifest_path)
m=m.loc[m["status"]=="DOWNLOADED_OK"].copy()
queried=set()
for _,r in m.iterrows():
    for rep in str(r["reporter_batch"]).split(","):
        queried.add((int(r["year"]),int(rep)))
expected=set((int(r["_query_year"]),int(r["reporterCode"])) for _,r in avail.iterrows())
if queried != expected:
    missing=sorted(expected-queried)
    raise RuntimeError(f"Export-flow availability download incomplete; missing {len(missing)} reporter-years.")

status_path.write_text(
    "EXPORT_FLOW_AVAILABILITY_DOWNLOAD_COMPLETE=yes\n"
    f"expected_reporter_years={len(expected)}\n"
    f"successful_manifest_rows={len(m)}\n",
    encoding="utf-8"
)
print("EXPORT_FLOW_AVAILABILITY_DOWNLOAD_COMPLETE=yes")

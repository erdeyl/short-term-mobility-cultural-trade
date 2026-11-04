from pathlib import Path
import os, time, hashlib
import pandas as pd
import requests
from _mirror_paths import *

ensure_dirs()
for raw_folder in (RAW_FLOW_AVAIL, RAW_TRADE, RAW_META):
    raw_folder.mkdir(parents=True, exist_ok=True)

API_KEY = os.environ.get("COMTRADE_API_KEY","").strip()
if not API_KEY:
    raise SystemExit("COMTRADE_API_KEY is not set.")

REPORTER_BATCH = int(os.environ.get("COMTRADE_REPORTER_BATCH","10"))
CODE_BATCH = int(os.environ.get("COMTRADE_CODE_BATCH","40"))
SLEEP_SECONDS = float(os.environ.get("COMTRADE_SLEEP_SECONDS","0.8"))
MAX_NEW_CALLS = int(os.environ.get("COMTRADE_MAX_NEW_CALLS","500"))
MAXROWS = 100000
URL = "https://comtradeapi.un.org/data/v1/get/C/A/HS"

avail=pd.read_csv(MAIN_AVAIL)
mp=pd.read_csv(MAIN_TARGETS,dtype={"source_code":"string"})
mp["source_code"]=mp["source_code"].str.zfill(6)

manifest_path=RAW_META/"exporter_trade_download_manifest.csv"
status_path=DIAG_DOWNLOAD/"EXPORTER_REPORTED_TRADE_DOWNLOAD_COMPLETE.txt"

if manifest_path.exists():
    manifest=pd.read_csv(manifest_path)
else:
    manifest=pd.DataFrame(columns=[
        "year","classification","reporter_batch","code_batch","status",
        "api_count","data_rows","filename","error"
    ])

def save_manifest():
    manifest.to_csv(manifest_path,index=False,encoding="utf-8-sig")

def chunks(items,n):
    items=list(items)
    for i in range(0,len(items),n):
        yield items[i:i+n]

def upsert_manifest(row):
    global manifest
    fn=row["filename"]
    if len(manifest):
        manifest=manifest.loc[manifest["filename"].astype(str)!=str(fn)].copy()
    manifest.loc[len(manifest)] = row
    save_manifest()

new_calls=0

def request_data(year,version,reporters,codes):
    global new_calls
    repstr=",".join(str(int(x)) for x in reporters)
    codestr=",".join(str(x) for x in codes)
    stem=(
        f"X_HS_{year}_{version}_"
        f"R{hashlib.md5(repstr.encode()).hexdigest()[:8]}_"
        f"C{hashlib.md5(codestr.encode()).hexdigest()[:8]}"
    )
    outfile=RAW_TRADE/f"{stem}.csv"

    if outfile.exists() and len(manifest):
        ok=manifest.loc[
            (manifest["filename"].astype(str)==outfile.name) &
            (manifest["status"].astype(str)=="DOWNLOADED_OK")
        ]
        if len(ok)==1:
            print("SKIP existing:",outfile.name)
            return

    if new_calls>=MAX_NEW_CALLS:
        raise RuntimeError("DAILY_SAFETY_STOP")

    params={
        "period":str(year),
        "reporterCode":repstr,
        "cmdCode":codestr,
        "flowCode":"X",
        "partner2Code":"0",
        "customsCode":"C00",
        "motCode":"0",
        "maxrecords":str(MAXROWS),
        "subscription-key":API_KEY,
    }

    for attempt in range(1,6):
        try:
            print(
                f"GET exporter trade year={year} version={version} "
                f"reporters={len(reporters)} codes={len(codes)} attempt={attempt}"
            )
            r=requests.get(
                URL,params=params,timeout=180,
                headers={"User-Agent":"academic-replication-pipeline/1.0"}
            )
            new_calls+=1

            if r.status_code==429:
                time.sleep(20*attempt)
                continue

            if r.status_code in (500,502,503,504):
                if len(reporters)>1:
                    mid=len(reporters)//2
                    request_data(year,version,reporters[:mid],codes)
                    request_data(year,version,reporters[mid:],codes)
                    return
                if len(codes)>1:
                    mid=len(codes)//2
                    request_data(year,version,reporters,codes[:mid])
                    request_data(year,version,reporters,codes[mid:])
                    return
                raise RuntimeError(f"HTTP {r.status_code} on atomic query.")

            if r.status_code!=200:
                raise RuntimeError(f"HTTP {r.status_code}: {r.text[:500]}")

            payload=r.json()
            data=payload.get("data",[])
            api_count=payload.get("count")
            n=len(data)

            if (isinstance(api_count,int) and api_count>MAXROWS) or n>=MAXROWS:
                if len(reporters)>1:
                    mid=len(reporters)//2
                    request_data(year,version,reporters[:mid],codes)
                    request_data(year,version,reporters[mid:],codes)
                    return
                if len(codes)>1:
                    mid=len(codes)//2
                    request_data(year,version,reporters,codes[:mid])
                    request_data(year,version,reporters,codes[mid:])
                    return
                raise RuntimeError("Atomic query exceeds record ceiling.")

            df=pd.DataFrame(data)
            if len(df):
                if "classificationCode" in df.columns:
                    if not (df["classificationCode"].astype(str)==str(version)).all():
                        raise RuntimeError("Returned classification mismatch.")
                if "classificationSearchCode" in df.columns:
                    if not (df["classificationSearchCode"].astype(str)=="HS").all():
                        raise RuntimeError("classificationSearchCode is not HS.")
                if "flowCode" in df.columns:
                    if not (df["flowCode"].astype(str)=="X").all():
                        raise RuntimeError("Non-export flow returned.")

            df.to_csv(outfile,index=False,encoding="utf-8-sig")
            upsert_manifest({
                "year":year,"classification":version,
                "reporter_batch":repstr,"code_batch":codestr,
                "status":"DOWNLOADED_OK","api_count":api_count,
                "data_rows":n,"filename":outfile.name,"error":""
            })
            time.sleep(SLEEP_SECONDS)
            return

        except Exception as e:
            if str(e)=="DAILY_SAFETY_STOP":
                raise
            if attempt==5:
                upsert_manifest({
                    "year":year,"classification":version,
                    "reporter_batch":repstr,"code_batch":codestr,
                    "status":"FAILED","api_count":None,"data_rows":None,
                    "filename":outfile.name,"error":f"{type(e).__name__}: {e}"
                })
                raise
            time.sleep(5*attempt)

try:
    for year in sorted(avail["_query_year"].unique()):
        yr=avail[avail["_query_year"]==year]
        for version in sorted(yr["classificationCode"].dropna().unique()):
            reporters=sorted(
                yr.loc[yr["classificationCode"]==version,"reporterCode"]
                .astype(int).unique()
            )
            codes=sorted(
                mp.loc[mp["source_version"]==version,"source_code"]
                .dropna().astype(str).unique()
            )
            if not reporters or not codes:
                continue
            for rbatch in chunks(reporters,REPORTER_BATCH):
                for cbatch in chunks(codes,CODE_BATCH):
                    request_data(int(year),str(version),list(rbatch),list(cbatch))
except RuntimeError as e:
    if str(e)=="DAILY_SAFETY_STOP":
        print("DAILY_SAFETY_STOP=yes")
        print("Re-run RUN_04A_DOWNLOAD_EXPORTER_TRADE.bat later; successful files are resumed.")
        raise SystemExit(2)
    raise

m=pd.read_csv(manifest_path)
m=m.loc[m["status"]=="DOWNLOADED_OK"].copy()

queried=set()
for _,row in m.iterrows():
    for rep in str(row["reporter_batch"]).split(","):
        queried.add((int(row["year"]),str(row["classification"]),int(rep)))
expected=set(
    (int(r["_query_year"]),str(r["classificationCode"]),int(r["reporterCode"]))
    for _,r in avail.iterrows()
)
if queried != expected:
    raise RuntimeError(
        f"Exporter trade download incomplete: reporter-year-version coverage differs by "
        f"{len(expected-queried)} missing cells."
    )

for (year,version),sub in m.groupby(["year","classification"]):
    got=set()
    for x in sub["code_batch"]:
        got.update(str(x).split(","))
    want=set(
        mp.loc[mp["source_version"]==version,"source_code"]
        .dropna().astype(str)
    )
    if got!=want:
        raise RuntimeError(f"Code coverage mismatch year={year} version={version}")

status_path.write_text(
    "EXPORTER_REPORTED_TRADE_DOWNLOAD_COMPLETE=yes\n"
    f"successful_manifest_rows={len(m)}\n"
    f"data_rows={int(pd.to_numeric(m['data_rows'],errors='coerce').fillna(0).sum())}\n"
    "flow=X_exports\n"
    "classification=HS_as_reported\n",
    encoding="utf-8"
)
print("EXPORTER_REPORTED_TRADE_DOWNLOAD_COMPLETE=yes")

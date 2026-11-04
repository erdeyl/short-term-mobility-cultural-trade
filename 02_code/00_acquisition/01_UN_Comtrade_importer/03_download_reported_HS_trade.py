from pathlib import Path
from getpass import getpass
import pandas as pd
import requests, time, json, hashlib, math, sys, os
from _paths import *
ensure_dirs()
ROOT = ROOT
INPUT_AVAIL = INT_AVAIL / "reported_classification_availability_2007_2021.csv"
INPUT_MAP = INT_CONC / "reported_HS_download_targets_by_version.csv"
RAW = RAW_TRADE
DIAG = DIAG_DOWNLOAD
manifest_path = RAW_META / "download_manifest.csv"
REPORTER_BATCH = int(os.environ.get("COMTRADE_REPORTER_BATCH","10"))
CODE_BATCH = int(os.environ.get("COMTRADE_CODE_BATCH","40"))
SLEEP_SECONDS = float(os.environ.get("COMTRADE_SLEEP_SECONDS","0.8"))
MAX_NEW_CALLS = int(os.environ.get("COMTRADE_MAX_NEW_CALLS","500"))
MAXROWS = 100000
existing_files = sorted(RAW.glob("*.csv"))
if manifest_path.exists():
    _m = pd.read_csv(manifest_path)
    if len(existing_files)==330 and len(_m)==330 and (_m["status"]=="DOWNLOADED_OK").all() and int(_m["data_rows"].sum())==1611818:
        print("ARCHIVED_TRADE_DOWNLOAD_ALREADY_COMPLETE=PASS")
        print("No API calls made.")
        raise SystemExit(0)

key = os.environ.get("COMTRADE_API_KEY", "").strip() or getpass("Paste CURRENT UN Comtrade Primary key, then press Enter: ").strip()
if not key:
    raise SystemExit("No API key entered.")

avail = pd.read_csv(INPUT_AVAIL)
mp = pd.read_csv(INPUT_MAP, dtype={"source_code":str})
mp["source_code"] = mp["source_code"].str.zfill(6)

manifest_path = RAW_META / "download_manifest.csv"
if manifest_path.exists():
    manifest = pd.read_csv(manifest_path)
else:
    manifest = pd.DataFrame(columns=[
        "year","classification","reporter_batch","code_batch","status",
        "api_count","data_rows","filename","error"
    ])

def save_manifest():
    manifest.to_csv(manifest_path, index=False, encoding="utf-8-sig")

def chunks(items, n):
    items = list(items)
    for i in range(0, len(items), n):
        yield items[i:i+n]

new_calls = 0

def request_data(year, version, reporters, codes, depth=0):
    global new_calls, manifest

    repstr = ",".join(str(int(x)) for x in reporters)
    codestr = ",".join(codes)
    stem = f"HS_{year}_{version}_R{hashlib.md5(repstr.encode()).hexdigest()[:8]}_C{hashlib.md5(codestr.encode()).hexdigest()[:8]}"
    outfile = RAW / f"{stem}.csv"

    if outfile.exists() and outfile.stat().st_size > 0:
        print("SKIP existing:", outfile.name)
        return

    if new_calls >= MAX_NEW_CALLS:
        print("DAILY_SAFETY_STOP=yes")
        print("Run the same script again later; existing files will be skipped.")
        save_manifest()
        raise SystemExit(0)

    params = {
        "period":str(year),
        "reporterCode":repstr,
        "cmdCode":codestr,
        "flowCode":"M",
        "partner2Code":"0",
        "customsCode":"C00",
        "motCode":"0",
        "maxrecords":str(MAXROWS),
        "subscription-key":key,
    }

    url = "https://comtradeapi.un.org/data/v1/get/C/A/HS"

    for attempt in range(1,6):
        try:
            print(f"GET year={year} version={version} reporters={len(reporters)} codes={len(codes)} attempt={attempt}")
            r = requests.get(url, params=params, timeout=180,
                             headers={"User-Agent":"academic-replication-pipeline/1.0"})
            new_calls += 1

            if r.status_code == 429:
                wait = 20 * attempt
                print(f"HTTP 429. Waiting {wait}s.")
                time.sleep(wait)
                continue

            if r.status_code in (500,502,503,504):
                # Split instead of repeatedly hammering a large query.
                if len(reporters) > 1:
                    mid = len(reporters)//2
                    request_data(year, version, reporters[:mid], codes, depth+1)
                    request_data(year, version, reporters[mid:], codes, depth+1)
                    return
                if len(codes) > 1:
                    mid = len(codes)//2
                    request_data(year, version, reporters, codes[:mid], depth+1)
                    request_data(year, version, reporters, codes[mid:], depth+1)
                    return
                raise RuntimeError(f"Server error HTTP {r.status_code} on atomic query.")

            if r.status_code != 200:
                raise RuntimeError(f"HTTP {r.status_code}: {r.text[:500]}")

            payload = r.json()
            data = payload.get("data", [])
            api_count = payload.get("count")
            n = len(data)

            # If count indicates truncation, split before saving.
            if (isinstance(api_count, int) and api_count > MAXROWS) or n >= MAXROWS:
                if len(reporters) > 1:
                    mid = len(reporters)//2
                    request_data(year, version, reporters[:mid], codes, depth+1)
                    request_data(year, version, reporters[mid:], codes, depth+1)
                    return
                if len(codes) > 1:
                    mid = len(codes)//2
                    request_data(year, version, reporters, codes[:mid], depth+1)
                    request_data(year, version, reporters, codes[mid:], depth+1)
                    return
                raise RuntimeError("Atomic query exceeds record ceiling.")

            df = pd.DataFrame(data)
            if not df.empty:
                # Mechanical provenance validation.
                if "classificationCode" in df.columns:
                    bad = df.loc[df["classificationCode"].astype(str) != str(version)]
                    if len(bad):
                        raise RuntimeError(
                            f"Returned classification mismatch: expected {version}, "
                            f"found {sorted(df['classificationCode'].astype(str).unique())}"
                        )
                if "classificationSearchCode" in df.columns:
                    bad = df.loc[df["classificationSearchCode"].astype(str) != "HS"]
                    if len(bad):
                        raise RuntimeError("classificationSearchCode is not HS.")
                if "flowCode" in df.columns:
                    bad = df.loc[df["flowCode"].astype(str) != "M"]
                    if len(bad):
                        raise RuntimeError("Non-import flow returned.")

            df.to_csv(outfile, index=False, encoding="utf-8-sig")

            manifest.loc[len(manifest)] = [
                year,version,repstr,codestr,"DOWNLOADED_OK",
                api_count,n,outfile.name,""
            ]
            save_manifest()
            print("OK:", outfile.name, "rows=", n, "api_count=", api_count)
            time.sleep(SLEEP_SECONDS)
            return

        except Exception as e:
            if attempt == 5:
                manifest.loc[len(manifest)] = [
                    year,version,repstr,codestr,"FAILED",
                    None,None,outfile.name,f"{type(e).__name__}: {e}"
                ]
                save_manifest()
                raise
            wait = 5 * attempt
            print(type(e).__name__, e)
            print(f"Waiting {wait}s before retry...")
            time.sleep(wait)

# Each reporter-year is queried only under its actual reported HS edition.
for year in sorted(avail["_query_year"].unique()):
    yr = avail[avail["_query_year"] == year]
    for version in sorted(yr["classificationCode"].dropna().unique()):
        reporters = sorted(yr.loc[yr["classificationCode"]==version, "reporterCode"].astype(int).unique())
        codes = sorted(mp.loc[mp["source_version"]==version, "source_code"].dropna().unique())

        if not reporters or not codes:
            continue

        for rbatch in chunks(reporters, REPORTER_BATCH):
            for cbatch in chunks(codes, CODE_BATCH):
                request_data(int(year), str(version), rbatch, list(cbatch))

# Completion marker
(ROOT / "DOWNLOAD_COMPLETE.txt").write_text(
    "COMTRADE_REPORTED_HS_DOWNLOAD_COMPLETE=yes\n"
    "years=2007-2021\n"
    "flow=M_imports\n"
    "classification=HS_as_reported\n"
    "canonical_target=H3_HS2007\n",
    encoding="utf-8"
)
print("COMTRADE_REPORTED_HS_DOWNLOAD_COMPLETE=yes")

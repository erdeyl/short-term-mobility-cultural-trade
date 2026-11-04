"""SW2_01: parse all 344 UN Tourism country workbooks (sheet 'Data') read-only into one long table.
Output: 05_output/11_data_screens/tourism_long.csv.gz + parse_manifest.csv.
Positive control: per-family row counts must equal the build's frozen counts
(PKG 01_build_UN_Tourism.do:116-119: NROW_TOUR_NAT 106612, NROW_TOUR_RES 161471,
NROW_VIS_NAT 93476, NROW_VIS_RES 127634) and file counts 61/131/45/107 (:111-114)."""
import sys
from pathlib import Path
import pandas as pd
sys.path.insert(0, str(Path(__file__).resolve().parent))
from SW2_xlsx import read_sheet

# package paths: ROOT = package root; screens write to 05_output/11_data_screens (not run by run_all.py)
ROOT = Path(__file__).resolve().parents[2]
W = ROOT
PKG = ROOT
RAW = ROOT / "01_raw/05_Mobility"
OUT = ROOT / "05_output/11_data_screens"
FAM = {"Tourists Arrivals by Nationality": ("TOUR", "NAT", "INBD_TRIP_NLTY_TOUR", 61, 106612),
       "Tourists Arrivals by Residence": ("TOUR", "RES", "INBD_TRIP_AREA_TOUR", 131, 161471),
       "Visitors Arrivals by Nationality": ("VSTR", "NAT", "INBD_TRIP_NLTY_VSTR", 45, 93476),
       "Visitors Arrivals by Residence": ("VSTR", "RES", "INBD_TRIP_AREA_VSTR", 107, 127634)}
COLS = ["reporter_area_code", "reporter_area_label", "indicator_code", "indicator_label",
        "indicator_previous_code", "partner_area_code", "partner_area_label", "year", "value",
        "flag", "flag_label", "unit", "notes"]

frames, man = [], []
for folder, (fam, basis, ind, nf_exp, nr_exp) in FAM.items():
    files = sorted((RAW / folder).glob("*.xlsx"))
    nrows = 0
    for f in files:
        rows = read_sheet(f, "Data")
        hdr = [h.strip() if h else h for h in rows[0]]
        missing = [c for c in COLS if c not in hdr]
        if missing:
            raise RuntimeError(f"{f.name}: missing columns {missing}; header={hdr}")
        idx = {c: hdr.index(c) for c in COLS}
        recs = []
        for r in rows[1:]:
            if not r or all(x is None or str(x).strip() == "" for x in r):
                continue
            rec = {c: (r[idx[c]] if idx[c] < len(r) else None) for c in COLS}
            recs.append(rec)
        df = pd.DataFrame(recs, columns=COLS)
        df["value_raw"] = df["value"]
        df["value"] = pd.to_numeric(df["value"], errors="coerce")
        for c in ["reporter_area_code", "partner_area_code", "year"]:
            df[c] = pd.to_numeric(df[c], errors="coerce").astype("Int64")
        df["family"], df["basis"], df["file"] = fam, basis, f.name
        df["file_start"] = int(f.name[8:12])
        df["file_end"] = int(f.name[12:16])
        nrows += len(df)
        man.append({"folder": folder, "file": f.name, "rows": len(df),
                    "reporter": int(df["reporter_area_code"].iloc[0]) if len(df) else None,
                    "ind_codes": ";".join(sorted(set(df["indicator_code"].dropna()))),
                    "units": ";".join(sorted(set(df["unit"].dropna()))),
                    "ymin": int(df["year"].min()), "ymax": int(df["year"].max())})
        frames.append(df)
    status = "PASS" if (len(files) == nf_exp and nrows == nr_exp) else "FAIL"
    print(f"PC_PARSE {folder}: files {len(files)} (exp {nf_exp}) rows {nrows} (exp {nr_exp}) -> {status}")
long = pd.concat(frames, ignore_index=True)
long.to_csv(OUT / "tourism_long.csv.gz", index=False, compression="gzip")
pd.DataFrame(man).to_csv(OUT / "parse_manifest.csv", index=False)
print("rows total", len(long))
print("indicator codes per family:", long.groupby(["family", "basis"])["indicator_code"].unique().to_dict())
print("units:", long["unit"].value_counts(dropna=False).to_dict())

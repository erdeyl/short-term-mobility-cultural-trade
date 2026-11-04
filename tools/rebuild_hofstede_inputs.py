"""rebuild_hofstede_inputs.py -- rebuild the first sheet of the build's Hofstede workbook from the official file alone.

The chapter build and the analysis read "6-dimensions-for-website-2015-08-16 (1).xls" (01_raw/05_Mobility): the official
2015-08-16 file with ISO code columns, 36 added economies and 14 economies whose missing scores were filled from the
official regional rows. That workbook is not public. This tool reads the public official file and two score-free tables
of derived/hofstede/ and writes
  <out>/rebuilt_package_sheet.json  every cell (type, value) of the workbook's first sheet, read by the chapter build
                                    (02_Hofstede/00_extract_and_audit_hofstede_source.py) when the workbook is absent;
  <out>/derived_package_xls_sheet_via_libreoffice.csv  the text export that A2_00a_hofstede_sheets.py writes from the
                                    workbook, read by A2_00_hofstede.py.
Tables: hofstede_package_workbook_layout.csv (one row per sheet row; per cell: O = the official cell of the row's
official code, R:<ctr> = the official cell of regional row <ctr>, T: text, N: number literal (ISO numeric codes only),
B: empty, E: error code); hofstede_regional_proxy_construction.csv (which economy takes which dimensions from which
regional row): every R cell is checked against it. No score is stored in either table.

Usage: python tools/rebuild_hofstede_inputs.py <official_xls> <out_dir> [--verify <workbook_xls>]
--verify compares the rebuilt sheet cell by cell (type and exact value) and the text export byte by byte with the
workbook, and exits 1 on any difference.
"""
import argparse, csv, json, sys, tempfile
from pathlib import Path

import xlrd

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "02_code" / "10_analysis"))
import A2_00a_hofstede_sheets as A  # the same cell rendering as the analysis export

SCORE = {2: "pdi", 3: "idv", 4: "mas", 5: "uai", 6: "lto", 7: "ivr"}
LAYOUT = ROOT / "derived" / "hofstede" / "hofstede_package_workbook_layout.csv"
CONSTR = ROOT / "derived" / "hofstede" / "hofstede_regional_proxy_construction.csv"
OFFICIAL_SHA = "e0be0407209aeaca272377aa7508b54da339d121c103f5a20c90bf78f8580cc3"


def rebuild(official_xls):
    import hashlib
    if hashlib.sha256(Path(official_xls).read_bytes()).hexdigest() != OFFICIAL_SHA:
        raise SystemExit(f"{official_xls}: SHA-256 differs from the official 2015-08-16 file ({OFFICIAL_SHA})")
    o = xlrd.open_workbook(official_xls).sheet_by_index(0)
    orow = {o.cell(r, 0).value: r for r in range(1, o.nrows)}
    con = {r["iso3"]: r for r in csv.DictReader(open(CONSTR, encoding="utf-8"))}
    grid, seen = [], set()
    for lr in csv.DictReader(open(LAYOUT, encoding="utf-8")):
        key, row = lr["official_ctr"], []
        specs = [lr[f"col{c + 1}"] for c in range(len(lr) - 2)]
        iso = specs[8][2:].strip() if specs[8].startswith("T:") else ""
        for c, s in enumerate(specs):
            if s == "O":
                cell = o.cell(orow[key], c)
            elif s.startswith("R:"):
                k = con.get(iso)
                if not (k and k["regional_row_used"] == s[2:] and SCORE.get(c) in k["dimensions_from_region"].split()):
                    raise SystemExit(f"layout row {lr['sheet_row']} col {c + 1}: {s} not in the construction table")
                seen.add((iso, SCORE[c]))
                cell = o.cell(orow[s[2:]], c)
            elif s.startswith("T:"):
                cell = xlrd.sheet.Cell(xlrd.XL_CELL_TEXT, s[2:])
            elif s.startswith("N:"):
                if c in SCORE:
                    raise SystemExit("number literal in a score column")
                cell = xlrd.sheet.Cell(xlrd.XL_CELL_NUMBER, float(s[2:]))
            elif s.startswith("B:"):
                cell = xlrd.sheet.Cell(int(s[2:]), "")
            elif s.startswith("E:"):
                cell = xlrd.sheet.Cell(xlrd.XL_CELL_ERROR, int(s[2:]))
            else:
                raise SystemExit(f"unknown cell spec {s!r}")
            row.append((cell.ctype, cell.value))
        grid.append(row)
    need = {(i, d) for i, k in con.items() for d in k["dimensions_from_region"].split()}
    if need != seen:
        raise SystemExit(f"construction table not fully used by the layout: {sorted(need ^ seen)[:10]}")
    return grid


def export_text(grid):
    lines = [";".join(A.cell_text(xlrd.sheet.Cell(t, v)) for t, v in row) for row in grid]
    return ("\n".join(lines) + "\n").encode("utf-8")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("official_xls"); ap.add_argument("out_dir")
    ap.add_argument("--verify", default="", help="the workbook to compare with (optional)")
    a = ap.parse_args()
    grid = rebuild(a.official_xls)
    out = Path(a.out_dir); out.mkdir(parents=True, exist_ok=True)
    (out / "rebuilt_package_sheet.json").write_text(json.dumps({"sheet_name": "6 dimensions for website", "cells": grid},
                                                               ensure_ascii=False), encoding="utf-8")
    txt = export_text(grid)
    (out / "derived_package_xls_sheet_via_libreoffice.csv").write_bytes(txt)
    print(f"HOFSTEDE_REBUILD_OK rows x cols ({len(grid)}, {len(grid[0])}) -> {out}")
    if a.verify:
        sh = xlrd.open_workbook(a.verify).sheet_by_index(0)
        diff = [(r + 1, c + 1, (sh.cell(r, c).ctype, sh.cell(r, c).value), grid[r][c])
                for r in range(sh.nrows) for c in range(sh.ncols)
                if (sh.cell(r, c).ctype, repr(sh.cell(r, c).value)) != (grid[r][c][0], repr(grid[r][c][1]))]
        if (sh.nrows, sh.ncols) != (len(grid), len(grid[0])):
            diff.append(("shape", (sh.nrows, sh.ncols), (len(grid), len(grid[0]))))
        with tempfile.TemporaryDirectory() as td:
            A.export(a.verify, Path(td) / "ref.csv")
            same_txt = (Path(td) / "ref.csv").read_bytes() == txt
        print(f"HOFSTEDE_REBUILD_VERIFY cells differing {len(diff)} of {sh.nrows * sh.ncols}; text export byte-identical {same_txt}")
        for d in diff[:20]:
            print("  DIFF row, col, workbook, rebuilt:", d)
        sys.exit(0 if not diff and same_txt else 1)


if __name__ == "__main__":
    main()

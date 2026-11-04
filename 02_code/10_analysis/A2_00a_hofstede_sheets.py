"""A2_00a_hofstede_sheets.py -- write the first sheet of the two Hofstede workbooks as ';'-separated text, the input
format of A2_00_hofstede.py.

The analysis run read LibreOffice CSV exports of the two .xls files (field separator ';', decimal comma, numbers
as shown with up to 15 significant digits, cell text such as "#NULL!" kept). This script reproduces that export
with xlrd so that no office suite is needed: text cells verbatim, numeric cells rendered as LibreOffice shows
them (shortest round-trip decimal rounded half-up to 15 significant digits; decimal comma), empty cells
empty. It writes only the two text files named below.

Usage: python3 A2_00a_hofstede_sheets.py <official_xls> <package_xls> <out_dir>
  package_xls = "-": export the official file only (run_all.py then writes the second file with
                tools/rebuild_hofstede_inputs.py, which rebuilds the workbook's sheet from the official file)
  official_xls = 6-dimensions-for-website-2015-08-16.xls (official file, geerthofstede.com)
  package_xls  = the workbook read by the chapter build (01_raw/05_Mobility; official rows plus the
                 documented regional-proxy rows, see derived/hofstede/README.md)
Writes: <out_dir>/derived_official_0816_sheet_via_libreoffice.csv, <out_dir>/derived_package_xls_sheet_via_libreoffice.csv
(file names kept from the analysis run, which A2_00_hofstede.py reads).
"""
import sys
from decimal import Decimal, ROUND_HALF_UP
from pathlib import Path

import xlrd


def lo_number(x):
    """LibreOffice 'as shown' rendering of a double in the General format: the shortest round-trip decimal,
    rounded half-up to 15 significant digits, trailing zeros removed (reproduces the exports used in the run)."""
    d = Decimal(repr(float(x)))
    if d == 0:
        return "0"
    q = Decimal(1).scaleb(d.adjusted() - 14)
    r = d.quantize(q, rounding=ROUND_HALF_UP)
    s = format(r, "f")
    if "." in s:
        s = s.rstrip("0").rstrip(".")
    return s


def cell_text(c):
    if c.ctype in (xlrd.XL_CELL_EMPTY, xlrd.XL_CELL_BLANK):
        return ""
    if c.ctype == xlrd.XL_CELL_NUMBER:
        s = lo_number(c.value)
        if "e" in s or "E" in s:
            raise SystemExit(f"unexpected exponent format for {c.value!r}")
        return s.replace(".", ",")
    if c.ctype == xlrd.XL_CELL_ERROR:
        return xlrd.error_text_from_code.get(c.value, "#ERR")
    if c.ctype == xlrd.XL_CELL_BOOLEAN:
        return "TRUE" if c.value else "FALSE"
    return str(c.value)


def export(xls, out):
    sh = xlrd.open_workbook(xls).sheet_by_index(0)
    lines = []
    for r in range(sh.nrows):
        vals = [cell_text(sh.cell(r, k)) for k in range(sh.ncols)]
        for v in vals:
            if ";" in v or '"' in v or "\n" in v:
                raise SystemExit(f"cell needs quoting, not expected in these workbooks: {v!r}")
        lines.append(";".join(vals))
    Path(out).write_text("\n".join(lines) + "\n", encoding="utf-8")
    return sh.nrows, sh.ncols


if __name__ == "__main__":
    off, pkg, outdir = sys.argv[1:4]
    Path(outdir).mkdir(parents=True, exist_ok=True)
    a = export(off, Path(outdir) / "derived_official_0816_sheet_via_libreoffice.csv")
    b = export(pkg, Path(outdir) / "derived_package_xls_sheet_via_libreoffice.csv") if pkg != "-" else "rebuilt separately"
    print(f"HOFSTEDE_SHEETS_OK official rows x cols {a}; package rows x cols {b}")

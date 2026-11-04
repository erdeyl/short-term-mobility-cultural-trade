"""SW2 raw OOXML reader (read-only). openpyxl cannot read the UN Tourism stylesheets,
so sheets are parsed directly from the zip container: workbook.xml -> rels -> sheet XML,
sharedStrings for t="s", inlineStr for t="inlineStr"; numbers kept as text then float."""
import re
import zipfile
import xml.etree.ElementTree as ET

NS = {"m": "http://schemas.openxmlformats.org/spreadsheetml/2006/main",
      "r": "http://schemas.openxmlformats.org/officeDocument/2006/relationships",
      "pr": "http://schemas.openxmlformats.org/package/2006/relationships"}


def _col_index(ref):
    letters = re.match(r"([A-Z]+)", ref).group(1)
    n = 0
    for ch in letters:
        n = n * 26 + (ord(ch) - 64)
    return n - 1


def sheet_names(path):
    with zipfile.ZipFile(path) as z:
        wb = ET.fromstring(z.read("xl/workbook.xml"))
        return [s.get("name") for s in wb.find("m:sheets", NS)]


def read_sheet(path, name):
    """Return list of rows (lists of str|None) for the sheet called `name`."""
    with zipfile.ZipFile(path) as z:
        wb = ET.fromstring(z.read("xl/workbook.xml"))
        rid = None
        for s in wb.find("m:sheets", NS):
            if s.get("name") == name:
                rid = s.get("{%s}id" % NS["r"])
        if rid is None:
            raise KeyError(f"sheet {name!r} not in {path}")
        rels = ET.fromstring(z.read("xl/_rels/workbook.xml.rels"))
        target = None
        for rel in rels:
            if rel.get("Id") == rid:
                target = rel.get("Target")
        target = target.lstrip("/")
        if not target.startswith("xl/"):
            target = "xl/" + target
        shared = []
        if "xl/sharedStrings.xml" in z.namelist():
            sst = ET.fromstring(z.read("xl/sharedStrings.xml"))
            for si in sst.findall("m:si", NS):
                shared.append("".join(t.text or "" for t in si.iter("{%s}t" % NS["m"])))
        root = ET.fromstring(z.read(target))
    rows = []
    for row in root.iter("{%s}row" % NS["m"]):
        cells = {}
        for c in row.findall("m:c", NS):
            t = c.get("t")
            idx = _col_index(c.get("r"))
            v = c.find("m:v", NS)
            if t == "s":
                val = shared[int(v.text)] if v is not None and v.text is not None else None
            elif t == "inlineStr":
                is_ = c.find("m:is", NS)
                val = "".join(x.text or "" for x in is_.iter("{%s}t" % NS["m"])) if is_ is not None else None
            else:
                val = v.text if v is not None else None
            cells[idx] = val
        if cells:
            width = max(cells) + 1
            rows.append([cells.get(i) for i in range(width)])
        else:
            rows.append([])
    return rows

#!/usr/bin/env python3
"""scan_portability.py -- static portability scan: no absolute or machine-specific path in any file of the package.

  python3 tools/scan_portability.py [--root PACKAGE_ROOT] [--include-outputs]

Every file is read as bytes (text and binary; members of .zip/.xlsx/.docx containers are scanned too) and searched,
case-insensitively, for the patterns below. Exit 0 = no hit, 1 = hits (listed with file, line and context).
By default the run-time output folders (03_intermediate, 04_analysis data, 05_output, 06_results, 00_stata_temp) and
the user-supplied raw data in 01_raw are skipped (they are not part of the distributed source tree); --include-outputs
scans them as well (used on the release copy, after tools/make_release.py has replaced the run's root path).
Positive control: --self-test writes a temporary file containing a pattern and checks that the scan reports it.
"""
import argparse
import io
import re
import sys
import tempfile
import zipfile
from pathlib import Path

# patterns, hex-encoded so that this file does not match itself: the macOS user-home prefix, Windows drive C (both
# separators), the Linux home prefix, the macOS temporary-folder prefix, two folder names of the authors' machine, the
# Windows user-home prefix, and (_LOCAL_HEX, empty in the anonymized copy) a third folder name of the authors' machine.
# Decode with bytes.fromhex to read them.
_HEX = ["2f55736572732f", "433a5c", "433a2f", "2f686f6d652f", "2f707269766174652f746d70", "73637261746368706164",
        "7265736375655f636f7079", "5c55736572735c"]
_LOCAL_HEX = ["47616f5469616e6a695f64617461"]
PATTERNS = [bytes.fromhex(h) for h in _HEX + _LOCAL_HEX]
SKIP_DIRS = {"03_intermediate", "04_analysis data", "05_output", "06_results", "00_stata_temp", ".git", "__pycache__"}
ZIPLIKE = {".zip", ".xlsx", ".docx", ".pptx"}
RX = re.compile(b"|".join(re.escape(x) for x in PATTERNS), re.IGNORECASE)


def hits_in(data, name):
    out = []
    for m in RX.finditer(data):
        line = data.count(b"\n", 0, m.start()) + 1
        a, b = max(0, m.start() - 40), min(len(data), m.end() + 40)
        ctx = data[a:b].decode("utf-8", "replace").replace("\n", " ")
        out.append((name, line, ctx))
    return out


def scan(root, include_outputs):
    res = []
    root = Path(root)
    for p in sorted(root.rglob("*")):
        if not p.is_file():
            continue
        relp = p.relative_to(root)
        if any(part in SKIP_DIRS for part in relp.parts) and not include_outputs:
            continue
        if relp.parts[0] == "01_raw" and not include_outputs and p.suffix.lower() not in (".md", ".py", ".sha256", ".txt"):
            continue
        data = p.read_bytes()
        res += hits_in(data, str(relp))
        if p.suffix.lower() in ZIPLIKE:
            try:
                with zipfile.ZipFile(io.BytesIO(data)) as z:
                    for n in z.namelist():
                        res += hits_in(z.read(n), f"{relp}!{n}")
            except zipfile.BadZipFile:
                pass
    return res


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=str(Path(__file__).resolve().parents[1]))
    ap.add_argument("--include-outputs", action="store_true")
    ap.add_argument("--self-test", action="store_true")
    a = ap.parse_args()
    if a.self_test:
        with tempfile.TemporaryDirectory() as d:
            (Path(d) / "probe.txt").write_bytes(b"path = " + PATTERNS[0] + b"someone/x\n")
            ok = len(scan(d, True)) == 1
        print("SELF_TEST", "PASS" if ok else "FAIL")
        sys.exit(0 if ok else 1)
    res = scan(a.root, a.include_outputs)
    for name, line, ctx in res:
        print(f"HIT {name}:{line}: ...{ctx}...")
    print(f"PORTABILITY_SCAN files_with_hits={len({r[0] for r in res})} hits={len(res)} -> {'FAIL' if res else 'PASS'}")
    sys.exit(1 if res else 0)


if __name__ == "__main__":
    main()

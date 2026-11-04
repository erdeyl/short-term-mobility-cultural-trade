#!/usr/bin/env python3
"""make_release.py -- build the anonymized copy of the package (Supplementary File S1) and run the anonymization gate.

  python3 tools/make_release.py --out STAGING_DIR [--zip S1.zip] [--run-root PATH_OF_THE_RUN] [--include-outputs]
  python3 tools/make_release.py --gate-only DIR_OR_ZIP          # scan only
  python3 tools/make_release.py --positive-control              # authors' copy: the scan must find the README author line

Steps (build mode):
 1. copy the package tree to STAGING_DIR, without the files that identify the authors (CITATION.cff), version-control
    files and caches; run-time outputs only with --include-outputs, and then only the parts listed in INCLUDE_OUTPUTS;
 2. in every text file: replace the absolute path of the run (--run-root, also when Stata wrapped it over lines with
    "\\n> "), any user-home or temporary-folder path, Stata licence-banner lines, and the author lines listed in
    AUTHOR_LINES; in Stata logs, remove the output of `list` commands (they can show UN Tourism cell values);
 3. gate: every file (bytes, case-insensitive; also inside zip-based files) must contain none of the patterns
    (author and user names, affiliation and e-mail domain, funder file number, home and temporary-folder prefixes),
    and no hex literal or base64 run in any file may decode to text that contains an identifying pattern; the system
    grep -ri is run as a second, independent scan; any hit fails;
 4. zip STAGING_DIR to --zip and scan the zip again.
The patterns are stored hex-encoded so that the scan does not match this file itself. The release copy of this file
and of tools/scan_portability.py omits the identifying patterns and the author lines (redacted_copy below), so the
anonymized copy cannot be decoded to the authors' names. Exit 0 = gate PASS.
"""
import argparse
import base64
import binascii
import hashlib
import io
import os
import re
import shutil
import subprocess
import sys
import unicodedata
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
# hex-encoded, case-insensitive patterns (decode with bytes.fromhex). _ID_HEX (empty in the anonymized copy): family
# and given names of the three authors with and without diacritics, the owner's e-mail domain stem, affiliation names
# and domain, the funder file number and name. _PATH_HEX: the macOS home and temporary prefixes, the Windows home prefix.
_ID_HEX = ["6572646579", "6c61737a6c6f", "6cc3a1737a6cc3b3", "6c61cc81737a6c6fcc81", "67616f", "7469616e6a69",
           "6b6f76616373", "6b6f76c3a16373", "6b6f7661cc816373", "73616e646f72", "73c3a16e646f72", "7361cc816e646f72",
           "646562726563656e", "756e69646562", "626f6c796169", "636c756a", "323032333038333630303336",
           "7363686f6c61727368697020636f756e63696c"]
_PATH_HEX = ["2f55736572732f", "2f707269766174652f746d70", "5c55736572735c"]
ID_PATTERNS = [bytes.fromhex(h) for h in _ID_HEX]
PATTERNS = ID_PATTERNS + [bytes.fromhex(h) for h in _PATH_HEX]
RX = re.compile(b"|".join(re.escape(p) for p in PATTERNS), re.IGNORECASE)
ID_RX = re.compile(b"|".join(re.escape(p) for p in ID_PATTERNS), re.IGNORECASE) if ID_PATTERNS else None
HEX_LIT = re.compile(rb"(?<![0-9A-Za-z])(?:[0-9A-Fa-f]{2}){3,}(?![0-9A-Za-z])")  # even length, at least 6 hex digits
B64_RUN = re.compile(rb"(?<![A-Za-z0-9+/])[A-Za-z0-9+/]{16,}={0,2}")
REDACTED_TOOLS = ("tools/make_release.py", "tools/scan_portability.py")
EXCLUDE_NAMES = {"CITATION.cff", ".gitignore", ".DS_Store"}
EXCLUDE_DIRS = {".git", "__pycache__", ".venv", "00_stata_temp"}
RUNTIME_DIRS = {"03_intermediate", "04_analysis data", "05_output", "06_results"}
# run-time outputs released with --include-outputs (glob patterns relative to the package root); everything else stays local
INCLUDE_OUTPUTS = ["06_results/**/*", "05_output/_run/run_all.log", "05_output/_run/run_times.csv",
                   "05_output/_run/check_stata_packages.log",
                   "05_output/10_analysis/corrected2x/results/A1.csv", "05_output/10_analysis/corrected2x/results/A2.csv",
                   "05_output/10_analysis/corrected2x/positive_controls.csv", "05_output/10_analysis/corrected2x/TAB_results.csv",
                   "05_output/10_analysis/corrected2x/*nflow*.csv", "05_output/10_analysis/corrected2x/logs/*.log",
                   "05_output/10_analysis/corrected2x/FIG_cd_slopes_controls.csv", "05_output/10_analysis/corrected2x/pc_table_identity.csv",
                   # unordered-pair recomputation and Narrow-A benchmark (estimates and test tables only)
                   "05_output/10_analysis/corrected2x/results/A2_7c.csv", "05_output/10_analysis/corrected2x/tables/clustering_pvalues*.csv",
                   "05_output/10_analysis/corrected2x/tables/benchmark_basket_family.csv", "05_output/10_analysis/corrected2x/tables/S5_*.csv",
                   "05_output/10_analysis/corrected2x/tables/sample_overlap.csv", "05_output/10_analysis/corrected2x_upair/results/**/*.csv",
                   "05_output/10_analysis/corrected2x_upair/logs/*.log",
                   "05_output/00_common/03_logs/**/*.log", "05_output/03_Mobility/03_logs/**/*.log"]
TEXT_SUFFIX = {".md", ".txt", ".csv", ".log", ".do", ".ado", ".sthlp", ".py", ".sh", ".json", ".tsv", ".sha256", ".cff", ""}  # "" = LICENSE
# author lines of the GitHub version and their anonymized replacement (file, exact old text, new text)
AUTHOR_LINES = [  # (file, hex of the exact text of the GitHub version, replacement)
    ("README.md", bytes.fromhex("417574686f72733a205469616e6a692047616f2c2053c3a16e646f72204b6f76c3a1637320616e64204cc3a1737a6cc3b32045726465792e").decode("utf-8"), "Authors: anonymized for double-anonymized peer review."),
    ("02_code/99_rescue/ado/nflow.ado", bytes.fromhex("2872652d696d706c656d656e74656420666f72204c2e20457264657929").decode("utf-8"), "(re-implemented for the authors)"),
    ("02_code/99_rescue/ado/nflow.sthlp", bytes.fromhex("4c2e2045726465792c20323032362d31302d30382e").decode("utf-8"), "the authors, 2026-10-08."),
    ("LICENSE", bytes.fromhex("436f70797269676874202863292032303236205469616e6a692047616f2c2053c3a16e646f72204b6f76c3a1637320616e64204cc3a1737a6cc3b3204572646579").decode("utf-8"), "Copyright (c) 2026 The authors"),
    ("LICENSE-CC-BY-4.0.md", bytes.fromhex("436f70797269676874202863292032303236205469616e6a692047616f2c2053c3a16e646f72204b6f76c3a1637320616e64204cc3a1737a6cc3b3204572646579").decode("utf-8"), "Copyright (c) 2026 The authors"),
]


RAW_SHIPPED = {"06_WorldBank", "07_CEPII_Language"}  # redistributable raw folders (LICENSES_AND_SOURCES.md)


def raw_allowed(rel):
    """01_raw in the release: README files, the manifest, and the files of the redistributable sources only."""
    parts = rel.parts
    return rel.name in ("README.md", "RAW_MANIFEST.sha256") or (len(parts) > 2 and parts[1] in RAW_SHIPPED)


def scan_bytes(data, name):
    hits = []
    for m in RX.finditer(data):
        a, b = max(0, m.start() - 30), min(len(data), m.end() + 30)
        hits.append((name, data.count(b"\n", 0, m.start()) + 1, data[a:b].decode("utf-8", "replace").replace("\n", " ")))
    return hits


def _readable(b):
    """True if the bytes are UTF-8 text without control characters (an encoded name decodes to readable text)."""
    try:
        s = b.decode("utf-8")
    except UnicodeDecodeError:
        return False
    return all(c.isprintable() or c in "\t\r\n" for c in s)


def decoded_hits(data, name):
    """Hex literals and base64 runs that decode to readable text containing an identifying pattern."""
    if ID_RX is None:
        return []
    hits = []
    for rx, kind in ((HEX_LIT, "hex"), (B64_RUN, "base64")):
        for m in rx.finditer(data):
            s = m.group(0)
            try:
                b = bytes.fromhex(s.decode("ascii")) if kind == "hex" else base64.b64decode(s + b"=" * (-len(s) % 4))
            except (binascii.Error, ValueError):
                continue
            if _readable(b) and ID_RX.search(b):
                hits.append((name, data.count(b"\n", 0, m.start()) + 1, f"{kind} literal decodes to an identifying pattern"))
    return hits


def _cut(text, start, end, new):
    """Replace the block from the line that begins with `start` to the first `end` after it (the block must be unique)."""
    assert text.count("\n" + start) == 1, f"redaction marker not unique: {start!r}"
    a = text.index("\n" + start) + 1
    b = text.index(end, a) + len(end)
    return text[:a] + new + text[b:]


def redacted_copy(rel, text):
    """Release copy of the two tools: the identifying gate patterns and the author lines are left out."""
    if rel == "tools/make_release.py":
        text = _cut(text, "_ID_HEX = [", "]\n", "_ID_HEX = []  # the anonymized copy omits the identifying patterns that the authors' build uses\n")
        text = _cut(text, "AUTHOR_LINES = [", "\n]\n", "AUTHOR_LINES = []  # the anonymized copy omits the author lines that the authors' build uses\n")
    elif rel == "tools/scan_portability.py":
        text = _cut(text, "_LOCAL_HEX = [", "]\n", "_LOCAL_HEX = []  # the anonymized copy omits the folder name that the authors' build uses\n")
    return text


def scan_tree(path):
    path = Path(path)
    hits = []
    files = [path] if path.is_file() else sorted(p for p in path.rglob("*") if p.is_file())
    for p in files:
        rel = p.name if path.is_file() else str(p.relative_to(path))
        data = p.read_bytes()
        if p.suffix.lower() == ".zip" or zipfile.is_zipfile(io.BytesIO(data)):
            try:
                with zipfile.ZipFile(io.BytesIO(data)) as z:
                    for n in z.namelist():
                        hits += scan_bytes(n.encode("utf-8"), f"{rel}!{n} (member name)")
                        inner = z.read(n)
                        hits += scan_bytes(inner, f"{rel}!{n}") + decoded_hits(inner, f"{rel}!{n}")
                        if zipfile.is_zipfile(io.BytesIO(inner)):
                            with zipfile.ZipFile(io.BytesIO(inner)) as z2:
                                for n2 in z2.namelist():
                                    hits += scan_bytes(z2.read(n2), f"{rel}!{n}!{n2}")
                continue
            except zipfile.BadZipFile:
                pass
        hits += scan_bytes(rel.encode("utf-8"), f"{rel} (file name)")
        hits += scan_bytes(data, rel) + decoded_hits(data, rel)
        if data[:2] in (b"\xff\xfe", b"\xfe\xff"):
            try:
                hits += scan_bytes(data.decode("utf-16").encode("utf-8"), rel + " (utf-16)")
            except UnicodeDecodeError:
                pass
    return hits


def system_grep(path):
    """Independent second scan with the operating system's grep (case-insensitive, binary files included)."""
    if shutil.which("grep") is None or Path(path).is_file():
        return None
    n = 0
    for p in PATTERNS:
        r = subprocess.run(["grep", "-r", "-i", "-a", "-l", "-F", "-e", p.decode("utf-8"), str(path)], capture_output=True, text=True)
        if r.returncode == 0:
            for line in r.stdout.splitlines():
                print("GREP_HIT", line)
                n += 1
        elif r.returncode > 1:
            print("GREP_ERROR", r.stderr.strip())
            return -1
    return n


def path_regex(p):
    """Regex for an absolute path that Stata may have wrapped over lines as '\\n> '."""
    sep = r"(?:\r?\n> ?)?"
    return re.compile(sep.join(re.escape(c) for c in p))


_U, _T, _W = (bytes.fromhex(h).decode() for h in ("2f55736572732f", "2f707269766174652f746d702f", "5c55736572735c"))
SCRUB = [(re.compile(re.escape(_U) + r"[^/\s\"']+"), "<USER_HOME>"), (re.compile(re.escape(_T) + r"[^\s\"']*"), "<TMP>"),
         (re.compile(r"/var/folders/[^\s\"']*"), "<TMP>"), (re.compile(r"[A-Za-z]:" + re.escape(_W) + r"[^\\\s\"']+"), "<USER_HOME>"),
         (re.compile(r"^.*(?:Licensed to:|Serial number:|Stata license:).*$\n?(?:^ {10,}\S.*$\n?)?", re.M), "")]
LIST_CMD = re.compile(r"^(?:\.|\s*\d+\.)\s+(?:(?:quietly|noisily|capture|qui|noi|cap)\s+)*(?:li|lis|list)\b.*$", re.M)
NEXT_CMD = re.compile(r"^(?:\. |\s*\d+\. )")


def strip_lists(text):
    """Remove the output that follows a Stata `list` command up to the next command line."""
    out, i, n = [], 0, 0
    lines = text.split("\n")
    while i < len(lines):
        out.append(lines[i])
        if LIST_CMD.match(lines[i]):
            j = i + 1
            while j < len(lines) and lines[j].startswith("> "):
                out.append(lines[j]); j += 1
            k = j
            while k < len(lines) and not NEXT_CMD.match(lines[k]):
                k += 1
            if k > j:
                out.append("[output of list removed in the release copy: it can contain UN Tourism values]")
                n += 1
            i = k
            continue
        i += 1
    return "\n".join(out), n


def build(args):
    out = Path(args.out)
    if out.exists():
        sys.exit(f"--out exists, choose a new folder: {out}")
    pats = [p for p in INCLUDE_OUTPUTS] if args.include_outputs else []
    keep = set()
    for g in pats:
        keep |= {p for p in ROOT.glob(g) if p.is_file()}
    n_files = n_lists = 0
    for p in sorted(ROOT.rglob("*")):
        if not p.is_file():
            continue
        rel = p.relative_to(ROOT)
        if p.name in EXCLUDE_NAMES or any(part in EXCLUDE_DIRS for part in rel.parts):
            continue
        if rel.parts[0] in RUNTIME_DIRS and p not in keep:
            continue
        if p.suffix.lower() in (".tif", ".tiff"):
            continue  # 600-dpi TIFF copies of the figures: their compressed pixel data can contain byte sequences that
            # match a short name pattern by chance; PDF and PNG of the same figures and the plotted data are released
        if rel.parts[0] == "01_raw" and not raw_allowed(rel):
            continue  # restricted or large raw files stay local (LICENSES_AND_SOURCES.md)
        dst = out / rel
        dst.parent.mkdir(parents=True, exist_ok=True)
        if p.suffix.lower() in TEXT_SUFFIX and p.stat().st_size < 50_000_000:
            try:
                t = p.read_text(encoding="utf-8")
            except UnicodeDecodeError:
                shutil.copy2(p, dst); n_files += 1
                continue
            for f, old, new in AUTHOR_LINES:  # each listed line must be present in its own file (checked before any change)
                if rel.as_posix() == f and old not in t:
                    sys.exit(f"author line not found in {f}: {old!r}")
            for f, old, new in AUTHOR_LINES:
                t = path_regex(old).sub(new, t)  # in every text file, also where a log echoes it wrapped over lines as "\n> "
            if args.run_root:
                t = path_regex(args.run_root.rstrip("/")).sub("<PACKAGE_ROOT>", t)
                t = path_regex(str(Path(args.run_root.rstrip("/")).parent)).sub("<RUN_FOLDER>", t)  # e.g. the virtual environment
            if rel.as_posix() != "tools/make_release.py":  # SCRUB would rewrite the tool's own regular expressions
                for rx, rep in SCRUB:
                    t = rx.sub(rep, t)
            if rel.as_posix() in REDACTED_TOOLS:
                t = redacted_copy(rel.as_posix(), t)  # identifying patterns and author lines stay out of the release
            if p.suffix.lower() == ".log":
                t, k = strip_lists(t)
                n_lists += k
            dst.write_text(t, encoding="utf-8")
        else:
            shutil.copy2(p, dst)
        n_files += 1
    print(f"STAGED {n_files} files to {out}; list outputs removed: {n_lists}")
    ok = gate(out)
    if args.zip:
        z = Path(args.zip)
        with zipfile.ZipFile(z, "w", zipfile.ZIP_DEFLATED) as zf:
            for p in sorted(out.rglob("*")):
                if p.is_file():
                    zf.write(p, Path("Supplementary_File_S1") / p.relative_to(out))
        ok = gate(z) and ok
        print(f"ZIP {z} sha256 {hashlib.sha256(z.read_bytes()).hexdigest()}")
    return ok


def gate(path):
    hits = scan_tree(path)
    for name, line, ctx in hits:
        print(f"GATE_HIT {name}:{line}: ...{ctx}...")
    g = system_grep(path)
    ok = not hits and (g in (0, None))
    print(f"ANONYMIZATION_GATE {path}: scan hits={len(hits)}, grep hits={g if g is not None else 'n/a'} -> {'PASS' if ok else 'FAIL'}")
    if ID_RX is None:
        print("DECODE_CONTROL not available in the anonymized copy (it has no identifying patterns)")
        return ok
    # positive control: the decode scan must find the identifying patterns in the authors' (unredacted) tools
    ctl = [f for f in REDACTED_TOOLS if decoded_hits((ROOT / f).read_bytes(), f)]
    print(f"DECODE_CONTROL authors' tools with decodable identifying patterns: {len(ctl)} of {len(REDACTED_TOOLS)} "
          f"-> {'PASS' if len(ctl) == len(REDACTED_TOOLS) else 'FAIL'}")
    return ok and len(ctl) == len(REDACTED_TOOLS)


def positive_control():
    """The same scan on the GitHub version must report the README author line (proves that the scan can find names)."""
    readme = ROOT / "README.md"
    lines = readme.read_text(encoding="utf-8").splitlines()
    author = [i + 1 for i, l in enumerate(lines) if l.startswith("Authors:")]
    hits = scan_tree(readme)
    ok = bool(author) and any(line == author[0] for _, line, _ in hits)
    g = system_grep(ROOT)
    print(f"POSITIVE_CONTROL GitHub version: README author line {author[:1]} found by the scan: {ok}; "
          f"scan hits in README.md={len(hits)}; system grep files with hits in the whole tree={g} -> {'PASS' if ok and g else 'FAIL'}")
    return ok and bool(g)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out")
    ap.add_argument("--zip")
    ap.add_argument("--run-root", default="")
    ap.add_argument("--include-outputs", action="store_true")
    ap.add_argument("--gate-only")
    ap.add_argument("--positive-control", action="store_true")
    a = ap.parse_args()
    accented = [p.decode("utf-8") for p in ID_PATTERNS if not p.isascii()]
    assert accented or not ID_PATTERNS, "the identifying patterns contain no accented name"
    for s in accented:  # every accented name is covered in both Unicode forms (empty in the anonymized copy)
        for form in ("NFC", "NFD"):
            assert unicodedata.normalize(form, s).encode("utf-8") in ID_PATTERNS, (s, form)
    if a.positive_control:
        sys.exit(0 if positive_control() else 1)
    if a.gate_only:
        sys.exit(0 if gate(a.gate_only) else 1)
    if not a.out:
        ap.error("--out is required")
    sys.exit(0 if build(a) else 1)


if __name__ == "__main__":
    main()

"""pkg_fs.py -- platform-neutral file operations called from the analysis do-files (via pkg_py).

They replace POSIX shell one-liners of the original analysis code with identical effects:
  rmtree <dir>                         = rm -rf <dir>
  mkdirs <dir> [<dir> ...]             = mkdir -p <dir> ...
  link <target> <linkname>             = ln -s <target> <linkname>; where symbolic links are not
                                          permitted (Windows without developer mode) a hard link, else a copy
  shaheader <csv>                      = printf 'table,pub_sha256,rep_sha256,pub_sha256_nocr,rep_sha256_nocr\\n' > <csv>
  sharow <csv> <name> <pub> <rep>      = one row: name, sha256(pub), sha256(rep), sha256 of both with '\\r' removed
                                          (an unreadable file gives an empty field, as the shell version did)
  shacheck <file> <sha256> <out> <yes> <no>  writes <yes> to <out> if sha256(file) == <sha256>, else <no>
Usage: python3 pkg_fs.py <command> <arguments>
"""
import hashlib
import os
import shutil
import sys
from pathlib import Path


def sha(path, strip_cr=False):
    try:
        data = Path(path).read_bytes()
    except OSError:
        return ""
    if strip_cr:
        data = data.replace(b"\r", b"")
    return hashlib.sha256(data).hexdigest()


def main(argv):
    cmd, args = argv[0], argv[1:]
    if cmd == "rmtree":
        shutil.rmtree(args[0], ignore_errors=True)
    elif cmd == "mkdirs":
        for d in args:
            os.makedirs(d, exist_ok=True)
    elif cmd == "link":
        target, name = args
        if os.path.lexists(name):
            os.remove(name)
        try:
            os.symlink(target, name)
        except OSError:
            try:
                os.link(target, name)
            except OSError:
                shutil.copy2(target, name)
    elif cmd == "shaheader":
        with open(args[0], "w", newline="\n") as fh:
            fh.write("table,pub_sha256,rep_sha256,pub_sha256_nocr,rep_sha256_nocr\n")
    elif cmd == "sharow":
        out, name, pub, rep = args
        with open(out, "a", newline="\n") as fh:
            fh.write(",".join([name, sha(pub), sha(rep), sha(pub, True), sha(rep, True)]) + "\n")
    elif cmd == "shacheck":
        f, want, out, yes, no = args
        with open(out, "w", newline="\n") as fh:
            fh.write((yes if sha(f) == want else no) + "\n")
    else:
        raise SystemExit(f"pkg_fs.py: unknown command {cmd}")


if __name__ == "__main__":
    main(sys.argv[1:])

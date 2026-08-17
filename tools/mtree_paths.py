#!/usr/bin/env python3
"""Reconstruct full paths from the IPSW BSD mtree.
Directory blocks are bracketed by '# ./path' comments; indented lines are
that directory's entries. Line continuations end with a trailing backslash."""
import re, sys

src = open(sys.argv[1], "r", errors="replace")
out = open(sys.argv[2], "w")

def unesc(s):
    return re.sub(r"\\(\d{3})", lambda m: chr(int(m.group(1), 8)), s)

curdir = "."
pending = ""
n = 0
for line in src:
    line = line.rstrip("\n")
    if pending:
        line = pending + line.lstrip()
        pending = ""
    if line.endswith("\\"):
        pending = line[:-1]
        continue
    if line.startswith("# ."):
        curdir = line[2:].strip()
        continue
    if not line or line.startswith("/set") or line.startswith("#"):
        continue
    if not line[0].isspace():
        continue                      # the dir's own entry line, already known
    name = line.strip().split(None, 1)[0]
    if name == "..":
        continue
    out.write(f"{curdir}/{unesc(name)}\n")
    n += 1
out.close()
print(f"{n:,} file paths written to {sys.argv[2]}")

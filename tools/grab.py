#!/usr/bin/env python3
import json, sys
from ipsw_peek import extract

url = sys.argv[1]
wanted = sys.argv[2:]
entries = {e["name"]: e for e in json.load(open("members.json"))}
for w in wanted:
    e = entries[w]
    data = extract(url, e)
    out = w.replace("/", "_")
    open(out, "wb").write(data)
    print(f"{w}  ->  {out}  ({len(data):,} bytes)")

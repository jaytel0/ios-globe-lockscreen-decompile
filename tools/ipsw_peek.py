#!/usr/bin/env python3
"""Read an IPSW (a ZIP) over HTTP using byte-range requests, without downloading it."""
import io, struct, sys, zlib, subprocess, json

def fetch(url, start, end):
    out = subprocess.run(
        ["curl", "-s", "--max-time", "180", "-r", f"{start}-{end}", url],
        capture_output=True, check=True)
    return out.stdout

def size_of(url):
    out = subprocess.run(["curl", "-sIL", "--max-time", "60", url],
                         capture_output=True, text=True, check=True).stdout
    for line in out.splitlines():
        if line.lower().startswith("content-length:"):
            n = int(line.split(":")[1].strip())
    return n

def central_directory(url, total):
    tail_len = min(1 << 17, total)
    tail = fetch(url, total - tail_len, total - 1)
    i = tail.rfind(b"PK\x05\x06")
    if i < 0:
        raise SystemExit("no EOCD found")
    cd_size, cd_off = struct.unpack("<II", tail[i + 12:i + 20])
    n_entries = struct.unpack("<H", tail[i + 10:i + 12])[0]
    # ZIP64?
    j = tail.rfind(b"PK\x06\x06")
    if j >= 0:
        n_entries = struct.unpack("<Q", tail[j + 32:j + 40])[0]
        cd_size = struct.unpack("<Q", tail[j + 40:j + 48])[0]
        cd_off = struct.unpack("<Q", tail[j + 48:j + 56])[0]
    return cd_off, cd_size, n_entries

def parse_cd(buf):
    entries, p = [], 0
    while p < len(buf) - 4 and buf[p:p + 4] == b"PK\x01\x02":
        (method,) = struct.unpack("<H", buf[p + 10:p + 12])
        csize, usize = struct.unpack("<II", buf[p + 20:p + 28])
        nlen, elen, clen = struct.unpack("<HHH", buf[p + 28:p + 34])
        (lho,) = struct.unpack("<I", buf[p + 42:p + 46])
        name = buf[p + 46:p + 46 + nlen].decode("utf-8", "replace")
        extra = buf[p + 46 + nlen:p + 46 + nlen + elen]
        # ZIP64 extra field
        q = 0
        while q < len(extra) - 4:
            hid, hlen = struct.unpack("<HH", extra[q:q + 4])
            if hid == 0x0001:
                blob, r = extra[q + 4:q + 4 + hlen], 0
                if usize == 0xFFFFFFFF: usize = struct.unpack("<Q", blob[r:r+8])[0]; r += 8
                if csize == 0xFFFFFFFF: csize = struct.unpack("<Q", blob[r:r+8])[0]; r += 8
                if lho   == 0xFFFFFFFF: lho   = struct.unpack("<Q", blob[r:r+8])[0]; r += 8
            q += 4 + hlen
        entries.append(dict(name=name, method=method, csize=csize, usize=usize, lho=lho))
        p += 46 + nlen + elen + clen
    return entries

def extract(url, e):
    """Range-fetch one member and decompress it."""
    hdr = fetch(url, e["lho"], e["lho"] + 29)
    nlen, elen = struct.unpack("<HH", hdr[26:30])
    start = e["lho"] + 30 + nlen + elen
    raw = fetch(url, start, start + e["csize"] - 1)
    if e["method"] == 0:
        return raw
    return zlib.decompress(raw, -15)

if __name__ == "__main__":
    url = sys.argv[1]
    total = size_of(url)
    off, csz, n = central_directory(url, total)
    print(f"archive bytes : {total:,}")
    print(f"members       : {n}")
    print(f"cd @ {off:,} ({csz:,} bytes)\n")
    cd = fetch(url, off, off + csz - 1)
    entries = parse_cd(cd)
    for e in sorted(entries, key=lambda x: -x["usize"]):
        print(f"{e['usize']:>14,}  {'stored' if e['method']==0 else 'defl  '}  {e['name']}")
    with open("members.json", "w") as f:
        json.dump(entries, f, indent=1)

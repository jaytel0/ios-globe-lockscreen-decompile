#!/usr/bin/env python3
"""Identify .art payloads. Header: [0:2] format, [2:4] flags, [4:6] width LE,
[6:8] height LE, then payload. Match payload size against ASTC mip-chain
totals and against plain uncompressed layouts."""
import os, sys, struct

FOOTPRINTS = [(4,4),(5,4),(5,5),(6,5),(6,6),(8,5),(8,6),(8,8),(10,10),(12,12)]

def astc_total(w, h, bw, bh, levels):
    total, ww, hh = 0, w, h
    for _ in range(levels):
        total += ((ww + bw - 1)//bw) * ((hh + bh - 1)//bh) * 16
        ww, hh = max(1, ww//2), max(1, hh//2)
    return total

def max_levels(w, h):
    n, ww, hh = 0, w, h
    while True:
        n += 1
        if ww == 1 and hh == 1:
            return n + 2          # allow a couple of trailing 1x1 levels
        ww, hh = max(1, ww//2), max(1, hh//2)

for path in sys.argv[1:]:
    size = os.path.getsize(path)
    hdr = open(path, "rb").read(8)
    fmt, flags, w, h = struct.unpack("<HHHH", hdr)
    payload = size - 8
    print(f"{os.path.basename(path):36} {w:>5}x{h:<5} fmt=0x{fmt:04x} flags=0x{flags:04x}", end="  ")
    found = None
    for bw, bh in FOOTPRINTS:
        for lv in range(1, max_levels(w, h) + 1):
            if astc_total(w, h, bw, bh, lv) == payload:
                found = f"ASTC {bw}x{bh}, {lv} mip levels"
                break
        if found: break
    if not found and w and h:
        bpp = payload / (w * h)
        if bpp == int(bpp):
            found = f"uncompressed {int(bpp)} B/px" + (f" (x6 = cube map, {int(bpp)//6} B/px)" if int(bpp) % 6 == 0 and int(bpp) >= 6 else "")
    print(found or "unknown")

#!/usr/bin/env python3
"""Decode an arbitrary mip level of a NanoUniverse .art ASTC tile."""
import struct
import texture2ddecoder
from PIL import Image

def decode_mip(path, bw, bh, level=0):
    raw = open(path, "rb").read()
    fmt, flags, w, h = struct.unpack("<HHHH", raw[:8])
    off = 8
    for _ in range(level):
        off += ((w + bw - 1)//bw) * ((h + bh - 1)//bh) * 16
        w, h = max(1, w//2), max(1, h//2)
    n = ((w + bw - 1)//bw) * ((h + bh - 1)//bh) * 16
    dec = texture2ddecoder.decode_astc(raw[off:off + n], w, h, bw, bh)
    return Image.frombytes("RGBA", (w, h), dec, "raw", "BGRA")

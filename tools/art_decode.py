#!/usr/bin/env python3
"""Decode a NanoUniverse .art tile (ASTC, 8-byte header, mip 0 only) to PNG."""
import struct, sys, os
import texture2ddecoder
from PIL import Image

def decode(path, bw, bh):
    raw = open(path, "rb").read()
    fmt, flags, w, h = struct.unpack("<HHHH", raw[:8])
    nblocks = ((w + bw - 1)//bw) * ((h + bh - 1)//bh)
    data = raw[8:8 + nblocks * 16]                      # mip level 0 only
    dec = texture2ddecoder.decode_astc(data, w, h, bw, bh)
    img = Image.frombytes("RGBA", (w, h), dec, "raw", "BGRA")
    return img

if __name__ == "__main__":
    path, bw, bh, out = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), sys.argv[4]
    img = decode(path, bw, bh)
    img.save(out)
    print(f"{os.path.basename(path)} -> {out}  {img.size}")

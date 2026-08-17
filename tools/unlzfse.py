#!/usr/bin/env python3
"""Strip the Image4 wrapper and LZFSE-decompress, using macOS libcompression."""
import ctypes, ctypes.util, sys

LZFSE = 0x801
lib = ctypes.CDLL("/usr/lib/libcompression.dylib")
lib.compression_decode_buffer.restype = ctypes.c_size_t
lib.compression_decode_buffer.argtypes = [
    ctypes.c_void_p, ctypes.c_size_t, ctypes.c_void_p, ctypes.c_size_t,
    ctypes.c_void_p, ctypes.c_int]

raw = open(sys.argv[1], "rb").read()
i = raw.find(b"bvx2")
if i < 0:
    sys.exit("no lzfse payload found")
print(f"lzfse payload at offset {i}, {len(raw)-i:,} bytes compressed")
src = raw[i:]

cap = 256 << 20
dst = ctypes.create_string_buffer(cap)
n = lib.compression_decode_buffer(dst, cap, src, len(src), None, LZFSE)
if n == 0:
    sys.exit("decompression failed")
print(f"decompressed to {n:,} bytes")
open(sys.argv[2], "wb").write(dst.raw[:n])

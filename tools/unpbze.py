#!/usr/bin/env python3
"""Decode Apple's pbzx/pbze chunked container: magic, u64be chunksize,
then repeating (u64be raw_size, u64be comp_size, payload[comp_size])."""
import ctypes, struct, sys

lib = ctypes.CDLL("/usr/lib/libcompression.dylib")
lib.compression_decode_buffer.restype = ctypes.c_size_t
lib.compression_decode_buffer.argtypes = [
    ctypes.c_void_p, ctypes.c_size_t, ctypes.c_void_p, ctypes.c_size_t,
    ctypes.c_void_p, ctypes.c_int]
LZFSE = 0x801

def lzfse(src, out_size):
    dst = ctypes.create_string_buffer(out_size + 4096)
    n = lib.compression_decode_buffer(dst, out_size + 4096, src, len(src), None, LZFSE)
    return dst.raw[:n]

raw = open(sys.argv[1], "rb").read()
p = raw.find(b"pbze")
if p < 0:
    p = raw.find(b"pbzx")
p += 4
(chunk_size,) = struct.unpack(">Q", raw[p:p + 8]); p += 8
print(f"container chunk size: {chunk_size:,}")

out = bytearray()
n = 0
while p + 16 <= len(raw):
    rawsz, compsz = struct.unpack(">QQ", raw[p:p + 16])
    p += 16
    blob = raw[p:p + compsz]
    p += compsz
    if compsz == rawsz:
        out += blob                      # stored chunk
    else:
        out += lzfse(blob, rawsz)
    n += 1
print(f"chunks: {n}  ->  {len(out):,} bytes")
open(sys.argv[2], "wb").write(out)

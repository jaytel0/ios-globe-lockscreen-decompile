#!/usr/bin/env python3
"""Decompress with libcompression's streaming API (handles multi-block LZBITMAP)."""
import ctypes, sys

lib = ctypes.CDLL("/usr/lib/libcompression.dylib")

class Stream(ctypes.Structure):
    _fields_ = [("dst_ptr", ctypes.c_void_p), ("dst_size", ctypes.c_size_t),
                ("src_ptr", ctypes.c_void_p), ("src_size", ctypes.c_size_t),
                ("state", ctypes.c_void_p)]

lib.compression_stream_init.argtypes = [ctypes.POINTER(Stream), ctypes.c_int, ctypes.c_int]
lib.compression_stream_process.argtypes = [ctypes.POINTER(Stream), ctypes.c_int]
lib.compression_stream_destroy.argtypes = [ctypes.POINTER(Stream)]

DECODE, FINALIZE = 1, 0x0001
STATUS_OK, STATUS_END, STATUS_ERR = 0, 1, -1

def decode(src: bytes, alg: int) -> bytes:
    s = Stream()
    if lib.compression_stream_init(ctypes.byref(s), DECODE, alg) != STATUS_OK:
        raise RuntimeError("init failed")
    buf = ctypes.create_string_buffer(8 << 20)
    src_buf = ctypes.create_string_buffer(src, len(src))
    s.src_ptr = ctypes.cast(src_buf, ctypes.c_void_p)
    s.src_size = len(src)
    out = bytearray()
    while True:
        s.dst_ptr = ctypes.cast(buf, ctypes.c_void_p)
        s.dst_size = len(buf)
        st = lib.compression_stream_process(ctypes.byref(s), FINALIZE)
        produced = len(buf) - s.dst_size
        out += buf.raw[:produced]
        if st == STATUS_END:
            break
        if st == STATUS_ERR:
            raise RuntimeError(f"error after {len(out):,} bytes")
        if produced == 0 and s.src_size == 0:
            break
    lib.compression_stream_destroy(ctypes.byref(s))
    return bytes(out)

if __name__ == "__main__":
    raw = open(sys.argv[1], "rb").read()
    magic = sys.argv[3].encode() if len(sys.argv) > 3 else b"pbze"
    i = raw.find(magic)
    print(f"payload at {i}")
    for name, alg in [("LZBITMAP", 0x702), ("LZFSE", 0x801), ("ZLIB", 0x205)]:
        try:
            data = decode(raw[i:], alg)
            if data:
                print(f"{name}: {len(data):,} bytes")
                open(sys.argv[2], "wb").write(data)
                break
        except RuntimeError as e:
            print(f"{name}: {e}")

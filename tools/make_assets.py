#!/usr/bin/env python3
"""Export Earth cube faces as PNGs, pre-permuted into Metal slice order
(+X, -X, +Y, -Y, +Z, -Z) so the app loads slice 0..5 straight through."""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from build_faces import build_faces
from PIL import Image

METAL_ORDER = [1, 0, 4, 5, 2, 3]      # verified by the equirect unwrap
OUT = "AegirDemo/Resources"

JOBS = [
    # layer, mip, target face size, mode,     basename
    ("a", 0, 2048, "RGB",   "earth_albedo"),
    ("n", 1, 1024, "L",     "earth_relief"),
    ("e", 0, 1024, "RGB",   "earth_lights"),   # city lights, colour
    ("e", 0, 1024, "ALPHA", "earth_water"),    # water mask, from the alpha channel
    ("c", 0,  768, "L",     "earth_cloud"),
]

os.makedirs(OUT, exist_ok=True)
cache = {}
for layer, mip, size, mode, base in JOBS:
    if (layer, mip) not in cache:
        cache[(layer, mip)] = build_faces(layer, mip)
    faces = cache[(layer, mip)]
    total = 0
    for slot, src in enumerate(METAL_ORDER):
        img = faces[src]
        if img.size[0] != size:
            img = img.resize((size, size), Image.LANCZOS)
        img = img.split()[3] if mode == "ALPHA" else img.convert(mode)
        path = f"{OUT}/{base}_{slot}.png"
        img.save(path, optimize=True)
        total += os.path.getsize(path)
    print(f"{base:14} {mode:5} {size}px x6  ->  {total/1e6:5.1f} MB")
print("done")

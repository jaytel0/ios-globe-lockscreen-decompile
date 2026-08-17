#!/usr/bin/env python3
"""Unwrap the 6 assembled cube faces into an equirectangular world map so the
face->direction mapping and per-face orientation can be checked by eye.

Standard GL/Metal cube convention, with our world axes:
    lon=0 -> +Z, lon=+90 -> +X, lat=+90 -> +Y
"""
import sys, os, numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from build_faces import build_faces
from PIL import Image

# slot order is Metal's: 0=+X 1=-X 2=+Y 3=-Y 4=+Z 5=-Z
# value = index of the assembled face that belongs in that slot
DEFAULT_ORDER = [1, 0, 4, 5, 2, 3]
DEFAULT_ROT   = [0, 0, 0, 0, 0, 0]      # per-slot rotation, multiples of 90 deg

def equirect(faces, order, rot, W=2048, H=1024):
    lon = (np.arange(W) + 0.5) / W * 2 * np.pi - np.pi          # -pi .. pi
    lat = np.pi / 2 - (np.arange(H) + 0.5) / H * np.pi          # +pi/2 .. -pi/2
    lon, lat = np.meshgrid(lon, lat)
    x = np.cos(lat) * np.sin(lon)
    y = np.sin(lat)
    z = np.cos(lat) * np.cos(lon)

    ax, ay, az = np.abs(x), np.abs(y), np.abs(z)
    slot = np.where(ax >= np.maximum(ay, az), np.where(x > 0, 0, 1),
           np.where(ay >= az,                 np.where(y > 0, 2, 3),
                                              np.where(z > 0, 4, 5)))
    ma = np.maximum(ax, np.maximum(ay, az))
    sc = np.select([slot == 0, slot == 1, slot == 2, slot == 3, slot == 4, slot == 5],
                   [-z,        z,         x,         x,         x,        -x])
    tc = np.select([slot == 0, slot == 1, slot == 2, slot == 3, slot == 4, slot == 5],
                   [-y,       -y,         z,        -z,        -y,        -y])
    s = (sc / ma + 1) / 2
    t = (tc / ma + 1) / 2

    size = faces[0].size[0]
    out = np.zeros((H, W, 4), np.uint8)
    for sl in range(6):
        img = faces[order[sl]]
        if rot[sl]:
            img = img.rotate(-90 * rot[sl], expand=True)
        arr = np.asarray(img.convert("RGBA"))
        m = slot == sl
        px = np.clip((s[m] * size).astype(int), 0, size - 1)
        py = np.clip((t[m] * size).astype(int), 0, size - 1)
        out[m] = arr[py, px]
    return Image.fromarray(out, "RGBA")

if __name__ == "__main__":
    layer = sys.argv[1] if len(sys.argv) > 1 else "a"
    mip = int(sys.argv[2]) if len(sys.argv) > 2 else 3
    out = sys.argv[3] if len(sys.argv) > 3 else "thumbs/equirect_test.png"
    faces = build_faces(layer, mip)
    equirect(faces, DEFAULT_ORDER, DEFAULT_ROT).convert("RGB").save(out)
    print("wrote", out)

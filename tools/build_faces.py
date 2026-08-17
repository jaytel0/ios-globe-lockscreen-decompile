#!/usr/bin/env python3
"""Assemble NanoUniverse's 24 Earth tiles into 6 cube faces, per layer."""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from art_mip import decode_mip
from PIL import Image

FW = "rootfs/System/Library/PrivateFrameworks/NanoUniverse.framework"
LAYERS = {            # suffix: (block_w, block_h)
    "a": (6, 6),      # albedo
    "n": (6, 6),      # normal
    "e": (4, 4),      # emissive: RGB city lights, A land/ocean mask
    "c": (4, 4),      # cloud
}

def build_faces(layer, mip=0, planet="p03"):
    bw, bh = LAYERS[layer]
    tiles = [decode_mip(f"{FW}/{planet}-i{i:02d}-{layer}-calliope~iphone.art", bw, bh, mip)
             for i in range(24)]
    s = tiles[0].size[0]
    faces = []
    for f in range(6):
        face = Image.new("RGBA", (s * 2, s * 2))
        for k in range(4):                      # tiles run row-major within a face
            face.paste(tiles[f * 4 + k], ((k % 2) * s, (k // 2) * s))
        faces.append(face)
    return faces

if __name__ == "__main__":
    layer = sys.argv[1] if len(sys.argv) > 1 else "a"
    mip = int(sys.argv[2]) if len(sys.argv) > 2 else 0
    faces = build_faces(layer, mip)
    os.makedirs("faces", exist_ok=True)
    for i, f in enumerate(faces):
        f.save(f"faces/{layer}_{i}.png")
    print(f"layer {layer}: 6 faces of {faces[0].size} written to faces/")

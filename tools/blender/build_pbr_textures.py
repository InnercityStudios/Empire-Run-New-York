"""Build mobile PBR textures from photographic sources (Poly Haven, CC0).

Reads art_source/third_party/textures/polyhaven/<set>/<set>_{diff,nor_gl,arm}_2k.*
and writes 1K derivatives to assets/textures/pbr/<set>_{albedo,normal,arm}.png.
ARM packs ambient occlusion (R), roughness (G) and metalness (B).

Usage: Blender -b --factory-startup --python tools/blender/build_pbr_textures.py
"""
import os

import bpy

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SRC = os.path.join(ROOT, "art_source", "third_party", "textures", "polyhaven")
OUT = os.path.join(ROOT, "assets", "textures", "pbr")
SIZE = 1024
MAPS = {"diff": "albedo", "nor_gl": "normal", "arm": "arm"}

os.makedirs(OUT, exist_ok=True)
for name in sorted(os.listdir(SRC)):
    folder = os.path.join(SRC, name)
    if not os.path.isdir(folder):
        continue
    for src_key, out_key in MAPS.items():
        path = os.path.join(folder, "%s_%s_2k.png" % (name, src_key))
        if not os.path.exists(path):
            print("PBR missing", path)
            continue
        img = bpy.data.images.load(path)
        if out_key != "albedo":
            img.colorspace_settings.name = "Non-Color"
        img.scale(SIZE, SIZE)
        img.filepath_raw = os.path.join(OUT, "%s_%s.png" % (name, out_key))
        img.file_format = "PNG"
        img.save()
        print("PBR %s -> %s_%s.png" % (os.path.basename(path), name, out_key))
        bpy.data.images.remove(img)
print("PBR OK")

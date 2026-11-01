#!/usr/bin/env python3
"""Write Godot .import presets for generated textures before (re)import.

Godot honours an existing .import file when importing a source, so this keeps
mobile-appropriate settings (VRAM compression, mipmaps, normal-map handling)
under version control instead of relying on editor auto-detection.

Usage: python3 tools/configure_imports.py
"""
import glob
import os

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))

TEMPLATE = """[remap]

importer="texture"
type="CompressedTexture2D"

[deps]

source_file="{res}"

[params]

compress/mode={mode}
compress/high_quality=false
compress/lossy_quality=0.7
compress/normal_map={normal}
compress/channel_pack=0
mipmaps/generate=true
mipmaps/limit=-1
roughness/mode=0
process/fix_alpha_border=true
process/premult_alpha=false
process/normal_map_invert_y=false
process/size_limit={limit}
detect_3d/compress_to=0
"""


def sources():
    yield from sorted(glob.glob(os.path.join(ROOT, "assets", "textures", "*.png")))
    # Textures Godot extracts from licensed vehicle GLBs.
    for ext in ("png", "jpg"):
        yield from sorted(glob.glob(os.path.join(ROOT, "assets", "models", "vehicles", "licensed", "*." + ext)))


def main():
    for path in sources():
        name = os.path.basename(path)
        res = "res://" + os.path.relpath(path, ROOT)
        normal = 1 if name.endswith("_normal.png") else 0
        palette = name.startswith("palette_")
        mode = 0 if palette else 2  # palette: lossless for exact swatches
        imp = path + ".import"
        body = TEMPLATE.format(res=res, mode=mode, normal=normal, limit=0)
        old = open(imp).read() if os.path.exists(imp) else ""
        # Preserve the uid Godot assigned so references stay stable.
        uid = next((l for l in old.splitlines() if l.startswith("uid=")), None)
        if uid:
            body = body.replace('type="CompressedTexture2D"\n', 'type="CompressedTexture2D"\n%s\n' % uid)
        if old != body:
            with open(imp, "w") as f:
                f.write(body)
            print("configured", name)


main()

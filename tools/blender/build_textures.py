"""Generate the shared world texture set and material library.

Usage: Blender -b --factory-startup --python tools/blender/build_textures.py
"""
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))

from empire import materials, textures  # noqa: E402

t0 = time.time()
textures.build_all(os.path.join(ROOT, "assets", "textures"))
materials.export_material_library(os.path.join(ROOT, "data", "materials.json"))
print("TEXTURES OK in %.1fs" % (time.time() - t0))

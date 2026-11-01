"""Render a quick geometry preview of exported GLBs (development aid).

Usage: Blender -b --factory-startup --python tools/blender/preview.py -- out.png a.glb [b.glb ...]
Assets are laid out in a row and viewed from a 3/4 elevated angle.
"""
import math
import sys

import bpy
from mathutils import Vector

args = sys.argv[sys.argv.index("--") + 1:]
out, files = args[0], args[1:]
bpy.ops.wm.read_factory_settings(use_empty=True)
x = 0.0
objs = []
for path in files:
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    new = [o for o in bpy.data.objects if o not in before and o.type == "MESH"]
    for o in new:
        w = o.dimensions.x
        o.location.x = x + w * 0.5
        x += w + 2.0
        objs.append(o)
mn = Vector((min(o.location.x - o.dimensions.x * 0.5 for o in objs), -2, 0))
mx = Vector((x, 20, max(o.dimensions.z for o in objs)))
center = (mn + mx) * 0.5
size = max(mx.x - mn.x, mx.z) * 1.15
scene = bpy.context.scene
cam_data = bpy.data.cameras.new("cam")
cam_data.type = "ORTHO"
cam_data.ortho_scale = size
cam = bpy.data.objects.new("cam", cam_data)
scene.collection.objects.link(cam)
d = Vector((0.55, -1.0, 0.75)).normalized()
cam.location = center + d * 120
cam.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()
scene.camera = cam
sun_data = bpy.data.lights.new("sun", "SUN")
sun_data.energy = 3.5
sun = bpy.data.objects.new("sun", sun_data)
sun.rotation_euler = (math.radians(50), math.radians(10), math.radians(30))
scene.collection.objects.link(sun)
scene.render.engine = "BLENDER_WORKBENCH"
scene.display.shading.light = "STUDIO"
scene.display.shading.color_type = "MATERIAL"
scene.display.shading.show_shadows = True
scene.display.shading.show_cavity = True
scene.render.resolution_x = 1600
scene.render.resolution_y = 1000
scene.render.filepath = out
bpy.ops.render.render(write_still=True)
print("PREVIEW", out)

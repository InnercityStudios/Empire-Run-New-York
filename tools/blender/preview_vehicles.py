"""Textured lineup render of vehicle GLBs (development aid).

Usage: Blender -b --factory-startup --python tools/blender/preview_vehicles.py -- out.png a.glb [b.glb ...]
Vehicles are lined up along X, front (+Y) pointing up-screen-right.
"""
import math
import sys

import bpy
from mathutils import Vector

args = sys.argv[sys.argv.index("--") + 1:]
out, files = args[0], args[1:]
bpy.ops.wm.read_factory_settings(use_empty=True)
for i, path in enumerate(files):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    for o in bpy.data.objects:
        if o not in before and o.parent is None:
            o.location.x += i * 3.2
scene = bpy.context.scene
cam_data = bpy.data.cameras.new("cam")
cam_data.type = "ORTHO"
cam_data.ortho_scale = max(8.0, len(files) * 3.4)
cam = bpy.data.objects.new("cam", cam_data)
scene.collection.objects.link(cam)
center = Vector(((len(files) - 1) * 1.6, 0, 0.7))
d = Vector((0.9, 1.0, 0.75)).normalized()
cam.location = center + d * 40
cam.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()
scene.camera = cam
scene.render.engine = "BLENDER_WORKBENCH"
scene.display.shading.light = "STUDIO"
scene.display.shading.color_type = "TEXTURE"
scene.display.shading.show_cavity = True
scene.render.resolution_x = 1800
scene.render.resolution_y = 900
scene.render.filepath = out
bpy.ops.render.render(write_still=True)

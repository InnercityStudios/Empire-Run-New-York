"""Prepare licensed third-party vehicles (art_source/third_party/vehicles) for the game.

Sources stay untouched. Output goes to assets/models/vehicles/licensed/*.glb:
- all parts joined into one mesh (one draw call per material);
- oriented front +Y (Godot -Z), centred, wheels on the ground, real-world scale kept;
- lossless planar cleanup, then a gentle seam-preserving collapse only above budget;
- textures resized per role (paint/glass/lights keep 1024, hidden parts 512);
- optional repaint variants (the family's black sedans).
Godot generates further distance LODs on import.

Usage: Blender -b --factory-startup --python tools/blender/build_licensed_vehicles.py
"""
import json
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
SRC = os.path.join(ROOT, "art_source", "third_party", "vehicles")
OUT = os.path.join(ROOT, "assets", "models", "vehicles", "licensed")

TRI_BUDGET = 10000
KEEP_FULL_RES = ("Bodymat", "Lights_and_Glass")  # material name fragments
HIDDEN_RES = 512

CREDIT = {"author": "Daniel Zhabotinsky", "author_url": "https://sketchfab.com/DanielZhabotinsky",
          "license": "CC-BY-4.0", "license_url": "http://creativecommons.org/licenses/by/4.0/"}

SPECS = [
    {"id": "chapman_73_black", "src": "chapman_73.glb", "title": "Chapman '73", "paint": (0.018, 0.018, 0.02),
     "source_url": "https://sketchfab.com/3d-models/chapman-73-low-poly-model-f30b644b59b54e809355009dce463d47"},
    {"id": "chapman_73", "src": "chapman_73.glb", "title": "Chapman '73",
     "source_url": "https://sketchfab.com/3d-models/chapman-73-low-poly-model-f30b644b59b54e809355009dce463d47"},
    {"id": "chapman_73_police", "src": "chapman_73_cop_cruiser.glb", "title": "Chapman '73 Cop cruiser",
     "source_url": "https://sketchfab.com/3d-models/chapman-73-cop-cruiser-low-poly-model-b71558486d024ecc8dc4abbb1263f022"},
    {"id": "canyon_75_taxi", "src": "canyon_75_taxi.glb", "title": "Canyon '75 Taxi",
     "source_url": "https://sketchfab.com/3d-models/canyon-75-taxi-low-poly-model-9e8f92a215784f3d8aaaaeab1bef54c4"},
    {"id": "phoenix_455_71", "src": "phoenix_455_71.glb", "title": "Phoenix 455 '71",
     "source_url": "https://sketchfab.com/3d-models/phoenix-455-71-low-poly-model-955edc733c6d44fabc0ad7c246a15896"},
    {"id": "phoenix_455_71_maroon", "src": "phoenix_455_71.glb", "title": "Phoenix 455 '71",
     "paint": (0.12, 0.02, 0.018),
     "source_url": "https://sketchfab.com/3d-models/phoenix-455-71-low-poly-model-955edc733c6d44fabc0ad7c246a15896"},
]


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def tri_count(obj):
    return sum(len(p.vertices) - 2 for p in obj.data.polygons)


def join_all():
    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    for o in meshes:
        mw = o.matrix_world.copy()
        o.parent = None
        o.data = o.data.copy()  # make single-user so transforms can be applied
        o.data.transform(mw)
        o.matrix_world = Matrix.Identity(4)
    for o in bpy.data.objects:
        o.select_set(o in meshes)
    bpy.context.view_layer.objects.active = meshes[0]
    bpy.ops.object.join()
    obj = bpy.context.view_layer.objects.active
    for o in list(bpy.data.objects):
        if o != obj:
            bpy.data.objects.remove(o)
    obj.parent = None
    obj.matrix_world = Matrix.Identity(4)
    obj.name = "vehicle"
    return obj




def orient_and_ground(obj, flip):
    """Long axis -> Y, front -> +Y, centred on X/Y, wheels at z = 0.
    These sources already face +Y once imported; `flip` turns a model whose
    front was verified (front-view render) to face -Y."""
    me = obj.data
    xs = [v.co.x for v in me.vertices]
    ys = [v.co.y for v in me.vertices]
    if (max(xs) - min(xs)) > (max(ys) - min(ys)):
        me.transform(Matrix.Rotation(math.radians(90), 4, "Z"))
    if flip:
        me.transform(Matrix.Rotation(math.radians(180), 4, "Z"))
    xs = [v.co.x for v in me.vertices]
    ys = [v.co.y for v in me.vertices]
    zs = [v.co.z for v in me.vertices]
    me.transform(Matrix.Translation((-(max(xs) + min(xs)) * 0.5, -(max(ys) + min(ys)) * 0.5, -min(zs))))
    me.update()


def optimise(obj):
    before = tri_count(obj)
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.0001)
    bm.to_mesh(obj.data)
    bm.free()
    # Lossless: merge coplanar faces without crossing UV seams, materials or sharp edges.
    mod = obj.modifiers.new("planar", "DECIMATE")
    mod.decimate_type = "DISSOLVE"
    mod.angle_limit = math.radians(1.0)
    mod.delimit = {"UV", "MATERIAL", "SEAM", "SHARP"}
    bpy.ops.object.modifier_apply(modifier=mod.name)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.quads_convert_to_tris()
    bpy.ops.object.mode_set(mode="OBJECT")
    after_planar = tri_count(obj)
    if after_planar > TRI_BUDGET:
        mod = obj.modifiers.new("collapse", "DECIMATE")
        mod.decimate_type = "COLLAPSE"
        mod.ratio = TRI_BUDGET / after_planar
        mod.use_collapse_triangulate = True
        mod.use_symmetry = True
        mod.symmetry_axis = "X"
        bpy.ops.object.modifier_apply(modifier=mod.name)
    return before, after_planar, tri_count(obj)


def resize_textures(obj):
    seen = set()
    for m in obj.data.materials:
        if not (m and m.use_nodes):
            continue
        keep = any(f in m.name for f in KEEP_FULL_RES)
        for n in m.node_tree.nodes:
            if n.type == "TEX_IMAGE" and n.image and n.image.name not in seen:
                seen.add(n.image.name)
                w, h = n.image.size
                if not keep and max(w, h) > HIDDEN_RES:
                    n.image.scale(HIDDEN_RES, HIDDEN_RES * h // w)


def repaint(obj, rgb):
    for m in obj.data.materials:
        if m and "Bodymat" in m.name and m.use_nodes:
            bsdf = m.node_tree.nodes.get("Principled BSDF")
            if bsdf:
                bsdf.inputs["Base Color"].default_value = (*rgb, 1.0)
                for link in list(bsdf.inputs["Base Color"].links):
                    # Keep detail maps but tint them: route texture through a multiply.
                    src = link.from_socket
                    mix = m.node_tree.nodes.new("ShaderNodeMix")
                    mix.data_type = "RGBA"
                    mix.blend_type = "MULTIPLY"
                    mix.inputs["Factor"].default_value = 1.0
                    m.node_tree.links.new(src, mix.inputs["A"])
                    mix.inputs["B"].default_value = (*rgb, 1.0)
                    m.node_tree.links.new(mix.outputs["Result"], bsdf.inputs["Base Color"])
                bsdf.inputs["Roughness"].default_value = 0.18


def main():
    os.makedirs(OUT, exist_ok=True)
    credits = []
    only = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    for spec in SPECS:
        if only and spec["id"] not in only:
            continue
        reset()
        bpy.ops.import_scene.gltf(filepath=os.path.join(SRC, spec["src"]))
        obj = join_all()
        orient_and_ground(obj, spec.get("flip", False))
        before, planar, after = optimise(obj)
        resize_textures(obj)
        if spec.get("paint"):
            repaint(obj, spec["paint"])
        dims = obj.dimensions
        out = os.path.join(OUT, spec["id"] + ".glb")
        for o in bpy.context.scene.objects:
            o.select_set(o == obj)
        bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", use_selection=True, export_apply=True,
                                  export_yup=True, export_image_format="AUTO", export_materials="EXPORT",
                                  export_animations=False, export_cameras=False, export_lights=False)
        print("VEHICLE %-24s tris %6d -> planar %6d -> %6d  dims %.2f x %.2f x %.2f  mats %d  %.1f MB" % (
            spec["id"], before, planar, after, dims.x, dims.y, dims.z, len(obj.data.materials),
            os.path.getsize(out) / 1e6))
        credits.append({"id": spec["id"], "title": spec["title"], "source_url": spec["source_url"], **CREDIT,
                        "modifications": "Joined, re-oriented, mesh-optimised, textures resized"
                        + (", repainted" if spec.get("paint") else "")})
    if not only:
        with open(os.path.join(ROOT, "data", "credits_vehicles.json"), "w") as f:
            json.dump({"version": 1, "assets": credits}, f, indent=2)


main()

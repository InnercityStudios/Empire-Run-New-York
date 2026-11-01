"""Prepare licensed third-party buildings (art_source/third_party/buildings) for the game.

Sources stay untouched. Output: assets/models/buildings/lic_*.glb plus
data/building_catalog_licensed.json (merged into the building catalogue).
- The skyscraper pack is split into single buildings; each is scaled to a
  target height (the pack is not modelled to one scale), turned so its main
  facade faces the street (-Y here, +Z in Godot) with the facade on y = 0 and
  the building behind it, like the generated catalogue;
- textures resized for mobile (towers 512, landmarks 1024);
- facade tone sampled from the textures for the distant-city LOD.
Post-1977 buildings in the pack (One WTC, NY Times, Hearst) are skipped.

Usage: Blender -b --factory-startup --python tools/blender/build_licensed_buildings.py
"""
import json
import math
import os

import bmesh
import bpy
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
SRC = os.path.join(ROOT, "art_source", "third_party", "buildings")
OUT = os.path.join(ROOT, "assets", "models", "buildings")

PACK = {"src": "new_york_buildings.glb", "title": "New York Buildings", "author": "sumitmangela",
        "author_url": "https://sketchfab.com/sumitmangela", "license": "CC-BY-4.0",
        "license_url": "http://creativecommons.org/licenses/by/4.0/",
        "source_url": "https://sketchfab.com/3d-models/new-york-buildings-e7922fe0f7b14ed786f84529f9217dac"}
BROOKLYN = {"src": "brooklyn_street_building_low_poly.glb", "title": "Brooklyn Street Building Low Poly",
            "author": "B0rn2D13", "author_url": "https://sketchfab.com/B0rn2D13", "license": "Sketchfab Standard",
            "license_url": "https://sketchfab.com/licenses",
            "source_url": "https://sketchfab.com/3d-models/brooklyn-street-building-low-poly-fa55d25ef06e414c942828c3031ff279"}

# Pack facades face +X; rotate -90 degrees so they face -Y (the street).
SPECS = [
    {"id": "lic_empire_state", "pack": PACK, "objs": ["Object_28"], "height": 205.0, "kind": "landmark_tower", "tex": 1024},
    {"id": "lic_chrysler", "pack": PACK, "objs": ["Object_35"], "height": 175.0, "kind": "landmark_tower", "tex": 1024},
    {"id": "lic_woolworth", "pack": PACK, "objs": ["Object_37"], "height": 140.0, "kind": "landmark_tower", "tex": 1024},
    {"id": "lic_pan_am", "pack": PACK, "objs": ["Object_30"], "height": 135.0, "kind": "landmark_tower", "tex": 1024},
    {"id": "lic_office_block", "pack": PACK, "objs": ["Object_42", "Object_43"], "height": 58.0, "kind": "highrise"},
    {"id": "lic_tower_glass_a", "pack": PACK, "objs": ["Object_16"], "height": 128.0, "kind": "highrise"},
    {"id": "lic_tower_stone", "pack": PACK, "objs": ["Object_20"], "height": 150.0, "kind": "highrise"},
    {"id": "lic_tower_glass_b", "pack": PACK, "objs": ["Object_22"], "height": 92.0, "kind": "highrise"},
    {"id": "lic_tower_glass_c", "pack": PACK, "objs": ["Object_24"], "height": 118.0, "kind": "highrise"},
    {"id": "lic_tower_glass_d", "pack": PACK, "objs": ["Object_26"], "height": 140.0, "kind": "highrise"},
    {"id": "lic_apartment_14", "pack": PACK, "objs": ["Object_14"], "height": 46.0, "kind": "apartment"},
    {"id": "lic_apartment_12", "pack": PACK, "objs": ["Object_10"], "height": 40.0, "kind": "apartment"},
    {"id": "lic_apartment_10", "pack": PACK, "objs": ["Object_4"], "height": 34.0, "kind": "apartment"},
    {"id": "lic_apartment_9", "pack": PACK, "objs": ["Object_6"], "height": 30.0, "kind": "apartment"},
    {"id": "lic_walkup_6", "pack": PACK, "objs": ["Object_8"], "height": 21.0, "kind": "walkup"},
    {"id": "lic_walkup_5", "pack": PACK, "objs": ["Object_12"], "height": 18.0, "kind": "walkup"},
    # Facade faces +Y in the source: turn 180 degrees; real-world scale.
    {"id": "lic_brooklyn_corner", "pack": BROOKLYN, "objs": None, "height": None, "rot": 180, "kind": "brooklyn"},
]


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def tri_count(obj):
    return sum(len(p.vertices) - 2 for p in obj.data.polygons)


def join(names):
    meshes = [o for o in bpy.data.objects if o.type == "MESH" and (names is None or o.name in names)]
    for o in meshes:
        mw = o.matrix_world.copy()
        o.parent = None
        o.data = o.data.copy()
        o.data.transform(mw)
        o.matrix_world = Matrix.Identity(4)
    for o in bpy.data.objects:
        o.select_set(o in meshes)
    bpy.context.view_layer.objects.active = meshes[0]
    if len(meshes) > 1:
        bpy.ops.object.join()
    obj = bpy.context.view_layer.objects.active
    for o in list(bpy.data.objects):
        if o != obj:
            bpy.data.objects.remove(o)
    obj.name = "building"
    return obj


def place(obj, height, rot):
    me = obj.data
    me.transform(Matrix.Rotation(math.radians(rot), 4, "Z"))
    zs = [v.co.z for v in me.vertices]
    if height:
        s = height / (max(zs) - min(zs))
        me.transform(Matrix.Scale(s, 4))
    xs = [v.co.x for v in me.vertices]
    ys = [v.co.y for v in me.vertices]
    zs = [v.co.z for v in me.vertices]
    # Facade on y = 0, building behind it (+Y), centred on x, standing on z = 0.
    me.transform(Matrix.Translation((-(max(xs) + min(xs)) * 0.5, -min(ys), -min(zs))))
    me.update()


def tidy(obj):
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.0005)
    bm.to_mesh(obj.data)
    bm.free()


def textures(obj, limit):
    tones = []
    seen = set()
    for slot in obj.material_slots:
        mat = slot.material
        if not mat or not mat.use_nodes:
            continue
        for n in mat.node_tree.nodes:
            if n.type == "TEX_IMAGE" and n.image and n.image.name not in seen:
                seen.add(n.image.name)
                img = n.image
                w, h = img.size
                if max(w, h) > limit:
                    img.scale(limit, max(1, limit * h // w)) if w >= h else img.scale(max(1, limit * w // h), limit)
                px = img.pixels[:]
                step = max(4, (len(px) // 4 // 4000) * 4)
                r = g = b = 0.0
                n_px = 0
                for i in range(0, len(px) - 3, step):
                    r += px[i]
                    g += px[i + 1]
                    b += px[i + 2]
                    n_px += 1
                if n_px:
                    tones.append((r / n_px, g / n_px, b / n_px))
    if not tones:
        return "#8a8478"
    r, g, b = (sum(t[k] for t in tones) / len(tones) for k in range(3))
    # Image pixels are linear in Blender: back to sRGB for the catalogue.
    srgb = lambda c: 255 * (c ** (1 / 2.2))
    return "#%02x%02x%02x" % (int(srgb(r)), int(srgb(g)), int(srgb(b)))


def main():
    entries = []
    credits = {}
    for spec in SPECS:
        reset()
        pack = spec["pack"]
        bpy.ops.import_scene.gltf(filepath=os.path.join(SRC, pack["src"]))
        obj = join(spec["objs"])
        place(obj, spec["height"], spec.get("rot", -90))
        tidy(obj)
        facade = textures(obj, spec.get("tex", 1024 if spec["kind"] == "highrise" else 512))
        dims = obj.dimensions
        out = os.path.join(OUT, spec["id"] + ".glb")
        for o in bpy.context.scene.objects:
            o.select_set(o == obj)
        bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", use_selection=True, export_apply=True,
                                  export_yup=True, export_image_format="JPEG", export_materials="EXPORT",
                                  export_animations=False, export_cameras=False, export_lights=False)
        entries.append({"id": spec["id"], "kind": spec["kind"], "width": round(dims.x, 2), "depth": round(dims.y, 2),
                        "height": round(dims.z, 2), "facade": facade, "roof_tone": 0.5, "licensed": pack["title"]})
        credits[pack["title"]] = {k: pack[k] for k in ("title", "author", "author_url", "license", "license_url", "source_url")}
        print("BUILDING %-22s tris %6d  dims %.1f x %.1f x %.1f  facade %s  %.2f MB" % (
            spec["id"], tri_count(obj), dims.x, dims.y, dims.z, facade, os.path.getsize(out) / 1e6))
    with open(os.path.join(ROOT, "data", "building_catalog_licensed.json"), "w") as f:
        json.dump({"version": 1, "buildings": entries, "credits": list(credits.values())}, f, indent=2)


main()

"""Build every building GLB and the building catalogue consumed by Godot.

Usage: Blender -b --factory-startup --python tools/blender/build_buildings.py [-- id ...]
"""
import json
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))

from empire.buildings import BuildingGenerator, build_warehouse  # noqa: E402
from empire.geometry import export_glb, reset_scene  # noqa: E402

OUT = os.path.join(ROOT, "assets", "models", "buildings")


def shop(sign, frontage="M_Shopfront_Green", text="M_Sign_Gold", awning=None, variant=0, **kw):
    g = {"type": "shop", "sign": sign, "frontage": frontage, "sign_text": text, "awning": awning,
         "shop_variant": variant}
    g.update(kw)
    return g


# kind: midblock | corner_left | corner_right | landmark
BUILDINGS = [
    # --- Mid-block tenements ---------------------------------------------------
    {"id": "tenement_a", "kind": "midblock", "width": 7.5, "floors": 5, "brick": "M_Brick_Red",
     "cornice_mat": "M_Cornice_Dark", "fire_escape": True,
     "ground": shop("SALUMERIA", "M_Shopfront_Green", awning=1, variant=0, res_door=False)},
    {"id": "tenement_b", "kind": "midblock", "width": 9.0, "floors": 4, "brick": "M_Brick_Brown", "cornice": "simple",
     "ground": shop("PASTICCERIA", "M_Shopfront_Cream", "M_Shopfront_Red", awning=0, variant=1, door_side="left")},
    {"id": "tenement_c", "kind": "midblock", "width": 7.5, "floors": 6, "brick": "M_Brick_Tan",
     "cornice_mat": "M_Cornice_Cream", "fire_escape": True, "water_tower": True,
     "ground": shop("BARBER SHOP", "M_Shopfront_Black", "M_Sign_White", variant=2, res_door=False)},
    {"id": "tenement_d", "kind": "midblock", "width": 10.5, "floors": 5, "brick": "M_Brick_Dark",
     "cornice_mat": "M_Cornice_Green", "fire_escape": True,
     "ground": shop("DELICATESSEN", "M_Shopfront_Red", awning=2, variant=0, res_side="right")},
    {"id": "tenement_e", "kind": "midblock", "width": 9.0, "floors": 5, "brick": "M_Brick_Painted", "cornice": "simple",
     "fire_escape": True, "frame": "M_Frame_Dark",
     "ground": shop("LIQUORS", "M_Shopfront_Black", "M_Sign_White", variant=3, blade="WINE", neon="M_Neon_Red")},
    {"id": "tenement_f", "kind": "midblock", "width": 8.0, "floors": 4, "brick": "M_Brick_Red",
     "cornice_mat": "M_Cornice_Dark", "fire_escape": True,
     "ground": shop("CAFFÈ ROMA", "M_Shopfront_Red", awning=3, variant=1, res_door=False, door_side="left")},
    {"id": "tenement_g", "kind": "midblock", "width": 12.0, "floors": 6, "brick": "M_Brick_Brown",
     "cornice_mat": "M_Cornice_Dark", "fire_escape": True, "water_tower": True, "ac": 0.16,
     "ground": shop("HARDWARE", "M_Shopfront_Green", "M_Sign_White", variant=0, res_side="right")},
    {"id": "tenement_h", "kind": "midblock", "width": 7.5, "floors": 3, "brick": "M_Brick_Tan", "cornice": "simple",
     "ground": {"type": "residential"}},
    {"id": "tenement_i", "kind": "midblock", "width": 10.5, "floors": 5, "brick": "M_Brick_Red",
     "cornice_mat": "M_Cornice_Green", "fire_escape": True,
     "ground": shop("LAUNDROMAT", "M_Shopfront_Cream", "M_Shopfront_Green", variant=2)},
    {"id": "tenement_j", "kind": "midblock", "width": 9.0, "floors": 6, "brick": "M_Brick_Dark",
     "cornice_mat": "M_Cornice_Dark", "fire_escape": True, "water_tower": True,
     "ground": shop("PIZZERIA", "M_Shopfront_Red", awning=0, variant=1, blade="PIZZA", neon="M_Neon_Gold")},
    {"id": "tenement_k", "kind": "midblock", "width": 8.0, "floors": 5, "brick": "M_Brick_Tan",
     "cornice_mat": "M_Cornice_Green", "fire_escape": True,
     "ground": shop("TAILOR", "M_Shopfront_Black", awning=2, variant=3, res_door=False)},
    {"id": "tenement_l", "kind": "midblock", "width": 9.0, "floors": 3, "brick": "M_Brick_Painted", "cornice": "simple",
     "frame": "M_Frame_Dark", "ground": {"type": "residential"}},
    # --- Corner buildings (side facade wraps the street corner) ---------------------
    {"id": "corner_left_a", "kind": "corner_left", "width": 12.0, "floors": 5, "brick": "M_Brick_Red",
     "cornice_mat": "M_Cornice_Dark", "fire_escape": True,
     "ground": shop("LATTICINI", "M_Shopfront_Green", awning=1, variant=0, res_door=False),
     "side_ground": shop("FRESH MOZZARELLA", "M_Shopfront_Green", variant=0, res_side="left")},
    {"id": "corner_left_b", "kind": "corner_left", "width": 12.0, "floors": 6, "brick": "M_Brick_Brown",
     "cornice_mat": "M_Cornice_Cream", "fire_escape": True, "water_tower": True,
     "ground": shop("DRUGS", "M_Shopfront_Cream", "M_Shopfront_Red", variant=2, res_door=False),
     "side_ground": shop("PRESCRIPTIONS", "M_Shopfront_Cream", "M_Shopfront_Red", variant=2)},
    {"id": "corner_right_a", "kind": "corner_right", "width": 12.0, "floors": 5, "brick": "M_Brick_Tan",
     "cornice_mat": "M_Cornice_Green", "fire_escape": True,
     "ground": shop("BAKERY", "M_Shopfront_Red", awning=0, variant=1, res_door=False, door_side="right"),
     "side_ground": shop("PANE FRESCO", "M_Shopfront_Red", variant=1, res_side="right")},
    {"id": "corner_right_b", "kind": "corner_right", "width": 12.0, "floors": 4, "brick": "M_Brick_Dark",
     "cornice_mat": "M_Cornice_Dark", "fire_escape": True,
     "ground": shop("FLORIST", "M_Shopfront_Green", awning=1, variant=0, res_door=False),
     "side_ground": shop("FLOWERS", "M_Shopfront_Green", variant=3, res_side="right")},
    # --- Landmarks: player headquarters and businesses ------------------------------------
    {"id": "hq_social_club", "kind": "landmark", "width": 10.5, "floors": 3, "brick": "M_Brick_Brown",
     "cornice_mat": "M_Cornice_Cream", "frame": "M_Frame_Dark", "ac": 0.0,
     "ground": shop("MARINO SOCIAL CLUB", "M_Shopfront_Black", "M_Sign_Gold", awning=1, variant=3,
                    font="display", lamps=True, res_side="left")},
    {"id": "biz_restaurant_vesuvio", "kind": "landmark", "width": 12.0, "floors": 5, "brick": "M_Brick_Red",
     "cornice_mat": "M_Cornice_Dark", "fire_escape": True, "water_tower": True,
     "ground": shop("RISTORANTE VESUVIO", "M_Shopfront_Red", "M_Sign_Gold", awning=0, variant=1,
                    font="display", blade="VESUVIO", neon="M_Neon_Red", lamps=True)},
    {"id": "biz_trattoria_napoli", "kind": "landmark", "width": 10.5, "floors": 4, "brick": "M_Brick_Tan",
     "cornice_mat": "M_Cornice_Green", "fire_escape": True,
     "ground": shop("TRATTORIA NAPOLI", "M_Shopfront_Green", "M_Sign_Gold", awning=1, variant=1,
                    font="display", res_side="right")},
    {"id": "biz_bar_blue_lantern", "kind": "landmark", "width": 9.0, "floors": 4, "brick": "M_Brick_Dark",
     "cornice_mat": "M_Cornice_Dark", "fire_escape": True,
     "ground": shop("THE BLUE LANTERN", "M_Shopfront_Black", "M_Sign_White", awning=2, variant=3,
                    blade="BAR", neon="M_Neon_Green")},
    {"id": "biz_garage_bowery", "kind": "landmark", "width": 14.0, "floors": 2, "brick": "M_Brick_Painted",
     "cornice": "simple", "frame": "M_Frame_Dark", "ac": 0.0,
     "ground": {"type": "garage", "sign": "BOWERY AUTO BODY", "sign_board": "M_Sign_White",
                "sign_text": "M_Shopfront_Red", "shutter": "M_Shutter_Green"}},
    {"id": "biz_warehouse_grand", "kind": "landmark", "builder": "warehouse", "width": 24.0, "depth": 22.0,
     "floors": 4, "brick": "M_Brick_Red", "water_tower": True,
     "sign": "GRAND STREET FREIGHT & STORAGE", "side_sign": "STORAGE · CARTAGE · FREIGHT"},
]


def main():
    only = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    catalog_path = os.path.join(ROOT, "data", "building_catalog.json")
    catalog = {}
    if only and os.path.exists(catalog_path):
        with open(catalog_path) as f:
            catalog = {b["id"]: b for b in json.load(f)["buildings"]}
    t0 = time.time()
    for spec in BUILDINGS:
        if only and spec["id"] not in only:
            continue
        reset_scene()
        if spec.get("builder") == "warehouse":
            mb = build_warehouse(spec)
        else:
            mb = BuildingGenerator(spec).build()
        tris = mb.triangle_count()
        obj = mb.build()
        height = max(v.co.z for v in obj.data.vertices)
        export_glb(obj, os.path.join(OUT, spec["id"] + ".glb"))
        catalog[spec["id"]] = {
            "id": spec["id"],
            "kind": spec["kind"],
            "scene": "res://assets/models/buildings/%s.glb" % spec["id"],
            "width": spec["width"],
            "depth": spec.get("depth", 20.0),
            "height": round(height, 2),
            "triangles": tris,
            "materials": len(obj.data.materials),
        }
        print("BUILT %-26s tris=%6d mats=%2d h=%.1f" % (spec["id"], tris, len(obj.data.materials), height))
    with open(catalog_path, "w") as f:
        json.dump({"version": 1, "buildings": [catalog[k] for k in sorted(catalog)]}, f, indent=2)
    print("BUILDINGS OK in %.1fs" % (time.time() - t0))


main()

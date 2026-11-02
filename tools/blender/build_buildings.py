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

from empire import buildings_extra  # noqa: E402
from empire.buildings import BuildingGenerator, build_warehouse  # noqa: E402
from empire.geometry import export_glb, reset_scene  # noqa: E402

OUT = os.path.join(ROOT, "assets", "models", "buildings")

FACADE_TONES = {
    "M_Brick_Red": "#7e3a2b", "M_Brick_Brown": "#634434", "M_Brick_Tan": "#a2845f", "M_Brick_Dark": "#4d2b23",
    "M_Brick_Painted": "#cfc6b4", "M_Stone": "#b8ae9b", "M_Siding_White": "#d9d2c2", "M_Siding_Green": "#7d9a84",
    "M_Siding_Yellow": "#d4bd84", "M_Siding_Blue": "#8da2b4",
}
ROOF_TONES = {"M_Roof_Tar": 0.15, "M_Roof_Silver": 0.85, "M_Roof_Gravel": 0.55, "M_Shingle_Gray": 0.35,
              "M_Shingle_Brown": 0.3, "M_Shingle_Slate": 0.25}


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
    # --- Taller elevator apartments and low commercial strips (new silhouettes) -----
    {"id": "apartment_tall_a", "kind": "midblock_tall", "width": 16.0, "floors": 8, "brick": "M_Brick_Tan",
     "cornice_mat": "M_Cornice_Cream", "fire_escape": True, "water_tower": True, "lintel": "hood", "quoins": True,
     "setback": {"floors": 2, "inset": 2.5},
     "ground": shop("GRAND LUNCHEONETTE", "M_Shopfront_Cream", "M_Shopfront_Red", awning=1, variant=1)},
    {"id": "apartment_tall_b", "kind": "midblock_tall", "width": 14.0, "floors": 9, "brick": "M_Brick_Brown",
     "cornice_mat": "M_Cornice_Dark", "fire_escape": True, "lintel": "keystone",
     "setback": {"floors": 1, "inset": 2.0},
     "ground": shop("MERCATO", "M_Shopfront_Green", awning=0, variant=0, res_side="right")},
    {"id": "taxpayer_a", "kind": "midblock_low", "width": 15.0, "floors": 0, "brick": "M_Brick_Painted",
     "cornice": "simple", "frame": "M_Frame_Dark", "ground_h": 4.6,
     "ground": shop("DISCOUNT RECORDS & RADIO", "M_Shopfront_Black", "M_Neon_Red", awning=2, variant=2)},
    # --- Rowhouses (brownstone residential blocks) ---------------------------------
    {"id": "rowhouse_a", "kind": "rowhouse", "width": 6.5, "floors": 3, "brick": "M_Brick_Brown", "lintel": "hood",
     "cornice_mat": "M_Cornice_Dark", "ground": {"type": "residential"}, "ac": 0.05},
    {"id": "rowhouse_b", "kind": "rowhouse", "width": 7.0, "floors": 4, "brick": "M_Brick_Dark", "lintel": "keystone",
     "cornice_mat": "M_Cornice_Dark", "ground": {"type": "residential"}, "ac": 0.05},
    {"id": "rowhouse_c", "kind": "rowhouse", "width": 6.0, "floors": 3, "brick": "M_Brick_Red", "lintel": "flat",
     "cornice": "simple", "ground": {"type": "residential"}, "ac": 0.08},
    {"id": "rowhouse_d", "kind": "rowhouse", "width": 7.5, "floors": 4, "brick": "M_Brick_Tan", "lintel": "hood",
     "cornice_mat": "M_Cornice_Green", "ground": {"type": "residential"}, "ac": 0.05},
    # --- Industrial: warehouses, lofts, works ---------------------------------------------
    {"id": "warehouse_a", "kind": "industrial", "builder": "warehouse", "width": 24.0, "depth": 30.0, "floors": 4,
     "brick": "M_Brick_Red", "sign": "", "side_sign": "", "roof": "M_Roof_Tar"},
    {"id": "warehouse_b", "kind": "industrial", "builder": "warehouse", "width": 20.0, "depth": 26.0, "floors": 3,
     "brick": "M_Brick_Brown", "sign": "HUDSON COLD STORAGE", "side_sign": "", "water_tower": True},
    {"id": "loft_a", "kind": "industrial", "builder": "warehouse", "width": 16.0, "depth": 24.0, "floors": 6,
     "brick": "M_Brick_Tan", "sign": "", "side_sign": "", "floor_h": 3.6},
    {"id": "warehouse_c", "kind": "industrial", "builder": "warehouse", "width": 28.0, "depth": 34.0, "floors": 2,
     "brick": "M_Brick_Dark", "sign": "MERCHANTS TRUCKING", "side_sign": "TRUCKING · CARTAGE"},
    {"id": "factory_a", "kind": "industrial", "builder": "factory", "width": 30.0, "depth": 36.0, "brick": "M_Brick_Red"},
    # --- Suburban houses and the family estate ----------------------------------------
    {"id": "house_a", "kind": "house", "builder": "house", "width": 11.0, "depth": 10.0, "wall": "M_Siding_White",
     "roof": "M_Shingle_Gray", "seed": 1},
    {"id": "house_b", "kind": "house", "builder": "house", "width": 10.0, "depth": 9.5, "wall": "M_Siding_Green",
     "roof": "M_Shingle_Brown", "trim": "M_Frame_White", "seed": 2},
    {"id": "house_c", "kind": "house", "builder": "house", "width": 12.0, "depth": 10.5, "wall": "M_Brick_Red",
     "roof": "M_Shingle_Slate", "hip": True, "seed": 3},
    {"id": "house_d", "kind": "house", "builder": "house", "width": 10.5, "depth": 9.0, "wall": "M_Siding_Yellow",
     "roof": "M_Shingle_Gray", "seed": 4, "garage": False},
    {"id": "house_e", "kind": "house", "builder": "house", "width": 11.5, "depth": 10.0, "wall": "M_Siding_Blue",
     "roof": "M_Shingle_Slate", "hip": True, "seed": 5},
    {"id": "estate_a", "kind": "estate", "builder": "estate", "width": 26.0, "depth": 18.0, "wall": "M_Stone",
     "roof": "M_Shingle_Slate", "seed": 6},
    # --- Waterfront ---------------------------------------------------------------------
    {"id": "pier_shed_a", "kind": "pier", "builder": "pier_shed", "width": 26.0, "depth": 150.0},
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
    # Family estates (world-map mansions by level, and grounds pieces).
    {"id": "mansion_l1", "kind": "mansion", "builder": "mansion", "level": 1, "width": 30.0, "depth": 18.0},
    {"id": "mansion_l2", "kind": "mansion", "builder": "mansion", "level": 2, "width": 58.0, "depth": 18.0},
    {"id": "mansion_l3", "kind": "mansion", "builder": "mansion", "level": 3, "width": 58.0, "depth": 22.0},
    {"id": "estate_gatehouse", "kind": "estate_part", "builder": "estate_gatehouse", "width": 14.0, "depth": 5.0},
    {"id": "estate_wall", "kind": "estate_part", "builder": "estate_wall", "width": 20.0, "depth": 1.0},
    {"id": "estate_garage", "kind": "estate_part", "builder": "estate_garage", "width": 15.0, "depth": 8.0},
    {"id": "estate_fountain", "kind": "estate_part", "builder": "fountain", "width": 6.4, "depth": 6.4},
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
        builder = spec.get("builder")
        if builder == "warehouse":
            mb = build_warehouse(spec)
        elif builder in ("house", "estate", "factory", "pier_shed", "mansion", "estate_gatehouse", "estate_wall",
                         "estate_garage", "fountain"):
            mb = getattr(buildings_extra, "build_" + builder)(spec)
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
            # Average tones for the distant-city LOD box.
            "facade": FACADE_TONES.get(spec.get("wall", spec.get("brick", "")), "#7a5a48"),
            "roof_tone": ROOF_TONES.get(spec.get("roof", ""), 0.5),
        }
        print("BUILT %-26s tris=%6d mats=%2d h=%.1f" % (spec["id"], tris, len(obj.data.materials), height))
    with open(catalog_path, "w") as f:
        json.dump({"version": 1, "buildings": [catalog[k] for k in sorted(catalog)]}, f, indent=2)
    print("BUILDINGS OK in %.1fs" % (time.time() - t0))


main()

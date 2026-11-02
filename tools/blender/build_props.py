"""Build vehicle and street-prop GLBs.

Usage: Blender -b --factory-startup --python tools/blender/build_props.py
"""
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))

from empire import props, vehicles  # noqa: E402
from empire.geometry import export_glb, reset_scene  # noqa: E402

ASSETS = [
    ("vehicles/sedan_black", lambda: vehicles.build_sedan(name="sedan_black")),
    ("vehicles/taxi", lambda: vehicles.build_sedan(paint="M_CarPaint_Taxi", roof="M_CarPaint_Taxi", taxi=True,
                                                   name="taxi")),
    ("vehicles/box_truck", vehicles.build_box_truck),
    ("props/street_lamp", props.build_street_lamp),
    ("props/traffic_signal", props.build_traffic_signal),
    ("props/fire_hydrant", props.build_hydrant),
    ("props/mailbox", props.build_mailbox),
    ("props/trash_can", props.build_trash_can),
    ("props/newspaper_box", props.build_newspaper_box),
    ("props/tree_a", lambda: props.build_tree(3, "tree_a")),
    ("props/tree_b", lambda: props.build_tree(11, "tree_b")),
    ("props/tree_far", props.build_tree_far),
    ("props/subway_entrance", props.build_subway_entrance),
    ("props/bus_stop", props.build_bus_stop),
    ("props/phone_booth", props.build_phone_booth),
    ("props/newsstand", props.build_newsstand),
    ("props/trash_pile", props.build_trash_pile),
    ("props/parking_meter", props.build_parking_meter),
    ("props/tree_oak", lambda: props.build_oak(21, "tree_oak")),
    ("props/tree_oak_b", lambda: props.build_oak(37, "tree_oak_b")),
    ("props/tree_maple", lambda: props.build_maple(22, "tree_maple")),
    ("props/tree_birch", lambda: props.build_birch(23, "tree_birch")),
    ("props/tree_pine", lambda: props.build_pine(24, "tree_pine")),
    ("props/tree_poplar", lambda: props.build_poplar(25, "tree_poplar")),
    ("props/tree_pine_far", props.build_pine_far),
    ("props/bush_a", lambda: props.build_bush(31, "bush_a")),
    ("props/bush_b", lambda: props.build_bush(32, "bush_b")),
    ("props/rock_a", lambda: props.build_rock(41, "rock_a", (2.4, 1.8, 1.2))),
    ("props/rock_b", lambda: props.build_rock(42, "rock_b", (3.8, 2.6, 1.0))),
    ("props/rock_c", lambda: props.build_rock(43, "rock_c", (1.2, 1.1, 1.1))),
    ("props/reeds", lambda: props.build_reeds(51, "reeds")),
]

t0 = time.time()
only = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
for rel, fn in ASSETS:
    if only and rel.split("/")[-1] not in only:
        continue
    reset_scene()
    mb = fn()
    tris = mb.triangle_count()
    obj = mb.build()
    export_glb(obj, os.path.join(ROOT, "assets", "models", rel + ".glb"))
    print("BUILT %-24s tris=%5d mats=%d" % (rel, tris, len(obj.data.materials)))
print("PROPS OK in %.1fs" % (time.time() - t0))

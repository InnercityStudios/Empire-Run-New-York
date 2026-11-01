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
    ("props/subway_entrance", props.build_subway_entrance),
    ("props/bus_stop", props.build_bus_stop),
    ("props/phone_booth", props.build_phone_booth),
    ("props/newsstand", props.build_newsstand),
    ("props/trash_pile", props.build_trash_pile),
    ("props/parking_meter", props.build_parking_meter),
]

t0 = time.time()
for rel, fn in ASSETS:
    reset_scene()
    mb = fn()
    tris = mb.triangle_count()
    obj = mb.build()
    export_glb(obj, os.path.join(ROOT, "assets", "models", rel + ".glb"))
    print("BUILT %-24s tris=%5d mats=%d" % (rel, tris, len(obj.data.materials)))
print("PROPS OK in %.1fs" % (time.time() - t0))

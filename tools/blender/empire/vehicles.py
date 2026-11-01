"""Original 1970s-era vehicles. Front faces +Y (Godot -Z), origin at ground
centre. Paint uses a single named material so Godot can recolour instances.
"""
import math

from mathutils import Matrix, Vector

from .geometry import MeshBuilder


def _wheel(mb, cx, cy, r=0.37, w=0.24, whitewall=True):
    rot = Matrix.Rotation(math.radians(90), 4, "Y")
    side = 1 if cx > 0 else -1
    m = Matrix.Translation((cx - side * w * 0.5, cy, r)) @ rot
    mb.add_cylinder((0, 0, 0), r, w, 14, "M_Tire", cap_top=False, matrix=m, smooth=True)
    hub = Matrix.Translation((cx + side * w * 0.5, cy, r)) @ Matrix.Rotation(math.radians(90 * side), 4, "Y")
    mb.add_cylinder((0, 0, 0), r * 0.82, 0.012, 14, "M_Whitewall" if whitewall else "M_Tire", cap_top=True,
                    matrix=hub, smooth=False)
    mb.add_cylinder((0, 0, 0.012), r * 0.5, 0.03, 12, "M_Chrome", cap_top=True, matrix=hub, smooth=False)


def build_sedan(paint="M_CarPaint", roof="M_VinylRoof", taxi=False, name="sedan"):
    """Long, low, square-shouldered four-door sedan (5.6 m)."""
    mb = MeshBuilder(name)
    hw = 1.0  # half width
    # Body side profile (y forward, z up), extruded across the width.
    prof = [(-2.78, 0.34), (2.78, 0.34), (2.82, 0.62), (2.78, 0.84), (2.55, 0.9), (0.98, 0.96),
            (-1.38, 0.96), (-2.6, 0.93), (-2.8, 0.86), (-2.83, 0.6)]
    mb.add_prism([(-hw, y, z) for y, z in prof], (-hw, 0, 0), (hw, 0, 0), paint)
    # Greenhouse: frustum from belt line to roof with glass sides, tumblehome.
    bw, tw = 0.94, 0.8
    b = [(-bw, -1.35, 0.96), (bw, -1.35, 0.96), (bw, 0.95, 0.96), (-bw, 0.95, 0.96)]
    t = [(-tw, -0.92, 1.42), (tw, -0.92, 1.42), (tw, 0.32, 1.42), (-tw, 0.32, 1.42)]
    for i in range(4):
        j = (i + 1) % 4
        mid = Vector(b[i]) + Vector(b[j])
        mb.add_face([b[i], b[j], t[j], t[i]], "M_CarGlass", normal=(mid.x, mid.y, 0.3))
    mb.add_face(t, roof, normal=(0, 0, 1))
    # Pillars (A, B, C) as paint strips over the glass
    for s in (-1, 1):
        x = s * 0.875
        for (y0, z0, y1, z1, wdt) in ((0.95, 0.96, 0.32, 1.42, 0.09), (-0.32, 0.96, -0.3, 1.42, 0.1),
                                      (-1.35, 0.96, -0.92, 1.42, 0.22)):
            xo = s * (0.947 if z0 < 1 else 0.81)
            xt = s * 0.807
            mb.add_face([(s * 0.945, y0 - wdt * 0.5, z0), (s * 0.945, y0 + wdt * 0.5, z0),
                         (xt, y1 + wdt * 0.5, z1), (xt, y1 - wdt * 0.5, z1)], paint, normal=(s, 0, 0.2))
    # Chrome bumpers, grille, lamps
    mb.add_box((-1.02, 2.78, 0.34), (1.02, 2.95, 0.55), "M_Chrome")
    mb.add_box((-1.02, -2.98, 0.34), (1.02, -2.8, 0.55), "M_Chrome")
    mb.add_box((-0.62, 2.8, 0.58), (0.62, 2.84, 0.82), "M_Grille")
    mb.add_box((-0.66, 2.79, 0.56), (0.66, 2.83, 0.6), "M_Chrome")
    for s in (-1, 1):
        for x in (0.72, 0.9):
            mb.add_box((s * x - 0.075, 2.79, 0.62), (s * x + 0.075, 2.84, 0.78), "M_Headlight")
        mb.add_box((s * 0.98 - 0.32 * (s > 0), -2.84, 0.6), (s * 0.98 + 0.32 * (s < 0), -2.79, 0.8), "M_Taillight")
        mb.add_box((s * 1.0, -2.6, 0.62), (s * 1.012, 2.6, 0.66), "M_Chrome")  # side trim spear
        mb.add_box((s * 1.0, 0.75, 0.98), (s * 1.12, 0.85, 1.05), "M_Chrome")  # mirror
    mb.add_box((-0.03, 2.5, 0.9), (0.03, 2.62, 0.98), "M_Chrome")  # hood ornament
    # Wheels (whitewalls)
    for x in (-0.86, 0.86):
        for y in (1.7, -1.55):
            _wheel(mb, x, y, whitewall=not taxi)
    if taxi:
        mb.add_box((-0.35, -0.45, 1.42), (0.35, -0.15, 1.62), "M_Sign_White")
        mb.add_box((-1.002, -0.6, 0.5), (1.002, 0.4, 0.56), "M_Sign_Black")
    return mb


def build_box_truck(paint="M_CarPaint_Truck", name="box_truck"):
    mb = MeshBuilder(name)
    # Cab
    cab = [(-1.1, 1.6, 0.45), (1.1, 1.6, 0.45), (1.1, 3.2, 0.45), (-1.1, 3.2, 0.45)]
    mb.add_box((-1.1, 1.6, 0.45), (1.1, 3.25, 1.35), paint)
    mb.add_box((-1.05, 1.6, 1.35), (1.05, 2.7, 2.35), paint, mats={"py": "M_CarGlass"})
    mb.add_face([(-1.05, 2.7, 1.35), (1.05, 2.7, 1.35), (1.05, 2.45, 2.35), (-1.05, 2.45, 2.35)], "M_CarGlass",
                normal=(0, 1, 0.3))
    mb.add_box((-1.15, 3.2, 0.4), (1.15, 3.35, 0.65), "M_Chrome")
    mb.add_box((-0.7, 3.24, 0.7), (0.7, 3.27, 1.2), "M_Grille")
    for s in (-1, 1):
        mb.add_box((s * 0.85 - 0.12, 3.24, 0.85), (s * 0.85 + 0.12, 3.28, 1.05), "M_Headlight")
    # Cargo box
    mb.add_box((-1.2, -3.2, 0.55), (1.2, 1.5, 3.1), "M_Sign_White")
    mb.add_box((-1.0, -3.24, 0.65), (1.0, -3.2, 2.9), "M_Shutter")
    mb.add_box((-1.2, -3.3, 0.4), (1.2, 1.6, 0.6), "M_Grille")
    for s in (-1, 1):
        mb.add_box((s * 1.1 - 0.1, -3.32, 0.62), (s * 1.1 + 0.1, -3.28, 0.82), "M_Taillight")
    for x in (-0.95, 0.95):
        for y in (2.4, -1.4, -2.3):
            _wheel(mb, x, y, r=0.46, w=0.3, whitewall=False)
    return mb

"""Building families beyond the tenement core: detached houses and estates,
sawtooth factories and arched pier sheds. Same conventions as buildings.py:
origin at the front-centre at ground level, front facing -Y, depth to +Y.
"""
import math
import random

from mathutils import Vector

from .buildings import Facade, atlas_uv
from .geometry import MeshBuilder
from .textures import WINDOW_ATLAS_COLS, WINDOW_ATLAS_ROWS


def _ground_ao(p, n):
    if abs(n.z) < 0.5:
        return 0.72 + 0.28 * min(1.0, max(0.0, p.z / 1.8))
    return 0.75 if n.z < -0.5 else 1.0


def _window(f, u0, u1, v0, v1, frame, rng, depth=0.12):
    f.quad(u0, u1, v0, v1, -depth + 0.02, "M_Window",
           atlas_uv(rng.randrange(WINDOW_ATLAS_COLS * WINDOW_ATLAS_ROWS), WINDOW_ATLAS_COLS, WINDOW_ATLAS_ROWS))
    for (a, b, c, d) in ((u0 - 0.08, u1 + 0.08, v0 - 0.08, v0), (u0 - 0.08, u1 + 0.08, v1, v1 + 0.08),
                         (u0 - 0.08, u0, v0, v1), (u1, u1 + 0.08, v0, v1)):
        f.quad(a, b, c, d, 0.02, frame)
    f.quad(u0, u1, (v0 + v1) * 0.5 - 0.03, (v0 + v1) * 0.5 + 0.03, -depth + 0.04, frame)


def _gable(mb, x0, x1, y0, y1, z, rise, roof, wall, overhang=0.35):
    """Gable roof with the ridge running along X."""
    ym = (y0 + y1) * 0.5
    zr = z + rise
    xo0, xo1 = x0 - overhang, x1 + overhang
    yo0, yo1 = y0 - overhang, y1 + overhang
    k = rise / (ym - y0)
    zl = z - overhang * k
    mb.add_face([(xo0, yo0, zl), (xo1, yo0, zl), (xo1, ym, zr), (xo0, ym, zr)], roof, normal=(0, -1, 1))
    mb.add_face([(xo1, yo1, zl), (xo0, yo1, zl), (xo0, ym, zr), (xo1, ym, zr)], roof, normal=(0, 1, 1))
    for x, s in ((x0, -1), (x1, 1)):
        mb.add_face([(x, y0, z), (x, y1, z), (x, ym, zr)], wall, normal=(s, 0, 0))


def _hip(mb, x0, x1, y0, y1, z, rise, roof, overhang=0.5):
    xo0, xo1, yo0, yo1 = x0 - overhang, x1 + overhang, y0 - overhang, y1 + overhang
    inset = min((y1 - y0), (x1 - x0)) * 0.5
    zr = z + rise
    r0 = Vector((xo0 + inset, (yo0 + yo1) * 0.5, zr))
    r1 = Vector((xo1 - inset, (yo0 + yo1) * 0.5, zr))
    c = [Vector((xo0, yo0, z)), Vector((xo1, yo0, z)), Vector((xo1, yo1, z)), Vector((xo0, yo1, z))]
    mb.add_face([c[0], c[1], r1, r0], roof, normal=(0, -1, 1))
    mb.add_face([c[2], c[3], r0, r1], roof, normal=(0, 1, 1))
    mb.add_face([c[1], c[2], r1], roof, normal=(1, 0, 1))
    mb.add_face([c[3], c[0], r0], roof, normal=(-1, 0, 1))


def build_house(spec):
    """Two-storey detached house: siding or brick, gable roof, porch, chimney
    and an attached garage."""
    rng = random.Random(spec["seed"])
    mb = MeshBuilder(spec["id"])
    mb.shade_fn = _ground_ao
    W, D = spec["width"], spec.get("depth", 10.0)
    wall = spec["wall"]
    trim = spec.get("trim", "M_Frame_White")
    fh = 2.9
    H = fh * 2 + 0.4
    x0, x1 = -W * 0.5, W * 0.5
    mb.add_box((x0, 0, 0), (x1, D, 0.45), "M_Concrete", skip=("nz",))
    mb.add_box((x0 + 0.05, 0.05, 0.45), (x1 - 0.05, D - 0.05, H), wall, skip=("nz", "pz"))
    f = Facade(mb, (x0, 0, 0), (1, 0, 0), W, H)
    cols = [W * t for t in (0.2, 0.4, 0.6, 0.8)] if W > 10 else [W * t for t in (0.25, 0.5, 0.75)]
    door_u = cols[len(cols) // 2]
    for k in range(2):
        z = 0.45 + k * fh
        for c in cols:
            if k == 0 and abs(c - door_u) < 0.1:
                f.quad(c - 0.5, c + 0.5, z, z + 2.2, -0.05, "M_Door")
                continue
            _window(f, c - 0.45, c + 0.45, z + 0.85, z + 2.2, trim, rng)
    # Side and back windows
    for side, right, width in (((x0, D, 0), (0, -1, 0), D), ((x1, 0, 0), (0, 1, 0), D), ((x1, D, 0), (-1, 0, 0), W)):
        sf = Facade(mb, side, right, width, H)
        for k in range(2):
            for t in (0.3, 0.7):
                z = 0.45 + k * fh
                _window(sf, width * t - 0.45, width * t + 0.45, z + 0.85, z + 2.1, trim, rng)
    # Porch with posts and roof
    pw = min(W * 0.55, 6.0)
    mb.add_box((door_u - W * 0.5 - pw * 0.5, -2.2, 0), (door_u - W * 0.5 + pw * 0.5, 0, 0.45), "M_Wood", skip=("nz",))
    for t in (0.0, 1.0):
        px = door_u - W * 0.5 - pw * 0.5 + 0.15 + (pw - 0.3) * t
        mb.add_box((px - 0.08, -2.1, 0.45), (px + 0.08, -1.94, 3.2), trim)
    mb.add_face([(door_u - W * 0.5 - pw * 0.5 - 0.2, -2.5, 3.1), (door_u - W * 0.5 + pw * 0.5 + 0.2, -2.5, 3.1),
                 (door_u - W * 0.5 + pw * 0.5 + 0.2, 0, 3.45), (door_u - W * 0.5 - pw * 0.5 - 0.2, 0, 3.45)],
                spec["roof"], normal=(0, -0.3, 1))
    if spec.get("hip"):
        _hip(mb, x0, x1, 0, D, H, 2.6, spec["roof"])
    else:
        _gable(mb, x0, x1, 0, D, H, 2.8, spec["roof"], wall)
    # Chimney
    cx = x1 - 1.2 if rng.random() < 0.5 else x0 + 0.6
    mb.add_box((cx, D * 0.6, H - 1.0), (cx + 0.7, D * 0.6 + 0.7, H + 3.4), "M_Brick_Red", skip=("nz",),
               mats={"pz": "M_Tarpaper"})
    # Attached garage
    if spec.get("garage", True):
        gx = x1 if rng.random() < 0.5 else x0 - 4.0
        mb.add_box((gx, 1.5, 0), (gx + 4.0, D, 3.0), wall, skip=("nz",), mats={"pz": "M_Tarpaper"})
        side_face = Facade(mb, (gx, 1.5, 0), (1, 0, 0), 4.0, 3.0)
        side_face.quad(0.4, 3.6, 0.05, 2.5, 0.01, "M_Shutter")
    return mb


def build_estate(spec):
    """Family estate: three-storey stone mansion, columned portico, hip roof."""
    rng = random.Random(spec["seed"])
    mb = MeshBuilder(spec["id"])
    mb.shade_fn = _ground_ao
    W, D = spec["width"], spec.get("depth", 18.0)
    wall = spec.get("wall", "M_Stone")
    fh = 3.4
    H = fh * 3 + 0.6
    x0, x1 = -W * 0.5, W * 0.5
    mb.add_box((x0, 0, 0), (x1, D, 0.6), "M_Stone", skip=("nz",))
    mb.add_box((x0 + 0.05, 0.05, 0.6), (x1 - 0.05, D - 0.05, H), wall, skip=("nz", "pz"))
    f = Facade(mb, (x0, 0, 0), (1, 0, 0), W, H)
    n = int(W / 2.6)
    for k in range(3):
        z = 0.6 + k * fh
        for i in range(n):
            c = W * (i + 0.5) / n
            if k == 0 and i == n // 2:
                f.quad(c - 0.8, c + 0.8, z, z + 2.9, -0.08, "M_Door")
                continue
            _window(f, c - 0.55, c + 0.55, z + 0.8, z + 2.6, "M_Frame_White", rng, 0.18)
    f.box(0, W, 0.6 + fh - 0.25, 0.6 + fh - 0.05, 0, 0.12, "M_Stone")
    f.box(0, W, H - 0.5, H, 0, 0.35, "M_Cornice_Cream")
    # Columned portico
    pw = 9.0
    mb.add_box((-pw * 0.5, -4.0, 0), (pw * 0.5, 0, 0.6), "M_Stone", skip=("nz",))
    for i in range(4):
        px = -pw * 0.5 + 0.6 + (pw - 1.2) * i / 3
        mb.add_cylinder((px, -3.4, 0.6), 0.3, 6.2, 10, "M_Frame_White", cap_top=False)
    mb.add_box((-pw * 0.5 - 0.3, -4.2, 6.8), (pw * 0.5 + 0.3, 0, 7.6), "M_Cornice_Cream")
    mb.add_face([(-pw * 0.5 - 0.3, -4.2, 7.6), (pw * 0.5 + 0.3, -4.2, 7.6), (0, -4.2, 9.2)], "M_Cornice_Cream",
                normal=(0, -1, 0))
    _hip(mb, x0, x1, 0, D, H, 4.0, spec.get("roof", "M_Roof_Tar"))
    for cx in (x0 + 2.0, x1 - 2.7):
        mb.add_box((cx, D * 0.5, H), (cx + 0.8, D * 0.5 + 0.8, H + 4.6), "M_Brick_Red", skip=("nz",),
                   mats={"pz": "M_Tarpaper"})
    return mb


def build_factory(spec):
    """Single-storey works with a north-light sawtooth roof and a chimney."""
    mb = MeshBuilder(spec["id"])
    mb.shade_fn = _ground_ao
    W, D = spec["width"], spec.get("depth", 36.0)
    brick = spec.get("brick", "M_Brick_Red")
    h = 6.5
    x0, x1 = -W * 0.5, W * 0.5
    mb.add_box((x0, 0, 0), (x1, D, h), brick, skip=("nz", "pz"))
    f = Facade(mb, (x0, 0, 0), (1, 0, 0), W, h)
    bays = int(W / 6)
    for i in range(bays):
        c = W * (i + 0.5) / bays
        if i == bays // 2:
            f.quad(c - 2.0, c + 2.0, 0.02, 4.2, 0.01, "M_Shutter")
        else:
            f.quad(c - 1.6, c + 1.6, 1.6, 4.8, 0.01, "M_Window", atlas_uv(7, WINDOW_ATLAS_COLS, WINDOW_ATLAS_ROWS))
    teeth = int(D / 6)
    for i in range(teeth):
        y0 = i * D / teeth
        y1 = (i + 1) * D / teeth
        mb.add_face([(x0, y0, h), (x1, y0, h), (x1, y1, h + 2.6), (x0, y1, h + 2.6)], "M_Roof_Silver",
                    normal=(0, -0.6, 1))
        mb.add_face([(x0, y1, h), (x1, y1, h), (x1, y1, h + 2.6), (x0, y1, h + 2.6)], "M_Window",
                    normal=(0, 1, 0), uvs=atlas_uv(7, WINDOW_ATLAS_COLS, WINDOW_ATLAS_ROWS))
        for x, s in ((x0, -1), (x1, 1)):
            mb.add_face([(x, y0, h), (x, y1, h), (x, y1, h + 2.6)], brick, normal=(s, 0, 0))
    mb.add_cylinder((x1 - 4.0, D - 5.0, 0), 1.2, 26.0, 12, brick, radius_top=0.85, cap_top=False, uv_wrap=2.4)
    mb.add_cylinder((x1 - 4.0, D - 5.0, 25.6), 0.95, 0.6, 12, "M_Iron", cap_top=False)
    return mb


def build_pier_shed(spec):
    """Long, low arched-roof pier shed with corrugated walls and cargo doors."""
    mb = MeshBuilder(spec["id"])
    mb.shade_fn = _ground_ao
    W, D = spec["width"], spec["depth"]
    h = 7.0
    x0, x1 = -W * 0.5, W * 0.5
    mb.add_box((x0, 0, 0), (x1, D, h), "M_Shutter_Green", skip=("nz", "pz"))
    seg = 8
    prev = None
    for i in range(seg + 1):
        a = math.pi * i / seg
        x = -math.cos(a) * W * 0.5
        z = h + math.sin(a) * W * 0.18
        if prev is not None:
            mb.add_face([(prev[0], 0, prev[1]), (x, 0, z), (x, D, z), (prev[0], D, prev[1])], "M_Roof_Silver",
                        normal=(x + prev[0], 0, 1))
            for y, s in ((0.0, -1), (D, 1)):
                mb.add_face([(prev[0], y, h), (x, y, h), (x, y, z), (prev[0], y, prev[1])], "M_Shutter_Green",
                            normal=(0, s, 0))
        prev = (x, z)
    side = Facade(mb, (x1, 0, 0), (0, 1, 0), D, h)
    n = int(D / 14)
    for i in range(n):
        c = D * (i + 0.5) / n
        side.quad(c - 2.5, c + 2.5, 0.02, 5.0, 0.02, "M_Door")
    front = Facade(mb, (x0, 0, 0), (1, 0, 0), W, h)
    front.box(W * 0.1, W * 0.9, h - 1.6, h - 0.4, 0, 0.12, "M_Sign_White")
    return mb


# ---------------------------------------------------------------------------
# Family estates: an Italianate villa that grows with the mansion level.
# Same conventions (front at y = 0 facing -Y, depth +Y, origin front-centre).
# ---------------------------------------------------------------------------
def _villa_block(mb, rng, x0, x1, y0, y1, floors, wall, roof, shutters=True, hip=True, fh=3.6, base=0.8):
    W, D = x1 - x0, y1 - y0
    H = base + floors * fh
    mb.add_box((x0 - 0.15, y0 - 0.15, 0), (x1 + 0.15, y1 + 0.15, base), "M_Stone", skip=("nz",))
    mb.add_box((x0, y0, base), (x1, y1, H), wall, skip=("nz", "pz") if hip else ("nz",),
               mats={"pz": "M_Roof_Gravel"})
    for face, (o, r, length) in {"front": ((x0, y0, 0), (1, 0, 0), W), "back": ((x1, y1, 0), (-1, 0, 0), W),
                                 "left": ((x0, y1, 0), (0, -1, 0), D), "right": ((x1, y0, 0), (0, 1, 0), D)}.items():
        f = Facade(mb, o, r, length, H)
        n = max(1, int(length / 3.4))
        for k in range(floors):
            z = base + k * fh
            for i in range(n):
                c = length * (i + 0.5) / n
                _window(f, c - 0.6, c + 0.6, z + 0.9, z + 2.9, "M_Frame_White", rng, 0.2)
                if shutters and face in ("front", "back"):
                    for sgn in (-1, 1):
                        f.box(c + sgn * 0.62 - (0.45 if sgn < 0 else 0), c + sgn * 0.62 + (0.45 if sgn > 0 else 0),
                              z + 0.9, z + 2.9, 0.0, 0.06, "M_Shutter_Green")
        f.box(0, length, base + fh - 0.2, base + fh, 0, 0.15, "M_Cornice_Cream")
    # Bracketed eaves
    mb.add_box((x0 - 0.6, y0 - 0.6, H), (x1 + 0.6, y1 + 0.6, H + 0.35), "M_Cornice_Cream")
    if hip:
        _hip(mb, x0 - 0.3, x1 + 0.3, y0 - 0.3, y1 + 0.3, H + 0.35, min(W, D) * 0.22, roof)
    else:
        for sx in (x0, x1 - 0.25):
            mb.add_box((sx, y0, H + 0.35), (sx + 0.25, y1, H + 1.3), "M_Cornice_Cream")
        mb.add_box((x0, y0, H + 0.35), (x1, y0 + 0.25, H + 1.3), "M_Cornice_Cream")
    return H


def build_mansion(spec):
    level = spec.get("level", 1)
    rng = random.Random(spec["id"])
    mb = MeshBuilder(spec["id"])
    mb.shade_fn = _ground_ao
    wall, roof = "M_Stucco", "M_Roof_Terracotta"
    W, D = 30.0, 18.0
    x0, x1 = -W * 0.5, W * 0.5
    H = _villa_block(mb, rng, x0, x1, 0.0, D, 2, wall, roof)
    # Portico with columns, pediment and a balcony above.
    pw = 10.0
    mb.add_box((-pw * 0.5, -5.0, 0), (pw * 0.5, 0, 0.8), "M_Stone", skip=("nz",))
    for i in range(4):
        px = -pw * 0.5 + 0.7 + (pw - 1.4) * i / 3
        mb.add_cylinder((px, -4.3, 0.8), 0.32, 3.6, 10, "M_Stucco", cap_top=False)
    mb.add_box((-pw * 0.5 - 0.3, -5.1, 4.4), (pw * 0.5 + 0.3, 0, 5.0), "M_Cornice_Cream")
    for i in range(9):
        bx = -pw * 0.5 + 0.4 + (pw - 0.8) * i / 8
        mb.add_box((bx - 0.07, -5.0, 5.0), (bx + 0.07, -4.86, 5.8), "M_Cornice_Cream", skip=("nz",))
    mb.add_box((-pw * 0.5, -5.05, 5.75), (pw * 0.5, -4.8, 5.9), "M_Cornice_Cream")
    # Front steps
    for k in range(3):
        mb.add_box((-3.0, -6.6 + k * 0.5, 0), (3.0, -5.0, 0.27 * (k + 1)), "M_Stone", skip=("nz",))
    # Chimneys
    for cx in (x0 + 3.0, x1 - 3.8):
        mb.add_box((cx, D * 0.55, H), (cx + 0.9, D * 0.55 + 0.9, H + 5.4), "M_Brick_Red", skip=("nz",),
                   mats={"pz": "M_Tarpaper"})
    if level >= 2:
        # Two-storey wings with roof terraces and balustrades.
        for sgn in (-1, 1):
            wx0, wx1 = (x0 - 14.0, x0 - 0.4) if sgn < 0 else (x1 + 0.4, x1 + 14.0)
            _villa_block(mb, rng, wx0, wx1, 2.0, 16.0, 2, wall, roof, hip=False)
    if level >= 3:
        # Belvedere tower and rear loggia.
        _villa_block(mb, rng, -3.4, 3.4, 5.8, 12.6, 2, wall, roof, shutters=False, base=H + 0.35)
        for i in range(6):
            lx = x0 + 2.0 + (W - 4.0) * i / 5
            mb.add_cylinder((lx, D + 3.6, 0.8), 0.28, 3.6, 8, "M_Stucco", cap_top=False)
        mb.add_box((x0 + 1.4, D, 0), (x1 - 1.4, D + 4.2, 0.8), "M_Stone", skip=("nz",))
        mb.add_box((x0 + 1.4, D, 4.4), (x1 - 1.4, D + 4.3, 4.9), "M_Cornice_Cream")
    return mb


def build_estate_gatehouse(spec):
    """Gate: two stone piers with lamps, wrought-iron gates, a guard lodge."""
    mb = MeshBuilder(spec["id"])
    mb.shade_fn = _ground_ao
    for sx in (-4.6, 3.4):
        mb.add_box((sx, -0.6, 0), (sx + 1.2, 0.6, 3.4), "M_Stone", skip=("nz",))
        mb.add_box((sx - 0.15, -0.75, 3.4), (sx + 1.35, 0.75, 3.7), "M_Cornice_Cream")
        mb.add_cylinder((sx + 0.6, 0, 3.7), 0.22, 0.6, 8, "M_Iron")
    for i in range(14):
        gx = -3.3 + i * 0.5
        mb.add_box((gx - 0.03, -0.03, 0.1), (gx + 0.03, 0.03, 2.6 + 0.3 * math.sin(i / 13 * math.pi)), "M_Iron")
    for z in (0.5, 2.2):
        mb.add_box((-3.4, -0.04, z), (3.4, 0.04, z + 0.08), "M_Iron")
    mb.add_box((5.4, 1.0, 0), (9.4, 5.0, 3.2), "M_Stucco", skip=("nz",))
    _hip(mb, 5.1, 9.7, 0.7, 5.3, 3.2, 1.4, "M_Roof_Terracotta")
    f = Facade(mb, (5.4, 1.0, 0), (1, 0, 0), 4.0, 3.2)
    f.quad(0.6, 1.6, 0.0, 2.3, -0.05, "M_Door")
    _window(f, 2.2, 3.4, 1.0, 2.3, "M_Frame_White", random.Random(3), 0.15)
    return mb


def build_estate_wall(spec):
    """20 m of stone boundary wall with piers and coping (origin at centre)."""
    mb = MeshBuilder(spec["id"])
    mb.add_box((-10, -0.3, 0), (10, 0.3, 2.2), "M_Stone", skip=("nz",))
    mb.add_box((-10, -0.42, 2.2), (10, 0.42, 2.4), "M_Cornice_Cream")
    for px in (-10.0, 0.0):
        mb.add_box((px - 0.5, -0.5, 0), (px + 0.5, 0.5, 2.7), "M_Stone", skip=("nz",))
    return mb


def build_estate_garage(spec):
    mb = MeshBuilder(spec["id"])
    mb.shade_fn = _ground_ao
    W, D, H = 15.0, 8.0, 4.4
    mb.add_box((-W * 0.5, 0, 0), (W * 0.5, D, H), "M_Stucco", skip=("nz",))
    _hip(mb, -W * 0.5 - 0.4, W * 0.5 + 0.4, -0.4, D + 0.4, H, 2.0, "M_Roof_Terracotta")
    f = Facade(mb, (-W * 0.5, 0, 0), (1, 0, 0), W, H)
    for i in range(3):
        c = W * (i + 0.5) / 3
        f.quad(c - 1.9, c + 1.9, 0.0, 3.2, -0.08, "M_Shutter_Green")
    return mb


def build_fountain(spec):
    mb = MeshBuilder(spec["id"])
    mb.add_cylinder((0, 0, 0), 3.2, 0.7, 16, "M_Stone", cap_top=False)
    mb.add_cylinder((0, 0, 0.55), 3.0, 0.02, 16, "M_FountainWater")
    mb.add_cylinder((0, 0, 0), 0.5, 2.2, 10, "M_Stone")
    mb.add_cylinder((0, 0, 2.2), 1.3, 0.3, 12, "M_Stone")
    mb.add_cylinder((0, 0, 2.5), 0.25, 1.0, 8, "M_Stone")
    return mb

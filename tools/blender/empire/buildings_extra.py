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


def build_tower(spec):
    """Modular mid-century tower: a stone or brick podium with shopfronts and a
    lobby, a shaft dressed in a tileable facade (curtain wall, limestone office
    or brick apartments; one tile = 4 bays x 2 floors so windows land on
    floors), stepped setbacks with roof terraces, copings and a plant room.
    A few hundred triangles; the detail lives in the shared facade textures.

    spec: width, depth (multiples of 1.8 m), floors, style (curtain | office |
    bricktower), setbacks [[floor, inset_m], ...], podium (material)."""
    mb = MeshBuilder(spec["id"])
    mb.shade_fn = _ground_ao
    W, D = spec["width"], spec["depth"]
    style = spec.get("style", "curtain")
    facade = {"curtain": "M_Facade_Curtain", "office": "M_Facade_Office", "bricktower": "M_Facade_BrickTower"}[style]
    podium_mat = spec.get("podium", "M_Stone" if style != "bricktower" else "M_Brick_Tan")
    coping = "M_MetalGalv" if style == "curtain" else "M_Stone"
    rng = random.Random(spec["id"])
    fh = 3.6
    podium_h = 2 * fh
    x0, x1 = -W * 0.5, W * 0.5
    # Podium: shopfront bays between stone piers, lobby in the middle bay.
    mb.add_box((x0, 0.0, 0.0), (x1, D, podium_h), podium_mat, skip=("nz",))
    f = Facade(mb, (x0, 0.0, 0.0), (1, 0, 0), W, podium_h)
    bays = max(3, int(W / 6.5))
    bay_w = W / bays
    for i in range(bays):
        u0, u1 = i * bay_w + 0.5, (i + 1) * bay_w - 0.5
        if i == bays // 2:
            f.quad(u0 + 0.8, u1 - 0.8, 0.0, 3.6, 0.03, "M_ShopGlass", atlas_uv(3, 2, 2))
            f.box(u0 + 0.4, u1 - 0.4, 3.6, 4.1, 0.0, 1.6, coping)  # lobby canopy
        else:
            f.quad(u0, u1, 0.3, 4.2, 0.03, "M_ShopGlass", atlas_uv(rng.randrange(3), 2, 2))
            f.box(u0, u1, 4.2, 4.9, 0.0, 0.12, "M_Sign_Black")
    f.box(0.0, W, podium_h - 0.5, podium_h, 0.0, 0.3, coping)
    # Shaft with setbacks.
    inset0 = 0.0 if style == "bricktower" else 1.8
    steps = [[0, inset0]] + [list(s) for s in spec.get("setbacks", [])]
    floors = spec["floors"]
    for k, (start, inset) in enumerate(steps):
        end = steps[k + 1][0] if k + 1 < len(steps) else floors
        z0 = podium_h + start * fh
        z1 = podium_h + end * fh
        sx0, sx1 = x0 + inset, x1 - inset
        sy0, sy1 = inset, D - inset * (0.6 if k else 0.0)
        mb.add_box((sx0, sy0, z0), (sx1, sy1, z1), facade, skip=("nz",), mats={"pz": "M_Roof_Tar"})
        mb.add_box((sx0 - 0.25, sy0 - 0.25, z1), (sx1 + 0.25, sy1 + 0.25, z1 + 0.6), coping, skip=("nz",),
                   mats={"pz": "M_Roof_Tar"})
        top = (sx0, sx1, sy0, sy1, z1 + 0.6)
    # Plant room and (for apartments) a timber water tank on the roof.
    sx0, sx1, sy0, sy1, zt = top
    pw, pd = (sx1 - sx0) * 0.4, (sy1 - sy0) * 0.4
    cx, cy = (sx0 + sx1) * 0.5, (sy0 + sy1) * 0.5 + (sy1 - sy0) * 0.12
    mb.add_box((cx - pw * 0.5, cy - pd * 0.5, zt), (cx + pw * 0.5, cy + pd * 0.5, zt + 4.2),
               "M_Brick_Tan" if style == "bricktower" else "M_Concrete", skip=("nz",), mats={"pz": "M_Roof_Tar"})
    if style == "bricktower":
        mb.add_cylinder((sx0 + 3.0, sy1 - 3.0, zt + 2.5), 1.8, 3.4, 10, "M_Wood", uv_wrap=2.4)
        for dx, dy in ((-1.2, -1.2), (1.2, -1.2), (1.2, 1.2), (-1.2, 1.2)):
            mb.add_box((sx0 + 3.0 + dx - 0.1, sy1 - 3.0 + dy - 0.1, zt), (sx0 + 3.0 + dx + 0.1, sy1 - 3.0 + dy + 0.1, zt + 2.5),
                       "M_Iron", skip=("nz", "pz"))
    else:
        for i in range(3):
            ux = cx - pw * 0.5 - 2.5 - i * 2.2
            mb.add_box((ux, cy - 0.8, zt), (ux + 1.6, cy + 0.8, zt + 1.4), "M_AC_Unit", skip=("nz",))
    return mb

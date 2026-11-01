"""Street furniture: lamps, traffic signals, hydrants, mailboxes, trees, bins.
Origins at ground level; front faces -Y.
"""
import math
import random

from mathutils import Matrix, Vector

from .geometry import MeshBuilder


def build_street_lamp():
    """Tapered pole with a curved arm and cobra-head luminaire, 8.5 m."""
    mb = MeshBuilder("street_lamp")
    mb.add_cylinder((0, 0, 0), 0.16, 0.6, 8, "M_PoleGreen", cap_top=True)
    mb.add_cylinder((0, 0, 0.6), 0.1, 7.6, 8, "M_PoleGreen", radius_top=0.06, cap_top=True)
    # Arm: short segments curving out over the roadway (toward -Y)
    pts = [Vector((0, -i * 0.38, 7.9 + 0.55 * math.sin(i / 6 * math.pi * 0.5))) for i in range(7)]
    for a, b in zip(pts[:-1], pts[1:]):
        d = b - a
        length = d.length
        rot = d.to_track_quat("Z", "Y").to_matrix().to_4x4()
        mb.add_cylinder((0, 0, 0), 0.045, length, 6, "M_PoleGreen", cap_top=False, matrix=Matrix.Translation(a) @ rot)
    head = pts[-1] + Vector((0, -0.45, -0.05))
    mb.add_box((head.x - 0.22, head.y - 0.55, head.z - 0.12), (head.x + 0.22, head.y + 0.4, head.z + 0.08),
               "M_PoleGreen")
    mb.add_box((head.x - 0.18, head.y - 0.5, head.z - 0.16), (head.x + 0.18, head.y + 0.32, head.z - 0.12),
               "M_LampGlass")
    return mb


def build_traffic_signal():
    """Corner signal post with two heads (one per axis). Lens materials are
    shared per axis so Godot animates all intersections by swapping emission."""
    mb = MeshBuilder("traffic_signal")
    mb.add_cylinder((0, 0, 0), 0.09, 4.2, 8, "M_PoleGreen", cap_top=True)
    for axis, rot in (("ns", 0.0), ("ew", 90.0)):
        m = Matrix.Rotation(math.radians(rot), 4, "Z")
        mb.add_box((-0.17, -0.12, 3.0), (0.17, 0.12, 4.0), "M_SignalHousing", matrix=m)
        mats = ["M_SignalRed", "M_SignalAmber", "M_SignalGreen"]
        for i, mat in enumerate(mats):
            z = 3.82 - i * 0.31
            lens = mat if axis == "ns" else mat + "_EW"
            mb.add_box((-0.1, -0.135, z - 0.1), (0.1, -0.12, z + 0.1), lens, matrix=m)
            mb.add_box((-0.12, -0.2, z + 0.1), (0.12, -0.12, z + 0.13), "M_SignalHousing", matrix=m)
    return mb


def build_hydrant():
    mb = MeshBuilder("fire_hydrant")
    mb.add_cylinder((0, 0, 0), 0.16, 0.08, 10, "M_HydrantRed", cap_top=True)
    mb.add_cylinder((0, 0, 0.08), 0.12, 0.55, 10, "M_HydrantRed", cap_top=False)
    mb.add_cylinder((0, 0, 0.63), 0.14, 0.06, 10, "M_HydrantRed", cap_top=False)
    mb.add_cylinder((0, 0, 0.69), 0.12, 0.14, 10, "M_HydrantRed", radius_top=0.04, cap_top=True)
    rot = Matrix.Rotation(math.radians(90), 4, "X")
    for x in (-1, 1):
        m = Matrix.Translation((x * 0.12, 0, 0.45)) @ Matrix.Rotation(math.radians(90 * x), 4, "Y")
        mb.add_cylinder((0, 0, 0), 0.05, 0.08, 8, "M_MetalGalv", cap_top=True, matrix=m)
    m = Matrix.Translation((0, -0.12, 0.4)) @ rot
    mb.add_cylinder((0, 0, 0), 0.07, 0.1, 8, "M_MetalGalv", cap_top=True, matrix=m)
    return mb


def build_mailbox():
    mb = MeshBuilder("mailbox")
    for x in (-0.2, 0.2):
        for y in (-0.18, 0.18):
            mb.add_box((x - 0.03, y - 0.03, 0), (x + 0.03, y + 0.03, 0.3), "M_MailBlue")
    mb.add_box((-0.26, -0.24, 0.3), (0.26, 0.24, 1.05), "M_MailBlue")
    rot = Matrix.Translation((0, 0.24, 1.05)) @ Matrix.Rotation(math.radians(90), 4, "X")  # domed top
    mb.add_cylinder((0, 0, 0), 0.26, 0.48, 10, "M_MailBlue", cap_top=True, cap_bottom=True, matrix=rot)
    mb.add_box((-0.16, -0.25, 1.0), (0.16, -0.24, 1.08), "M_MetalGalv")
    return mb


def build_trash_can():
    mb = MeshBuilder("trash_can")
    mb.add_cylinder((0, 0, 0), 0.26, 0.9, 10, "M_TrashWire", radius_top=0.3, cap_top=False, cap_bottom=True)
    mb.add_cylinder((0, 0, 0.8), 0.24, 0.05, 10, "M_Sign_White", cap_top=True)
    return mb


def build_newspaper_box():
    mb = MeshBuilder("newspaper_box")
    mb.add_box((-0.25, -0.22, 0), (0.25, 0.22, 0.3), "M_Iron")
    mb.add_box((-0.25, -0.22, 0.3), (0.25, 0.22, 1.0), "M_PaperBox")
    mb.add_box((-0.2, -0.225, 0.55), (0.2, -0.22, 0.9), "M_CarGlass")
    return mb


def build_tree(seed=3, name="tree"):
    """Street tree (London plane): branching trunk and a canopy of many small
    leaf clusters, shaded darker toward the inside and underside."""
    rng = random.Random(seed)
    mb = MeshBuilder(name)
    mb.add_cylinder((0, 0, 0), 0.15, 3.0, 7, "M_Bark", radius_top=0.1, cap_top=False)
    centre = Vector((0, 0, 5.2))
    for i in range(4):
        a = i * 1.57 + rng.random() * 0.6
        d = Vector((math.cos(a) * 0.7, math.sin(a) * 0.7, 1.0)).normalized()
        rot = d.to_track_quat("Z", "Y").to_matrix().to_4x4()
        mb.add_cylinder((0, 0, 0), 0.06, 2.2, 5, "M_Bark", radius_top=0.025, cap_top=False,
                        matrix=Matrix.Translation((0, 0, 2.8)) @ rot)
    canopy_r = 2.3 + rng.random() * 0.4

    def leaf_shade(p, n):
        rel = p - centre
        up = max(0.0, min(1.0, (rel.z + canopy_r) / (2 * canopy_r)))
        outward = max(0.0, n.dot(rel.normalized())) if rel.length > 0.01 else 0.5
        return 0.45 + 0.35 * up + 0.2 * outward

    mb.shade_fn = leaf_shade
    golden = math.pi * (3 - math.sqrt(5))
    count = 13
    for i in range(count):
        y = 1 - (i + 0.5) / count * 1.6
        rad = math.sqrt(max(0.0, 1 - y * y))
        th = golden * i + rng.random() * 0.4
        c = centre + Vector((math.cos(th) * rad, math.sin(th) * rad, y * 0.75)) * canopy_r * 0.72
        _blob(mb, c, 0.95 + rng.random() * 0.45, rng, levels=1)
    _blob(mb, centre, canopy_r * 0.7, rng, levels=1)
    mb.shade_fn = None
    # Tree pit guard
    for (x0, y0, x1, y1) in ((-0.75, -0.75, 0.75, -0.7), (-0.75, 0.7, 0.75, 0.75), (-0.75, -0.75, -0.7, 0.75),
                             (0.7, -0.75, 0.75, 0.75)):
        mb.add_box((x0, y0, 0.0), (x1, y1, 0.35), "M_Iron")
    return mb


def _blob(mb, c, r, rng, levels=2, mat="M_Foliage"):
    """Icosphere-like blob (subdivided octahedron) with noise displacement."""
    verts = [Vector(v) for v in ((1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1))]
    faces = [(0, 2, 4), (2, 1, 4), (1, 3, 4), (3, 0, 4), (2, 0, 5), (1, 2, 5), (3, 1, 5), (0, 3, 5)]
    for _ in range(levels):
        cache = {}
        new_faces = []

        def mid(a, b):
            key = (min(a, b), max(a, b))
            if key not in cache:
                verts.append(((verts[a] + verts[b]) * 0.5).normalized())
                cache[key] = len(verts) - 1
            return cache[key]
        for a, b, cc in faces:
            ab, bc, ca = mid(a, b), mid(b, cc), mid(cc, a)
            new_faces += [(a, ab, ca), (b, bc, ab), (cc, ca, bc), (ab, bc, ca)]
        faces = new_faces
    disp = [1.0 + (rng.random() - 0.5) * 0.35 for _ in verts]
    pts = [c + Vector((v.x, v.y, v.z * 0.78)) * r * disp[i] for i, v in enumerate(verts)]
    for f in faces:
        p = [pts[i] for i in f]
        n = sum(((pts[i] - c) for i in f), Vector())
        mb.add_face(p, mat, normal=n, smooth=True)


def build_subway_entrance():
    """IRT-style stair entrance: iron railing enclosure, lamp globes, sign."""
    mb = MeshBuilder("subway_entrance")
    L, Wd = 4.6, 1.9
    mb.add_face([(-Wd / 2, -L / 2, 0.02), (Wd / 2, -L / 2, 0.02), (Wd / 2, L / 2 - 0.4, 0.02),
                 (-Wd / 2, L / 2 - 0.4, 0.02)], "M_Tarpaper", normal=(0, 0, 1), shade=0.25)
    for x in (-Wd / 2, Wd / 2):
        mb.add_box((x - 0.04, -L / 2, 0), (x + 0.04, L / 2, 0.1), "M_PoleGreen")
        mb.add_box((x - 0.04, -L / 2, 1.0), (x + 0.04, L / 2, 1.06), "M_PoleGreen")
        n = 14
        for i in range(n + 1):
            y = -L / 2 + L * i / n
            mb.add_face([(x, y - 0.015, 0.1), (x, y + 0.015, 0.1), (x, y + 0.015, 1.0), (x, y - 0.015, 1.0)],
                        "M_PoleGreen", normal=(1 if x > 0 else -1, 0, 0))
    mb.add_box((-Wd / 2, L / 2 - 0.05, 0), (Wd / 2, L / 2 + 0.03, 1.06), "M_PoleGreen")
    for x in (-Wd / 2, Wd / 2):
        mb.add_cylinder((x, -L / 2, 0), 0.06, 2.4, 6, "M_PoleGreen", cap_top=False)
        mb.add_cylinder((x, -L / 2, 2.4), 0.2, 0.32, 8, "M_SubwayGlobe", radius_top=0.12)
    mb.add_box((-0.55, -L / 2 - 0.03, 1.15), (0.55, -L / 2 + 0.01, 1.5), "M_Sign_Black")
    return mb


def build_bus_stop():
    mb = MeshBuilder("bus_stop")
    for x in (-1.6, 1.6):
        mb.add_box((x - 0.04, 0.6, 0), (x + 0.04, 0.68, 2.4), "M_MetalGalv")
    mb.add_box((-1.7, -0.3, 2.4), (1.7, 0.75, 2.5), "M_MetalGalv")
    mb.add_face([(-1.6, 0.66, 0.3), (1.6, 0.66, 0.3), (1.6, 0.66, 2.3), (-1.6, 0.66, 2.3)], "M_CarGlass",
                normal=(0, -1, 0))
    mb.add_box((-1.2, 0.35, 0.45), (1.2, 0.62, 0.5), "M_Wood")
    mb.add_cylinder((2.2, 0.0, 0), 0.04, 2.8, 6, "M_MetalGalv", cap_top=False)
    mb.add_box((2.0, -0.03, 2.3), (2.4, 0.03, 2.75), "M_MailBlue")
    return mb


def build_phone_booth():
    mb = MeshBuilder("phone_booth")
    mb.add_box((-0.06, -0.06, 0), (0.06, 0.06, 1.2), "M_MetalGalv")
    mb.add_box((-0.38, -0.32, 1.2), (0.38, 0.12, 2.15), "M_MetalGalv", mats={"ny": "M_Grille"})
    mb.add_box((-0.42, -0.36, 2.15), (0.42, 0.16, 2.3), "M_MailBlue")
    mb.add_box((-0.18, -0.33, 1.45), (0.18, -0.3, 1.9), "M_Iron")
    return mb


def build_newsstand():
    mb = MeshBuilder("newsstand")
    mb.add_box((-1.4, -0.9, 0), (1.4, 0.9, 2.3), "M_Shopfront_Green", skip=("nz",))
    mb.add_face([(-1.6, -1.4, 2.4), (1.6, -1.4, 2.4), (1.6, 1.0, 2.55), (-1.6, 1.0, 2.55)], "M_Shopfront_Green",
                normal=(0, 0, 1))
    mb.add_face([(-1.3, -0.91, 0.9), (1.3, -0.91, 0.9), (1.3, -0.91, 2.0), (-1.3, -0.91, 2.0)], "M_ShopGlass",
                normal=(0, -1, 0), uvs=[(0.02, 0.02), (0.48, 0.02), (0.48, 0.48), (0.02, 0.48)])
    cols = ["M_PaperBox", "M_Sign_White", "M_MailBlue", "M_Neon_Gold", "M_Sign_White", "M_PaperBox"]
    for i, c in enumerate(cols):
        x = -1.25 + i * 0.42
        mb.add_box((x, -1.15, 0.7), (x + 0.36, -0.92, 0.85), c)
    return mb


def build_trash_pile(seed=5):
    """1970s kerbside garbage: black bags and a dented can."""
    rng = random.Random(seed)
    mb = MeshBuilder("trash_pile")
    for i in range(6):
        c = Vector((rng.uniform(-0.8, 0.8), rng.uniform(-0.35, 0.35), 0.3))
        _blob_bag(mb, c, 0.32 + rng.random() * 0.12, rng)
    mb.add_cylinder((0.9, 0.2, 0), 0.27, 0.75, 10, "M_MetalGalv", cap_top=True)
    return mb


def _blob_bag(mb, c, r, rng):
    mb.shade_fn = lambda p, n: 0.55 + 0.45 * max(0.0, min(1.0, (p.z - c.z + r) / (2 * r)))
    _blob(mb, c, r, rng, levels=1, mat="M_TrashBag")
    mb.shade_fn = None


def build_parking_meter():
    mb = MeshBuilder("parking_meter")
    mb.add_cylinder((0, 0, 0), 0.04, 1.1, 6, "M_MetalGalv", cap_top=False)
    mb.add_box((-0.1, -0.08, 1.1), (0.1, 0.08, 1.42), "M_MetalGalv")
    mb.add_box((-0.07, -0.085, 1.22), (0.07, -0.08, 1.36), "M_CarGlass")
    return mb


def build_tree_far():
    """Distant tree for large stands (parks): one canopy blob and a trunk, ~40 tris."""
    rng = random.Random(7)
    mb = MeshBuilder("tree_far")
    mb.add_box((-0.15, -0.15, 0), (0.15, 0.15, 3.2), "M_Bark", skip=("nz",))
    mb.shade_fn = lambda p, n: 0.5 + 0.5 * max(0.0, min(1.0, (p.z - 2.8) / 4.6))
    _blob(mb, Vector((0, 0, 5.0)), 2.6, rng, levels=1)
    mb.shade_fn = None
    return mb

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
    rng = random.Random(seed)
    mb = MeshBuilder(name)
    mb.add_cylinder((0, 0, 0), 0.16, 2.6, 7, "M_Bark", radius_top=0.11, cap_top=False)
    for i in range(3):
        a = i * 2.1 + rng.random()
        d = Vector((math.cos(a) * 0.6, math.sin(a) * 0.6, 1.0)).normalized()
        rot = d.to_track_quat("Z", "Y").to_matrix().to_4x4()
        mb.add_cylinder((0, 0, 0), 0.07, 1.6, 6, "M_Bark", radius_top=0.035, cap_top=False,
                        matrix=Matrix.Translation((0, 0, 2.4)) @ rot)
    # Canopy: displaced low-poly blobs
    for i in range(5):
        a = i * 1.3 + rng.random()
        c = Vector((math.cos(a) * 1.0, math.sin(a) * 1.0, 4.1 + rng.random() * 0.9)) if i else Vector((0, 0, 4.9))
        r = 1.5 + rng.random() * 0.5
        _blob(mb, c, r, rng)
    # Tree pit guard
    for (x0, y0, x1, y1) in ((-0.75, -0.75, 0.75, -0.7), (-0.75, 0.7, 0.75, 0.75), (-0.75, -0.75, -0.7, 0.75),
                             (0.7, -0.75, 0.75, 0.75)):
        mb.add_box((x0, y0, 0.0), (x1, y1, 0.35), "M_Iron")
    return mb


def _blob(mb, c, r, rng):
    """Icosphere-like blob (subdivided octahedron) with noise displacement."""
    verts = [Vector(v) for v in ((1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1))]
    faces = [(0, 2, 4), (2, 1, 4), (1, 3, 4), (3, 0, 4), (2, 0, 5), (1, 2, 5), (3, 1, 5), (0, 3, 5)]
    for _ in range(2):
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
        mb.add_face(p, "M_Foliage", normal=n, smooth=True)

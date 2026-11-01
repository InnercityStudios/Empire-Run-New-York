"""Parametric 1970s New York building generator.

Every building is one mesh with ~10 material surfaces. Origin is the centre
of the front facade at sidewalk level; the front faces -Y (Godot +Z) and the
footprint extends to +Y by `depth`.
"""
import math
import os
import random

from mathutils import Vector

from .geometry import MeshBuilder, make_text, remove_object
from .textures import AWNING_SCHEMES, SHOP_ATLAS_COLS, SHOP_ATLAS_ROWS, WINDOW_ATLAS_COLS, WINDOW_ATLAS_ROWS

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
FONT_SIGN = os.path.join(ROOT, "assets", "fonts", "Oswald-Variable.ttf")
FONT_DISPLAY = os.path.join(ROOT, "assets", "fonts", "Cinzel-Variable.ttf")

GROUND_H = 4.2
FLOOR_H = 3.1
WIN_W = 0.95
WIN_H = 1.65
WIN_SILL = 0.85
WIN_DEPTH = 0.25

# Window atlas weights: plain, lace, blinds, lit, shade, red curtain, plant, grimy
WINDOW_WEIGHTS = [0.22, 0.15, 0.14, 0.08, 0.13, 0.08, 0.08, 0.12]


def atlas_uv(cell, cols, rows, inset=0.004):
    cx, cy = cell % cols, cell // cols
    u0, u1 = cx / cols + inset, (cx + 1) / cols - inset
    vt, vb = 1 - cy / rows - inset, 1 - (cy + 1) / rows + inset
    return [(u0, vb), (u1, vb), (u1, vt), (u0, vt)]


def facing_name(n):
    if n.y < -0.5:
        return "-Y"
    if n.y > 0.5:
        return "+Y"
    if n.x < -0.5:
        return "-X"
    return "+X"


class Facade:
    """A vertical wall plane addressed in local (u across, v up, o outward)."""

    def __init__(self, mb, origin, right, width, height):
        self.mb = mb
        self.O = Vector(origin)
        self.R = Vector(right).normalized()
        self.Z = Vector((0, 0, 1))
        self.N = self.R.cross(self.Z)
        self.width = width
        self.height = height

    def P(self, u, v, o=0.0):
        return self.O + self.R * u + self.Z * v + self.N * o

    def nvec(self, nu, nv, no):
        return self.R * nu + self.Z * nv + self.N * no

    def face(self, pts, mat, n, uvs=None, shade=None):
        self.mb.add_face([self.P(*p) for p in pts], mat, uvs=uvs, normal=self.nvec(*n), shade=shade)

    def quad(self, u0, u1, v0, v1, o, mat, uvs=None, shade=None):
        self.face([(u0, v0, o), (u1, v0, o), (u1, v1, o), (u0, v1, o)], mat, (0, 0, 1), uvs, shade)

    def box(self, u0, u1, v0, v1, o0, o1, mat, skip_back=True, shade=None, bottom=False):
        pts = [self.P(u, v, o) for u in (u0, u1) for v in (v0, v1) for o in (o0, o1)]
        mn = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
        mx = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
        skip = ()
        if skip_back and o0 <= 0.0:
            # The face against the wall is never visible.
            back = -self.N
            skip = ({(-1, 0): "nx", (1, 0): "px"}.get((round(back.x), round(back.y))) or
                    {(0, -1): "ny", (0, 1): "py"}.get((round(back.x), round(back.y))),)
        if not bottom and v0 > 0.05:
            skip = tuple(s for s in skip if s) + ("nz",)
        prev = self.mb.shade
        if shade is not None:
            self.mb.shade = shade
        self.mb.add_box(mn, mx, mat, skip=skip)
        self.mb.shade = prev

    def text(self, text, font, u, v, w, h, o, mat, facing=None):
        obj = make_text(text, font, w, h, self.P(u, v, o), facing or facing_name(self.N))
        self.mb.add_bmesh_object(obj, mat)
        remove_object(obj)

    def wall(self, openings, mat, reveal_mat=None):
        """Wall quad with rectangular openings (u0, u1, v0, v1, depth)."""
        reveal_mat = reveal_mat or mat
        us = sorted({0.0, self.width, *[o[0] for o in openings], *[o[1] for o in openings]})
        vs = sorted({0.0, self.height, *[o[2] for o in openings], *[o[3] for o in openings]})
        for j in range(len(vs) - 1):
            v0, v1 = vs[j], vs[j + 1]
            if v1 - v0 < 1e-4:
                continue
            start = None
            for i in range(len(us) - 1):
                cu, cv = (us[i] + us[i + 1]) * 0.5, (v0 + v1) * 0.5
                inside = any(o[0] < cu < o[1] and o[2] < cv < o[3] for o in openings)
                if not inside and start is None:
                    start = us[i]
                elif inside and start is not None:
                    self.quad(start, us[i], v0, v1, 0.0, mat)
                    start = None
            if start is not None:
                self.quad(start, us[-1], v0, v1, 0.0, mat)
        for (u0, u1, v0, v1, d) in openings:
            if v0 > 1e-4:
                self.face([(u0, v0, 0), (u1, v0, 0), (u1, v0, -d), (u0, v0, -d)], reveal_mat, (0, 1, 0), shade=0.8)
            self.face([(u0, v1, 0), (u1, v1, 0), (u1, v1, -d), (u0, v1, -d)], reveal_mat, (0, -1, 0), shade=0.45)
            self.face([(u0, v0, 0), (u0, v1, 0), (u0, v1, -d), (u0, v0, -d)], reveal_mat, (1, 0, 0), shade=0.62)
            self.face([(u1, v0, 0), (u1, v1, 0), (u1, v1, -d), (u1, v0, -d)], reveal_mat, (-1, 0, 0), shade=0.62)


class BuildingGenerator:
    def __init__(self, spec):
        self.s = spec
        self.rng = random.Random(spec.get("seed", hash(spec["id"]) & 0xFFFF))
        self.mb = MeshBuilder(spec["id"])
        self.W = spec["width"]
        self.D = spec.get("depth", 20.0)
        self.floors = spec["floors"]
        self.gfh = spec.get("ground_h", GROUND_H)
        self.fh = spec.get("floor_h", FLOOR_H)
        self.top = self.gfh + self.floors * self.fh
        self.cornice = spec.get("cornice", "bracket")
        self.crown = 0.45 if self.cornice == "bracket" else 0.25
        self.Hb = self.top + self.crown
        self.brick = spec["brick"]
        self.frame = spec.get("frame", "M_Frame_White")
        self.z0 = spec.get("z0", 0.0)
        # Architectural style (deterministic per building id)
        self.lintel = spec.get("lintel", self.rng.choice(["flat", "keystone", "keystone", "hood", "soldier"]))
        self.quoins = spec.get("quoins", self.rng.random() < 0.35)
        self.belt = spec.get("belt", self.rng.random() < 0.6)
        self.mb.shade_fn = self._occlusion

    def _occlusion(self, p, n):
        """Cheap baked AO: grime and bounce-light loss near the pavement, soot
        under the cornice, darker undersides."""
        k = 1.0
        if abs(n.z) < 0.5:
            k *= 0.68 + 0.32 * min(1.0, max(0.0, (p.z + self.z0) / 2.4))
            if self.top - 1.2 < p.z < self.top:
                k *= 0.86
        elif n.z < -0.5:
            k *= 0.7
        return k

    # -- helpers -----------------------------------------------------------------
    def window_variant(self):
        r = self.rng.random()
        acc = 0.0
        for i, w in enumerate(WINDOW_WEIGHTS):
            acc += w
            if r <= acc:
                return i
        return 0

    def window_columns(self, width, margin=0.9, spacing=2.05):
        n = max(1, int(round((width - 2 * margin) / spacing)) + 1)
        if n == 1:
            return [width * 0.5]
        span = width - 2 * margin - WIN_W
        return [margin + WIN_W * 0.5 + span * i / (n - 1) for i in range(n)]

    def upper_window_openings(self, f, cols, w=WIN_W, h=WIN_H):
        ops = []
        for k in range(self.floors):
            z = self.gfh + k * self.fh
            for c in cols:
                ops.append((c - w * 0.5, c + w * 0.5, z + WIN_SILL, z + WIN_SILL + h, WIN_DEPTH))
        return ops

    def dress_windows(self, f, ops, ac_chance=0.1, grimy=False):
        for (u0, u1, v0, v1, d) in ops:
            var = 7 if grimy else self.window_variant()
            glass_o = -d + 0.04
            f.quad(u0, u1, v0, v1, glass_o, "M_Window", atlas_uv(var, WINDOW_ATLAS_COLS, WINDOW_ATLAS_ROWS),
                   shade=0.92)
            # Frame and meeting rail: flat faces over the textured sash (detail
            # lives in the texture, not in triangles).
            fw = 0.07
            fr = self.frame
            o = glass_o + 0.015
            f.quad(u0, u1, v0, v0 + fw, o, fr, shade=0.85)
            f.quad(u0, u1, v1 - fw, v1, o, fr, shade=0.7)
            f.quad(u0, u0 + fw, v0 + fw, v1 - fw, o, fr, shade=0.8)
            f.quad(u1 - fw, u1, v0 + fw, v1 - fw, o, fr, shade=0.8)
            mid = (v0 + v1) * 0.5
            f.quad(u0 + fw, u1 - fw, mid - 0.03, mid + 0.03, o + 0.01, fr)
            f.box(u0 - 0.08, u1 + 0.08, v0 - 0.08, v0, -0.03, 0.09, "M_Stone")
            self._lintel(f, u0, u1, v1)
            if self.rng.random() < ac_chance:
                c = (u0 + u1) * 0.5
                f.box(c - 0.31, c + 0.31, v0 + 0.02, v0 + 0.42, -0.14, 0.34, "M_AC_Unit")
                f.box(c - 0.26, c + 0.26, v0 + 0.08, v0 + 0.36, 0.34, 0.345, "M_Grille")

    def _lintel(self, f, u0, u1, v1):
        style = self.lintel
        if style == "keystone":
            f.box(u0 - 0.1, u1 + 0.1, v1, v1 + 0.2, -0.02, 0.04, "M_Stone")
            c = (u0 + u1) * 0.5
            f.box(c - 0.1, c + 0.1, v1 - 0.03, v1 + 0.3, -0.02, 0.07, "M_Stone")
        elif style == "hood":
            f.box(u0 - 0.16, u1 + 0.16, v1 + 0.05, v1 + 0.24, -0.02, 0.06, "M_Stone")
            f.box(u0 - 0.2, u1 + 0.2, v1 + 0.24, v1 + 0.32, -0.02, 0.16, "M_Stone")
            for uu in (u0 - 0.14, u1 + 0.06):
                f.box(uu, uu + 0.08, v1 - 0.2, v1 + 0.24, -0.02, 0.1, "M_Stone", shade=0.85)
        elif style == "soldier":
            # Soldier-course brick lintel, slightly proud of the wall.
            f.box(u0 - 0.06, u1 + 0.06, v1, v1 + 0.26, -0.02, 0.025, self.brick)
        else:
            f.box(u0 - 0.1, u1 + 0.1, v1, v1 + 0.2, -0.02, 0.03, "M_Stone")

    def cornice_on(self, f, start_u=0.0, end_u=None):
        end_u = f.width if end_u is None else end_u
        mat = self.s.get("cornice_mat", "M_Cornice_Dark")
        if self.cornice == "bracket":
            f.box(start_u, end_u, self.top - 0.75, self.top - 0.05, 0.0, 0.1, mat)
            f.box(start_u, end_u, self.top - 0.05, self.top + 0.12, 0.0, 0.34, mat, shade=0.8)
            f.box(start_u, end_u, self.top + 0.12, self.top + 0.3, 0.0, 0.5, mat)
            f.box(start_u, end_u, self.top + 0.3, self.top + self.crown, 0.0, 0.66, mat)
            n = max(2, int((end_u - start_u) / 1.3))
            for i in range(n + 1):
                u = start_u + 0.15 + (end_u - start_u - 0.3) * i / n
                f.box(u - 0.09, u + 0.09, self.top - 0.66, self.top - 0.05, 0.1, 0.45, mat, shade=0.82)
            # Dentil course under the crown
            u = start_u + 0.12
            while u < end_u - 0.2:
                f.box(u, u + 0.1, self.top - 0.2, self.top - 0.05, 0.1, 0.2, mat, shade=0.75)
                u += 0.32
        else:
            f.box(start_u, end_u, self.top - 0.25, self.top - 0.05, 0.0, 0.08, "M_Stone")
            f.box(start_u, end_u, self.top + self.crown - 0.12, self.top + self.crown, 0.0, 0.1, "M_Stone")

    def sign(self, f, u0, u1, v0, v1, text, board_mat, text_mat, font):
        f.box(u0, u1, v0, v1, 0.0, 0.12, board_mat)
        trim = "M_Gold_Trim" if text_mat == "M_Sign_Gold" else "M_Frame_Dark"
        f.box(u0, u1, v1 - 0.05, v1, 0.12, 0.15, trim)
        f.box(u0, u1, v0, v0 + 0.05, 0.12, 0.15, trim, shade=0.8)
        if text:
            f.text(text, font, (u0 + u1) * 0.5, (v0 + v1) * 0.5, (u1 - u0) * 0.84, (v1 - v0) * 0.62, 0.125, text_mat)

    def awning(self, f, u0, u1, v_top, scheme, depth=1.5, drop=0.9):
        rows = len(AWNING_SCHEMES)
        vt = 1 - scheme / rows - 0.01
        vb = 1 - (scheme + 1) / rows + 0.01
        su0, su1 = u0 / 2.0, u1 / 2.0
        vm = (vt + vb) * 0.5
        f.face([(u0, v_top, 0), (u1, v_top, 0), (u1, v_top - drop, depth), (u0, v_top - drop, depth)],
               "M_Awning", (0, 0.8, 0.6), uvs=[(su0, vt), (su1, vt), (su1, vb), (su0, vb)])
        f.face([(u0, v_top - drop, depth), (u1, v_top - drop, depth), (u1, v_top - drop - 0.3, depth),
                (u0, v_top - drop - 0.3, depth)], "M_Awning", (0, 0, 1),
               uvs=[(su0, vm), (su1, vm), (su1, vb), (su0, vb)])
        for u, s in ((u0, -1), (u1, 1)):
            f.face([(u, v_top, 0), (u, v_top - drop, depth), (u, v_top - drop - 0.3, depth)], "M_Awning", (s, 0, 0),
                   uvs=[(0.02, vt), (0.1, vb), (0.12, vb)])

    def blade_sign(self, f, u, v0, v1, text, board_mat, neon_mat):
        f.box(u - 0.07, u + 0.07, v0, v1, 0.2, 1.05, board_mat)
        f.box(u - 0.03, u + 0.03, v0 + (v1 - v0) * 0.5 - 0.03, v0 + (v1 - v0) * 0.5 + 0.03, 0.0, 0.2, "M_Iron")
        stacked = "\n".join(text)
        for side in (1, -1):
            facing = facing_name(f.R * side)
            obj = make_text(stacked, FONT_SIGN, 0.62, (v1 - v0) * 0.88,
                            f.P(u + side * 0.075, (v0 + v1) * 0.5, 0.625), facing)
            self.mb.add_bmesh_object(obj, neon_mat)
            remove_object(obj)

    def fire_escape(self, f, u0, u1):
        iron = "M_Iron"
        depth = 1.1
        zs = [self.gfh + k * self.fh for k in range(self.floors)]
        for k, z in enumerate(zs):
            f.box(u0, u1, z - 0.07, z, 0.0, depth, iron)
            f.box(u0, u1, z + 0.92, z + 0.97, depth - 0.04, depth, iron)
            f.box(u0, u1, z + 0.44, z + 0.47, depth - 0.03, depth, iron)
            for uu in (u0, u1 - 0.04):
                f.box(uu, uu + 0.04, z + 0.92, z + 0.97, 0.0, depth, iron)
            nb = max(2, int((u1 - u0) / 0.24))
            for i in range(nb + 1):
                uu = u0 + (u1 - u0) * i / nb
                f.quad(uu - 0.012, uu + 0.012, z, z + 0.95, depth - 0.015, iron)
            for uu, s in ((u0, -1), (u1, 1)):
                for j in range(5):
                    o = 0.05 + (depth - 0.1) * j / 4
                    f.face([(uu, z, o - 0.012), (uu, z, o + 0.012), (uu, z + 0.95, o + 0.012),
                            (uu, z + 0.95, o - 0.012)], iron, (s, 0, 0))
            if k < len(zs) - 1:
                zn = zs[k + 1]
                run = min(u1 - u0 - 0.9, 3.0)
                if k % 2 == 0:
                    us, ue = u0 + 0.3, u0 + 0.3 + run
                else:
                    us, ue = u1 - 0.3, u1 - 0.3 - run
                oa, ob = 0.2, 0.8
                steps = int(abs(ue - us) / 0.24)
                for i in range(steps):
                    t0 = (i + 0.1) / steps
                    t1 = (i + 0.7) / steps
                    ua, ub = us + (ue - us) * t0, us + (ue - us) * t1
                    va = z + (zn - z) * (i + 1) / steps
                    f.face([(ua, va, oa), (ub, va, oa), (ub, va, ob), (ua, va, ob)], iron, (0, 1, 0))
                for o in (oa, ob):
                    f.face([(us, z - 0.18, o), (ue, zn - 0.18, o), (ue, zn, o), (us, z, o)], iron, (0, 0, 1))
                f.face([(us, z + 0.9, ob), (ue, zn + 0.9, ob), (ue, zn + 0.95, ob), (us, z + 0.95, ob)], iron, (0, 0, 1))
        # Counterweighted drop ladder below the lowest platform
        z0 = zs[0]
        lu = u1 - 0.75
        for uu in (lu, lu + 0.45):
            f.box(uu, uu + 0.04, z0 - 2.3, z0, depth - 0.35, depth - 0.31, iron)
        for r in range(7):
            vv = z0 - 2.2 + r * 0.31
            f.box(lu, lu + 0.49, vv, vv + 0.03, depth - 0.34, depth - 0.32, iron)
        # Gooseneck ladder to the roof
        zt = zs[-1]
        gu = (u0 + u1) * 0.5
        for uu in (gu - 0.25, gu + 0.21):
            f.box(uu, uu + 0.04, zt, self.Hb + 0.9, depth - 0.25, depth - 0.21, iron)

    # -- ground floor variants ---------------------------------------------------------
    def ground_shop(self, f, g, width, allow_res_door=True):
        """Shopfront with optional residential entrance. Returns openings and a
        callback that dresses them after the wall is built."""
        pier = 0.45
        ops = []
        res = None
        open_h = self.gfh - 1.25
        a, b = pier, width - pier
        if allow_res_door and width >= 8.5 and g.get("res_door", True):
            if g.get("res_side", "left") == "left":
                res = (pier + 0.2, pier + 0.2 + 1.15)
                a = res[1] + 0.45
            else:
                res = (width - pier - 1.35, width - pier - 0.2)
                b = res[0] - 0.45
            ops.append((res[0], res[1], 0.0, 2.75, 0.35))
        ops.append((a, b, 0.0, open_h, 0.3))

        def dress():
            front = g.get("frontage", "M_Shopfront_Green")
            if res:
                f.quad(res[0], res[1], 0.0, 2.3, -0.35, "M_Door")
                f.quad(res[0], res[1], 2.3, 2.75, -0.35, "M_Window", atlas_uv(0, WINDOW_ATLAS_COLS, WINDOW_ATLAS_ROWS))
                f.box(res[0] - 0.12, res[1] + 0.12, 2.75, 2.97, -0.02, 0.06, "M_Stone")
                f.box(res[0] - 0.1, res[1] + 0.1, 0.0, 0.17, 0.0, 0.38, "M_Stone")
            depth = 0.3
            door_w = 1.05
            if g.get("door_side", "right") == "right":
                door = (b - 0.15 - door_w, b - 0.15)
                disp = (a, door[0] - 0.08)
            else:
                door = (a + 0.15, a + 0.15 + door_w)
                disp = (door[1] + 0.08, b)
            variant = g.get("shop_variant", 0)
            transom = open_h - 0.75
            # Panelled bulkhead
            f.box(disp[0], disp[1], 0.0, 0.55, -depth, -depth + 0.1, front)
            npan = max(1, int((disp[1] - disp[0]) / 1.2))
            for i in range(npan):
                pu0 = disp[0] + (disp[1] - disp[0]) * i / npan + 0.1
                pu1 = disp[0] + (disp[1] - disp[0]) * (i + 1) / npan - 0.1
                f.box(pu0, pu1, 0.1, 0.45, -depth + 0.1, -depth + 0.13, front, shade=0.82)
            # Display glass, transom lights and header
            f.quad(disp[0], disp[1], 0.6, transom, -depth + 0.02, "M_ShopGlass",
                   atlas_uv(variant, SHOP_ATLAS_COLS, SHOP_ATLAS_ROWS))
            f.quad(a, b, transom + 0.06, open_h - 0.12, -depth + 0.02, "M_Window",
                   atlas_uv(0, WINDOW_ATLAS_COLS, WINDOW_ATLAS_ROWS), shade=0.85)
            f.box(a, b, transom, transom + 0.06, -depth, -depth + 0.08, front)
            f.box(a, b, open_h - 0.12, open_h, -depth, -depth + 0.1, front, shade=0.7)
            nt = max(2, int((b - a) / 0.6))
            for i in range(1, nt):
                uu = a + (b - a) * i / nt
                f.box(uu - 0.02, uu + 0.02, transom + 0.06, open_h - 0.12, -depth, -depth + 0.06, front)
            nm = max(1, int((disp[1] - disp[0]) / 1.7))
            for i in range(nm + 1):
                uu = disp[0] + (disp[1] - disp[0]) * i / nm
                f.box(uu - 0.045, uu + 0.045, 0.55, transom, -depth, -depth + 0.07, front)
            f.box(disp[0], disp[1], 0.55, 0.62, -depth, -depth + 0.14, front)
            # Roll-down security gate housing; closed shops have the gate half down.
            f.box(a - 0.05, b + 0.05, open_h - 0.02, open_h + 0.28, -0.02, 0.18, "M_Iron", shade=0.85)
            if variant == 3:
                f.quad(disp[0], disp[1], transom - 1.1, open_h, -0.02 + 0.1, "M_Shutter")
            # Recessed entry: tiled floor, glazed side returns, door at the back.
            rec = depth + 0.75
            f.quad(door[0], door[1], 0.0, 2.45, -rec, "M_Door", shade=0.75)
            f.quad(door[0] + 0.15, door[1] - 0.15, 1.15, 2.2, -rec + 0.01, "M_ShopGlass",
                   atlas_uv(3, SHOP_ATLAS_COLS, SHOP_ATLAS_ROWS), shade=0.8)
            f.face([(door[0], 0.01, -depth), (door[1], 0.01, -depth), (door[1], 0.01, -rec), (door[0], 0.01, -rec)],
                   "M_Tile", (0, 1, 0), shade=0.8)
            for uu, sgn in ((door[0], 1), (door[1], -1)):
                f.face([(uu, 0, -depth), (uu, 2.45, -depth), (uu, 2.45, -rec), (uu, 0, -rec)], "M_ShopGlass",
                       (sgn, 0, 0), uvs=atlas_uv(variant, SHOP_ATLAS_COLS, SHOP_ATLAS_ROWS), shade=0.7)
            f.face([(door[0], 2.45, -depth), (door[1], 2.45, -depth), (door[1], 2.45, -rec), (door[0], 2.45, -rec)],
                   front, (0, -1, 0), shade=0.5)
            f.quad(door[0], door[1], 2.45, open_h - 0.4, -depth + 0.02, "M_ShopGlass",
                   atlas_uv(g.get("shop_variant", 0), SHOP_ATLAS_COLS, SHOP_ATLAS_ROWS))
            # Sign band and ledge
            self.sign(f, a - 0.1, b + 0.1, self.gfh - 1.17, self.gfh - 0.4, g.get("sign", ""),
                      g.get("sign_board", front), g.get("sign_text", "M_Sign_Gold"),
                      FONT_DISPLAY if g.get("font") == "display" else FONT_SIGN)
            f.box(0.0, width, self.gfh - 0.4, self.gfh - 0.2, 0.0, 0.17, "M_Stone")
            if g.get("awning") is not None:
                self.awning(f, disp[0] - 0.05, disp[1] + 0.05, open_h + 0.02, g["awning"])
            if g.get("blade"):
                bu = (res[1] + 0.25) if res and g.get("res_side", "left") == "left" else (b - 0.3)
                self.blade_sign(f, bu, self.gfh + 0.25, self.gfh + 2.15, g["blade"], "M_Sign_Black",
                                g.get("neon", "M_Neon_Red"))
            if g.get("lamps"):
                for uu in (door[0] - 0.25, door[1] + 0.25):
                    f.box(uu - 0.1, uu + 0.1, 2.1, 2.5, 0.0, 0.2, "M_Gold_Trim")
                    f.box(uu - 0.07, uu + 0.07, 2.15, 2.45, 0.2, 0.22, "M_LampGlass")
        return ops, dress

    def ground_residential(self, f, width):
        cols = self.window_columns(width)
        mid = len(cols) // 2
        ops = []
        door = None
        for i, c in enumerate(cols):
            if i == mid:
                door = (c - 0.6, c + 0.6)
                ops.append((door[0], door[1], 0.0, 2.8, 0.4))
            else:
                ops.append((c - WIN_W * 0.5, c + WIN_W * 0.5, 1.4, 1.4 + WIN_H, WIN_DEPTH))

        def dress():
            win_ops = [o for o in ops if o[2] > 0]
            self.dress_windows(f, win_ops, ac_chance=0.0)
            f.quad(door[0], door[1], 0.0, 2.35, -0.4, "M_Door")
            f.quad(door[0], door[1], 2.35, 2.8, -0.4, "M_Window", atlas_uv(3, WINDOW_ATLAS_COLS, WINDOW_ATLAS_ROWS))
            f.box(door[0] - 0.3, door[1] + 0.3, 2.8, 3.15, -0.02, 0.12, "M_Stone")
            f.box(door[0] - 0.3, door[0] - 0.05, 0.0, 2.8, -0.02, 0.1, "M_Stone")
            f.box(door[1] + 0.05, door[1] + 0.3, 0.0, 2.8, -0.02, 0.1, "M_Stone")
            for s in range(3):
                f.box(door[0] - 0.35, door[1] + 0.35, 0.0, 0.18 * (3 - s), 0.0, 0.3 * (s + 1) + 0.2, "M_Stone")
            f.box(0.0, width, 0.0, 0.9, 0.0, 0.06, "M_Stone")
            f.box(0.0, width, self.gfh - 0.3, self.gfh - 0.12, 0.0, 0.1, "M_Stone")
        return ops, dress

    def ground_garage(self, f, g, width):
        ops = []
        doors = []
        n = 2 if width >= 11 else 1
        dw = 3.4
        total = n * dw + (n - 1) * 0.8
        start = width - 0.6 - total
        for i in range(n):
            u0 = start + i * (dw + 0.8)
            doors.append((u0, u0 + dw))
            ops.append((u0, u0 + dw, 0.0, 3.5, 0.22))
        office = (0.7, 1.75)
        ops.append((office[0], office[1], 0.0, 2.5, 0.25))
        ops.append((office[1] + 0.4, min(start - 0.4, office[1] + 2.4), 1.0, 2.6, 0.18))

        def dress():
            for (u0, u1) in doors:
                f.quad(u0, u1, 0.0, 3.5, -0.22, g.get("shutter", "M_Shutter"))
                f.box(u0 - 0.15, u1 + 0.15, 3.5, 3.7, -0.02, 0.1, "M_Iron")
            f.quad(office[0], office[1], 0.0, 2.5, -0.25, "M_Door")
            w0, w1 = office[1] + 0.4, min(start - 0.4, office[1] + 2.4)
            f.quad(w0, w1, 1.0, 2.6, -0.18, "M_ShopGlass", atlas_uv(3, SHOP_ATLAS_COLS, SHOP_ATLAS_ROWS))
            self.sign(f, 0.4, width - 0.4, self.gfh - 0.75, self.gfh - 0.05, g.get("sign", ""),
                      g.get("sign_board", "M_Sign_White"), g.get("sign_text", "M_Shopfront_Red"), FONT_SIGN)
        return ops, dress

    # -- assembly ----------------------------------------------------------------------
    def facade(self, origin, right, width, ground, fire_escape=False, ac=0.1):
        f = Facade(self.mb, origin, right, width, self.Hb)
        cols = self.window_columns(width)
        ops = self.upper_window_openings(f, cols)
        gtype = ground.get("type", "shop")
        if gtype == "none":
            gops, dress = [], (lambda: None)
        elif gtype == "residential":
            gops, dress = self.ground_residential(f, width)
        elif gtype == "garage":
            gops, dress = self.ground_garage(f, ground, width)
        else:
            gops, dress = self.ground_shop(f, ground, width, allow_res_door=ground.get("res_door", True))
        f.wall(ops + gops, self.brick)
        self.dress_windows(f, ops, ac_chance=ac)
        dress()
        if gtype != "residential":
            pass
        self.cornice_on(f)
        if self.belt and gtype != "none":
            f.box(0.0, width, self.gfh + WIN_SILL - 0.18, self.gfh + WIN_SILL - 0.06, -0.02, 0.06, "M_Stone")
        if self.quoins:
            v = self.gfh
            k = 0
            while v < self.top - 0.8:
                long = 0.62 if k % 2 == 0 else 0.4
                for uu in (0.0, width - long):
                    f.box(uu, uu + long, v, v + 0.38, -0.02, 0.035, "M_Stone")
                v += 0.42
                k += 1
        if fire_escape and len(cols) >= 2:
            k = min(len(cols) - 2, self.s.get("fe_col", max(0, len(cols) // 2 - 1)))
            u0 = cols[k] - WIN_W * 0.5 - 0.35
            u1 = cols[k + 1] + WIN_W * 0.5 + 0.35
            self.fire_escape(f, u0, u1)
        return f

    def plain_wall(self, origin, right, width, height):
        f = Facade(self.mb, origin, right, width, height)
        f.quad(0.0, width, 0.0, height, 0.0, self.brick)
        return f

    def back_facade(self):
        W, D = self.W, self.D
        f = Facade(self.mb, (W * 0.5, D, 0.0), (-1, 0, 0), W, self.Hb)
        f.quad(0.0, W, 0.0, self.Hb, 0.0, self.brick)
        cols = self.window_columns(W, margin=1.0, spacing=2.4)
        for k in range(self.floors + 1):
            z = (0.9 if k == 0 else self.gfh + (k - 1) * self.fh + WIN_SILL)
            for c in cols:
                f.quad(c - 0.45, c + 0.45, z, z + 1.5, 0.012, "M_Window",
                       atlas_uv(self.window_variant(), WINDOW_ATLAS_COLS, WINDOW_ATLAS_ROWS))
                f.box(c - 0.5, c + 0.5, z - 0.08, z, 0.0, 0.05, "M_Stone")

    def roof(self):
        W, D, Hb = self.W, self.D, self.Hb
        x0, x1 = -W * 0.5, W * 0.5
        t = 0.3
        hr = Hb - 0.6
        mb = self.mb
        roof_mat = self.s.get("roof", self.rng.choice(["M_Roof_Tar", "M_Roof_Silver", "M_Roof_Silver", "M_Roof_Gravel"]))
        mb.add_face([(x0 + t, t, hr), (x1 - t, t, hr), (x1 - t, D - t, hr), (x0 + t, D - t, hr)], roof_mat,
                    normal=(0, 0, 1))
        # Parapet inner faces and coping
        inner = [(x0 + t, t), (x1 - t, t), (x1 - t, D - t), (x0 + t, D - t)]
        outer = [(x0, 0.0), (x1, 0.0), (x1, D), (x0, D)]
        for i in range(4):
            a, b = inner[i], inner[(i + 1) % 4]
            cen = Vector((0, D * 0.5, 0))
            mid = Vector(((a[0] + b[0]) * 0.5, (a[1] + b[1]) * 0.5, 0))
            mb.add_face([(a[0], a[1], hr), (b[0], b[1], hr), (b[0], b[1], Hb), (a[0], a[1], Hb)], self.brick,
                        normal=cen - mid)
            oa, ob = outer[i], outer[(i + 1) % 4]
            mb.add_face([(oa[0], oa[1], Hb), (ob[0], ob[1], Hb), (b[0], b[1], Hb), (a[0], a[1], Hb)], "M_Stone",
                        normal=(0, 0, 1))
        rng = self.rng
        # Stair bulkhead
        bx = x0 + 1.2 + rng.random() * max(0.1, W - 5.0)
        by = D * (0.45 + rng.random() * 0.3)
        mb.add_box((bx, by, hr), (bx + 2.4, by + 3.0, hr + 2.6), self.brick, skip=("nz",),
                   mats={"pz": "M_Tarpaper"})
        mb.add_face([(bx + 0.7, by - 0.01, hr), (bx + 1.6, by - 0.01, hr), (bx + 1.6, by - 0.01, hr + 2.1),
                     (bx + 0.7, by - 0.01, hr + 2.1)], "M_Door", normal=(0, -1, 0))
        # Chimneys and vents
        for _ in range(rng.randint(1, 3)):
            cx = x0 + 0.6 + rng.random() * (W - 1.6)
            cy = D - 0.9 - rng.random() * 2.0
            mb.add_box((cx, cy, hr), (cx + 0.7, cy + 0.6, hr + 1.4 + rng.random()), self.brick, skip=("nz",),
                       mats={"pz": "M_Tarpaper"})
        for _ in range(rng.randint(1, 3)):
            vx = x0 + 1.0 + rng.random() * (W - 2.0)
            vy = 2.0 + rng.random() * (D - 4.0)
            mb.add_cylinder((vx, vy, hr), 0.18, 0.7, 8, "M_MetalGalv", cap_top=True)
        # Plank walkway from the bulkhead and rooftop condensers
        if rng.random() < 0.5:
            wx = bx + 0.9
            mb.add_face([(wx, 0.8, hr + 0.04), (wx + 0.6, 0.8, hr + 0.04), (wx + 0.6, by, hr + 0.04),
                         (wx, by, hr + 0.04)], "M_Wood", normal=(0, 0, 1))
        for _ in range(rng.randint(0, 2)):
            hx = x0 + 0.8 + rng.random() * max(0.1, W - 2.8)
            hy = 1.2 + rng.random() * (D - 3.0)
            mb.add_box((hx, hy, hr), (hx + 1.2, hy + 0.9, hr + 0.85), "M_AC_Unit", skip=("nz",))
            mb.add_cylinder((hx + 0.6, hy + 0.45, hr + 0.85), 0.32, 0.03, 10, "M_Grille")
        # Mushroom-capped vent stacks
        for _ in range(rng.randint(1, 2)):
            vx = x0 + 1.0 + rng.random() * (W - 2.0)
            vy = 2.0 + rng.random() * (D - 4.0)
            mb.add_cylinder((vx, vy, hr), 0.08, 1.1, 6, "M_MetalGalv", cap_top=False)
            mb.add_cylinder((vx, vy, hr + 1.1), 0.22, 0.12, 8, "M_MetalGalv", radius_top=0.05)
        # Tar patches break up the roof surface
        for _ in range(rng.randint(1, 3)):
            px = x0 + 0.6 + rng.random() * (W - 3.0)
            py = 0.8 + rng.random() * (D - 4.0)
            pw, pd = 1.0 + rng.random() * 2.0, 1.0 + rng.random() * 2.5
            mb.add_face([(px, py, hr + 0.01), (px + pw, py, hr + 0.01), (px + pw, py + pd, hr + 0.01),
                         (px, py + pd, hr + 0.01)], "M_Tarpaper", normal=(0, 0, 1))
        # Skylight over the stairwell
        if rng.random() < 0.55:
            sx = x0 + 1.0 + rng.random() * max(0.1, W - 3.4)
            sy = D * 0.25
            mb.add_box((sx, sy, hr), (sx + 1.4, sy + 1.0, hr + 0.35), "M_Frame_Dark", skip=("nz",),
                       mats={"pz": "M_CarGlass"})
        # 1970s TV aerials
        for _ in range(rng.randint(1, 3)):
            ax = x0 + 0.8 + rng.random() * (W - 1.6)
            ay = 1.0 + rng.random() * (D - 2.0)
            mast = 2.2 + rng.random() * 1.6
            mb.add_cylinder((ax, ay, hr), 0.03, mast, 4, "M_MetalGalv", cap_top=False, smooth=False)
            for i in range(4):
                bz = hr + mast - 0.15 - i * 0.28
                half = 0.7 - i * 0.12
                mb.add_box((ax - half, ay - 0.015, bz), (ax + half, ay + 0.015, bz + 0.03), "M_MetalGalv")
        # Rooftop pigeon coop
        if rng.random() < 0.2 and W >= 9:
            cx = x0 + 1.0
            cy = D - 4.5
            mb.add_box((cx, cy, hr), (cx + 2.6, cy + 1.8, hr + 1.6), "M_Wood", skip=("nz",))
            mb.add_face([(cx - 0.1, cy - 0.1, hr + 1.6), (cx + 2.7, cy - 0.1, hr + 1.6), (cx + 2.7, cy + 1.9, hr + 1.75),
                         (cx - 0.1, cy + 1.9, hr + 1.75)], "M_Tarpaper", normal=(0, 0, 1))
            mb.add_face([(cx + 0.2, cy - 0.01, hr + 0.4), (cx + 2.4, cy - 0.01, hr + 0.4), (cx + 2.4, cy - 0.01, hr + 1.4),
                         (cx + 0.2, cy - 0.01, hr + 1.4)], "M_TrashWire", normal=(0, -1, 0))
        if self.s.get("water_tower") and not self.s.get("setback"):
            self.water_tower(x0 + W * (0.3 + rng.random() * 0.4), D * 0.62, hr)

    def water_tower(self, cx, cy, z):
        mb = self.mb
        leg_h = 3.6
        r = 1.7
        for dx in (-1.1, 1.1):
            for dy in (-1.1, 1.1):
                mb.add_box((cx + dx - 0.08, cy + dy - 0.08, z), (cx + dx + 0.08, cy + dy + 0.08, z + leg_h), "M_Iron")
        for h in (1.2, 2.6):
            mb.add_box((cx - 1.2, cy - 1.15, z + h), (cx + 1.2, cy - 1.05, z + h + 0.08), "M_Iron")
            mb.add_box((cx - 1.2, cy + 1.05, z + h), (cx + 1.2, cy + 1.15, z + h + 0.08), "M_Iron")
            mb.add_box((cx - 1.15, cy - 1.2, z + h), (cx - 1.05, cy + 1.2, z + h + 0.08), "M_Iron")
            mb.add_box((cx + 1.05, cy - 1.2, z + h), (cx + 1.15, cy + 1.2, z + h + 0.08), "M_Iron")
        mb.add_box((cx - 1.9, cy - 1.9, z + leg_h), (cx + 1.9, cy + 1.9, z + leg_h + 0.2), "M_Wood")
        tz = z + leg_h + 0.2
        mb.add_cylinder((cx, cy, tz), r, 3.4, 14, "M_Wood", cap_top=False, uv_wrap=2.0, smooth=True)
        for h in (0.4, 1.4, 2.4, 3.2):
            mb.add_cylinder((cx, cy, tz + h), r + 0.03, 0.07, 14, "M_Iron", cap_top=False, smooth=True)
        mb.add_cylinder((cx, cy, tz + 3.4), r + 0.12, 1.1, 14, "M_Tarpaper", radius_top=0.08, cap_top=False,
                        cap_bottom=True, smooth=False)
        mb.add_cylinder((cx, cy, tz + 4.5), 0.07, 0.4, 6, "M_Iron")
        # Access ladder
        for dx in (-0.2, 0.2):
            mb.add_box((cx + dx - 0.02, cy - r - 0.15, z), (cx + dx + 0.02, cy - r - 0.11, tz + 3.4), "M_Iron")

    def build(self):
        s = self.s
        W, D, Hb = self.W, self.D, self.Hb
        corner = s.get("corner")
        ground = s.get("ground", {"type": "shop"})
        self.facade((-W * 0.5, 0.0, 0.0), (1, 0, 0), W, ground, fire_escape=s.get("fire_escape", False),
                    ac=s.get("ac", 0.1))
        side_ground = dict(s.get("side_ground", {"type": "shop", "sign": "", "res_door": True}))
        if corner == "left":
            self.facade((-W * 0.5, D, 0.0), (0, -1, 0), D, side_ground, fire_escape=False, ac=s.get("ac", 0.1))
        else:
            self.plain_wall((-W * 0.5, D, 0.0), (0, -1, 0), D, Hb)
        if corner == "right":
            self.facade((W * 0.5, 0.0, 0.0), (0, 1, 0), D, side_ground, fire_escape=False, ac=s.get("ac", 0.1))
        else:
            self.plain_wall((W * 0.5, 0.0, 0.0), (0, 1, 0), D, Hb)
        self.back_facade()
        self.roof()
        if s.get("setback"):
            self._setback(s["setback"])
        return self.mb

    def _setback(self, sb):
        """Stack a narrower upper volume (elevator-building silhouette)."""
        inset = sb.get("inset", 2.5)
        up = dict(self.s)
        up.update({"id": self.s["id"] + "_upper", "width": self.W - 2 * inset, "depth": self.D - inset - 2.0,
                   "floors": sb.get("floors", 2), "ground": {"type": "none"}, "ground_h": 0.3, "corner": None,
                   "fire_escape": False, "setback": None, "quoins": False, "belt": False,
                   "z0": self.Hb - 0.6, "seed": self.rng.randint(0, 99999)})
        upper = BuildingGenerator(up)
        upper.build()
        self.mb.merge(upper.mb, (0.0, inset, self.Hb - 0.6))


def build_warehouse(spec):
    """Heavy timber-and-brick freight warehouse with a raised loading dock."""
    g = BuildingGenerator(dict(spec, cornice="simple"))
    g.fh = spec.get("floor_h", 3.8)
    g.gfh = 4.6
    g.top = g.gfh + g.floors * g.fh
    g.crown = 0.6
    g.Hb = g.top + g.crown
    W, D, Hb = g.W, g.D, g.Hb
    mb = g.mb
    f = Facade(mb, (-W * 0.5, 0.0, 0.0), (1, 0, 0), W, Hb)
    bays = max(3, int(W / 4.0))
    bay_w = W / bays
    ops = []
    for k in range(g.floors):
        z = g.gfh + k * g.fh
        for i in range(bays):
            c = bay_w * (i + 0.5)
            ops.append((c - 1.0, c + 1.0, z + 0.7, z + 3.0, 0.25))
    doors = []
    for i in range(bays):
        c = bay_w * (i + 0.5)
        if i in (1, bays - 2):
            doors.append((c - 1.6, c + 1.6))
            ops.append((c - 1.6, c + 1.6, 1.2, 4.2, 0.25))
        elif i == 0:
            ops.append((c - 0.55, c + 0.55, 0.0, 2.6, 0.3))
        else:
            ops.append((c - 1.0, c + 1.0, 1.6, 3.6, 0.22))
    f.wall(ops, g.brick)
    for (u0, u1, v0, v1, d) in ops:
        if v0 >= g.gfh:
            f.quad(u0, u1, v0, v1, -d, "M_Window", atlas_uv(7 if g.rng.random() < 0.6 else 0, 4, 2))
            for t in (1 / 3, 2 / 3):
                uu = u0 + (u1 - u0) * t
                f.quad(uu - 0.03, uu + 0.03, v0, v1, -d + 0.01, "M_Frame_Dark")
            f.box(u0 - 0.1, u1 + 0.1, v0 - 0.12, v0, -0.02, 0.08, "M_Stone")
            f.box(u0 - 0.15, u1 + 0.15, v1, v1 + 0.35, -0.02, 0.05, "M_Stone")
        elif (u0, u1) in doors:
            f.quad(u0, u1, v0, v1, -d, "M_Shutter")
        elif v0 == 0.0:
            f.quad(u0, u1, v0, v1, -d, "M_Door")
        else:
            f.quad(u0, u1, v0, v1, -d, "M_Window", atlas_uv(7, 4, 2))
    # Pilasters between bays
    for i in range(bays + 1):
        uu = bay_w * i
        f.box(max(0.0, uu - 0.3), min(W, uu + 0.3), 0.0, g.top, 0.0, 0.12, g.brick)
    # Loading dock and canopy
    f.box(bay_w * 0.9, W - bay_w * 0.9, 0.0, 1.2, 0.0, 2.2, "M_Concrete", skip_back=True)
    f.box(bay_w * 0.85, W - bay_w * 0.85, 4.5, 4.7, 0.0, 2.8, "M_Iron")
    for uu in (bay_w * 0.9, W - bay_w * 0.9):
        f.box(uu - 0.06, uu + 0.06, 1.2, 4.5, 2.6, 2.72, "M_Iron")
    # Name band and cornice
    f.box(0.0, W, g.top - 1.4, g.top - 0.2, 0.0, 0.14, "M_Sign_Black")
    if spec.get("sign"):
        f.text(spec["sign"], FONT_DISPLAY, W * 0.5, g.top - 0.8, W * 0.8, 0.8, 0.145, "M_Sign_White")
    f.box(0.0, W, g.top, Hb, 0.0, 0.35, "M_Stone")
    # Painted side sign (left wall)
    side = Facade(mb, (-W * 0.5, D, 0.0), (0, -1, 0), D, Hb)
    side.quad(0.0, D, 0.0, Hb, 0.0, g.brick)
    side.quad(D * 0.1, D * 0.9, g.top - 7.0, g.top - 1.0, 0.01, "M_Sign_Black")
    if spec.get("side_sign"):
        side.text(spec["side_sign"], FONT_SIGN, D * 0.5, g.top - 4.0, D * 0.72, 4.6, 0.02, "M_Cornice_Cream")
    g.plain_wall((W * 0.5, 0.0, 0.0), (0, 1, 0), D, Hb)
    g.back_facade()
    g.roof()
    return mb

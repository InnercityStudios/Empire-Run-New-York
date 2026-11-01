"""Mesh construction helpers for game-ready assets.

MeshBuilder accumulates faces into one mesh with multiple material slots, so
each exported asset is a single mesh (one draw call per material surface).
UVs default to world-planar projection scaled by the material's `uv_m`, which
keeps texel density consistent across every asset that shares a material.

Blender convention used by all generators: +Z up, asset front faces -Y
(exported as +Z in glTF/Godot). Vehicles face +Y (Godot -Z, the look_at axis).
"""
import math
import os

import bmesh
import bpy
from mathutils import Matrix, Vector

from . import materials as matlib


def srgb_to_linear(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def hex_to_linear(hexstr):
    h = hexstr.lstrip("#")
    return tuple(srgb_to_linear(int(h[i:i + 2], 16) / 255.0) for i in (0, 2, 4))


def get_material(name):
    """Create (once) a Blender material carrying the preview colour of `name`."""
    mat = bpy.data.materials.get(name)
    if mat:
        return mat
    spec = {"color": "#8a8278"} if name == matlib.PALETTE_NAME else matlib.get(name)
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    col = spec.get("color", "#ffffff")
    if spec.get("albedo") and col.lower() == "#ffffff":
        col = "#9a8f84"  # neutral preview when the look comes from a texture
    bsdf.inputs["Base Color"].default_value = (*hex_to_linear(col), 1.0)
    bsdf.inputs["Roughness"].default_value = spec.get("roughness", 0.8)
    bsdf.inputs["Metallic"].default_value = spec.get("metallic", 0.0)
    return mat


def reset_scene():
    _FONTS.clear()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    for block in (bpy.data.meshes, bpy.data.materials, bpy.data.curves, bpy.data.objects):
        for item in list(block):
            block.remove(item)


class MeshBuilder:
    def __init__(self, name):
        self.name = name
        self.verts = []
        self.faces = []
        self.face_uvs = []
        self.face_mats = []
        self.face_smooth = []
        self.face_shades = []
        self.mat_names = []
        # Baked ambient occlusion: per-vertex value = face shade x shade_fn(p, n).
        # Stored as the colour attribute (Godot reads COLOR.r as occlusion).
        self.shade = 1.0
        self.shade_fn = None

    # -- internals -------------------------------------------------------------
    def _mat_index(self, mat):
        if mat not in self.mat_names:
            self.mat_names.append(mat)
        return self.mat_names.index(mat)

    @staticmethod
    def planar_uv(p, n, uv_m, offset=(0.0, 0.0)):
        ax, ay, az = abs(n.x), abs(n.y), abs(n.z)
        if az >= ax and az >= ay:
            u, v = p.x, p.y * (1 if n.z > 0 else -1)
        elif ax >= ay:
            u, v = p.y * (1 if n.x > 0 else -1), p.z
        else:
            u, v = p.x * (-1 if n.y > 0 else 1), p.z
        return ((u + offset[0]) / uv_m, (v + offset[1]) / uv_m)

    def add_face(self, pts, mat, uvs=None, normal=None, smooth=False, uv_offset=(0.0, 0.0), shade=None):
        """Add a polygon. If `normal` is given, winding is fixed to face it.
        `shade` darkens the face (baked occlusion); defaults to self.shade."""
        pts = [Vector(p) for p in pts]
        if len(pts) < 3:
            return
        n = (pts[1] - pts[0]).cross(pts[2] - pts[1])
        if n.length < 1e-9 and len(pts) > 3:
            n = (pts[2] - pts[0]).cross(pts[3] - pts[0])
        if normal is not None and n.dot(Vector(normal)) < 0:
            pts.reverse()
            if uvs is not None:
                uvs = list(reversed(uvs))
            n = -n
        if n.length < 1e-9:
            return
        n.normalize()
        if matlib.is_palette(mat):
            uvs = [matlib.palette_uv(mat)] * len(pts)
            mat = matlib.PALETTE_NAME
        elif uvs is None:
            uv_m = matlib.get(mat).get("uv_m", 1.0)
            uvs = [self.planar_uv(p, n, uv_m, uv_offset) for p in pts]
        base = len(self.verts)
        self.verts.extend(pts)
        self.faces.append(tuple(range(base, base + len(pts))))
        self.face_uvs.append(list(uvs))
        self.face_mats.append(self._mat_index(mat))
        self.face_smooth.append(smooth)
        k = self.shade if shade is None else shade
        self.face_shades.append([k * (self.shade_fn(p, n) if self.shade_fn else 1.0) for p in pts])

    def add_box(self, mn, mx, mat, skip=(), matrix=None, mats=None):
        """Axis-aligned box from min to max corner. `skip` drops faces by name
        (px, nx, py, ny, pz, nz). `matrix` transforms the result. `mats` maps a
        face name to an alternative material."""
        x0, y0, z0 = mn
        x1, y1, z1 = mx
        c = [Vector(v) for v in (
            (x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0),
            (x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1))]
        faces = {
            "nz": ((0, 3, 2, 1), (0, 0, -1)),
            "pz": ((4, 5, 6, 7), (0, 0, 1)),
            "ny": ((0, 1, 5, 4), (0, -1, 0)),
            "py": ((2, 3, 7, 6), (0, 1, 0)),
            "nx": ((3, 0, 4, 7), (-1, 0, 0)),
            "px": ((1, 2, 6, 5), (1, 0, 0)),
        }
        for key, (idx, nrm) in faces.items():
            if key in skip:
                continue
            pts = [c[i] for i in idx]
            n = Vector(nrm)
            if matrix is not None:
                pts = [matrix @ p for p in pts]
                n = (matrix.to_3x3() @ n).normalized()
            self.add_face(pts, (mats or {}).get(key, mat), normal=n)

    def add_cylinder(self, base, radius, height, segments, mat, cap_top=True, cap_bottom=False,
                     radius_top=None, matrix=None, smooth=True, uv_wrap=None, cap_mat=None):
        """Vertical cylinder/frustum standing on `base`. `uv_wrap` (metres) gives a
        wrapped UV around the circumference; otherwise planar UVs are used."""
        rt = radius if radius_top is None else radius_top
        bx, by, bz = base
        ring0, ring1 = [], []
        for i in range(segments + 1):
            a = 2 * math.pi * i / segments
            ca, sa = math.cos(a), math.sin(a)
            ring0.append(Vector((bx + ca * radius, by + sa * radius, bz)))
            ring1.append(Vector((bx + ca * rt, by + sa * rt, bz + height)))
        tf = (lambda p: matrix @ p) if matrix is not None else (lambda p: p)
        circ = 2 * math.pi * radius
        for i in range(segments):
            pts = [ring0[i], ring0[i + 1], ring1[i + 1], ring1[i]]
            mid = (pts[0] + pts[1]) * 0.5
            outward = Vector((mid.x - bx, mid.y - by, 0))
            uvs = None
            if uv_wrap:
                u0, u1 = circ * i / segments / uv_wrap, circ * (i + 1) / segments / uv_wrap
                v1 = height / uv_wrap
                uvs = [(u0, 0), (u1, 0), (u1, v1), (u0, v1)]
            n = outward if matrix is None else matrix.to_3x3() @ outward
            self.add_face([tf(p) for p in pts], mat, uvs=uvs, normal=n, smooth=smooth)
        up = Vector((0, 0, 1)) if matrix is None else matrix.to_3x3() @ Vector((0, 0, 1))
        if cap_top and rt > 0:
            self.add_face([tf(p) for p in ring1[:-1]], cap_mat or mat, normal=up)
        if cap_bottom:
            self.add_face([tf(p) for p in ring0[:-1]], cap_mat or mat, normal=-up)

    def add_prism(self, profile, axis_from, axis_to, mat, side_mat=None, smooth_sides=False):
        """Extrude a 2D profile given as 3D points on one plane, translated by
        (axis_to - axis_from). Caps use `mat`, sides use `side_mat`."""
        off = Vector(axis_to) - Vector(axis_from)
        p0 = [Vector(p) for p in profile]
        p1 = [p + off for p in p0]
        cen0 = sum(p0, Vector()) / len(p0)
        self.add_face(p0, mat, normal=-off)
        self.add_face(p1, mat, normal=off)
        for i in range(len(p0)):
            j = (i + 1) % len(p0)
            mid = (p0[i] + p0[j]) * 0.5
            outward = mid - cen0
            outward -= off.normalized() * outward.dot(off.normalized())
            self.add_face([p0[i], p0[j], p1[j], p1[i]], side_mat or mat, normal=outward, smooth=smooth_sides)

    def add_bmesh_object(self, obj, mat, matrix=None):
        """Bake an evaluated object (e.g. a text curve) into this builder."""
        dg = bpy.context.evaluated_depsgraph_get()
        ev = obj.evaluated_get(dg)
        mesh = ev.to_mesh()
        mw = (matrix or Matrix.Identity(4)) @ obj.matrix_world
        for poly in mesh.polygons:
            pts = [mw @ mesh.vertices[i].co for i in poly.vertices]
            self.add_face(pts, mat)
        ev.to_mesh_clear()

    def merge(self, other, offset=(0.0, 0.0, 0.0)):
        """Append another builder's faces, translated by `offset`."""
        off = Vector(offset)
        base = len(self.verts)
        self.verts.extend(v + off for v in other.verts)
        for f, uvs, mi, sm, sh in zip(other.faces, other.face_uvs, other.face_mats, other.face_smooth,
                                      other.face_shades):
            self.faces.append(tuple(i + base for i in f))
            self.face_uvs.append(uvs)
            self.face_mats.append(self._mat_index(other.mat_names[mi]))
            self.face_smooth.append(sm)
            self.face_shades.append(sh)

    # -- output ----------------------------------------------------------------
    def build(self, weld=True):
        mesh = bpy.data.meshes.new(self.name)
        mesh.from_pydata([tuple(v) for v in self.verts], [], self.faces)
        mesh.validate(clean_customdata=False)
        uv_layer = mesh.uv_layers.new(name="UVMap")
        col = mesh.color_attributes.new(name="Col", type="BYTE_COLOR", domain="CORNER")
        mesh.color_attributes.active_color = col
        for poly, uvs, mi, sm, sh in zip(mesh.polygons, self.face_uvs, self.face_mats, self.face_smooth,
                                         self.face_shades):
            poly.material_index = mi
            poly.use_smooth = sm
            for k, li in enumerate(poly.loop_indices):
                uv_layer.data[li].uv = uvs[k]
                a = max(0.0, min(1.0, sh[k]))
                col.data[li].color = (a, a, a, 1.0)
        for name in self.mat_names:
            mesh.materials.append(get_material(name))
        obj = bpy.data.objects.new(self.name, mesh)
        bpy.context.scene.collection.objects.link(obj)
        if weld:
            # Weld coincident vertices; flat/smooth flags keep hard edges where intended.
            bm = bmesh.new()
            bm.from_mesh(mesh)
            bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.0005)
            bm.to_mesh(mesh)
            bm.free()
        return obj

    def triangle_count(self):
        return sum(len(f) - 2 for f in self.faces)


_FONTS = {}


def load_font(path):
    if path not in _FONTS:
        _FONTS[path] = bpy.data.fonts.load(path)
    return _FONTS[path]


def make_text(text, font_path, max_w, max_h, center, facing="-Y", align="CENTER"):
    """Create a flat text object fitted inside max_w x max_h, centred on
    `center`, facing the given axis. Returns the object (caller bakes it)."""
    cu = bpy.data.curves.new("txt", "FONT")
    cu.body = text
    cu.font = load_font(font_path)
    cu.align_x = align
    cu.align_y = "CENTER"
    cu.resolution_u = 3
    cu.size = 1.0
    obj = bpy.data.objects.new("txt", cu)
    bpy.context.scene.collection.objects.link(obj)
    bpy.context.view_layer.update()
    dims = obj.dimensions
    if dims.x <= 0 or dims.y <= 0:
        return obj
    s = min(max_w / dims.x, max_h / dims.y)
    obj.scale = (s, s, s)
    rot = {"-Y": (math.radians(90), 0, 0),
           "+Y": (math.radians(90), 0, math.radians(180)),
           "-X": (math.radians(90), 0, math.radians(-90)),
           "+X": (math.radians(90), 0, math.radians(90))}[facing]
    obj.rotation_euler = rot
    obj.location = center
    bpy.context.view_layer.update()
    return obj


def remove_object(obj):
    data = obj.data
    bpy.data.objects.remove(obj)
    if isinstance(data, bpy.types.Curve):
        bpy.data.curves.remove(data)


def export_glb(obj, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    for o in bpy.context.scene.objects:
        o.select_set(o == obj)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_yup=True,
        export_texcoords=True,
        export_normals=True,
        export_materials="EXPORT",
        export_image_format="NONE",
        export_vertex_color="ACTIVE",
        export_all_vertex_colors=False,
        export_cameras=False,
        export_lights=False,
        export_animations=False,
    )

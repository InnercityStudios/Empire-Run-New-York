class_name RoadBuilder
extends RefCounted
## Generates road, intersection, ground and sidewalk meshes from a DistrictLayout.

const CORNER_SEGMENTS := 6
const CURB_LIP := 0.3


## One mesh for every carriageway, intersection and the surrounding ground.
static func build_road_mesh(layout: DistrictLayout) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for seg in layout.road_segments:
		_add_segment(st, seg)
	for inter in layout.intersections:
		var r: Rect2 = inter["rect"]
		_add_flat_quad(st, r, 0.0, 0.0)
	var mesh := st.commit()
	# Surrounding ground at a hair below the roads (same material, seamless).
	var gst := SurfaceTool.new()
	gst.begin(Mesh.PRIMITIVE_TRIANGLES)
	_add_flat_quad(gst, layout.bounds.grow(600.0), -0.03, 0.0)
	gst.commit(mesh)
	var mat := Materials.get_road_material()
	mesh.surface_set_material(0, mat)
	mesh.surface_set_material(1, mat)
	return mesh


static func _add_segment(st: SurfaceTool, seg: Dictionary) -> void:
	var a: Vector2 = seg["from"]
	var b: Vector2 = seg["to"]
	var length := a.distance_to(b)
	if length < 0.05:
		return
	var d := (b - a) / length
	var right := Vector2(-d.y, d.x)
	var hw: float = seg["width"] * 0.5
	var style: float = float(seg.get("style", 1)) / 2.0
	var p := [a - right * hw, a + right * hw, b + right * hw, b - right * hw]
	var lat := [-hw, hw, hw, -hw]
	var along := [0.0, 0.0, length, length]
	var idx := [0, 1, 2, 0, 2, 3]
	_emit(st, p, lat, along, idx, Vector2(length, hw), style)


static func _add_flat_quad(st: SurfaceTool, r: Rect2, y: float, style: float) -> void:
	var p := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
	_emit(st, p, [0.0, 0.0, 0.0, 0.0], [0.0, 0.0, 0.0, 0.0], [0, 1, 2, 0, 2, 3], Vector2.ZERO, style, y)


static func _emit(st: SurfaceTool, p: Array, lat: Array, along: Array, idx: Array, info: Vector2, style: float,
		y := 0.0) -> void:
	var tris := []
	for k in range(0, idx.size(), 3):
		tris.append([idx[k], idx[k + 1], idx[k + 2]])
	for t in tris:
		var v0 := Vector3(p[t[0]].x, y, p[t[0]].y)
		var v1 := Vector3(p[t[1]].x, y, p[t[1]].y)
		var v2 := Vector3(p[t[2]].x, y, p[t[2]].y)
		var order: Array = t if (v1 - v0).cross(v2 - v0).y < 0.0 else [t[0], t[2], t[1]]
		for i in order:
			st.set_normal(Vector3.UP)
			st.set_tangent(Plane(1, 0, 0, 1))
			st.set_color(Color(style, 0, 0, 1))
			st.set_uv(Vector2(lat[i], along[i]))
			st.set_uv2(info)
			st.add_vertex(Vector3(p[i].x, y, p[i].y))


## Raised sidewalk slab for a block: rounded corners, granite curb lip and face.
## Geometry is added to `tools` ({material_name: SurfaceTool}) for chunk merging.
static func add_sidewalk(tools: Dictionary, rect: Rect2, curb_h: float, radius: float) -> void:
	var outer := _rounded_rect(rect, radius)
	var inner := _rounded_rect(rect.grow(-CURB_LIP), maxf(radius - CURB_LIP, 0.5))
	var top: SurfaceTool = _tool(tools, "M_Sidewalk")
	var curb: SurfaceTool = _tool(tools, "M_Curb")
	var c := rect.get_center()
	# Sidewalk top (convex fan)
	for i in inner.size():
		var j := (i + 1) % inner.size()
		_tri(top, Vector3(c.x, curb_h, c.y), Vector3(inner[i].x, curb_h, inner[i].y),
			Vector3(inner[j].x, curb_h, inner[j].y), Vector3.UP, 3.0)
	# Curb lip ring and vertical curb face
	for i in outer.size():
		var j := (i + 1) % outer.size()
		var o0 := Vector3(outer[i].x, curb_h, outer[i].y)
		var o1 := Vector3(outer[j].x, curb_h, outer[j].y)
		var i0 := Vector3(inner[i].x, curb_h, inner[i].y)
		var i1 := Vector3(inner[j].x, curb_h, inner[j].y)
		_tri(curb, o0, o1, i1, Vector3.UP, 2.0)
		_tri(curb, o0, i1, i0, Vector3.UP, 2.0)
		var mid := (outer[i] + outer[j]) * 0.5
		var edge := (outer[j] - outer[i]).normalized()
		var n := Vector3(edge.y, 0, -edge.x)
		if n.dot(Vector3(mid.x - c.x, 0, mid.y - c.y)) < 0:
			n = -n
		var b0 := Vector3(outer[i].x, -0.02, outer[i].y)
		var b1 := Vector3(outer[j].x, -0.02, outer[j].y)
		_tri(curb, b0, b1, o1, n, 2.0)
		_tri(curb, b0, o1, o0, n, 2.0)


static func _tool(tools: Dictionary, mat: String) -> SurfaceTool:
	if not tools.has(mat):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		tools[mat] = st
	return tools[mat]


## Adds a triangle facing `n` with world-planar UVs (metres / uv_m).
static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, n: Vector3, uv_m: float) -> void:
	var verts := [a, b, c]
	# Godot treats clockwise winding (seen from the front) as front-facing.
	if (b - a).cross(c - a).dot(n) > 0.0:
		verts = [a, c, b]
	for v in verts:
		st.set_normal(n)
		var uv: Vector2
		if absf(n.y) > 0.5:
			uv = Vector2(v.x, v.z) / uv_m
		elif absf(n.x) > absf(n.z):
			uv = Vector2(v.z * signf(n.x), -v.y) / uv_m
		else:
			uv = Vector2(-v.x * signf(n.z), -v.y) / uv_m
		st.set_uv(uv)
		st.add_vertex(v)


static func _rounded_rect(r: Rect2, radius: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var corners := [
		[Vector2(r.end.x - radius, r.position.y + radius), -PI * 0.5],
		[Vector2(r.end.x - radius, r.end.y - radius), 0.0],
		[Vector2(r.position.x + radius, r.end.y - radius), PI * 0.5],
		[Vector2(r.position.x + radius, r.position.y + radius), PI],
	]
	for c in corners:
		for k in CORNER_SEGMENTS + 1:
			var a: float = c[1] + (PI * 0.5) * k / CORNER_SEGMENTS
			pts.append(c[0] + Vector2(cos(a), sin(a)) * radius)
	return pts

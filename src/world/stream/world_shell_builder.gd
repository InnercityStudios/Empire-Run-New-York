class_name WorldShellBuilder
extends RefCounted
## Always-loaded, low-cost world geometry: water, land and region grounds,
## quay walls, road surfaces (one mesh per chunk), the bridge, park lakes and
## paths. Together with the far-city LOD this guarantees there is never empty
## terrain or a hard city edge at any zoom.

const WATER_SHADER := preload("res://src/world/shaders/water.gdshader")
const QUAY_DEPTH := 2.2


static func build(world: WorldLayout, parent: Node3D) -> Dictionary:
	var stats := {"road_chunks": 0}
	_add(parent, "Water", _water(world), false)
	_add(parent, "Land", _land(world), false)
	_add(parent, "Quays", _quays(world), true)
	var roads_root := Node3D.new()
	roads_root.name = "Roads"
	parent.add_child(roads_root)
	for key in world.chunk_keys():
		var c: Dictionary = world.chunk(key)
		if c["roads"].is_empty() and c["intersections"].is_empty():
			continue
		var mesh := RoadBuilder.build_chunk_roads(c["roads"], c["intersections"])
		if mesh.get_surface_count() == 0:
			continue
		var mi := _add(roads_root, "Roads_%d_%d" % [key.x, key.y], mesh, false)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		stats["road_chunks"] += 1
	_add(parent, "Bridges", _bridges(world), true)
	_add(parent, "ParkFeatures", _park_features(world), false)
	_add(parent, "Piers", _piers(world), true)
	return stats


static func _add(parent: Node3D, node_name: String, mesh: Mesh, shadows: bool) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


static func _quad(st: SurfaceTool, r: Rect2, y: float, uv_m: float) -> void:
	var a := Vector3(r.position.x, y, r.position.y)
	var b := Vector3(r.end.x, y, r.position.y)
	var c := Vector3(r.end.x, y, r.end.y)
	var d := Vector3(r.position.x, y, r.end.y)
	RoadBuilder._tri(st, a, b, c, Vector3.UP, uv_m)
	RoadBuilder._tri(st, a, c, d, Vector3.UP, uv_m)


static func _water(world: WorldLayout) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_quad(st, world.world_rect.grow(1500.0), world.water_level, 10.0)
	st.generate_tangents()
	var mesh := st.commit()
	var m := ShaderMaterial.new()
	m.shader = WATER_SHADER
	m.set_shader_parameter("wave_normal", load("res://assets/textures/water_normal.png"))
	mesh.surface_set_material(0, m)
	return mesh


## Land: asphalt base everywhere on land (seamless with roads), region ground
## overlays (grass, concrete) and backdrop shores.
static func _land(world: WorldLayout) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var asphalt := SurfaceTool.new()
	asphalt.begin(Mesh.PRIMITIVE_TRIANGLES)
	var land_rects: Array = [world.land]
	for bd in world.backdrops:
		land_rects.append(bd["rect"])
	for r in land_rects:
		var p := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
		RoadBuilder._emit(asphalt, p, [0.0, 0.0, 0.0, 0.0], [0.0, 0.0, 0.0, 0.0], [0, 1, 2, 0, 2, 3], Vector2.ZERO, 0.0, -0.03)
	asphalt.commit(mesh)
	mesh.surface_set_material(0, Materials.get_road_material())
	var overlays := {}
	for g in world.region_grounds:
		if g["ground"] == "asphalt":
			continue
		if not overlays.has(g["ground"]):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			overlays[g["ground"]] = st
		_quad(overlays[g["ground"]], g["rect"], -0.015, 6.0 if g["ground"] == "M_Grass" else 3.0)
	for mat_name in overlays:
		var st: SurfaceTool = overlays[mat_name]
		st.generate_tangents()
		st.commit(mesh)
		mesh.surface_set_material(mesh.get_surface_count() - 1, Materials.get_material(mat_name))
	return mesh


## Vertical stone quay walls wherever land meets water.
static func _quays(world: WorldLayout) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var y0 := world.water_level - 0.6
	var y1 := 0.0
	var land := world.land
	# West, east and south edges of the island face water; the north continues.
	_wall(st, Vector2(land.position.x, land.end.y), Vector2(land.position.x, land.position.y), Vector2(-1, 0), y0, y1)
	_wall(st, Vector2(land.end.x, land.position.y), Vector2(land.end.x, land.end.y), Vector2(1, 0), y0, y1)
	_wall(st, Vector2(land.end.x, land.end.y), Vector2(land.position.x, land.end.y), Vector2(0, 1), y0, y1)
	for bd in world.backdrops:
		var r: Rect2 = bd["rect"]
		if r.end.x <= land.position.x:
			_wall(st, Vector2(r.end.x, r.position.y), Vector2(r.end.x, r.end.y), Vector2(1, 0), y0, y1)
		elif r.position.x >= land.end.x:
			_wall(st, Vector2(r.position.x, r.end.y), Vector2(r.position.x, r.position.y), Vector2(-1, 0), y0, y1)
	st.generate_tangents()
	var mesh := st.commit()
	mesh.surface_set_material(0, Materials.get_material("M_Quay"))
	return mesh


static func _wall(st: SurfaceTool, a: Vector2, b: Vector2, out: Vector2, y0: float, y1: float) -> void:
	var n := Vector3(out.x, 0, out.y)
	var p0 := Vector3(a.x, y0, a.y)
	var p1 := Vector3(b.x, y0, b.y)
	var p2 := Vector3(b.x, y1, b.y)
	var p3 := Vector3(a.x, y1, a.y)
	RoadBuilder._tri(st, p0, p1, p2, n, 3.0)
	RoadBuilder._tri(st, p0, p2, p3, n, 3.0)


static func _box(st: SurfaceTool, mn: Vector3, mx: Vector3, uv_m: float) -> void:
	var faces := [
		[Vector3.UP, [Vector3(mn.x, mx.y, mn.z), Vector3(mx.x, mx.y, mn.z), Vector3(mx.x, mx.y, mx.z), Vector3(mn.x, mx.y, mx.z)]],
		[Vector3.LEFT, [Vector3(mn.x, mn.y, mx.z), Vector3(mn.x, mn.y, mn.z), Vector3(mn.x, mx.y, mn.z), Vector3(mn.x, mx.y, mx.z)]],
		[Vector3.RIGHT, [Vector3(mx.x, mn.y, mn.z), Vector3(mx.x, mn.y, mx.z), Vector3(mx.x, mx.y, mx.z), Vector3(mx.x, mx.y, mn.z)]],
		[Vector3.FORWARD, [Vector3(mx.x, mn.y, mn.z), Vector3(mn.x, mn.y, mn.z), Vector3(mn.x, mx.y, mn.z), Vector3(mx.x, mx.y, mn.z)]],
		[Vector3.BACK, [Vector3(mn.x, mn.y, mx.z), Vector3(mx.x, mn.y, mx.z), Vector3(mx.x, mx.y, mx.z), Vector3(mn.x, mx.y, mx.z)]],
	]
	for f in faces:
		var q: Array = f[1]
		RoadBuilder._tri(st, q[0], q[1], q[2], f[0], uv_m)
		RoadBuilder._tri(st, q[0], q[2], q[3], f[0], uv_m)


static func _piers(world: WorldLayout) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for pr in world.piers:
		var d: Rect2 = pr["deck"]
		_box(st, Vector3(d.position.x, world.water_level - 0.5, d.position.y), Vector3(d.end.x, -0.02, d.end.y), 3.0)
	st.generate_tangents()
	var mesh := st.commit()
	if mesh.get_surface_count() > 0:
		mesh.surface_set_material(0, Materials.get_material("M_Concrete"))
	return mesh


## Suspension bridge: deck, two towers, main cables and suspenders.
static func _bridges(world: WorldLayout) -> ArrayMesh:
	var deck := SurfaceTool.new()
	deck.begin(Mesh.PRIMITIVE_TRIANGLES)
	var steel := SurfaceTool.new()
	steel.begin(Mesh.PRIMITIVE_TRIANGLES)
	for br in world.bridges:
		var a: Vector2 = br["from"]
		var b: Vector2 = br["to"]
		var hw: float = br["width"] * 0.5
		var mn := Vector2(minf(a.x, b.x), minf(a.y, b.y) - hw)
		var mx := Vector2(maxf(a.x, b.x), maxf(a.y, b.y) + hw)
		_box(deck, Vector3(mn.x, -1.4, mn.y), Vector3(mx.x, -0.05, mx.y), 4.0)
		var z := a.y
		var tower_h := 62.0
		for tx in br["towers"]:
			for side in [-1.0, 1.0]:
				_box(steel, Vector3(tx - 3.0, world.water_level, z + side * (hw + 0.5) - 2.5),
					Vector3(tx + 3.0, tower_h, z + side * (hw + 0.5) + 2.5), 4.0)
			_box(steel, Vector3(tx - 2.5, tower_h - 6.0, z - hw - 3.0), Vector3(tx + 2.5, tower_h - 2.0, z + hw + 3.0), 4.0)
			_box(steel, Vector3(tx - 2.5, 18.0, z - hw - 3.0), Vector3(tx + 2.5, 21.0, z + hw + 3.0), 4.0)
		# Main cables: parabola between tower tops, anchored at the shores.
		var t0: float = br["towers"][0]
		var t1: float = br["towers"][-1]
		for side in [-1.0, 1.0]:
			var cz: float = z + side * (hw + 0.5)
			var pts: Array = []
			var n := 24
			for i in n + 1:
				var x: float = lerpf(a.x, b.x, float(i) / n)
				var y: float
				if x < t0:
					y = lerpf(2.0, tower_h - 1.0, (x - a.x) / maxf(t0 - a.x, 1.0))
				elif x > t1:
					y = lerpf(tower_h - 1.0, 2.0, (x - t1) / maxf(b.x - t1, 1.0))
				else:
					var u := (x - t0) / (t1 - t0) * 2.0 - 1.0
					y = 8.0 + (tower_h - 9.0) * u * u
				pts.append(Vector3(x, y, cz))
			for i in n:
				var p0: Vector3 = pts[i]
				var p1: Vector3 = pts[i + 1]
				_beam(steel, p0, p1, 0.5)
				if i % 2 == 0 and p0.y > 3.0:
					_beam(steel, Vector3(p0.x, 0.0, cz), p0, 0.12)
	deck.generate_tangents()
	steel.generate_tangents()
	var mesh := ArrayMesh.new()
	deck.commit(mesh)
	steel.commit(mesh)
	if mesh.get_surface_count() >= 2:
		mesh.surface_set_material(0, Materials.get_material("M_Concrete"))
		mesh.surface_set_material(1, Materials.get_material("M_Palette"))
	return mesh


static func _beam(st: SurfaceTool, a: Vector3, b: Vector3, r: float) -> void:
	var d := (b - a).normalized()
	var side := d.cross(Vector3.UP).normalized() * r if absf(d.y) < 0.99 else Vector3(r, 0, 0)
	var up := side.cross(d).normalized() * r
	for k in 4:
		var o0: Vector3 = [side, up, -side, -up][k]
		var o1: Vector3 = [up, -side, -up, side][k]
		var n := (o0 + o1).normalized()
		RoadBuilder._tri(st, a + o0, b + o0, b + o1, n, 4.0)
		RoadBuilder._tri(st, a + o0, b + o1, a + o1, n, 4.0)


## Park lakes (inset water with a stone rim) and gravel paths.
static func _park_features(world: WorldLayout) -> ArrayMesh:
	var lake := SurfaceTool.new()
	lake.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rim := SurfaceTool.new()
	rim.begin(Mesh.PRIMITIVE_TRIANGLES)
	var paths := SurfaceTool.new()
	paths.begin(Mesh.PRIMITIVE_TRIANGLES)
	for pk in world.parks:
		var l: Rect2 = pk["lake"]
		_quad(lake, l, -0.45, 10.0)
		for side in [[l.position, Vector2(l.end.x, l.position.y), Vector2(0, 1)],
				[Vector2(l.end.x, l.position.y), l.end, Vector2(-1, 0)],
				[l.end, Vector2(l.position.x, l.end.y), Vector2(0, -1)],
				[Vector2(l.position.x, l.end.y), l.position, Vector2(1, 0)]]:
			_wall(rim, side[0], side[1], side[2], -0.6, 0.02)
		for path in pk["paths"]:
			var a: Vector2 = path[0]
			var b: Vector2 = path[1]
			var dir := (b - a).normalized()
			var right := Vector2(-dir.y, dir.x) * 1.6
			var q := [a - right, a + right, b + right, b - right]
			RoadBuilder._tri(paths, Vector3(q[0].x, 0.0, q[0].y), Vector3(q[1].x, 0.0, q[1].y), Vector3(q[2].x, 0.0, q[2].y), Vector3.UP, 4.0)
			RoadBuilder._tri(paths, Vector3(q[0].x, 0.0, q[0].y), Vector3(q[2].x, 0.0, q[2].y), Vector3(q[3].x, 0.0, q[3].y), Vector3.UP, 4.0)
	var mesh := ArrayMesh.new()
	var water := ShaderMaterial.new()
	water.shader = WATER_SHADER
	water.set_shader_parameter("wave_normal", load("res://assets/textures/water_normal.png"))
	water.set_shader_parameter("deep_color", Color(0.06, 0.12, 0.1))
	for entry in [[lake, water], [rim, Materials.get_material("M_Quay")], [paths, Materials.get_material("M_Gravel")]]:
		var st: SurfaceTool = entry[0]
		st.generate_tangents()
		st.commit(mesh)
		if mesh.get_surface_count() > 0:
			mesh.surface_set_material(mesh.get_surface_count() - 1, entry[1])
	return mesh

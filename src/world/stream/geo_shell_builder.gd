class_name GeoShellBuilder
extends RefCounted
## Always-loaded geometry of a geography world: open water, coastlines with
## quay walls, park and airport grounds, lakes and paths, road surfaces in
## 1 km tiles and the bridges (deck, towers, cables). Cheap enough to stay
## resident, so no zoom level ever shows a void or a hard map edge.

const ROAD_TILE := 1024.0
const TOWER_HEIGHT := 64.0


static func build(world: WorldLayout, parent: Node3D) -> Dictionary:
	var stats := {"road_chunks": 0}
	_add(parent, "Water", _water(world), false)
	_add(parent, "Land", _land(world), false)
	_add(parent, "Quays", _quays(world), false)
	_add(parent, "Grounds", _grounds(world), false)
	_add(parent, "ParkFeatures", _park_features(world), false)
	var roads_root := Node3D.new()
	roads_root.name = "Roads"
	parent.add_child(roads_root)
	var tiles := {}
	for seg in world.road_segments:
		var k := _tile((seg["from"] + seg["to"]) * 0.5)
		if not tiles.has(k):
			tiles[k] = [[], []]
		tiles[k][0].append(seg)
	for inter in world.intersections:
		var k := _tile(inter["center"])
		if not tiles.has(k):
			tiles[k] = [[], []]
		tiles[k][1].append(inter)
	var keys := tiles.keys()
	keys.sort()
	for k in keys:
		var mesh := RoadBuilder.build_chunk_roads(tiles[k][0], tiles[k][1])
		if mesh.get_surface_count() == 0:
			continue
		_add(roads_root, "Roads_%d_%d" % [k.x, k.y], mesh, false)
		stats["road_chunks"] += 1
	var bridges := _bridges(world)
	if bridges.get_surface_count() > 0:
		_add(parent, "Bridges", bridges, true)
	return stats


static func _tile(p: Vector2) -> Vector2i:
	return Vector2i((p / ROAD_TILE).floor())


static func _add(parent: Node3D, node_name: String, mesh: Mesh, shadows: bool) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


static func _water(world: WorldLayout) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	WorldShellBuilder._quad(st, world.world_rect.grow(3000.0), world.water_level, 10.0)
	st.generate_tangents()
	var mesh := st.commit()
	var m := ShaderMaterial.new()
	m.shader = WorldShellBuilder.WATER_SHADER
	m.set_shader_parameter("wave_normal", load("res://assets/textures/water_normal.png"))
	mesh.surface_set_material(0, m)
	return mesh


static func _fill_polygon(st: SurfaceTool, poly: PackedVector2Array, y: float, uv_m: float) -> void:
	var idx := Geometry2D.triangulate_polygon(poly)
	for k in range(0, idx.size(), 3):
		var a := poly[idx[k]]
		var b := poly[idx[k + 1]]
		var c := poly[idx[k + 2]]
		RoadBuilder._tri(st, Vector3(a.x, y, a.y), Vector3(b.x, y, b.y), Vector3(c.x, y, c.y), Vector3.UP, uv_m)


## Land: the asphalt road material everywhere (seamless with streets).
static func _land(world: WorldLayout) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for c in world.land_polygons:
		var poly: PackedVector2Array = c["polygon"]
		var idx := Geometry2D.triangulate_polygon(poly)
		for k in range(0, idx.size(), 3):
			var p := [poly[idx[k]], poly[idx[k + 1]], poly[idx[k + 2]]]
			RoadBuilder._emit(st, p, [0.0, 0.0, 0.0], [0.0, 0.0, 0.0], [0, 1, 2], Vector2.ZERO, 0.0, -0.03)
	var mesh := st.commit()
	if mesh.get_surface_count() > 0:
		mesh.surface_set_material(0, Materials.get_road_material())
	return mesh


## Stone quay walls along every shoreline.
static func _quays(world: WorldLayout) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var y0 := world.water_level - 0.6
	for c in world.land_polygons:
		var poly: PackedVector2Array = c["polygon"]
		for i in poly.size():
			var a := poly[i]
			var b := poly[(i + 1) % poly.size()]
			WorldShellBuilder._wall(st, a, b, _outward(poly, a, b), y0, 0.0)
	st.generate_tangents()
	var mesh := st.commit()
	mesh.surface_set_material(0, Materials.get_material("M_Quay"))
	return mesh


static func _grounds(world: WorldLayout) -> ArrayMesh:
	var tools := {}
	for g in world.grounds:
		var mat: String = g["material"]
		if not tools.has(mat):
			var s := SurfaceTool.new()
			s.begin(Mesh.PRIMITIVE_TRIANGLES)
			tools[mat] = s
		_fill_polygon(tools[mat], g["polygon"], -0.015, 6.0 if mat == "M_Grass" else 3.0)
	var mesh := ArrayMesh.new()
	for mat in tools:
		var st: SurfaceTool = tools[mat]
		st.generate_tangents()
		st.commit(mesh)
		mesh.surface_set_material(mesh.get_surface_count() - 1, Materials.get_material(mat))
	return mesh


## Lakes (water at ground level with a low stone rim) and gravel paths.
static func _park_features(world: WorldLayout) -> ArrayMesh:
	var lake := SurfaceTool.new()
	lake.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rim := SurfaceTool.new()
	rim.begin(Mesh.PRIMITIVE_TRIANGLES)
	var paths := SurfaceTool.new()
	paths.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n_lake := 0
	var n_path := 0
	for pk in world.park_areas:
		for l in pk["lakes"]:
			var poly: PackedVector2Array = l
			_fill_polygon(lake, poly, 0.02, 10.0)
			n_lake += 1
			for i in poly.size():
				var a := poly[i]
				var b := poly[(i + 1) % poly.size()]
				var out := _outward(poly, a, b)
				WorldShellBuilder._wall(rim, a + out * 0.8, b + out * 0.8, out, -0.02, 0.12)
		for path in pk["paths"]:
			var a: Vector2 = path[0]
			var b: Vector2 = path[1]
			var right := Vector2(-(b - a).normalized().y, (b - a).normalized().x) * 1.8
			var q := [a - right, a + right, b + right, b - right]
			RoadBuilder._tri(paths, Vector3(q[0].x, 0.0, q[0].y), Vector3(q[1].x, 0.0, q[1].y), Vector3(q[2].x, 0.0, q[2].y), Vector3.UP, 4.0)
			RoadBuilder._tri(paths, Vector3(q[0].x, 0.0, q[0].y), Vector3(q[2].x, 0.0, q[2].y), Vector3(q[3].x, 0.0, q[3].y), Vector3.UP, 4.0)
			n_path += 1
	var mesh := ArrayMesh.new()
	var water := ShaderMaterial.new()
	water.shader = WorldShellBuilder.WATER_SHADER
	water.set_shader_parameter("wave_normal", load("res://assets/textures/water_normal.png"))
	water.set_shader_parameter("deep_color", Color(0.06, 0.12, 0.1))
	for entry in [[lake, water, n_lake], [rim, Materials.get_material("M_Quay"), n_lake], [paths, Materials.get_material("M_Gravel"), n_path]]:
		if int(entry[2]) == 0:
			continue
		var st: SurfaceTool = entry[0]
		st.generate_tangents()
		st.commit(mesh)
		mesh.surface_set_material(mesh.get_surface_count() - 1, entry[1])
	return mesh


## Bridge decks follow their paths; suspension and cantilever bridges get two
## towers in the river, main cables and suspenders; others a low truss rail.
static func _bridges(world: WorldLayout) -> ArrayMesh:
	var deck := SurfaceTool.new()
	deck.begin(Mesh.PRIMITIVE_TRIANGLES)
	var steel := SurfaceTool.new()
	steel.begin(Mesh.PRIMITIVE_TRIANGLES)
	for br in world.bridge_paths:
		var path: PackedVector2Array = br["path"]
		var hw: float = float(br["width"]) * 0.5 + 1.0
		for s in path.size() - 1:
			_oriented_box(deck, path[s], path[s + 1], hw, -1.6, -0.04)
			if br["kind"] in ["truss", "swing", "bascule"]:
				for side in [-1.0, 1.0]:
					var n: Vector2 = Vector2(-(path[s + 1] - path[s]).normalized().y, (path[s + 1] - path[s]).normalized().x) * (hw - 0.3) * side
					WorldShellBuilder._beam(steel, Vector3(path[s].x + n.x, 5.5, path[s].y + n.y),
						Vector3(path[s + 1].x + n.x, 5.5, path[s + 1].y + n.y), 0.35)
		var towers: Array = br["towers"]
		if towers.size() != 2:
			continue
		var total: float = br["length"]
		var s_t := [_distance_along(path, towers[0]), _distance_along(path, towers[1])]
		for k in 2:
			var tp: Vector2 = towers[k]
			var dir := _dir_at(path, s_t[k])
			var n := Vector2(-dir.y, dir.x)
			for side in [-1.0, 1.0]:
				var c: Vector2 = tp + n * (hw + 1.5) * side
				_oriented_box(steel, c - dir * 3.0, c + dir * 3.0, 2.5, world.water_level, TOWER_HEIGHT)
			for y in [TOWER_HEIGHT - 6.0, 20.0]:
				var a := tp - n * (hw + 3.5)
				var b := tp + n * (hw + 3.5)
				_oriented_box(steel, a, b, 2.2, y, y + 3.5)
		# Main cables: shore anchors up to the tower tops, sagging between.
		for side in [-1.0, 1.0]:
			var steps := 32
			var prev := Vector3.ZERO
			for i in steps + 1:
				var d := total * i / steps
				var y: float
				if d < s_t[0]:
					y = lerpf(2.0, TOWER_HEIGHT - 1.0, d / maxf(s_t[0], 1.0))
				elif d > s_t[1]:
					y = lerpf(TOWER_HEIGHT - 1.0, 2.0, (d - s_t[1]) / maxf(total - s_t[1], 1.0))
				else:
					var u: float = (d - s_t[0]) / maxf(s_t[1] - s_t[0], 1.0) * 2.0 - 1.0
					y = 8.0 + (TOWER_HEIGHT - 9.0) * u * u
				var p := GeographyBuilder._along(path, d)
				var n: Vector2 = Vector2(-_dir_at(path, d).y, _dir_at(path, d).x) * (hw + 1.5) * side
				var cur := Vector3(p.x + n.x, y, p.y + n.y)
				if i > 0:
					WorldShellBuilder._beam(steel, prev, cur, 0.5)
					if i % 2 == 0 and cur.y > 3.0:
						WorldShellBuilder._beam(steel, Vector3(cur.x, 0.0, cur.z), cur, 0.12)
				prev = cur
	deck.generate_tangents()
	steel.generate_tangents()
	var mesh := ArrayMesh.new()
	deck.commit(mesh)
	if mesh.get_surface_count() > 0:
		mesh.surface_set_material(0, Materials.get_material("M_Concrete"))
	var before := mesh.get_surface_count()
	steel.commit(mesh)
	if mesh.get_surface_count() > before:
		mesh.surface_set_material(before, Materials.get_material("M_Palette"))
	return mesh


## Unit normal of edge a->b pointing out of the polygon.
static func _outward(poly: PackedVector2Array, a: Vector2, b: Vector2) -> Vector2:
	var d := (b - a).normalized()
	var n := Vector2(d.y, -d.x)
	return -n if Geometry2D.is_point_in_polygon((a + b) * 0.5 + n * 0.5, poly) else n


static func _distance_along(path: PackedVector2Array, p: Vector2) -> float:
	var best := 0.0
	var best_d := INF
	var acc := 0.0
	for s in path.size() - 1:
		var q := Geometry2D.get_closest_point_to_segment(p, path[s], path[s + 1])
		var d := q.distance_to(p)
		if d < best_d:
			best_d = d
			best = acc + path[s].distance_to(q)
		acc += path[s].distance_to(path[s + 1])
	return best


static func _dir_at(path: PackedVector2Array, d: float) -> Vector2:
	for s in path.size() - 1:
		var l := path[s].distance_to(path[s + 1])
		if d <= l or s == path.size() - 2:
			return (path[s + 1] - path[s]).normalized()
		d -= l
	return Vector2.RIGHT


## Box along a ground segment a->b, `hw` half-width, between heights y0..y1.
static func _oriented_box(st: SurfaceTool, a: Vector2, b: Vector2, hw: float, y0: float, y1: float) -> void:
	var d := (b - a).normalized()
	var n := Vector2(-d.y, d.x) * hw
	var c := [a - n, b - n, b + n, a + n]
	var top := []
	var bot := []
	for p in c:
		top.append(Vector3(p.x, y1, p.y))
		bot.append(Vector3(p.x, y0, p.y))
	RoadBuilder._tri(st, top[0], top[1], top[2], Vector3.UP, 4.0)
	RoadBuilder._tri(st, top[0], top[2], top[3], Vector3.UP, 4.0)
	for i in 4:
		var j := (i + 1) % 4
		var e: Vector2 = (c[j] as Vector2) - (c[i] as Vector2)
		var mid: Vector2 = ((c[i] as Vector2) + (c[j] as Vector2)) * 0.5 - (a + b) * 0.5
		var nn := Vector3(e.y, 0, -e.x).normalized()
		if nn.dot(Vector3(mid.x, 0, mid.y)) < 0.0:
			nn = -nn
		RoadBuilder._tri(st, bot[i], bot[j], top[j], nn, 4.0)
		RoadBuilder._tri(st, bot[i], top[j], top[i], nn, 4.0)

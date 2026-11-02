class_name FarCityBuilder
extends RefCounted
## Distant-city LOD: per chunk, one box per building (facade tone from the
## catalogue, procedural windows in the shader), plain block pavements and
## backdrop districts. About 10 triangles per building, so the whole province
## can stay resident and the horizon is always a city, never empty ground.

const SHADER := preload("res://src/world/shaders/far_building.gdshader")
const PAVEMENT := Color(0.6, 0.58, 0.54)
const YARD_GRASS := Color(0.34, 0.4, 0.27)
const YARD_GRAVEL := Color(0.46, 0.44, 0.4)

static var _material: ShaderMaterial


static func material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = SHADER
		_material.set_shader_parameter("noise_tex", load("res://assets/textures/grime_noise.png"))
	return _material


static func build_chunk(world: WorldLayout, key: Vector2i, catalog: Dictionary) -> ArrayMesh:
	return to_mesh(build_arrays(world, key, catalog))


## Mesh arrays only (safe on worker threads); `to_mesh` uploads on the main thread.
static func build_arrays(world: WorldLayout, key: Vector2i, catalog: Dictionary) -> Array:
	var c: Dictionary = world.chunk(key)
	if c.is_empty():
		return []
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var lots: Array = []
	for li in c["lots"]:
		lots.append(world.lots[li])
	for bi in c["blocks"]:
		var b: Dictionary = world.blocks[bi]
		if b["sidewalks"]:
			var yard: String = b.get("yard", "")
			_flat(verts, normals, colors, WorldLayout.block_corners(b), world.curb_height,
				YARD_GRASS if yard == "M_Grass" else YARD_GRAVEL if yard == "M_Gravel" else PAVEMENT)
		if b.get("gen", false):
			lots.append_array(BlockFiller.fill(b, world.sidewalk, world.curb_height, false)["lots"])
	for lot in lots:
		var def: Dictionary = catalog.get(lot["building"], {})
		if def.is_empty():
			continue
		var t: Transform3D = lot["transform"]
		var w: float = def["width"]
		var d: float = def.get("depth", 20.0)
		var h: float = def.get("height", 15.0) * 0.92
		var col := Color.html(def.get("facade", "#7a5a48"))
		col.a = def.get("roof_tone", 0.5)
		_box(verts, normals, colors, t, Vector3(-w * 0.5, 0.0, -d), Vector3(w * 0.5, h, 0.0), col)
	for box in c["backdrop"]:
		var r: Rect2 = box["rect"]
		var t := Transform3D(Basis(), Vector3(r.get_center().x, 0.0, r.get_center().y))
		var tone := Color.html(["#6f4a3a", "#8a7560", "#5a4136", "#9c8f7c"][int(absf(r.position.x * 7 + r.position.y)) % 4])
		tone.a = 0.5
		_box(verts, normals, colors, t, Vector3(-r.size.x * 0.5, 0, -r.size.y * 0.5),
			Vector3(r.size.x * 0.5, box["height"], r.size.y * 0.5), tone)
	if verts.is_empty():
		return []
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	return arrays


static func to_mesh(arrays: Array) -> ArrayMesh:
	if arrays.is_empty():
		return null
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, material())
	return mesh


static func _flat(v: PackedVector3Array, n: PackedVector3Array, c: PackedColorArray, q: PackedVector2Array, y: float,
		col: Color) -> void:
	var idx := Geometry2D.triangulate_polygon(q)
	for k in range(0,idx.size(),3):
		var a := Vector3(q[idx[k]].x,y,q[idx[k]].y)
		var b := Vector3(q[idx[k+1]].x,y,q[idx[k+1]].y)
		var d := Vector3(q[idx[k+2]].x,y,q[idx[k+2]].y)
		var order := [a,b,d] if (b-a).cross(d-a).y<0.0 else [a,d,b]
		for p in order:
			v.append(p);n.append(Vector3.UP);c.append(Color(col.r,col.g,col.b,.6))


static func _box(v: PackedVector3Array, n: PackedVector3Array, c: PackedColorArray, t: Transform3D, mn: Vector3,
		mx: Vector3, col: Color) -> void:
	var p := [
		Vector3(mn.x, mn.y, mn.z), Vector3(mx.x, mn.y, mn.z), Vector3(mx.x, mn.y, mx.z), Vector3(mn.x, mn.y, mx.z),
		Vector3(mn.x, mx.y, mn.z), Vector3(mx.x, mx.y, mn.z), Vector3(mx.x, mx.y, mx.z), Vector3(mn.x, mx.y, mx.z)]
	# Quads are listed counter-clockwise seen from outside; triangles are
	# emitted reversed because Godot's front faces are clockwise.
	var quads := [[4, 7, 6, 5], [3, 7, 4, 0], [1, 5, 6, 2], [0, 4, 5, 1], [2, 6, 7, 3]]
	for q in quads:
		var w := [t * (p[q[0]] as Vector3), t * (p[q[1]] as Vector3), t * (p[q[2]] as Vector3), t * (p[q[3]] as Vector3)]
		var normal: Vector3 = ((w[1] - w[0]).cross(w[2] - w[0])).normalized()
		for i in [0, 2, 1, 0, 3, 2]:
			v.append(w[i])
			n.append(normal)
			c.append(col)

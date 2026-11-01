class_name FarCityBuilder
extends RefCounted
## Distant-city LOD: per chunk, one box per building (facade tone from the
## catalogue, procedural windows in the shader), plain block pavements and
## backdrop districts. About 10 triangles per building, so the whole province
## can stay resident and the horizon is always a city, never empty ground.

const SHADER := preload("res://src/world/shaders/far_building.gdshader")
const PAVEMENT := Color(0.6, 0.58, 0.54)

static var _material: ShaderMaterial


static func material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = SHADER
		_material.set_shader_parameter("noise_tex", load("res://assets/textures/grime_noise.png"))
	return _material


static func build_chunk(world: WorldLayout, key: Vector2i, catalog: Dictionary) -> ArrayMesh:
	var c: Dictionary = world.chunk(key)
	if c.is_empty():
		return null
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	for bi in c["blocks"]:
		var b: Dictionary = world.blocks[bi]
		if b["sidewalks"]:
			_flat(verts, normals, colors, b["rect"], world.curb_height, PAVEMENT)
	for li in c["lots"]:
		var lot: Dictionary = world.lots[li]
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
		return null
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, material())
	return mesh


static func _flat(v: PackedVector3Array, n: PackedVector3Array, c: PackedColorArray, r: Rect2, y: float, col: Color) -> void:
	var a := Vector3(r.position.x, y, r.position.y)
	var b := Vector3(r.end.x, y, r.position.y)
	var cc := Vector3(r.end.x, y, r.end.y)
	var d := Vector3(r.position.x, y, r.end.y)
	var pav := Color(col.r, col.g, col.b, 0.6)
	for p in [a, b, cc, a, cc, d]:
		v.append(p)
		n.append(Vector3.UP)
		c.append(pav)


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

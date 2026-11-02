class_name TerrainMesh
extends RefCounted
## Indexed heightfield tiles with world-space samples and local vertices.
## Skirts hide mixed-LOD edges; same-LOD shared vertices/normals are identical.
const TILE := 1024.0
const SHADER := preload("res://src/world/shaders/terrain.gdshader")
static var _material: ShaderMaterial

static func material() -> ShaderMaterial:
	if _material==null:
		_material=ShaderMaterial.new()
		_material.shader=SHADER
		for pair in [["grass_tex","grass"],["dirt_tex","dirt"],["sand_tex","sand"],["rock_tex","rock"],["mud_tex","mud"]]:
			_material.set_shader_parameter(pair[0],load("res://assets/textures/terrain_%s_albedo.png"%pair[1]))
		_material.set_shader_parameter("ground_normal",load("res://assets/textures/terrain_grass_normal.png"))
	return _material

static func arrays(field: TerrainField, key: Vector2i, step: int) -> Array:
	var n := int(TILE)/step
	var origin := Vector2(key)*TILE
	var samples := []
	for z in range(-1,n+2):
		for x in range(-1,n+2):
			samples.append(field.sample(origin+Vector2(x*step,z*step)))
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uv := PackedVector2Array()
	var tangents := PackedFloat32Array()
	var indices := PackedInt32Array()
	for z in n+1:
		for x in n+1:
			var si := (z+1)*(n+3)+x+1
			var v: Vector4 = samples[si]
			vertices.append(Vector3(x*step,v.x,z*step))
			var dx := float(samples[si+1].x-samples[si-1].x)/(step*2.0)
			var dz := float(samples[si+n+3].x-samples[si-n-3].x)/(step*2.0)
			normals.append(Vector3(-dx,1,-dz).normalized())
			tangents.append_array([1.0,dx,0.0,1.0])
			colors.append(Color(clampf(v.y/192.0,0,1),v.z,0,clampf(v.w/90.0,0,1)))
			uv.append((origin+Vector2(x*step,z*step))/7.0)
	for z in n:
		for x in n:
			var a := z*(n+1)+x
			indices.append_array([a,a+1,a+n+2,a,a+n+2,a+n+1])
	# Border skirts need no independent height queries. They stay underground.
	var border := []
	for x in n+1:border.append(x)
	for z in range(1,n+1):border.append(z*(n+1)+n)
	for x in range(n-1,-1,-1):border.append(n*(n+1)+x)
	for z in range(n-1,0,-1):border.append(z*(n+1))
	for i in border.size():
		var ai: int=border[i]
		var bi: int=border[(i+1)%border.size()]
		var base := vertices.size()
		for idx in [ai,bi]:
			vertices.append(vertices[idx]-Vector3.UP*7.0)
			normals.append(normals[idx]);colors.append(colors[idx]);uv.append(uv[idx])
			tangents.append_array([1.0,0.0,0.0,1.0])
		indices.append_array([ai,base,base+1,ai,base+1,bi])
	var result := []
	result.resize(Mesh.ARRAY_MAX)
	result[Mesh.ARRAY_VERTEX]=vertices;result[Mesh.ARRAY_NORMAL]=normals
	result[Mesh.ARRAY_COLOR]=colors;result[Mesh.ARRAY_TEX_UV]=uv
	result[Mesh.ARRAY_TANGENT]=tangents;result[Mesh.ARRAY_INDEX]=indices
	return result

static func instance(data: Array, key: Vector2i) -> MeshInstance3D:
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,data)
	mesh.surface_set_material(0,material())
	var mi := MeshInstance3D.new()
	mi.mesh=mesh;mi.position=Vector3(key.x*TILE,0,key.y*TILE)
	mi.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi

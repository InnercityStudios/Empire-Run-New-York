class_name VehicleMeshes
extends RefCounted
## Vehicle meshes prepared for the two ways cars are drawn:
## - `single`: one MeshInstance3D per car, paint set with the "tint" instance uniform.
## - `instanced`: MultiMesh batches, paint read from per-instance custom data.

static var _instanced: Dictionary = {}
static var _rim: ShaderMaterial


## Expands a weighted [kind, weight] mix into a pick list.
static func weighted(mix: Array) -> Array:
	var out := []
	for entry in mix:
		for i in int(entry[1]):
			out.append(entry[0])
	return out


static func is_tintable(kind: String) -> bool:
	return bool(Content.db.vehicles.get(kind, {}).get("tintable", false))


## Shared additive rim overlay used to highlight selected vehicles.
static func rim_overlay() -> ShaderMaterial:
	if _rim == null:
		_rim = ShaderMaterial.new()
		_rim.shader = preload("res://src/world/shaders/selection_rim.gdshader")
	return _rim


static func single(kind: String) -> ArrayMesh:
	return AssetLibrary.vehicle_mesh(kind)


static func instanced(kind: String) -> ArrayMesh:
	if _instanced.has(kind):
		return _instanced[kind]
	var src := AssetLibrary.vehicle_mesh(kind)
	if src == null:
		return null
	var mesh := src.duplicate() as ArrayMesh
	for i in mesh.get_surface_count():
		var mat_name := Materials.material_name_of(src.surface_get_material(i))
		# Licensed models keep their own PBR materials (no per-instance tint).
		if mat_name != "":
			mesh.surface_set_material(i, Materials.get_instanced_material(mat_name))
	_instanced[kind] = mesh
	return mesh

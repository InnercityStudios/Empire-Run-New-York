class_name VehicleMeshes
extends RefCounted
## Vehicle meshes prepared for the two ways cars are drawn:
## - `single`: one MeshInstance3D per car, paint set with the "tint" instance uniform.
## - `instanced`: MultiMesh batches, paint read from per-instance custom data.

static var _instanced: Dictionary = {}


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
		mesh.surface_set_material(i, Materials.get_instanced_material(mat_name))
	_instanced[kind] = mesh
	return mesh

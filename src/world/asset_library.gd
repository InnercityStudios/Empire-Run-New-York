class_name AssetLibrary
extends RefCounted
## Loads pipeline GLBs once and returns their mesh with shared library materials.

const BUILDING_DIR := "res://assets/models/buildings/"
const PROP_DIR := "res://assets/models/props/"
const VEHICLE_DIR := "res://assets/models/vehicles/"

static var _meshes: Dictionary = {}


static func building_mesh(id: String) -> ArrayMesh:
	return mesh_at(BUILDING_DIR + id + ".glb")


static func prop_mesh(id: String) -> ArrayMesh:
	return mesh_at(PROP_DIR + id + ".glb")


## Vehicle mesh by content id (data/defs/units.json), falling back to the
## procedural model of the same name.
static func vehicle_mesh(id: String) -> ArrayMesh:
	var def: Dictionary = Content.db.vehicles.get(id, {})
	return mesh_at(def.get("model", VEHICLE_DIR + id + ".glb"))


## Mesh of the first MeshInstance3D in a GLB scene, with materials remapped.
static func mesh_at(path: String) -> ArrayMesh:
	if _meshes.has(path):
		return _meshes[path]
	var mesh: ArrayMesh = null
	var scene := load(path) as PackedScene
	if scene == null:
		push_error("AssetLibrary: cannot load %s" % path)
	else:
		var root := scene.instantiate()
		var mi := _find_mesh_instance(root)
		if mi and mi.mesh is ArrayMesh:
			mesh = mi.mesh
			Materials.apply_to_mesh(mesh)
		else:
			push_error("AssetLibrary: no mesh in %s" % path)
		root.free()
	_meshes[path] = mesh
	return mesh


static func _find_mesh_instance(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D:
		return n
	for c in n.get_children():
		var r := _find_mesh_instance(c)
		if r:
			return r
	return null

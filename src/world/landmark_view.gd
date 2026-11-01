class_name LandmarkView
extends Node3D
## A selectable world building (headquarters or business) on the city map.
##
## Rendering only: gameplay state lives in the simulation and is looked up by
## the landmark id.

var landmark_id: String
var building_id: String
var size := Vector3(10, 15, 20)  ## width, height, depth (footprint extends to -Z)
var frontage := Vector3.ZERO     ## street-centreline point in front of the entrance
var out_dir := Vector3.BACK      ## unit vector from the facade toward the street
var mesh_instance: MeshInstance3D
var surface_names: PackedStringArray = []
var _highlight := 0.0
var _tween: Tween


func setup(id: String, info: Dictionary) -> void:
	landmark_id = id
	building_id = info["building"]
	name = id
	transform = info["transform"]
	size = Vector3(info["width"], info["height"], info["depth"])
	var f: Vector2 = info["frontage"]
	frontage = Vector3(f.x, 0.0, f.y)
	var o: Vector2 = info["out"]
	out_dir = Vector3(o.x, 0, o.y)
	mesh_instance = MeshInstance3D.new()
	mesh_instance.name = "Mesh"
	mesh_instance.mesh = AssetLibrary.building_mesh(building_id)
	add_child(mesh_instance)
	if mesh_instance.mesh:
		for i in mesh_instance.mesh.get_surface_count():
			surface_names.append(Materials.material_name_of(mesh_instance.mesh.surface_get_material(i)))


## World-space anchor above the roofline for UI markers.
func marker_anchor() -> Vector3:
	return global_transform * Vector3(0, size.y + 3.0, -size.z * 0.35)


## Point on the sidewalk in front of the entrance.
func entrance_point() -> Vector3:
	return global_transform * Vector3(0, 0, 2.0)


func world_aabb() -> AABB:
	var local := AABB(Vector3(-size.x * 0.5, 0, -size.z), size)
	return global_transform * local


## Ray hit distance against the building footprint box, or -1.
func ray_hit(origin: Vector3, dir: Vector3) -> float:
	var inv := global_transform.affine_inverse()
	var lo := inv * origin
	var ld := (inv.basis * dir)
	var box := AABB(Vector3(-size.x * 0.5, 0, -size.z), size)
	var hit: Variant = box.intersects_ray(lo, ld)
	if hit == null:
		return -1.0
	return origin.distance_to(global_transform * (hit as Vector3))


func set_highlighted(on: bool) -> void:
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_method(_apply_highlight, _highlight, 1.0 if on else 0.0, 0.25)


func _apply_highlight(v: float) -> void:
	_highlight = v
	if mesh_instance:
		mesh_instance.set_instance_shader_parameter("highlight", v * 0.14)

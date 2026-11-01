class_name OcclusionFader
extends Node
## Keeps tracked crews visible behind buildings.
##
## Up to two world targets (selected and followed crew) are published as
## global shader parameters. Only chunks whose bounds cross the camera-target
## sightline get the cutout material variant, which dithers away the part of
## the building in front of the crew. Other chunks keep the cheaper opaque
## materials (alpha-tested shaders are costly on mobile tile-based GPUs).

const MAX_TARGETS := 2
const GLOBALS := ["occl_target_0", "occl_target_1"]

var world: CityWorld
var camera: Camera3D
var targets: Array = []   ## Array[Callable] returning Vector3, or null
var _cut: Dictionary = {} ## chunk index -> true while using cutout materials


func _process(_delta: float) -> void:
	if world == null or camera == null:
		return
	var cam := camera.global_position
	var active: Array = []
	for i in MAX_TARGETS:
		var value := Vector4.ZERO
		if i < targets.size() and targets[i] is Callable and (targets[i] as Callable).is_valid():
			var p: Variant = (targets[i] as Callable).call()
			if p is Vector3:
				var radius := 5.0 + cam.distance_to(p) * 0.045
				value = Vector4(p.x, p.y + 1.0, p.z, radius)
				active.append([p + Vector3(0, 1.0, 0), radius])
		RenderingServer.global_shader_parameter_set(GLOBALS[i], value)
	var want := {}
	for t in active:
		var target: Vector3 = t[0]
		for ci in world.chunks.size():
			var chunk: Dictionary = world.chunks[ci]
			var inst: MeshInstance3D = chunk["instance"]
			var aabb: AABB = inst.global_transform * (chunk["aabb"] as AABB)
			if aabb.grow(t[1]).intersects_segment(cam, target):
				want[ci] = true
	for ci in want:
		if not _cut.has(ci):
			_set_cutout(ci, true)
	for ci in _cut.keys():
		if not want.has(ci):
			_set_cutout(ci, false)
	_cut = want


func _set_cutout(ci: int, on: bool) -> void:
	var chunk: Dictionary = world.chunks[ci]
	var inst: MeshInstance3D = chunk["instance"]
	var names: PackedStringArray = chunk["names"]
	for s in names.size():
		inst.set_surface_override_material(s, Materials.get_cutout_material(names[s]) if on else null)

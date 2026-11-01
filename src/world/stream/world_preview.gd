@tool
class_name WorldPreview
extends Node3D
## Editor inspection of the streamed world. Builds the world shell, the far
## city for the whole province and full detail around `focus`, directly in the
## Godot editor (open scenes/world/world_preview.tscn). Toggle `rebuild` after
## changing data or assets. Not used at runtime.

@export var focus := Vector2(-80, 0)
@export_range(0.0, 900.0, 10.0) var detail_radius := 260.0
@export var show_far_city := true
@export var rebuild := false:
	set(v):
		if v and is_inside_tree():
			_rebuild()

var stats := {}


func _ready() -> void:
	if Engine.is_editor_hint():
		_rebuild()


func _rebuild() -> void:
	for c in get_children():
		c.queue_free()
	var t0 := Time.get_ticks_msec()
	var content := GameContent.load_default()
	var layout := WorldLayout.build(content.worlds["greater_new_york"], content)
	var shell := Node3D.new()
	shell.name = "Shell"
	add_child(shell)
	WorldShellBuilder.build(layout, shell)
	var lots := 0
	for key in layout.chunk_keys():
		var dist := layout.chunk_rect(key).get_center().distance_to(focus)
		if dist <= detail_radius:
			var r := ChunkDetailBuilder.build(layout, key)
			var built := ChunkDetailBuilder.to_mesh(r["surfaces"])
			if built["mesh"]:
				var mi := MeshInstance3D.new()
				mi.name = "Detail_%d_%d" % [key.x, key.y]
				mi.mesh = built["mesh"]
				add_child(mi)
				lots += int(r["lots"])
		elif show_far_city:
			var far := FarCityBuilder.build_chunk(layout, key, content.building_catalog)
			if far:
				var fm := MeshInstance3D.new()
				fm.name = "Far_%d_%d" % [key.x, key.y]
				fm.mesh = far
				add_child(fm)
	for id in layout.landmarks:
		var lv := LandmarkView.new()
		add_child(lv)
		lv.setup(id, layout.landmarks[id])
	stats = {"regions": layout.regions.size(), "lots": layout.lots.size(), "detail_lots": lots,
		"build_ms": Time.get_ticks_msec() - t0}
	print("WorldPreview: ", stats)

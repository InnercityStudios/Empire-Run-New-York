class_name CityWorld
extends Node3D
## Renders a district: roads, merged block chunks, landmarks and parked cars.
##
## Each block (buildings + sidewalk + street furniture) is merged into one mesh
## with one surface per material, which keeps draw calls to roughly a dozen per
## visible block and gives the renderer per-block frustum culling.

signal built

var layout: DistrictLayout
var landmarks: Dictionary = {}  ## landmark id -> LandmarkView
var chunks: Array = []          ## {instance: MeshInstance3D, names: PackedStringArray, aabb: AABB}
var stats := {"buildings": 0, "props": 0, "parked": 0, "chunks": 0, "build_ms": 0}


func build(p_layout: DistrictLayout) -> void:
	var t0 := Time.get_ticks_msec()
	layout = p_layout
	var road := MeshInstance3D.new()
	road.name = "Roads"
	road.mesh = RoadBuilder.build_road_mesh(layout)
	road.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(road)
	_build_chunks()
	_build_landmarks()
	_build_parked_cars()
	stats["build_ms"] = Time.get_ticks_msec() - t0
	print("CityWorld: %d buildings, %d props, %d parked cars in %d chunks (%d ms)" % [
		stats["buildings"], stats["props"], stats["parked"], stats["chunks"], stats["build_ms"]])
	built.emit()


func _build_chunks() -> void:
	var per_block := {}
	for lot in layout.lots:
		if lot["landmark"] != "":
			continue
		per_block[lot["block"]] = per_block.get(lot["block"], []) + [lot]
	var props_by_block := {}
	for p in layout.props:
		props_by_block[p["block"]] = props_by_block.get(p["block"], []) + [p]
	var root := Node3D.new()
	root.name = "Blocks"
	add_child(root)
	for bi in layout.blocks.size():
		var block: Dictionary = layout.blocks[bi]
		var tools := {}
		RoadBuilder.add_sidewalk(tools, block["rect"], layout.curb_height, layout.corner_radius)
		var merged := {}
		for lot in per_block.get(bi, []):
			_append_mesh(merged, AssetLibrary.building_mesh(lot["building"]), lot["transform"])
			stats["buildings"] += 1
		for p in props_by_block.get(bi, []):
			_append_mesh(merged, AssetLibrary.prop_mesh(p["prop"]), p["transform"])
			stats["props"] += 1
		var mesh := ArrayMesh.new()
		var names := PackedStringArray()
		for mat_name in merged:
			(merged[mat_name] as SurfaceTool).commit(mesh)
			names.append(mat_name)
		for mat_name in tools:
			var st: SurfaceTool = tools[mat_name]
			st.generate_tangents()
			st.commit(mesh)
			names.append(mat_name)
		for i in names.size():
			mesh.surface_set_material(i, Materials.get_material(names[i]))
		var mi := MeshInstance3D.new()
		mi.name = "Block_%d_%d" % [block["col"], block["row"]]
		mi.mesh = mesh
		root.add_child(mi)
		chunks.append({"instance": mi, "names": names, "aabb": mesh.get_aabb()})
	stats["chunks"] = chunks.size()


func _append_mesh(merged: Dictionary, mesh: ArrayMesh, xform: Transform3D) -> void:
	if mesh == null:
		return
	for s in mesh.get_surface_count():
		var mat_name := Materials.material_name_of(mesh.surface_get_material(s))
		if not merged.has(mat_name):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			merged[mat_name] = st
		(merged[mat_name] as SurfaceTool).append_from(mesh, s, xform)


func _build_landmarks() -> void:
	var root := Node3D.new()
	root.name = "Landmarks"
	add_child(root)
	for id in layout.landmarks:
		var lv := LandmarkView.new()
		root.add_child(lv)
		lv.setup(id, layout.landmarks[id])
		landmarks[id] = lv
		chunks.append({"instance": lv.mesh_instance, "names": lv.surface_names, "aabb": lv.mesh_instance.mesh.get_aabb()})


func _build_parked_cars() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = layout.seed_value + 77
	var kinds := ["sedan_black", "sedan_black", "sedan_black", "taxi", "box_truck"]
	var buckets := {}
	for spot in layout.parking:
		var kind: String = kinds[rng.randi() % kinds.size()]
		buckets[kind] = buckets.get(kind, []) + [spot["transform"]]
	var paints: Array = Content.db.traffic_paints
	for kind in buckets:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = VehicleMeshes.instanced(kind)
		var list: Array = buckets[kind]
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, list[i])
			var tint := Color.html(paints[rng.randi() % paints.size()]) if kind == "sedan_black" else Color.WHITE
			mm.set_instance_custom_data(i, tint)
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Parked_" + kind
		mmi.multimesh = mm
		add_child(mmi)
		stats["parked"] += list.size()


## Closest landmark hit by a world-space ray, or "".
func pick_landmark(origin: Vector3, dir: Vector3) -> String:
	var best := ""
	var best_d := INF
	for id in landmarks:
		var d: float = (landmarks[id] as LandmarkView).ray_hit(origin, dir)
		if d >= 0.0 and d < best_d:
			best_d = d
			best = id
	return best

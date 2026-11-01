class_name WorldStreamer
extends Node3D
## Streams a WorldLayout around the camera.
##
## Always resident (cheap): the world shell (water, land, roads, bridge,
## park lakes) and the far-city LOD for every chunk. Streamed: full-detail
## chunks inside a zoom-dependent radius, built on worker threads and swapped
## in over their far LOD; unloaded with hysteresis. Landmarks (gameplay
## buildings) are always present.
##
## Public surface matches what the camera, crews, markers and occlusion fader
## need: `layout`, `landmarks`, `chunks`, `pick_landmark()`.

signal built
signal initial_detail_ready

const MAX_TASKS := 3
const MAX_APPLY_PER_FRAME := 2
const HYSTERESIS := 120.0
## Full detail is for close play: the radius shrinks as the camera climbs and
## the strategic view is pure far city (one box per building) plus landmarks.
const DETAIL_MAX := 220.0
const DETAIL_CUTOFF := 60.0

@export var detail_enabled := true

var layout: WorldLayout
var landmarks: Dictionary = {}
var chunks: Dictionary = {}          ## loaded detail + landmarks: key -> {instance, names, aabb}
var camera: StrategyCamera
var stats := {"build_ms": 0, "far_chunks": 0, "detail_loaded": 0, "detail_built": 0, "detail_ms_total": 0}

var _far: Dictionary = {}            ## chunk key -> Node3D
var _detail: Dictionary = {}         ## chunk key -> Node3D
var _tasks: Dictionary = {}          ## chunk key -> WorkerThreadPool task id
var _results: Array = []
var _mutex := Mutex.new()
var _initial_signalled := false
var _detail_root: Node3D
var _tree_mesh: ArrayMesh
var _tree_far_mesh: ArrayMesh


func build(p_layout: WorldLayout) -> void:
	var t0 := Time.get_ticks_msec()
	layout = p_layout
	_prewarm()
	var shell := Node3D.new()
	shell.name = "Shell"
	add_child(shell)
	stats.merge(WorldShellBuilder.build(layout, shell), true)
	var far_root := Node3D.new()
	far_root.name = "FarCity"
	add_child(far_root)
	for key in layout.chunk_keys():
		var node := Node3D.new()
		node.name = "Far_%d_%d" % [key.x, key.y]
		far_root.add_child(node)
		var mesh := FarCityBuilder.build_chunk(layout, key, Content.db.building_catalog)
		if mesh:
			var mi := MeshInstance3D.new()
			mi.mesh = mesh
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			node.add_child(mi)
		var trees: Array = layout.chunk(key)["trees"]
		if not trees.is_empty():
			node.add_child(_tree_multimesh(trees, _tree_far_mesh, false))
		_far[key] = node
	stats["far_chunks"] = _far.size()
	_detail_root = Node3D.new()
	_detail_root.name = "Detail"
	add_child(_detail_root)
	_build_landmarks()
	stats["build_ms"] = Time.get_ticks_msec() - t0
	print("WorldStreamer: %d chunks, %d road meshes, shell + far city in %d ms" % [
		_far.size(), stats.get("road_chunks", 0), stats["build_ms"]])
	built.emit()


## Load every asset and material on the main thread so worker threads only
## read immutable caches.
func _prewarm() -> void:
	for id in Content.db.building_catalog:
		AssetLibrary.building_mesh(id)
	for prop in ["street_lamp", "traffic_signal", "fire_hydrant", "mailbox", "trash_can", "newspaper_box", "tree_a",
			"tree_b", "tree_far", "subway_entrance", "bus_stop", "phone_booth", "newsstand", "trash_pile", "parking_meter"]:
		AssetLibrary.prop_mesh(prop)
	for mat_name in Materials.all_names():
		Materials.get_material(mat_name)
	_tree_mesh = AssetLibrary.prop_mesh("tree_a")
	_tree_far_mesh = AssetLibrary.prop_mesh("tree_far")


func _build_landmarks() -> void:
	var root := Node3D.new()
	root.name = "Landmarks"
	add_child(root)
	for id in layout.landmarks:
		var lv := LandmarkView.new()
		root.add_child(lv)
		lv.setup(id, layout.landmarks[id])
		landmarks[id] = lv
		chunks["landmark:" + id] = {"instance": lv.mesh_instance, "names": lv.surface_names,
			"aabb": lv.mesh_instance.mesh.get_aabb()}


# --- Streaming --------------------------------------------------------------------------
func _process(_delta: float) -> void:
	if layout == null or camera == null or not detail_enabled or QualityFlags.off("detail"):
		return
	var focus := Vector2(camera.focus.x, camera.focus.z)
	var radius := detail_radius(camera.distance)
	_apply_results()
	# Unload far-away detail.
	for key in _detail.keys():
		if radius == 0.0 or _chunk_distance(key, focus) > radius + HYSTERESIS:
			_unload(key)
	# Request missing chunks, nearest first.
	var wanted: Array = []
	var cr := int(ceil(radius / layout.chunk_size)) + 1
	var center := layout.chunk_of(focus)
	for dx in range(-cr, cr + 1):
		for dz in range(-cr, cr + 1):
			var key := center + Vector2i(dx, dz)
			if not _far.has(key) or _detail.has(key) or _tasks.has(key):
				continue
			var d := _chunk_distance(key, focus)
			if d <= radius:
				wanted.append([d, key])
	wanted.sort_custom(func(a, b): return a[0] < b[0])
	for w in wanted:
		if _tasks.size() >= MAX_TASKS:
			break
		var key: Vector2i = w[1]
		_tasks[key] = WorkerThreadPool.add_task(_build_task.bind(key), false, "chunk %s" % key)
	if not _initial_signalled and wanted.is_empty() and _tasks.is_empty() and (not _detail.is_empty() or radius == 0.0):
		_initial_signalled = true
		initial_detail_ready.emit()


static func detail_radius(camera_distance: float) -> float:
	var r := clampf(260.0 - camera_distance * 0.6, 0.0, DETAIL_MAX)
	return r if r >= DETAIL_CUTOFF else 0.0


func pending_count() -> int:
	return _tasks.size() + _results.size()


func _chunk_distance(key: Vector2i, p: Vector2) -> float:
	var r := layout.chunk_rect(key)
	var q := Vector2(clampf(p.x, r.position.x, r.end.x), clampf(p.y, r.position.y, r.end.y))
	return q.distance_to(p)


func _build_task(key: Vector2i) -> void:
	var t := Time.get_ticks_usec()
	var result := ChunkDetailBuilder.build(layout, key)
	result["ms"] = (Time.get_ticks_usec() - t) / 1000
	_mutex.lock()
	_results.append(result)
	_mutex.unlock()


func _apply_results() -> void:
	for key in _tasks.keys():
		if WorkerThreadPool.is_task_completed(_tasks[key]):
			WorkerThreadPool.wait_for_task_completion(_tasks[key])
			_tasks.erase(key)
	_mutex.lock()
	var ready := _results.slice(0, MAX_APPLY_PER_FRAME)
	_results = _results.slice(MAX_APPLY_PER_FRAME)
	_mutex.unlock()
	for r in ready:
		_attach(r)


func _attach(r: Dictionary) -> void:
	var key: Vector2i = r["key"]
	if _detail.has(key):
		return
	var root := Node3D.new()
	root.name = "Detail_%d_%d" % [key.x, key.y]
	_detail_root.add_child(root)
	var built := ChunkDetailBuilder.to_mesh(r["surfaces"])
	if OS.get_cmdline_user_args().has("--debug-chunks"):
		for sf in r["surfaces"]:
			var a: Array = sf[1]
			print("CHUNK %s %s v=%d n=%s t=%s uv=%s c=%s i=%d" % [key, sf[0], (a[0] as PackedVector3Array).size(),
				str(a[1] != null and (a[1] as PackedVector3Array).size()), str(a[2] != null), str(a[4] != null), str(a[3] != null),
				(a[12] as PackedInt32Array).size() if a[12] != null else -1])
		print("CHUNK %s mesh surfaces=%d aabb=%s" % [key, built["mesh"].get_surface_count() if built["mesh"] else 0, built["mesh"].get_aabb() if built["mesh"] else AABB()])
	if built["mesh"]:
		var mi := MeshInstance3D.new()
		mi.mesh = built["mesh"]
		root.add_child(mi)
		chunks["detail:%d,%d" % [key.x, key.y]] = {"instance": mi, "names": built["names"],
			"aabb": (built["mesh"] as Mesh).get_aabb()}
	if not r["trees"].is_empty():
		root.add_child(_tree_multimesh(r["trees"], _tree_mesh, true))
	if not r["parked"].is_empty():
		_add_parked(root, r["parked"], key)
	_detail[key] = root
	if _far.has(key):
		(_far[key] as Node3D).visible = false
	stats["detail_loaded"] = _detail.size()
	stats["detail_built"] += 1
	stats["detail_ms_total"] += int(r.get("ms", 0))
	stats["detail_tris_max"] = maxi(int(stats.get("detail_tris_max", 0)), int(r.get("tris", 0)))
	stats["detail_ms_max"] = maxi(int(stats.get("detail_ms_max", 0)), int(r.get("ms", 0)))


func _unload(key: Vector2i) -> void:
	var node: Node3D = _detail[key]
	node.queue_free()
	_detail.erase(key)
	chunks.erase("detail:%d,%d" % [key.x, key.y])
	if _far.has(key):
		(_far[key] as Node3D).visible = true
	stats["detail_loaded"] = _detail.size()


func _tree_multimesh(points: Array, mesh: Mesh, is_transforms: bool) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = points.size()
	for i in points.size():
		if is_transforms:
			mm.set_instance_transform(i, points[i])
		else:
			var p: Vector2 = points[i]
			var h := hash(Vector2i(roundi(p.x * 10), roundi(p.y * 10)))
			var s := 0.8 + float(h % 1000) / 2500.0
			mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3(s, s, s)), Vector3(p.x, 0.0, p.y)))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if is_transforms else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mmi


func _add_parked(root: Node3D, spots: Array, key: Vector2i) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([layout.seed_value, key])
	var kinds := VehicleMeshes.weighted(Content.db.vehicle_mix("parked_mix"))
	var paints: Array = Content.db.traffic_paints
	var buckets := {}
	for spot in spots:
		var kind: String = kinds[rng.randi() % kinds.size()]
		buckets[kind] = buckets.get(kind, []) + [spot["transform"]]
	for kind in buckets:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = VehicleMeshes.instanced(kind)
		var list: Array = buckets[kind]
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, list[i])
			mm.set_instance_custom_data(i, Color.html(paints[rng.randi() % paints.size()]) if VehicleMeshes.is_tintable(kind) else Color.WHITE)
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		root.add_child(mmi)


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

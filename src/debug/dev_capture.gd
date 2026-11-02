extends Node
## Autoload "DevCapture": scripted screenshots for automated visual checks.
##
## Inactive unless user arguments are passed after "--":
##   --capture=<png path>       save a screenshot and quit
##   --capture-delay=<seconds>  wait before capturing (default 3)
##   --view=x,z,distance,yaw    camera placement
##   --select=<landmark|crew>   select an entity before capturing
##   --command=<json>           run a game command once the world is ready
##   --stats                    print rendering statistics with the capture

signal capture_saved(path: String)

var _args := {}


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		_args[kv[0]] = kv[1] if kv.size() > 1 else ""
	if not _args.has("capture"):
		set_process(false)
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Measurements must be like-for-like: never inherit a maximised window.
	var size := Vector2i(1600, 900)
	if _args.has("size"):
		var wh := (_args["size"] as String).split("x")
		size = Vector2i(int(wh[0]), int(wh[1]))
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(size)
	await get_tree().create_timer(0.2).timeout
	_apply_setup()
	await get_tree().create_timer(float(_args.get("capture-delay", "3"))).timeout
	if _args.has("benchmark"):
		await _benchmark(float(_args["benchmark"]))
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path: String = _args["capture"]
	var err := img.save_png(path)
	print("DevCapture: saved %s (%dx%d) err=%d" % [path, img.get_width(), img.get_height(), err])
	if _args.has("stats"):
		print("DevCapture: fps=%d draw_calls=%d primitives=%d objects=%d vram_mb=%.1f" % [
			Engine.get_frames_per_second(),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) / 1048576.0])
		var main := get_tree().get_first_node_in_group("main")
		if main and "world" in main and main.world is WorldStreamer:
			var w: WorldStreamer = main.world
			if w._terrain_streamer:
				print("DevCapture: terrain ",w._terrain_streamer.stats," pending=",w._terrain_streamer.tasks.size())
			print("DevCapture: streamer ", w.stats, " pending=", w.pending_count(),
				" camera_distance=%.0f radius=%.0f" % [w.camera.distance, WorldStreamer.detail_radius(w.camera.distance)])
	var main := get_tree().get_first_node_in_group("main")
	if main and main.get("world") and main.world.get("stats") != null:
		print("DevCapture: WorldStreamer stats ", main.world.stats)
	capture_saved.emit(path)
	get_tree().quit()


## Uncapped frame-time sampling (vsync off) for comparable performance numbers.
func _benchmark(seconds: float) -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	for i in 30:
		await get_tree().process_frame
	var vp_rid := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp_rid, true)
	var gpu_total := 0.0
	var cpu_total := 0.0
	var times: Array[float] = []
	var draw_calls := 0
	var prims := 0
	var start := Time.get_ticks_usec()
	var last := start
	while Time.get_ticks_usec() - start < seconds * 1_000_000.0:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		times.append((now - last) / 1000.0)
		last = now
		gpu_total += RenderingServer.viewport_get_measured_render_time_gpu(vp_rid)
		cpu_total += RenderingServer.viewport_get_measured_render_time_cpu(vp_rid)
		draw_calls = maxi(draw_calls, RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
		prims = maxi(prims, RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))
	times.sort()
	var avg := 0.0
	for t in times:
		avg += t
	avg /= maxf(times.size(), 1)
	print("DevCapture: GPU avg_gpu_ms=%.2f avg_render_cpu_ms=%.2f" % [gpu_total / maxf(times.size(), 1), cpu_total / maxf(times.size(), 1)])
	print("DevCapture: BENCH frames=%d avg_ms=%.2f p50_ms=%.2f p95_ms=%.2f p99_ms=%.2f max_draw_calls=%d max_primitives=%d vram_mb=%.1f static_mem_mb=%.1f" % [
		times.size(), avg, times[times.size() / 2], times[int(times.size() * 0.95)], times[int(times.size() * 0.99)],
		draw_calls, prims, RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) / 1048576.0,
		OS.get_static_memory_usage() / 1048576.0])


func _apply_setup() -> void:
	# Measurements must not be disturbed by a mouse or trackpad over the window.
	var cam_node := get_tree().get_first_node_in_group("strategy_camera")
	if cam_node:
		cam_node.input_enabled = false
		cam_node.set_process_unhandled_input(false)
	if _args.has("view"):
		var p := (_args["view"] as String).split(",")
		var cam := get_tree().get_first_node_in_group("strategy_camera")
		if cam and p.size() >= 3:
			if _args.has("whole-world"):
				cam.max_distance = 50000.0
			var v := {"x": float(p[0]), "z": float(p[1]), "distance": float(p[2])}
			if p.size() >= 4:
				v["yaw_deg"] = float(p[3])
			cam.dev_set_view(v)
	if _args.has("command"):
		var cmd: Variant = JSON.parse_string(_args["command"])
		if cmd is Dictionary:
			print("DevCapture: command result ", Game.execute(cmd))
	if _args.has("select"):
		var main := get_tree().get_first_node_in_group("main")
		if main and main.has_method("dev_select"):
			main.dev_select(_args["select"])
	if _args.has("follow"):
		var main_node := get_tree().get_first_node_in_group("main")
		if main_node and main_node.has_method("_set_follow"):
			main_node._set_follow(_args["follow"])

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
	await get_tree().create_timer(0.2).timeout
	_apply_setup()
	await get_tree().create_timer(float(_args.get("capture-delay", "3"))).timeout
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
	capture_saved.emit(path)
	get_tree().quit()


func _apply_setup() -> void:
	if _args.has("view"):
		var p := (_args["view"] as String).split(",")
		var cam := get_tree().get_first_node_in_group("strategy_camera")
		if cam and p.size() >= 3:
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

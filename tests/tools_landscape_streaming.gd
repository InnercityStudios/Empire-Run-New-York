extends SceneTree
## Integration smoke test: real main scene, simulation, terrain and city
## streamers, with rapid camera changes and strategic zoom. No GPU validation.
func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	if not OS.get_cmdline_user_args().has("--no-save"):
		push_error("Run this tool with -- --new-game --no-save")
		quit(2);return
	var scene := load("res://scenes/main.tscn") as PackedScene
	var main := scene.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	var world = main.world
	var camera = main.camera
	var terrain = world._terrain_streamer
	var failures := []
	for view in [Vector3(-80,0,110),Vector3(-5200,-6800,1100),Vector3(-2650,5720,800),Vector3(12500,-11500,1100),Vector3(400,-1700,3200)]:
		camera.dev_set_view({"x":view.x,"z":view.y,"distance":view.z})
		var start := Time.get_ticks_msec()
		while Time.get_ticks_msec()-start<8000:
			await create_timer(.05).timeout
			if terrain.tasks.size()>2:failures.append("terrain task limit exceeded")
			if Time.get_ticks_msec()-start>1500 and terrain.tasks.is_empty():break
		print("STREAM_VIEW ",view," terrain=",terrain.stats," terrain_pending=",terrain.tasks.size()," city_pending=",world.pending_count())
		if view.z<2400 and terrain.detail.is_empty():failures.append("no detailed terrain at "+str(view))
		if terrain.detail.size()>40:failures.append("terrain tiles did not unload")
		if root.get_node("Game").world==null:failures.append("simulation missing")
	if not terrain.detail.is_empty():failures.append("strategic zoom did not release detailed terrain")
	print("STREAMING_SMOKE: ","PASS" if failures.is_empty() else str(failures))
	main.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

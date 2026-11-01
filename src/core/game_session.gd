extends Node
## Autoload "Game": the client's game session.
##
## Owns the SimWorld, advances it with wall-clock time, routes player commands
## into it and fans its events out to presentation. In the online build this
## is the seam where commands go to the server and authoritative state comes
## back; views only ever talk to this object.

signal session_started
signal sim_event(event: Dictionary)
signal command_failed(cmd: Dictionary, error: String)

const SAVE_DIR := "user://saves"
const SAVE_PATH := "user://saves/slot_0.json"
const AUTOSAVE_INTERVAL_MS := 15_000

var world: SimWorld
var layout: WorldLayout
var player_id := ""
var _dirty := false
var _last_save_ms := 0


func now_ms() -> int:
	return int(Time.get_unix_time_from_system() * 1000.0)


## Sub-millisecond time for smooth interpolation in views.
func now_ms_f() -> float:
	return Time.get_unix_time_from_system() * 1000.0


func start(p_layout: WorldLayout) -> void:
	layout = p_layout
	var content: GameContent = Content.db
	var roads := SimBootstrap.roads_for(layout)
	var locations := SimBootstrap.landmark_locations(layout, roads)
	var fresh := "new-game" in OS.get_cmdline_user_args() or "--new-game" in OS.get_cmdline_user_args()
	if not fresh:
		world = _load(content, roads, locations)
	if world == null:
		world = SimWorld.create_new(content, roads, locations, content.scenarios["new_game"], now_ms())
		_dirty = true
	player_id = world.player_faction_id
	world.advance_to(now_ms())
	world.drain_events()
	session_started.emit()


func is_running() -> bool:
	return world != null


## Execute a command as the local player. Returns the simulation's result.
func execute(cmd: Dictionary) -> Dictionary:
	if world == null:
		return {"ok": false, "error": "not_ready"}
	var c := cmd.duplicate()
	c["faction"] = player_id
	world.advance_to(now_ms())
	var result := world.execute(c)
	_flush_events()
	if result.get("ok", false):
		_dirty = true
	else:
		command_failed.emit(c, result.get("error", "unknown"))
	return result


func restart() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	world = SimWorld.create_new(Content.db, world.roads, world.landmark_locations, Content.db.scenarios["new_game"], now_ms())
	player_id = world.player_faction_id
	_dirty = true
	session_started.emit()


func _process(_delta: float) -> void:
	if world == null:
		return
	world.advance_to(now_ms())
	_flush_events()
	if _dirty and Time.get_ticks_msec() - _last_save_ms > AUTOSAVE_INTERVAL_MS:
		save()


func _flush_events() -> void:
	for e in world.drain_events():
		if e["type"] in ["crew_arrived", "upgrade_complete", "business_acquired"]:
			_dirty = true
		sim_event.emit(e)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED \
			or what == NOTIFICATION_WM_GO_BACK_REQUEST:
		save()


func _exit_tree() -> void:
	save()


func save() -> void:
	if world == null:
		return
	_last_save_ms = Time.get_ticks_msec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SAVE_DIR))
	var data := {"district": layout.id, "saved_at_ms": now_ms(), "world": world.to_dict()}
	# Write to a temp file then rename so a crash never leaves a torn save.
	var tmp := SAVE_PATH + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_error("Game: cannot write save (%s)" % error_string(FileAccess.get_open_error()))
		return
	f.store_string(JSON.stringify(data))
	f.close()
	var err := DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), ProjectSettings.globalize_path(SAVE_PATH))
	if err != OK:
		push_error("Game: save rename failed (%s)" % error_string(err))
		return
	_dirty = false


func _load(content: GameContent, roads: RoadGraph, locations: Dictionary) -> SimWorld:
	if not FileAccess.file_exists(SAVE_PATH):
		return null
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if not parsed is Dictionary or not parsed.has("world"):
		push_warning("Game: ignoring incompatible save")
		return null
	var w := SimWorld.from_dict(parsed["world"], content, roads, locations, SimBootstrap.legacy_roads(content))
	if w == null:
		push_warning("Game: save version mismatch, starting a new game")
	return w

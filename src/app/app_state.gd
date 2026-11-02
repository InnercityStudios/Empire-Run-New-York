extends Node
## Autoload "App": the player-facing application around the game world.
##
## - Local player profile (username, crest, family identity). This is a LOCAL
##   MOCK: there is no online account, authentication or cloud save yet.
## - Settings persisted to user://settings.cfg and applied live (audio buses,
##   graphics quality, frame rate, haptics, gameplay options).
## - Launch intent for the game scene (new game or continue).
## - Title music that survives scene changes, scene fades and the Android /
##   Escape back-button stack used by every overlay.

signal settings_changed
signal profile_changed

const PROFILE_PATH := "user://profile.json"
const SETTINGS_PATH := "user://settings.cfg"
const BUSES := ["Music", "SFX", "Ambience", "Dialogue"]
const TITLE_THEME := preload("res://assets/audio/music/title_theme.wav")
const DEFAULTS := {
	"audio": {"master": 1.0, "music": 0.55, "sfx": 0.85, "ambience": 0.7, "dialogue": 1.0},
	"graphics": {"quality": "high", "fps": 60},
	"gameplay": {"haptics": true, "tips": true, "dialogue_auto": false, "language": "en"},
}

var profile: Dictionary = {}
var settings := ConfigFile.new()
var launch_mode := ""          ## "new" | "continue" | "" (developer launch flags decide)
var skip_splash := false       ## returning from the game goes straight to the menu
var _music: AudioStreamPlayer
var _music_tween: Tween
var _back_stack: Array = []    ## Callables returning true when they consumed Back
var _fade: ColorRect


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for bus in BUSES:
		if AudioServer.get_bus_index(bus) < 0:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, bus)
			AudioServer.set_bus_send(i, "Master")
	_load_settings()
	_load_profile()
	_music = AudioStreamPlayer.new()
	_music.name = "TitleMusic"
	_music.stream = TITLE_THEME
	_music.bus = "Music"
	add_child(_music)
	var layer := CanvasLayer.new()
	layer.layer = 120
	add_child(layer)
	_fade = ColorRect.new()
	_fade.color = Color(0.02, 0.018, 0.016, 0.0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(_fade)
	get_tree().set_auto_accept_quit(true)
	apply_settings()


# --- Profile (local mock) ---------------------------------------------------------------
func has_profile() -> bool:
	return not profile.is_empty() and String(profile.get("username", "")) != ""


func _load_profile() -> void:
	if FileAccess.file_exists(PROFILE_PATH):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PROFILE_PATH))
		if parsed is Dictionary:
			profile = parsed


func save_profile(p: Dictionary) -> void:
	profile = p.duplicate(true)
	profile["local_only"] = true
	var f := FileAccess.open(PROFILE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(profile, "\t"))
	profile_changed.emit()


func mark_seen(key: String) -> void:
	var seen: Array = profile.get("seen", [])
	if not seen.has(key):
		seen.append(key)
		profile["seen"] = seen
		save_profile(profile)


func has_seen(key: String) -> bool:
	return (profile.get("seen", []) as Array).has(key)


## Username rules: 3-16 letters, digits, spaces or underscores, starting with a letter.
static func validate_username(name: String) -> String:
	var n := name.strip_edges()
	if n.length() < 3:
		return "At least 3 characters."
	if n.length() > 16:
		return "No more than 16 characters."
	var re := RegEx.create_from_string("^[A-Za-z][A-Za-z0-9 _]*$")
	if re.search(n) == null:
		return "Start with a letter; use letters, numbers, spaces or _."
	return ""


static func validate_family(name: String) -> String:
	var n := name.strip_edges()
	if n.length() < 2:
		return "At least 2 characters."
	if n.length() > 14:
		return "No more than 14 characters."
	var re := RegEx.create_from_string("^[A-Za-z][A-Za-z' -]*$")
	if re.search(n) == null:
		return "Letters, spaces, hyphens or apostrophes only."
	return ""


# --- Settings -----------------------------------------------------------------------------
func _load_settings() -> void:
	settings.load(SETTINGS_PATH)
	for section in DEFAULTS:
		for key in DEFAULTS[section]:
			if not settings.has_section_key(section, key):
				settings.set_value(section, key, DEFAULTS[section][key])


func get_setting(section: String, key: String) -> Variant:
	return settings.get_value(section, key, DEFAULTS.get(section, {}).get(key))


func set_setting(section: String, key: String, value: Variant) -> void:
	settings.set_value(section, key, value)
	settings.save(SETTINGS_PATH)
	apply_settings()
	settings_changed.emit()


func apply_settings() -> void:
	var vol := func(bus: String, key: String) -> void:
		var i := AudioServer.get_bus_index(bus)
		if i >= 0:
			var v := float(get_setting("audio", key))
			AudioServer.set_bus_volume_db(i, linear_to_db(maxf(v, 0.0001)))
			AudioServer.set_bus_mute(i, v <= 0.001)
	vol.call("Master", "master")
	vol.call("Music", "music")
	vol.call("SFX", "sfx")
	vol.call("Ambience", "ambience")
	vol.call("Dialogue", "dialogue")
	Engine.max_fps = int(get_setting("graphics", "fps"))
	_apply_graphics()


## Graphics quality: engine/viewport level only (world systems are untouched).
func _apply_graphics() -> void:
	var q := String(get_setting("graphics", "quality"))
	var vp := get_viewport()
	match q:
		"low":
			vp.msaa_3d = Viewport.MSAA_DISABLED
			vp.scaling_3d_scale = 0.75
			vp.mesh_lod_threshold = 2.0
		"medium":
			vp.msaa_3d = Viewport.MSAA_2X
			vp.scaling_3d_scale = 0.9
			vp.mesh_lod_threshold = 1.4
		_:
			vp.msaa_3d = Viewport.MSAA_2X
			vp.scaling_3d_scale = 1.0
			vp.mesh_lod_threshold = 1.0
	for light in get_tree().get_nodes_in_group("quality_shadow"):
		(light as DirectionalLight3D).shadow_enabled = q != "low"


## Called by the world when its sun exists, so Low quality can drop shadows.
func register_sun(light: DirectionalLight3D) -> void:
	light.add_to_group("quality_shadow")
	_apply_graphics()


func haptic() -> void:
	if bool(get_setting("gameplay", "haptics")) and OS.has_feature("mobile"):
		Input.vibrate_handheld(12)


# --- Music ----------------------------------------------------------------------------------
func play_title(volume_db := -14.0) -> void:
	if _music_tween:
		_music_tween.kill()
	if not _music.playing:
		_music.volume_db = -40.0
		_music.play()
	_music_tween = create_tween()
	_music_tween.tween_property(_music, "volume_db", volume_db, 1.5)


## Title theme settles under the city once the world is on screen.
func duck_music(volume_db := -22.0) -> void:
	if _music_tween:
		_music_tween.kill()
	_music_tween = create_tween()
	_music_tween.tween_property(_music, "volume_db", volume_db, 2.5)


# --- Back button / overlays -------------------------------------------------------------------
## Overlays register a handler while open; Back calls the newest one.
func push_back(handler: Callable) -> void:
	_back_stack.append(handler)


func pop_back(handler: Callable) -> void:
	_back_stack.erase(handler)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		handle_back()


func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("ui_cancel"):
		if handle_back():
			get_viewport().set_input_as_handled()


func handle_back() -> bool:
	for i in range(_back_stack.size() - 1, -1, -1):
		var h: Callable = _back_stack[i]
		if not h.is_valid():
			_back_stack.remove_at(i)
			continue
		if h.call():
			return true
	return false


# --- Scene transitions -------------------------------------------------------------------------
func change_scene(path: String) -> void:
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0, 0.35)
	await tw.finished
	_back_stack.clear()
	get_tree().change_scene_to_file(path)
	await get_tree().process_frame
	await get_tree().process_frame
	create_tween().tween_property(_fade, "color:a", 0.0, 0.45)


func save_exists() -> bool:
	return FileAccess.file_exists("user://saves/slot_0.json")


## Summary of the existing save for the Continue button, or {}.
func save_summary() -> Dictionary:
	if not save_exists():
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://saves/slot_0.json"))
	if not parsed is Dictionary:
		return {}
	var w: Dictionary = parsed.get("world", {})
	var player: String = w.get("player", "")
	var out := {"chapter": int(w.get("chapter_index", 0)) + 1, "saved_at_ms": int(parsed.get("saved_at_ms", 0))}
	for f in w.get("factions", []):
		if f.get("id") == player:
			out["family"] = f.get("name", "")
			out["cash"] = int(f.get("cash", 0))
	return out


## Deletes the local profile and save, then returns to the launch sequence.
func reset_local_progress() -> void:
	var game := get_node_or_null("/root/Game")
	if game and game.has_method("discard"):
		game.discard()
	for path in [PROFILE_PATH, "user://saves/slot_0.json"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	profile = {}
	profile_changed.emit()
	launch_mode = ""
	change_scene("res://scenes/boot.tscn")

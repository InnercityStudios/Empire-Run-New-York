extends Control
## Launch sequence: splash -> main menu -> (player creation) -> game.
##
## Developer launches skip the front end so world captures and benchmarks keep
## working exactly as before: --capture / --benchmark / --new-game /
## --skip-menu go straight to the game. --ui-screen=<splash|menu|creation|
## settings|profile> opens one front-end screen (for UI captures).

const GAME_SCENE := "res://scenes/main.tscn"
const DIRECT_FLAGS := ["--capture", "--benchmark", "--new-game", "new-game", "--skip-menu", "--world"]

var _menu: MainMenu


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UiTheme.theme()
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.018, 0.016)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var screen := ""
	var direct := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--ui-screen="):
			screen = a.get_slice("=", 1)
		for flag in DIRECT_FLAGS:
			if a == flag or a.begins_with(flag + "="):
				direct = true
	if screen == "" and direct:
		App.launch_mode = "new" if ("--new-game" in OS.get_cmdline_user_args()) else "continue"
		get_tree().change_scene_to_file.call_deferred(GAME_SCENE)
		return
	if screen == "" and App.skip_splash:
		App.skip_splash = false
		screen = "menu"
	match screen:
		"", "splash":
			_splash()
		"creation":
			_creation()
		"settings":
			_show_menu(false)
			SettingsPanel.open(self)
		"profile":
			_show_menu(false)
			ProfilePanel.open(self)
		_:
			App.play_title()
			_show_menu()


func _splash() -> void:
	var s := SplashScreen.new()
	add_child(s)
	s.finished.connect(func(): _show_menu())


func _show_menu(animate := true) -> void:
	if _menu and is_instance_valid(_menu):
		return
	_menu = MainMenu.new()
	add_child(_menu)
	if not animate:
		_menu.modulate.a = 1.0
	else:
		_menu.modulate.a = 0.0
		create_tween().tween_property(_menu, "modulate:a", 1.0, 0.6)
	_menu.continue_requested.connect(_continue)
	_menu.new_game_requested.connect(_new_game)
	_menu.settings_requested.connect(func(): SettingsPanel.open(self))
	_menu.profile_requested.connect(func(): ProfilePanel.open(self))


func _continue() -> void:
	App.launch_mode = "continue"
	App.change_scene(GAME_SCENE)


func _new_game() -> void:
	if App.save_exists():
		ConfirmDialog.ask(self, "Start a new game?",
			"Your current family's progress on this device will be replaced.", "Start over", _creation, true)
	else:
		_creation()


func _creation() -> void:
	App.play_title()
	if _menu and is_instance_valid(_menu):
		_menu.queue_free()
		_menu = null
	var c := PlayerCreation.new()
	add_child(c)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--ui-step="):
			c.dev_jump(int(arg.get_slice("=", 1)))
	c.modulate.a = 0.0
	create_tween().tween_property(c, "modulate:a", 1.0, 0.4)
	c.completed.connect(func(_p: Dictionary):
		App.launch_mode = "new"
		App.change_scene(GAME_SCENE))
	c.cancelled.connect(func():
		c.queue_free()
		_show_menu())

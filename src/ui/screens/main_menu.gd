class_name MainMenu
extends Control
## Title menu over the approved key art: Continue (when a save exists), New
## Game, Profile, Settings and Quit. Account features are clearly local-only.

signal continue_requested
signal new_game_requested
signal settings_requested
signal profile_requested

var _back := Callable()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UiTheme.theme()
	var art := TextureRect.new()
	art.texture = load("res://assets/branding/loading_screen.png")
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.set_anchors_preset(Control.PRESET_FULL_RECT)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(art)
	# Slow drift on the art (one tween, no per-frame script).
	art.resized.connect(func(): art.pivot_offset = art.size * 0.5)
	var drift := create_tween().set_loops()
	drift.tween_property(art, "scale", Vector2(1.06, 1.06), 24.0).set_trans(Tween.TRANS_SINE)
	drift.tween_property(art, "scale", Vector2.ONE, 24.0).set_trans(Tween.TRANS_SINE)
	var shade := TextureRect.new()
	shade.texture = _side_gradient()
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	var m := UiKit.safe_margins(self)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	col.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	col.offset_left = m.x + 56
	col.offset_right = m.x + 56 + 440
	col.offset_top = 70
	col.offset_bottom = -60
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(col)
	# The key art carries the logo; the column sits beneath it on the left.
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 120)
	col.add_child(gap)
	var summary := App.save_summary()
	if not summary.is_empty():
		var sub := "%s  ·  Chapter %d  ·  %s" % [summary.get("family", ""), summary.get("chapter", 1),
			UiTheme.money(int(summary.get("cash", 0)))]
		var cont := UiKit.menu_button("Continue", sub, "chevron")
		cont.pressed.connect(func(): continue_requested.emit())
		col.add_child(cont)
		var ago := _ago(int(summary.get("saved_at_ms", 0)))
		if ago != "":
			(cont.find_child("Sub", true, false) as Label).text = sub + "  ·  " + ago
		cont.call_deferred("grab_focus")
	var ng := UiKit.menu_button("New Game", "Begin a new family in 1977 New York", "family")
	ng.pressed.connect(func(): new_game_requested.emit())
	col.add_child(ng)
	if summary.is_empty():
		ng.call_deferred("grab_focus")
	var pr := UiKit.menu_button("Profile", "Your boss, family and records", "people")
	pr.disabled = not App.has_profile()
	pr.modulate.a = 0.45 if pr.disabled else 1.0
	pr.pressed.connect(func(): profile_requested.emit())
	col.add_child(pr)
	var st := UiKit.menu_button("Settings", "Sound, graphics and controls", "gear")
	st.pressed.connect(func(): settings_requested.emit())
	col.add_child(st)
	if not OS.has_feature("ios"):
		var q := UiKit.menu_button("Quit", "", "close")
		q.pressed.connect(func(): get_tree().quit())
		col.add_child(q)
	# Account chip (local mock) and build line.
	var chip := UiKit.panel(10, 0.3, 10)
	chip.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	chip.grow_vertical = Control.GROW_DIRECTION_BEGIN
	chip.offset_left = m.x + 56
	chip.offset_top = -m.w - 58
	chip.offset_bottom = -m.w - 8
	add_child(chip)
	var ch := HBoxContainer.new()
	ch.add_theme_constant_override("separation", 10)
	chip.add_child(ch)
	if App.has_profile():
		var p := App.profile
		ch.add_child(UiKit.crest(p.get("crest", "shield"), UiKit.initials_for(p.get("username", "")),
			Color(p.get("family_color", "#c9a24a")), 30))
		ch.add_child(UiTheme.label("%s  ·  local profile" % p.get("username", ""), 15, UiKit.IVORY, "body_medium"))
	else:
		ch.add_child(UiTheme.label("No profile yet", 15, UiKit.IVORY, "body_medium"))
	ch.add_child(UiTheme.label("Online account not connected", 13, UiTheme.FAINT, "body_medium"))
	var ver := UiTheme.label("v%s  ·  development build" % ProjectSettings.get_setting("application/config/version", "0.1.0"),
		13, UiTheme.FAINT, "body_medium")
	ver.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	ver.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	ver.grow_vertical = Control.GROW_DIRECTION_BEGIN
	ver.offset_right = -m.z - 8
	ver.offset_bottom = -m.w - 8
	add_child(ver)
	col.modulate.a = 0.0
	col.position.x -= 24
	var tw := create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(col, "modulate:a", 1.0, 0.5)
	tw.tween_property(col, "position:x", col.position.x + 24, 0.6)
	_back = func() -> bool:
		_confirm_quit()
		return true
	App.push_back(_back)


func _exit_tree() -> void:
	App.pop_back(_back)


func _confirm_quit() -> void:
	ConfirmDialog.ask(self, "Leave New York?", "Your progress is saved on this device.", "Quit", func(): get_tree().quit())


static func _side_gradient() -> Texture2D:
	var g := GradientTexture2D.new()
	g.fill_from = Vector2(0, 0.5)
	g.fill_to = Vector2(1, 0.5)
	var gr := Gradient.new()
	gr.offsets = PackedFloat32Array([0.0, 0.42, 0.75])
	gr.colors = PackedColorArray([Color(0.02, 0.018, 0.016, 0.93), Color(0.02, 0.018, 0.016, 0.55),
		Color(0.02, 0.018, 0.016, 0.0)])
	g.gradient = gr
	return g


static func _ago(ms: int) -> String:
	if ms <= 0:
		return ""
	var s := int((Time.get_unix_time_from_system() * 1000.0 - ms) / 1000.0)
	if s < 90:
		return "just now"
	if s < 3600:
		return "%d min ago" % (s / 60)
	if s < 86400:
		return "%d h ago" % (s / 3600)
	return "%d days ago" % (s / 86400)

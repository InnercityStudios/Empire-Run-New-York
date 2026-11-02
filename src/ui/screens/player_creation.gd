class_name PlayerCreation
extends Control
## New-player flow: name, crest, family identity, review. Creates the LOCAL
## profile (no online account) and asks to start a new game.

signal completed(profile: Dictionary)
signal cancelled

const STEPS := ["Your name", "Your crest", "Your family", "Review"]

var _step := 0
var _data := {"username": "", "crest": "shield", "family_name": "", "family_color": "#c9a24a"}
var _content: VBoxContainer
var _dots: HBoxContainer
var _next: Button
var _prev: Button
var _error: Label
var _back := Callable()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UiTheme.theme()
	if App.has_profile():
		for k in _data:
			_data[k] = App.profile.get(k, _data[k])
	var art := TextureRect.new()
	art.texture = load("res://assets/branding/loading_screen.png")
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.set_anchors_preset(Control.PRESET_FULL_RECT)
	art.anchor_top = -0.6  # crop the art's own logo out of frame, at any aspect ratio
	art.modulate = Color(0.42, 0.39, 0.37)
	add_child(art)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var p := UiKit.panel(18, 0.45, 30)
	p.custom_minimum_size = Vector2(1000, 580)
	center.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 18)
	p.add_child(v)
	var top := HBoxContainer.new()
	v.add_child(top)
	var cap := UiTheme.label("CREATE YOUR FAMILY", 16, UiTheme.GOLD, "caps")
	cap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(cap)
	_dots = HBoxContainer.new()
	_dots.add_theme_constant_override("separation", 10)
	top.add_child(_dots)
	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 16)
	_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(_content)
	_error = UiTheme.label("", 16, UiKit.BURGUNDY_LIGHT.lightened(0.35), "body_medium")
	_error.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_error)
	var nav := HBoxContainer.new()
	nav.add_theme_constant_override("separation", 14)
	v.add_child(nav)
	_prev = UiKit.button("Back", "secondary", "", 200)
	_prev.pressed.connect(_go_back)
	nav.add_child(_prev)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nav.add_child(sp)
	_next = UiKit.button("Next", "primary", "", 240)
	_next.pressed.connect(_go_next)
	nav.add_child(_next)
	_back = func() -> bool:
		_go_back()
		return true
	App.push_back(_back)
	_show()


## Development captures: open a later step with sample entries.
func dev_jump(step: int) -> void:
	_data["username"] = "Nicky"
	_data["family_name"] = "Ferraro"
	_step = clampi(step, 0, STEPS.size() - 1)
	_show()


func _exit_tree() -> void:
	App.pop_back(_back)


func _go_back() -> void:
	if _step == 0:
		cancelled.emit()
		return
	_step -= 1
	_show()


func _go_next() -> void:
	var err := _validate()
	_error.text = err
	if err != "":
		return
	if _step == STEPS.size() - 1:
		var profile := _data.duplicate()
		profile["username"] = String(profile["username"]).strip_edges()
		profile["family_name"] = String(profile["family_name"]).strip_edges()
		profile["created_ms"] = int(Time.get_unix_time_from_system() * 1000.0)
		App.save_profile(profile)
		completed.emit(profile)
		return
	_step += 1
	_show()


func _validate() -> String:
	match _step:
		0:
			return App.validate_username(_data["username"])
		2:
			return App.validate_family(_data["family_name"])
	return ""


func _show() -> void:
	_error.text = ""
	for c in _content.get_children():
		c.queue_free()
	for c in _dots.get_children():
		c.queue_free()
	for i in STEPS.size():
		var d := UiTheme.label("%d  %s" % [i + 1, STEPS[i].to_upper()], 15,
			UiTheme.GOLD_LIGHT if i == _step else (UiKit.IVORY if i < _step else UiTheme.FAINT), "caps")
		_dots.add_child(d)
	_prev.text = "BACK" if _step > 0 else "CANCEL"
	_next.text = "ENTER NEW YORK" if _step == STEPS.size() - 1 else "NEXT"
	match _step:
		0:
			_step_name()
		1:
			_step_crest()
		2:
			_step_family()
		3:
			_step_review()
	_content.modulate.a = 0.0
	create_tween().tween_property(_content, "modulate:a", 1.0, 0.2)


func _field(placeholder: String, value: String, key: String, max_len: int) -> LineEdit:
	var e := LineEdit.new()
	e.placeholder_text = placeholder
	e.text = value
	e.max_length = max_len
	e.custom_minimum_size = Vector2(520, 64)
	e.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	e.alignment = HORIZONTAL_ALIGNMENT_CENTER
	e.add_theme_font_override("font", UiTheme.font("display"))
	e.add_theme_font_size_override("font_size", 28)
	e.add_theme_color_override("font_color", UiKit.IVORY)
	e.add_theme_color_override("font_placeholder_color", UiTheme.FAINT)
	for state in ["normal", "focus"]:
		var s := StyleBoxFlat.new()
		s.bg_color = Color(0, 0, 0, 0.35)
		s.border_color = Color(UiTheme.GOLD, 0.8 if state == "focus" else 0.35)
		s.border_width_bottom = 2
		s.set_content_margin_all(12)
		e.add_theme_stylebox_override(state, s)
	e.text_changed.connect(func(t: String):
		_data[key] = t
		_error.text = "")
	e.text_submitted.connect(func(_t): _go_next())
	e.call_deferred("grab_focus")
	return e


func _title(text: String, sub: String) -> void:
	_content.add_child(UiKit.header(text, 40))
	var s := UiTheme.label(sub, 21, UiTheme.MUTED, "body_medium")
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	s.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content.add_child(s)


func _step_name() -> void:
	_title("Who runs this family?", "Your name as other families will see it. 3–16 characters.")
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(0, 40)
	_content.add_child(sp)
	_content.add_child(_field("Your name", _data["username"], "username", 16))


func _step_crest() -> void:
	_title("Choose your crest", "Your mark on the map, on your estate and on everything you own.")
	var grid := HBoxContainer.new()
	grid.alignment = BoxContainer.ALIGNMENT_CENTER
	grid.add_theme_constant_override("separation", 18)
	_content.add_child(grid)
	var initials := UiKit.initials_for(_data["username"])
	for style in UiKit.CREST_STYLES:
		var b := Button.new()
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(130, 150)
		b.button_pressed = style == _data["crest"]
		for state in ["normal", "hover", "pressed", "hover_pressed"]:
			var s := StyleBoxFlat.new()
			var on: bool = state in ["pressed", "hover_pressed"]
			s.bg_color = Color(UiTheme.GOLD, 0.12) if on else Color(1, 1, 1, 0.03)
			s.border_color = Color(UiTheme.GOLD, 0.9 if on else 0.2)
			s.set_border_width_all(2 if on else 1)
			s.set_corner_radius_all(12)
			b.add_theme_stylebox_override(state, s)
		var cr := UiKit.crest(style, initials, Color(_data["family_color"]), 104)
		cr.position = Vector2(13, 14)
		b.add_child(cr)
		var st: String = style
		b.pressed.connect(func():
			_data["crest"] = st
			_show())
		UiKit.feedback(b)
		grid.add_child(b)


func _step_family() -> void:
	_title("Name your family", "Families are known by name. Choose one that will be feared and respected.")
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	_content.add_child(row)
	var f := _field("Family name", _data["family_name"], "family_name", 14)
	f.custom_minimum_size = Vector2(380, 64)
	row.add_child(f)
	row.add_child(UiTheme.label("FAMILY", 26, UiTheme.GOLD, "display"))
	var cap := UiTheme.label("FAMILY COLOUR", 16, UiTheme.MUTED, "caps")
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_content.add_child(cap)
	var colors := HBoxContainer.new()
	colors.alignment = BoxContainer.ALIGNMENT_CENTER
	colors.add_theme_constant_override("separation", 14)
	_content.add_child(colors)
	for hexc in UiKit.FAMILY_COLORS:
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(76, 76)
		var on: bool = hexc == _data["family_color"]
		for state in ["normal", "hover", "pressed"]:
			var s := StyleBoxFlat.new()
			s.bg_color = Color(hexc)
			s.border_color = UiTheme.GOLD_LIGHT if on else Color(0, 0, 0, 0.6)
			s.set_border_width_all(4 if on else 2)
			s.set_corner_radius_all(38)
			b.add_theme_stylebox_override(state, s)
		var hc: String = hexc
		b.pressed.connect(func():
			_data["family_color"] = hc
			var keep: String = _data["family_name"]
			_show()
			_data["family_name"] = keep)
		UiKit.feedback(b)
		colors.add_child(b)


func _step_review() -> void:
	_title("The %s Family" % String(_data["family_name"]).strip_edges(), "1977. Little Italy. Everything starts here.")
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 40)
	_content.add_child(row)
	row.add_child(UiKit.crest(_data["crest"], UiKit.initials_for(_data["username"]), Color(_data["family_color"]), 180))
	var facts := VBoxContainer.new()
	facts.add_theme_constant_override("separation", 10)
	facts.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(facts)
	for pair in [["Boss", String(_data["username"]).strip_edges()],
			["Family", "%s Family" % String(_data["family_name"]).strip_edges()],
			["Starting territory", "Little Italy, Manhattan"],
			["Account", "Local profile on this device"]]:
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 16)
		var k := UiTheme.label(pair[0].to_upper(), 16, UiTheme.MUTED, "caps")
		k.custom_minimum_size = Vector2(240, 0)
		h.add_child(k)
		h.add_child(UiTheme.label(pair[1], 25, UiKit.IVORY, "body_bold"))
		facts.add_child(h)

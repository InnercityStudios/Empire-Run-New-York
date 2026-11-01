class_name Hud
extends CanvasLayer
## World-map interface. Reads state from Game.world and reports player intent
## through signals; it never mutates simulation state itself.
##
## Layout (1920x1080 reference, safe-area aware):
##   top-left   family plate          top-centre  stat chips      top-right  clock + menu
##   left       collapsible crew rail bottom      selection sheet (keeps the map visible)

signal crew_card_pressed(crew_id: String)
signal action_requested(action: String, payload: Dictionary)
signal close_selection
signal move_mode_cancelled

const REFRESH_INTERVAL := 0.2
const MARGIN := Vector2(20, 14)
const SHEET_WIDTH := 860.0

var markers: WorldMarkers
var root: Control
var _cash_label: Label
var _income_label: Label
var _soldier_label: Label
var _power_label: Label
var _clock_label: Label
var _family_label: Label
var _rail: GlassPanel
var _rail_rows: VBoxContainer
var _rail_count: Label
var _rail_toggle: Button
var _rail_open := true
var _roster_rows: Dictionary = {}
var _sheet_holder: Control
var _sheet: GlassPanel
var _sheet_refresh: Callable
var _toasts: VBoxContainer
var _banner: GlassPanel
var _banner_label: Label
var _menu: Control
var _refresh_accum := 0.0
var _shown_cash := 0.0
var _selection := {}


func _ready() -> void:
	layer = 10
	root = Control.new()
	root.name = "Root"
	root.theme = UiTheme.theme()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	markers = WorldMarkers.new()
	markers.name = "WorldMarkers"
	root.add_child(markers)
	_build_top_bar()
	_build_rail()
	_build_sheet_holder()
	_build_toasts()
	_build_banner()
	_apply_safe_area()
	get_viewport().size_changed.connect(_apply_safe_area)


func _apply_safe_area() -> void:
	# Keep controls clear of notches and rounded corners on phones.
	var safe := DisplayServer.get_display_safe_area()
	var screen := DisplayServer.screen_get_size()
	var vp := get_viewport().get_visible_rect().size
	var margin := MARGIN
	if screen.x > 0 and safe.size.x > 0 and safe.size.x < screen.x:
		margin.x = maxf(margin.x, safe.position.x * vp.x / screen.x)
	root.offset_left = margin.x
	root.offset_right = -margin.x
	root.offset_top = margin.y
	root.offset_bottom = -margin.y


# --- Top bar -------------------------------------------------------------------------
func _build_top_bar() -> void:
	var bar := HBoxContainer.new()
	bar.name = "TopBar"
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bar.add_theme_constant_override("separation", 10)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bar)
	# Family plate
	var plate := _pill()
	bar.add_child(plate)
	var ph := HBoxContainer.new()
	ph.add_theme_constant_override("separation", 10)
	plate.content.add_child(ph)
	var emblem := TextureRect.new()
	emblem.texture = load("res://assets/branding/app_icon.png")
	emblem.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	emblem.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	emblem.custom_minimum_size = Vector2(38, 38)
	ph.add_child(emblem)
	var names := VBoxContainer.new()
	names.add_theme_constant_override("separation", -2)
	ph.add_child(names)
	_family_label = UiTheme.label("Marino Family", 20, UiTheme.GOLD_LIGHT, "display")
	names.add_child(_family_label)
	var pw := HBoxContainer.new()
	pw.add_theme_constant_override("separation", 5)
	pw.add_child(UiTheme.icon_rect("power", 14, UiTheme.GOLD))
	_power_label = UiTheme.label("0", UiTheme.SIZE_CAPTION + 1, UiTheme.MUTED, "body_medium")
	pw.add_child(_power_label)
	names.add_child(pw)
	# Stat chips
	var chips := HBoxContainer.new()
	chips.add_theme_constant_override("separation", 8)
	chips.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chips.alignment = BoxContainer.ALIGNMENT_CENTER
	chips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(chips)
	_cash_label = _chip(chips, "cash", 150)
	_income_label = _chip(chips, "income", 120)
	_soldier_label = _chip(chips, "soldier", 70)
	# Clock and menu
	var right := _pill(Vector4(16, 6, 6, 6))
	bar.add_child(right)
	var rh := HBoxContainer.new()
	rh.add_theme_constant_override("separation", 10)
	right.content.add_child(rh)
	_clock_label = UiTheme.label("", UiTheme.SIZE_SMALL, UiTheme.MUTED, "body_medium")
	_clock_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rh.add_child(_clock_label)
	var menu_btn := UiTheme.icon_button("menu", 40)
	menu_btn.pressed.connect(_toggle_menu)
	rh.add_child(menu_btn)


func _pill(pad := Vector4(14, 7, 16, 7)) -> GlassPanel:
	var p := GlassPanel.new()
	p.radius = 12.0
	p.padding = pad
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	return p


func _chip(parent: Control, icon_name: String, min_w: float) -> Label:
	var p := _pill(Vector4(12, 9, 14, 9))
	p.custom_minimum_size = Vector2(min_w, 0)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(p)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	p.content.add_child(h)
	h.add_child(UiTheme.icon_rect(icon_name, 20, UiTheme.GOLD))
	var l := UiTheme.label("", 21, UiTheme.CREAM, "body_bold")
	h.add_child(l)
	return l


# --- Crew rail -----------------------------------------------------------------------
func _build_rail() -> void:
	_rail = GlassPanel.new()
	_rail.name = "CrewRail"
	_rail.padding = Vector4(8, 8, 8, 8)
	_rail.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_rail.position = Vector2(0, 74)
	_rail.custom_minimum_size = Vector2(272, 0)
	root.add_child(_rail)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	_rail.content.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(6, 0)
	head.add_child(spacer)
	head.add_child(UiTheme.caption("Crews", UiTheme.MUTED))
	_rail_count = UiTheme.label("0", UiTheme.SIZE_CAPTION, UiTheme.FAINT, "body_medium")
	_rail_count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_rail_count)
	_rail_toggle = UiTheme.icon_button("chevron_down", 32)
	_rail_toggle.pressed.connect(_toggle_rail)
	head.add_child(_rail_toggle)
	_rail_rows = VBoxContainer.new()
	_rail_rows.add_theme_constant_override("separation", 2)
	v.add_child(_rail_rows)


func _toggle_rail() -> void:
	_rail_open = not _rail_open
	_rail_rows.visible = _rail_open
	_rail_toggle.icon = UiTheme.icon("chevron_down" if _rail_open else "chevron")
	_rail.reset_size()


func rebuild_roster(world: SimWorld) -> void:
	for r in _roster_rows.values():
		r["row"].queue_free()
	_roster_rows.clear()
	var ids := world.crews.keys()
	ids.sort()
	var n := 0
	for id in ids:
		var crew: CrewState = world.crews[id]
		if crew.owner_id != world.player_faction_id:
			continue
		n += 1
		var row := PanelContainer.new()
		row.custom_minimum_size = Vector2(0, 52)
		row.mouse_filter = Control.MOUSE_FILTER_STOP
		row.add_theme_stylebox_override("panel", _row_style(false))
		_rail_rows.add_child(row)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 10)
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(h)
		var status_dot := UiTheme.dot(UiTheme.GREEN, 8)
		h.add_child(status_dot)
		var tv := VBoxContainer.new()
		tv.add_theme_constant_override("separation", -3)
		tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(tv)
		tv.add_child(UiTheme.label(crew.name, 19, UiTheme.CREAM, "body_medium"))
		var status := UiTheme.label("", UiTheme.SIZE_CAPTION, UiTheme.MUTED)
		status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		status.custom_minimum_size = Vector2(170, 0)
		tv.add_child(status)
		var power := UiTheme.label("", 17, UiTheme.GOLD, "body_bold")
		h.add_child(power)
		var crew_id: String = id
		row.gui_input.connect(func(e: InputEvent):
			if (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT) \
					or (e is InputEventScreenTouch and e.pressed):
				crew_card_pressed.emit(crew_id))
		_roster_rows[id] = {"row": row, "status": status, "dot": status_dot, "power": power}
	_rail_count.text = "  %d" % n


func _row_style(selected: bool) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(1, 1, 1, 0.07) if selected else Color(1, 1, 1, 0.0)
	s.set_corner_radius_all(8)
	s.border_color = UiTheme.GOLD
	s.border_width_left = 3 if selected else 0
	s.content_margin_left = 10
	s.content_margin_right = 10
	s.content_margin_top = 4
	s.content_margin_bottom = 4
	return s


func _refresh_roster(world: SimWorld, now: int) -> void:
	for id in _roster_rows:
		var crew: CrewState = world.crews.get(id)
		if crew == null:
			continue
		var r: Dictionary = _roster_rows[id]
		(r["status"] as Label).text = crew_status_text(world, crew, now)
		(r["power"] as Label).text = str(world.crew_power(crew.id))
		var guarding := false
		for b in world.businesses.values():
			if b.assigned_crew_id == id:
				guarding = true
		(r["dot"] as ColorRect).color = UiTheme.GOLD if crew.is_moving() else (UiTheme.GREEN if guarding else UiTheme.MUTED)
		var selected: bool = _selection.get("kind") == "crew" and _selection.get("id") == id
		(r["row"] as PanelContainer).add_theme_stylebox_override("panel", _row_style(selected))


func crew_status_text(world: SimWorld, crew: CrewState, now: int) -> String:
	if crew.is_moving():
		var dest := landmark_display_name(world, crew.dest_landmark)
		return "En route%s · %s" % [(" to " + dest) if dest != "" else "", UiTheme.duration(crew.arrive_ms - now)]
	var b := world.business_at_landmark(crew.at_landmark)
	if b != null and b.assigned_crew_id == crew.id:
		return "Guarding " + b.name
	var place := landmark_display_name(world, crew.at_landmark)
	if place != "":
		return "At " + place
	var street: String = Game.layout.street_name(world.roads.edges[crew.location["edge"]]["street"])
	return "Waiting on " + street


func landmark_display_name(world: SimWorld, landmark_id: String) -> String:
	if landmark_id == "":
		return ""
	var b := world.business_at_landmark(landmark_id)
	if b:
		return b.name
	var hq := world.hq_at_landmark(landmark_id)
	return hq.name if hq else ""


# --- Bottom sheet --------------------------------------------------------------------
func _build_sheet_holder() -> void:
	_sheet_holder = Control.new()
	_sheet_holder.name = "SheetHolder"
	_sheet_holder.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_sheet_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_sheet_holder)


func show_selection(sel: Dictionary) -> void:
	_selection = sel
	if _sheet and is_instance_valid(_sheet):
		_sheet.queue_free()
	_sheet = null
	_sheet_refresh = Callable()
	if sel.is_empty():
		return
	_sheet = GlassPanel.new()
	_sheet.name = "SelectionSheet"
	_sheet.radius = 14.0
	_sheet.accent = true
	_sheet.padding = Vector4(20, 14, 16, 14)
	_sheet.custom_minimum_size = Vector2(SHEET_WIDTH, 0)
	_sheet_holder.add_child(_sheet)
	_sheet_refresh = SelectionPanelBuilder.build(_sheet.content, sel, self)
	_refresh_now()
	_position_sheet(true)


func _position_sheet(animate: bool) -> void:
	await get_tree().process_frame
	if _sheet == null or not is_instance_valid(_sheet):
		return
	_sheet.reset_size()
	var w := _sheet_holder.size.x
	var target := Vector2((w - _sheet.size.x) * 0.5, -_sheet.size.y)
	if animate:
		_sheet.position = target + Vector2(0, 24)
		_sheet.modulate.a = 0.0
		var tw := create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(_sheet, "position", target, 0.22)
		tw.tween_property(_sheet, "modulate:a", 1.0, 0.18)
	else:
		_sheet.position = target


func emit_action(action: String, payload: Dictionary) -> void:
	action_requested.emit(action, payload)


func emit_close() -> void:
	close_selection.emit()


# --- Banner, toasts, menu ------------------------------------------------------------
func _build_banner() -> void:
	_banner = GlassPanel.new()
	_banner.visible = false
	_banner.radius = 12.0
	_banner.padding = Vector4(16, 6, 6, 6)
	_banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_banner.position = Vector2(-280, 74)
	_banner.custom_minimum_size = Vector2(560, 0)
	root.add_child(_banner)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	_banner.content.add_child(h)
	h.add_child(UiTheme.icon_rect("move", 22, UiTheme.GOLD_LIGHT))
	_banner_label = UiTheme.label("", UiTheme.SIZE_SMALL, UiTheme.CREAM, "body_medium")
	_banner_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_banner_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(_banner_label)
	var cancel := UiTheme.button("Cancel", "", true)
	cancel.custom_minimum_size = Vector2(0, 40)
	cancel.pressed.connect(func(): move_mode_cancelled.emit())
	h.add_child(cancel)


func show_move_banner(on: bool, crew_name := "") -> void:
	_banner.visible = on
	if on:
		_banner_label.text = "Send %s — tap a building or a street" % crew_name


func _build_toasts() -> void:
	_toasts = VBoxContainer.new()
	_toasts.name = "Toasts"
	_toasts.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_toasts.position = Vector2(-430, 74)
	_toasts.custom_minimum_size = Vector2(430, 0)
	_toasts.add_theme_constant_override("separation", 6)
	_toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_toasts)


func toast(text: String, icon_name := "cash", color := UiTheme.GOLD_LIGHT) -> void:
	var p := _pill(Vector4(12, 8, 14, 8))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.size_flags_horizontal = Control.SIZE_SHRINK_END
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	p.content.add_child(h)
	h.add_child(UiTheme.icon_rect(icon_name, 18, color))
	var l := UiTheme.label(text, UiTheme.SIZE_SMALL, UiTheme.CREAM, "body_medium")
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(0, 0)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l)
	_toasts.add_child(p)
	if _toasts.get_child_count() > 4:
		_toasts.get_child(0).queue_free()
	p.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(p, "modulate:a", 1.0, 0.18)
	tw.tween_interval(3.0)
	tw.tween_property(p, "modulate:a", 0.0, 0.45)
	tw.tween_callback(p.queue_free)


func _toggle_menu() -> void:
	if _menu and is_instance_valid(_menu):
		_menu.queue_free()
		_menu = null
		return
	_menu = Control.new()
	_menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	_menu.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(_menu)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed:
			_toggle_menu())
	_menu.add_child(dim)
	var panel := GlassPanel.new()
	panel.radius = 16.0
	panel.accent = true
	panel.padding = Vector4(28, 22, 28, 24)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(440, 0)
	panel.position = Vector2(-220, -200)
	_menu.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	panel.content.add_child(v)
	var logo := TextureRect.new()
	logo.texture = load("res://assets/branding/logo_empire.png")
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.custom_minimum_size = Vector2(380, 150)
	v.add_child(logo)
	var district := UiTheme.label("Little Italy  ·  Manhattan  ·  1977", UiTheme.SIZE_SMALL, UiTheme.MUTED)
	district.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(district)
	var resume := UiTheme.button("Resume")
	resume.pressed.connect(_toggle_menu)
	v.add_child(resume)
	var restart := UiTheme.button("Restart chapter", "", true)
	restart.pressed.connect(func():
		_toggle_menu()
		action_requested.emit("restart", {}))
	v.add_child(restart)


# --- Per-frame -------------------------------------------------------------------------
func _process(delta: float) -> void:
	if not Game.is_running():
		return
	var world := Game.world
	var f := world.player()
	_shown_cash = lerpf(_shown_cash, float(f.cash), 1.0 - exp(-8.0 * delta))
	if absf(_shown_cash - f.cash) < 1.0:
		_shown_cash = f.cash
	_cash_label.text = UiTheme.money(roundi(_shown_cash))
	_refresh_accum += delta
	if _refresh_accum >= REFRESH_INTERVAL:
		_refresh_accum = 0.0
		_refresh_now()


func _refresh_now() -> void:
	if not Game.is_running():
		return
	var world := Game.world
	var now := Game.now_ms()
	var f := world.player()
	_family_label.text = f.name
	_power_label.text = "Power  %s" % UiTheme.money(world.faction_power(f.id)).trim_prefix("$")
	_income_label.text = "%s/h" % UiTheme.short_money(world.faction_income_per_hour(f.id))
	var soldiers := 0
	for c in world.crews.values():
		if c.owner_id == f.id:
			soldiers += PowerCalculator.soldier_count(c.soldiers)
	_soldier_label.text = str(soldiers)
	_clock_label.text = _period_clock()
	_refresh_roster(world, now)
	if _sheet_refresh.is_valid():
		_sheet_refresh.call(world, now)


## The local date and time, set in 1977.
func _period_clock() -> String:
	var d := Time.get_datetime_dict_from_system()
	d["year"] = 1977
	var pd := Time.get_datetime_dict_from_unix_time(Time.get_unix_time_from_datetime_dict(d))
	var days := ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
	var months := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
	return "%s %d %s 1977   %02d:%02d" % [days[pd["weekday"]], pd["day"], months[pd["month"] - 1], pd["hour"], pd["minute"]]

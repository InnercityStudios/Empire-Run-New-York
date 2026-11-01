class_name Hud
extends CanvasLayer
## World-map interface. Reads state from Game.world and reports player intent
## through signals; it never mutates simulation state itself.

signal crew_card_pressed(crew_id: String)
signal action_requested(action: String, payload: Dictionary)
signal close_selection
signal move_mode_cancelled

const REFRESH_INTERVAL := 0.2

var markers: WorldMarkers
var root: Control
var _cash_label: Label
var _income_label: Label
var _soldier_label: Label
var _power_label: Label
var _clock_label: Label
var _family_label: Label
var _roster: VBoxContainer
var _roster_cards: Dictionary = {}
var _panel_holder: Control
var _panel: DecoPanel
var _panel_refresh: Callable
var _toasts: VBoxContainer
var _banner: DecoPanel
var _menu: DecoPanel
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
	_build_roster()
	_build_selection_holder()
	_build_toasts()
	_build_banner()
	_apply_safe_area()
	get_viewport().size_changed.connect(_apply_safe_area)


func _apply_safe_area() -> void:
	# Keep controls clear of notches and rounded corners on phones.
	var safe := DisplayServer.get_display_safe_area()
	var screen := DisplayServer.screen_get_size()
	var vp := get_viewport().get_visible_rect().size
	var margin := Vector2(24, 16)
	if screen.x > 0 and safe.size.x > 0 and safe.size.x < screen.x:
		var scale_x := vp.x / screen.x
		margin.x = maxf(margin.x, safe.position.x * scale_x)
	root.offset_left = margin.x
	root.offset_right = -margin.x
	root.offset_top = margin.y
	root.offset_bottom = -margin.y


# --- Construction ------------------------------------------------------------------
func _build_top_bar() -> void:
	var bar := HBoxContainer.new()
	bar.name = "TopBar"
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bar.offset_bottom = 96
	bar.add_theme_constant_override("separation", 16)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bar)
	# Family plate
	var plate := DecoPanel.new()
	plate.add_theme_stylebox_override("panel", _compact_style())
	bar.add_child(plate)
	var ph := HBoxContainer.new()
	plate.add_child(ph)
	var emblem := TextureRect.new()
	emblem.texture = load("res://assets/branding/app_icon.png")
	emblem.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	emblem.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	emblem.custom_minimum_size = Vector2(64, 64)
	ph.add_child(emblem)
	var names := VBoxContainer.new()
	names.add_theme_constant_override("separation", 0)
	ph.add_child(names)
	_family_label = UiTheme.title("Marino Family", 28)
	names.add_child(_family_label)
	var pw := HBoxContainer.new()
	pw.add_theme_constant_override("separation", 6)
	pw.add_child(UiTheme.icon_rect("power", 22))
	_power_label = UiTheme.label("0", 22, UiTheme.CREAM, "body_bold")
	pw.add_child(_power_label)
	names.add_child(pw)
	# Resource chips
	var chips := HBoxContainer.new()
	chips.add_theme_constant_override("separation", 12)
	chips.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chips.alignment = BoxContainer.ALIGNMENT_CENTER
	chips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(chips)
	_cash_label = _chip(chips, "cash", 220)
	_income_label = _chip(chips, "income", 190)
	_soldier_label = _chip(chips, "soldier", 120)
	# Clock and menu
	var right := DecoPanel.new()
	right.add_theme_stylebox_override("panel", _compact_style())
	bar.add_child(right)
	var rh := HBoxContainer.new()
	right.add_child(rh)
	rh.add_child(UiTheme.icon_rect("clock", 26))
	_clock_label = UiTheme.label("", 24, UiTheme.CREAM, "body")
	rh.add_child(_clock_label)
	var menu_btn := UiTheme.button("", "menu", true)
	menu_btn.custom_minimum_size = Vector2(64, 56)
	menu_btn.pressed.connect(_toggle_menu)
	rh.add_child(menu_btn)


func _chip(parent: Control, icon_name: String, min_w: float) -> Label:
	var p := PanelContainer.new()
	var s := _compact_style()
	s.bg_color = Color(0.05, 0.045, 0.04, 0.88)
	p.add_theme_stylebox_override("panel", s)
	p.custom_minimum_size = Vector2(min_w, 0)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(p)
	var h := HBoxContainer.new()
	p.add_child(h)
	h.add_child(UiTheme.icon_rect(icon_name, 30))
	var l := UiTheme.label("", 28, UiTheme.CREAM, "body_bold")
	h.add_child(l)
	return l


func _compact_style() -> StyleBoxFlat:
	var s := UiTheme.panel_style()
	s.content_margin_left = 16
	s.content_margin_right = 16
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	return s


func _build_roster() -> void:
	_roster = VBoxContainer.new()
	_roster.name = "Roster"
	_roster.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_roster.position = Vector2(0, 124)
	_roster.add_theme_constant_override("separation", 10)
	_roster.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_roster)
	var head := UiTheme.label("YOUR CREWS", 20, UiTheme.MUTED, "body_bold")
	_roster.add_child(head)


func _build_selection_holder() -> void:
	_panel_holder = Control.new()
	_panel_holder.name = "SelectionHolder"
	_panel_holder.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_panel_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_panel_holder)


func _build_toasts() -> void:
	_toasts = VBoxContainer.new()
	_toasts.name = "Toasts"
	_toasts.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_toasts.position = Vector2(-560, 124)
	_toasts.custom_minimum_size = Vector2(560, 0)
	_toasts.alignment = BoxContainer.ALIGNMENT_BEGIN
	_toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_toasts)


func _build_banner() -> void:
	_banner = DecoPanel.new()
	_banner.visible = false
	_banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_banner.position = Vector2(-380, 130)
	_banner.custom_minimum_size = Vector2(760, 0)
	root.add_child(_banner)
	var h := HBoxContainer.new()
	_banner.add_child(h)
	h.add_child(UiTheme.icon_rect("move", 36, UiTheme.GOLD_LIGHT))
	var l := UiTheme.label("Tap a building or street to send the crew", 26, UiTheme.CREAM)
	l.name = "Text"
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l)
	var cancel := UiTheme.button("Cancel", "close", true)
	cancel.pressed.connect(func(): move_mode_cancelled.emit())
	h.add_child(cancel)


func show_move_banner(on: bool, crew_name := "") -> void:
	_banner.visible = on
	if on:
		(_banner.find_child("Text", true, false) as Label).text = "Send %s: tap a building or a street" % crew_name


# --- Menu -------------------------------------------------------------------------------
func _toggle_menu() -> void:
	if _menu and is_instance_valid(_menu):
		_menu.queue_free()
		_menu = null
		return
	_menu = DecoPanel.new()
	_menu.set_anchors_preset(Control.PRESET_CENTER)
	_menu.custom_minimum_size = Vector2(520, 0)
	_menu.position = Vector2(-260, -220)
	root.add_child(_menu)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	_menu.add_child(v)
	var logo := TextureRect.new()
	logo.texture = load("res://assets/branding/logo_empire.png")
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.custom_minimum_size = Vector2(440, 200)
	v.add_child(logo)
	var district := UiTheme.label("Little Italy · Manhattan · 1977", 24, UiTheme.MUTED)
	district.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(district)
	var resume := UiTheme.button("Resume", "", false)
	resume.pressed.connect(_toggle_menu)
	v.add_child(resume)
	var restart := UiTheme.button("Restart Chapter", "", true)
	restart.pressed.connect(func():
		_toggle_menu()
		action_requested.emit("restart", {}))
	v.add_child(restart)


# --- Roster -----------------------------------------------------------------------------
func rebuild_roster(world: SimWorld) -> void:
	for c in _roster_cards.values():
		c["card"].queue_free()
	_roster_cards.clear()
	var ids := world.crews.keys()
	ids.sort()
	for id in ids:
		var crew: CrewState = world.crews[id]
		if crew.owner_id != world.player_faction_id:
			continue
		var card := DecoPanel.new()
		card.custom_minimum_size = Vector2(330, 0)
		var s := _compact_style()
		card.add_theme_stylebox_override("panel", s)
		_roster.add_child(card)
		var h := HBoxContainer.new()
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(h)
		h.add_child(UiTheme.icon_rect("crew", 40, UiTheme.GOLD))
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 0)
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(v)
		var name_l := UiTheme.label(crew.name, 24, UiTheme.GOLD_LIGHT, "body_bold")
		v.add_child(name_l)
		var status := UiTheme.label("", 20, UiTheme.MUTED)
		v.add_child(status)
		var crew_id: String = id
		card.gui_input.connect(func(e: InputEvent):
			if (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT) \
					or (e is InputEventScreenTouch and e.pressed):
				crew_card_pressed.emit(crew_id))
		_roster_cards[id] = {"card": card, "status": status}


func _refresh_roster(world: SimWorld, now: int) -> void:
	for id in _roster_cards:
		var crew: CrewState = world.crews.get(id)
		if crew == null:
			continue
		var entry: Dictionary = _roster_cards[id]
		(entry["status"] as Label).text = "%s  ·  %s" % [_power_text(world, crew), crew_status_text(world, crew, now)]
		var selected: bool = _selection.get("kind") == "crew" and _selection.get("id") == id
		(entry["card"] as DecoPanel).ornament_color = UiTheme.GOLD_LIGHT if selected else UiTheme.GOLD_DARK
		(entry["card"] as DecoPanel).queue_redraw()


func _power_text(world: SimWorld, crew: CrewState) -> String:
	return "Power %d" % world.crew_power(crew.id)


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


# --- Selection panel ---------------------------------------------------------------------
func show_selection(sel: Dictionary) -> void:
	_selection = sel
	if _panel and is_instance_valid(_panel):
		_panel.queue_free()
	_panel = null
	_panel_refresh = Callable()
	if sel.is_empty():
		return
	_panel = DecoPanel.new()
	_panel.name = "SelectionPanel"
	_panel.custom_minimum_size = Vector2(980, 0)
	_panel_holder.add_child(_panel)
	var built := SelectionPanelBuilder.build(_panel, sel, self)
	_panel_refresh = built
	_refresh_now()
	_position_panel()
	_panel.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(_panel, "modulate:a", 1.0, 0.18)


func _position_panel() -> void:
	if _panel == null:
		return
	await get_tree().process_frame
	if _panel == null or not is_instance_valid(_panel):
		return
	var w := _panel_holder.size.x
	_panel.reset_size()
	_panel.position = Vector2((w - _panel.size.x) * 0.5, -_panel.size.y)


func emit_action(action: String, payload: Dictionary) -> void:
	action_requested.emit(action, payload)


func emit_close() -> void:
	close_selection.emit()


# --- Toasts -------------------------------------------------------------------------------
func toast(text: String, icon_name := "cash", color := UiTheme.GOLD_LIGHT) -> void:
	var p := PanelContainer.new()
	var s := _compact_style()
	s.bg_color = Color(0.05, 0.045, 0.04, 0.92)
	p.add_theme_stylebox_override("panel", s)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var h := HBoxContainer.new()
	p.add_child(h)
	h.add_child(UiTheme.icon_rect(icon_name, 28, color))
	var l := UiTheme.label(text, 24, UiTheme.CREAM)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(440, 0)
	h.add_child(l)
	_toasts.add_child(p)
	if _toasts.get_child_count() > 4:
		_toasts.get_child(0).queue_free()
	p.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(p, "modulate:a", 1.0, 0.2)
	tw.tween_interval(3.2)
	tw.tween_property(p, "modulate:a", 0.0, 0.5)
	tw.tween_callback(p.queue_free)


# --- Per-frame ---------------------------------------------------------------------------
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
	_power_label.text = "Power %s" % _thousands(world.faction_power(f.id))
	_income_label.text = "%s/h" % UiTheme.short_money(world.faction_income_per_hour(f.id))
	var soldiers := 0
	for c in world.crews.values():
		if c.owner_id == f.id:
			soldiers += PowerCalculator.soldier_count(c.soldiers)
	_soldier_label.text = str(soldiers)
	_clock_label.text = _period_clock()
	_refresh_roster(world, now)
	if _panel_refresh.is_valid():
		_panel_refresh.call(world, now)


func _thousands(n: int) -> String:
	return UiTheme.money(n).trim_prefix("$")


## The local date and time, set in 1977.
func _period_clock() -> String:
	var d := Time.get_datetime_dict_from_system()
	d["year"] = 1977
	var unix := Time.get_unix_time_from_datetime_dict(d)
	var pd := Time.get_datetime_dict_from_unix_time(unix)
	var days := ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
	var months := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
	return "%s %d %s 1977  %02d:%02d" % [days[pd["weekday"]], pd["day"], months[pd["month"] - 1], pd["hour"], pd["minute"]]

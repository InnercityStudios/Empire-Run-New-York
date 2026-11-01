class_name Hud
extends CanvasLayer
## World-map interface. Reads state from Game.world and reports player intent
## through signals; it never mutates simulation state itself.
##
## Layout (1920x1080 reference canvas, expands to any landscape aspect,
## safe-area aware):
##   top-left    family crest, name, power; location chip (district under camera)
##   left        navigation rail (City, Crews, Businesses; planned systems locked)
##   top-right   resource bar, date, inbox, menu
##   bottom-left minimap          bottom-right  next objective
##   bottom      selection sheet (business / HQ / crew), keeps the map visible

signal crew_card_pressed(crew_id: String)
signal business_card_pressed(business_id: String)
signal action_requested(action: String, payload: Dictionary)
signal close_selection
signal move_mode_cancelled
signal focus_requested(world_point: Vector2, landmark_id: String)

const REFRESH_INTERVAL := 0.2
const MARGIN := Vector2(20, 14)
const SHEET_WIDTH := 760.0
const RAIL_TOP := 162.0
const NAV := [
	{"id": "city", "label": "City", "icon": "home"},
	{"id": "crews", "label": "Crews", "icon": "people"},
	{"id": "businesses", "label": "Business", "icon": "building"},
	{"id": "operations", "label": "Ops", "icon": "target", "locked": true},
	{"id": "family", "label": "Family", "icon": "family", "locked": true},
	{"id": "research", "label": "Research", "icon": "flask", "locked": true},
]

var markers: WorldMarkers
var root: Control
var strategy_camera: StrategyCamera
var _layout: WorldLayout
var _cash_label: Label
var _cash_seg: Control
var _income_label: Label
var _soldier_label: Label
var _biz_label: Label
var _power_label: Label
var _clock_label: Label
var _family_label: Label
var _location_label: Label
var _location_sub: Label
var _nav_buttons: Dictionary = {}
var _nav_active := "city"
var _panel: GlassPanel
var _panel_kind := ""
var _panel_refresh: Callable
var _roster_rows: Dictionary = {}
var _sheet_holder: Control
var _sheet: GlassPanel
var _sheet_refresh: Callable
var _toasts: VBoxContainer
var _banner: GlassPanel
var _banner_label: Label
var _menu: Control
var _inbox: Control
var _inbox_badge: Label
var _inbox_log: Array = []
var _unread := 0
var _minimap_panel: GlassPanel
var _minimap: Minimap
var _minimap_button: Button
var _objective: GlassPanel
var _obj_text: Label
var _obj_bar: ProgressBar
var _obj_count: Label
var _obj_target := ""
var _refresh_accum := 0.0
var _shown_cash := 0.0
var _last_cash := -1
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
	_build_profile()
	_build_rail()
	_build_top_right()
	_build_sheet_holder()
	_build_objective()
	_build_toasts()
	_build_banner()
	_apply_safe_area()
	get_viewport().size_changed.connect(_apply_safe_area)


## Called by Main once the world exists (minimap and location need it).
func attach_world(p_layout: WorldLayout, p_camera: StrategyCamera) -> void:
	_layout = p_layout
	strategy_camera = p_camera
	if p_layout.is_geo:
		_build_minimap()


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
	# Narrow (4:3) screens: the objective card yields to the selection sheet.
	if _objective:
		_objective.visible = _selection.is_empty() or vp.x >= 1700.0


# --- Helpers ---------------------------------------------------------------------------
func _glass(pad := Vector4(14, 8, 14, 8), radius := 12.0) -> GlassPanel:
	var p := GlassPanel.new()
	p.radius = radius
	p.padding = pad
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	return p


## Subtle press feedback on any button (scale dip, no layout change).
static func press_feedback(b: Control) -> void:
	b.resized.connect(func(): b.pivot_offset = b.size * 0.5)
	b.gui_input.connect(func(e: InputEvent):
		var down: bool = (e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and e.pressed) \
			or (e is InputEventScreenTouch and e.pressed)
		if down:
			var tw := b.create_tween()
			tw.tween_property(b, "scale", Vector2(0.94, 0.94), 0.06)
			tw.tween_property(b, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_BACK))


func _square_button(icon_name: String, caption: String) -> Button:
	var b := Button.new()
	b.icon = UiTheme.icon(icon_name)
	b.text = caption
	b.expand_icon = true
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(76, 70)
	b.add_theme_font_override("font", UiTheme.font("body_medium"))
	b.add_theme_font_size_override("font_size", 14)
	b.add_theme_constant_override("icon_max_width", 28)
	for state in ["normal", "hover", "pressed"]:
		var s := StyleBoxFlat.new()
		s.bg_color = Color(0.06, 0.055, 0.05, 0.86 if state != "pressed" else 0.95)
		s.border_color = Color(UiTheme.GOLD, 0.32 if state == "normal" else 0.7)
		s.set_border_width_all(1)
		s.set_corner_radius_all(12)
		s.content_margin_top = 10
		s.content_margin_bottom = 6
		s.shadow_color = Color(0, 0, 0, 0.35)
		s.shadow_size = 8
		s.anti_aliasing = true
		b.add_theme_stylebox_override(state, s)
	for c in ["font_color", "font_hover_color", "font_pressed_color"]:
		b.add_theme_color_override(c, UiTheme.CREAM)
	for c in ["icon_normal_color", "icon_hover_color", "icon_pressed_color"]:
		b.add_theme_color_override(c, UiTheme.GOLD_LIGHT)
	press_feedback(b)
	return b


# --- Profile and location ----------------------------------------------------------------
func _build_profile() -> void:
	var box := HBoxContainer.new()
	box.name = "Profile"
	box.add_theme_constant_override("separation", 12)
	box.set_anchors_preset(Control.PRESET_TOP_LEFT)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(box)
	# Crest in a gold ring.
	var crest := Control.new()
	crest.custom_minimum_size = Vector2(84, 84)
	crest.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(crest)
	var img := TextureRect.new()
	img.texture = load("res://assets/branding/app_icon.png")
	img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	img.position = Vector2(6, 6)
	img.size = Vector2(72, 72)
	var mask := ShaderMaterial.new()
	mask.shader = preload("res://src/ui/shaders/circle_mask.gdshader")
	img.material = mask
	crest.add_child(img)
	crest.draw.connect(func():
		crest.draw_circle(Vector2(42, 42), 41, Color(0, 0, 0, 0.55))
		crest.draw_arc(Vector2(42, 42), 39.5, 0, TAU, 64, UiTheme.GOLD, 2.5, true)
		crest.draw_arc(Vector2(42, 42), 36.5, 0, TAU, 64, Color(UiTheme.GOLD_DARK, 0.9), 1.0, true))
	var names := VBoxContainer.new()
	names.add_theme_constant_override("separation", 2)
	names.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.add_child(names)
	_family_label = UiTheme.label("Marino Family", 27, UiTheme.GOLD_LIGHT, "display")
	_family_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_family_label.add_theme_constant_override("shadow_outline_size", 6)
	names.add_child(_family_label)
	var pw := HBoxContainer.new()
	pw.add_theme_constant_override("separation", 6)
	pw.add_child(UiTheme.icon_rect("power", 16, UiTheme.GOLD))
	_power_label = UiTheme.label("", 17, UiTheme.CREAM, "body_medium")
	_power_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_power_label.add_theme_constant_override("shadow_outline_size", 5)
	pw.add_child(_power_label)
	names.add_child(pw)
	# Location chip: district under the camera; tap toggles the minimap.
	var chip := _glass(Vector4(12, 7, 10, 7), 12)
	chip.name = "Location"
	chip.set_anchors_preset(Control.PRESET_TOP_LEFT)
	chip.position = Vector2(0, 96)
	chip.custom_minimum_size = Vector2(270, 0)
	root.add_child(chip)
	var ch := HBoxContainer.new()
	ch.add_theme_constant_override("separation", 10)
	chip.content.add_child(ch)
	ch.add_child(UiTheme.icon_rect("pin", 24, UiTheme.GOLD))
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", -3)
	cv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ch.add_child(cv)
	_location_label = UiTheme.label("Little Italy", 20, UiTheme.CREAM, "body_bold")
	cv.add_child(_location_label)
	_location_sub = UiTheme.label("New York, 1977", 14, UiTheme.MUTED, "body_medium")
	cv.add_child(_location_sub)
	ch.add_child(UiTheme.icon_rect("chevron_down", 18, UiTheme.MUTED))
	chip.gui_input.connect(func(e: InputEvent):
		if (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT) \
				or (e is InputEventScreenTouch and e.pressed):
			_toggle_minimap())
	press_feedback(chip)


# --- Navigation rail -----------------------------------------------------------------------
func _build_rail() -> void:
	var rail := _glass(Vector4(6, 8, 6, 8), 14)
	rail.name = "NavRail"
	rail.set_anchors_preset(Control.PRESET_TOP_LEFT)
	rail.position = Vector2(0, RAIL_TOP)
	root.add_child(rail)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	rail.content.add_child(v)
	for item in NAV:
		var b := _nav_button(item)
		v.add_child(b)
		_nav_buttons[item["id"]] = b
	_set_nav_active("city")


func _nav_button(item: Dictionary) -> Button:
	var b := Button.new()
	b.name = "Nav_" + item["id"]
	b.icon = UiTheme.icon(item["icon"])
	b.text = item["label"]
	b.expand_icon = true
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(84, 70)
	b.add_theme_font_override("font", UiTheme.font("body_medium"))
	b.add_theme_font_size_override("font_size", 15)
	b.add_theme_constant_override("icon_max_width", 30)
	var locked: bool = item.get("locked", false)
	b.set_meta("locked", locked)
	b.tooltip_text = "Coming in a later chapter" if locked else ""
	if locked:
		var lock := UiTheme.icon_rect("lock", 13, UiTheme.FAINT)
		lock.position = Vector2(58, 8)
		b.add_child(lock)
	var id: String = item["id"]
	b.pressed.connect(func(): _on_nav(id))
	press_feedback(b)
	return b


func _style_nav(b: Button, active: bool) -> void:
	var locked: bool = b.get_meta("locked", false)
	for state in ["normal", "hover", "pressed"]:
		var s := StyleBoxFlat.new()
		s.set_corner_radius_all(10)
		s.content_margin_top = 10
		s.content_margin_bottom = 6
		s.anti_aliasing = true
		if active:
			s.bg_color = Color(UiTheme.GOLD, 0.14)
			s.border_color = Color(UiTheme.GOLD, 0.85)
			s.set_border_width_all(1)
			s.shadow_color = Color(UiTheme.GOLD, 0.22)
			s.shadow_size = 10
		else:
			s.bg_color = Color(1, 1, 1, 0.06 if state == "hover" and not locked else 0.0)
		b.add_theme_stylebox_override(state, s)
	var text_col := UiTheme.FAINT if locked else (UiTheme.GOLD_LIGHT if active else UiTheme.CREAM)
	var icon_col := Color(UiTheme.FAINT, 0.8) if locked else (UiTheme.GOLD_LIGHT if active else Color(UiTheme.GOLD, 0.85))
	for c in ["font_color", "font_hover_color", "font_pressed_color"]:
		b.add_theme_color_override(c, text_col)
	for c in ["icon_normal_color", "icon_hover_color", "icon_pressed_color"]:
		b.add_theme_color_override(c, icon_col)


func _set_nav_active(id: String) -> void:
	_nav_active = id
	for k in _nav_buttons:
		_style_nav(_nav_buttons[k], k == id)


func _on_nav(id: String) -> void:
	var b: Button = _nav_buttons[id]
	if b.get_meta("locked", false):
		toast("%s opens in a later chapter." % b.text, "lock", UiTheme.MUTED)
		return
	if id == "city" or id == _panel_kind:
		_close_panel()
		_set_nav_active("city")
		return
	_open_panel(id)
	_set_nav_active(id)


# --- Side panels (crews, businesses) -------------------------------------------------------
func _close_panel() -> void:
	if _panel and is_instance_valid(_panel):
		var p := _panel
		var tw := create_tween().set_parallel()
		tw.tween_property(p, "modulate:a", 0.0, 0.12)
		tw.tween_property(p, "position:x", p.position.x - 16.0, 0.12)
		tw.chain().tween_callback(p.queue_free)
	_panel = null
	_panel_kind = ""
	_panel_refresh = Callable()
	_roster_rows.clear()


func _open_panel(kind: String) -> void:
	_close_panel()
	_panel_kind = kind
	_panel = _glass(Vector4(14, 12, 12, 12), 14)
	_panel.name = "SidePanel"
	_panel.accent = true
	_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_panel.position = Vector2(108, RAIL_TOP)
	_panel.custom_minimum_size = Vector2(392, 0)
	root.add_child(_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	_panel.content.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	var title := UiTheme.title("Crews" if kind == "crews" else "Businesses", 24)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close := UiTheme.icon_button("close", 34)
	close.pressed.connect(func(): _on_nav("city"))
	head.add_child(close)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 3)
	v.add_child(rows)
	if kind == "crews":
		_fill_crews(rows)
	else:
		_fill_businesses(rows)
	_panel.modulate.a = 0.0
	_panel.position.x -= 16.0
	var tw := create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(_panel, "modulate:a", 1.0, 0.16)
	tw.tween_property(_panel, "position:x", 108.0, 0.18)
	_refresh_now()


func _row(parent: Control) -> PanelContainer:
	var row := PanelContainer.new()
	row.custom_minimum_size = Vector2(0, 56)
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.add_theme_stylebox_override("panel", _row_style(false))
	parent.add_child(row)
	return row


func _row_style(selected: bool) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(UiTheme.GOLD, 0.1) if selected else Color(1, 1, 1, 0.035)
	s.set_corner_radius_all(8)
	s.border_color = UiTheme.GOLD
	s.border_width_left = 3 if selected else 0
	s.content_margin_left = 12
	s.content_margin_right = 10
	s.content_margin_top = 5
	s.content_margin_bottom = 5
	return s


static func _tapped(e: InputEvent) -> bool:
	return (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT) \
		or (e is InputEventScreenTouch and e.pressed)


func _fill_crews(rows: VBoxContainer) -> void:
	var world := Game.world
	var ids := world.crews.keys()
	ids.sort()
	for id in ids:
		var crew: CrewState = world.crews[id]
		if crew.owner_id != world.player_faction_id:
			continue
		var row := _row(rows)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 10)
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(h)
		var dot := UiTheme.dot(UiTheme.GREEN, 8)
		h.add_child(dot)
		var tv := VBoxContainer.new()
		tv.add_theme_constant_override("separation", -2)
		tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(tv)
		tv.add_child(UiTheme.label(crew.name, 19, UiTheme.CREAM, "body_bold"))
		var status := UiTheme.label("", 14, UiTheme.MUTED, "body_medium")
		status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		status.custom_minimum_size = Vector2(250, 0)
		tv.add_child(status)
		var pv := VBoxContainer.new()
		pv.add_theme_constant_override("separation", -4)
		pv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(pv)
		pv.add_child(UiTheme.caption("Power"))
		var power := UiTheme.label("", 19, UiTheme.GOLD_LIGHT, "body_bold")
		power.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		pv.add_child(power)
		var crew_id: String = id
		row.gui_input.connect(func(e: InputEvent):
			if _tapped(e):
				crew_card_pressed.emit(crew_id))
		_roster_rows[id] = {"row": row, "status": status, "dot": dot, "power": power}
	_panel_refresh = _refresh_crews


func _refresh_crews(world: SimWorld, now: int) -> void:
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


func _fill_businesses(rows: VBoxContainer) -> void:
	var world := Game.world
	var ids := world.businesses.keys()
	ids.sort()
	var items: Dictionary = {}
	for id in ids:
		var b: BusinessState = world.businesses[id]
		var mine := b.owner_id == world.player_faction_id
		var row := _row(rows)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 10)
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(h)
		var f := world.faction(b.owner_id)
		h.add_child(UiTheme.dot(Color.html(f.color) if f else UiTheme.MUTED, 8))
		var tv := VBoxContainer.new()
		tv.add_theme_constant_override("separation", -2)
		tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(tv)
		tv.add_child(UiTheme.label(b.name, 18, UiTheme.CREAM, "body_bold"))
		var sub := UiTheme.label("", 14, UiTheme.MUTED, "body_medium")
		tv.add_child(sub)
		var collect: Button = null
		if mine:
			collect = UiTheme.button("Collect", "cash")
			collect.custom_minimum_size = Vector2(0, 40)
			collect.add_theme_font_size_override("font_size", 14)
			var bid: String = id
			collect.pressed.connect(func(): action_requested.emit("collect", {"business": bid}))
			press_feedback(collect)
			h.add_child(collect)
		var bid2: String = id
		row.gui_input.connect(func(e: InputEvent):
			if _tapped(e):
				business_card_pressed.emit(bid2))
		items[id] = {"sub": sub, "collect": collect, "row": row}
	_panel_refresh = func(w: SimWorld, now: int) -> void:
		for id in items:
			var b: BusinessState = w.businesses[id]
			var it: Dictionary = items[id]
			var own_f := w.faction(b.owner_id)
			var stored := b.stored(now, w.content)
			if b.owner_id == w.player_faction_id:
				(it["sub"] as Label).text = "Lv %d  ·  %s ready  ·  %s/h" % [b.level, UiTheme.short_money(stored),
					UiTheme.short_money(b.net_per_hour(w.content))]
				(it["collect"] as Button).disabled = stored <= 0
			else:
				(it["sub"] as Label).text = "Lv %d  ·  %s" % [b.level, own_f.name if own_f else "Independent"]
			var selected: bool = _selection.get("kind") == "business" and _selection.get("id") == id
			(it["row"] as PanelContainer).add_theme_stylebox_override("panel", _row_style(selected))


## Kept for Main: rebuilds the open crew list after a new session.
func rebuild_roster(_world: SimWorld) -> void:
	if _panel_kind != "":
		var kind := _panel_kind
		_close_panel()
		_open_panel(kind)


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


# --- Top right: resources, date, inbox, menu -----------------------------------------------
func _build_top_right() -> void:
	var bar := HBoxContainer.new()
	bar.name = "TopRight"
	bar.add_theme_constant_override("separation", 10)
	bar.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	bar.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bar)
	var res := _glass(Vector4(8, 6, 8, 6), 12)
	res.name = "Resources"
	res.mouse_filter = Control.MOUSE_FILTER_IGNORE
	res.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	bar.add_child(res)
	var rh := HBoxContainer.new()
	rh.add_theme_constant_override("separation", 0)
	res.content.add_child(rh)
	var seg := func(icon_name: String, caption: String, min_w: float, sep: bool) -> Label:
		if sep:
			var line := ColorRect.new()
			line.color = Color(UiTheme.GOLD, 0.22)
			line.custom_minimum_size = Vector2(1, 34)
			line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			rh.add_child(line)
		var m := MarginContainer.new()
		for k in ["margin_left", "margin_right"]:
			m.add_theme_constant_override(k, 14)
		m.custom_minimum_size = Vector2(min_w, 0)
		rh.add_child(m)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 9)
		m.add_child(h)
		h.add_child(UiTheme.icon_rect(icon_name, 24, UiTheme.GOLD))
		var tv := VBoxContainer.new()
		tv.add_theme_constant_override("separation", -5)
		h.add_child(tv)
		var l := UiTheme.label("", 22, UiTheme.CREAM, "body_bold")
		tv.add_child(l)
		tv.add_child(UiTheme.label(caption, 12, UiTheme.FAINT, "caps"))
		return l
	_cash_label = seg.call("cash", "CASH", 150, false)
	_cash_seg = _cash_label.get_parent().get_parent().get_parent()
	_income_label = seg.call("income", "PER HOUR", 128, true)
	_soldier_label = seg.call("soldier", "SOLDIERS", 100, true)
	_biz_label = seg.call("building", "BUSINESSES", 100, true)
	var clock := _glass(Vector4(14, 8, 14, 8), 12)
	clock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clock.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	bar.add_child(clock)
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", -4)
	clock.content.add_child(cv)
	_clock_label = UiTheme.label("", 18, UiTheme.CREAM, "body_bold")
	_clock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cv.add_child(_clock_label)
	var date_cap := UiTheme.label("", 12, UiTheme.FAINT, "caps")
	date_cap.name = "Date"
	date_cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cv.add_child(date_cap)
	var inbox := _square_button("envelope", "Inbox")
	inbox.pressed.connect(_toggle_inbox)
	bar.add_child(inbox)
	_inbox_badge = UiTheme.label("", 12, UiTheme.INK, "body_bold")
	_inbox_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_inbox_badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_inbox_badge.custom_minimum_size = Vector2(20, 20)
	_inbox_badge.position = Vector2(54, -6)
	var badge_bg := StyleBoxFlat.new()
	badge_bg.bg_color = UiTheme.RED
	badge_bg.set_corner_radius_all(10)
	_inbox_badge.add_theme_stylebox_override("normal", badge_bg)
	_inbox_badge.add_theme_color_override("font_color", UiTheme.CREAM)
	_inbox_badge.visible = false
	inbox.add_child(_inbox_badge)
	var menu := _square_button("gear", "Menu")
	menu.pressed.connect(_toggle_menu)
	bar.add_child(menu)


# --- Minimap ---------------------------------------------------------------------------------
func _build_minimap() -> void:
	_minimap_panel = _glass(Vector4(5, 5, 5, 5), 12)
	_minimap_panel.name = "Minimap"
	_minimap_panel.set_border(Color(UiTheme.GOLD, 0.55))
	_minimap_panel.anchor_top = 1.0
	_minimap_panel.anchor_bottom = 1.0
	_minimap_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_minimap_panel.offset_top = -206.0
	_minimap_panel.offset_bottom = 0.0
	root.add_child(_minimap_panel)
	_minimap = Minimap.new()
	_minimap.custom_minimum_size = Vector2(300, 196)
	_minimap_panel.content.add_child(_minimap)
	_minimap.setup(_layout, strategy_camera)
	_minimap.travel_requested.connect(func(p: Vector2): focus_requested.emit(p, ""))
	_minimap_button = UiTheme.icon_button("map", 52)
	_minimap_button.anchor_top = 1.0
	_minimap_button.anchor_bottom = 1.0
	_minimap_button.offset_top = -52.0
	_minimap_button.offset_bottom = 0.0
	_minimap_button.visible = false
	_minimap_button.pressed.connect(_toggle_minimap)
	root.add_child(_minimap_button)
	var hide_btn := UiTheme.icon_button("close", 26)
	hide_btn.position = Vector2(8, 8)
	hide_btn.pressed.connect(_toggle_minimap)
	_minimap.add_child(hide_btn)


func _toggle_minimap() -> void:
	if _minimap_panel == null:
		return
	var showing := not _minimap_panel.visible
	_minimap_panel.visible = showing
	_minimap_button.visible = not showing
	if showing:
		_minimap_panel.modulate.a = 0.0
		create_tween().tween_property(_minimap_panel, "modulate:a", 1.0, 0.15)


# --- Objective card --------------------------------------------------------------------------
func _build_objective() -> void:
	_objective = _glass(Vector4(16, 12, 12, 12), 14)
	_objective.name = "Objective"
	_objective.accent = true
	_objective.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_objective.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_objective.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_objective.custom_minimum_size = Vector2(460, 0)
	_objective.visible = false
	root.add_child(_objective)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	_objective.content.add_child(h)
	h.add_child(UiTheme.icon_rect("target", 34, UiTheme.GOLD_LIGHT))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	v.add_child(UiTheme.label("Next Objective", 19, UiTheme.GOLD_LIGHT, "display"))
	_obj_text = UiTheme.label("", 17, UiTheme.CREAM, "body_medium")
	_obj_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_obj_text.custom_minimum_size = Vector2(300, 0)
	v.add_child(_obj_text)
	var ph := HBoxContainer.new()
	ph.add_theme_constant_override("separation", 10)
	v.add_child(ph)
	_obj_bar = ProgressBar.new()
	_obj_bar.show_percentage = false
	_obj_bar.custom_minimum_size = Vector2(0, 6)
	_obj_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_obj_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ph.add_child(_obj_bar)
	_obj_count = UiTheme.label("", 14, UiTheme.MUTED, "body_medium")
	ph.add_child(_obj_count)
	var go := UiTheme.icon_button("chevron", 46)
	go.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	go.pressed.connect(func():
		if _obj_target != "" and Game.layout.landmarks.has(_obj_target):
			focus_requested.emit(Game.layout.landmarks[_obj_target]["frontage"], _obj_target))
	h.add_child(go)


func _refresh_objective(world: SimWorld) -> void:
	var defs: Array = world.content.scenarios.get("new_game", {}).get("objectives", [])
	var o := ObjectiveTracker.current(world, defs)
	var narrow := get_viewport().get_visible_rect().size.x < 1700.0
	_objective.visible = not o.is_empty() and (_selection.is_empty() or not narrow)
	if o.is_empty():
		return
	_obj_text.text = o["text"]
	_obj_target = o["landmark"]
	var cur: int = o["current"]
	var tgt: int = o["target"]
	_obj_bar.max_value = tgt
	_obj_bar.value = mini(cur, tgt)
	_obj_count.text = ("%s / %s" % [UiTheme.short_money(cur), UiTheme.short_money(tgt)]) if tgt >= 1000 \
		else "%d / %d" % [cur, tgt]


# --- Bottom sheet ----------------------------------------------------------------------------
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
	_apply_safe_area()
	if sel.is_empty():
		return
	_sheet = GlassPanel.new()
	_sheet.name = "SelectionSheet"
	_sheet.radius = 14.0
	_sheet.accent = true
	_sheet.padding = Vector4(18, 12, 14, 12)
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


# --- Banner, toasts, inbox, menu ---------------------------------------------------------------
func _build_banner() -> void:
	_banner = _glass(Vector4(16, 6, 6, 6), 12)
	_banner.visible = false
	_banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_banner.position = Vector2(-280, 92)
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
	_toasts.position = Vector2(-420, 92)
	_toasts.custom_minimum_size = Vector2(420, 0)
	_toasts.add_theme_constant_override("separation", 6)
	_toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_toasts)


func toast(text: String, icon_name := "cash", color := UiTheme.GOLD_LIGHT) -> void:
	_inbox_log.push_front({"text": text, "icon": icon_name, "color": color, "time": _clock_label.text})
	_inbox_log = _inbox_log.slice(0, 30)
	if _inbox == null:
		_unread += 1
		_inbox_badge.text = str(mini(_unread, 99))
		_inbox_badge.visible = true
	var p := _glass(Vector4(12, 8, 14, 8), 10)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.size_flags_horizontal = Control.SIZE_SHRINK_END
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	p.content.add_child(h)
	h.add_child(UiTheme.icon_rect(icon_name, 18, color))
	var l := UiTheme.label(text, 16, UiTheme.CREAM, "body_medium")
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(0, 0)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l)
	_toasts.add_child(p)
	if _toasts.get_child_count() > 3:
		_toasts.get_child(0).queue_free()
	p.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(p, "modulate:a", 1.0, 0.18)
	tw.tween_interval(2.6)
	tw.tween_property(p, "modulate:a", 0.0, 0.4)
	tw.tween_callback(p.queue_free)


func _toggle_inbox() -> void:
	if _inbox and is_instance_valid(_inbox):
		_inbox.queue_free()
		_inbox = null
		return
	_unread = 0
	_inbox_badge.visible = false
	var p := _glass(Vector4(14, 12, 14, 12), 14)
	p.name = "InboxPanel"
	p.accent = true
	p.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	p.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	p.position = Vector2(-430, 92)
	p.custom_minimum_size = Vector2(430, 0)
	root.add_child(p)
	_inbox = p
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	p.content.add_child(v)
	v.add_child(UiTheme.title("Inbox", 22))
	if _inbox_log.is_empty():
		v.add_child(UiTheme.label("No news yet.", 16, UiTheme.MUTED))
	for e in _inbox_log.slice(0, 8):
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 10)
		v.add_child(h)
		h.add_child(UiTheme.icon_rect(e["icon"], 16, e["color"]))
		var l := UiTheme.label(e["text"], 15, UiTheme.CREAM, "body_medium")
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(l)
		h.add_child(UiTheme.label(String(e["time"]), 12, UiTheme.FAINT, "body_medium"))
	p.modulate.a = 0.0
	create_tween().tween_property(p, "modulate:a", 1.0, 0.15)


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
	var panel := _glass(Vector4(28, 22, 28, 24), 16)
	panel.accent = true
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
	var district := UiTheme.label("New York  ·  1977", UiTheme.SIZE_SMALL, UiTheme.MUTED)
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


# --- Per-frame -------------------------------------------------------------------------------
func _process(delta: float) -> void:
	if not Game.is_running():
		return
	var world := Game.world
	var f := world.player()
	if _last_cash >= 0 and f.cash > _last_cash:
		# Collection feedback: brief gold flash on the cash segment.
		_cash_seg.modulate = Color(1.5, 1.3, 0.8)
		create_tween().tween_property(_cash_seg, "modulate", Color.WHITE, 0.5)
	_last_cash = f.cash
	_shown_cash = lerpf(_shown_cash, float(f.cash), 1.0 - exp(-8.0 * delta))
	if absf(_shown_cash - f.cash) < 1.0:
		_shown_cash = f.cash
	_cash_label.text = UiTheme.short_money(roundi(_shown_cash)) if _shown_cash >= 1_000_000 else UiTheme.money(roundi(_shown_cash))
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
	_income_label.text = UiTheme.short_money(world.faction_income_per_hour(f.id))
	var soldiers := 0
	for c in world.crews.values():
		if c.owner_id == f.id:
			soldiers += PowerCalculator.soldier_count(c.soldiers)
	_soldier_label.text = str(soldiers)
	var owned := 0
	for b in world.businesses.values():
		if b.owner_id == f.id:
			owned += 1
	_biz_label.text = "%d / %d" % [owned, world.businesses.size()]
	var clock := _period_clock()
	_clock_label.text = clock[1]
	(_clock_label.get_parent().get_node("Date") as Label).text = clock[0]
	if _layout and strategy_camera:
		var p := Vector2(strategy_camera.focus.x, strategy_camera.focus.z)
		var dname := _layout.district_name_at(p)
		_location_label.text = dname if dname != "" else "East River"
		_location_sub.text = "%s, New York 1977" % _borough_at(p)
	if _panel_refresh.is_valid():
		_panel_refresh.call(world, now)
	if _sheet_refresh.is_valid():
		_sheet_refresh.call(world, now)
	_refresh_objective(world)


func _borough_at(p: Vector2) -> String:
	if _layout.is_geo:
		var b := _layout.geo.borough_at(p)
		if not b.is_empty():
			return String(b["borough"]).capitalize().replace("Bronx", "The Bronx")
	return "Manhattan"


## [date, time] in 1977 at the local time of day.
func _period_clock() -> Array:
	var d := Time.get_datetime_dict_from_system()
	d["year"] = 1977
	var pd := Time.get_datetime_dict_from_unix_time(Time.get_unix_time_from_datetime_dict(d))
	var days := ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
	var months := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
	return ["%s %d %s 1977" % [days[pd["weekday"]], pd["day"], months[pd["month"] - 1]], "%02d:%02d" % [pd["hour"], pd["minute"]]]

class_name UiKit
extends RefCounted
## Shared building blocks for menus and overlays (extends UiTheme's palette and
## type): panels, buttons, rows, crest avatars and transitions. Every screen is
## assembled from these so the look stays consistent and re-skinnable.

const IVORY := Color("#efe6d2")
const BURGUNDY := Color("#5b1f24")
const BURGUNDY_LIGHT := Color("#8a2e35")
const PANEL_BG := Color(0.06, 0.055, 0.05, 0.94)
const SCRIM := Color(0.02, 0.018, 0.016, 0.62)
## Crest styles (frame shapes) and family colours offered at creation.
const CREST_STYLES := ["shield", "oval", "diamond", "seal", "crest", "plate"]
const FAMILY_COLORS := ["#c9a24a", "#8a2e35", "#d9cfb8", "#3f6b52", "#2f4a6b", "#6b4a8a"]



## Solid premium panel: charcoal, hairline gold border, shadow.
static func panel(radius := 14, border_alpha := 0.38, pad := 20) -> PanelContainer:
	var p := PanelContainer.new()
	var s := StyleBoxFlat.new()
	s.bg_color = PANEL_BG
	s.border_color = Color(UiTheme.GOLD, border_alpha)
	s.set_border_width_all(1)
	s.set_corner_radius_all(radius)
	s.shadow_color = Color(0, 0, 0, 0.45)
	s.shadow_size = 18
	s.shadow_offset = Vector2(0, 6)
	s.set_content_margin_all(pad)
	s.anti_aliasing = true
	p.add_theme_stylebox_override("panel", s)
	return p


## Full-screen dim + centred panel; returns {root, panel, body}.
static func modal(parent: Node, width := 760.0, title := "") -> Dictionary:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(root)
	var dim := ColorRect.new()
	dim.color = SCRIM
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var p := panel(16, 0.45, 26)
	p.custom_minimum_size = Vector2(width, 0)
	center.add_child(p)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 14)
	p.add_child(body)
	if title != "":
		body.add_child(header(title))
	root.modulate.a = 0.0
	p.scale = Vector2(0.97, 0.97)
	p.resized.connect(func(): p.pivot_offset = p.size * 0.5)
	var tw := root.create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(root, "modulate:a", 1.0, 0.18)
	tw.tween_property(p, "scale", Vector2.ONE, 0.22)
	return {"root": root, "panel": p, "body": body, "dim": dim}


static func close_modal(root: Control) -> void:
	if root == null or not is_instance_valid(root):
		return
	var tw := root.create_tween()
	tw.tween_property(root, "modulate:a", 0.0, 0.14)
	tw.tween_callback(root.queue_free)


## Modal overlay with a close button; Back (Escape / Android) and a tap on the
## scrim close it. Returns modal()'s dictionary.
static func overlay(parent: Node, width: float, title: String) -> Dictionary:
	var m := modal(parent, width, "")
	var root: Control = m["root"]
	var head := Control.new()
	head.custom_minimum_size = Vector2(0, 62)
	(m["body"] as Control).add_child(head)
	var h := header(title)
	h.set_anchors_preset(Control.PRESET_FULL_RECT)
	head.add_child(h)
	var close := UiTheme.icon_button("close", 52)
	close.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	close.offset_left = -52
	close.offset_top = -6
	head.add_child(close)
	var shut := func(): close_modal(root)
	close.pressed.connect(shut)
	var back := func() -> bool:
		close_modal(root)
		return true
	App.push_back(back)
	root.tree_exiting.connect(func(): App.pop_back(back))
	(m["dim"] as ColorRect).gui_input.connect(func(e: InputEvent):
		if (e is InputEventMouseButton and e.pressed) or (e is InputEventScreenTouch and e.pressed):
			close_modal(root))
	return m


## Title with a thin gold rule and diamond ornament.
static func header(text: String, size := 30) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	var t := UiTheme.title(text, size)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	v.add_child(ornament())
	return v


static func ornament(width := 260.0) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(width, 10)
	c.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	c.draw.connect(func():
		var mid := c.size.x * 0.5
		var y := c.size.y * 0.5
		c.draw_line(Vector2(0, y), Vector2(mid - 10, y), Color(UiTheme.GOLD, 0.55), 1.0, true)
		c.draw_line(Vector2(mid + 10, y), Vector2(c.size.x, y), Color(UiTheme.GOLD, 0.55), 1.0, true)
		c.draw_colored_polygon(PackedVector2Array([Vector2(mid, y - 4), Vector2(mid + 4, y), Vector2(mid, y + 4),
			Vector2(mid - 4, y)]), UiTheme.GOLD))
	return c


## Buttons: "primary" (gold), "secondary" (outline), "danger" (burgundy).
static func button(text: String, kind := "primary", icon_name := "", min_w := 0.0) -> Button:
	var b := UiTheme.button(text, icon_name, kind == "secondary")
	b.custom_minimum_size = Vector2(min_w, 54)
	if kind == "danger":
		for state in ["normal", "hover", "pressed", "disabled"]:
			var s := StyleBoxFlat.new()
			s.bg_color = {"normal": BURGUNDY, "hover": BURGUNDY_LIGHT, "pressed": Color("#3e1418"),
				"disabled": Color(1, 1, 1, 0.05)}[state]
			s.border_color = Color(UiTheme.GOLD, 0.5)
			s.set_border_width_all(1)
			s.set_corner_radius_all(8)
			s.content_margin_left = 18
			s.content_margin_right = 18
			b.add_theme_stylebox_override(state, s)
		for c in ["font_color", "font_hover_color", "font_pressed_color"]:
			b.add_theme_color_override(c, IVORY)
	feedback(b)
	return b


## Wide left-aligned menu entry with a gold edge on hover/focus.
static func menu_button(text: String, sub := "", icon_name := "") -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_ALL
	b.custom_minimum_size = Vector2(380, 68 if sub == "" else 84)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.text = ""
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var s := StyleBoxFlat.new()
		s.bg_color = Color(0.05, 0.045, 0.04, 0.78) if state in ["normal", "disabled"] else Color(0.11, 0.09, 0.06, 0.9)
		s.border_color = UiTheme.GOLD
		s.border_width_left = 0 if state in ["normal", "disabled"] else 3
		s.border_width_bottom = 1
		s.set_corner_radius_all(4)
		s.content_margin_left = 22
		b.add_theme_stylebox_override(state, s)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.set_anchors_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 22
	b.add_child(h)
	if icon_name != "":
		var ic := UiTheme.icon_rect(icon_name, 26, UiTheme.GOLD)
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(ic)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", -2)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(v)
	var t := UiTheme.label(text.to_upper(), 25, IVORY, "display")
	t.name = "Title"
	v.add_child(t)
	if sub != "":
		var s2 := UiTheme.label(sub, 17, UiTheme.MUTED, "body_medium")
		s2.name = "Sub"
		v.add_child(s2)
	b.mouse_entered.connect(func(): b.grab_focus())
	feedback(b)
	return b


static func feedback(b: Control) -> void:
	b.resized.connect(func(): b.pivot_offset = b.size * 0.5)
	b.gui_input.connect(func(e: InputEvent):
		var down: bool = (e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and e.pressed) \
			or (e is InputEventScreenTouch and e.pressed)
		if down:
			App.haptic()
			var tw := b.create_tween()
			tw.tween_property(b, "scale", Vector2(0.97, 0.97), 0.05)
			tw.tween_property(b, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_BACK))


## Labelled 0-100% slider row.
static func slider_row(text: String, value: float, on_change: Callable) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 16)
	var l := UiTheme.label(text, 19, IVORY, "body_medium")
	l.custom_minimum_size = Vector2(200, 0)
	h.add_child(l)
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.05
	s.value = value
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.custom_minimum_size = Vector2(0, 40)
	_style_slider(s)
	h.add_child(s)
	var pct := UiTheme.label("%d%%" % roundi(value * 100), 17, UiTheme.MUTED, "body_bold")
	pct.custom_minimum_size = Vector2(56, 0)
	pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h.add_child(pct)
	s.value_changed.connect(func(v: float):
		pct.text = "%d%%" % roundi(v * 100)
		on_change.call(v))
	return h


static func _style_slider(s: HSlider) -> void:
	var track := StyleBoxFlat.new()
	track.bg_color = Color(1, 1, 1, 0.1)
	track.set_corner_radius_all(3)
	track.content_margin_top = 3
	track.content_margin_bottom = 3
	var fill := StyleBoxFlat.new()
	fill.bg_color = UiTheme.GOLD
	fill.set_corner_radius_all(3)
	fill.content_margin_top = 3
	fill.content_margin_bottom = 3
	s.add_theme_stylebox_override("slider", track)
	s.add_theme_stylebox_override("grabber_area", fill)
	s.add_theme_stylebox_override("grabber_area_highlight", fill)
	var g := Image.create(28, 28, false, Image.FORMAT_RGBA8)
	g.fill(Color(0, 0, 0, 0))
	for y in 28:
		for x in 28:
			var d := Vector2(x - 13.5, y - 13.5).length()
			if d <= 12.5:
				g.set_pixel(x, y, UiTheme.GOLD_LIGHT if d < 10.5 else Color(0.1, 0.08, 0.05))
	var tex := ImageTexture.create_from_image(g)
	s.add_theme_icon_override("grabber", tex)
	s.add_theme_icon_override("grabber_highlight", tex)


## Toggle row (CheckButton) with label and description.
static func toggle_row(text: String, desc: String, value: bool, on_change: Callable) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 16)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", -2)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	v.add_child(UiTheme.label(text, 19, IVORY, "body_medium"))
	if desc != "":
		var d := UiTheme.label(desc, 14, UiTheme.MUTED)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(d)
	var t := CheckButton.new()
	t.button_pressed = value
	t.focus_mode = Control.FOCUS_NONE
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	t.toggled.connect(func(on: bool): on_change.call(on))
	h.add_child(t)
	return h


## Segmented choice; returns the container. on_change(index).
static func segmented(options: Array, selected: int, on_change: Callable) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 0)
	var group := ButtonGroup.new()
	for i in options.size():
		var b := Button.new()
		b.text = String(options[i]).to_upper()
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = i == selected
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(120, 46)
		b.add_theme_font_override("font", UiTheme.font("body_bold"))
		b.add_theme_font_size_override("font_size", 15)
		for state in ["normal", "hover", "pressed", "hover_pressed"]:
			var s := StyleBoxFlat.new()
			var on: bool = state in ["pressed", "hover_pressed"]
			s.bg_color = Color(UiTheme.GOLD, 0.9) if on else Color(1, 1, 1, 0.05 if state == "normal" else 0.09)
			s.border_color = Color(UiTheme.GOLD, 0.45)
			s.set_border_width_all(1)
			s.corner_radius_top_left = 8 if i == 0 else 0
			s.corner_radius_bottom_left = 8 if i == 0 else 0
			s.corner_radius_top_right = 8 if i == options.size() - 1 else 0
			s.corner_radius_bottom_right = 8 if i == options.size() - 1 else 0
			b.add_theme_stylebox_override(state, s)
		b.add_theme_color_override("font_color", IVORY)
		b.add_theme_color_override("font_hover_color", IVORY)
		b.add_theme_color_override("font_pressed_color", UiTheme.INK)
		b.add_theme_color_override("font_hover_pressed_color", UiTheme.INK)
		var idx := i
		b.pressed.connect(func(): on_change.call(idx))
		h.add_child(b)
	return h


## Family crest: monogram inside a heraldic frame (no portraits until approved).
static func crest(style: String, initials: String, color: Color, size := 120.0) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(size, size)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.draw.connect(func(): draw_crest(c, Rect2(Vector2.ZERO, c.size), style, initials, color))
	return c


static func crest_polygon(style: String, r: Rect2) -> PackedVector2Array:
	var c := r.get_center()
	var w := r.size.x * 0.46
	var h := r.size.y * 0.48
	var pts := PackedVector2Array()
	match style:
		"shield":
			pts = PackedVector2Array([c + Vector2(-w, -h), c + Vector2(w, -h), c + Vector2(w, h * 0.15),
				c + Vector2(w * 0.55, h * 0.7), c + Vector2(0, h), c + Vector2(-w * 0.55, h * 0.7), c + Vector2(-w, h * 0.15)])
		"diamond":
			pts = PackedVector2Array([c + Vector2(0, -h), c + Vector2(w, 0), c + Vector2(0, h), c + Vector2(-w, 0)])
		"crest":  # escutcheon with a three-point crown top
			pts = PackedVector2Array([c + Vector2(-w, -h * 0.7), c + Vector2(-w * 0.5, -h * 0.45), c + Vector2(0, -h),
				c + Vector2(w * 0.5, -h * 0.45), c + Vector2(w, -h * 0.7), c + Vector2(w * 0.9, h * 0.3),
				c + Vector2(0, h), c + Vector2(-w * 0.9, h * 0.3)])
		"plate":
			pts = PackedVector2Array([c + Vector2(-w, -h * 0.8), c + Vector2(-w * 0.7, -h), c + Vector2(w * 0.7, -h),
				c + Vector2(w, -h * 0.8), c + Vector2(w, h * 0.8), c + Vector2(w * 0.7, h), c + Vector2(-w * 0.7, h),
				c + Vector2(-w, h * 0.8)])
		"seal":  # scalloped wax seal
			for i in 32:
				var a := TAU * i / 32.0
				var rr := 1.0 if i % 2 == 0 else 0.86
				pts.append(c + Vector2(cos(a) * w * rr, sin(a) * w * rr))
		_:  # oval cartouche, upright
			for i in 40:
				var a := TAU * i / 40.0
				pts.append(c + Vector2(cos(a) * w * 0.78, sin(a) * h))
	return pts


static func draw_crest(ci: CanvasItem, r: Rect2, style: String, initials: String, color: Color) -> void:
	var outer := crest_polygon(style, r)
	var inner := crest_polygon(style, r.grow(-r.size.x * 0.07))
	ci.draw_colored_polygon(outer, UiTheme.GOLD)
	ci.draw_colored_polygon(inner, Color(0.07, 0.06, 0.05))
	var band := crest_polygon(style, r.grow(-r.size.x * 0.12))
	ci.draw_polyline(band + PackedVector2Array([band[0]]), Color(color, 0.9), maxf(1.5, r.size.x * 0.02), true)
	var font := UiTheme.font("display")
	var fs := int(r.size.y * (0.34 if initials.length() <= 2 else 0.26))
	var tw := font.get_string_size(initials, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	ci.draw_string(font, r.get_center() + Vector2(-tw * 0.5, fs * 0.36), initials, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
		UiTheme.GOLD_LIGHT)


static func initials_for(name: String) -> String:
	var parts := name.strip_edges().split(" ", false)
	if parts.is_empty():
		return "?"
	if parts.size() == 1:
		return parts[0].substr(0, 1).to_upper()
	return (parts[0].substr(0, 1) + parts[-1].substr(0, 1)).to_upper()


## Safe-area margins in canvas units (notches, rounded corners).
static func safe_margins(node: Control) -> Vector4:
	var safe := DisplayServer.get_display_safe_area()
	var screen := DisplayServer.screen_get_size()
	var vp := node.get_viewport_rect().size
	var m := Vector4(28, 18, 28, 18)
	if screen.x > 0 and safe.size.x > 0 and safe.size.x < screen.x:
		var k := vp.x / screen.x
		m.x = maxf(m.x, safe.position.x * k)
		m.z = maxf(m.z, (screen.x - safe.end.x) * k)
	return m

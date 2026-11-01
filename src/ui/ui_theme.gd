class_name UiTheme
extends RefCounted
## Visual language of the interface: charcoal, antique gold, Cinzel display
## caps and condensed Oswald for data. All UI is built from these helpers so
## the look stays consistent and can be re-skinned in one place.

const INK := Color("#0c0b0a")
const CHARCOAL := Color("#141210")
const PANEL := Color(0.075, 0.068, 0.061, 0.94)
const PANEL_SOFT := Color(0.1, 0.09, 0.08, 0.9)
const GOLD := Color("#c9a24a")
const GOLD_LIGHT := Color("#e8c97f")
const GOLD_DARK := Color("#7a5f28")
const CREAM := Color("#efe6d2")
const MUTED := Color("#9d9480")
const RED := Color("#b3362b")
const GREEN := Color("#5f9f6e")

const ICON_DIR := "res://assets/ui/icons/"

static var _theme: Theme
static var _fonts: Dictionary = {}
static var _icons: Dictionary = {}


static func font(kind: String) -> Font:
	if _fonts.has(kind):
		return _fonts[kind]
	var spec: Array = {
		"display": ["res://assets/fonts/Cinzel-Variable.ttf", 700],
		"display_regular": ["res://assets/fonts/Cinzel-Variable.ttf", 500],
		"body": ["res://assets/fonts/Oswald-Variable.ttf", 400],
		"body_bold": ["res://assets/fonts/Oswald-Variable.ttf", 600],
	}[kind]
	var base: FontFile = load(spec[0])
	var fv := FontVariation.new()
	fv.base_font = base
	fv.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): spec[1]}
	_fonts[kind] = fv
	return fv


static func icon(icon_name: String) -> Texture2D:
	if not _icons.has(icon_name):
		_icons[icon_name] = load(ICON_DIR + icon_name + ".svg")
	return _icons[icon_name]


static func theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font = font("body")
	t.default_font_size = 26
	t.set_color("font_color", "Label", CREAM)
	t.set_stylebox("panel", "PanelContainer", panel_style())
	# Primary (gold) button
	t.set_stylebox("normal", "Button", _button_box(GOLD, GOLD_LIGHT))
	t.set_stylebox("hover", "Button", _button_box(GOLD_LIGHT, Color.WHITE))
	t.set_stylebox("pressed", "Button", _button_box(GOLD_DARK, GOLD))
	t.set_stylebox("disabled", "Button", _button_box(Color(0.24, 0.22, 0.2), Color(0.32, 0.3, 0.27)))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", INK)
	t.set_color("font_hover_color", "Button", INK)
	t.set_color("font_pressed_color", "Button", CREAM)
	t.set_color("font_disabled_color", "Button", MUTED)
	t.set_color("icon_normal_color", "Button", INK)
	t.set_color("icon_hover_color", "Button", INK)
	t.set_color("icon_pressed_color", "Button", CREAM)
	t.set_color("icon_disabled_color", "Button", MUTED)
	t.set_font("font", "Button", font("body_bold"))
	t.set_font_size("font_size", "Button", 25)
	t.set_constant("h_separation", "Button", 10)
	t.set_constant("icon_max_width", "Button", 30)
	# Secondary (outlined) button
	t.add_type("SecondaryButton")
	t.set_type_variation("SecondaryButton", "Button")
	t.set_stylebox("normal", "SecondaryButton", _outline_box(PANEL_SOFT, GOLD_DARK))
	t.set_stylebox("hover", "SecondaryButton", _outline_box(Color(0.16, 0.14, 0.11), GOLD))
	t.set_stylebox("pressed", "SecondaryButton", _outline_box(Color(0.22, 0.18, 0.12), GOLD_LIGHT))
	t.set_stylebox("disabled", "SecondaryButton", _outline_box(PANEL_SOFT, Color(0.25, 0.23, 0.2)))
	t.set_color("font_color", "SecondaryButton", GOLD_LIGHT)
	t.set_color("font_hover_color", "SecondaryButton", CREAM)
	t.set_color("font_pressed_color", "SecondaryButton", CREAM)
	t.set_color("icon_normal_color", "SecondaryButton", GOLD_LIGHT)
	t.set_color("icon_hover_color", "SecondaryButton", CREAM)
	t.set_color("icon_pressed_color", "SecondaryButton", CREAM)
	# Progress bars
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.55)
	bg.set_corner_radius_all(2)
	bg.border_color = Color(GOLD_DARK, 0.7)
	bg.set_border_width_all(1)
	var fill := StyleBoxFlat.new()
	fill.bg_color = GOLD
	fill.set_corner_radius_all(2)
	t.set_stylebox("background", "ProgressBar", bg)
	t.set_stylebox("fill", "ProgressBar", fill)
	t.set_constant("separation", "VBoxContainer", 8)
	t.set_constant("separation", "HBoxContainer", 10)
	_theme = t
	return t


static func panel_style(color := PANEL) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.border_color = Color(GOLD, 0.85)
	s.set_border_width_all(2)
	s.set_corner_radius_all(3)
	s.shadow_color = Color(0, 0, 0, 0.45)
	s.shadow_size = 10
	s.content_margin_left = 22
	s.content_margin_right = 22
	s.content_margin_top = 18
	s.content_margin_bottom = 18
	return s


static func _button_box(fill_color: Color, border: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = fill_color
	s.border_color = border
	s.set_border_width_all(2)
	s.set_corner_radius_all(2)
	s.content_margin_left = 22
	s.content_margin_right = 22
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	return s


static func _outline_box(fill_color: Color, border: Color) -> StyleBoxFlat:
	var s := _button_box(fill_color, border)
	return s


static func label(text: String, size := 26, color := CREAM, font_kind := "body") -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font(font_kind))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


static func title(text: String, size := 34) -> Label:
	var l := label(text, size, GOLD_LIGHT, "display")
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	l.add_theme_constant_override("shadow_offset_y", 2)
	return l


static func button(text: String, icon_name := "", secondary := false) -> Button:
	var b := Button.new()
	b.text = text.to_upper()
	if icon_name != "":
		b.icon = icon(icon_name)
		b.expand_icon = false
	if secondary:
		b.theme_type_variation = "SecondaryButton"
	b.custom_minimum_size = Vector2(0, 66)
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_filter = Control.MOUSE_FILTER_STOP
	return b


static func icon_rect(icon_name: String, size := 32, color := GOLD) -> TextureRect:
	var r := TextureRect.new()
	r.texture = icon(icon_name)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.custom_minimum_size = Vector2(size, size)
	r.modulate = color
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


static func money(amount: int) -> String:
	var neg := amount < 0
	var s := str(absi(amount))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-$" if neg else "$") + s + out


static func short_money(amount: int) -> String:
	if amount >= 1_000_000:
		return "$%.1fM" % (amount / 1_000_000.0)
	if amount >= 10_000:
		return "$%dK" % (amount / 1000)
	return money(amount)


static func duration(ms: int) -> String:
	var s := maxi(0, ms / 1000)
	if s >= 3600:
		return "%dh %02dm" % [s / 3600, (s % 3600) / 60]
	if s >= 60:
		return "%dm %02ds" % [s / 60, s % 60]
	return "%ds" % s

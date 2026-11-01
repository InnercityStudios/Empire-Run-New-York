class_name UiTheme
extends RefCounted
## Visual language of the interface (v2): restrained charcoal glass, antique
## gold used sparingly for emphasis, Cinzel only for headings and branding,
## Inter for all data, labels and buttons. All UI is built from these helpers
## so the look stays consistent and can be re-skinned in one place.

const INK := Color("#121110")
const CHARCOAL := Color("#141210")
const PANEL := Color(0.055, 0.05, 0.045, 0.82)
const PANEL_SOFT := Color(1, 1, 1, 0.05)
const GOLD := Color("#c9a24a")
const GOLD_LIGHT := Color("#e2c27a")
const GOLD_DARK := Color("#7a5f28")
const HAIRLINE := Color(0.79, 0.64, 0.29, 0.28)
const CREAM := Color("#ede6d6")
const MUTED := Color("#a39b8a")
const FAINT := Color("#6f685c")
const RED := Color("#c4473b")
const GREEN := Color("#6fae7c")

## Type scale on the 1920x1080 reference canvas.
const SIZE_CAPTION := 15
const SIZE_SMALL := 18
const SIZE_BODY := 21
const SIZE_VALUE := 24
const SIZE_TITLE := 28

const ICON_DIR := "res://assets/ui/icons/"

static var _theme: Theme
static var _fonts: Dictionary = {}
static var _icons: Dictionary = {}


## Font roles: display (Cinzel headings), body / body_medium / body_bold (Inter).
static func font(kind: String) -> Font:
	if _fonts.has(kind):
		return _fonts[kind]
	var spec: Array = {
		"display": ["res://assets/fonts/Cinzel-Variable.ttf", 600, 0],
		"display_regular": ["res://assets/fonts/Cinzel-Variable.ttf", 500, 0],
		"body": ["res://assets/fonts/Inter-Variable.ttf", 420, 0],
		"body_medium": ["res://assets/fonts/Inter-Variable.ttf", 520, 0],
		"body_bold": ["res://assets/fonts/Inter-Variable.ttf", 620, 0],
		"caps": ["res://assets/fonts/Inter-Variable.ttf", 600, 1],
	}.get(kind, ["res://assets/fonts/Inter-Variable.ttf", 420, 0])
	var fv := FontVariation.new()
	fv.base_font = load(spec[0])
	fv.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): spec[1]}
	if spec[2] > 0:
		fv.spacing_glyph = 1  # tracked small caps captions
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
	t.default_font_size = SIZE_BODY
	t.set_color("font_color", "Label", CREAM)
	# Primary button: solid antique gold, dark text
	t.set_stylebox("normal", "Button", _button_box(GOLD, Color(0, 0, 0, 0)))
	t.set_stylebox("hover", "Button", _button_box(GOLD_LIGHT, Color(0, 0, 0, 0)))
	t.set_stylebox("pressed", "Button", _button_box(GOLD_DARK, Color(0, 0, 0, 0)))
	t.set_stylebox("disabled", "Button", _button_box(Color(1, 1, 1, 0.06), Color(1, 1, 1, 0.08)))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", INK)
	t.set_color("font_hover_color", "Button", INK)
	t.set_color("font_pressed_color", "Button", CREAM)
	t.set_color("font_disabled_color", "Button", FAINT)
	t.set_color("icon_normal_color", "Button", INK)
	t.set_color("icon_hover_color", "Button", INK)
	t.set_color("icon_pressed_color", "Button", CREAM)
	t.set_color("icon_disabled_color", "Button", FAINT)
	t.set_font("font", "Button", font("body_bold"))
	t.set_font_size("font_size", "Button", SIZE_SMALL)
	t.set_constant("h_separation", "Button", 8)
	t.set_constant("icon_max_width", "Button", 22)
	# Secondary button: hairline outline on glass
	t.add_type("SecondaryButton")
	t.set_type_variation("SecondaryButton", "Button")
	t.set_stylebox("normal", "SecondaryButton", _button_box(Color(1, 1, 1, 0.04), Color(1, 1, 1, 0.14)))
	t.set_stylebox("hover", "SecondaryButton", _button_box(Color(1, 1, 1, 0.09), HAIRLINE))
	t.set_stylebox("pressed", "SecondaryButton", _button_box(Color(1, 1, 1, 0.14), GOLD))
	t.set_stylebox("disabled", "SecondaryButton", _button_box(Color(1, 1, 1, 0.02), Color(1, 1, 1, 0.06)))
	for state in ["font_color", "font_hover_color", "font_pressed_color"]:
		t.set_color(state, "SecondaryButton", CREAM)
	t.set_color("font_disabled_color", "SecondaryButton", FAINT)
	for state in ["icon_normal_color", "icon_hover_color", "icon_pressed_color"]:
		t.set_color(state, "SecondaryButton", GOLD_LIGHT)
	# Progress bars: thin, rounded
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(1, 1, 1, 0.08)
	bg.set_corner_radius_all(3)
	var fill := StyleBoxFlat.new()
	fill.bg_color = GOLD
	fill.set_corner_radius_all(3)
	t.set_stylebox("background", "ProgressBar", bg)
	t.set_stylebox("fill", "ProgressBar", fill)
	t.set_constant("separation", "VBoxContainer", 6)
	t.set_constant("separation", "HBoxContainer", 8)
	_theme = t
	return t


static func _button_box(fill_color: Color, border: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = fill_color
	s.border_color = border
	s.set_border_width_all(1 if border.a > 0.0 else 0)
	s.set_corner_radius_all(8)
	s.content_margin_left = 18
	s.content_margin_right = 18
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	s.anti_aliasing = true
	return s


static func label(text: String, size := SIZE_BODY, color := CREAM, font_kind := "body") -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font(font_kind))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## Small tracked uppercase caption (e.g. stat names).
static func caption(text: String, color := FAINT) -> Label:
	return label(text.to_upper(), SIZE_CAPTION, color, "caps")


static func title(text: String, size := SIZE_TITLE) -> Label:
	return label(text, size, GOLD_LIGHT, "display")


static func button(text: String, icon_name := "", secondary := false) -> Button:
	var b := Button.new()
	b.text = text.to_upper()
	if icon_name != "":
		b.icon = icon(icon_name)
		b.expand_icon = false
	if secondary:
		b.theme_type_variation = "SecondaryButton"
	b.custom_minimum_size = Vector2(0, 48)
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_filter = Control.MOUSE_FILTER_STOP
	return b


## Round icon-only button (close, menu, collapse).
static func icon_button(icon_name: String, size := 44) -> Button:
	var b := Button.new()
	b.icon = icon(icon_name)
	b.theme_type_variation = "SecondaryButton"
	b.custom_minimum_size = Vector2(size, size)
	b.focus_mode = Control.FOCUS_NONE
	b.expand_icon = true
	for state in ["normal", "hover", "pressed"]:
		var sb := (b.get_theme_stylebox(state, "SecondaryButton") as StyleBoxFlat).duplicate() as StyleBoxFlat
		sb.set_corner_radius_all(size / 2)
		sb.content_margin_left = 12
		sb.content_margin_right = 12
		sb.content_margin_top = 12
		sb.content_margin_bottom = 12
		b.add_theme_stylebox_override(state, sb)
	return b


static func icon_rect(icon_name: String, size := 24, color := GOLD) -> TextureRect:
	var r := TextureRect.new()
	r.texture = icon(icon_name)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.custom_minimum_size = Vector2(size, size)
	r.modulate = color
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


static func dot(color: Color, size := 8) -> Control:
	var c := ColorRect.new()
	c.color = color
	c.custom_minimum_size = Vector2(size, size)
	c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


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
		return "$%.1fK" % (amount / 1000.0)
	return money(amount)


static func duration(ms: int) -> String:
	var s := maxi(0, ms / 1000)
	if s >= 3600:
		return "%dh %02dm" % [s / 3600, (s % 3600) / 60]
	if s >= 60:
		return "%dm %02ds" % [s / 60, s % 60]
	return "%ds" % s

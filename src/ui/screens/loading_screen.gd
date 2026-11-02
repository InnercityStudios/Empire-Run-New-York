class_name LoadingScreen
extends CanvasLayer
## World loading overlay: key art, real build-stage progress and rotating
## gameplay tips. Progress comes from the caller (set_progress) — nothing is
## faked on a timer. Tips rotate on a Timer, not per frame.

const TIPS_PATH := "res://data/ui/tips.json"
const TIP_SECONDS := 5.0

var _bar: ProgressBar
var _stage: Label
var _tip: Label
var _tips: Array = []
var _tip_index := 0
var _root: Control


func _ready() -> void:
	layer = 50
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.theme = UiTheme.theme()
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.018, 0.016)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(bg)
	var art := TextureRect.new()
	art.texture = load("res://assets/branding/loading_screen.png")
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(art)
	var shade := TextureRect.new()
	shade.texture = _bottom_gradient()
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	shade.offset_top = -300
	_root.add_child(shade)
	var m := UiKit.safe_margins(_root)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	box.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	box.offset_left = m.x + 120
	box.offset_right = -m.z - 120
	box.offset_top = -m.w - 190
	box.offset_bottom = -m.w - 44
	_root.add_child(box)
	_tip = UiTheme.label("", 19, UiKit.IVORY, "body_medium")
	_tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip.custom_minimum_size = Vector2(0, 54)
	box.add_child(_tip)
	_bar = ProgressBar.new()
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(0, 6)
	_bar.max_value = 1.0
	var bg_s := StyleBoxFlat.new()
	bg_s.bg_color = Color(1, 1, 1, 0.1)
	bg_s.set_corner_radius_all(3)
	var fill := StyleBoxFlat.new()
	fill.bg_color = UiTheme.GOLD
	fill.set_corner_radius_all(3)
	_bar.add_theme_stylebox_override("background", bg_s)
	_bar.add_theme_stylebox_override("fill", fill)
	box.add_child(_bar)
	var row := HBoxContainer.new()
	box.add_child(row)
	_stage = UiTheme.caption("Preparing", UiTheme.MUTED)
	_stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_stage)
	row.add_child(UiTheme.caption("Greater New York  ·  1977", UiTheme.FAINT))
	_load_tips()
	if bool(App.get_setting("gameplay", "tips")) and not _tips.is_empty():
		_tip_index = randi() % _tips.size()
		_tip.text = _tips[_tip_index]
		var t := Timer.new()
		t.wait_time = TIP_SECONDS
		t.autostart = true
		t.timeout.connect(_next_tip)
		add_child(t)


func set_progress(value: float, stage: String) -> void:
	if _bar == null:
		return
	create_tween().tween_property(_bar, "value", clampf(value, 0.0, 1.0), 0.25)
	_stage.text = stage


func dismiss() -> void:
	if _root == null:
		return
	set_progress(1.0, "Ready")
	var tw := create_tween()
	tw.tween_interval(0.25)
	tw.tween_property(_root, "modulate:a", 0.0, 0.6)
	tw.tween_callback(queue_free)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root = null


func _next_tip() -> void:
	_tip_index = (_tip_index + 1) % _tips.size()
	var tw := create_tween()
	tw.tween_property(_tip, "modulate:a", 0.0, 0.3)
	tw.tween_callback(func(): _tip.text = _tips[_tip_index])
	tw.tween_property(_tip, "modulate:a", 1.0, 0.3)


func _load_tips() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(TIPS_PATH))
	if parsed is Dictionary:
		for t in parsed.get("tips", []):
			_tips.append(tr(String(t)))


static func _bottom_gradient() -> Texture2D:
	var g := GradientTexture2D.new()
	g.fill_from = Vector2(0.5, 0)
	g.fill_to = Vector2(0.5, 1)
	var gr := Gradient.new()
	gr.colors = PackedColorArray([Color(0.02, 0.018, 0.016, 0.0), Color(0.02, 0.018, 0.016, 0.92)])
	g.gradient = gr
	return g

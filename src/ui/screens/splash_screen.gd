class_name SplashScreen
extends Control
## Launch splash: the Empire logo resolves out of black with a slow light sweep,
## then hands over to the menu. Tap to skip. ~3 s, no per-frame script work.

signal finished

const SWEEP := preload("res://src/ui/shaders/logo_sweep.gdshader")

var _done := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.018, 0.016)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var glow := TextureRect.new()
	glow.texture = _radial()
	glow.set_anchors_preset(Control.PRESET_CENTER)
	glow.size = Vector2(1400, 900)
	glow.position = -glow.size * 0.5
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.modulate = Color(UiTheme.GOLD, 0.0)
	add_child(glow)
	var logo := TextureRect.new()
	logo.texture = load("res://assets/branding/logo_empire.png")
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.set_anchors_preset(Control.PRESET_CENTER)
	logo.size = Vector2(900, 430)
	logo.position = -logo.size * 0.5 + Vector2(0, -20)
	logo.pivot_offset = logo.size * 0.5
	var mat := ShaderMaterial.new()
	mat.shader = SWEEP
	logo.material = mat
	logo.modulate.a = 0.0
	logo.scale = Vector2(0.965, 0.965)
	add_child(logo)
	var line := UiTheme.label("NEW YORK  ·  1977", 18, UiTheme.MUTED, "caps")
	line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	line.set_anchors_preset(Control.PRESET_CENTER)
	line.size = Vector2(600, 30)
	line.position = Vector2(-300, 230)
	line.modulate.a = 0.0
	add_child(line)
	App.play_title(-12.0)
	var tw := create_tween().set_parallel()
	tw.tween_property(glow, "modulate:a", 0.22, 1.6)
	tw.tween_property(logo, "modulate:a", 1.0, 1.2).set_delay(0.3)
	tw.tween_property(logo, "scale", Vector2.ONE, 2.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_method(func(v: float): mat.set_shader_parameter("sweep", v), -0.3, 1.3, 1.6).set_delay(0.9)
	tw.tween_property(line, "modulate:a", 1.0, 0.8).set_delay(1.4)
	tw.chain().tween_interval(0.7)
	tw.chain().tween_callback(_finish)


func _gui_input(e: InputEvent) -> void:
	if (e is InputEventMouseButton and e.pressed) or (e is InputEventScreenTouch and e.pressed):
		_finish()


func _finish() -> void:
	if _done:
		return
	_done = true
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.45)
	tw.tween_callback(func():
		finished.emit()
		queue_free())


static func _radial() -> Texture2D:
	var g := GradientTexture2D.new()
	g.fill = GradientTexture2D.FILL_RADIAL
	g.fill_from = Vector2(0.5, 0.5)
	g.fill_to = Vector2(1.0, 0.5)
	var gr := Gradient.new()
	gr.set_color(0, Color(1, 1, 1, 1))
	gr.set_color(1, Color(1, 1, 1, 0))
	g.gradient = gr
	return g

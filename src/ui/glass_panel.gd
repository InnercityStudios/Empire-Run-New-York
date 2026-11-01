class_name GlassPanel
extends PanelContainer
## Frosted-glass surface used by every floating panel: blurred map behind a
## dark tint, rounded corners, hairline border and a soft drop shadow.
## Add children to `content` (a MarginContainer), not to the panel itself.

const SHADER := preload("res://src/ui/shaders/glass.gdshader")

@export var radius := 10.0
@export var padding := Vector4(16, 12, 16, 12)  ## left, top, right, bottom
@export var accent := false

var content: MarginContainer
var _glass: ColorRect
var _mat: ShaderMaterial


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shadow := StyleBoxFlat.new()
	shadow.bg_color = Color(0, 0, 0, 0)
	shadow.shadow_color = Color(0, 0, 0, 0.32)
	shadow.shadow_size = 14
	shadow.shadow_offset = Vector2(0, 4)
	add_theme_stylebox_override("panel", shadow)
	_glass = ColorRect.new()
	_glass.name = "Glass"
	_glass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_glass.material = _mat
	add_child(_glass)
	content = MarginContainer.new()
	content.name = "Content"
	content.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(content)


func _ready() -> void:
	(get_theme_stylebox("panel") as StyleBoxFlat).set_corner_radius_all(int(radius))
	content.add_theme_constant_override("margin_left", int(padding.x))
	content.add_theme_constant_override("margin_top", int(padding.y))
	content.add_theme_constant_override("margin_right", int(padding.z))
	content.add_theme_constant_override("margin_bottom", int(padding.w))
	_mat.set_shader_parameter("radius", radius)
	_mat.set_shader_parameter("top_accent", 1.0 if accent else 0.0)
	if QualityFlags.off("blur"):
		_mat.set_shader_parameter("blur_lod", 0.0)
		_mat.set_shader_parameter("tint", Color(0.055, 0.05, 0.045, 0.9))
	resized.connect(_sync)
	_sync()


func set_border(color: Color) -> void:
	_mat.set_shader_parameter("border_color", color)


func _sync() -> void:
	_mat.set_shader_parameter("rect_size", size)

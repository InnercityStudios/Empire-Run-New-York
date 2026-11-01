class_name SelectionRing
extends MeshInstance3D
## Ground ring marking the current selection (buildings and crews).

const SHADER := preload("res://src/world/shaders/selection_ring.gdshader")
const SEGMENTS := 64

var _target: Callable
var _radius := 6.0


func _ready() -> void:
	mesh = _build_ring(1.0, 0.82)
	var m := ShaderMaterial.new()
	m.shader = SHADER
	material_override = m
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visible = false


## Track a position provider (Callable -> Vector3) with a ring of `radius` metres.
func show_at(target: Callable, radius: float) -> void:
	_target = target
	_radius = radius
	visible = true
	scale = Vector3.ONE * radius * 0.6
	create_tween().tween_property(self, "scale", Vector3.ONE * radius, 0.25).set_trans(Tween.TRANS_BACK)
	_update()


func clear() -> void:
	_target = Callable()
	visible = false


func _process(_delta: float) -> void:
	if visible:
		_update()


func _update() -> void:
	if not _target.is_valid():
		visible = false
		return
	var p: Vector3 = _target.call()
	global_position = Vector3(p.x, 0.22, p.z)


static func _build_ring(outer: float, inner: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in SEGMENTS:
		var a0 := TAU * i / SEGMENTS
		var a1 := TAU * (i + 1) / SEGMENTS
		var u0 := float(i) / SEGMENTS
		var u1 := float(i + 1) / SEGMENTS
		var p := [
			[Vector3(cos(a0) * inner, 0, sin(a0) * inner), Vector2(u0, 0)],
			[Vector3(cos(a0) * outer, 0, sin(a0) * outer), Vector2(u0, 1)],
			[Vector3(cos(a1) * outer, 0, sin(a1) * outer), Vector2(u1, 1)],
			[Vector3(cos(a1) * inner, 0, sin(a1) * inner), Vector2(u1, 0)],
		]
		for idx in [0, 1, 2, 0, 2, 3]:
			st.set_normal(Vector3.UP)
			st.set_uv(p[idx][1])
			st.add_vertex(p[idx][0])
	return st.commit()

class_name StrategyCamera
extends Node3D
## Elevated strategy camera for touch and desktop.
##
## Touch: one finger pans (the ground point under the finger stays under it),
## pinch zooms toward the pinch centre, two-finger twist rotates.
## Desktop: left-drag pans, wheel zooms toward the cursor, right-drag rotates,
## WASD/arrows pan, Q/E rotate.
## Pitch flattens as you zoom in, so close-ups read like a street-level
## tactical view and the strategic view stays readable.

signal tapped(screen_pos: Vector2)
signal distance_changed(distance: float)
signal follow_cancelled

@export var min_distance := 58.0
@export var max_distance := 720.0
@export var pitch_near_deg := 42.0
@export var pitch_far_deg := 60.0
@export var fov_deg := 30.0
@export var smoothing := 12.0
@export var tap_slop_px := 14.0
@export var keyboard_pan_speed := 0.9

var camera: Camera3D
var focus := Vector3.ZERO
var target_focus := Vector3.ZERO
var distance := 150.0
var target_distance := 150.0
var yaw := deg_to_rad(-32.0)
var target_yaw := deg_to_rad(-32.0)
var bounds := Rect2(-300, -300, 600, 600)
var follow_target: Node3D
var input_enabled := true

var _touches: Dictionary = {}
var _drag_anchor: Variant = null
var _press_pos := Vector2.ZERO
var _press_time := 0
var _moved := false
var _velocity := Vector3.ZERO
var _last_drag_ms := 0
var _pinch_start := {}
var _rotating := false
var _last_distance := -1.0


func _ready() -> void:
	camera = Camera3D.new()
	camera.name = "Camera"
	camera.fov = fov_deg
	camera.near = 1.0
	camera.far = 2500.0
	add_child(camera)
	camera.make_current()
	add_to_group("strategy_camera")
	_apply(true)


func set_bounds(r: Rect2) -> void:
	bounds = r
	target_focus = _clamp_focus(target_focus)


func focus_on(point: Vector3, new_distance := -1.0, instant := false) -> void:
	target_focus = _clamp_focus(Vector3(point.x, 0, point.z))
	if new_distance > 0.0:
		target_distance = clampf(new_distance, min_distance, max_distance)
	if instant:
		focus = target_focus
		distance = target_distance
		_apply(true)


func follow(node: Node3D) -> void:
	follow_target = node


func stop_follow(emit := true) -> void:
	if follow_target and emit:
		follow_cancelled.emit()
	follow_target = null


func pitch_for(d: float) -> float:
	var t := inverse_lerp(min_distance, max_distance, d)
	t = clampf(t, 0.0, 1.0)
	return deg_to_rad(lerpf(pitch_near_deg, pitch_far_deg, ease(t, 0.8)))


## Ground-plane (y = 0) point under a screen position.
func ground_point(screen_pos: Vector2, plane_y := 0.0) -> Variant:
	var o := camera.project_ray_origin(screen_pos)
	var d := camera.project_ray_normal(screen_pos)
	if absf(d.y) < 1e-4:
		return null
	var t := (plane_y - o.y) / d.y
	if t < 0.0:
		return null
	return o + d * t


func _process(delta: float) -> void:
	if follow_target and is_instance_valid(follow_target):
		var p := follow_target.global_position
		target_focus = _clamp_focus(Vector3(p.x, 0, p.z))
	elif _drag_anchor == null and _velocity.length() > 0.05:
		target_focus = _clamp_focus(target_focus + _velocity * delta)
		focus = _clamp_focus(focus + _velocity * delta)
		_velocity = _velocity.lerp(Vector3.ZERO, 1.0 - exp(-4.5 * delta))
	if input_enabled:
		_keyboard(delta)
	var k := 1.0 - exp(-smoothing * delta)
	focus = focus.lerp(target_focus, k)
	distance = lerpf(distance, target_distance, k)
	yaw = lerp_angle(yaw, target_yaw, k)
	_apply()


func _apply(force := false) -> void:
	var pitch := pitch_for(distance)
	var b := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -pitch)
	global_position = focus
	camera.global_transform = Transform3D(b, focus + b * Vector3(0, 0, distance))
	if force or absf(distance - _last_distance) > 0.5:
		_last_distance = distance
		distance_changed.emit(distance)


func _clamp_focus(p: Vector3) -> Vector3:
	return Vector3(clampf(p.x, bounds.position.x, bounds.end.x), 0.0, clampf(p.z, bounds.position.y, bounds.end.y))


func _keyboard(delta: float) -> void:
	var v := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		v.y -= 1
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		v.y += 1
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		v.x -= 1
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		v.x += 1
	if v != Vector2.ZERO:
		stop_follow()
		var move := Basis(Vector3.UP, yaw) * Vector3(v.x, 0, v.y) * distance * keyboard_pan_speed * delta
		target_focus = _clamp_focus(target_focus + move)
	if Input.is_physical_key_pressed(KEY_Q):
		target_yaw += 1.6 * delta
	if Input.is_physical_key_pressed(KEY_E):
		target_yaw -= 1.6 * delta


# --- Input -------------------------------------------------------------------------
func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled:
		return
	if event is InputEventScreenTouch:
		_on_touch(event)
	elif event is InputEventScreenDrag:
		_on_touch_drag(event)
	elif event is InputEventMouseButton and event.device != InputEvent.DEVICE_ID_EMULATION:
		_on_mouse_button(event)
	elif event is InputEventMouseMotion and event.device != InputEvent.DEVICE_ID_EMULATION:
		_on_mouse_motion(event)
	elif event is InputEventMagnifyGesture:
		_zoom_at(event.position, 1.0 / event.factor)
	elif event is InputEventPanGesture:
		_zoom_at(event.position, 1.0 + event.delta.y * 0.05)
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode in [KEY_EQUAL, KEY_KP_ADD]:
			target_distance = clampf(target_distance * 0.8, min_distance, max_distance)
		elif event.physical_keycode in [KEY_MINUS, KEY_KP_SUBTRACT]:
			target_distance = clampf(target_distance * 1.25, min_distance, max_distance)


func _begin_press(pos: Vector2) -> void:
	_press_pos = pos
	_press_time = Time.get_ticks_msec()
	_moved = false
	_velocity = Vector3.ZERO
	_drag_anchor = ground_point(pos)


func _drag_to(pos: Vector2) -> void:
	if not _moved and pos.distance_to(_press_pos) > tap_slop_px:
		_moved = true
		stop_follow()
	if not _moved or _drag_anchor == null:
		return
	var now: Variant = ground_point(pos)
	if now == null:
		return
	var delta: Vector3 = (_drag_anchor as Vector3) - (now as Vector3)
	delta.y = 0
	var before := focus
	focus = _clamp_focus(focus + delta)
	target_focus = focus
	_apply()
	var dt := maxf((Time.get_ticks_msec() - _last_drag_ms) / 1000.0, 0.001)
	_last_drag_ms = Time.get_ticks_msec()
	_velocity = _velocity.lerp((focus - before) / dt, 0.35)


func _end_press(pos: Vector2) -> void:
	if not _moved and pos.distance_to(_press_pos) <= tap_slop_px and Time.get_ticks_msec() - _press_time < 600:
		_velocity = Vector3.ZERO
		tapped.emit(pos)
	elif Time.get_ticks_msec() - _last_drag_ms > 80:
		_velocity = Vector3.ZERO
	_velocity = _velocity.limit_length(distance * 3.0)
	_drag_anchor = null


func _on_mouse_button(e: InputEventMouseButton) -> void:
	match e.button_index:
		MOUSE_BUTTON_LEFT:
			if e.pressed:
				_begin_press(e.position)
			else:
				_end_press(e.position)
		MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE:
			_rotating = e.pressed
		MOUSE_BUTTON_WHEEL_UP:
			if e.pressed:
				_zoom_at(e.position, 0.88)
		MOUSE_BUTTON_WHEEL_DOWN:
			if e.pressed:
				_zoom_at(e.position, 1.14)


func _on_mouse_motion(e: InputEventMouseMotion) -> void:
	if _rotating:
		target_yaw -= e.relative.x * 0.006
	elif e.button_mask & MOUSE_BUTTON_MASK_LEFT and _drag_anchor != null:
		_drag_to(e.position)


func _zoom_at(screen_pos: Vector2, factor: float) -> void:
	var old := target_distance
	target_distance = clampf(target_distance * factor, min_distance, max_distance)
	var p: Variant = ground_point(screen_pos)
	if p != null and follow_target == null:
		var ratio := 1.0 - target_distance / old
		var g: Vector3 = p
		target_focus = _clamp_focus(target_focus + (Vector3(g.x, 0, g.z) - target_focus) * ratio)


func _on_touch(e: InputEventScreenTouch) -> void:
	if e.pressed:
		_touches[e.index] = e.position
		if _touches.size() == 1:
			_begin_press(e.position)
		elif _touches.size() == 2:
			_moved = true
			_drag_anchor = null
			_start_pinch()
	else:
		_touches.erase(e.index)
		if _touches.is_empty():
			_end_press(e.position)
		elif _touches.size() == 1:
			# Continue panning with the remaining finger.
			var p: Vector2 = _touches.values()[0]
			_drag_anchor = ground_point(p)
			_pinch_start = {}


func _on_touch_drag(e: InputEventScreenDrag) -> void:
	_touches[e.index] = e.position
	if _touches.size() == 1:
		_drag_to(e.position)
	elif _touches.size() == 2 and not _pinch_start.is_empty():
		var pts: Array = _touches.values()
		var d: float = maxf((pts[0] as Vector2).distance_to(pts[1]), 1.0)
		var mid: Vector2 = ((pts[0] as Vector2) + (pts[1] as Vector2)) * 0.5
		var ang: float = ((pts[1] as Vector2) - (pts[0] as Vector2)).angle()
		target_distance = clampf(_pinch_start["distance"] * _pinch_start["span"] / d, min_distance, max_distance)
		var twist: float = wrapf(ang - _pinch_start["angle"], -PI, PI)
		if absf(twist) > 0.12 or _pinch_start["rotating"]:
			_pinch_start["rotating"] = true
			target_yaw = _pinch_start["yaw"] + twist
		var g: Variant = ground_point(mid)
		var g0: Variant = _pinch_start["anchor"]
		if g != null and g0 != null:
			stop_follow()
			var delta: Vector3 = (g0 as Vector3) - (g as Vector3)
			target_focus = _clamp_focus(target_focus + Vector3(delta.x, 0, delta.z) * 0.5)


func _start_pinch() -> void:
	var pts: Array = _touches.values()
	var mid: Vector2 = ((pts[0] as Vector2) + (pts[1] as Vector2)) * 0.5
	_pinch_start = {
		"span": maxf((pts[0] as Vector2).distance_to(pts[1]), 1.0),
		"distance": target_distance,
		"angle": ((pts[1] as Vector2) - (pts[0] as Vector2)).angle(),
		"yaw": target_yaw,
		"rotating": false,
		"anchor": ground_point(mid),
	}


## Development hook used by DevCapture: {x, z, distance, yaw_deg}.
func dev_set_view(v: Dictionary) -> void:
	if v.has("yaw_deg"):
		target_yaw = deg_to_rad(v["yaw_deg"])
		yaw = target_yaw
	focus_on(Vector3(v.get("x", focus.x), 0, v.get("z", focus.z)), v.get("distance", distance), true)

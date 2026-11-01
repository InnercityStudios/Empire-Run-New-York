class_name Minimap
extends Control
## Compact province map drawn from the real world geography: coastlines,
## parks, arterials and bridges, territory colours, business and crew dots,
## the camera's view and a compass. Tap or drag to move the camera there.
##
## The static map is a child control that only redraws when the zoom window
## changes; markers redraw every few frames (cheap 2D primitives).

signal travel_requested(world_point: Vector2)

const SPAN := 2600.0          ## metres shown across the map
const WATER := Color("#1b3440")
const LAND := Color("#3b3832")
const PARK := Color("#4a6b3a")
const ROAD := Color(0.84, 0.78, 0.66, 0.55)
const BRIDGE := Color("#c9a24a")

var layout: WorldLayout
var camera: StrategyCamera
var center := Vector2.ZERO
var _static: Control
var _last_center := Vector2.ZERO
var _dirty := true
var _territory: Dictionary = {}   ## district id -> Color
var _tick := 0


func setup(p_layout: WorldLayout, p_camera: StrategyCamera) -> void:
	layout = p_layout
	camera = p_camera
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_static = Control.new()
	_static.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_static.size = size
	_static.draw.connect(_draw_static)
	add_child(_static)
	resized.connect(func():
		_static.size = size
		_dirty = true)
	for d in layout.districts:
		match String(d.get("territory", "neutral")):
			"player":
				_territory[d["id"]] = Color(UiTheme.GOLD, 0.55)
			"rival":
				_territory[d["id"]] = Color(UiTheme.RED, 0.45)
			"contested":
				_territory[d["id"]] = Color("#9a6fc1", 0.4)


func to_map(p: Vector2) -> Vector2:
	return (p - center) * (size.x / SPAN) + size * 0.5


func to_world(m: Vector2) -> Vector2:
	return (m - size * 0.5) / (size.x / SPAN) + center


func _process(_delta: float) -> void:
	if camera == null or not is_visible_in_tree():
		return
	center = Vector2(camera.focus.x, camera.focus.z)
	# The static layer follows the camera in coarse steps (cheap redraws).
	if _dirty or center.distance_to(_last_center) > SPAN * 0.04:
		_dirty = false
		_last_center = center
		_static.queue_redraw()
	_tick += 1
	if _tick % 3 == 0:
		queue_redraw()


func _draw_static() -> void:
	if layout == null:
		return
	var c := _last_center
	var k := size.x / SPAN
	var tf := func(p: Vector2) -> Vector2: return (p - c) * k + size * 0.5
	_static.draw_rect(Rect2(Vector2.ZERO, size), WATER)
	var view := Rect2(c - size / k * 0.5, size / k).grow(200.0)
	for lp in layout.land_polygons:
		var poly: PackedVector2Array = lp["polygon"]
		_static.draw_colored_polygon(_xf(poly, c, k), LAND)
	# Territory: blocks of player, rival and contested districts.
	for b in layout.blocks:
		var col: Color = _territory.get(b.get("district", "little_italy" if not b.has("xform") else ""), Color.TRANSPARENT)
		if col.a <= 0.0:
			continue
		var bc := WorldLayout.block_center(b)
		if not view.has_point(bc):
			continue
		_static.draw_colored_polygon(_xf(WorldLayout.block_corners(b), c, k), col)
	for pk in layout.park_areas:
		_static.draw_colored_polygon(_xf(pk["polygon"], c, k), PARK)
	for seg in layout.road_segments:
		if float(seg["width"]) < 16.0:
			continue
		var a: Vector2 = seg["from"]
		if not view.has_point(a):
			continue
		_static.draw_line(tf.call(a), tf.call(seg["to"]), ROAD, maxf(1.0, float(seg["width"]) * k * 1.6))
	for br in layout.bridge_paths:
		_static.draw_polyline(_xf(br["path"], c, k), BRIDGE, 2.5)


func _xf(poly: PackedVector2Array, c: Vector2, k: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(poly.size())
	var half := size * 0.5
	for i in poly.size():
		out[i] = (poly[i] - c) * k + half
	return out


func _draw() -> void:
	if layout == null or camera == null:
		return
	# Offset of the cached static layer relative to the live centre.
	_static.position = (_last_center - center) * (size.x / SPAN)
	if Game.is_running():
		var world := Game.world
		for b in world.businesses.values():
			var lm: Dictionary = layout.landmarks.get(b.landmark_id, {})
			if lm.is_empty():
				continue
			var f := world.faction(b.owner_id)
			var col := Color.html(f.color) if f else UiTheme.MUTED
			var p := to_map(lm["frontage"])
			draw_circle(p, 4.5, Color(0, 0, 0, 0.6))
			draw_circle(p, 3.2, col)
		var now := Game.now_ms_f()
		for crew in world.crews.values():
			var pc: Vector2 = crew.position_cm(now, world.roads) / 100.0
			var mine: bool = crew.owner_id == world.player_faction_id
			draw_rect(Rect2(to_map(pc) - Vector2(2.5, 2.5), Vector2(5, 5)), UiTheme.CREAM if mine else UiTheme.RED)
	# Camera view wedge.
	var cp := size * 0.5
	var fwd := Vector2(-sin(camera.yaw), -cos(camera.yaw))
	var reach := clampf(camera.distance * 1.6 * size.x / SPAN, 10.0, size.x * 0.45)
	var side := Vector2(-fwd.y, fwd.x) * reach * 0.7
	draw_colored_polygon(PackedVector2Array([cp, cp + fwd * reach + side, cp + fwd * reach - side]),
		Color(UiTheme.GOLD_LIGHT, 0.16))
	draw_circle(cp, 3.5, UiTheme.GOLD_LIGHT)
	# Compass (north is -Z).
	var nc := Vector2(size.x - 18, 18)
	draw_circle(nc, 12, Color(0, 0, 0, 0.55))
	draw_arc(nc, 12, 0, TAU, 24, Color(UiTheme.GOLD, 0.8), 1.2, true)
	draw_colored_polygon(PackedVector2Array([nc + Vector2(0, -9), nc + Vector2(-4, 2), nc + Vector2(4, 2)]), UiTheme.GOLD_LIGHT)
	draw_string(UiTheme.font("body_bold"), nc + Vector2(-4, 9), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, UiTheme.CREAM)


func _gui_input(e: InputEvent) -> void:
	var pressed: bool = (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT) \
		or (e is InputEventScreenTouch and e.pressed)
	if pressed:
		travel_requested.emit(to_world(e.position))
		accept_event()

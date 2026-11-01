class_name WorldMarkers
extends Control
## Screen-space markers anchored to the 3D world, drawn in 2D so they stay
## crisp and tappable at any zoom. Label density follows importance:
## - selected entity: full label (name, level / power, health);
## - your own places: name only when zoomed in; rivals and neutrals: icon pin;
## - crews: a compact power pill unless selected.

signal marker_pressed(kind: String, id: String)
signal collect_pressed(business_id: String)

const NAME_DISTANCE_OWN := 190.0
const NAME_DISTANCE_OTHER := 110.0
const COLLECT_THRESHOLD := 0.1

var camera: Camera3D
var world_view: CityWorld
var crew_views: Dictionary = {}
var selected := {}
var _bubbles: Array = []
var _pins: Array = []
var _time := 0.0
var _plate := StyleBoxFlat.new()
var _plate_sel := StyleBoxFlat.new()
var _gold := StyleBoxFlat.new()


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for sb in [_plate, _plate_sel, _gold]:
		sb.set_corner_radius_all(6)
		sb.anti_aliasing = true
	_plate.bg_color = Color(0.05, 0.045, 0.04, 0.78)
	_plate_sel.bg_color = Color(0.05, 0.045, 0.04, 0.9)
	_plate_sel.border_color = Color(UiTheme.GOLD, 0.8)
	_plate_sel.set_border_width_all(1)
	_gold.bg_color = UiTheme.GOLD
	_gold.set_corner_radius_all(12)
	_gold.shadow_color = Color(0, 0, 0, 0.35)
	_gold.shadow_size = 4


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


## Returns true if a marker consumed the tap (checked before world picking).
func handle_tap(screen_pos: Vector2) -> bool:
	var local := get_global_transform_with_canvas().affine_inverse() * screen_pos
	for b in _bubbles:
		if (b["rect"] as Rect2).grow(12).has_point(local):
			collect_pressed.emit(b["business"])
			return true
	for p in _pins:
		if (p["rect"] as Rect2).grow(10).has_point(local):
			marker_pressed.emit(p["kind"], p["id"])
			return true
	return false


func _camera_distance() -> float:
	var pitch_sin := maxf(sin(-camera.global_rotation.x), 0.2)
	return camera.global_position.y / pitch_sin


func _draw() -> void:
	_bubbles.clear()
	_pins.clear()
	if camera == null or world_view == null or not Game.is_running():
		return
	var world := Game.world
	var now := Game.now_ms()
	var dist := _camera_distance()
	var to_local := get_global_transform_with_canvas().affine_inverse()
	var sel_id: String = selected.get("id", "")
	for id in world_view.landmarks:
		var lv: LandmarkView = world_view.landmarks[id]
		var anchor := lv.marker_anchor()
		if camera.is_position_behind(anchor):
			continue
		var sp := to_local * camera.unproject_position(anchor)
		var b := world.business_at_landmark(id)
		var hq := world.hq_at_landmark(id)
		var entity_id: String = hq.faction_id if hq else (b.id if b else "")
		var owner_id: String = b.owner_id if b else (hq.faction_id if hq else "")
		var f := world.faction(owner_id)
		var col := Color.html(f.color) if f else UiTheme.MUTED
		var mine := owner_id == world.player_faction_id
		var is_sel := sel_id == entity_id
		var icon_name: String = "hq" if hq else SelectionPanelBuilder.TYPE_ICONS.get(b.type_id if b else "", "cash")
		_draw_pin(sp, icon_name, col, is_sel)
		_pins.append({"rect": Rect2(sp - Vector2(24, 54), Vector2(48, 56)), "kind": "hq" if hq else "business",
			"id": entity_id})
		var show_name := is_sel or dist < (NAME_DISTANCE_OWN if mine else NAME_DISTANCE_OTHER)
		if show_name:
			var label: String = hq.name if hq else (b.name if b else id)
			var level := ("  ·  HQ %d" % hq.level) if hq else (("  ·  Lv %d" % b.level) if b else "")
			_draw_plate(sp + Vector2(0, 8), label + level, col, is_sel)
		if b and mine:
			var stored := b.stored(now, world.content)
			if stored > 0 and stored >= b.capacity(world.content) * COLLECT_THRESHOLD:
				var bob := sin(_time * 2.6 + float(id.hash() % 7)) * 3.0
				_draw_bubble(sp + Vector2(0, -74 + bob), UiTheme.short_money(stored),
					stored >= b.capacity(world.content), b.id)
	for cid in crew_views:
		var cv: CrewView = crew_views[cid]
		var crew: CrewState = world.crews.get(cid)
		if crew == null:
			continue
		var p := cv.lead_position() + Vector3(0, 3.0, 0)
		if camera.is_position_behind(p):
			continue
		var sp := to_local * camera.unproject_position(p)
		var f := world.faction(crew.owner_id)
		var col := Color.html(f.color) if f else UiTheme.MUTED
		var rect: Rect2
		if sel_id == cid:
			rect = _draw_crew_full(sp, crew, col, world)
		else:
			rect = _draw_crew_compact(sp, crew, col, world)
		_pins.append({"rect": rect, "kind": "crew", "id": cid})


func _draw_pin(p: Vector2, icon_name: String, col: Color, is_sel: bool) -> void:
	var r := 17.0 if not is_sel else 20.0
	var c := p + Vector2(0, -30)
	draw_colored_polygon(PackedVector2Array([c + Vector2(-6, r - 3), c + Vector2(6, r - 3), p + Vector2(0, -6)]),
		Color(0.05, 0.045, 0.04, 0.9))
	draw_circle(c, r + 1.5, Color(0, 0, 0, 0.35))
	draw_circle(c, r, Color(0.06, 0.055, 0.05, 0.94))
	draw_arc(c, r - 1.0, 0, TAU, 40, col, 2.5 if not is_sel else 3.0, true)
	if is_sel:
		draw_arc(c, r + 5.0 + sin(_time * 4.0) * 1.5, 0, TAU, 40, Color(UiTheme.GOLD_LIGHT, 0.7), 1.5, true)
	var s := r * 1.05
	draw_texture_rect(UiTheme.icon(icon_name), Rect2(c - Vector2(s, s) * 0.5, Vector2(s, s)), false, UiTheme.CREAM)


func _draw_plate(p: Vector2, text: String, col: Color, is_sel: bool) -> void:
	var font := UiTheme.font("body_bold")
	var fs := 15
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 22
	var rect := Rect2(p - Vector2(w * 0.5, 0), Vector2(w, 24))
	draw_style_box(_plate_sel if is_sel else _plate, rect)
	draw_rect(Rect2(rect.position + Vector2(5, 7), Vector2(3, 10)), col)
	draw_string(font, rect.position + Vector2(13, 17), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiTheme.CREAM)


func _draw_bubble(p: Vector2, text: String, full: bool, business_id: String) -> void:
	var font := UiTheme.font("body_bold")
	var fs := 16
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 44
	var rect := Rect2(p - Vector2(w * 0.5, 13), Vector2(w, 26))
	if full:
		var glow := StyleBoxFlat.new()
		glow.bg_color = Color(UiTheme.GOLD_LIGHT, 0.25 + 0.2 * sin(_time * 5.0))
		glow.set_corner_radius_all(15)
		draw_style_box(glow, rect.grow(3))
	draw_style_box(_gold, rect)
	draw_texture_rect(UiTheme.icon("cash"), Rect2(rect.position + Vector2(9, 4), Vector2(18, 18)), false, UiTheme.INK)
	draw_string(font, rect.position + Vector2(31, 19), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiTheme.INK)
	_bubbles.append({"rect": rect, "business": business_id})


func _draw_crew_compact(p: Vector2, crew: CrewState, col: Color, world: SimWorld) -> Rect2:
	var font := UiTheme.font("body_bold")
	var text := str(world.crew_power(crew.id))
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 24
	var rect := Rect2(p - Vector2(w * 0.5, 22), Vector2(w, 20))
	draw_style_box(_plate, rect)
	draw_circle(rect.position + Vector2(9, 10), 3.5, col)
	draw_string(font, rect.position + Vector2(16, 15), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UiTheme.CREAM)
	return rect.grow(8)


func _draw_crew_full(p: Vector2, crew: CrewState, col: Color, world: SimWorld) -> Rect2:
	var font := UiTheme.font("body_bold")
	var name_text := crew.name
	var power := str(world.crew_power(crew.id))
	var nw := font.get_string_size(name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
	var pw := font.get_string_size(power, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
	var w := nw + pw + 40
	var rect := Rect2(p - Vector2(w * 0.5, 34), Vector2(w, 26))
	draw_style_box(_plate_sel, rect)
	draw_circle(rect.position + Vector2(11, 13), 4.0, col)
	draw_string(font, rect.position + Vector2(20, 18), power, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, UiTheme.GOLD_LIGHT)
	draw_string(font, rect.position + Vector2(28 + pw, 18), name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, UiTheme.CREAM)
	var hp := Rect2(rect.position + Vector2(6, rect.size.y + 3), Vector2(w - 12, 3))
	draw_rect(hp, Color(0, 0, 0, 0.6))
	var frac := float(crew.hp) / maxf(float(crew.max_hp), 1.0)
	draw_rect(Rect2(hp.position, Vector2(hp.size.x * frac, 3)), UiTheme.GREEN if frac > 0.4 else UiTheme.RED)
	return rect.grow(8)

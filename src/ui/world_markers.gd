class_name WorldMarkers
extends Control
## Screen-space markers anchored to the 3D world: building pins with owner
## colours and names, tap-to-collect cash bubbles, and crew name plates with
## power and health. Drawn in 2D so they stay crisp and tappable at any zoom.

signal marker_pressed(kind: String, id: String)
signal collect_pressed(business_id: String)

const NAME_FADE_FAR := 300.0
const COLLECT_THRESHOLD := 0.1  ## show the cash bubble when storage is 10% full

var camera: Camera3D
var world_view: CityWorld
var crew_views: Dictionary = {}  ## crew id -> CrewView
var selected := {}
var _bubbles: Array = []         ## [{rect: Rect2, business: String}]
var _pins: Array = []            ## [{rect: Rect2, kind, id}]
var _time := 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


## Called by the main controller before world picking; returns true if a
## marker consumed the tap.
func handle_tap(screen_pos: Vector2) -> bool:
	var local := get_global_transform_with_canvas().affine_inverse() * screen_pos
	for b in _bubbles:
		if (b["rect"] as Rect2).grow(10).has_point(local):
			collect_pressed.emit(b["business"])
			return true
	for p in _pins:
		if (p["rect"] as Rect2).grow(6).has_point(local):
			marker_pressed.emit(p["kind"], p["id"])
			return true
	return false


func _draw() -> void:
	_bubbles.clear()
	_pins.clear()
	if camera == null or world_view == null or not Game.is_running():
		return
	var world := Game.world
	var now := Game.now_ms()
	var cam_dist := camera.global_position.y / maxf(sin(-camera.global_rotation.x), 0.2)
	var name_alpha := clampf(1.0 - (cam_dist - NAME_FADE_FAR * 0.7) / (NAME_FADE_FAR * 0.3), 0.0, 1.0)
	var to_local := get_global_transform_with_canvas().affine_inverse()
	for id in world_view.landmarks:
		var lv: LandmarkView = world_view.landmarks[id]
		var anchor := lv.marker_anchor()
		if camera.is_position_behind(anchor):
			continue
		var sp := to_local * camera.unproject_position(anchor)
		var b := world.business_at_landmark(id)
		var hq := world.hq_at_landmark(id)
		var owner_id := b.owner_id if b else (hq.faction_id if hq else "")
		var f := world.faction(owner_id)
		var col := Color.html(f.color) if f else UiTheme.MUTED
		var icon_name: String = "hq" if hq else SelectionPanelBuilder.TYPE_ICONS.get(b.type_id if b else "", "cash")
		var label: String = hq.name if hq else (b.name if b else id)
		var is_sel: bool = selected.get("id", "") == (hq.faction_id if hq else (b.id if b else ""))
		_draw_pin(sp, icon_name, col, is_sel)
		_pins.append({"rect": Rect2(sp - Vector2(34, 74), Vector2(68, 80)), "kind": "hq" if hq else "business",
			"id": hq.faction_id if hq else (b.id if b else "")})
		if name_alpha > 0.01:
			var lvl_text := ("  Lv %d" % b.level) if b else ("  HQ %d" % hq.level if hq else "")
			_draw_plate(sp + Vector2(0, 12), label.to_upper() + lvl_text, col, name_alpha)
		if b and b.owner_id == world.player_faction_id:
			var stored := b.stored(now, world.content)
			if stored > 0 and stored >= b.capacity(world.content) * COLLECT_THRESHOLD:
				var bob := sin(_time * 3.0 + float(id.hash() % 7)) * 4.0
				var full := stored >= b.capacity(world.content)
				_draw_bubble(sp + Vector2(0, -104 + bob), UiTheme.short_money(stored), full, b.id)
	for cid in crew_views:
		var cv: CrewView = crew_views[cid]
		var crew: CrewState = world.crews.get(cid)
		if crew == null:
			continue
		var p := cv.lead_position() + Vector3(0, 3.2, 0)
		if camera.is_position_behind(p):
			continue
		var sp := to_local * camera.unproject_position(p)
		var f := world.faction(crew.owner_id)
		_draw_crew_plate(sp, crew, Color.html(f.color) if f else UiTheme.MUTED, world, selected.get("id", "") == cid)
		_pins.append({"rect": Rect2(sp - Vector2(110, 40), Vector2(220, 56)), "kind": "crew", "id": cid})


func _draw_pin(p: Vector2, icon_name: String, col: Color, is_sel: bool) -> void:
	var r := 30.0 if not is_sel else 34.0
	var c := p + Vector2(0, -44)
	draw_colored_polygon(PackedVector2Array([c + Vector2(-14, r * 0.7), c + Vector2(14, r * 0.7), p]), Color(0.05, 0.045, 0.04, 0.95))
	draw_circle(c, r + 3, UiTheme.GOLD_LIGHT if is_sel else UiTheme.GOLD)
	draw_circle(c, r, Color(0.06, 0.055, 0.05, 0.96))
	draw_arc(c, r - 4, 0, TAU, 40, col, 4.0, true)
	var tex := UiTheme.icon(icon_name)
	var s := r * 1.15
	draw_texture_rect(tex, Rect2(c - Vector2(s, s) * 0.5, Vector2(s, s)), false, UiTheme.CREAM)


func _draw_plate(p: Vector2, text: String, col: Color, alpha: float) -> void:
	var font := UiTheme.font("body_bold")
	var fs := 20
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 28
	var rect := Rect2(p - Vector2(w * 0.5, 0), Vector2(w, 30))
	draw_rect(rect, Color(0.04, 0.035, 0.03, 0.82 * alpha))
	draw_rect(Rect2(rect.position, Vector2(4, rect.size.y)), Color(col, alpha))
	draw_string(font, rect.position + Vector2(16, 22), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(UiTheme.CREAM, alpha))


func _draw_bubble(p: Vector2, text: String, full: bool, business_id: String) -> void:
	var font := UiTheme.font("body_bold")
	var fs := 24
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 64
	var rect := Rect2(p - Vector2(w * 0.5, 22), Vector2(w, 44))
	var glow := 0.5 + 0.5 * sin(_time * 5.0)
	draw_rect(rect.grow(3), Color(UiTheme.GOLD_LIGHT, 0.35 + 0.4 * glow if full else 0.25))
	draw_rect(rect, UiTheme.GOLD if not full else UiTheme.GOLD_LIGHT)
	draw_rect(rect, UiTheme.GOLD_DARK, false, 2.0)
	draw_texture_rect(UiTheme.icon("cash"), Rect2(rect.position + Vector2(10, 7), Vector2(30, 30)), false, UiTheme.INK)
	draw_string(font, rect.position + Vector2(46, 32), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiTheme.INK)
	_bubbles.append({"rect": rect, "business": business_id})


func _draw_crew_plate(p: Vector2, crew: CrewState, col: Color, world: SimWorld, is_sel: bool) -> void:
	var font := UiTheme.font("body_bold")
	var title := crew.name.to_upper()
	var power := str(world.crew_power(crew.id))
	var tw := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 19).x
	var pw := font.get_string_size(power, HORIZONTAL_ALIGNMENT_LEFT, -1, 19).x
	var w := tw + pw + 64
	var rect := Rect2(p - Vector2(w * 0.5, 36), Vector2(w, 30))
	draw_rect(rect, Color(0.04, 0.035, 0.03, 0.88))
	if is_sel:
		draw_rect(rect.grow(2), UiTheme.GOLD_LIGHT, false, 2.0)
	draw_rect(Rect2(rect.position, Vector2(26, rect.size.y)), col)
	draw_texture_rect(UiTheme.icon("power"), Rect2(rect.position + Vector2(4, 5), Vector2(19, 19)), false, UiTheme.INK)
	draw_string(font, rect.position + Vector2(32, 22), power, HORIZONTAL_ALIGNMENT_LEFT, -1, 19, UiTheme.GOLD_LIGHT)
	draw_string(font, rect.position + Vector2(40 + pw, 22), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 19, UiTheme.CREAM)
	var hp_rect := Rect2(rect.position + Vector2(0, rect.size.y + 3), Vector2(w, 6))
	draw_rect(hp_rect, Color(0, 0, 0, 0.7))
	var frac := float(crew.hp) / maxf(float(crew.max_hp), 1.0)
	draw_rect(Rect2(hp_rect.position, Vector2(w * frac, 6)), UiTheme.GREEN if frac > 0.4 else UiTheme.RED)

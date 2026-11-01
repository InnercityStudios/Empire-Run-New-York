extends Node
## Game entry point and world-map controller.
##
## Builds the district, starts the session, and connects views to it:
## taps become selections or commands, simulation events become feedback.
## Gameplay rules live in the simulation; this script only translates.

const CREW_PICK_RADIUS_PX := 64.0
const ERROR_TEXT := {
	"insufficient_cash": "Not enough cash.",
	"nothing_to_collect": "Nothing to collect yet.",
	"already_upgrading": "Already being upgraded.",
	"max_level": "Already at the highest level.",
	"not_for_sale": "That business isn't for sale.",
	"unreachable": "No route to that location.",
	"not_owner": "That isn't yours to command.",
	"no_idle_crew": "All crews are busy.",
}

@onready var world: WorldStreamer = $World
@onready var camera: StrategyCamera = $StrategyCamera
@onready var atmosphere: WorldAtmosphere = $Atmosphere

var hud: Hud
var traffic: TrafficSystem
var fader: OcclusionFader
var ring: SelectionRing
var crew_views: Dictionary = {}
var selection := {}
var move_mode_crew := ""
var follow_crew := ""
var _crew_root: Node3D


func _ready() -> void:
	add_to_group("main")
	_show_loading()
	await get_tree().process_frame
	var layout := WorldLayout.build(Content.db.worlds["greater_new_york"], Content.db)
	world.build(layout)
	world.camera = camera
	camera.set_bounds(layout.playable)
	camera.distance_changed.connect(atmosphere.on_camera_distance)
	camera.tapped.connect(_on_tap)
	camera.follow_cancelled.connect(func(): _set_follow(""))

	_crew_root = Node3D.new()
	_crew_root.name = "Crews"
	add_child(_crew_root)
	ring = SelectionRing.new()
	ring.name = "SelectionRing"
	add_child(ring)
	traffic = TrafficSystem.new()
	traffic.name = "Traffic"
	add_child(traffic)
	traffic.obstacle_provider = _crew_car_positions
	traffic.camera = camera
	if not QualityFlags.off("traffic"):
		traffic.setup(layout)
	fader = OcclusionFader.new()
	fader.name = "OcclusionFader"
	fader.world = world
	fader.camera = camera.camera
	add_child(fader)

	hud = Hud.new()
	hud.name = "Hud"
	add_child(hud)
	hud.markers.camera = camera.camera
	hud.markers.world_view = world
	hud.markers.marker_pressed.connect(_on_marker_pressed)
	hud.markers.collect_pressed.connect(func(bid): _command({"type": "collect_business", "business": bid}))
	hud.crew_card_pressed.connect(func(cid): _select({"kind": "crew", "id": cid}, true))
	hud.action_requested.connect(_on_action)
	hud.close_selection.connect(func(): _select({}))
	hud.move_mode_cancelled.connect(func(): _set_move_mode(""))

	Game.sim_event.connect(_on_sim_event)
	Game.command_failed.connect(_on_command_failed)
	Game.session_started.connect(_on_session_started)
	Game.start(layout)
	_add_ambience()
	_intro()
	world.initial_detail_ready.connect(_hide_loading, CONNECT_ONE_SHOT)
	get_tree().create_timer(12.0).timeout.connect(_hide_loading)


func _on_session_started() -> void:
	for v in crew_views.values():
		v.queue_free()
	crew_views.clear()
	for id in Game.world.crews:
		var crew: CrewState = Game.world.crews[id]
		var v := CrewView.new()
		_crew_root.add_child(v)
		v.setup(crew, world.layout.lane_offset, crew.owner_id == Game.player_id, _street_widths())
		crew_views[id] = v
	hud.markers.crew_views = crew_views
	hud.rebuild_roster(Game.world)
	_select({})


func _street_widths() -> Dictionary:
	return world.layout.street_widths()


# --- Loading screen and ambience ----------------------------------------------------
var _loading: CanvasLayer


func _show_loading() -> void:
	_loading = CanvasLayer.new()
	_loading.layer = 50
	add_child(_loading)
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.035, 0.03)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_loading.add_child(bg)
	var art := TextureRect.new()
	art.texture = load("res://assets/branding/loading_screen.png")
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.set_anchors_preset(Control.PRESET_FULL_RECT)
	_loading.add_child(art)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.35)
	shade.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	shade.offset_top = -86
	_loading.add_child(shade)
	var label := UiTheme.label("Loading Greater New York  ·  1977", UiTheme.SIZE_SMALL, UiTheme.CREAM, "body_medium")
	label.name = "Status"
	label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	label.offset_top = -58
	label.offset_left = -300
	label.offset_right = 300
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_loading.add_child(label)


func _hide_loading() -> void:
	if _loading == null or not is_instance_valid(_loading):
		return
	var layer := _loading
	_loading = null
	var tw := create_tween()
	for c in layer.get_children():
		tw.parallel().tween_property(c, "modulate:a", 0.0, 0.6)
	tw.tween_callback(layer.queue_free)


var _ambience: AudioStreamPlayer


func _add_ambience() -> void:
	_ambience = AudioStreamPlayer.new()
	_ambience.name = "CityAmbience"
	_ambience.stream = load("res://assets/audio/ambience/city_traffic.wav")
	_ambience.volume_db = -14.0
	_ambience.autoplay = true
	add_child(_ambience)
	camera.distance_changed.connect(func(d: float):
		# Street noise fades as the camera climbs to the strategic view.
		_ambience.volume_db = lerpf(-9.0, -26.0, clampf((d - 60.0) / 500.0, 0.0, 1.0)))


func _intro() -> void:
	var hq: HeadquartersState = Game.world.headquarters.get(Game.player_id)
	var target := Vector3.ZERO
	if hq and world.landmarks.has(hq.landmark_id):
		target = (world.landmarks[hq.landmark_id] as LandmarkView).entrance_point()
	camera.focus_on(target + Vector3(40, 0, 60), 320.0, true)
	camera.smoothing = 1.6
	camera.focus_on(target, 135.0)
	var title := TextureRect.new()
	title.texture = load("res://assets/branding/logo_empire.png")
	title.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	title.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	title.set_anchors_preset(Control.PRESET_CENTER)
	title.custom_minimum_size = Vector2(900, 430)
	title.position = Vector2(-450, -260)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.root.add_child(title)
	var tw := create_tween()
	tw.tween_interval(1.4)
	tw.tween_property(title, "modulate:a", 0.0, 1.2)
	tw.tween_callback(title.queue_free)
	tw.tween_callback(func(): camera.smoothing = 12.0)


func _process(delta: float) -> void:
	if not Game.is_running():
		return
	var now := Game.now_ms_f()
	for id in crew_views:
		var crew: CrewState = Game.world.crews.get(id)
		if crew:
			(crew_views[id] as CrewView).update_from(crew, Game.world.roads, now, delta)
	var targets: Array = []
	if selection.get("kind") == "crew":
		targets.append(_lead_provider(selection["id"]))
	if follow_crew != "" and follow_crew != selection.get("id", ""):
		targets.append(_lead_provider(follow_crew))
	fader.targets = targets


func _lead_provider(crew_id: String) -> Callable:
	var v: CrewView = crew_views.get(crew_id)
	return v.lead_position if v else Callable()


func _crew_car_positions() -> Array:
	var out: Array = []
	for v in crew_views.values():
		for car in (v as CrewView).cars:
			out.append(Vector2(car.global_position.x, car.global_position.z))
	return out


# --- Input --------------------------------------------------------------------------------
func _on_tap(screen_pos: Vector2) -> void:
	if hud.markers.handle_tap(screen_pos):
		return
	var cam := camera.camera
	var origin := cam.project_ray_origin(screen_pos)
	var dir := cam.project_ray_normal(screen_pos)
	if move_mode_crew != "":
		var lm := world.pick_landmark(origin, dir)
		if lm != "":
			_command({"type": "move_crew", "crew": move_mode_crew, "landmark": lm})
		else:
			var g: Variant = camera.ground_point(screen_pos)
			if g != null:
				var p: Vector3 = g
				_command({"type": "move_crew", "crew": move_mode_crew, "point": [roundi(p.x * 100.0), roundi(p.z * 100.0)]})
		_set_move_mode("")
		return
	var crew_id := _pick_crew(screen_pos)
	if crew_id != "":
		_select({"kind": "crew", "id": crew_id})
		return
	var lm_id := world.pick_landmark(origin, dir)
	if lm_id != "":
		_select(_selection_for_landmark(lm_id))
		return
	_select({})


func _pick_crew(screen_pos: Vector2) -> String:
	var best := ""
	var best_d := CREW_PICK_RADIUS_PX
	for id in crew_views:
		for car in (crew_views[id] as CrewView).cars:
			var p: Vector3 = car.global_position
			if camera.camera.is_position_behind(p):
				continue
			var d := camera.camera.unproject_position(p).distance_to(screen_pos)
			if d < best_d:
				best_d = d
				best = id
	return best


func _selection_for_landmark(lm_id: String) -> Dictionary:
	var b := Game.world.business_at_landmark(lm_id)
	if b:
		return {"kind": "business", "id": b.id}
	var hq := Game.world.hq_at_landmark(lm_id)
	if hq:
		return {"kind": "hq", "id": hq.faction_id}
	return {}


func _on_marker_pressed(kind: String, id: String) -> void:
	if move_mode_crew != "" and kind != "crew":
		var lm := _landmark_of({"kind": kind, "id": id})
		if lm != "":
			_command({"type": "move_crew", "crew": move_mode_crew, "landmark": lm})
		_set_move_mode("")
		return
	_select({"kind": kind, "id": id})


# --- Selection -----------------------------------------------------------------------------
func _select(sel: Dictionary, focus := false) -> void:
	for lv in world.landmarks.values():
		(lv as LandmarkView).set_highlighted(false)
	for v in crew_views.values():
		(v as CrewView).set_highlighted(false)
	selection = sel
	hud.markers.selected = sel
	hud.show_selection(sel)
	ring.clear()
	match sel.get("kind", ""):
		"business", "hq":
			var lv: LandmarkView = world.landmarks.get(_landmark_of(sel))
			if lv:
				lv.set_highlighted(true)
				ring.show_at(lv.entrance_point, 7.0)
				if focus:
					camera.focus_on(lv.entrance_point())
		"crew":
			var v: CrewView = crew_views.get(sel["id"])
			if v:
				v.set_highlighted(true)
				ring.show_at(v.lead_position, 5.0)
				if focus:
					camera.focus_on(v.lead_position(), minf(camera.target_distance, 150.0))
					# A moving crew is only useful to look at if the camera keeps up.
					if Game.world.crews[sel["id"]].is_moving():
						_set_follow(sel["id"])


func _landmark_of(sel: Dictionary) -> String:
	match sel.get("kind", ""):
		"business":
			return Game.world.businesses[sel["id"]].landmark_id
		"hq":
			return Game.world.headquarters[sel["id"]].landmark_id
	return ""


func _set_move_mode(crew_id: String) -> void:
	move_mode_crew = crew_id
	var name_text: String = Game.world.crews[crew_id].name if crew_id != "" else ""
	hud.show_move_banner(crew_id != "", name_text)


func _set_follow(crew_id: String) -> void:
	follow_crew = crew_id
	hud.set_meta("following", crew_id)
	if crew_id == "":
		camera.stop_follow(false)
	else:
		var v: CrewView = crew_views.get(crew_id)
		if v and not v.cars.is_empty():
			camera.follow(v.cars[0])
			camera.target_distance = minf(camera.target_distance, 120.0)


# --- Commands and feedback -----------------------------------------------------------------
func _command(cmd: Dictionary) -> Dictionary:
	return Game.execute(cmd)


func _on_action(action: String, payload: Dictionary) -> void:
	match action:
		"collect":
			_command({"type": "collect_business", "business": payload["business"]})
		"collect_all":
			_command({"type": "collect_all"})
		"upgrade":
			if _command({"type": "upgrade_business", "business": payload["business"]}).get("ok", false):
				hud.toast("Upgrade under way.", "upgrade")
		"buy":
			_command({"type": "acquire_business", "business": payload["business"]})
		"send_crew":
			var cid := _best_crew_for(payload["landmark"])
			if cid == "":
				_on_command_failed({}, "no_idle_crew")
			elif _command({"type": "move_crew", "crew": cid, "landmark": payload["landmark"]}).get("ok", false):
				hud.toast("%s is on the way." % Game.world.crews[cid].name, "crew")
		"move_mode":
			_set_move_mode(payload["crew"])
		"recall":
			_command({"type": "recall_crew", "crew": payload["crew"]})
		"recall_all":
			for id in Game.world.crews:
				if Game.world.crews[id].owner_id == Game.player_id:
					_command({"type": "recall_crew", "crew": id})
		"follow":
			_set_follow(payload["crew"] if payload["on"] else "")
		"restart":
			_set_follow("")
			Game.restart()


## Prefer the selected crew, then idle crews not already guarding something.
func _best_crew_for(landmark_id: String) -> String:
	var w := Game.world
	var ids := w.crews.keys()
	ids.sort()
	var fallback := ""
	for id in ids:
		var c: CrewState = w.crews[id]
		if c.owner_id != Game.player_id or c.at_landmark == landmark_id or c.dest_landmark == landmark_id:
			continue
		var guarding := false
		for b in w.businesses.values():
			if b.assigned_crew_id == id:
				guarding = true
		if not c.is_moving() and not guarding:
			return id
		if fallback == "" and not c.is_moving():
			fallback = id
	return fallback


func _on_sim_event(e: Dictionary) -> void:
	var w := Game.world
	match e["type"]:
		"business_collected":
			if e["faction"] == Game.player_id:
				hud.toast("Collected %s from %s." % [UiTheme.money(e["amount"]), w.businesses[e["business"]].name], "cash")
		"upgrade_complete":
			var b: BusinessState = w.businesses[e["business"]]
			if b.owner_id == Game.player_id:
				hud.toast("%s upgraded to level %d." % [b.name, b.level], "upgrade")
		"business_acquired":
			if e["faction"] == Game.player_id:
				hud.toast("%s now answers to the family." % w.businesses[e["business"]].name, "buy")
				_select(selection)
		"crew_arrived":
			var c: CrewState = w.crews[e["crew"]]
			if c.owner_id == Game.player_id:
				var where := hud.landmark_display_name(w, e["landmark"])
				hud.toast("%s arrived%s." % [c.name, (" at " + where) if where != "" else ""], "crew")
		"crew_departed":
			if selection.get("id") == e["crew"]:
				hud.show_selection(selection)


func _on_command_failed(_cmd: Dictionary, error: String) -> void:
	hud.toast(ERROR_TEXT.get(error, "That can't be done right now."), "close", UiTheme.RED)


## Development hook for DevCapture: "crew:<id>", "business:<id>", "hq:<faction>".
func dev_select(spec: String) -> void:
	var parts := spec.split(":")
	if parts.size() == 2:
		_select({"kind": parts[0], "id": parts[1]}, true)
		print("DevCapture: selected %s (sheet=%s)" % [spec, str(hud.find_child("SelectionSheet", true, false) != null)])

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
	"chapter_incomplete": "Finish every objective first.",
	"chapter_locked": "The family needs more power for this chapter.",
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
	await _loading_stage(0.08, "Reading the map")
	var world_id := GameContent.DEFAULT_WORLD
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--world="):
			world_id = a.get_slice("=", 1)
	var layout := WorldLayout.build(Content.db.worlds[world_id], Content.db)
	await _loading_stage(0.3, "Raising the city")
	world.build(layout)
	await _loading_stage(0.55, "Putting traffic on the streets")
	world.camera = camera
	camera.set_bounds(layout.playable)
	if layout.is_geo:
		camera.max_distance = 3200.0
	camera.distance_changed.connect(atmosphere.on_camera_distance)
	if atmosphere.sun:
		App.register_sun(atmosphere.sun)
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

	await _loading_stage(0.7, "Opening the family books")
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
	hud.attach_world(layout, camera)
	hud.business_card_pressed.connect(func(bid): _select({"kind": "business", "id": bid}, true))
	hud.focus_requested.connect(_on_focus_requested)

	Game.sim_event.connect(_on_sim_event)
	Game.command_failed.connect(_on_command_failed)
	Game.session_started.connect(_on_session_started)
	Game.start(layout)
	_add_ambience()
	_intro()
	_loading.set_progress(0.85, "Bringing the neighbourhood into view")
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


## Minimap travel and objective "go to": move the camera; select the
## business at the landmark when there is one.
func _on_focus_requested(p: Vector2, landmark_id: String) -> void:
	_set_follow("")
	camera.focus_on(Vector3(p.x, 0.0, p.y), minf(camera.target_distance, 220.0) if landmark_id != "" else -1.0)
	if landmark_id != "":
		var b := Game.world.business_at_landmark(landmark_id)
		if b:
			_select({"kind": "business", "id": b.id})


func _street_widths() -> Dictionary:
	return world.layout.street_widths()


# --- Loading screen and ambience ----------------------------------------------------
var _loading: LoadingScreen


func _show_loading() -> void:
	App.play_title()
	_loading = LoadingScreen.new()
	add_child(_loading)


## Report a build stage and let the loading screen draw before the next one.
func _loading_stage(value: float, stage: String) -> void:
	_loading.set_progress(value, stage)
	await get_tree().process_frame
	await get_tree().process_frame


func _hide_loading() -> void:
	if _loading == null or not is_instance_valid(_loading):
		return
	_loading.dismiss()
	_loading = null
	# The theme loops for the session; it drops under the city when play begins.
	App.duck_music()
	get_tree().create_timer(3.0).timeout.connect(_chapter_intro)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--ui-open="):
			hud.dev_open(arg.get_slice("=", 1))


## The current chapter's intro conversation, once per profile. Skipped in
## developer captures unless --ui-dialogue asks for it.
func _chapter_intro() -> void:
	var args := OS.get_cmdline_user_args()
	var capturing := Array(args).any(func(a: String): return a.begins_with("--capture"))
	if not Game.is_running() or (capturing and not "--ui-dialogue" in args):
		return
	var chapters: Array = Content.db.chapters
	if Game.world.chapter_index >= chapters.size():
		return
	var id := String(chapters[Game.world.chapter_index].get("intro_dialogue", ""))
	if id == "" or (App.has_seen(id) and not "--ui-dialogue" in args):
		return
	var box := DialogueBox.play(hud.overlays, id)
	if box:
		App.mark_seen(id)


var ambience: AmbienceDirector


func _add_ambience() -> void:
	ambience = AmbienceDirector.new()
	ambience.name = "Ambience"
	ambience.camera = camera
	ambience.traffic = traffic
	add_child(ambience)
	camera.distance_changed.connect(ambience.on_camera_distance)
	ambience.on_camera_distance(camera.distance)


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
		"claim_chapter":
			_command({"type": "claim_chapter"})
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
		"chapter_completed":
			hud.toast("Chapter %d complete. %s added to the family." % [e["chapter"], UiTheme.money(e["reward"])],
				"cash")
			_chapter_intro()
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

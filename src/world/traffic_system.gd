class_name TrafficSystem
extends Node3D
## Ambient city traffic and signal phasing. Presentation only (not part of the
## simulation). Cars wander the road graph in the right-hand lane near the
## camera, stop for red lights at junctions of three or more roads, and queue
## behind other cars and crew convoys. Cars that drift out of view respawn
## around the camera, so cost stays constant however large the world is.
## Drawn as one MultiMesh per vehicle type.

const CYCLE := 30.0
const CRUISE_MIN := 8.0
const CRUISE_MAX := 11.5
const ACCEL := 3.0
const BRAKE := 9.0
const FOLLOW_GAP := 7.0
const ROUTE_NODES := 10
const ACTIVE_RADIUS := 420.0

@export var car_count := 40

var layout: WorldLayout
var camera: StrategyCamera
var obstacle_provider: Callable  ## returns Array[Vector2] of extra obstacles (crew cars)
var ns_state := "green"
var ew_state := "red"

var _adj: Array = []
var _degree := PackedInt32Array()
var _cars: Array = []
var _mm: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _clock := 0.0


func setup(p_layout: WorldLayout) -> void:
	layout = p_layout
	_rng.seed = layout.seed_value + 4242
	_adj.resize(layout.graph_nodes.size())
	for i in _adj.size():
		_adj[i] = []
	for e in layout.graph_edges:
		_adj[e["a"]].append([e["b"], e["width"]])
		_adj[e["b"]].append([e["a"], e["width"]])
	_degree = layout.node_degrees()
	var pick := VehicleMeshes.weighted(Content.db.vehicle_mix("traffic_mix"))
	var kinds := {}
	for k in pick:
		kinds[k] = 0
	var paints: Array = Content.db.traffic_paints
	for i in car_count:
		var kind: String = pick[i % pick.size()]
		var car := {"kind": kind, "index": kinds[kind], "speed": 0.0,
			"cruise": _rng.randf_range(CRUISE_MIN, CRUISE_MAX),
			"tint": Color.html(paints[_rng.randi() % paints.size()]) if VehicleMeshes.is_tintable(kind) else Color.WHITE}
		kinds[kind] += 1
		_cars.append(car)
	for kind in kinds:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = VehicleMeshes.instanced(kind)
		mm.instance_count = kinds[kind]
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Traffic_" + kind
		mmi.multimesh = mm
		add_child(mmi)
		_mm[kind] = mm
	for car in _cars:
		(_mm[car["kind"]] as MultiMesh).set_instance_custom_data(car["index"], car["tint"])
		_respawn(car, true)


## World position of a random moving car (for spatial sound), or null.
func random_car_position() -> Variant:
	if _cars.is_empty():
		return null
	var car: Dictionary = _cars[_rng.randi() % _cars.size()]
	if float(car["speed"]) < 1.0:
		return null
	var p: Vector2 = car["pos"]
	return Vector3(p.x, 1.2, p.y)


func signal_state_for(axis: String) -> String:
	return ns_state if axis == "ns" else ew_state


func _focus() -> Vector2:
	if camera:
		return Vector2(camera.focus.x, camera.focus.z)
	return Vector2.ZERO


func _process(delta: float) -> void:
	if layout == null:
		return
	_clock = fmod(_clock + delta, CYCLE)
	_update_signals()
	var focus := _focus()
	var positions: Array = []
	for car in _cars:
		positions.append(car["pos"])
	if obstacle_provider.is_valid():
		positions.append_array(obstacle_provider.call())
	for car in _cars:
		if (car["pos"] as Vector2).distance_to(focus) > ACTIVE_RADIUS + 200.0:
			_respawn(car, true)
		_drive(car, delta, positions)
		var mm: MultiMesh = _mm[car["kind"]]
		var d: Vector2 = car["dir"]
		var p: Vector2 = car["pos"]
		mm.set_instance_transform(car["index"], Transform3D(Basis(Vector3.UP, atan2(-d.x, -d.y)), Vector3(p.x, 0, p.y)))


func _update_signals() -> void:
	var ns := "red"
	var ew := "red"
	if _clock < 11.0:
		ns = "green"
	elif _clock < 14.0:
		ns = "amber"
	elif _clock >= 15.0 and _clock < 26.0:
		ew = "green"
	elif _clock >= 26.0 and _clock < 29.0:
		ew = "amber"
	if ns != ns_state or ew != ew_state:
		ns_state = ns
		ew_state = ew
		Materials.set_signal_state(ns, ew)


func _drive(car: Dictionary, delta: float, obstacles: Array) -> void:
	var path: LanePath = car["path"]
	var s: float = car["s"]
	var target: float = car["cruise"]
	for stop in car["stops"]:
		var dist: float = stop["s"] - s
		if dist < -0.5:
			continue
		if dist > 30.0:
			break
		var state := signal_state_for(stop["axis"])
		if state == "red" or (state == "amber" and dist > 6.0):
			target = minf(target, sqrt(maxf(0.0, 2.0 * BRAKE * 0.6 * maxf(dist - 0.3, 0.0))))
		break
	var pos: Vector2 = car["pos"]
	var dir: Vector2 = car["dir"]
	for o in obstacles:
		var rel: Vector2 = (o as Vector2) - pos
		var fwd := rel.dot(dir)
		if fwd <= 0.5 or fwd > 16.0:
			continue
		if absf(rel.cross(dir)) > 1.6:
			continue
		target = minf(target, maxf(0.0, (fwd - FOLLOW_GAP) * 1.3))
	var speed: float = car["speed"]
	speed = move_toward(speed, target, (ACCEL if target > speed else BRAKE) * delta)
	car["speed"] = speed
	s += speed * delta
	if s >= path.length - 0.1:
		_new_route(car, car["route"][-1], car["route"][-2] if car["route"].size() > 1 else -1, false)
		return
	car["s"] = s
	var smp := path.sample(s)
	car["pos"] = smp["pos"]
	car["dir"] = (car["dir"] as Vector2).lerp(smp["dir"], 1.0 - exp(-12.0 * delta)).normalized()


func _respawn(car: Dictionary, scatter: bool) -> void:
	# Start at a random junction near the camera.
	var focus := _focus()
	var start := -1
	var near := layout.nodes_near(focus, ACTIVE_RADIUS)
	for attempt in 24:
		if near.is_empty():
			break
		var n: int = near[_rng.randi() % near.size()]
		if _adj[n].size() >= 2:
			start = n
			break
	if start < 0:
		start = near[0] if not near.is_empty() else _rng.randi() % layout.graph_nodes.size()
	_new_route(car, start, -1, scatter)


func _new_route(car: Dictionary, start: int, came_from: int, scatter: bool) -> void:
	if _adj[start].size() <= 1 and came_from >= 0:
		_respawn(car, false)  # dead end (pier tip, map edge): reappear elsewhere
		return
	var route: Array = [start]
	var prev := came_from
	var cur := start
	for i in ROUTE_NODES:
		var options: Array = (_adj[cur] as Array).filter(func(n): return n[0] != prev)
		if options.is_empty():
			break
		var nxt: int = options[_rng.randi() % options.size()][0]
		route.append(nxt)
		prev = cur
		cur = nxt
	if route.size() < 2:
		route.append((_adj[start][0] as Array)[0])
	var centre: Array = []
	for n in route:
		centre.append(layout.graph_nodes[n])
	var path := LanePath.from_centreline(centre, layout.lane_offset)
	car["route"] = route
	car["path"] = path
	car["stops"] = _stops_for(route, path)
	car["s"] = _rng.randf() * path.length * 0.6 if scatter else 0.0
	var smp := path.sample(car["s"])
	car["pos"] = smp["pos"]
	car["dir"] = smp["dir"]


## Stop lines before each signalised junction (three or more roads) on the route.
func _stops_for(route: Array, path: LanePath) -> Array:
	var stops := []
	var centre_len := 0.0
	var cum := [0.0]
	for i in range(1, route.size()):
		centre_len += (layout.graph_nodes[route[i]] as Vector2).distance_to(layout.graph_nodes[route[i - 1]])
		cum.append(centre_len)
	var ratio := path.length / maxf(centre_len, 0.001)
	for i in range(1, route.size() - 1):
		var n: int = route[i]
		if _degree[n] < 3:
			continue
		var d: Vector2 = (layout.graph_nodes[n] as Vector2) - layout.graph_nodes[route[i - 1]]
		var axis := "ns" if absf(d.y) > absf(d.x) else "ew"
		var crossing_w := 12.0
		for adj in _adj[n]:
			var e: Vector2 = (layout.graph_nodes[adj[0]] as Vector2) - layout.graph_nodes[n]
			if absf(e.normalized().dot(d.normalized())) < 0.5:
				crossing_w = maxf(crossing_w, adj[1])
		stops.append({"s": cum[i] * ratio - (crossing_w * 0.5 + 5.6), "axis": axis})
	return stops

class_name CrewView
extends Node3D
## Visual convoy for one crew: its sedans driving in the right-hand lane.
## Position comes from the simulation's time-based progress, mapped onto a
## smoothed lane path, so the view never drifts from the authoritative state.

const CONVOY_GAP := 7.5
const KERB_CLEARANCE := 1.3
const PLAYER_TINT := Color("#101012")
const RIVAL_TINT := Color("#3d1411")

var crew_id := ""
var owner_id := ""
var cars: Array[MeshInstance3D] = []
var _path: LanePath
var _route_serial := -1
var _park_dir := Vector2(0, -1)
var _lane_offset := 1.9
var _street_widths: Dictionary = {}
var _yaws: Array[float] = []
var _placed := false


func setup(crew: CrewState, lane_offset: float, is_player: bool, street_widths: Dictionary) -> void:
	_street_widths = street_widths
	crew_id = crew.id
	owner_id = crew.owner_id
	name = "Crew_" + crew.id
	_lane_offset = lane_offset
	var mesh := VehicleMeshes.single(crew.vehicle_id)
	for i in crew.vehicle_count:
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.set_instance_shader_parameter("tint", PLAYER_TINT if is_player else RIVAL_TINT)
		add_child(mi)
		cars.append(mi)
		_yaws.append(0.0)


## Lead vehicle position (camera follow, markers, occlusion).
func lead_position() -> Vector3:
	return cars[0].global_position if not cars.is_empty() else global_position


func set_highlighted(on: bool) -> void:
	for c in cars:
		c.set_instance_shader_parameter("highlight", 0.7 if on else 0.0)


func update_from(crew: CrewState, roads: RoadGraph, now_ms: float, delta: float) -> void:
	var d := delta if _placed else 0.0
	_placed = true
	if crew.is_moving() and crew.route_points.size() >= 2:
		if crew.route_serial != _route_serial:
			_route_serial = crew.route_serial
			var centre: Array = []
			for p in crew.route_points:
				centre.append(Vector2(p) / 100.0)
			_path = LanePath.from_centreline(centre, _lane_offset)
		var frac := crew.progress_cm(now_ms) / maxf(float(crew.route_length), 1.0)
		var s := frac * _path.length
		for i in cars.size():
			var smp := _path.sample(s - i * CONVOY_GAP)
			_place(i, smp["pos"], smp["dir"], d)
			if i == 0:
				_park_dir = smp["dir"]
	else:
		_route_serial = -1
		var p := Vector2(roads.location_point(crew.location)) / 100.0
		var e: Dictionary = roads.edges[crew.location["edge"]]
		var edge_dir := Vector2(roads.nodes[e["b"]] - roads.nodes[e["a"]]).normalized()
		var dir := edge_dir if edge_dir.dot(_park_dir) >= 0.0 else -edge_dir
		var right := Vector2(-dir.y, dir.x)
		# Pull up at the kerb on the right-hand side of the street.
		var kerb: float = _street_widths.get(e["street"], 12.0) * 0.5 - KERB_CLEARANCE
		var half := CONVOY_GAP * 0.5 * (cars.size() - 1)
		for i in cars.size():
			_place(i, p + right * kerb + dir * (half - i * CONVOY_GAP), dir, d)


func _place(i: int, pos: Vector2, dir: Vector2, delta: float) -> void:
	# Vehicles face -Z; yaw so that -Z points along `dir` (x, z).
	var target_yaw := atan2(-dir.x, -dir.y)
	_yaws[i] = lerp_angle(_yaws[i], target_yaw, 1.0 - exp(-10.0 * delta)) if delta > 0.0 else target_yaw
	cars[i].global_transform = Transform3D(Basis(Vector3.UP, _yaws[i]), Vector3(pos.x, 0.0, pos.y))

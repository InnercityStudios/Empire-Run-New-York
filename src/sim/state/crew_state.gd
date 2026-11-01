class_name CrewState
extends RefCounted
## A crew: capo, soldiers and vehicles. Movement is a pure function of time:
## progress = route_length * (now - depart) / (arrive - depart).

var id := ""
var owner_id := ""
var name := ""
var capo_id := ""
var soldiers: Dictionary = {}
var vehicle_id := ""
var vehicle_count := 1
var hp := 0
var max_hp := 0
var status := "idle"             ## idle | moving
var location: Dictionary = {"edge": 0, "offset": 0}
var at_landmark := ""
var dest_landmark := ""
var route_points: Array = []     ## Array[Vector2i] in cm
var route_length := 0
var route_costs: Array = []      ## cumulative travel cost at each route point (speed by road class)
var route_cost := 0
var depart_ms := 0
var arrive_ms := 0
var route_serial := 0            ## bumps on every new route (presentation cache key)


func is_moving() -> bool:
	return status == "moving"


func _time_fraction(now_ms: float) -> float:
	if not is_moving() or arrive_ms <= depart_ms:
		return 1.0
	return clampf((now_ms - depart_ms) / float(arrive_ms - depart_ms), 0.0, 1.0)


## Distance travelled along the route (cm). Speed varies by road class, so
## time maps to distance through the route's cumulative costs.
func progress_cm(now_ms: float) -> float:
	if not is_moving():
		return float(route_length)
	if route_costs.size() != route_points.size():
		return route_length * _time_fraction(now_ms)
	return RoadGraph.distance_at_cost(route_points, route_costs, route_cost * _time_fraction(now_ms))


## Ground position in cm (float for smooth presentation).
func position_cm(now_ms: float, roads: RoadGraph) -> Vector2:
	if is_moving() and route_points.size() >= 2:
		if route_costs.size() == route_points.size():
			return RoadGraph.point_at_cost(route_points, route_costs, route_cost * _time_fraction(now_ms))
		return RoadGraph.point_along(route_points, progress_cm(now_ms))
	return Vector2(roads.location_point(location))


func to_dict() -> Dictionary:
	var pts := []
	for p in route_points:
		pts.append([p.x, p.y])
	return {
		"id": id, "owner": owner_id, "name": name, "capo": capo_id, "soldiers": soldiers.duplicate(),
		"vehicle": vehicle_id, "vehicles": vehicle_count, "hp": hp, "max_hp": max_hp, "status": status,
		"location": location.duplicate(), "at_landmark": at_landmark, "dest_landmark": dest_landmark,
		"route": pts, "route_length": route_length, "route_costs": route_costs.duplicate(), "route_cost": route_cost,
		"depart_ms": depart_ms, "arrive_ms": arrive_ms,
		"route_serial": route_serial,
	}


static func from_dict(d: Dictionary) -> CrewState:
	var c := CrewState.new()
	c.id = d["id"]
	c.owner_id = d.get("owner", "")
	c.name = d.get("name", "")
	c.capo_id = d.get("capo", "")
	for tier in d.get("soldiers", {}):
		c.soldiers[tier] = int(d["soldiers"][tier])
	c.vehicle_id = d.get("vehicle", "")
	c.vehicle_count = int(d.get("vehicles", 1))
	c.hp = int(d.get("hp", 0))
	c.max_hp = int(d.get("max_hp", 0))
	c.status = d.get("status", "idle")
	var loc: Dictionary = d.get("location", {})
	c.location = {"edge": int(loc.get("edge", 0)), "offset": int(loc.get("offset", 0))}
	c.at_landmark = d.get("at_landmark", "")
	c.dest_landmark = d.get("dest_landmark", "")
	for p in d.get("route", []):
		c.route_points.append(Vector2i(int(p[0]), int(p[1])))
	c.route_length = int(d.get("route_length", 0))
	for v in d.get("route_costs", []):
		c.route_costs.append(int(v))
	c.route_cost = int(d.get("route_cost", c.route_length))
	c.depart_ms = int(d.get("depart_ms", 0))
	c.arrive_ms = int(d.get("arrive_ms", 0))
	c.route_serial = int(d.get("route_serial", 0))
	return c

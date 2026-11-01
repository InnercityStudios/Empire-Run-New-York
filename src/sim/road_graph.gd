class_name RoadGraph
extends RefCounted
## Street network used by the simulation for crew routing.
##
## - Positions are integer centimetres on the ground plane (x, z), so routes
##   and travel times are bit-identical between client and server.
## - Nodes are identified by their position key ("x,z" in cm). Keys are stable
##   across regeneration and world expansion, which keeps saves valid.
## - Edges carry a speed factor (permille of a vehicle's base speed) by road
##   class; route cost is travel time at base speed, so crews prefer arterials.
## - A location on the network is {"edge": int, "offset": int} (cm from node a).
##   Persist locations with `location_to_key` / `location_from_key`.

const CELL_CM := 10_000  ## spatial index cell: 100 m

var nodes: Array[Vector2i] = []
var edges: Array = []            ## {a, b, length, street, speed}
var _node_lookup: Dictionary = {}
var _edge_lookup: Dictionary = {}
var _adjacency: Array = []
var _cells: Dictionary = {}
var _max_speed := 1000


static func from_layout(layout_nodes: Array, layout_edges: Array) -> RoadGraph:
	var g := RoadGraph.new()
	var node_ids: Array = []
	for p in layout_nodes:
		node_ids.append(g.add_node(Vector2i(roundi(p.x * 100.0), roundi(p.y * 100.0))))
	for e in layout_edges:
		g.add_edge(node_ids[e["a"]], node_ids[e["b"]], e.get("street", ""), int(e.get("speed", 1000)))
	return g


static func node_key(p: Vector2i) -> String:
	return "%d,%d" % [p.x, p.y]


## Adds a node, merging with an existing node at the same position.
func add_node(p: Vector2i) -> int:
	var k := node_key(p)
	if _node_lookup.has(k):
		return _node_lookup[k]
	nodes.append(p)
	_adjacency.append([])
	_node_lookup[k] = nodes.size() - 1
	return nodes.size() - 1


func find_node(p: Vector2i) -> int:
	return _node_lookup.get(node_key(p), -1)


func add_edge(a: int, b: int, street := "", speed := 1000) -> int:
	if a == b:
		return -1
	var key := _edge_key(a, b)
	if _edge_lookup.has(key):
		return _edge_lookup[key]
	var length := roundi(Vector2(nodes[b] - nodes[a]).length())
	edges.append({"a": a, "b": b, "length": maxi(length, 1), "street": street, "speed": maxi(speed, 100)})
	var idx := edges.size() - 1
	_edge_lookup[key] = idx
	_adjacency[a].append([idx, b])
	_adjacency[b].append([idx, a])
	_max_speed = maxi(_max_speed, speed)
	_index_edge(idx)
	return idx


func _edge_key(a: int, b: int) -> String:
	var ka := node_key(nodes[a])
	var kb := node_key(nodes[b])
	return ka + "|" + kb if ka < kb else kb + "|" + ka


func _index_edge(idx: int) -> void:
	var e: Dictionary = edges[idx]
	var a: Vector2i = nodes[e["a"]]
	var b: Vector2i = nodes[e["b"]]
	for cx in range(mini(a.x, b.x) / CELL_CM - 1, maxi(a.x, b.x) / CELL_CM + 2):
		for cz in range(mini(a.y, b.y) / CELL_CM - 1, maxi(a.y, b.y) / CELL_CM + 2):
			var c := Vector2i(cx, cz)
			if not _cells.has(c):
				_cells[c] = []
			_cells[c].append(idx)


func neighbours(node: int) -> Array:
	return _adjacency[node]


## Travel cost of an edge in cm at base speed (length scaled by road speed).
func edge_cost(idx: int) -> int:
	var e: Dictionary = edges[idx]
	return int(e["length"]) * 1000 / int(e["speed"])


func location_point(loc: Dictionary) -> Vector2i:
	var e: Dictionary = edges[loc["edge"]]
	var a: Vector2i = nodes[e["a"]]
	var b: Vector2i = nodes[e["b"]]
	var off: int = clampi(loc["offset"], 0, e["length"])
	return a + (b - a) * off / e["length"]


## Serialisable form of a location, independent of edge indices.
func location_to_key(loc: Dictionary) -> Dictionary:
	var e: Dictionary = edges[loc["edge"]]
	return {"a": node_key(nodes[e["a"]]), "b": node_key(nodes[e["b"]]), "offset": int(loc["offset"])}


func location_from_key(k: Dictionary) -> Dictionary:
	var a: int = _node_lookup.get(k.get("a", ""), -1)
	var b: int = _node_lookup.get(k.get("b", ""), -1)
	if a < 0 or b < 0 or not _edge_lookup.has(_edge_key(a, b)):
		return {}
	var idx: int = _edge_lookup[_edge_key(a, b)]
	var off := int(k.get("offset", 0))
	if edges[idx]["a"] != a:
		off = int(edges[idx]["length"]) - off
	return {"edge": idx, "offset": clampi(off, 0, edges[idx]["length"])}


## Nearest point on the network to a position in cm.
func locate(p: Vector2i) -> Dictionary:
	var best := {"edge": 0, "offset": 0}
	var best_d := INF
	var c := Vector2i(p.x / CELL_CM, p.y / CELL_CM)
	var candidates: Dictionary = {}
	for r in range(0, 6):
		for cx in range(c.x - r, c.x + r + 1):
			for cz in range(c.y - r, c.y + r + 1):
				for idx in _cells.get(Vector2i(cx, cz), []):
					candidates[idx] = true
		if not candidates.is_empty() and r >= 1:
			break
	if candidates.is_empty():
		for i in edges.size():
			candidates[i] = true
	var ids := candidates.keys()
	ids.sort()
	for i in ids:
		var e: Dictionary = edges[i]
		var a := Vector2(nodes[e["a"]])
		var b := Vector2(nodes[e["b"]])
		var ab := b - a
		var t := clampf((Vector2(p) - a).dot(ab) / maxf(ab.length_squared(), 1.0), 0.0, 1.0)
		var d := Vector2(p).distance_squared_to(a + ab * t)
		if d < best_d - 0.5:
			best_d = d
			best = {"edge": i, "offset": roundi(t * e["length"])}
	return best


## Fastest route between two locations (A*, deterministic tie-breaking).
## Returns {points: Array[Vector2i], costs: Array[int] (cumulative cost at each
## point), length: int, cost: int} or {} when unreachable.
func route(from_loc: Dictionary, to_loc: Dictionary) -> Dictionary:
	var start := location_point(from_loc)
	var goal := location_point(to_loc)
	var se: Dictionary = edges[from_loc["edge"]]
	var ge: Dictionary = edges[to_loc["edge"]]
	if from_loc["edge"] == to_loc["edge"]:
		var direct := absi(int(to_loc["offset"]) - int(from_loc["offset"]))
		var direct_cost := direct * 1000 / int(se["speed"])
		return {"points": [start, goal], "costs": [0, direct_cost], "length": direct, "cost": direct_cost}
	var dist := {}
	var prev := {}
	var heap := _Heap.new()
	var s_sp: int = se["speed"]
	for pair in [[se["a"], int(from_loc["offset"])], [se["b"], int(se["length"]) - int(from_loc["offset"])]]:
		var c: int = pair[1] * 1000 / s_sp
		if not dist.has(pair[0]) or c < dist[pair[0]]:
			dist[pair[0]] = c
			prev[pair[0]] = -1
			heap.push(c + _heuristic(pair[0], goal), pair[0])
	var targets := {ge["a"]: true, ge["b"]: true}
	var closed := {}
	var settled := 0
	while not heap.is_empty():
		var cur: int = heap.pop()
		if closed.has(cur):
			continue
		closed[cur] = true
		if targets.has(cur):
			settled += 1
			if settled == 2:
				break
		for adj in _adjacency[cur]:
			var other: int = adj[1]
			if closed.has(other):
				continue
			var nd: int = dist[cur] + edge_cost(adj[0])
			if not dist.has(other) or nd < dist[other]:
				dist[other] = nd
				prev[other] = cur
				heap.push(nd + _heuristic(other, goal), other)
	var g_sp: int = ge["speed"]
	var end_node := -1
	var total := 0
	if dist.has(ge["a"]):
		end_node = ge["a"]
		total = dist[ge["a"]] + int(to_loc["offset"]) * 1000 / g_sp
	if dist.has(ge["b"]):
		var via_b: int = dist[ge["b"]] + (int(ge["length"]) - int(to_loc["offset"])) * 1000 / g_sp
		if end_node < 0 or via_b < total:
			end_node = ge["b"]
			total = via_b
	if end_node < 0:
		return {}
	var chain: Array = []
	var n := end_node
	while n != -1:
		chain.push_front(n)
		n = prev[n]
	var points: Array = [start]
	var costs: Array = [0]
	for node in chain:
		if nodes[node] != points[-1]:
			points.append(nodes[node])
			costs.append(dist[node])
	if goal != points[-1]:
		points.append(goal)
		costs.append(total)
	else:
		costs[-1] = total
	var length := 0
	for i in points.size() - 1:
		length += roundi(Vector2(points[i + 1] - points[i]).length())
	return {"points": points, "costs": costs, "length": length, "cost": total}


func _heuristic(node: int, goal: Vector2i) -> int:
	# Admissible: straight-line distance at the fastest road speed.
	return int(Vector2(nodes[node] - goal).length()) * 1000 / _max_speed


## Point (cm) at a distance (cm) along a polyline of Vector2i.
static func point_along(points: Array, dist: float) -> Vector2:
	var remaining := maxf(dist, 0.0)
	for i in points.size() - 1:
		var a := Vector2(points[i])
		var b := Vector2(points[i + 1])
		var seg := a.distance_to(b)
		if remaining <= seg:
			return a.lerp(b, remaining / maxf(seg, 0.001))
		remaining -= seg
	return Vector2(points[-1])


## Distance (cm) travelled after spending `cost` along a route.
static func distance_at_cost(points: Array, costs: Array, cost: float) -> float:
	if costs.size() != points.size():
		return cost
	var travelled := 0.0
	for i in points.size() - 1:
		var seg := Vector2(points[i]).distance_to(Vector2(points[i + 1]))
		var c0 := float(costs[i])
		var c1 := float(costs[i + 1])
		if cost <= c1:
			return travelled + seg * clampf((cost - c0) / maxf(c1 - c0, 0.001), 0.0, 1.0)
		travelled += seg
	return travelled


## Point (cm) reached after spending `cost` along a route with cumulative costs.
static func point_at_cost(points: Array, costs: Array, cost: float) -> Vector2:
	if costs.size() != points.size():
		return point_along(points, cost)
	for i in points.size() - 1:
		var c0 := float(costs[i])
		var c1 := float(costs[i + 1])
		if cost <= c1:
			var t := (cost - c0) / maxf(c1 - c0, 0.001)
			return Vector2(points[i]).lerp(Vector2(points[i + 1]), clampf(t, 0.0, 1.0))
	return Vector2(points[-1])


## Binary min-heap of (priority, node) with node id as the tie-breaker.
class _Heap:
	var _p: Array[int] = []
	var _n: Array[int] = []

	func is_empty() -> bool:
		return _p.is_empty()

	func _less(i: int, j: int) -> bool:
		return _p[i] < _p[j] or (_p[i] == _p[j] and _n[i] < _n[j])

	func _swap(i: int, j: int) -> void:
		var tp := _p[i]
		_p[i] = _p[j]
		_p[j] = tp
		var tn := _n[i]
		_n[i] = _n[j]
		_n[j] = tn

	func push(priority: int, node: int) -> void:
		_p.append(priority)
		_n.append(node)
		var i := _p.size() - 1
		while i > 0:
			var parent := (i - 1) >> 1
			if not _less(i, parent):
				break
			_swap(i, parent)
			i = parent

	func pop() -> int:
		var top := _n[0]
		var last := _p.size() - 1
		_swap(0, last)
		_p.resize(last)
		_n.resize(last)
		var i := 0
		while true:
			var l := i * 2 + 1
			var r := l + 1
			var m := i
			if l < _p.size() and _less(l, m):
				m = l
			if r < _p.size() and _less(r, m):
				m = r
			if m == i:
				break
			_swap(i, m)
			i = m
		return top

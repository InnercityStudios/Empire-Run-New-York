class_name RoadGraph
extends RefCounted
## Street network used by the simulation for crew routing.
##
## Positions are integer centimetres on the ground plane (x, z) so routes and
## travel times are bit-identical between client and server. A location on
## the network is {"edge": int, "offset": int} with offset in cm from node a.

var nodes: Array[Vector2i] = []
var edges: Array = []          ## {a: int, b: int, length: int, street: String}
var _adjacency: Array = []     ## node -> Array of [edge index, other node]


static func from_layout(layout_nodes: Array, layout_edges: Array) -> RoadGraph:
	var g := RoadGraph.new()
	for p in layout_nodes:
		g.nodes.append(Vector2i(roundi(p.x * 100.0), roundi(p.y * 100.0)))
	g._adjacency.resize(g.nodes.size())
	for i in g.nodes.size():
		g._adjacency[i] = []
	for e in layout_edges:
		g.add_edge(e["a"], e["b"], e.get("street", ""))
	return g


func add_edge(a: int, b: int, street := "") -> int:
	var length := roundi(Vector2(nodes[b] - nodes[a]).length())
	edges.append({"a": a, "b": b, "length": maxi(length, 1), "street": street})
	var idx := edges.size() - 1
	_adjacency[a].append([idx, b])
	_adjacency[b].append([idx, a])
	return idx


func neighbours(node: int) -> Array:
	return _adjacency[node]


func location_point(loc: Dictionary) -> Vector2i:
	var e: Dictionary = edges[loc["edge"]]
	var a: Vector2i = nodes[e["a"]]
	var b: Vector2i = nodes[e["b"]]
	var off: int = clampi(loc["offset"], 0, e["length"])
	return a + (b - a) * off / e["length"]


## Nearest point on the network to a position in cm.
func locate(p: Vector2i) -> Dictionary:
	var best := {"edge": 0, "offset": 0}
	var best_d := INF
	for i in edges.size():
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


## Shortest route between two locations.
## Returns {points: Array[Vector2i], length: int} or {} when unreachable.
func route(from_loc: Dictionary, to_loc: Dictionary) -> Dictionary:
	var start := location_point(from_loc)
	var goal := location_point(to_loc)
	if from_loc["edge"] == to_loc["edge"]:
		return {"points": [start, goal], "length": absi(int(to_loc["offset"]) - int(from_loc["offset"]))}
	var se: Dictionary = edges[from_loc["edge"]]
	var ge: Dictionary = edges[to_loc["edge"]]
	var dist := {}
	var prev := {}
	dist[se["a"]] = int(from_loc["offset"])
	dist[se["b"]] = int(se["length"]) - int(from_loc["offset"])
	prev[se["a"]] = -1
	prev[se["b"]] = -1
	var open: Array = [se["a"], se["b"]]
	var closed := {}
	while not open.is_empty():
		# Deterministic: lowest distance, then lowest node id.
		var bi := 0
		for k in range(1, open.size()):
			var n: int = open[k]
			var c: int = open[bi]
			if dist[n] < dist[c] or (dist[n] == dist[c] and n < c):
				bi = k
		var cur: int = open[bi]
		open.remove_at(bi)
		if closed.has(cur):
			continue
		closed[cur] = true
		for adj in _adjacency[cur]:
			var nd: int = dist[cur] + int(edges[adj[0]]["length"])
			var other: int = adj[1]
			if not dist.has(other) or nd < dist[other]:
				dist[other] = nd
				prev[other] = cur
				open.append(other)
	var via_a: int = dist.get(ge["a"], -1)
	var via_b: int = dist.get(ge["b"], -1)
	var end_node := -1
	var total := 0
	if via_a >= 0:
		end_node = ge["a"]
		total = via_a + int(to_loc["offset"])
	if via_b >= 0 and (end_node < 0 or via_b + int(ge["length"]) - int(to_loc["offset"]) < total):
		end_node = ge["b"]
		total = via_b + int(ge["length"]) - int(to_loc["offset"])
	if end_node < 0:
		return {}
	var chain: Array = []
	var n := end_node
	while n != -1:
		chain.push_front(n)
		n = prev[n]
	var points: Array = [start]
	for node in chain:
		if nodes[node] != points[-1]:
			points.append(nodes[node])
	if goal != points[-1]:
		points.append(goal)
	return {"points": points, "length": total}


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

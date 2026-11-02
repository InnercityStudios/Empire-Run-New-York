class_name StreetNetwork
extends RefCounted
## Streets-first layout: a set of road polylines becomes one planar graph
## (roads split wherever they cross or end on another road), paved junctions,
## trimmed road surfaces and the blocks between the roads.
##
## Blocks are the bounded faces of the planar graph, shrunk to the kerb line
## by the half-width of their bounding roads, so every block is enclosed by
## streets and every street meets the next at a real junction. Deterministic:
## the output depends only on the input polylines.

const SNAP := 1.5            ## metres: ends this close to another road join it
const MIN_BLOCK_AREA := 600.0

var nodes: Array = []        ## Vector2
var edges: Array = []        ## {a, b, road}
var roads: Array = []        ## input {name, class, width, speed, path: PackedVector2Array}
var junctions: Array = []    ## {center, poly}
var segments: Array = []     ## road surface pieces {road, from, to, width, no_crossing}
var blocks: Array = []       ## PackedVector2Array kerb-line polygons
var _key_index: Dictionary = {}
var _adj: Array = []


static func build(p_roads: Array) -> StreetNetwork:
	var n := StreetNetwork.new()
	n._build(p_roads)
	return n


func _node(p: Vector2) -> int:
	var k := Vector2i(roundi(p.x * 2.0), roundi(p.y * 2.0))
	if _key_index.has(k):
		return _key_index[k]
	nodes.append(p)
	_adj.append([])
	_key_index[k] = nodes.size() - 1
	return nodes.size() - 1


const CELL := 128.0

func _build(p_roads: Array) -> void:
	roads = p_roads.duplicate(true)
	# Snap BEFORE computing intersections, otherwise split points refer to
	# the old geometry. Use nearest centreline, never the first road in a list.
	var segs := _segments()
	var buckets := _buckets(segs)
	for ri in roads.size():
		var path: PackedVector2Array = roads[ri]["path"]
		if path.size()<2:continue
		for idx in [0,path.size()-1]:
			var end := path[idx]
			var best := SNAP
			var snapped := end
			for si in buckets.get(Vector2i((end/CELL).floor()),[]):
				var other: Array = segs[si]
				if other[0]==ri:continue
				var q := Geometry2D.get_closest_point_to_segment(end,other[2],other[3])
				if q.distance_to(end)<best:
					best=q.distance_to(end);snapped=q
			path[idx]=snapped
		roads[ri]["path"]=path
	segs=_segments()
	buckets=_buckets(segs)
	var splits := {}
	var add := func(si: int, p: Vector2) -> void:
		var seg: Array = segs[si]
		var t := clampf((p-seg[2]).dot(seg[3]-seg[2])/maxf((seg[3]-seg[2]).length_squared(),.0001),0.0,1.0)
		if not splits.has(si):splits[si]=[]
		splits[si].append([t,p])
	var tested := {}
	for cell in buckets.values():
		for ii in cell.size():
			var i: int = cell[ii]
			for jj in range(ii+1,cell.size()):
				var j: int = cell[jj]
				var pair := Vector2i(mini(i,j),maxi(i,j))
				if tested.has(pair):continue
				tested[pair]=true
				var a: Array = segs[i]
				var b: Array = segs[j]
				if a[0]==b[0] and absi(a[1]-b[1])<=1:continue
				var cross: Variant = Geometry2D.segment_intersects_segment(a[2],a[3],b[2],b[3])
				if cross!=null:
					add.call(i,cross);add.call(j,cross)
				else:
					# Collinear overlaps are split then deduplicated, so duplicate
					# input routes cannot create parallel visual/navigation edges.
					for p in [a[2],a[3]]:
						if p.distance_to(Geometry2D.get_closest_point_to_segment(p,b[2],b[3]))<.01:add.call(j,p)
					for p in [b[2],b[3]]:
						if p.distance_to(Geometry2D.get_closest_point_to_segment(p,a[2],a[3]))<.01:add.call(i,p)
	var emitted := {}
	for si in segs.size():
		var seg: Array = segs[si]
		var pts: Array = [[0.0,seg[2]]]
		pts.append_array(splits.get(si,[]));pts.append([1.0,seg[3]])
		pts.sort_custom(func(x,y):return x[0]<y[0])
		for k in pts.size()-1:
			var a := _node(pts[k][1])
			var b := _node(pts[k+1][1])
			var key := Vector2i(mini(a,b),maxi(a,b))
			if a==b or emitted.has(key):continue
			emitted[key]=true
			edges.append({"a":a,"b":b,"road":seg[0]})
			_adj[a].append(edges.size()-1);_adj[b].append(edges.size()-1)
	_surfaces()
	_faces()

func _segments() -> Array:
	var segs := []
	for ri in roads.size():
		var path: PackedVector2Array = roads[ri]["path"]
		for i in path.size()-1:
			if path[i].distance_to(path[i+1])>.05:segs.append([ri,i,path[i],path[i+1]])
	return segs

func _buckets(segs: Array) -> Dictionary:
	var buckets := {}
	for i in segs.size():
		var a: Vector2 = segs[i][2]
		var b: Vector2 = segs[i][3]
		var lo := Vector2i(((a.min(b)-Vector2.ONE*SNAP)/CELL).floor())
		var hi := Vector2i(((a.max(b)+Vector2.ONE*SNAP)/CELL).floor())
		for x in range(lo.x,hi.x+1):
			for z in range(lo.y,hi.y+1):
				var key := Vector2i(x,z)
				if not buckets.has(key):buckets[key]=[]
				buckets[key].append(i)
	return buckets


func degree(n: int) -> int:
	return (_adj[n] as Array).size()


func half_width_at(n: int) -> float:
	var w := 0.0
	for ei in _adj[n]:
		w = maxf(w, float(roads[edges[ei]["road"]]["width"]) * 0.5)
	return w


## Road pieces trimmed back from junctions; a paved junction polygon where
## three or more pieces meet (or two at an angle).
func _surfaces() -> void:
	var trim := PackedFloat32Array()
	trim.resize(nodes.size())
	for n in nodes.size():
		var deg := degree(n)
		if deg >= 3:
			trim[n] = half_width_at(n) + 0.6
		elif deg == 2:
			var e0: Dictionary = edges[_adj[n][0]]
			var e1: Dictionary = edges[_adj[n][1]]
			var d0: Vector2 = (nodes[e0["b"] if e0["a"] == n else e0["a"]] - nodes[n]).normalized()
			var d1: Vector2 = (nodes[e1["b"] if e1["a"] == n else e1["a"]] - nodes[n]).normalized()
			var turn := PI - acos(clampf(d0.dot(d1), -1.0, 1.0))
			trim[n] = 0.0 if turn < 0.02 else minf(half_width_at(n) * tan(turn * 0.5) + 0.3, 8.0)
	for e in edges:
		var a: Vector2 = nodes[e["a"]]
		var b: Vector2 = nodes[e["b"]]
		var length := a.distance_to(b)
		var dir := (b - a) / maxf(length, 0.001)
		var ta := minf(trim[e["a"]], length * 0.45)
		var tb := minf(trim[e["b"]], length * 0.45)
		if length - ta - tb < 0.5:
			continue
		# Crossings only where the piece meets a real junction.
		var nc := Vector2(0.0 if degree(e["a"]) >= 3 else 1.0, 0.0 if degree(e["b"]) >= 3 else 1.0)
		segments.append({"road": e["road"], "from": a + dir * ta, "to": b - dir * tb,
			"width": float(roads[e["road"]]["width"]), "no_crossing": nc})
	for n in nodes.size():
		if trim[n] <= 0.0:
			continue
		var hull := PackedVector2Array()
		var c: Vector2 = nodes[n]
		for ei in _adj[n]:
			var e: Dictionary = edges[ei]
			var other: Vector2 = nodes[e["b"] if e["a"] == n else e["a"]]
			var dir := (other - c).normalized()
			var hw := float(roads[e["road"]]["width"]) * 0.5
			var nrm := Vector2(-dir.y, dir.x) * hw
			var t := minf(trim[n], c.distance_to(other) * 0.45)
			hull.append_array([c + dir * t + nrm, c + dir * t - nrm, c + nrm, c - nrm])
		junctions.append({"center": c, "poly": Geometry2D.convex_hull(hull)})


## Bounded faces of the planar graph, shrunk to the kerb line.
func _faces() -> void:
	# Half-edges sorted by angle around each node.
	var out := []  # node -> Array[[angle, to, edge]]
	out.resize(nodes.size())
	for n in nodes.size():
		out[n] = []
	for ei in edges.size():
		var e: Dictionary = edges[ei]
		var a: int = e["a"]
		var b: int = e["b"]
		out[a].append([(nodes[b] - nodes[a]).angle(), b, ei])
		out[b].append([(nodes[a] - nodes[b]).angle(), a, ei])
	for n in nodes.size():
		(out[n] as Array).sort_custom(func(x, y): return x[0] < y[0])
	var used := {}
	for start in nodes.size():
		for h in out[start]:
			var key := "%d>%d" % [start, h[1]]
			if used.has(key):
				continue
			var poly := PackedVector2Array()
			var widths: Array = []
			var u := start
			var v: int = h[1]
			var ei: int = h[2]
			var guard := 0
			while guard < 400:
				guard += 1
				var k := "%d>%d" % [u, v]
				if used.has(k):
					break
				used[k] = true
				poly.append(nodes[u])
				widths.append(float(roads[edges[ei]["road"]]["width"]))
				# Next half-edge: the one just clockwise of the way back (keeps the face on the left).
				var around: Array = out[v]
				var back: float = (nodes[u] - nodes[v]).angle()
				var idx := 0
				for i in around.size():
					if absf(around[i][0] - back) < 1e-6 and around[i][1] == u:
						idx = i
						break
				var nxt: Array = around[(idx - 1 + around.size()) % around.size()]
				u = v
				v = nxt[1]
				ei = nxt[2]
				if u == start and v == h[1]:
					break
			if poly.size() < 3:
				continue
			var area := _signed_area(poly)
			# Bounded faces wind one way; the unbounded outer face the other.
			if area <= MIN_BLOCK_AREA:
				continue
			var inset := 0.0
			for w in widths:
				inset = maxf(inset, w * 0.5)
			var shrunk := Geometry2D.offset_polygon(poly, -inset, Geometry2D.JOIN_MITER)
			for sp in shrunk:
				if not Geometry2D.is_polygon_clockwise(sp) and absf(_signed_area(sp)) > MIN_BLOCK_AREA:
					blocks.append(sp)
				elif Geometry2D.is_polygon_clockwise(sp) and absf(_signed_area(sp)) > MIN_BLOCK_AREA:
					sp.reverse()
					blocks.append(sp)


static func _signed_area(p: PackedVector2Array) -> float:
	var a := 0.0
	for i in p.size():
		var q := p[(i + 1) % p.size()]
		a += p[i].x * q.y - q.x * p[i].y
	return a * 0.5

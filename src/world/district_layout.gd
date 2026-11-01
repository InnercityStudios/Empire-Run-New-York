class_name DistrictLayout
extends RefCounted
## Deterministic city layout derived from a district definition.
##
## Produces streets, intersections, blocks, building lots, landmark placements,
## street furniture spots, parking spots and the road network. Pure data: no
## nodes are created here, so the layout can be unit-tested and shared with a
## server that needs the same road graph.
##
## Axes: +X east, +Z south, +Y up. "Avenues" run north-south (constant x),
## "streets" run east-west (constant z).

const FACES := ["north", "south", "east", "west"]
const PRIMARY_FACES := ["north", "south"]
const CORNER_WIDTH := 12.0

var id: String
var display_name: String
var seed_value: int
var sidewalk: float
var curb_height: float
var corner_radius: float
var lot_depth: float
var lane_offset: float
var avenues: Array = []
var streets: Array = []
var bounds: Rect2
var blocks: Array = []           ## {col, row, rect: Rect2, core: bool, faces: {face: bool}}
var road_segments: Array = []    ## {street, from: Vector2, to: Vector2, width, style}
var intersections: Array = []    ## {rect: Rect2, center: Vector2, avenue, street}
var lots: Array = []             ## {building, block, transform: Transform3D, landmark: String}
var landmarks: Dictionary = {}   ## landmark id -> {building, transform, frontage: Vector2, out: Vector2, block}
var props: Array = []            ## {prop, block, transform}
var parking: Array = []          ## {transform}
var graph_nodes: Array = []      ## Vector2 positions
var graph_edges: Array = []      ## {a, b, street, width}

var _catalog: Dictionary
var _midblock_ids: Array = []


static func build(def: Dictionary, catalog: Dictionary) -> DistrictLayout:
	var l := DistrictLayout.new()
	l._build(def, catalog)
	return l


func _build(def: Dictionary, catalog: Dictionary) -> void:
	_catalog = catalog
	id = def.get("id", "")
	display_name = def.get("display_name", id)
	seed_value = int(def.get("seed", 1))
	sidewalk = def.get("sidewalk_width", 4.0)
	curb_height = def.get("curb_height", 0.15)
	corner_radius = def.get("corner_radius", 3.0)
	lot_depth = def.get("lot_depth", 20.0)
	lane_offset = def.get("lane_offset", 1.9)
	avenues = def.get("avenues", []).duplicate(true)
	streets = def.get("streets", []).duplicate(true)
	avenues.sort_custom(func(a, b): return a["x"] < b["x"])
	streets.sort_custom(func(a, b): return a["z"] < b["z"])
	var margin: float = def.get("edge_margin", 60.0)
	bounds = Rect2(Vector2(avenues[0]["x"] - margin, streets[0]["z"] - margin), Vector2.ZERO)
	bounds.end = Vector2(avenues[-1]["x"] + margin, streets[-1]["z"] + margin)
	for b in catalog.values():
		if b.get("kind") == "midblock":
			_midblock_ids.append(b["id"])
	_midblock_ids.sort()
	_build_roads()
	_build_blocks()
	_place_landmarks_and_lots(def.get("landmarks", []))


# --- Roads ---------------------------------------------------------------------
func _build_roads() -> void:
	var n := avenues.size()
	var m := streets.size()
	for a in avenues:
		for s in streets:
			var c := Vector2(a["x"], s["z"])
			var size := Vector2(a["width"], s["width"])
			intersections.append({"rect": Rect2(c - size * 0.5, size), "center": c, "avenue": a["id"], "street": s["id"]})
	# Graph nodes: intersections, then the map-edge ends of every road.
	for j in m:
		for i in n:
			graph_nodes.append(Vector2(avenues[i]["x"], streets[j]["z"]))
	var node_at := func(i: int, j: int) -> int: return j * n + i
	for i in n:
		var a: Dictionary = avenues[i]
		var north := _add_node(Vector2(a["x"], bounds.position.y))
		var south := _add_node(Vector2(a["x"], bounds.end.y))
		var chain := [north]
		for j in m:
			chain.append(node_at.call(i, j))
		chain.append(south)
		_add_chain(chain, a)
		var zs: Array = [bounds.position.y]
		for s in streets:
			zs.append(s["z"] - s["width"] * 0.5)
			zs.append(s["z"] + s["width"] * 0.5)
		zs.append(bounds.end.y)
		for k in range(0, zs.size(), 2):
			road_segments.append({"street": a["id"], "from": Vector2(a["x"], zs[k]), "to": Vector2(a["x"], zs[k + 1]),
				"width": a["width"], "style": a.get("style", 1)})
	for j in m:
		var s: Dictionary = streets[j]
		var west := _add_node(Vector2(bounds.position.x, s["z"]))
		var east := _add_node(Vector2(bounds.end.x, s["z"]))
		var chain := [west]
		for i in n:
			chain.append(node_at.call(i, j))
		chain.append(east)
		_add_chain(chain, s)
		var xs: Array = [bounds.position.x]
		for a in avenues:
			xs.append(a["x"] - a["width"] * 0.5)
			xs.append(a["x"] + a["width"] * 0.5)
		xs.append(bounds.end.x)
		for k in range(0, xs.size(), 2):
			road_segments.append({"street": s["id"], "from": Vector2(xs[k], s["z"]), "to": Vector2(xs[k + 1], s["z"]),
				"width": s["width"], "style": s.get("style", 1)})


func _add_node(p: Vector2) -> int:
	graph_nodes.append(p)
	return graph_nodes.size() - 1


func _add_chain(chain: Array, road: Dictionary) -> void:
	for k in chain.size() - 1:
		graph_edges.append({"a": chain[k], "b": chain[k + 1], "street": road["id"], "width": road["width"]})


func street_name(street_id: String) -> String:
	for r in avenues + streets:
		if r["id"] == street_id:
			return r["name"]
	return ""


# --- Blocks ----------------------------------------------------------------------
func _build_blocks() -> void:
	var n := avenues.size()
	var m := streets.size()
	for row in range(-1, m):
		for col in range(-1, n):
			var x0: float = bounds.position.x if col == -1 else avenues[col]["x"] + avenues[col]["width"] * 0.5
			var x1: float = bounds.end.x if col == n - 1 else avenues[col + 1]["x"] - avenues[col + 1]["width"] * 0.5
			var z0: float = bounds.position.y if row == -1 else streets[row]["z"] + streets[row]["width"] * 0.5
			var z1: float = bounds.end.y if row == m - 1 else streets[row + 1]["z"] - streets[row + 1]["width"] * 0.5
			blocks.append({
				"col": col, "row": row,
				"rect": Rect2(x0, z0, x1 - x0, z1 - z0),
				"core": col >= 0 and col < n - 1 and row >= 0 and row < m - 1,
				"faces": {"north": row >= 0, "south": row < m - 1, "west": col >= 0, "east": col < n - 1},
			})


func block_index(col: int, row: int) -> int:
	return (row + 1) * (avenues.size() + 1) + (col + 1)


## Face frame: origin is the left end of the building line as seen from the
## street, `right` runs along the face, `out` points to the street.
func face_frame(block: Dictionary, face: String) -> Dictionary:
	var b: Rect2 = block["rect"].grow(-sidewalk)
	match face:
		"south":
			return {"origin": Vector2(b.position.x, b.end.y), "right": Vector2(1, 0), "out": Vector2(0, 1), "length": b.size.x,
				"left": "west", "right_face": "east"}
		"north":
			return {"origin": Vector2(b.end.x, b.position.y), "right": Vector2(-1, 0), "out": Vector2(0, -1), "length": b.size.x,
				"left": "east", "right_face": "west"}
		"east":
			return {"origin": Vector2(b.end.x, b.end.y), "right": Vector2(0, -1), "out": Vector2(1, 0), "length": b.size.y,
				"left": "south", "right_face": "north"}
		_:
			return {"origin": Vector2(b.position.x, b.position.y), "right": Vector2(0, 1), "out": Vector2(-1, 0), "length": b.size.y,
				"left": "north", "right_face": "south"}


func lot_transform(frame: Dictionary, u: float, scale_x := 1.0) -> Transform3D:
	var r: Vector2 = frame["right"]
	var o: Vector2 = frame["out"]
	var p: Vector2 = frame["origin"] + r * u
	var basis := Basis(Vector3(r.x, 0, r.y) * scale_x, Vector3.UP, Vector3(o.x, 0, o.y))
	return Transform3D(basis, Vector3(p.x, curb_height, p.y))


# --- Lots, landmarks, props --------------------------------------------------------
func _place_landmarks_and_lots(landmark_defs: Array) -> void:
	var by_face := {}
	for lm in landmark_defs:
		var key := "%d,%d,%s" % [lm["block"][0], lm["block"][1], lm["face"]]
		by_face[key] = by_face.get(key, []) + [lm]
	for block in blocks:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([seed_value, block["col"], block["row"]])
		for face in FACES:
			if not block["faces"][face]:
				continue
			var frame := face_frame(block, face)
			var length: float = frame["length"]
			var primary: bool = face in PRIMARY_FACES
			var has_left: bool = block["faces"][frame["left"]]
			var has_right: bool = block["faces"][frame["right_face"]]
			var u0 := 0.0
			var u1 := length
			var bi := blocks.find(block)
			if primary:
				if has_left:
					_add_lot(_pick_corner("corner_left", rng), bi, lot_transform(frame, CORNER_WIDTH * 0.5), "")
					u0 = CORNER_WIDTH
				if has_right:
					_add_lot(_pick_corner("corner_right", rng), bi, lot_transform(frame, length - CORNER_WIDTH * 0.5), "")
					u1 = length - CORNER_WIDTH
			else:
				u0 = lot_depth if has_left else 0.0
				u1 = length - lot_depth if has_right else length
			var runs := [[u0, u1]]
			var key := "%d,%d,%s" % [block["col"], block["row"], face]
			for lm in by_face.get(key, []):
				var w: float = _catalog[lm["building"]]["width"]
				var uc: float = clampf(lerpf(u0, u1, lm.get("at", 0.5)), u0 + w * 0.5, u1 - w * 0.5)
				var t := lot_transform(frame, uc)
				_add_lot(lm["building"], bi, t, lm["id"])
				var o: Vector2 = frame["out"]
				var front := Vector2(t.origin.x, t.origin.z)
				var road_w := _street_width_for(block, face)
				landmarks[lm["id"]] = {
					"building": lm["building"], "transform": t, "block": bi, "face": face,
					"out": o, "frontage": front + o * (sidewalk + road_w * 0.5),
					"width": w, "depth": _catalog[lm["building"]].get("depth", lot_depth),
					"height": _catalog[lm["building"]].get("height", 15.0),
				}
				runs = _split_runs(runs, uc - w * 0.5, uc + w * 0.5)
			for run in runs:
				_fill_run(frame, bi, run[0], run[1], rng)
			_place_props(block, bi, face, frame, rng, by_face.get(key, []))


func _street_width_for(block: Dictionary, face: String) -> float:
	var col: int = block["col"]
	var row: int = block["row"]
	match face:
		"north":
			return streets[row]["width"]
		"south":
			return streets[row + 1]["width"]
		"west":
			return avenues[col]["width"]
		_:
			return avenues[col + 1]["width"]


func _split_runs(runs: Array, a: float, b: float) -> Array:
	var out := []
	for r in runs:
		if b <= r[0] or a >= r[1]:
			out.append(r)
			continue
		if a > r[0]:
			out.append([r[0], a])
		if b < r[1]:
			out.append([b, r[1]])
	return out


func _pick_corner(kind: String, rng: RandomNumberGenerator) -> String:
	var ids := []
	for b in _catalog.values():
		if b.get("kind") == kind:
			ids.append(b["id"])
	ids.sort()
	return ids[rng.randi() % ids.size()]


func _fill_run(frame: Dictionary, bi: int, u0: float, u1: float, rng: RandomNumberGenerator) -> void:
	var length := u1 - u0
	if length < 6.0 or _midblock_ids.is_empty():
		return
	var chosen := []
	var total := 0.0
	var last := ""
	var guard := 0
	while guard < 64:
		guard += 1
		var candidates := _midblock_ids.filter(func(i): return i != last and total + _catalog[i]["width"] <= length + 0.01)
		if candidates.is_empty():
			break
		var pick: String = candidates[rng.randi() % candidates.size()]
		chosen.append(pick)
		total += _catalog[pick]["width"]
		last = pick
	if chosen.is_empty():
		return
	# Stretch lots slightly so the run is filled edge to edge.
	var s := length / total
	var u := u0
	for pick in chosen:
		var w: float = _catalog[pick]["width"] * s
		_add_lot(pick, bi, lot_transform(frame, u + w * 0.5, s), "")
		u += w


func _add_lot(building: String, bi: int, t: Transform3D, landmark_id: String) -> void:
	lots.append({"building": building, "block": bi, "transform": t, "landmark": landmark_id})


func _prop_transform(frame: Dictionary, u: float, inset: float, yaw_right := false) -> Transform3D:
	var r: Vector2 = frame["right"]
	var o: Vector2 = frame["out"]
	var p: Vector2 = frame["origin"] + r * u + o * (sidewalk - inset)
	var fwd := Vector3(o.x, 0, o.y)
	var right := Vector3(r.x, 0, r.y)
	var basis := Basis(right, Vector3.UP, fwd) if not yaw_right else Basis(-fwd, Vector3.UP, right)
	return Transform3D(basis, Vector3(p.x, curb_height, p.y))


func _place_props(block: Dictionary, bi: int, face: String, frame: Dictionary, rng: RandomNumberGenerator,
		face_landmarks: Array) -> void:
	var length: float = frame["length"]
	var blocked := []  # u ranges kept clear (landmark frontages)
	for lm in face_landmarks:
		var info: Dictionary = landmarks[lm["id"]]
		var t: Transform3D = info["transform"]
		var r: Vector2 = frame["right"]
		var uc: float = (Vector2(t.origin.x, t.origin.z) - frame["origin"]).dot(r)
		blocked.append([uc - info["width"] * 0.5 - 1.0, uc + info["width"] * 0.5 + 1.0])
	var is_clear := func(u: float) -> bool:
		for b in blocked:
			if u > b[0] and u < b[1]:
				return false
		return true
	var used := []
	var lamp_u := 7.0
	while lamp_u < length - 4.0:
		if is_clear.call(lamp_u):
			props.append({"prop": "street_lamp", "block": bi, "transform": _prop_transform(frame, lamp_u, 0.55)})
			used.append(lamp_u)
		lamp_u += 26.0
	var tree_u := 5.0 + rng.randf() * 4.0
	while tree_u < length - 5.0:
		var near := used.any(func(x): return absf(x - tree_u) < 3.5)
		if not near and rng.randf() < 0.62:
			var t := _prop_transform(frame, tree_u, 1.1)
			t.basis = t.basis.rotated(Vector3.UP, rng.randf() * TAU)
			props.append({"prop": "tree_a" if rng.randf() < 0.5 else "tree_b", "block": bi, "transform": t})
			used.append(tree_u)
		tree_u += 9.0 + rng.randf() * 4.0
	var hydrant_u := 6.0 if rng.randf() < 0.5 else length - 6.0
	props.append({"prop": "fire_hydrant", "block": bi, "transform": _prop_transform(frame, hydrant_u, 0.5)})
	used.append(hydrant_u)
	if face in PRIMARY_FACES:
		props.append({"prop": "trash_can", "block": bi, "transform": _prop_transform(frame, 2.8, 0.6)})
		props.append({"prop": "trash_can", "block": bi, "transform": _prop_transform(frame, length - 2.8, 0.6)})
	if rng.randf() < 0.45:
		var mu := 10.0 if rng.randf() < 0.5 else length - 10.0
		if is_clear.call(mu):
			props.append({"prop": "mailbox", "block": bi, "transform": _prop_transform(frame, mu, 0.6, true)})
	if rng.randf() < 0.4:
		var nu := 12.0 + rng.randf() * (length - 24.0)
		if is_clear.call(nu):
			props.append({"prop": "newspaper_box", "block": bi, "transform": _prop_transform(frame, nu, 0.6, true)})
	# Traffic signal at the left corner of each face that meets another street.
	if block["faces"][frame["left"]]:
		var t := _prop_transform(frame, -sidewalk + 1.4, 1.4)
		props.append({"prop": "traffic_signal", "block": bi, "transform": t})
	# Kerbside parking, kept clear of landmark frontages and hydrants.
	var pu := 9.0
	while pu < length - 9.0:
		var ok: bool = is_clear.call(pu) and absf(pu - hydrant_u) > 3.0
		if ok and rng.randf() < 0.42:
			var r: Vector2 = frame["right"]
			var o: Vector2 = frame["out"]
			var p: Vector2 = frame["origin"] + r * pu + o * (sidewalk + 1.2)
			var fwd := -Vector3(r.x, 0, r.y)
			# Vehicles face -Z: local Z = -forward, X = Y x Z.
			var basis := Basis(fwd.cross(Vector3.UP), Vector3.UP, -fwd)
			parking.append({"transform": Transform3D(basis, Vector3(p.x, 0.0, p.y))})
		pu += 6.4 + rng.randf() * 1.5

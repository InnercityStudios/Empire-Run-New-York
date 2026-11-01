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
## Fill style (opt-in; Little Italy uses the defaults, which keeps its layout
## bit-identical). See STYLES.
var style := "tenement"
var _style: Dictionary = {}
var _boundary_streets: Dictionary = {}
var _lot_counter := 0
var boundary_width := 20.0

## Neighbourhood fill styles: which building kinds fill block faces, whether
## street corners get corner buildings, building setback and gaps (metres),
## street-tree probability and whether blocks get raised sidewalks.
const STYLES := {
	"tenement": {"kinds": ["midblock"], "corners": true, "setback": 0.0, "gap": [0.0, 0.0], "tree_chance": 0.62,
		"sidewalks": true, "props": true},
	"industrial": {"kinds": ["industrial"], "corners": false, "setback": 0.0, "gap": [2.0, 10.0], "tree_chance": 0.12,
		"sidewalks": true, "props": true},
	"rowhouse": {"kinds": ["rowhouse"], "corners": false, "setback": 0.0, "gap": [0.0, 0.0], "tree_chance": 0.85,
		"sidewalks": true, "props": true, "primary_only": true},
	"suburban": {"kinds": ["house"], "corners": false, "setback": 7.0, "gap": [5.0, 11.0], "tree_chance": 0.9,
		"sidewalks": true, "props": true, "lawns": true},
	"towers": {"kinds": ["midblock_tall"], "corners": false, "setback": 12.0, "gap": [22.0, 40.0], "tree_chance": 0.9,
		"sidewalks": true, "props": true, "lawns": true},
	"waterfront": {"kinds": ["industrial"], "corners": false, "setback": 0.0, "gap": [6.0, 18.0], "tree_chance": 0.0,
		"sidewalks": true, "props": true},
	"civic": {"kinds": ["midblock_tall", "midblock_low", "midblock"], "corners": false, "setback": 3.0,
		"gap": [4.0, 16.0], "tree_chance": 0.75, "sidewalks": true, "props": true},
	"park": {"kinds": [], "corners": false, "setback": 0.0, "gap": [0.0, 0.0], "tree_chance": 0.0,
		"sidewalks": false, "props": false},
}


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
	if def.has("bounds"):
		var bb: Array = def["bounds"]
		bounds = Rect2(Vector2(bb[0], bb[1]), Vector2(bb[2] - bb[0], bb[3] - bb[1]))
	else:
		var margin: float = def.get("edge_margin", 60.0)
		bounds = Rect2(Vector2(avenues[0]["x"] - margin, streets[0]["z"] - margin), Vector2.ZERO)
		bounds.end = Vector2(avenues[-1]["x"] + margin, streets[-1]["z"] + margin)
	style = def.get("style", "tenement")
	_style = STYLES.get(style, STYLES["tenement"]).duplicate()
	_style.merge(def.get("style_overrides", {}), true)
	_boundary_streets = def.get("boundary_streets", {})
	boundary_width = def.get("boundary_width", 20.0)
	var kinds: Array = _style["kinds"] + def.get("extra_kinds", [])
	for b in catalog.values():
		if b.get("kind") in kinds:
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
		graph_edges.append({"a": chain[k], "b": chain[k + 1], "street": road["id"], "width": road["width"],
			"speed": road.get("speed", 1000)})


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
				"faces": {
					"north": row >= 0 or bool(_boundary_streets.get("north", false)),
					"south": row < m - 1 or bool(_boundary_streets.get("south", false)),
					"west": col >= 0 or bool(_boundary_streets.get("west", false)),
					"east": col < n - 1 or bool(_boundary_streets.get("east", false)),
				},
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
			if primary and _style["corners"]:
				if has_left:
					_add_lot(_pick_corner("corner_left", rng), bi, lot_transform(frame, CORNER_WIDTH * 0.5), "")
					u0 = CORNER_WIDTH
				if has_right:
					_add_lot(_pick_corner("corner_right", rng), bi, lot_transform(frame, length - CORNER_WIDTH * 0.5), "")
					u1 = length - CORNER_WIDTH
			elif not primary:
				u0 = lot_depth if has_left else 0.0
				u1 = length - lot_depth if has_right else length
			if not primary and _style.get("primary_only", false):
				u1 = u0  # side streets show rear gardens and blank party walls
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
			if _style["props"]:
				_place_props(block, bi, face, frame, rng, by_face.get(key, []))


func _street_width_for(block: Dictionary, face: String) -> float:
	var col: int = block["col"]
	var row: int = block["row"]
	# Faces on the district boundary front a road owned by the world (an arterial).
	match face:
		"north":
			return streets[row]["width"] if row >= 0 else boundary_width
		"south":
			return streets[row + 1]["width"] if row + 1 < streets.size() else boundary_width
		"west":
			return avenues[col]["width"] if col >= 0 else boundary_width
		_:
			return avenues[col + 1]["width"] if col + 1 < avenues.size() else boundary_width


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
	var gap: Array = _style["gap"]
	if float(gap[1]) > 0.0:
		_fill_run_spaced(frame, bi, u0, u1, rng)
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


## Detached and industrial styles: buildings with gaps (yards, lawns,
## driveways), set back from the building line, never stretched.
func _fill_run_spaced(frame: Dictionary, bi: int, u0: float, u1: float, rng: RandomNumberGenerator) -> void:
	var gap: Array = _style["gap"]
	var setback: float = _style["setback"]
	var u := u0 + rng.randf_range(float(gap[0]), float(gap[1])) * 0.5
	var last := ""
	var guard := 0
	while guard < 64:
		guard += 1
		var candidates := _midblock_ids.filter(func(i): return i != last and u + float(_catalog[i]["width"]) <= u1)
		if candidates.is_empty():
			break
		var pick: String = candidates[rng.randi() % candidates.size()]
		var w: float = _catalog[pick]["width"]
		var t := lot_transform(frame, u + w * 0.5)
		var o: Vector2 = frame["out"]
		t.origin -= Vector3(o.x, 0, o.y) * setback
		_add_lot(pick, bi, t, "")
		u += w + rng.randf_range(float(gap[0]), float(gap[1]))
		last = pick


func _add_lot(building: String, bi: int, t: Transform3D, landmark_id: String) -> void:
	# Stable identity: district id + generation order (deterministic).
	lots.append({"id": "%s:%d" % [id, _lot_counter], "building": building, "block": bi, "transform": t,
		"landmark": landmark_id})
	_lot_counter += 1


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
		if not near and rng.randf() < float(_style["tree_chance"]):
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
	_place_furniture(block, bi, face, frame, is_clear, used)
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


## Second-generation street furniture. Uses its own RNG stream so adding
## furniture never changes the deterministic lot and prop sequence above.
func _place_furniture(block: Dictionary, bi: int, face: String, frame: Dictionary, is_clear: Callable,
		used: Array) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, block["col"], block["row"], face, "furniture"])
	var length: float = frame["length"]
	var avenue_face := face == "east" or face == "west"
	var free := func(u: float, gap: float) -> bool:
		return is_clear.call(u) and not used.any(func(x): return absf(x - u) < gap)
	var put := func(prop: String, u: float, inset: float, rotate := false) -> void:
		props.append({"prop": prop, "block": bi, "transform": _prop_transform(frame, u, inset, rotate)})
		used.append(u)
	# Subway entrance on some avenue corners (stairs run along the kerb).
	if avenue_face and block["core"] and rng.randf() < 0.3:
		var u := 9.0 if rng.randf() < 0.5 else length - 9.0
		if free.call(u, 4.0):
			put.call("subway_entrance", u, 2.2, true)
	# Bus stop on wide streets.
	if _street_width_for(block, face) >= 14.0 and rng.randf() < 0.5:
		var u := length * (0.3 + rng.randf() * 0.4)
		if free.call(u, 3.5):
			put.call("bus_stop", u, 1.2)
	if rng.randf() < 0.35:
		var u := 4.5 if rng.randf() < 0.5 else length - 4.5
		if free.call(u, 1.5):
			put.call("phone_booth", u, 0.7)
	if block["core"] and rng.randf() < 0.18:
		var u := 6.0 + rng.randf() * (length - 12.0)
		if free.call(u, 3.5):
			put.call("newsstand", u, 1.6)
	# Garbage piled at the building line (the 1970s sanitation crisis).
	var piles := rng.randi_range(0, 2)
	for i in piles:
		var u := 3.0 + rng.randf() * (length - 6.0)
		if free.call(u, 1.5):
			props.append({"prop": "trash_pile", "block": bi, "transform": _prop_transform(frame, u, sidewalk - 0.6)})
	# Parking meters along the kerb.
	var mu := 6.0
	while mu < length - 6.0:
		if free.call(mu, 1.0) and rng.randf() < 0.7:
			props.append({"prop": "parking_meter", "block": bi, "transform": _prop_transform(frame, mu, 0.45)})
		mu += 6.5
